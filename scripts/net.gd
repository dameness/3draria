extends Node
# Rede (docs/MULTIPLAYER.md): todos os RPCs moram aqui, no nó "Net" filho da raiz da cena (game.tscn no cliente, server.tscn no servidor).
# Cada cena prende o próprio SceneMultiplayer na sua raiz, então o caminho do RPC ("Net") é o mesmo dos dois lados e servidor e clientes
# cabem no mesmo processo (tests/net.gd). Quem manda: o servidor nos blocos, líquidos, mudas, espalhamento e hora; o cliente no próprio
# personagem e no dano que causa. Blocos passam pelo funil world.set_block → block_changed (um lote por quadro).
# M4a: inimigos só no servidor (o cliente vê bonecos: enemy.puppet; o golpe vira `hit`, o dano no jogador vem por `hurt`).
# O servidor ainda não salva (M5).

enum { OFF, SERVER, CLIENT }
const PORT := 8070
const RATE := 1.0 / 15         # estado dos jogadores (15 Hz)
const CHUNKS_PER_FRAME := 6    # vazão da entrada (~1 KB cada): ~360 chunks/s a 60 fps
const BUFFER := 1 << 22        # 4 MB por conexão (o padrão de 64 KB não comporta a entrada)
const NEAR := 192.0            # raio de interesse do estado dos outros (blocos)
const FOE_RATE := 0.1          # estado dos inimigos (10 Hz)
const FOE_NEAR := 96.0         # raio de interesse dos inimigos (inimigo some a 64 do jogador mais perto)
const FOE_LOST := 1500         # ms sem estado: o boneco do inimigo sai (saiu do raio)
const RemotePlayer := preload("res://scripts/remote_player.gd")

static var join := ""          # menu → jogo: endereço do servidor (a cena lê e limpa)

@export var world: Node3D
@export var player: Node3D     # cliente: o jogador local (servidor: nenhum)
@export var entities: Node3D
@export var clock: Node

var mode := OFF
var address := ""              # cliente: ws://host:porta
var nick := ""                 # cliente: nome mostrado aos outros (padrão: o do personagem)
var version := ""
var spawn := Vector3.ZERO      # servidor: nascimento do mundo (SaveGame.world_out/world_in leem `player.spawn`)
var peers := {}                # servidor: id -> {name, look, equip, state, view, center, sent: {chunk: true}, queue: [chunk] (o mais perto no fim)}
var puppets := {}              # cliente: id -> remote_player
var out: Array = []            # blocos mudados neste quadro: [x, y, z, id, autor]
var from := 0                  # servidor: autor do lote sendo aplicado (0 = o próprio servidor)
var applying := false          # cliente: aplicando o lote do servidor (não reenviar)
var waiting := false           # cliente: espera o welcome e os chunks em volta (jogador parado)
var welcomed := false
var tick := 0.0
var clock_tick := 0.0
var worn := PackedInt32Array()
var foes := {}                 # id -> inimigo (servidor: todos; cliente: os bonecos)
var gone := {}                 # cliente: ids de inimigos que já saíram (um estado atrasado não os traz de volta)
var next_id := 0
var drops := {}                # id -> item_drop (servidor: os de verdade; cliente: as cópias)
var drops_out: Array = []      # nascidos neste quadro (cliente: a pedir ao servidor; servidor: a anunciar)
var foe_tick := 0.0


func _ready() -> void:
	version = _version()
	if address == "" and join != "":
		address = join
		join = ""
	if address != "":
		connect_to(address)


static func _version() -> String:   # hash do git gravado pelo scripts/update.sh (sem ele: "dev")
	var f := FileAccess.open("res://version.json", FileAccess.READ)
	return str(JSON.parse_string(f.get_as_text()).get("git", "dev")) if f else "dev"


func _attach(peer: WebSocketMultiplayerPeer) -> void:
	peer.outbound_buffer_size = BUFFER
	peer.inbound_buffer_size = BUFFER
	var api := SceneMultiplayer.new()
	api.multiplayer_peer = peer
	get_tree().set_multiplayer(api, get_parent().get_path())
	world.net = self
	entities.net = self


func _exit_tree() -> void:
	if mode != OFF:
		multiplayer.multiplayer_peer.close()
		get_tree().set_multiplayer(null, get_parent().get_path())


