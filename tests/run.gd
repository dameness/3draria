# Testes headless: .tools/godot --headless -s tests/run.gd
# Sai com código != 0 se algum check falhar.
extends SceneTree

const C := WorldGen.CHUNK
const H := WorldGen.HEIGHT
var failures := 0


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		printerr("FALHOU: ", msg)


func _init() -> void:
	check(ProjectSettings.get_setting("rendering/renderer/rendering_method") == "gl_compatibility", "renderer Compatibility")
	var m: Node = load("res://main.tscn").instantiate()
	check(m is Node3D, "main.tscn instancia um Node3D")
	m.free()
	Blocks.load_pack()
	Items.load_pack()
	Crafting.load_pack()
	# Erro de script aborta a função, que então retorna null em vez de true.
	for t in ["test_blocks", "test_atlas", "test_mesher", "test_gen", "test_raycast", "test_player", "test_items", "test_crafting", "test_mining", "test_day_night", "test_combat", "test_drops", "test_save"]:
		check(call(t) == true, t + " terminou sem erro de script")
	# Integração: a cena principal monta todos os chunks no alcance usando as threads.
	main = load("res://main.tscn").instantiate()
	world = main.get_node("World")
	player = main.get_node("Player")
	player.load_save = false
	root.add_child(main)
	started = Time.get_ticks_msec()


# Mundo de teste: 3x3 chunks com chão de pedra até y = 10 (topo em y = 11).
func floor_world() -> Node3D:
	var w: Node3D = load("res://scripts/world.gd").new()
	w.gen = WorldGen.new(1)
	for z in 3:
		for x in 3:
			var d := chunk(0)
			for i in C * C * 11:
				d[i] = Blocks.ids.stone
			w.chunks[Vector2i(x, z)] = d
	return w


func test_raycast():
	var w := floor_world()
	var hit: Dictionary = w.raycast(Vector3(20.5, 15.5, 20.5), Vector3.DOWN, 10)
	check(hit.get("pos") == Vector3i(20, 10, 20) and hit.get("normal") == Vector3i(0, 1, 0), "raio para baixo acerta o topo do chão")
	check(w.raycast(Vector3(20.5, 15.5, 20.5), Vector3.DOWN, 3).is_empty(), "raio curto não alcança")
	w.set_block(24, 12, 20, Blocks.ids.dirt)
	hit = w.raycast(Vector3(20.5, 12.5, 20.5), Vector3(1, 0.1, 0).normalized(), 10)
	check(hit.get("pos") == Vector3i(24, 12, 20) and hit.get("normal") == Vector3i(-1, 0, 0), "raio lateral acerta a face -X")
	check(w.get_block(24, 12, 20) == Blocks.ids.dirt, "set_block grava no chunk")
	w.set_block(16, 12, 20, Blocks.ids.dirt)
	check(w.versions.get(Vector2i(1, 1)) == 2 and w.versions.get(Vector2i(0, 1)) == 1, "editar a borda remonta o vizinho")
	w.free()
	return true


func test_player():
	var w := floor_world()
	var p: Node3D = load("res://scripts/player.gd").new()
	p.world = w
	p.position = Vector3(24.5, 15, 24.5)
	for i in 90:
		p.step(1.0 / 60, Vector3.ZERO, false)
	check(p.on_floor and absf(p.position.y - 11) < 0.01, "cai e para em cima do chão (y=%.3f)" % p.position.y)
	p.step(1.0 / 60, Vector3.ZERO, true)
	var peak := 0.0
	for i in 60:
		p.step(1.0 / 60, Vector3.ZERO, false)
		peak = maxf(peak, p.position.y - 11)
	check(peak > 1.1 and peak < 1.6 and p.on_floor, "pulo sobe ~1,4 bloco e volta ao chão (%.2f)" % peak)
	for y in [11, 12]:
		w.set_block(27, y, 24, Blocks.ids.dirt)
	for i in 60:
		p.step(1.0 / 60, Vector3(1, 0, 0), false)
	check(absf(p.position.x - (27 - 0.3)) < 0.01, "parede de 2 blocos para o jogador (x=%.3f)" % p.position.x)
	check(not p.overlaps_solid(p.position), "jogador nunca fica dentro de bloco")
	p.flying = true
	p.step(1.0, Vector3(1, 0, 0), false)
	check(p.position.x > 28, "voo atravessa blocos")
	p.free()
	w.free()
	return true


