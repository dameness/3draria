extends Node3D
# Guarda os chunks do mundo finito e mantém malhas só dentro da distância de renderização.
# Geração (um job por chunk, uma vez só) e mesh (um job por chunk, com os vizinhos já prontos) rodam no
# WorkerThreadPool; cada job lê só a sua cópia dos chunks e a thread principal grava o resultado em `chunks`.

const C := WorldGen.CHUNK
const H := WorldGen.HEIGHT
const NB: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]  # ordem do ChunkMesher

@export var render_distance := 6  # em chunks; teclas + e - mudam em jogo
@export var world_seed := 1337

var gen: WorldGen
var liquid := Liquid.new()   # água e lava fluindo (liquid.gd)
var chunks := {}   # Vector2i -> PackedByteArray
var meshes := {}   # Vector2i -> MeshInstance3D, ou null (sem faces / em construção)
var material := ShaderMaterial.new()   # shaders/chunk.gdshader: atlas × luz do céu/tochas
var water_material := ShaderMaterial.new()   # shaders/water.gdshader: superfície translúcida da água
var atlas_texture: ImageTexture
var pending: Array[Vector2i] = []   # chunks no alcance que ainda esperam a mesh (o mais perto no fim)
var meshable: Array[Vector2i] = []     # desses, os que já têm dados (e os dos vizinhos) e podem virar mesh
var need_gen: Array[Vector2i] = []  # chunks a gerar para os pending (o mais perto no fim)
var urgent: Array[Vector2i] = []   # chunks editados que precisam de mesh nova
var chests := {}    # Vector3i -> {item: PackedInt32Array, count: PackedInt32Array}; só os baús já abertos (os outros ainda não têm conteúdo)
var evil_boss_down := false   # Eater of Worlds / Brain já derrotado: libera o meteorito e, depois, o Wall of Flesh vale
var hardmode := false       # Wall of Flesh derrotado: cobalto/paládio e Hallow (start_hardmode)
var skeletron_down := false   # Skeletron derrotado: o dungeon abre para qualquer picareta
var meteor_due := false       # cai um meteorito à meia-noite
var orbs_broken := 0   # orbes/corações quebrados (a cada 3 acorda o chefe do mal); vai no save do mundo
var edited := {}    # Vector2i -> true; chunks alterados pelo jogador (o save guarda só estes)
var versions := {}  # Vector2i -> nº de edições; descarta mesh de job que ficou velho
var jobs := {}     # id da task -> resultado preenchido pela thread
var generating := {}   # Vector2i -> true: chunk que um job está gerando agora
var max_jobs := clampi(OS.get_processor_count() - 1, 1, 4)
var center := Vector2i(-999, -999)


func _ready() -> void:
	Blocks.load_pack()
	Items.load_pack()
	Crafting.load_pack()
	gen = WorldGen.new(world_seed)
	var atlas_image := Atlas.build(Blocks.textures)
	Blocks.tile_colors = Atlas.tile_colors(atlas_image)
	atlas_texture = ImageTexture.create_from_image(atlas_image)
	material.shader = preload("res://shaders/chunk.gdshader")
	water_material.shader = preload("res://shaders/water.gdshader")
	for m in [material, water_material]:
		m.set_shader_parameter("atlas", atlas_texture)


# Luz do dia (day_night.gd): claridade do céu, cor dela e direção de onde vem (sol ou lua).
func set_light(daylight: float, tint: Vector3, dir: Vector3) -> void:
	for m in [material, water_material]:
		m.set_shader_parameter("daylight", daylight)
		m.set_shader_parameter("sky_tint", tint)
	material.set_shader_parameter("light_dir", dir)


func get_block(x: int, y: int, z: int) -> int:
	if y < 0:
		return gen.BEDROCK
	var c := Vector2i(floori(x / float(C)), floori(z / float(C)))
	if y >= H or not in_world(c):
		return 0
	if not chunks.has(c):
		chunks[c] = gen.generate(c.x, c.y)
	return chunks[c][posmod(x, C) + posmod(z, C) * C + y * C * C]


# wake = false: o fluxo dos líquidos grava sem acordar de novo os vizinhos (ele mesmo acorda os que importam).
func set_block(x: int, y: int, z: int, id: int, wake := true) -> void:
	if y < 0 or y >= H:
		return
	get_block(x, y, z)  # garante que o chunk existe
	var c := Vector2i(floori(x / float(C)), floori(z / float(C)))
	if not in_world(c):
		return
	var lx := posmod(x, C)
	var lz := posmod(z, C)
	chunks[c][lx + lz * C + y * C * C] = id
	if y + 1 < H and Blocks.shape[chunks[c][lx + lz * C + (y + 1) * C * C]] == "plant" and not Blocks.solid[id]:
		chunks[c][lx + lz * C + (y + 1) * C * C] = 0  # planta sem chão some
	edited[c] = true
	if wake:
		liquid.wake(x, y, z)
	_rebuild(c)
	if lx == 0: _rebuild(c + Vector2i(-1, 0))
	if lx == C - 1: _rebuild(c + Vector2i(1, 0))
	if lz == 0: _rebuild(c + Vector2i(0, -1))
	if lz == C - 1: _rebuild(c + Vector2i(0, 1))


