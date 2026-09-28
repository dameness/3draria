extends SceneTree
# Prints do jogo renderizado de verdade (OpenGL por software), para conferir o visual sem GPU:
#   xvfb-run -a -s "-screen 0 1280x720x24" .tools/godot -s tests/screenshot.gd
# Salva textures/shot_*.png (fora do git). Cada cena: posição/olhar do jogador, hora, item na mão, inventário.

const SHOTS := [
	{"name": "spawn", "look": Vector2(0, -0.15)},
	{"name": "terra_blade", "item": "terra_blade", "look": Vector2(0.8, -0.1), "swing": 0.12},
	{"name": "alto", "up": 30.0, "look": Vector2(0.6, -0.6)},
	{"name": "noite", "time": 1100.0, "look": Vector2(2.0, -0.1), "item": "enchanted_sword"},
	{"name": "inventario", "inventory": true, "look": Vector2(0, -0.2)},
	{"name": "inimigos", "look": Vector2(0, -0.1), "enemies": ["green_slime", "zombie", "demon_eye"]},
	{"name": "3a_pessoa", "third": true, "look": Vector2(0.4, -0.25), "item": "terra_blade", "armor": ["gold_helmet", "gold_chainmail", "gold_greaves"]},
	{"name": "3a_pessoa_golpe", "third": true, "look": Vector2(-0.6, -0.15), "item": "platinum_broadsword", "swing": 0.1, "armor": ["platinum_helmet", "platinum_chainmail", "platinum_greaves"]},
	{"name": "chefe", "time": 1100.0, "look": Vector2(0, 0.25), "boss": "eye_of_cthulhu", "item": "terra_blade"},
]

var main: Node
var world: Node3D
var player: Node3D
var shot := 0
var wait := 0


func _initialize() -> void:
	main = load("res://game.tscn").instantiate()
	world = main.get_node("World")
	player = main.get_node("Player")
	root.add_child(main)
	DirAccess.make_dir_recursive_absolute("res://textures")


func _process(_delta: float) -> bool:
	if not world.is_idle() or world.center.x < 0:
		return false
	if wait == 0:
		_setup(SHOTS[shot])
	wait += 1
	if wait < 20:  # deixa o mundo remontar, a câmera assentar e o efeito aparecer
		if SHOTS[shot].has("swing") and wait > 12:
			player.cooldown = SHOTS[shot].swing
		return false
	var img := root.get_texture().get_image()
	img.save_png("res://textures/shot_%s.png" % SHOTS[shot].name)
	print("salvo textures/shot_%s.png" % SHOTS[shot].name)
	shot += 1
	wait = 0
	if shot >= SHOTS.size():
		quit()
		return true
	return false


func _setup(s: Dictionary) -> void:
	player.flying = s.has("up")
	player.position = player.spawn + Vector3.UP * s.get("up", 0.0)
	player.rotation.y = s.look.x
	player.pitch = s.look.y
	player.cam.rotation.x = s.look.y
	player.get_node("../DayNight").time = s.get("time", 300.0)
	player.inventory_open = s.get("inventory", false)
	player.inv.add(Items.ids.wood, 25)
	player.inv.add(Items.ids.stone, 40)
	var ent: Node3D = main.get_node("Entities")
	for e in ent.enemies.duplicate():
		ent.remove_enemy(e)
	ent.spawn_timer = 999.0  # sem spawns aleatórios no print
	var fwd := Vector3(-sin(s.look.x), 0, -cos(s.look.x))
	var side := fwd.cross(Vector3.UP)
	var i := 0
	for n in s.get("enemies", []):
		var pos: Vector3 = player.position + fwd * 7 + side * (i - 1) * 2.5
		pos.y = world.surface_y(int(pos.x), int(pos.z)) + (2.5 if n == "demon_eye" else 0.0)
		var e: Node3D = ent.spawn_enemy(ent.def_named(n), pos)
		e.set_physics_process(false)
		i += 1
	if s.has("boss"):
		var b: Node3D = ent.spawn_boss(s.boss)
		b.position = player.position + fwd * 12 + Vector3.UP * 5
		b.set_physics_process(false)
	player.third_person = s.get("third", false)
	for n in s.get("armor", []):
		player.inv.add(Items.ids[n], 1)
		player.inv.equip_from(player.inv.item.find(Items.ids[n]))
	if s.has("item"):
		player.inv.add(Items.ids[s.item], 1)
		player.slot = player.inv.item.find(Items.ids[s.item])
	else:
		player.slot = 0
