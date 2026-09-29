extends Node3D
# Jogador em 1ª pessoa com colisão AABB contra os voxels (VoxelBody).
# WASD anda, Espaço pula, Shift corre, F liga/desliga voo (Espaço sobe, C desce), V troca 1ª/3ª pessoa.
# Segurar o botão esquerdo usa o item da mão (picareta minera, espada golpeia, arco atira); direito coloca bloco.
# 1-0 ou roda escolhem o slot; E abre inventário/criação; Tab/M/+/- são do minimapa (minimap.gd); F5 salva (também salva ao fechar); F8 dá o kit de teste.
# Esc fecha o inventário; sem nada aberto, abre o menu (Continuar / Salvar e sair).

const HALF := 0.3        # meia largura da caixa
const TALL := 1.8
const EYE := 1.62
const GRAVITY := 28.0
const JUMP := 9.0        # sobe ~1,4 bloco
const WALK := 4.5
const REACH := 5.0
const SWIM_UP := 4.5       # Espaço na água: sobe a esta velocidade
const SWIM_SINK := 3.0     # sem Espaço: afunda devagar
const SWIM_DEPTH := 1.0    # com mais líquido que isto acima dos pés (até a cintura) nada; com menos, vadeia: anda e pula como em terra
const HOP_DEPTH := 1.5     # perto da superfície, Espaço junto de uma margem dá um pulo inteiro para sair da água
const LAVA_DAMAGE := 50    # por golpe (há invencibilidade entre um e outro), sem tirar a armadura
const METEORITE_BURN := 4  # por golpe (há invencibilidade entre um e outro)
const MAX_HP := 100
const IFRAMES := 0.67    # 40 frames de invencibilidade após levar dano, como no Terraria
const REGEN_DELAY := 5.0
const MINE_DECAY := 2.5        # sem golpear o bloco por este tempo, as rachaduras somem
const TPP_DISTANCE := 4.0      # câmera em 3ª pessoa: distância atrás da cabeça
const TPP_SHOULDER := 0.6      # e deslocada para a direita, para a mira não ficar sobre a cabeça
const TPP_MARGIN := 0.4        # a câmera para antes do bloco que está no caminho (a lente vê ~0,1 além do ponto)
const EPS := VoxelBody.EPS
const TEST_KIT := {"hermes_boots": 1, "shiny_red_balloon": 1, "band_of_regeneration": 1, "terra_blade": 1, "enchanted_sword": 1, "wooden_bow": 1, "wooden_arrow": 200, "iron_pickaxe": 1}  # F8, para playtest
const LO := Vector3(-HALF, 0, -HALF)
const HI := Vector3(HALF, TALL, HALF)

@export var world: Node3D
@export var entities: Node3D
@export var clock: Node
var velocity := Vector3.ZERO
var knock := Vector3.ZERO     # empurrão horizontal de golpes, some aos poucos
var on_floor := false
var hit_wall := false         # o último passo bateu numa parede (usado para sair da água)
var depth := 0.0              # blocos de líquido acima dos pés
var swimming := false         # mais fundo que SWIM_DEPTH
var flying := false
var map_open := false         # mapa cheio (M) aberto: o jogador fica parado (minimap.gd liga e desliga)
var death := Vector3.INF      # onde morreu por último (o mapa marca)
var inv := Inventory.new()
var slot := 0                 # slot da hotbar na mão
var inventory_open := false
var menu_open := false        # Esc: Continuar / Salvar e sair
var third_person := false     # V alterna
var message := ""             # aviso curto para o HUD
var message_until := 0
var hp := float(MAX_HP)
var iframes := 0.0
var since_hit := 99.0
var cooldown := 0.0
var spawn := Vector3.ZERO
var pitch := 0.0
var bob := 0.0                # fase do balanço da câmera ao andar
var shake := 0.0              # tremor da tela ao acertar ou ser acertado; some rápido
var swing_item := {}          # golpe em andamento: acerta no momento do impacto da animação
var swing_timer := 0.0
var target := {}              # resultado do raycast da mira
var mine_pos := Vector3i(-1, -1, -1)   # bloco que está sendo minerado e o dano acumulado nele (100 quebra)
var mine_damage := 0.0
var mine_idle := 0.0
var place_anim := 0.0         # a mão dá um empurrão ao colocar um bloco
var stride := 0.0             # distância andada desde a última nuvenzinha de poeira dos passos
var last_depth := 0.0
var bubble_timer := 0.0
var was_on_floor := false
var fall_speed := 0.0
var crack: BlockCrack
@onready var cam: Camera3D = $Camera
var highlight: MeshInstance3D