# Líquido (id do cheio: water, lava) que contém o ponto p, ou 0: o ponto tem de estar abaixo da superfície do bloco.
func liquid_at(p: Vector3) -> int:
	var x := floori(p.x)
	var y := floori(p.y)
	var z := floori(p.z)
	var b := get_block(x, y, z)
	if not Blocks.liquid[b]:
		return 0
	var above := get_block(x, y + 1, z)
	if p.y - y < Blocks.liquid_height(b) or (Blocks.liquid[above] and Blocks.liquid_kind[above] == Blocks.liquid_kind[b]):
		return Blocks.liquid_kind[b]
	return 0


# Começa o hardmode: liga na geração (chunks novos) e converte os já gerados (mesmo passe determinístico). Os chunks convertidos
# passam a contar como editados para o save guardá-los.
func start_hardmode() -> void:
	hardmode = true
	gen.hardmode = true
	for k in chunks.keys():
		gen.hardmode_pass(chunks[k], k.x, k.y)
		edited[k] = true
		_rebuild(k)


# Conteúdo do baú em p; na primeira vez sorteia o tesouro (determinístico pela seed e posição): acessório, flechas, tochas, minério.
func chest_at(p: Vector3i) -> Dictionary:
	if not chests.has(p):
		var rng := RandomNumberGenerator.new()
		rng.seed = hash([world_seed, p.x, p.y, p.z])
		var c := {"item": PackedInt32Array(), "count": PackedInt32Array()}
		c.item.resize(40)
		c.item.fill(-1)
		c.count.resize(40)
		var loot: Array = [["hermes_boots", 1, 1, 0.12], ["shiny_red_balloon", 1, 1, 0.12], ["band_of_regeneration", 1, 1, 0.12],
			["wooden_arrow", 25, 60, 0.5], ["torch", 8, 20, 0.6], ["iron_bar", 3, 8, 0.4], ["gold_bar", 2, 5, 0.25], ["copper_bar", 4, 10, 0.4]]
		var k := 0
		for l in loot:
			if rng.randf() < l[3]:
				c.item[k] = Items.ids[l[0]]
				c.count[k] = rng.randi_range(l[1], l[2])
				k += 1
		if k == 0:   # baú nunca vem vazio
			c.item[0] = Items.ids.torch
			c.count[0] = 10
		chests[p] = c
	return chests[p]


# Troca a seed e descarta tudo o que foi gerado (usado ao carregar um save).
func set_seed(s: int) -> void:
	world_seed = s
	gen = WorldGen.new(s)
	chunks.clear()
	edited.clear()
	chests.clear()
	orbs_broken = 0
	evil_boss_down = false
	meteor_due = false
	skeletron_down = false
	hardmode = false
	liquid = Liquid.new()


# Primeiro y livre acima do bloco sólido mais alto da coluna (ground: sem contar tronco e folhas).
func surface_y(x: int, z: int, ground := false) -> int:
	for y in range(H - 1, -1, -1):
		var b := get_block(x, y, z)
		if Blocks.solid[b] and not (ground and Blocks.clear[b]):
			return y + 1
	return 0


func _rebuild(k: Vector2i) -> void:
	versions[k] = versions.get(k, 0) + 1
	if meshes.has(k) and not k in urgent:
		urgent.append(k)


# Percorre voxels ao longo do raio (Amanatides & Woo).
# Retorna {"pos": bloco atingido, "normal": face atingida, "t": distância até a entrada no bloco} ou {} se não acertar.
func raycast(from: Vector3, dir: Vector3, max_dist: float) -> Dictionary:
	var p := Vector3i(from.floor())
	var step := Vector3i(dir.sign())
	var t_delta := Vector3.INF
	var t_max := Vector3.INF
	for a in 3:
		if dir[a] != 0:
			t_delta[a] = absf(1.0 / dir[a])
			t_max[a] = (p[a] + 1 - from[a] if dir[a] > 0 else from[a] - p[a]) * t_delta[a]
	var normal := Vector3i.ZERO
	var t := 0.0
	while t <= max_dist:
		var b := get_block(p.x, p.y, p.z)
		if b != 0 and not Blocks.soft[b]:  # a mira pega também blocos não sólidos (tochas), mas atravessa plantas e líquidos
			return {"pos": p, "normal": normal, "t": t}
		var a := t_max.min_axis_index()
		t = t_max[a]
		p[a] += step[a]
		t_max[a] += t_delta[a]
		normal = Vector3i.ZERO
		normal[a] = -step[a]
	return {}