func host(port := PORT) -> Error:
	var peer := WebSocketMultiplayerPeer.new()
	var err := peer.create_server(port)
	if err != OK:
		return err
	mode = SERVER
	_attach(peer)
	multiplayer.peer_disconnected.connect(_gone)
	return OK


func connect_to(addr: String) -> void:
	mode = CLIENT
	world.authority = false
	world.render_distance = Settings.render_distance
	waiting = true
	_freeze(true)
	var peer := WebSocketMultiplayerPeer.new()
	if peer.create_client(addr) != OK:
		_lost("endereço inválido: " + addr)
		return
	_attach(peer)
	if nick == "":
		nick = SaveGame.player_path.get_file().get_basename() if SaveGame.player_path != "" else "jogador"
	multiplayer.connected_to_server.connect(func(): hello.rpc_id(1, version, nick, SaveGame.look(SaveGame.player_path) if SaveGame.player_path != "" else {}))
	multiplayer.connection_failed.connect(_lost.bind("não conectou a " + addr))
	multiplayer.server_disconnected.connect(_lost.bind("conexão perdida"))
	player.say("conectando a " + addr)


func _freeze(on: bool) -> void:   # cliente esperando o mundo: jogador e inimigos parados
	var m := Node.PROCESS_MODE_DISABLED if on else Node.PROCESS_MODE_INHERIT
	player.process_mode = m
	if entities:
		entities.process_mode = m


func _lost(why: String) -> void:
	player.say(why)
	player.message_until = Time.get_ticks_msec() + 3600 * 1000   # fica na tela
	waiting = false


# ---------- funil dos blocos ----------

func block_changed(x: int, y: int, z: int, id: int) -> void:
	if not applying:
		out.append([x, y, z, id, from])


func _flush_blocks() -> void:
	if out.is_empty():
		return
	if mode == CLIENT:
		var a := PackedInt32Array()
		for b in out:
			a.append_array([b[0], b[1], b[2], b[3]])
		blocks.rpc_id(1, a)
	else:
		for id in peers:
			var a := PackedInt32Array()
			for b in out:
				if b[4] != id and peers[id].sent.has(_chunk_of(b[0], b[2])):   # quem não tem o chunk recebe a edição junto com ele
					a.append_array([b[0], b[1], b[2], b[3]])
			if not a.is_empty():
				blocks.rpc_id(id, a)
	out.clear()


static func _chunk_of(x: float, z: float) -> Vector2i:
	return Vector2i(floori(x / WorldGen.CHUNK), floori(z / WorldGen.CHUNK))


# ---------- funil dos inimigos (entities.spawn_enemy / remove_enemy, enemy.hurt) ----------

func enemy_born(e: Node3D) -> void:
	if mode == SERVER:
		next_id += 1
		e.net_id = next_id
		foes[next_id] = e


func enemy_gone(e: Node3D) -> void:
	if not foes.has(e.net_id):
		return
	foes.erase(e.net_id)
	if mode == SERVER:
		for id in peers:
			foe_gone.rpc_id(id, e.net_id, e.hp <= 0)


func enemy_hurt(e: Node3D, taken: int, crit: bool, dot: bool, dir: Vector3) -> void:
	if mode == SERVER and e.net_id:
		for id in _near(e.position, FOE_NEAR):
			foe_hurt.rpc_id(id, e.net_id, taken, e.hp, crit, dot, dir)


func _near(pos: Vector3, r: float) -> Array:   # servidor: os jogadores a até r de pos
	return peers.keys().filter(func(id): return not peers[id].state.is_empty() and peers[id].state[0].distance_to(pos) < r)


# ---------- funil dos itens no chão (entities.spawn_drop, item_drop._exit_tree) ----------

func drop_born(d: Node3D) -> void:
	if mode == SERVER:
		next_id += 1
		d.net_id = next_id
		drops[next_id] = d
		drops_out.append(d)


func drop_freed(d: Node3D) -> void:
	drops.erase(d.net_id)
	if mode == SERVER:
		for id in peers:
			drop_gone.rpc_id(id, d.net_id)


