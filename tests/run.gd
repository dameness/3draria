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
	# Erro de script aborta a função, que então retorna null em vez de true.
	for t in ["test_blocks", "test_atlas", "test_mesher", "test_gen", "test_raycast", "test_player"]:
		check(call(t) == true, t + " terminou sem erro de script")
	# Integração: a cena principal monta todos os chunks no alcance usando as threads.
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	world = main.get_node("World")
	player = main.get_node("Player")
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
			check(world.get_block(below.x, below.y, below.z) == 0, "quebrar tira o bloco")
			return false
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
	var nb := [gen.generate(9, 8), gen.generate(7, 8), gen.generate(8, 9), gen.generate(8, 7)]
	t = Time.get_ticks_usec()
	ChunkMesher.build(d, nb, Blocks.textures.size())
	print("chunk: geração %.1f ms, mesh %.1f ms" % [gen_ms, (Time.get_ticks_usec() - t) / 1000.0])
	return true