# Jogador + entidades fora da árvore de cena, sobre floor_world.
func make_player(w: Node3D) -> Node3D:
	var p: Node3D = load("res://scripts/player.gd").new()
	var ent: Node3D = load("res://scripts/entities.gd").new()
	var clock: Node = load("res://scripts/day_night.gd").new()
	p.world = w
	p.entities = ent
	p.clock = clock
	ent.world = w
	ent.player = p
	ent.clock = clock
	ent.load_defs()
	p.position = Vector3(24.5, 11, 24.5)
	p.spawn = p.position
	return p


func free_player(p: Node3D) -> void:
	p.entities.free()
	p.clock.free()
	p.free()


func enemy_def(n: String) -> Dictionary:
	var ent: Node3D = load("res://scripts/entities.gd").new()
	ent.load_defs()
	var d: Dictionary = ent.defs.filter(func(x): return x.name == n)[0]
	ent.free()
	return d


func run(node: Node, seconds: float) -> void:
	for i in int(seconds * 60):
		if not is_instance_valid(node) or node.is_queued_for_deletion():
			return
		node._physics_process(1.0 / 60)


func test_day_night():
	var c: Node = load("res://scripts/day_night.gd").new()
	c.time = 0
	check(c.clock() == "04:30" and is_equal_approx(c.light(), c.NIGHT_LIGHT), "amanhecer às 4:30, ainda escuro")
	c.time = 600
	check(not c.is_night() and c.light() == 1.0, "meio do dia claro")
	c.time = c.DAY_SECONDS
	check(c.is_night() and c.clock() == "19:30", "noite começa às 19:30")
	check(c.CYCLE == 24 * 60, "ciclo de 24 min")
	c.free()
	return true


func test_combat():
	var w := floor_world()
	var p := make_player(w)
	var ent: Node3D = p.entities
	var z: Node3D = ent.spawn_enemy(enemy_def("zombie"), Vector3(26, 11, 24.5))
	z._ready()
	check(z.hurt(10, Vector3.RIGHT, 0) == 7, "defesa 6 reduz 10 de dano para 7")
	var sword: Dictionary = Items.defs[Items.ids.wooden_sword]
	var eye: Vector3 = p.position + Vector3.UP * p.EYE
	check(p.swing(sword, eye, Vector3.RIGHT) == 1, "espada acerta o zumbi à frente")
	check(p.swing(sword, eye, Vector3.LEFT) == 0, "espada não acerta atrás")
	var hp: int = z.hp
	p.inv.add(Items.ids.wooden_arrow, 2)
	p.shoot(Items.defs[Items.ids.wooden_bow], eye, Vector3.RIGHT)
	var arrow: Node = ent.get_children().back()
	run(arrow, 1.0)
	check(z.hp == hp - (4 + 5 - 3) and p.inv.total(Items.ids.wooden_arrow) == 1, "flecha gasta munição e fere com arco + flecha − defesa")
	run(z, 1.0)
	check(p.hp < p.MAX_HP, "zumbi anda até o jogador e causa dano ao encostar")
	var after: float = p.hp
	z._physics_process(1.0 / 60)
	check(p.hp == after, "invencibilidade após levar dano")
	ent.remove_enemy(z)
	var s: Node3D = ent.spawn_enemy(enemy_def("green_slime"), Vector3(32.5, 11, 24.5))
	s._ready()
	var d0: float = s.position.distance_to(p.position)
	run(s, 4.0)
	check(s.position.distance_to(p.position) < d0 - 2, "slime pula na direção do jogador")
	s.hurt(100, Vector3.RIGHT, 0)
	check(not ent.enemies.has(s) and ent.get_children().any(func(n): return n.get("item") == Items.ids.gel), "slime morto some e dropa gel")
	var e: Node3D = ent.spawn_enemy(enemy_def("demon_eye"), Vector3(24.5, 18, 34.5))
	e._ready()
	d0 = e.position.distance_to(p.position)
	run(e, 2.0)
	check(e.position.distance_to(p.position) < d0 - 3, "olho demoníaco voa até o jogador")
	p.iframes = 0
	p.hurt(1000, Vector3.RIGHT)
	check(p.hp == p.MAX_HP and p.position == p.spawn, "morrer renasce no spawn com vida cheia")
	free_player(p)
	w.free()
	return true


