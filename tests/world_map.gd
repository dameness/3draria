extends SceneTree
# Mapa do mundo inteiro pela geração (sem renderizar): biomas em faixas, oceano, dungeon, Living Trees, minas e ruínas do mar.
#   .tools/godot --headless -s tests/world_map.gd [-- seed]   →   textures/mapa_mundo.png (1 pixel = 4 blocos)

func _initialize() -> void:
	Blocks.load_pack()
	Items.load_pack()
	var args := OS.get_cmdline_user_args()
	var g := WorldGen.new(int(args[0]) if args.size() > 0 else 1337)
	var n := WorldGen.SIZE / 4
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	for pz in n:
		for px in n:
			var x := px * 4
			var z := pz * 4
			var h := g.surface_height(x, z)
			var c := Color("#3f9b3a")
			if g.in_sea(x, z) or h <= WorldGen.WATER_LEVEL:
				c = Color("#1c4f8f").lerp(Color("#0b2a55"), clampf((WorldGen.WATER_LEVEL - h) / 30.0, 0.0, 1.0))
			elif g.evil_weight(x, z) > 0.5:
				c = Color("#6a3a8a") if g.evil == "corruption" else Color("#9a2a2a")
			elif g.hallow_weight(x, z) > 0.5:
				c = Color("#e6a0d8")
			elif g.snow_weight(x, z) > 0.5:
				c = Color("#eef4f8")
			elif g.desert_weight(x, z) > 0.5:
				c = Color("#e0c878")
			elif g.jungle_weight(x, z) > 0.5:
				c = Color("#1f6a2a")
			elif h >= WorldGen.ROCK_LINE:
				c = Color("#8a8a8a")
			img.set_pixel(px, pz, c)
	var mark := func(x: int, z: int, col: Color, r: int):
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var px := x / 4 + dx
				var pz := z / 4 + dz
				if px >= 0 and pz >= 0 and px < n and pz < n:
					img.set_pixel(px, pz, col)
	mark.call(int(WorldGen.CENTER.x), int(WorldGen.CENTER.y), Color.RED, 2)
	mark.call(g.dungeon_x + 30, g.dungeon_z + 25, Color("#2a4fd0"), 3)
	for t in g.living_trees:
		mark.call(t.x, t.z, Color("#ffe000") if t.main else Color("#c8a000"), 1)
	for m in g.mines:
		for k in range(0, m.len, 6):
			mark.call(m.x + (k if m.axis == 0 else 0), m.z + (0 if m.axis == 0 else k), Color.BLACK, 0)
	for cz in WorldGen.SIZE_CHUNKS:
		for cx in WorldGen.SIZE_CHUNKS:
			if g.sea_spot(cx, cz).x >= 0:
				mark.call(cx * 16 + 8, cz * 16 + 8, Color("#ffd000"), 0)
	DirAccess.make_dir_recursive_absolute("res://textures")
	img.save_png("res://textures/mapa_mundo.png")
	print("dungeon em ", g.dungeon_x, ",", g.dungeon_z, " | árvores ", g.living_trees.size(), " | minas ", g.mines.size(), " | evil ", g.evil)
	quit()