func _flush_drops() -> void:   # (no fim do quadro: quem chamou spawn_drop já pôs a velocidade e a espera)
	for d in drops_out:
		if mode == CLIENT:
			drop.rpc_id(1, d.item, d.count, d.position, d.velocity, d.delay)
			d.free()
		elif is_instance_valid(d) and not d.is_queued_for_deletion():
			for id in peers:
				_announce(id, d)
	drops_out.clear()


func _announce(id: int, d: Node3D) -> void:
	drop_new.rpc_id(id, d.net_id, d.item, d.count, d.position, d.velocity, d.delay)


# ---------- RPCs ----------

@rpc("any_peer", "reliable")
func hello(ver: String, who: String, look: Dictionary) -> void:
	var id := multiplayer.get_remote_sender_id()
	if mode != SERVER:
		return
	if ver != version:
		refuse.rpc_id(id, "versão diferente do servidor: atualize a página")
		return
	if peers.values().any(func(p): return p.name == who):
		refuse.rpc_id(id, "já há alguém com o nome " + who)
		return
	var body: Node3D = RemotePlayer.new()   # o alvo dos inimigos no servidor (sem modelo)
	body.entities = entities
	body.peer = id
	body.name = "Body%d" % id
	body.position = spawn
	get_parent().add_child(body)
	entities.remotes.append(body)
	peers[id] = {"name": who, "look": look, "equip": [], "state": [], "view": 6, "center": Vector2i(-999, -999), "sent": {}, "queue": [], "body": body}
	_requeue(id, spawn)
	var data := SaveGame.world_out(world, self, clock, "servidor")
	data.chunks = {}   # os chunks vão aos poucos (_send_chunks); o mapa explorado é por jogador (M5)
	data.erase("map")
	welcome.rpc_id(id, data)
	for k in drops:
		_announce(id, drops[k])
	for o in peers:
		if o != id:
			joined.rpc_id(id, o, peers[o].name, peers[o].look, peers[o].equip)
			joined.rpc_id(o, id, who, look, [])


@rpc("authority", "reliable")
func refuse(why: String) -> void:
	_lost(why)
	multiplayer.multiplayer_peer.close.call_deferred()   # (fechar dentro do próprio RPC dá erro no poll)


@rpc("authority", "reliable")
func welcome(data: Dictionary) -> void:
	SaveGame.world_in(world, player, clock, data)
	welcomed = true
	player.position = Vector3(player.bed) + Vector3(0.5, 0, 0.5) if player.bed != Vector3i.MAX else player.spawn   # home() só depois dos chunks (sem eles a cama "sumiria")
	_send_state()


@rpc("authority", "reliable")
func chunks(list: Array) -> void:
	for e in list:
		world.receive(e[0], e[1])


@rpc("any_peer", "reliable")
func blocks(a: PackedInt32Array) -> void:
	var id := multiplayer.get_remote_sender_id()
	if mode == SERVER:
		if not peers.has(id):
			return
		from = id
		for i in range(0, a.size(), 4):
			world.set_block(a[i], a[i + 1], a[i + 2], a[i + 3])
		from = 0
	elif id == 1:
		applying = true
		for i in range(0, a.size(), 4):
			world.set_block(a[i], a[i + 1], a[i + 2], a[i + 3])
		applying = false


# s = [posição, yaw, pitch, velocidade, flags (1 chão, 2 nadando, 4 morto, 8 fantasma), item na mão, cooldown, vida, vida máx., mana, mana máx.]
@rpc("any_peer", "unreliable_ordered")
func state(s: Array, view: int) -> void:
	var id := multiplayer.get_remote_sender_id()
	if mode != SERVER or not peers.has(id):
		return
	peers[id].state = s
	var b: Node3D = peers[id].body
	_pose(b, s)
	b.position = s[0]
	b.rotation.y = s[1]
	b.hp = s[7]
	b.max_hp = s[8]
	b.mana = s[9]
	b.mana_max = s[10]
	peers[id].view = clampi(view, 2, 16)
	_requeue(id, s[0])


@rpc("authority", "unreliable_ordered")
func states(list: Array) -> void:
	for s in list:
		var r: Node3D = puppets.get(s[0])
		if r == null:
			continue
		if not r.visible:
			r.position = s[1]
			r.visible = true
		r.set_meta("goal", s[1])
		r.set_meta("yaw", s[2])
		r.set_meta("seen", Time.get_ticks_msec())
		_pose(r, s.slice(1))