func test_drops():
	var w := floor_world()
	var p := make_player(w)
	var d: Node3D = p.entities.spawn_drop(Items.ids.dirt, 3, p.position + Vector3(2, 0.5, 0))
	d._ready()
	check(Items.rarity_color(Items.ids.dirt) == Color.WHITE, "raridade 0 = feixe branco")
	run(d, 2.0)
	check(p.inv.total(Items.ids.dirt) == 3 and d.is_queued_for_deletion(), "item solto é puxado e coletado")
	var far: Node3D = p.entities.spawn_drop(Items.ids.dirt, 1, p.position + Vector3(8, 3, 0))
	far._ready()
	run(far, 2.0)
	check(not far.is_queued_for_deletion() and absf(far.position.y - 11) < 0.01, "item longe cai e fica no chão")
	free_player(p)
	w.free()
	return true


func test_save():
	var path := "user://test_save.dat"
	var w := floor_world()
	var p := make_player(w)
	w.set_block(20, 11, 20, Blocks.ids.dirt)
	p.inv.add(Items.ids.iron_pickaxe, 1)
	p.inv.add(Items.ids.stone, 42)
	p.hp = 37
	p.position = Vector3(21.5, 11, 22.5)
	p.clock.time = 123.0
	check(SaveGame.save(w, p, p.clock, path) == OK, "salvar")
	var w2 := floor_world()
	var p2 := make_player(w2)
	check(SaveGame.load_into(w2, p2, p2.clock, path), "carregar")
	check(w2.get_block(20, 11, 20) == Blocks.ids.dirt and w2.world_seed == w.world_seed, "bloco editado volta")
	check(p2.inv.total(Items.ids.stone) == 42 and p2.inv.total(Items.ids.iron_pickaxe) == 1, "inventário volta")
	check(p2.hp == 37 and p2.position == p.position and p2.clock.time == 123.0, "vida, posição e hora voltam")
	DirAccess.remove_absolute(path)
	free_player(p)
	free_player(p2)
	w.free()
	w2.free()
	return true


func test_items():
	check(Items.places[Items.ids.stone] == Blocks.ids.stone, "bloco vira item que o coloca")
	check(Items.drop[Blocks.ids.grass] == Items.ids.dirt, "grama dropa terra")
	check(Items.drop[Blocks.ids.leaves] == -1 and Items.drop[Blocks.ids.bedrock] == -1, "folha e bedrock não dropam")
	check([Items.pick_power[Items.ids.copper_pickaxe], Items.pick_power[Items.ids.iron_pickaxe], Items.pick_power[Items.ids.gold_pickaxe]] == [35, 40, 55], "poder das picaretas como no Terraria (35/40/55)")
	var inv := Inventory.new()
	check(inv.add(Items.ids.dirt, 15000) == 0 and inv.item[0] == Items.ids.dirt and inv.count[0] == 9999 and inv.count[1] == 5001, "empilha até o limite")
	check(inv.add(Items.ids.copper_pickaxe, 2) == 0 and inv.count[2] == 1 and inv.count[3] == 1, "picareta não empilha")
	inv.remove(Items.ids.dirt, 6000)
	check(inv.total(Items.ids.dirt) == 9000, "remove tira a quantidade certa")
	check(inv.add(Items.ids.stone, 9999 * 40) > 0, "inventário cheio devolve o que sobrou")
	return true


