extends Camera3D
# Câmera livre para inspecionar o mundo até a F2 trazer o jogador.
# WASD move, Espaço sobe, C desce, Shift acelera, clique captura o mouse, Esc solta.

@export var speed := 20.0
var yaw := 0.0
var pitch := -0.4


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		yaw -= e.relative.x * 0.003
		pitch = clampf(pitch - e.relative.y * 0.003, -1.55, 1.55)
	elif e is InputEventMouseButton and e.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif e.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _process(delta: float) -> void:
	rotation = Vector3(pitch, yaw, 0)
	var k := func(key): return 1.0 if Input.is_physical_key_pressed(key) else 0.0
	var move: Vector3 = basis * Vector3(k.call(KEY_D) - k.call(KEY_A), 0, k.call(KEY_S) - k.call(KEY_W))
	move.y += k.call(KEY_SPACE) - k.call(KEY_C)
	position += move.normalized() * speed * (4.0 if Input.is_physical_key_pressed(KEY_SHIFT) else 1.0) * delta