func _pose(r: Node3D, s: Array) -> void:
	r.pitch = s[2]
	r.velocity = s[3]
	r.on_floor = s[4] & 1 != 0
	r.swimming = s[4] & 2 != 0
	r.dead = 1.0 if s[4] & 4 else 0.0
	r.ghost = s[4] & 8 != 0
	r.hand = s[5]
	r.cooldown = s[6]


@rpc("authority", "reliable")
func joined(id: int, who: String, look: Dictionary, worn_names: Array) -> void:
	var r: Node3D = RemotePlayer.new()
	r.entities = entities
	r.name = "Remote%d" % id
	r.visible = false   # até o primeiro estado
	get_parent().add_child(r)
	if not look.is_empty():
		r.model.restyle(look)
	var tag := Label3D.new()
	tag.text = who
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.position.y = 2.2
	tag.outline_size = 8
	tag.font_size = 40
	tag.pixel_size = 0.006
	tag.no_depth_test = true
	r.add_child(tag)
	puppets[id] = r
	_wear(r, worn_names)


@rpc("authority", "reliable")
func left(id: int) -> void:
	if puppets.has(id):
		puppets[id].queue_free()
		puppets.erase(id)


@rpc("any_peer", "reliable")
func equip(id: int, worn_names: Array) -> void:
	if mode == SERVER:
		id = multiplayer.get_remote_sender_id()
		if not peers.has(id):
			return
		peers[id].equip = worn_names
		_wear(peers[id].body, worn_names)   # a defesa do alvo no servidor
		for o in peers:
			if o != id:
				equip.rpc_id(o, id, worn_names)
	elif puppets.has(id):
		_wear(puppets[id], worn_names)


# Um inimigo do servidor feriu o jogador deste cliente (RemotePlayer.hurt lá): a defesa, a invencibilidade e a vida são daqui.
@rpc("authority", "reliable")
func hurt(damage: int, dir: Vector3, bounce: bool) -> void:
	player.hurt(damage, dir, bounce)


@rpc("authority", "unreliable_ordered")
func time_of_day(time: float, speed: float) -> void:
	clock.time = time
	clock.speed = speed


func _wear(r: Node3D, worn_names: Array) -> void:
	for i in mini(worn_names.size(), r.inv.equip.size()):
		r.inv.equip[i] = Items.ids.get(worn_names[i], -1)


# Inimigos perto do jogador, 10 Hz: [id, nome do def, posição, yaw, vida, bits (1 investida, 2 fase 2, 4 envenenado, 8 em chamas)].
@rpc("authority", "unreliable_ordered")
func foe_states(list: Array) -> void:
	var now := Time.get_ticks_msec()
	for f in list:
		if gone.has(f[0]):
			continue
		var e: Node3D = foes.get(f[0])
		if e == null:
			e = entities.spawn_enemy(entities.def_named(f[1]), f[2])
			e.puppet = true
			e.net_id = f[0]
			e.rotation.y = f[3]
			foes[f[0]] = e
		elif e.def.name != f[1]:
			e.become(entities.def_named(f[1]))   # verme: o segmento virou cabeça/rabo
		e.net_pos = f[2]
		e.net_yaw = f[3]
		e.hp = f[4]
		e.seen = now
		e.mode = "dash" if f[5] & 1 else "hover"
		var ph := 2 if f[5] & 2 else 1
		if ph != e.phase:
			e.phase = ph
			if e.model:
				EnemyModel.set_phase(e.model, ph)
			if e.def.ai == "brain":
				e.set_ghost(ph == 1)
		e.debuffs.clear()
		if f[5] & 4:
			e.debuffs.poisoned = 1.0
		if f[5] & 8:
			e.debuffs.on_fire = 1.0


@rpc("authority", "reliable")
func foe_hurt(id: int, taken: int, hp: int, crit: bool, dot: bool, dir: Vector3) -> void:
	var e: Node3D = foes.get(id)
	if e:
		e.hp = hp
		e.show_hit(taken, crit, dot, dir)