func test_crafting():
	var by_result := {}
	for r in Crafting.recipes:
		by_result[Items.names[r.result]] = r
	var inv := Inventory.new()
	inv.add(Items.ids.wood, 20)
	check(Crafting.craft(by_result.workbench, inv, {}), "bancada sem estação")
	check(inv.total(Items.ids.wood) == 10 and inv.total(Items.ids.workbench) == 1, "criar consome ingredientes e dá o item")
	inv.add(Items.ids.stone, 20)
	inv.add(Items.ids.gel, 1)
	check(Crafting.craft(by_result.torch, inv, {}) and inv.total(Items.ids.torch) == 3, "tocha: 1 gel + 1 madeira = 3")
	inv.add(Items.ids.wood, 1)
	check(not Crafting.craft(by_result.furnace, inv, {}), "fornalha exige bancada por perto")
	var w := floor_world()
	w.set_block(22, 11, 20, Blocks.ids.workbench)
	var st := Crafting.stations_near(w, Vector3(20.5, 11, 20.5))
	check(st.has(Blocks.ids.workbench) and Crafting.craft(by_result.furnace, inv, st), "bancada no mundo libera a fornalha")
	check(Crafting.stations_near(w, Vector3(30.5, 11, 20.5)).is_empty(), "estação longe não conta")
	w.free()
	# Cadeia completa até a picareta de ferro.
	inv.add(Items.ids.iron_ore, 51)
	inv.add(Items.ids.wood, 3)
	var all := {Blocks.ids.workbench: true, Blocks.ids.furnace: true, Blocks.ids.anvil: true}
	for i in 15:
		Crafting.craft(by_result.iron_bar, inv, all)
	check(Crafting.craft(by_result.anvil, inv, all) and Crafting.craft(by_result.iron_pickaxe, inv, all), "minério → barra → bigorna → picareta de ferro")
	return true


func test_mining():
	var w := floor_world()
	var p := make_player(w)
	p.target = {"pos": Vector3i(20, 10, 20), "normal": Vector3i(0, 1, 0)}
	w.set_block(20, 10, 20, Blocks.ids.gold_ore)
	# Ouro não tem tier no Terraria; o teste dá poder 40 a ele só para exercitar o bloqueio.
	var saved_power := Blocks.power[Blocks.ids.gold_ore]
	Blocks.power[Blocks.ids.gold_ore] = 40
	p.break_target()
	check(w.get_block(20, 10, 20) == Blocks.ids.gold_ore, "sem picareta não minera")
	p.inv.add(Items.ids.copper_pickaxe, 1)
	p.break_target()
	check(w.get_block(20, 10, 20) == Blocks.ids.gold_ore and p.message.contains("40"), "cobre não minera ouro e avisa o poder")
	p.inv.add(Items.ids.iron_pickaxe, 1)
	p.slot = 1
	p.break_target()
	var drops: Array = p.entities.get_children().filter(func(n): return n.get("item") == Items.ids.gold_ore)
	check(w.get_block(20, 10, 20) == 0 and drops.size() == 1, "ferro minera ouro e o drop cai no chão")
	p.inv.add(Items.ids.gold_ore, 1)
	p.slot = 2
	p.target = {"pos": Vector3i(20, 10, 21), "normal": Vector3i(0, 1, 0)}
	p.position = Vector3(25.5, 11, 25.5)
	p.place_target()
	check(w.get_block(20, 11, 21) == Blocks.ids.gold_ore and p.inv.total(Items.ids.gold_ore) == 0, "colocar usa o item da mão")
	Blocks.power[Blocks.ids.gold_ore] = saved_power
	free_player(p)
	w.free()
	return true


var main: Node
var world: Node3D
var player: Node3D
var started := 0
var edited := false
var edit_mesh_id := 0
var edit_faces := 0