func _ready() -> void:
	if SaveGame.world_path != "":
		SaveGame.load_world(world, self, clock, SaveGame.world_path)
	if spawn == Vector3.ZERO:  # mundo novo: nasce no meio, na superfície
		var mid := WorldGen.SIZE_CHUNKS * WorldGen.CHUNK / 2
		spawn = Vector3(mid + 0.5, world.surface_y(mid, mid), mid + 0.5)
	position = spawn
	if SaveGame.player_path == "" or not SaveGame.load_player(self, SaveGame.player_path):
		inv.add(Items.ids.copper_pickaxe, 1)  # itens iniciais de personagem novo
		inv.add(Items.ids.copper_shortsword, 1)
		inv.add(Items.ids.copper_axe, 1)
	cam.position.y = EYE
	if SaveGame.player_path != "":   # a aparência (cores) do personagem escolhido no menu
		get_node("Model").restyle(SaveGame.look(SaveGame.player_path))
	highlight = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3.ONE * 1.01
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0, 0, 0, 0.25)
	box.material = mat
	highlight.mesh = box
	highlight.top_level = true
	add_child(highlight)
	crack = BlockCrack.new()
	add_child(crack)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		SaveGame.save_all(world, self, clock)


func set_menu(open: bool) -> void:
	menu_open = open
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if open else Input.MOUSE_MODE_CAPTURED
	if is_inside_tree():
		get_tree().paused = open   # pausa de verdade: mundo, inimigos e relógio param (o HUD continua vivo)


func _unhandled_input(e: InputEvent) -> void:
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if e is InputEventKey and e.pressed and not e.echo and e.physical_keycode == KEY_E and not menu_open and not map_open:
		inventory_open = not inventory_open
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if inventory_open else Input.MOUSE_MODE_CAPTURED
	elif inventory_open:
		if e.is_action_pressed("ui_cancel"):
			inventory_open = false
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif e.is_action_pressed("ui_cancel"):
		set_menu(not menu_open)
	elif menu_open or map_open:
		pass
	elif e is InputEventMouseMotion and captured:
		rotation.y -= e.relative.x * 0.003
		pitch = clampf(pitch - e.relative.y * 0.003, -1.55, 1.55)
		cam.rotation.x = pitch
	elif e is InputEventMouseButton and e.pressed:
		if not captured:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		elif e.button_index == MOUSE_BUTTON_RIGHT:
			place_target()
		elif e.button_index == MOUSE_BUTTON_WHEEL_UP:
			slot = posmod(slot - 1, Inventory.HOTBAR)
		elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			slot = posmod(slot + 1, Inventory.HOTBAR)
	elif e is InputEventKey and e.pressed and not e.echo:
		if e.physical_keycode >= KEY_0 and e.physical_keycode <= KEY_9:
			slot = posmod(e.physical_keycode - KEY_1, Inventory.HOTBAR)  # 1..9 e 0 = décimo
		elif e.physical_keycode == KEY_F:
			flying = not flying
		elif e.physical_keycode == KEY_V:
			third_person = not third_person
		elif e.physical_keycode == KEY_F8:
			for n in TEST_KIT:
				inv.add(Items.ids[n], TEST_KIT[n])
			say("kit de teste")
		elif e.physical_keycode == KEY_F5:
			say("jogo salvo" if SaveGame.save_all(world, self, clock) == OK else "erro ao salvar")


func _physics_process(delta: float) -> void:
	var k := func(key): return 1.0 if Input.is_physical_key_pressed(key) and not map_open else 0.0   # com o mapa cheio aberto fica parado
	var wish := Vector3(k.call(KEY_D) - k.call(KEY_A), 0, k.call(KEY_S) - k.call(KEY_W)).rotated(Vector3.UP, rotation.y)
	if flying:
		wish.y = k.call(KEY_SPACE) - k.call(KEY_C)
	step(delta, wish.normalized(), k.call(KEY_SPACE) > 0.0, k.call(KEY_SHIFT) > 0.0)
	tick(delta)


