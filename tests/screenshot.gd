extends SceneTree
# Prints do jogo renderizado de verdade (OpenGL por software), para conferir o visual sem GPU:
#   xvfb-run -a -s "-screen 0 1280x720x24" .tools/godot -s tests/screenshot.gd
# Salva textures/shot_*.png (fora do git). Cada cena: posição/olhar do jogador, hora, item na mão, inventário.
# Só algumas cenas: acrescente `-- parte_do_nome ...` (ex.: `-- ceu noite`). "aim": "sun"|"moon" mira o astro.

const SHOTS := [
	{"name": "spawn", "look": Vector2(0, -0.15)},
	{"name": "terra_blade", "item": "terra_blade", "look": Vector2(0.8, -0.1), "swing": 0.12},
	{"name": "alto", "up": 30.0, "look": Vector2(0.6, -0.6)},
	{"name": "noite", "time": 1100.0, "look": Vector2(2.0, -0.1), "item": "enchanted_sword"},
	{"name": "inventario", "inventory": true, "look": Vector2(0, -0.2)},
	{"name": "inventario_cheio", "inventory": true, "look": Vector2(0, -0.2), "gear": true, "hp": 22},
	{"name": "bau", "inventory": true, "look": Vector2(0, -0.2), "gear": true, "chest": true},
	{"name": "mal", "evil": true, "up": 14.0, "look": Vector2(0.4, -0.45), "flying": true},
	{"name": "abismo", "evil": "chasm", "look": Vector2(0.3, -1.2), "flying": true},
	{"name": "verme", "evil": true, "up": 4.0, "look": Vector2(0, -0.1), "worm": true, "flying": true},
	{"name": "inimigos", "look": Vector2(0, -0.1), "enemies": ["green_slime", "zombie", "demon_eye"], "numbers": true},
	{"name": "slime", "look": Vector2(0, -0.35), "enemies": ["green_slime", "blue_slime"], "item": "wooden_sword"},
	{"name": "minera", "look": Vector2(0.5, -0.5), "item": "copper_pickaxe", "mine": 1, "mine_late": true},
	{"name": "minera_pedra", "look": Vector2(0.5, -0.5), "item": "copper_pickaxe", "block": "stone", "mine": 1, "mine_late": true},
	{"name": "arco", "look": Vector2(0.8, -0.1), "item": "iron_broadsword", "arc": true},
	{"name": "arco_3a", "third": true, "look": Vector2(-0.6, -0.15), "item": "iron_broadsword", "arc": true},
	{"name": "particulas", "look": Vector2(0, -0.1), "fx": true},
	{"name": "golpe_slime", "look": Vector2(0, -0.3), "enemies": ["green_slime"], "item": "wooden_sword", "hurt_late": true},
	{"name": "flash", "look": Vector2(0, -0.1), "enemies": ["green_slime", "zombie", "demon_eye"], "hurt": true},
	{"name": "3a_pessoa", "third": true, "look": Vector2(0.4, -0.25), "item": "terra_blade", "armor": ["gold_helmet", "gold_chainmail", "gold_greaves"]},
	{"name": "3a_pessoa_golpe", "third": true, "look": Vector2(-0.6, -0.15), "item": "platinum_broadsword", "swing": 0.1, "armor": ["platinum_helmet", "platinum_chainmail", "platinum_greaves"]},
	{"name": "caverna", "cave": true, "look": Vector2(0.3, -0.25), "item": "copper_pickaxe"},
	{"name": "noite_tochas", "time": 1100.0, "torches": true, "look": Vector2(0, -0.3), "third": true},
	{"name": "chefe", "time": 1100.0, "look": Vector2(0, 0.25), "boss": "eye_of_cthulhu", "item": "terra_blade"},
	{"name": "chefe_fase2", "time": 1100.0, "look": Vector2(0, 0.25), "boss": "eye_of_cthulhu", "phase2": true, "third": true},
	{"name": "lago", "find": "water", "at": Vector3(14, 5, 0), "look": Vector2(PI / 2, -0.3)},
	{"name": "respingo", "find": "water", "find_y": 70, "at": Vector3(-5, 5.5, 0), "look": Vector2(-PI / 2, -0.35), "splash": true},
	{"name": "agua", "find": "water", "find_y": 66, "at": Vector3(0, 2.3, 0), "look": Vector2(PI / 2, 0.1), "flying": true},
	{"name": "escoa", "find": "water", "find_y": 70, "at": Vector3(-6, 4, 0), "look": Vector2(-PI / 2, -0.4), "flying": true, "breach": 8, "flow": 14},
	{"name": "escoa_depois", "find": "water", "find_y": 70, "at": Vector3(-6, 4, 0), "look": Vector2(-PI / 2, -0.4), "flying": true, "breach": 8, "flow": 60},
	{"name": "submundo", "find": "lava", "find_y": 4, "at": Vector3(6, 6, 0), "look": Vector2(PI / 2, -0.25), "flying": true},
	{"name": "ceu_manha", "time": 25.0, "look": Vector2.ZERO, "aim": "sun", "tilt": -0.12},
	{"name": "ceu_por_do_sol", "time": 850.0, "look": Vector2.ZERO, "aim": "sun", "tilt": -0.08},
	{"name": "ceu_lua", "time": 1000.0, "look": Vector2.ZERO, "aim": "moon", "tilt": -0.1},
]

