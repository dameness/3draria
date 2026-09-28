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


func in_world(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < WorldGen.SIZE_CHUNKS and c.y < WorldGen.SIZE_CHUNKS


func set_render_distance(rd: int) -> void:
	render_distance = clampi(rd, 2, 16)
	center = Vector2i(-999, -999)  # força recalcular a fila


func is_idle() -> bool:
	return pending.is_empty() and jobs.is_empty()


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
	while jobs.size() < max_jobs and not pending.is_empty():
		var k: Vector2i = pending.pop_back()
		meshes[k] = null
		var r := {"k": k, "chunks": {}}
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
	if not meshes.has(k) or meshes[k] != null or r.arrays.is_empty():
		return  # saiu do alcance, já tem mesh, ou não tem faces
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