func eye() -> Vector3:
	return global_position + Vector3.UP * EYE


func _process(delta: float) -> void:
	_update_camera(delta)
	target = world.raycast(eye(), -cam.global_basis.z, REACH)
	highlight.visible = not target.is_empty()
	if highlight.visible:
		highlight.global_position = Vector3(target.pos) + Vector3.ONE * 0.5
	if mine_damage > 0.0 and not target.is_empty() and target.pos == mine_pos:
		crack.show_at(mine_pos, mine_damage / 100.0)
	else:
		crack.visible = false
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not inventory_open and not menu_open and not map_open \
			and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and cooldown <= 0:
		use_item()


# 1ª pessoa: câmera nos olhos e item na mão da câmera. 3ª pessoa: câmera atrás da cabeça e ao lado do ombro, mais perto se
# houver bloco no caminho (o raio vai dos olhos até o ponto da câmera, ombro incluído), e o corpo do jogador aparece.
func _update_camera(delta := 0.0) -> void:
	var offset := Vector3.ZERO
	if third_person:
		var want := Basis(Vector3.RIGHT, pitch) * Vector3(0, 0, TPP_DISTANCE) + Vector3(TPP_SHOULDER, 0, 0)   # em relação aos olhos
		var hit: Dictionary = world.raycast(eye(), (global_basis * want).normalized(), want.length() + TPP_MARGIN)
		var k := 1.0 if hit.is_empty() else clampf((hit.t - TPP_MARGIN) / want.length(), 0.0, 1.0)
		for i in 6:   # rede de segurança: encosta na parede lateral ou no teto sem a lente entrar em bloco
			if lens_clear(eye() + global_basis * (want * k)):
				break
			k *= 0.7
		offset = want * k
	cam.position = Vector3(0, EYE, 0) + offset
	var walk := clampf(Vector2(velocity.x, velocity.z).length() / WALK, 0.0, 1.4) if on_floor and not flying else 0.0
	bob += delta * (7.0 + walk * 3.0) * walk
	shake = maxf(shake - delta * 2.5, 0.0)
	if not third_person and delta > 0.0:   # em 1ª pessoa a câmera balança ao andar e treme nos golpes
		cam.position += Vector3(cos(bob * 0.5) * 0.02, absf(sin(bob)) * 0.035, 0) * walk
		cam.position += Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * shake * 0.05
	cam.get_node("Hand").visible = not third_person
	get_node("Model").visible = third_person


# A lente (um cubo de 0,3 em volta de p) não toca em bloco sólido.
func lens_clear(p: Vector3) -> bool:
	for dx in [-0.15, 0.15]:
		for dy in [-0.15, 0.15]:
			for dz in [-0.15, 0.15]:
				if Blocks.solid[world.get_block(floori(p.x + dx), floori(p.y + dy), floori(p.z + dz))]:
					return false
	return true


# Timers de vida: invencibilidade, cooldown de uso e regeneração lenta.
func tick(delta: float) -> void:
	iframes -= delta
	cooldown -= delta
	place_anim = maxf(place_anim - delta, 0.0)
	if not swing_item.is_empty():
		swing_timer -= delta
		if swing_timer <= 0.0:   # o impacto do golpe: a lâmina acerta o que está à frente e a picareta bate no bloco da mira
			var hits := 0
			if swing_item.get("damage", 0) > 0:
				hits = swing(swing_item, eye(), -cam.global_basis.z)
			if swing_item.has("pick_power") or swing_item.has("axe_power"):
				break_target()
			if hits > 0:
				shake = maxf(shake, 0.4)
			swing_item = {}
	if on_floor and world.get_block(floori(position.x), floori(position.y - 0.1), floori(position.z)) == Blocks.ids.meteorite:
		hurt(METEORITE_BURN, Vector3.ZERO)   # meteorito queima quem pisa (Burning do Terraria)
		Fx.sparks(entities, position + Vector3.UP * 0.2, Color("#ff9a3a"), 2, Vector3.UP)
	mine_idle += delta
	if mine_idle > MINE_DECAY:
		mine_damage = 0.0
		mine_pos = Vector3i(-1, -1, -1)
	since_hit += delta
	if since_hit > REGEN_DELAY:
		hp = minf(hp + delta * (1.0 + inv.acc_sum("regen")), MAX_HP)  # ponytail: 1 de vida/s; a regeneração do Terraria é mais complexa


