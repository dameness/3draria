extends Node3D
# Jogador em 1ª pessoa com colisão AABB contra os voxels (VoxelBody).
# WASD anda, Espaço pula, Shift corre, F liga/desliga voo (Espaço sobe, C desce).
# Segurar o botão esquerdo usa o item da mão (picareta minera, espada golpeia, arco atira); direito coloca bloco.
# 1-0 ou roda escolhem o slot; E abre inventário/criação; F5 salva (também salva ao fechar); F8 dá o kit de teste.
# Clique captura o mouse, Esc solta.

const HALF := 0.3        # meia largura da caixa
const TALL := 1.8
const EYE := 1.62
const GRAVITY := 28.0
const JUMP := 9.0        # sobe ~1,4 bloco
const WALK := 4.5
const REACH := 5.0
const MAX_HP := 100
const IFRAMES := 0.67    # 40 frames de invencibilidade após levar dano, como no Terraria
const REGEN_DELAY := 5.0
const EPS := VoxelBody.EPS
const TEST_KIT := {"terra_blade": 1, "enchanted_sword": 1, "wooden_bow": 1, "wooden_arrow": 200, "iron_pickaxe": 1}  # F8, para playtest
const LO := Vector3(-HALF, 0, -HALF)
const HI := Vector3(HALF, TALL, HALF)

@export var world: Node3D
@export var entities: Node3D
@export var clock: Node
@export var load_save := true   # testes desligam para não pegar o save de quem joga
var velocity := Vector3.ZERO
var knock := Vector3.ZERO     # empurrão horizontal de golpes, some aos poucos
var on_floor := false
var flying := false
var inv := Inventory.new()
var slot := 0                 # slot da hotbar na mão
var inventory_open := false
var message := ""             # aviso curto para o HUD
var message_until := 0
var hp := float(MAX_HP)
var iframes := 0.0
var since_hit := 99.0
var cooldown := 0.0
var spawn := Vector3.ZERO
var pitch := 0.0
var target := {}              # resultado do raycast da mira
@onready var cam: Camera3D = $Camera
var highlight: MeshInstance3D


func _ready() -> void:
	var mid := WorldGen.SIZE_CHUNKS * WorldGen.CHUNK / 2
	position = Vector3(mid + 0.5, world.surface_y(mid, mid), mid + 0.5)
	spawn = position
	inv.add(Items.ids.copper_pickaxe, 1)
	inv.add(Items.ids.copper_shortsword, 1)
	if load_save and SaveGame.load_into(world, self, clock):
		say("jogo carregado")
	cam.position.y = EYE
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
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and load_save:
		SaveGame.save(world, self, clock)


func _unhandled_input(e: InputEvent) -> void:
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if e is InputEventKey and e.pressed and not e.echo and e.physical_keycode == KEY_E:
		inventory_open = not inventory_open
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if inventory_open else Input.MOUSE_MODE_CAPTURED
	elif inventory_open:
		if e.is_action_pressed("ui_cancel"):
			inventory_open = false
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
	elif e.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif e is InputEventKey and e.pressed and not e.echo:
		if e.physical_keycode >= KEY_0 and e.physical_keycode <= KEY_9:
			slot = posmod(e.physical_keycode - KEY_1, Inventory.HOTBAR)  # 1..9 e 0 = décimo
		elif e.physical_keycode == KEY_F:
			flying = not flying
		elif e.physical_keycode == KEY_F8:
			for n in TEST_KIT:
				inv.add(Items.ids[n], TEST_KIT[n])
			say("kit de teste")
		elif e.physical_keycode == KEY_F5:
			say("jogo salvo" if SaveGame.save(world, self, clock) == OK else "erro ao salvar")


func _physics_process(delta: float) -> void:
	var k := func(key): return 1.0 if Input.is_physical_key_pressed(key) else 0.0
	var wish := Vector3(k.call(KEY_D) - k.call(KEY_A), 0, k.call(KEY_S) - k.call(KEY_W)).rotated(Vector3.UP, rotation.y)
	if flying:
		wish.y = k.call(KEY_SPACE) - k.call(KEY_C)
	step(delta, wish.normalized(), Input.is_physical_key_pressed(KEY_SPACE), Input.is_physical_key_pressed(KEY_SHIFT))
	tick(delta)


func _process(_delta: float) -> void:
	target = world.raycast(cam.global_position, -cam.global_basis.z, REACH)
	highlight.visible = not target.is_empty()
	if highlight.visible:
		highlight.global_position = Vector3(target.pos) + Vector3.ONE * 0.5
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not inventory_open \
			and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and cooldown <= 0:
		use_item()


# Timers de vida: invencibilidade, cooldown de uso e regeneração lenta.
func tick(delta: float) -> void:
	iframes -= delta
	cooldown -= delta
	since_hit += delta
	if since_hit > REGEN_DELAY:
		hp = minf(hp + delta, MAX_HP)  # ponytail: 1 de vida/s; a regeneração do Terraria é mais complexa


