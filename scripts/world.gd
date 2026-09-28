extends Node3D
# Guarda os chunks do mundo finito e mantém malhas só dentro da distância de renderização.
# Geração e mesh rodam no WorkerThreadPool; cada job lê só a sua cópia dos chunks
# e a thread principal grava o resultado em `chunks`.

const C := WorldGen.CHUNK
const H := WorldGen.HEIGHT
const NB: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]  # ordem do ChunkMesher

@export var render_distance := 6  # em chunks; teclas + e - mudam em jogo
@export var world_seed := 1337

var gen: WorldGen
var chunks := {}   # Vector2i -> PackedByteArray
var meshes := {}   # Vector2i -> MeshInstance3D, ou null (sem faces / em construção)
var material := StandardMaterial3D.new()
var pending: Array[Vector2i] = []
var urgent: Array[Vector2i] = []   # chunks editados que precisam de mesh nova
var versions := {}  # Vector2i -> nº de edições; descarta mesh de job que ficou velho
var jobs := {}     # id da task -> resultado preenchido pela thread
var max_jobs := clampi(OS.get_processor_count() - 1, 1, 4)
var center := Vector2i(-999, -999)


func _ready() -> void:
	Blocks.load_pack()
	gen = WorldGen.new(world_seed)
	material.albedo_texture = ImageTexture.create_from_image(Atlas.build(Blocks.textures))
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true


func get_block(x: int, y: int, z: int) -> int:
	if y < 0:
		return gen.BEDROCK
	var c := Vector2i(floori(x / float(C)), floori(z / float(C)))
	if y >= H or not in_world(c):
		return 0
	if not chunks.has(c):
		chunks[c] = gen.generate(c.x, c.y)
	return chunks[c][posmod(x, C) + posmod(z, C) * C + y * C * C]


func set_block(x: int, y: int, z: int, id: int) -> void:
	if y < 0 or y >= H:
		return
	get_block(x, y, z)  # garante que o chunk existe
	var c := Vector2i(floori(x / float(C)), floori(z / float(C)))
	if not in_world(c):
		return
	var lx := posmod(x, C)
	var lz := posmod(z, C)
	chunks[c][lx + lz * C + y * C * C] = id
	_rebuild(c)
	if lx == 0: _rebuild(c + Vector2i(-1, 0))
	if lx == C - 1: _rebuild(c + Vector2i(1, 0))
	if lz == 0: _rebuild(c + Vector2i(0, -1))
	if lz == C - 1: _rebuild(c + Vector2i(0, 1))


func _rebuild(k: Vector2i) -> void:
	versions[k] = versions.get(k, 0) + 1
	if meshes.has(k) and not k in urgent:
		urgent.append(k)


# Percorre voxels ao longo do raio (Amanatides & Woo).
# Retorna {"pos": bloco sólido atingido, "normal": face atingida} ou {} se não acertar.
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
		if Blocks.solid[get_block(p.x, p.y, p.z)]:
			return {"pos": p, "normal": normal}
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


func _process(_delta: float) -> void:
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
	while jobs.size() < max_jobs and not (urgent.is_empty() and pending.is_empty()):
		var k: Vector2i
		if urgent.is_empty():
			k = pending.pop_back()
			meshes[k] = null
		else:
			k = urgent.pop_front()
		var r := {"k": k, "chunks": {}, "version": versions.get(k, 0)}
		for o in [Vector2i.ZERO] + NB:
			if chunks.has(k + o):
				r.chunks[k + o] = chunks[k + o]
		jobs[WorkerThreadPool.add_task(_job.bind(r))] = r


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
	cam.far = (r + 2) * C
	var env := get_world_3d().environment
	if env:
		env.fog_depth_end = r * C
		env.fog_depth_begin = r * C * 0.6


# Roda em thread: gera o que faltar do chunk e vizinhos, e monta os arrays da mesh.
func _job(r: Dictionary) -> void:
	var k: Vector2i = r.k
	for o in [Vector2i.ZERO] + NB:
		if in_world(k + o) and not r.chunks.has(k + o):
			r.chunks[k + o] = gen.generate(k.x + o.x, k.y + o.y)
	r.arrays = ChunkMesher.build(r.chunks[k], NB.map(func(o): return r.chunks.get(k + o, PackedByteArray())), Blocks.textures.size())


func _apply(r: Dictionary) -> void:
	for c in r.chunks:
		if not chunks.has(c):
			chunks[c] = r.chunks[c]
	var k: Vector2i = r.k
	if not meshes.has(k) or r.version != versions.get(k, 0):
		return  # saiu do alcance, ou foi editado depois e outro job vai trazer a mesh certa
	if meshes[k]:
		meshes[k].queue_free()
		meshes[k] = null
	if r.arrays.is_empty():
		return
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, r.arrays)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	mi.position = Vector3(k.x * C, 0, k.y * C)
	add_child(mi)
	meshes[k] = mi


func _exit_tree() -> void:
	for id in jobs:
		WorkerThreadPool.wait_for_task_completion(id)