func step(delta: float, wish: Vector3, jump: bool, sprint := false) -> void:
	var speed := WALK * (1.4 if sprint else 1.0) * (1.0 + inv.acc_sum("speed"))
	if flying:
		velocity = Vector3.ZERO
		position += wish * speed * 3.0 * delta  # voo atravessa blocos
		return
	depth = liquid_depth()
	var kind := liquid_kind_below()
	swimming = depth > SWIM_DEPTH
	var slow := 0.55 if swimming else 0.75 if depth > 0.0 else 1.0
	velocity.x = wish.x * speed * slow + knock.x
	velocity.z = wish.z * speed * slow + knock.z
	knock = knock.move_toward(Vector3.ZERO, 20.0 * delta)
	if swimming:  # nadando: afunda devagar e Espaço sobe; junto de uma margem, perto da superfície, Espaço dá um pulo inteiro
		velocity.y = move_toward(velocity.y, SWIM_UP if jump else -SWIM_SINK, 30.0 * delta)
		if jump and depth < HOP_DEPTH and (hit_wall or on_floor):
			velocity.y = JUMP * (1.0 + inv.acc_sum("jump"))
	else:
		velocity.y = maxf(velocity.y - GRAVITY * delta, -50.0)
		if jump and on_floor:
			velocity.y = JUMP * (1.0 + inv.acc_sum("jump"))
	if depth > 0.0 and kind == Blocks.ids.lava:
		hurt(LAVA_DAMAGE, Vector3.ZERO)
	fall_speed = minf(velocity.y, fall_speed)
	var r := VoxelBody.move(world, position, HALF, TALL, velocity * delta)
	position = r[0]
	var hit: Vector3i = r[1]
	on_floor = hit.y < 0
	hit_wall = hit.x != 0 or hit.z != 0
	if hit.y != 0:
		velocity.y = 0.0
	_effects(delta)


# Partículas do movimento: poeira dos passos e do pouso (na cor do chão), respingo ao entrar ou sair da água e bolhas nadando.
func _effects(delta: float) -> void:
	if entities == null:
		return
	if on_floor and not was_on_floor and fall_speed < -7.0 and depth == 0.0:
		Fx.dust(entities, position + Vector3(0, 0.1, 0), _ground_color(), 10, Vector3.UP)
	if on_floor:
		fall_speed = 0.0
		var speed := Vector2(velocity.x, velocity.z).length()
		stride += speed * delta
		if stride > 1.5 and speed > 2.0 and depth == 0.0:
			stride = 0.0
			Fx.dust(entities, position + Vector3(0, 0.08, 0), _ground_color(), 2)
	was_on_floor = on_floor
	if (depth > 0.3) != (last_depth > 0.3) and absf(velocity.y) > 2.0:
		Fx.splash(entities, position + Vector3(0, maxf(depth, 0.3), 0), 14)
	last_depth = depth
	if swimming:
		bubble_timer -= delta
		if bubble_timer <= 0.0:
			bubble_timer = 0.45
			Fx.bubbles(entities, position + Vector3(0, 1.5, 0))


func _ground_color() -> Color:
	return Blocks.color_of(world.get_block(floori(position.x), floori(position.y - 0.1), floori(position.z)))


# Blocos de líquido acima dos pés (0 = seco): sobe pelos blocos do mesmo líquido e conta até a superfície do último.
func liquid_depth() -> float:
	var x := floori(position.x)
	var z := floori(position.z)
	var y := floori(position.y + 0.05)
	var b: int = world.get_block(x, y, z)
	if not Blocks.liquid[b]:
		return 0.0
	while true:
		var above: int = world.get_block(x, y + 1, z)
		if not (Blocks.liquid[above] and Blocks.liquid_kind[above] == Blocks.liquid_kind[b]):
			break
		b = above
		y += 1
	return maxf(y + Blocks.liquid_height(b) - position.y, 0.0)