func in_world(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < WorldGen.SIZE_CHUNKS and c.y < WorldGen.SIZE_CHUNKS


func set_render_distance(rd: int) -> void:
	render_distance = clampi(rd, 2, 16)
	center = Vector2i(-999, -999)  # força recalcular a fila


func is_idle() -> bool:
	return pending.is_empty() and urgent.is_empty() and jobs.is_empty()


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed:
		if e.keycode in [KEY_EQUAL, KEY_KP_ADD]:
			set_render_distance(render_distance + 1)
		elif e.keycode in [KEY_MINUS, KEY_KP_SUBTRACT]:
			set_render_distance(render_distance - 1)


func _process(delta: float) -> void:
	liquid.step(self, delta)
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var c := Vector2i(floori(cam.global_position.x / C), floori(cam.global_position.z / C))
	if c != center:
		_recenter(c, cam)
	for id in jobs.keys():
		if WorkerThreadPool.is_task_completed(id):
			WorkerThreadPool.wait_for_task_completion(id)
			_apply(jobs[id])
			jobs.erase(id)
	while jobs.size() < max_jobs:
		var r := _next_job()
		if r.is_empty():
			break
		jobs[WorkerThreadPool.add_task(_job.bind(r))] = r


# Próximo trabalho: refazer a mesh de um chunk editado, montar a de um chunk pronto (dados dele e dos vizinhos),
# ou gerar o chunk mais perto que falta. {} se não há nada a fazer agora.
func _next_job() -> Dictionary:
	if not urgent.is_empty():
		return _mesh_job(urgent.pop_front())
	while not meshable.is_empty():
		var k: Vector2i = meshable.pop_front()
		if pending.has(k):
			pending.erase(k)
			meshes[k] = null
			return _mesh_job(k)
	while not need_gen.is_empty():
		var c: Vector2i = need_gen.pop_back()
		if not chunks.has(c) and not generating.has(c):
			generating[c] = true
			return {"gen": c}
	return {}


func _has_data(k: Vector2i) -> bool:
	for o in [Vector2i.ZERO] + NB:
		if in_world(k + o) and not chunks.has(k + o):
			return false
	return true


func _mesh_job(k: Vector2i) -> Dictionary:
	var r := {"k": k, "chunks": {}, "version": versions.get(k, 0)}
	for o in [Vector2i.ZERO] + NB:
		if chunks.has(k + o):
			r.chunks[k + o] = chunks[k + o]
	return r


func _recenter(c: Vector2i, cam: Camera3D) -> void:
	center = c
	var r := render_distance
	for k in meshes.keys():
		if (k - c).length_squared() > (r + 1) * (r + 1):
			if meshes[k]:
				meshes[k].queue_free()
			meshes.erase(k)
	pending.clear()
	for z in range(c.y - r, c.y + r + 1):
		for x in range(c.x - r, c.x + r + 1):
			var k := Vector2i(x, z)
			if in_world(k) and not meshes.has(k) and (k - c).length_squared() <= r * r:
				pending.append(k)
	pending.sort_custom(func(a, b): return (a - c).length_squared() > (b - c).length_squared())
	meshable.clear()
	need_gen.clear()
	var seen := {}
	for n in range(pending.size() - 1, -1, -1):   # do mais perto para o mais longe
		if _has_data(pending[n]):
			meshable.append(pending[n])
		for o in [Vector2i.ZERO] + NB:
			var g: Vector2i = pending[n] + o
			if in_world(g) and not chunks.has(g) and not seen.has(g):
				seen[g] = true
				need_gen.append(g)
	need_gen.reverse()
	cam.far = (r + 2) * C
	var env := get_world_3d().environment
	if env:
		env.fog_depth_end = r * C
		env.fog_depth_begin = r * C * 0.6


# Roda em thread: gera um chunk ("gen") ou monta os arrays da mesh de um chunk (opaca + água).
func _job(r: Dictionary) -> void:
	if r.has("gen"):
		r.data = gen.generate(r.gen.x, r.gen.y)
		return
	var k: Vector2i = r.k
	r.water = []
	r.arrays = ChunkMesher.build(r.chunks[k], NB.map(func(o): return r.chunks.get(k + o, PackedByteArray())), Blocks.textures.size(), r.water)


func _apply(r: Dictionary) -> void:
	if r.has("gen"):
		generating.erase(r.gen)
		if not chunks.has(r.gen):  # a thread principal pode ter gerado o mesmo chunk antes (get_block)
			chunks[r.gen] = r.data
		for o in [Vector2i.ZERO] + NB:   # este chunk pode ter completado os dados de um vizinho
			var k: Vector2i = r.gen + o
			if pending.has(k) and not meshable.has(k) and _has_data(k):
				meshable.append(k)
		return
	var k: Vector2i = r.k
	if not meshes.has(k) or r.version != versions.get(k, 0):
		return  # saiu do alcance, ou foi editado depois e outro job vai trazer a mesh certa
	if meshes[k]:
		meshes[k].queue_free()
		meshes[k] = null
	if r.arrays.is_empty() and r.water.is_empty():
		return
	var mesh := ArrayMesh.new()
	for s in [[r.arrays, material], [r.water, water_material]]:  # superfície 0 = opaca, 1 = água
		if not s[0].is_empty():
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, s[0])
			mesh.surface_set_material(mesh.get_surface_count() - 1, s[1])
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = Vector3(k.x * C, 0, k.y * C)
	add_child(mi)
	meshes[k] = mi


func _exit_tree() -> void:
	for id in jobs:
		WorkerThreadPool.wait_for_task_completion(id)
