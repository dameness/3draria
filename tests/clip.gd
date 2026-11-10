extends SceneTree
# Clipe de jogo sem instalar nada: um robô segue um roteiro (andar, virar, pular, golpear) e o Godot grava em vídeo.
# Uso: scripts/clip.sh [roteiro]  → textures/clip_<roteiro>.mp4 (o --write-movie anda em passo fixo: o vídeo sai liso mesmo com OpenGL por CPU).
# Roteiro = lista de trechos {t: segundos, keys: teclas seguradas, turn: rad/s, pitch: alvo, item, attack, third, time: hora do dia}.
# Roteiro novo = uma entrada em CLIPS.

const CLIPS := {
	"passeio": [
		{"t": 3.0, "keys": [KEY_W], "pitch": -0.1},
		{"t": 2.0, "keys": [KEY_W], "turn": 0.5, "jump": true},
		{"t": 2.5, "keys": [KEY_W], "item": "copper_shortsword", "attack": true},
		{"t": 3.0, "keys": [KEY_W], "third": true, "turn": -0.4},
		{"t": 2.5, "keys": [KEY_W, KEY_D], "third": true, "jump": true},
		{"t": 3.0, "third": true, "item": "copper_axe", "attack": true, "turn": 0.6},
		{"t": 4.0, "keys": [KEY_W], "third": true, "time": 870.0, "turn": 0.2},
	],
	"noite": [
		{"t": 4.0, "keys": [KEY_W], "time": 1000.0, "give": ["torch"], "item": "torch"},
		{"t": 4.0, "keys": [KEY_W], "third": true, "turn": 0.5, "item": "copper_shortsword", "attack": true},
		{"t": 4.0, "keys": [KEY_W], "third": true, "turn": -0.5, "jump": true},
	],
}

var main: Node
var world: Node3D
var player: Node3D
var steps := []
var step := -1
var left := 0.0
var held := []


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	steps = CLIPS[args[0] if args.size() > 0 else "passeio"]
	main = load("res://game.tscn").instantiate()
	world = main.get_node("World")
	player = main.get_node("Player")
	root.add_child(main)


func _key(code: Key, down: bool) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.pressed = down
	Input.parse_input_event(e)


func _process(delta: float) -> bool:
	if step < 0:
		if not world.is_idle() or world.center.x < 0:
			return false
		print("clip_inicio ", Engine.get_frames_drawn())   # scripts/clip.sh corta o carregamento por aqui
		left = 0.0
		step = 0
		_enter(steps[0])
	var s: Dictionary = steps[step]
	player.rotation.y -= s.get("turn", 0.0) * delta
	player.pitch = lerpf(player.pitch, s.get("pitch", -0.12), minf(1.0, delta * 3.0))
	player.attack_held = s.get("attack", false)
	if player.attack_held:
		player.attack_buffer = 0.2
	if s.get("jump", false):
		_key(KEY_SPACE, fmod(left, 0.9) < 0.3)
	left -= delta
	if left <= 0.0:
		step += 1
		if step >= steps.size():
			return true
		_enter(steps[step])
	return false


func _enter(s: Dictionary) -> void:
	for k in held:
		_key(k, false)
	_key(KEY_SPACE, false)
	held = s.get("keys", [])
	for k in held:
		_key(k, true)
	left = s.t
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	player.third_person = s.get("third", false)
	if s.has("time"):
		main.get_node("DayNight").time = s.time
	for name in s.get("give", []):
		player.inv.add(Items.ids[name], 20)
	if s.has("item"):   # o item do trecho vai para o slot 0 da hotbar
		player.inv.item[0] = Items.ids[s.item]
		player.inv.count[0] = 1
		player.inv.version += 1
		player.slot = 0
