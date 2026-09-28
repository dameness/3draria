class_name BlockCrack
extends MeshInstance3D
# Rachaduras sobre o bloco que está sendo minerado: 4 estágios que crescem com o dano, como no Terraria. Um cubo um fio maior
# que o bloco com uma textura procedural (as mesmas fissuras em cada estágio, mais ramos a cada um).

const STAGES := 4
const GROW := 0.004     # o quanto o cubo passa do bloco, para não brigar com a face dele
static var _texture: ImageTexture


func _init() -> void:
	mesh = _cube()
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_texture = _crack_texture()
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.uv1_scale = Vector3(1.0 / STAGES, 1.0, 1.0)
	material_override = m
	top_level = true
	visible = false
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


# Mostra as rachaduras no bloco `pos`; progress vai de 0 (nada) a 1 (quebra).
func show_at(pos: Vector3i, progress: float) -> void:
	global_position = Vector3(pos) + Vector3.ONE * 0.5
	material_override.uv1_offset = Vector3(clampi(int(progress * STAGES), 0, STAGES - 1) / float(STAGES), 0.0, 0.0)
	visible = true


static func _cube() -> ArrayMesh:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var uv := PackedVector2Array()
	var idx := PackedInt32Array()
	for f in 6:
		var base := v.size()
		for k in 4:
			v.append((ChunkMesher.CORNERS[f][k] - Vector3.ONE * 0.5) * (1.0 + GROW * 2.0))
			n.append(Vector3(ChunkMesher.DIRS[f]))
		uv.append_array([Vector2(0, 1), Vector2(0, 0), Vector2(1, 0), Vector2(1, 1)])
		idx.append_array([base, base + 2, base + 1, base, base + 3, base + 2])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = v
	arrays[Mesh.ARRAY_NORMAL] = n
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


# Fileira de STAGES tiles 16x16 com fissuras a partir do centro: o estágio k desenha os 3 + 2k primeiros ramos.
static func _crack_texture() -> ImageTexture:
	if _texture:
		return _texture
	var img := Image.create(16 * STAGES, 16, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var branches := []
	for i in 9:
		var p := Vector2(8, 8) + Vector2(rng.randf_range(-1.5, 1.5), rng.randf_range(-1.5, 1.5))
		var ang := i * TAU / 9.0 + rng.randf_range(-0.35, 0.35)
		var path := []
		for s in rng.randi_range(5, 9):
			path.append(Vector2i(p))
			ang += rng.randf_range(-0.7, 0.7)
			p += Vector2.from_angle(ang) * rng.randf_range(1.0, 1.7)
		branches.append(path)
	for stage in STAGES:
		for b in mini(3 + stage * 2, branches.size()):
			var path: Array = branches[b]
			var last: Vector2i = path[0]
			for s in mini(path.size(), 3 + stage * 2 + 2):   # os ramos também crescem de um estágio para o outro
				var q: Vector2i = path[s]
				for t in 5:   # liga o ponto anterior ao atual: a fissura fica contínua
					var m := Vector2i(Vector2(last).lerp(Vector2(q), t / 4.0).round())
					if m.x >= 0 and m.x < 16 and m.y >= 0 and m.y < 16:
						img.set_pixel(stage * 16 + m.x, m.y, Color(0.04, 0.03, 0.02, 0.92))
				last = q
	_texture = ImageTexture.create_from_image(img)
	return _texture