var shots := []
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
	var only := Array(OS.get_cmdline_user_args())
	shots = SHOTS.filter(func(s): return only.is_empty() or only.any(func(o): return s.name.contains(o)))


func _process(_delta: float) -> bool:
	if not world.is_idle() or world.center.x < 0:
		return false
	if wait == 0:
		_setup(shots[shot])
	wait += 1
	if wait < 20:  # deixa o mundo remontar, a câmera assentar e o efeito aparecer
		if shots[shot].has("swing") and wait > 12:
			player.cooldown = shots[shot].swing
		if shots[shot].get("mine_late", false) and wait == 16:   # mais um golpe pouco antes do print: rachaduras e poeira no ar
			player.break_target()
		if shots[shot].get("hurt_late", false) and wait == 18:
			for e in main.get_node("Entities").enemies:
				e.hurt(2, player.position - e.position, 3.0)
		if shots[shot].get("arc", false) and wait == 19:   # um golpe inteiro de uma vez (o print roda a poucos quadros por segundo)
			var hand: Node3D = player.get_node("Camera/Hand")
			var model: Node3D = player.get_node("Model")
			var use: float = Items.defs[player.held()].use_time
			for i in 10:
				player.cooldown = use * (1.0 - 0.75 * i / 9.0)
				if player.third_person:
					model._process(0.016)
				else:
					hand._process(0.016)
		if shots[shot].get("fx", false) and wait == 19:   # um de cada tipo, em fileira à frente da câmera
			var ent: Node3D = main.get_node("Entities")
			var fwd := Vector3(-sin(player.rotation.y), 0, -cos(player.rotation.y))
			var right := fwd.cross(Vector3.UP)
			var base: Vector3 = player.position + fwd * 3.2 + Vector3.UP * 0.6
			var kinds := [["dust", Color("#8a6a48")], ["chips", Color("#8a6a48")], ["sparks", Color("#ffd060")], ["blood", Color("#a01818")], ["puff", Color("#5f8a5a")], ["splash", Color.WHITE], ["bubbles", Color.WHITE]]
			for k in kinds.size():
				var at: Vector3 = base + right * (k - 3) * 0.75
				match kinds[k][0]:
					"dust": Fx.dust(ent, at, kinds[k][1], 8)
					"chips": Fx.chips(ent, at, kinds[k][1], 12)
					"sparks": Fx.sparks(ent, at, kinds[k][1], 8)
					"blood": Fx.blood(ent, at, kinds[k][1], 10)
					"puff": Fx.puff(ent, at, kinds[k][1], 14)
					"splash": Fx.splash(ent, at, 16)
					"bubbles": Fx.bubbles(ent, at, 6)
		if shots[shot].get("splash", false) and wait == 12:
			player.flying = false
			player.velocity = Vector3(0, -8, 0)
		if shots[shot].get("numbers", false) and wait == 15:  # números de dano no ar (duram menos de 1 s)
			for e in main.get_node("Entities").enemies:
				main.get_node("Entities").spawn_text(e.position + Vector3.UP * (e.tall + 0.3), str(23), Color("#ffa050"))
		return false
	main.get_node("HUD").item_until = Time.get_ticks_msec() + 5000   # o nome do item some em 2 s; aqui fica
	var img := root.get_texture().get_image()
	img.save_png("res://textures/shot_%s.png" % shots[shot].name)
	print("salvo textures/shot_%s.png" % shots[shot].name)
	shot += 1
	wait = 0
	if shot >= shots.size():
		quit()
		return true
	return false