# Líquido (id do cheio: water, lava) nos pés, ou 0.
func liquid_kind_below() -> int:
	var b: int = world.get_block(floori(position.x), floori(position.y + 0.05), floori(position.z))
	return Blocks.liquid_kind[b] if Blocks.liquid[b] else 0


# Líquido (id do cheio) no meio do corpo, ou 0.
func liquid_at() -> int:
	return world.liquid_at(position + Vector3.UP * 0.6)


func overlaps_solid(p: Vector3) -> bool:
	return VoxelBody.overlaps(world, p, HALF, TALL)


func held() -> int:
	return inv.item[slot]


func say(text: String) -> void:
	message = text
	message_until = Time.get_ticks_msec() + 2000


# Dano como no Terraria (modo normal): dano − defesa/2 (armadura + bônus de conjunto), mínimo 1.
func hurt(damage: int, dir: Vector3) -> int:
	if iframes > 0 or flying:
		return 0
	var taken := maxi(1, damage - ceili(inv.defense() / 2.0))
	hp -= taken
	if entities:
		entities.spawn_text(position + Vector3.UP * (TALL + 0.4), str(taken), Color("#ff5058"))
	iframes = IFRAMES
	since_hit = 0.0
	shake = 1.0
	Sfx.play(entities, "hurt", position + Vector3.UP, 0.0)
	knock = Vector3(dir.x, 0, dir.z).normalized() * 6.0
	velocity.y = 5.0
	if hp <= 0:
		hp = MAX_HP
		death = position
		position = spawn
		velocity = Vector3.ZERO
		knock = Vector3.ZERO
		say("você morreu")
	return taken


# Botão esquerdo: picareta minera, arma com munição atira, arma golpeia.
func use_item() -> void:
	var id := held()
	if id == -1:
		return
	var d: Dictionary = Items.defs[id]
	cooldown = d.get("use_time", 0.25)
	if d.has("summon"):
		summon(d)
		return
	var forward := -cam.global_basis.z
	if d.has("ammo"):
		shoot(d, eye(), forward)
	elif d.has("bucket"):
		use_bucket(d)
	elif d.get("damage", 0) > 0 or Items.pick_power[id] > 0 or Items.axe_power[id] > 0:   # a lâmina (ou a picareta) só acerta quando o arco chega à frente (~1/3 do golpe)
		swing_item = d
		swing_timer = d.get("use_time", 0.25) * (0.42 if d.get("use_style") == "thrust" else 0.3)


# Balde: vazio pega o líquido da mira (um bloco); cheio derrama um bloco cheio no ar junto do alvo. O líquido depois flui sozinho (liquid.gd).
func use_bucket(d: Dictionary) -> void:
	if d.bucket == "empty":
		var look := Basis(Vector3.UP, rotation.y) * Basis(Vector3.RIGHT, pitch) * Vector3.FORWARD   # a mira, sem depender da câmera na árvore
		var hit: Dictionary = world.raycast(position + Vector3.UP * EYE, look, REACH, true)
		if hit.is_empty() or not Blocks.liquid[world.get_block(hit.pos.x, hit.pos.y, hit.pos.z)]:
			return
		var kind := Blocks.liquid_kind[world.get_block(hit.pos.x, hit.pos.y, hit.pos.z)]
		world.set_block(hit.pos.x, hit.pos.y, hit.pos.z, 0)
		inv.item[slot] = Items.ids["water_bucket" if kind == Blocks.ids.water else "lava_bucket"]
		inv.version += 1
		Fx.splash(entities, Vector3(hit.pos) + Vector3(0.5, 0.8, 0.5), 8)
		return
	if target.is_empty():
		return
	var p: Vector3i = target.pos + target.normal
	var there: int = world.get_block(p.x, p.y, p.z)
	if there == 0 or Blocks.soft[there]:
		world.set_block(p.x, p.y, p.z, Blocks.ids[d.bucket])
		inv.item[slot] = Items.ids.empty_bucket
		inv.version += 1
		Fx.splash(entities, Vector3(p) + Vector3(0.5, 0.8, 0.5), 8)