func _process(_delta: float) -> bool:
	var done = integration()
	if done == null:
		check(false, "integração terminou sem erro de script")
	elif not done:
		return false
	main.free()
	print("OK" if failures == 0 else "%d falha(s)" % failures)
	quit(1 if failures else 0)
	return true


# Retorna false enquanto espera, true quando terminou (null se der erro de script).
func integration():
	var elapsed := Time.get_ticks_msec() - started
	if world == null:
		check(false, "cena principal não carregou")
	elif world.center.x < 0 or not world.is_idle():
		if elapsed < 60000:
			return false
		check(false, "mundo não terminou de carregar em 60 s")
	else:
		var r: int = world.render_distance
		var expected := 0
		for z in range(world.center.y - r, world.center.y + r + 1):
			for x in range(world.center.x - r, world.center.x + r + 1):
				var k := Vector2i(x, z)
				expected += int(world.in_world(k) and (k - world.center).length_squared() <= r * r)
		check(world.meshes.size() == expected, "mundo: %d de %d chunks montados" % [world.meshes.size(), expected])
		var with_mesh: int = world.meshes.values().filter(func(m): return m != null).size()
		check(with_mesh == expected, "todo chunk no alcance tem faces visíveis")
		if not edited:
			edited = true
			print("mundo: %d chunks em %d ms com %d threads" % [expected, elapsed, world.max_jobs])
			check(player.on_floor, "jogador nasce e fica no chão")
			# Quebra o bloco sob o jogador pela mira e espera a mesh ser refeita.
			var k: Vector2i = world.center
			edit_mesh_id = world.meshes[k].get_instance_id()
			edit_faces = world.meshes[k].mesh.surface_get_array_len(0)
			player.cam.rotation.x = -PI / 2
			player._process(0)
			var below := Vector3i(player.position.floor()) - Vector3i(0, 1, 0)
			check(player.target.get("pos") == below, "mira olhando para baixo acerta o bloco sob os pés")
			player.break_target()
			check(world.get_block(below.x, below.y, below.z) == 0, "quebrar tira o bloco com a picareta inicial")
			player.inventory_open = true  # exercita a janela de inventário/criação
			return false
		if player.inv.total(Items.ids.dirt) == 0 and elapsed < 60000:
			return false  # espera o drop de terra ser coletado
		var m: MeshInstance3D = world.meshes[world.center]
		check(m.get_instance_id() != edit_mesh_id and m.mesh.surface_get_array_len(0) != edit_faces, "mesh do chunk editado foi refeita")
	return true


func test_blocks():
	check(Blocks.ids.air == 0 and not Blocks.solid[0], "id 0 é ar")
	check(Blocks.tiles.size() == Blocks.ids.size() * Blocks.FACES, "6 tiles por bloco")
	var g: int = Blocks.ids.grass
	check(Blocks.tiles[g * 6 + 2] != Blocks.tiles[g * 6 + 0], "grama: topo difere do lado")
	return true


func test_atlas():
	var img := Atlas.build(Blocks.textures)
	check(img.get_size() == Vector2i(16 * Blocks.textures.size(), 16), "atlas: uma fileira de tiles 16x16")
	DirAccess.make_dir_recursive_absolute("res://textures")
	check(img.save_png("res://textures/atlas.png") == OK, "atlas salvo em textures/atlas.png")
	return true


func chunk(fill: int) -> PackedByteArray:
	var d := PackedByteArray()
	d.resize(C * C * H)
	d.fill(fill)
	return d


func faces(arrays: Array) -> int:
	return 0 if arrays.is_empty() else arrays[Mesh.ARRAY_VERTEX].size() / 4


