extends Node
# Rede (docs/MULTIPLAYER.md): todos os RPCs moram aqui, no nó "Net" filho da raiz da cena (game.tscn no cliente, server.tscn no servidor).
# Cada cena prende o próprio SceneMultiplayer na sua raiz, então o caminho do RPC ("Net") é o mesmo dos dois lados e servidor e clientes
# cabem no mesmo processo (tests/net.gd). Quem manda: o servidor nos blocos, líquidos, mudas, espalhamento e hora; o cliente no próprio
# personagem. Blocos passam pelo funil world.set_block → block_changed (um lote por quadro).
# M3: sem inimigos/itens em rede (cada cliente ainda tem os seus, M4a) e o servidor ainda não salva (M5).

enum { OFF, SERVER, CLIENT }
const PORT := 8070
const RATE := 1.0 / 15         # estado dos jogadores (15 Hz)
const CHUNKS_PER_FRAME := 6    # vazão da entrada (~1 KB cada): ~360 chunks/s a 60 fps
const BUFFER := 1 << 22        # 4 MB por conexão (o padrão de 64 KB não comporta a entrada)
const NEAR := 192.0            # raio de interesse do estado dos outros (blocos)
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
	peers[id] = {"name": who, "look": look, "equip": [], "state": [], "view": 6, "center": Vector2i(-999, -999), "sent": {}, "queue": []}
	_requeue(id, spawn)
	var data := SaveGame.world_out(world, self, clock, "servidor")
	data.chunks = {}   # os chunks vão aos poucos (_send_chunks); o mapa explorado é por jogador (M5)
	data.erase("map")
	welcome.rpc_id(id, data)
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


# s = [posição, yaw, pitch, velocidade, flags (1 chão, 2 nadando, 4 morto), item na mão, cooldown]
@rpc("any_peer", "unreliable_ordered")
func state(s: Array, view: int) -> void:
	var id := multiplayer.get_remote_sender_id()
	if mode != SERVER or not peers.has(id):
		return
	peers[id].state = s
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
		r.pitch = s[3]
		r.velocity = s[4]
		r.on_floor = s[5] & 1 != 0
		r.swimming = s[5] & 2 != 0
		r.dead = 1.0 if s[5] & 4 else 0.0
		r.hand = s[6]
		r.cooldown = s[7]


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
		for o in peers:
			if o != id:
				equip.rpc_id(o, id, worn_names)
	elif puppets.has(id):
		_wear(puppets[id], worn_names)


@rpc("authority", "unreliable_ordered")
func time_of_day(time: float, speed: float) -> void:
	clock.time = time
	clock.speed = speed


func _wear(r: Node3D, worn_names: Array) -> void:
	for i in mini(worn_names.size(), r.inv.equip.size()):
		r.inv.equip[i] = Items.ids.get(worn_names[i], -1)


# ---------- servidor ----------

func _gone(id: int) -> void:
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


# ---------- cliente ----------

func _send_state() -> void:
	var p := player
	var flags := (1 if p.on_floor else 0) | (2 if p.swimming else 0) | (4 if p.dead > 0 else 0)
	state.rpc_id(1, [p.position, p.rotation.y, p.pitch, p.velocity, flags, p.held(), p.cooldown], world.render_distance)
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
	tick -= delta
	clock_tick -= delta
	if mode == SERVER:
		_send_chunks()
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