@rpc("authority", "reliable")
func foe_gone(id: int, died: bool) -> void:
	gone[id] = true
	var e: Node3D = foes.get(id)
	if e:
		if died:
			e.show_death()
		entities.remove_enemy(e)


# O cliente acertou um inimigo (calculou como em um jogador: variância, crítico, recuo); o servidor aplica a defesa e o resto.
@rpc("any_peer", "reliable")
func hit(id: int, dmg: int, dir: Vector3, knockback: float, crit: bool) -> void:
	var e: Node3D = foes.get(id)
	if mode == SERVER and peers.has(multiplayer.get_remote_sender_id()) and is_instance_valid(e):
		e.hurt(dmg, dir, knockback, crit)


@rpc("any_peer", "reliable")
func curse(id: int, buff: String, seconds: float) -> void:
	var e: Node3D = foes.get(id)
	if mode == SERVER and peers.has(multiplayer.get_remote_sender_id()) and is_instance_valid(e) and Buffs.defs.has(buff):
		e.afflict(buff, seconds)


# Cliente soltou um item (quebrou bloco, jogou, morreu...): nasce aqui e vai a todos.
@rpc("any_peer", "reliable")
func drop(item: int, count: int, pos: Vector3, vel: Vector3, delay: float) -> void:
	if mode == SERVER and peers.has(multiplayer.get_remote_sender_id()) and item >= 0 and item < Items.defs.size() and count > 0:
		var d: Node3D = entities.spawn_drop(item, count, pos)
		d.velocity = vel
		d.delay = delay


@rpc("authority", "reliable")
func drop_new(id: int, item: int, count: int, pos: Vector3, vel: Vector3, delay: float) -> void:
	var d: Node3D = entities.ItemDrop.new()
	d.item = item
	d.count = count
	d.entities = entities
	d.position = pos
	d.velocity = vel
	d.delay = delay
	d.net_id = id
	drops[id] = d
	entities.add_child(d)


@rpc("authority", "reliable")
func drop_gone(id: int) -> void:
	if drops.has(id):
		drops[id].queue_free()


# Pedido de pegar um item: o primeiro leva (o item sai na hora; um segundo pedido no mesmo quadro já o acha saindo).
@rpc("any_peer", "reliable")
func grab(id: int) -> void:
	var d: Node3D = drops.get(id)
	if mode == SERVER and peers.has(multiplayer.get_remote_sender_id()) and is_instance_valid(d) and not d.is_queued_for_deletion():
		give.rpc_id(multiplayer.get_remote_sender_id(), d.item, d.count)
		d.queue_free()


@rpc("authority", "reliable")
func give(item: int, count: int) -> void:
	var pk: Dictionary = Items.defs[item].get("pickup", {})
	if not pk.is_empty():   # coração / estrela: curam na hora
		player.pickup(pk)
		Sfx.play(entities, "pickup", player.position + Vector3.UP, -8.0)
		return
	var left: int = player.inv.add(item, count)
	Sfx.play(entities, "coin" if Inventory.coin_kind(item) != -1 else "pickup", player.position + Vector3.UP, -8.0)
	if left > 0:   # não coube (o inventário mudou enquanto o pedido ia): volta ao chão
		entities.spawn_drop(item, left, player.position + Vector3.UP)


# ---------- servidor ----------

func _gone(id: int) -> void:
	if peers.has(id):
		entities.remotes.erase(peers[id].body)
		peers[id].body.queue_free()
	peers.erase(id)
	for o in peers:
		left.rpc_id(o, id)


# Fila de chunks do jogador: os do raio de visão (+1, os vizinhos que a malha pede) que ele ainda não tem, o mais perto no fim.
func _requeue(id: int, pos: Vector3) -> void:
	var p: Dictionary = peers[id]
	var c := _chunk_of(pos.x, pos.z)
	if c == p.center and p.get("view_q", -1) == p.view:
		return
	p.center = c
	p.view_q = p.view
	var r: int = p.view + 1
	var q: Array = []
	for z in range(c.y - r, c.y + r + 1):
		for x in range(c.x - r, c.x + r + 1):
			var k := Vector2i(x, z)
			if world.in_world(k) and not p.sent.has(k) and (k - c).length_squared() <= r * r:
				q.append(k)
	q.sort_custom(func(a, b): return (a - c).length_squared() > (b - c).length_squared())
	p.queue = q