# Acerta todos os inimigos que a lâmina varre: à frente no plano horizontal (cone de ~75°) na altura do corpo, como o
# arco do Terraria, ou dentro do cone 3D da mira (para mirar em voadores). O feixe das espadas mágicas sai junto.
func swing(d: Dictionary, eye: Vector3, forward: Vector3) -> int:
	var hits := 0
	var flat := Vector3(forward.x, 0, forward.z)
	flat = flat.normalized() if flat.length() > 0.01 else forward
	for e in entities.enemies.duplicate():
		var to: Vector3 = e.position + Vector3.UP * e.tall / 2 - eye
		var flat_to := Vector3(to.x, 0, to.z)
		var reach: float = d.reach + e.half
		var in_arc: bool = flat_to.length() < reach and flat.dot(flat_to.normalized()) > 0.25 \
			and e.position.y < position.y + TALL + 0.5 and e.position.y + e.tall > position.y - 0.4
		var in_cone: bool = to.length() < reach and forward.dot(to.normalized()) > 0.5
		if in_arc or in_cone:
			e.hurt(d.damage, forward, d.knockback)
			hits += 1
	if d.has("shoot"):  # espadas como a Terra Blade disparam um feixe a cada golpe
		entities.spawn_projectile(d.shoot, eye + forward * 0.8, forward, d.shoot_speed, d.damage, d.knockback)
	return hits


# Invocador de chefe (ex.: Suspicious Looking Eye): só à noite e com um chefe por vez.
# Há lava a até r blocos dos pés?
func _lava_near(r: int) -> bool:
	var p := Vector3i(position.floor())
	for y in range(p.y - r, p.y + r + 1):
		for z in range(p.z - r, p.z + r + 1):
			for x in range(p.x - r, p.x + r + 1):
				if Blocks.liquid_kind[world.get_block(x, y, z)] == Blocks.ids.lava and Blocks.liquid[world.get_block(x, y, z)]:
					return true
	return false


func summon(d: Dictionary) -> void:
	if d.get("underworld", false) and not (position.y < WorldGen.UNDERWORLD_TOP and _lava_near(3)):
		say("jogue a boneca na lava, no submundo")
	elif d.get("night", false) and not clock.is_night():
		say("nada acontece... (só à noite)")
	elif entities.boss:
		say("já há um chefe")
	else:
		var b: Node3D = entities.spawn_boss(d.summon)
		inv.take_one(slot)
		say("%s despertou!" % b.def.name.replace("_", " "))


func shoot(d: Dictionary, eye: Vector3, forward: Vector3) -> void:
	var ammo := inv.take_ammo(d.ammo)
	if ammo == -1:
		say("sem munição (%s)" % d.ammo)
		return
	var dmg: int = d.damage + Items.defs[ammo].get("damage", 0)
	entities.spawn_projectile(Items.defs[ammo].projectile, eye, forward, d.shoot_speed, dmg, d.knockback)