func step(delta: float, wish: Vector3, jump: bool, sprint := false) -> void:
	var speed := WALK * (1.4 if sprint else 1.0)
	if flying:
		velocity = Vector3.ZERO
		position += wish * speed * 3.0 * delta  # voo atravessa blocos
		return
	velocity.x = wish.x * speed + knock.x
	velocity.z = wish.z * speed + knock.z
	knock = knock.move_toward(Vector3.ZERO, 20.0 * delta)
	velocity.y = maxf(velocity.y - GRAVITY * delta, -50.0)
	if jump and on_floor:
		velocity.y = JUMP
	var r := VoxelBody.move(world, position, HALF, TALL, velocity * delta)
	position = r[0]
	var hit: Vector3i = r[1]
	on_floor = hit.y < 0
	if hit.y != 0:
		velocity.y = 0.0


func overlaps_solid(p: Vector3) -> bool:
	return VoxelBody.overlaps(world, p, HALF, TALL)


func held() -> int:
	return inv.item[slot]


func say(text: String) -> void:
	message = text
	message_until = Time.get_ticks_msec() + 2000


# Dano como no Terraria (modo normal): dano − defesa/2. Sem armadura por enquanto.
func hurt(damage: int, dir: Vector3) -> void:
	if iframes > 0 or flying:
		return
	hp -= maxi(1, damage)
	iframes = IFRAMES
	since_hit = 0.0
	knock = Vector3(dir.x, 0, dir.z).normalized() * 6.0
	velocity.y = 5.0
	if hp <= 0:
		hp = MAX_HP
		position = spawn
		velocity = Vector3.ZERO
		knock = Vector3.ZERO
		say("você morreu")


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
	if Items.pick_power[id] > 0:
		break_target()
		return
	var eye := cam.global_position
	var forward := -cam.global_basis.z
	if d.has("ammo"):
		shoot(d, eye, forward)
	elif d.get("damage", 0) > 0:
		swing(d, eye, forward)


# Acerta todos os inimigos à frente dentro do alcance.
func swing(d: Dictionary, eye: Vector3, forward: Vector3) -> int:
	var hits := 0
	for e in entities.enemies.duplicate():
		var to: Vector3 = e.position + Vector3.UP * e.tall / 2 - eye
		if to.length() < d.reach + e.half and forward.dot(to.normalized()) > 0.5:
			e.hurt(d.damage, forward, d.knockback)
			hits += 1
	if d.has("shoot"):  # espadas como a Terra Blade disparam um feixe a cada golpe
		entities.spawn_projectile(d.shoot, eye + forward * 0.8, forward, d.shoot_speed, d.damage, d.knockback)
	return hits


# Invocador de chefe (ex.: Suspicious Looking Eye): só à noite e com um chefe por vez.
func summon(d: Dictionary) -> void:
	if not clock.is_night():
		say("nada acontece... (só à noite)")
	elif entities.boss:
		say("já há um chefe")
	else:
		var b: Node3D = entities.spawn_boss(d.summon)
		inv.take_one(slot)
		say("%s despertou!" % b.def.name.replace("_", " "))


# Primeira munição da classe pedida pela arma (ex.: qualquer flecha para arcos), na ordem do inventário.
func find_ammo(ammo_class: String) -> int:
	for i in Inventory.SIZE:
		if inv.item[i] != -1 and Items.defs[inv.item[i]].get("ammo_class") == ammo_class:
			return inv.item[i]
	return -1


func shoot(d: Dictionary, eye: Vector3, forward: Vector3) -> void:
	var ammo := find_ammo(d.ammo)
	if ammo == -1:
		say("sem munição (%s)" % d.ammo)
		return
	inv.remove(ammo, 1)
	var dmg: int = d.damage + Items.defs[ammo].get("damage", 0)
	entities.spawn_projectile(Items.defs[ammo].projectile, eye, forward, d.shoot_speed, dmg, d.knockback)


# Quebra o bloco na mira se a picareta na mão tiver poder; o drop cai como item solto.
func break_target() -> void:
	if target.is_empty():
		return
	var p: Vector3i = target.pos
	var b: int = world.get_block(p.x, p.y, p.z)
	var power := Items.pick_power[held()] if held() != -1 else 0
	if not Blocks.breakable[b]:
		return
	if power == 0:
		say("segure uma picareta")
		return
	if power < Blocks.power[b]:
		say("%s precisa de picareta com poder %d (a sua: %d)" % [Blocks.ids.keys()[b].replace("_", " "), Blocks.power[b], power])
		return
	world.set_block(p.x, p.y, p.z, 0)
	if Items.drop[b] != -1:
		entities.spawn_drop(Items.drop[b], 1, Vector3(p) + Vector3(0.5, 0.2, 0.5))


func place_target() -> void:
	if target.is_empty() or held() == -1 or Items.places[held()] == -1:
		return
	var p: Vector3i = target.pos + target.normal
	var lo := Vector3i((position + LO).floor())
	var hi := Vector3i((position + HI - Vector3.ONE * EPS).floor())
	var inside := p.x >= lo.x and p.x <= hi.x and p.y >= lo.y and p.y <= hi.y and p.z >= lo.z and p.z <= hi.z
	if not inside and world.get_block(p.x, p.y, p.z) == 0:
		world.set_block(p.x, p.y, p.z, Items.places[held()])
		inv.take_one(slot)
