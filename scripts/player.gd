extends Node3D
# Jogador em 1ª pessoa com colisão AABB contra os voxels (sem motor de física).
# WASD anda, Espaço pula, Shift corre, F liga/desliga voo (Espaço sobe, C desce),
# mouse esquerdo quebra, direito coloca, 1-9 ou roda escolhem o bloco. Clique captura o mouse, Esc solta.

const HALF := 0.3        # meia largura da caixa
const TALL := 1.8
const EYE := 1.62
const GRAVITY := 28.0
const JUMP := 9.0        # sobe ~1,4 bloco
const WALK := 4.5
const REACH := 5.0
const EPS := 0.001
const LO := Vector3(-HALF, 0, -HALF)
const HI := Vector3(HALF, TALL, HALF)

@export var world: Node3D
var velocity := Vector3.ZERO
var on_floor := false
var flying := false
var hotbar: Array[int] = []   # ids de bloco; a F3 troca pelo inventário
var slot := 0
var pitch := 0.0
var target := {}              # resultado do raycast da mira
@onready var cam: Camera3D = $Camera
var highlight: MeshInstance3D


func _ready() -> void:
	for id in Blocks.ids.size():
		if Blocks.solid[id] and Blocks.breakable[id] and hotbar.size() < 9:
			hotbar.append(id)
	var mid := WorldGen.SIZE_CHUNKS * WorldGen.CHUNK / 2
	position = Vector3(mid + 0.5, world.gen.surface_height(mid, mid) + 1, mid + 0.5)
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


func _unhandled_input(e: InputEvent) -> void:
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if e is InputEventMouseMotion and captured:
		rotation.y -= e.relative.x * 0.003
		pitch = clampf(pitch - e.relative.y * 0.003, -1.55, 1.55)
		cam.rotation.x = pitch
	elif e is InputEventMouseButton and e.pressed:
		if not captured:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		elif e.button_index == MOUSE_BUTTON_LEFT:
			break_target()
		elif e.button_index == MOUSE_BUTTON_RIGHT:
			place_target()
		elif e.button_index == MOUSE_BUTTON_WHEEL_UP:
			slot = posmod(slot - 1, hotbar.size())
		elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			slot = posmod(slot + 1, hotbar.size())
	elif e.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif e is InputEventKey and e.pressed and not e.echo:
		if e.physical_keycode >= KEY_1 and e.physical_keycode < KEY_1 + hotbar.size():
			slot = e.physical_keycode - KEY_1
		elif e.physical_keycode == KEY_F:
			flying = not flying


func _physics_process(delta: float) -> void:
	var k := func(key): return 1.0 if Input.is_physical_key_pressed(key) else 0.0
	var wish := Vector3(k.call(KEY_D) - k.call(KEY_A), 0, k.call(KEY_S) - k.call(KEY_W)).rotated(Vector3.UP, rotation.y)
	if flying:
		wish.y = k.call(KEY_SPACE) - k.call(KEY_C)
	step(delta, wish.normalized(), Input.is_physical_key_pressed(KEY_SPACE), Input.is_physical_key_pressed(KEY_SHIFT))


func _process(_delta: float) -> void:
	target = world.raycast(cam.global_position, -cam.global_basis.z, REACH)
	highlight.visible = not target.is_empty()
	if highlight.visible:
		highlight.global_position = Vector3(target.pos) + Vector3.ONE * 0.5


func step(delta: float, wish: Vector3, jump: bool, sprint := false) -> void:
	var speed := WALK * (1.4 if sprint else 1.0)
	if flying:
		velocity = Vector3.ZERO
		position += wish * speed * 3.0 * delta  # voo atravessa blocos
		return
	velocity.x = wish.x * speed
	velocity.z = wish.z * speed
	velocity.y = maxf(velocity.y - GRAVITY * delta, -50.0)
	if jump and on_floor:
		velocity.y = JUMP
	var motion := velocity * delta
	on_floor = false
	for a in [1, 0, 2]:
		if _move_axis(a, motion[a]):
			if a == 1:
				on_floor = motion.y < 0
				velocity.y = 0.0


# Move num eixo; se a caixa entrar num bloco sólido, encosta nele. Retorna true se bateu.
# ponytail: assume movimento < 1 bloco por passo (ok até 60 blocos/s a 60 Hz).
func _move_axis(a: int, amount: float) -> bool:
	if amount == 0.0:
		return false
	position[a] += amount
	if not overlaps_solid(position):
		return false
	if amount > 0:
		position[a] = floorf(position[a] + HI[a]) - HI[a] - EPS
	else:
		position[a] = floorf(position[a] + LO[a]) + 1 - LO[a] + EPS
	return true


func overlaps_solid(p: Vector3) -> bool:
	var lo := Vector3i((p + LO).floor())
	var hi := Vector3i((p + HI - Vector3.ONE * EPS).floor())
	for y in range(lo.y, hi.y + 1):
		for z in range(lo.z, hi.z + 1):
			for x in range(lo.x, hi.x + 1):
				if Blocks.solid[world.get_block(x, y, z)]:
					return true
	return false


func break_target() -> void:
	if not target.is_empty() and Blocks.breakable[world.get_block(target.pos.x, target.pos.y, target.pos.z)]:
		world.set_block(target.pos.x, target.pos.y, target.pos.z, 0)


func place_target() -> void:
	if target.is_empty() or hotbar.is_empty():
		return
	var p: Vector3i = target.pos + target.normal
	var lo := Vector3i((position + LO).floor())
	var hi := Vector3i((position + HI - Vector3.ONE * EPS).floor())
	var inside := p.x >= lo.x and p.x <= hi.x and p.y >= lo.y and p.y <= hi.y and p.z >= lo.z and p.z <= hi.z
	if not inside and world.get_block(p.x, p.y, p.z) == 0:
		world.set_block(p.x, p.y, p.z, hotbar[slot])