func _send_chunks() -> void:
	for id in peers:
		var q: Array = peers[id].queue
		var list := []
		while not q.is_empty() and list.size() < CHUNKS_PER_FRAME:
			var k: Vector2i = q.pop_back()
			var bytes: PackedByteArray
			if world.chunks.has(k):
				bytes = world.chunks[k].compress(FileAccess.COMPRESSION_ZSTD)
			elif world.packed.has(k):
				bytes = world.packed[k]
			else:
				bytes = world.unpack(k).compress(FileAccess.COMPRESSION_ZSTD)   # mundo sem assar (testes): o gerador
			list.append([k, bytes])
			peers[id].sent[k] = true
		if not list.is_empty():
			chunks.rpc_id(id, list)


func _send_states() -> void:
	for id in peers:
		var me: Array = peers[id].state
		var list := []
		for o in peers:
			var s: Array = peers[o].state
			if o != id and not s.is_empty() and (me.is_empty() or s[0].distance_to(me[0]) < NEAR):
				list.append([o] + s)
		if not list.is_empty():
			states.rpc_id(id, list)
	if clock_tick <= 0.0:
		clock_tick = 1.0
		for id in peers:
			time_of_day.rpc_id(id, clock.time, clock.speed)


func _send_foes() -> void:
	if foe_tick <= 0.0:
		foe_tick = FOE_RATE
		for id in peers:
			if peers[id].state.is_empty():
				continue
			var at: Vector3 = peers[id].state[0]
			var list := []
			for e in entities.enemies:
				if not e.display and e.position.distance_to(at) < FOE_NEAR:
					var bits := (1 if e.mode == "dash" else 0) | (2 if e.phase == 2 else 0) | (4 if e.debuffs.has("poisoned") else 0) | (8 if e.debuffs.has("on_fire") else 0)
					list.append([e.net_id, e.def.name, e.position, e.rotation.y, e.hp, bits])
			if not list.is_empty():
				foe_states.rpc_id(id, list)


# ---------- cliente ----------

func _send_state() -> void:
	var p := player
	var flags := (1 if p.on_floor else 0) | (2 if p.swimming else 0) | (4 if p.dead > 0 else 0) | (8 if p.ghost else 0)
	state.rpc_id(1, [p.position, p.rotation.y, p.pitch, p.velocity, flags, p.held(), p.cooldown, p.hp, p.max_hp, p.mana, p.mana_cap()], world.render_distance)
	if p.inv.equip != worn:
		worn = p.inv.equip.duplicate()
		equip.rpc_id(1, 0, Array(worn).map(func(i): return Items.names[i] if i != -1 else ""))


func _arrived() -> bool:   # os 3x3 chunks em volta do jogador já chegaram
	var c := _chunk_of(player.position.x, player.position.z)
	for dz in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			var k: Vector2i = c + Vector2i(dx, dz)
			if world.in_world(k) and not world.packed.has(k):
				return false
	return true


func _process(delta: float) -> void:
	if mode == OFF:
		return
	_flush_blocks()
	_flush_drops()
	tick -= delta
	clock_tick -= delta
	foe_tick -= delta
	if mode == SERVER:
		_send_chunks()
		_send_foes()
		if tick <= 0.0:
			tick = RATE
			_send_states()
		return
	if multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	if waiting and welcomed and _arrived():
		waiting = false
		player.position = player.home()
		player.say("")
		_freeze(false)
	if tick <= 0.0 and welcomed:
		tick = RATE
		_send_state()
	var now := Time.get_ticks_msec()
	var k := 1.0 - exp(-12.0 * delta)
	for id in puppets:
		var r: Node3D = puppets[id]
		if not r.visible:
			continue
		if now - int(r.get_meta("seen", now)) > 1000:   # saiu do raio de interesse
			r.visible = false
			continue
		r.position = r.position.lerp(r.get_meta("goal"), k)
		r.rotation.y = lerp_angle(r.rotation.y, r.get_meta("yaw"), k)
		r.cooldown = maxf(0.0, r.cooldown - delta)
	for id in foes.keys():
		if now - foes[id].seen > FOE_LOST:   # saiu do raio de interesse
			entities.remove_enemy(foes[id])