func test_mesher():
	var n := Blocks.textures.size()
	var stone := chunk(Blocks.ids.stone)
	check(faces(ChunkMesher.build(stone, [stone, stone, stone, stone], n)) == C * C, "chunk sólido cercado: só as 256 faces do topo")
	check(faces(ChunkMesher.build(stone, [PackedByteArray(), stone, stone, stone], n)) == C * C + C * H, "borda do mundo mostra a parede")
	var air := chunk(0)
	var nb := [air, air, air, air]
	check(ChunkMesher.build(air, nb, n).is_empty(), "chunk vazio não gera mesh")
	air[3 + 4 * C + 10 * C * C] = Blocks.ids.dirt
	var a := ChunkMesher.build(air, nb, n)
	check(faces(a) == 6, "bloco isolado: 6 faces")
	# Godot desenha a frente dos triângulos em sentido horário: cross(v1-v0, v2-v0) aponta para dentro.
	var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var nr: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
	var ix: PackedInt32Array = a[Mesh.ARRAY_INDEX]
	var wound := true
	for t in range(0, ix.size(), 3):
		wound = wound and (v[ix[t + 1]] - v[ix[t]]).cross(v[ix[t + 2]] - v[ix[t]]).dot(nr[ix[t]]) < 0
	check(wound, "triângulos em sentido horário visto de fora")
	air[4 + 4 * C + 10 * C * C] = Blocks.ids.dirt
	check(faces(ChunkMesher.build(air, nb, n)) == 10, "dois blocos vizinhos escondem a face em comum")
	return true


func test_gen():
	var gen := WorldGen.new(42)
	var t := Time.get_ticks_usec()
	var d := gen.generate(8, 8)
	var gen_ms := (Time.get_ticks_usec() - t) / 1000.0
	check(d == WorldGen.new(42).generate(8, 8), "geração determinística por seed")
	check(d != WorldGen.new(43).generate(8, 8), "seed diferente muda o mundo")
	check(d.size() == C * C * H, "chunk tem 16x16xALTURA blocos")
	var at := func(x, y, z): return d[x + z * C + y * C * C]
	var h := gen.surface_height(8 * C + 5, 8 * C + 5)
	check(at.call(5, h, 5) == gen.GRASS and at.call(5, h + 1, 5) == 0, "superfície: grama no topo, ar acima")
	check(at.call(5, 0, 5) == gen.BEDROCK, "fundo: bedrock")
	var count := {}
	for y in H:
		var layer := "submundo" if y < WorldGen.UNDERWORLD_TOP else "cavernas" if y < WorldGen.CAVERN_TOP else "subterrâneo"
		for i in C * C:
			var k := "%s:%d" % [layer, d[i + y * C * C]]
			count[k] = count.get(k, 0) + 1
	check(count.has("submundo:%d" % gen.ASH) and count.has("submundo:0"), "submundo: cinza com espaço aberto")
	check(count.get("cavernas:%d" % gen.STONE, 0) > count.get("cavernas:%d" % gen.DIRT, 0), "cavernas: pedra predomina")
	check(count.has("cavernas:0"), "cavernas: há cavernas")
	check(count.get("subterrâneo:%d" % gen.DIRT, 0) > count.get("subterrâneo:%d" % gen.STONE, 0), "subterrâneo: terra predomina")
	var found := {}
	for c in 4:
		var cd := gen.generate(c, 3)
		for i in cd.size():
			found[cd[i]] = mini(found.get(cd[i], 999), i / (C * C))  # menor y de cada bloco
	for o in gen.ores:
		check(found.has(o.block) and found[o.block] >= o.min_y, "minério %s aparece a partir de y=%d" % [Blocks.ids.keys()[o.block], o.min_y])
	check(found.has(gen.WOOD) and found.has(gen.LEAVES), "há árvores")
	var nb := [gen.generate(9, 8), gen.generate(7, 8), gen.generate(8, 9), gen.generate(8, 7)]
	t = Time.get_ticks_usec()
	ChunkMesher.build(d, nb, Blocks.textures.size())
	print("chunk: geração %.1f ms, mesh %.1f ms" % [gen_ms, (Time.get_ticks_usec() - t) / 1000.0])
	return true