# Um golpe da picareta no bloco da mira, como no Terraria: cada golpe soma ao bloco (poder da picareta × dureza dele) e ele racha
# até 100, quando quebra e o drop cai como item solto. A grama absorve o golpe que a quebraria: vira terra, ainda rachada.
# Bloco que a picareta não alcança (poder abaixo do mínimo) só avisa.
func break_target() -> void:
	if target.is_empty():
		return
	var p: Vector3i = target.pos
	var b: int = world.get_block(p.x, p.y, p.z)
	var axe := Blocks.axe[b] == 1   # tronco: só o machado corta; o resto, só a picareta
	var power := (Items.axe_power[held()] if axe else Items.pick_power[held()]) if held() != -1 else 0
	if not Blocks.breakable[b]:
		return
	if power == 0:
		say("precisa de um machado" if axe else "segure uma picareta")
		return
	if b == Blocks.ids.chest and Array(world.chest_at(p).item).any(func(id): return id != -1):
		say("esvazie o baú primeiro")
		return
	if Blocks.guard[b] > power and not world.skeletron_down:
		say("os tijolos do dungeon resistem (poder %d, ou derrote o Skeletron)" % Blocks.guard[b])
		return
	if power < Blocks.power[b]:
		say("%s precisa de picareta com poder %d (a sua: %d)" % [Blocks.ids.keys()[b].replace("_", " "), Blocks.power[b], power])
		return
	if p != mine_pos:
		mine_pos = p
		mine_damage = 0.0
	mine_idle = 0.0
	var normal := Vector3(target.normal)
	var face := Vector3(p) + Vector3.ONE * 0.5 + normal * 0.5
	var color := Blocks.color_of(b)
	var hard := Blocks.mine[b] <= 1.0   # pedra e minério soltam faíscas
	var tree: bool = b == Blocks.ids.wood and Timber.is_tree(world, p)   # árvore: 100 de vida por tile e ⌊poder × 24%⌋ por golpe (wiki Axe power)
	var damage: float = floori(power * Timber.HIT) if tree else power * Blocks.mine[b]
	if b == Blocks.ids.grass and mine_damage + damage >= 100.0:
		world.set_block(p.x, p.y, p.z, Blocks.ids.dirt)
		Fx.dust(entities, face, color, 6, normal)
		return
	mine_damage += damage
	if mine_damage < 100.0:
		Fx.dust(entities, face, color, 7, normal)
		Sfx.play(entities, "stone" if Blocks.mine[b] <= 1.0 else "dig", face)
		if hard:
			Fx.sparks(entities, face, Color("#ffe27a"), 2, normal)
		if tree:
			Timber.rustle(entities, world, p)
		shake = maxf(shake, 0.15)
		return
	if tree:   # o tile quebrou: cai ele e tudo o que está em cima (na base, a árvore inteira)
		Timber.fell(entities, p, power, position)
		mine_damage = 0.0
		mine_pos = Vector3i(-1, -1, -1)
		shake = maxf(shake, 0.3)
		return
	world.set_block(p.x, p.y, p.z, 0)
	world.chests.erase(p)
	if b == Blocks.ids.shadow_orb or b == Blocks.ids.crimson_heart:
		entities.orb_broken(b)
	mine_damage = 0.0
	mine_pos = Vector3i(-1, -1, -1)
	if Items.drop[b] != -1:
		entities.spawn_drop(Items.drop[b], 1, Vector3(p) + Vector3(0.5, 0.2, 0.5))
	Fx.chips(entities, Vector3(p) + Vector3.ONE * 0.5, color, 12)
	Sfx.play(entities, "break", Vector3(p) + Vector3.ONE * 0.5)
	if hard:
		Fx.sparks(entities, face, Color("#ffe27a"), 5, normal)
	shake = maxf(shake, 0.3)


func place_target() -> void:
	var npc: Node3D = entities.npc_aimed(REACH)
	if npc:
		entities.talk(npc)
		return
	if not target.is_empty() and world.get_block(target.pos.x, target.pos.y, target.pos.z) == Blocks.ids.chest:
		inventory_open = true   # botão direito num baú abre o inventário com o painel do baú
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		get_parent().get_node("HUD").open_chest(world.chest_at(target.pos))
		return
	if target.is_empty() or held() == -1 or Items.places[held()] == -1:
		return
	if Items.places[held()] == Blocks.sapling and not (target.normal == Vector3i.UP and Blocks.grassy[world.get_block(target.pos.x, target.pos.y, target.pos.z)] == 1):
		say("a muda só pega em cima da grama")
		return
	var p: Vector3i = target.pos + target.normal
	var lo := Vector3i((position + LO).floor())
	var hi := Vector3i((position + HI - Vector3.ONE * EPS).floor())
	var inside := p.x >= lo.x and p.x <= hi.x and p.y >= lo.y and p.y <= hi.y and p.z >= lo.z and p.z <= hi.z
	var there: int = world.get_block(p.x, p.y, p.z)
	if not inside and (there == 0 or Blocks.soft[there]):  # ar, planta ou líquido: o bloco novo substitui
		Sfx.play(entities, "place", Vector3(p) + Vector3.ONE * 0.5)
		world.set_block(p.x, p.y, p.z, Items.places[held()])
		inv.take_one(slot)
		place_anim = 0.18