func _setup(s: Dictionary) -> void:
	player.flying = s.has("up") or s.has("cave") or s.get("flying", false)
	player.position = player.spawn + Vector3.UP * s.get("up", 0.0)
	if s.has("find"):  # junto do bloco pedido (água, lava) mais perto do meio do mundo
		var best := Vector3i.ZERO
		var bd := 1 << 40
		for z in range(40, 216, 2):
			for x in range(40, 216, 2):
				var d := (x - 128) * (x - 128) + (z - 128) * (z - 128)
				if d < bd and world.get_block(x, s.get("find_y", WorldGen.WATER_LEVEL), z) == Blocks.ids[s.find]:
					bd = d
					best = Vector3i(x, s.get("find_y", WorldGen.WATER_LEVEL), z)
		player.position = Vector3(best) + Vector3(0.5, 0, 0.5) + s.at
		print("  ", s.name, " em ", player.position)
		if s.has("breach"):   # abre um canal de `breach` blocos para o lado (+X) a partir da borda do lago, com uma cova no fim, e deixa fluir
			var x := best.x
			while world.get_block(x, best.y, best.z) == Blocks.ids.water:
				x += 1
			for i in range(s.breach):
				world.set_block(x + i, best.y, best.z, 0)
			for dy in range(1, 5):
				world.set_block(x + s.breach - 1, best.y - dy, best.z, 0)
			world.liquid.settle(world, s.get("flow", 10))
	if s.has("evil"):   # bioma do mal: acima do centro, ou dentro do 1º abismo
		var g: WorldGen = world.gen
		var at := Vector2i(g.evil_center)
		if s.evil is String:
			var o: Vector3i = g.chasm_orb(0)
			player.position = Vector3(o.x + 0.5, o.y + 24, o.z + 0.5)
		else:
			player.position = Vector3(at.x + 0.5, world.surface_y(at.x, at.y) + s.get("up", 0.0), at.y + 0.5)
		print("  ", s.name, " ", g.evil, " em ", player.position)
	var sp := Vector3i(player.spawn.floor())
	if s.get("cave", false):  # sala escavada 12 blocos abaixo, com tochas no chão
		for x in range(-5, 6):
			for z in range(-7, 5):
				for y in range(0, 5):
					world.set_block(sp.x + x, sp.y - 14 + y, sp.z + z, 0)
		for t in [Vector3i(-4, 0, -6), Vector3i(4, 0, -6), Vector3i(0, 0, -2)]:
			world.set_block(sp.x + t.x, sp.y - 14, sp.z + t.z, Blocks.ids.torch)
		player.position = Vector3(sp.x + 0.5, sp.y - 14, sp.z + 3.5)
	if s.get("torches", false):
		for t in [Vector3i(-2, 0, -4), Vector3i(3, 0, -5), Vector3i(0, 0, -9)]:
			var y: int = world.surface_y(sp.x + t.x, sp.z + t.z)
			world.set_block(sp.x + t.x, y, sp.z + t.z, Blocks.ids.torch)
	player.rotation.y = s.look.x
	player.pitch = s.look.y
	player.cam.rotation.x = s.look.y
	var clock: Node = player.get_node("../DayNight")
	clock.time = s.get("time", 300.0)
	if s.has("aim"):
		var sd: Vector3 = clock.sun_dir() * (1.0 if s.aim == "sun" else -1.0)
		player.rotation.y = atan2(-sd.x, -sd.z)
		player.pitch = asin(sd.y) + s.get("tilt", 0.0)
		player.cam.rotation.x = player.pitch
	player.inventory_open = s.get("inventory", false)
	if s.get("gear", false):   # moedas, munição, acessórios e um favorito, para a GUI do inventário
		player.inv.add(Items.ids.copper_coin, 37)
		player.inv.add(Items.ids.gold_coin, 4)
		player.inv.add(Items.ids.platinum_coin, 1)
		player.inv.ammo[0] = Items.ids.wooden_arrow
		player.inv.ammo_count[0] = 120
		player.inv.acc[0] = Items.ids.hermes_boots
		player.inv.acc[1] = Items.ids.band_of_regeneration
		player.inv.add(Items.ids.iron_pickaxe, 1)
		player.inv.add(Items.ids.torch, 40)
		player.inv.add(Items.ids.gold_bar, 12)
		player.inv.fav[3] = 1
	player.hp = s.get("hp", 100)
	if s.get("chest", false):
		var c: Dictionary = world.chest_at(Vector3i(1, 2, 3))
		main.get_node("HUD").open_chest(c)
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
		var pos: Vector3 = player.position + fwd * 6 + side * (i - (s.enemies.size() - 1) / 2.0) * 2.2
		pos.y = world.surface_y(int(pos.x), int(pos.z)) + (2.5 if n == "demon_eye" else 0.0)
		var e: Node3D = ent.spawn_enemy(ent.def_named(n), pos)
		e.set_physics_process(false)
		if s.get("hurt", false):   # o clarão vermelho do golpe, congelado para o print
			e.hurt(1, Vector3.ZERO, 0)
			e.flash = 99.0
		i += 1
	if s.get("worm", false):
		var w: Node3D = ent.spawn_worm(ent.def_named("eater_of_worlds"), player.position + fwd * 10 + Vector3.UP * 1.0)
		for e in ent.enemies:
			e.set_physics_process(false)
		# dobra a fila em S para o print mostrar as juntas
		var k := 0
		for e in ent.enemies:
			e.position = w.position - fwd * 1.15 * k + side * sin(k * 0.45) * 3.0 + Vector3.UP * (1.0 + sin(k * 0.3))
			k += 1
			if e.follow:
				e.velocity = Vector3.ZERO
	if s.has("boss"):
		var b: Node3D = ent.spawn_boss(s.boss)
		b.position = player.position + fwd * 12 + Vector3.UP * 5
		b.set_physics_process(false)
		if s.get("phase2", false):
			EnemyModel.set_phase(b.model, 2)
	player.third_person = s.get("third", false)
	for n in s.get("armor", []):
		player.inv.add(Items.ids[n], 1)
		player.inv.equip_from(player.inv.item.find(Items.ids[n]))
	if s.has("item"):
		player.inv.add(Items.ids[s.item], 1)
		player.slot = player.inv.item.find(Items.ids[s.item])
	else:
		player.slot = 0
	if s.has("mine"):   # um bloco à frente, na mira, já com `mine` golpes
		player.pitch = -0.75
		player.cam.rotation.x = -0.75
		player._process(0.0)
		if s.has("block") and not player.target.is_empty():
			var t: Vector3i = player.target.pos
			world.set_block(t.x, t.y, t.z, Blocks.ids[s.block])
			player._process(0.0)
		for _hit in s.mine:
			player.break_target()
