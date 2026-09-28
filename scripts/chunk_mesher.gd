class_name ChunkMesher
# Monta os arrays de mesh de um chunk só com as faces que dão para blocos não sólidos.
# Não toca em nada compartilhado: pode rodar em thread.

const C := WorldGen.CHUNK
const H := WorldGen.HEIGHT
const CC := C * C
const DIRS: Array[Vector3i] = [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]
# 4 cantos por face, anti-horário visto de fora; os índices invertem para o horário que o Godot usa.
const CORNERS := [
	[Vector3(1, 0, 0), Vector3(1, 1, 0), Vector3(1, 1, 1), Vector3(1, 0, 1)],
	[Vector3(0, 0, 1), Vector3(0, 1, 1), Vector3(0, 1, 0), Vector3(0, 0, 0)],
	[Vector3(0, 1, 0), Vector3(0, 1, 1), Vector3(1, 1, 1), Vector3(1, 1, 0)],
	[Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 0, 1), Vector3(0, 0, 1)],
	[Vector3(1, 0, 1), Vector3(1, 1, 1), Vector3(0, 1, 1), Vector3(0, 0, 1)],
	[Vector3(0, 0, 0), Vector3(0, 1, 0), Vector3(1, 1, 0), Vector3(1, 0, 0)],
]
const SHADE := [0.8, 0.8, 1.0, 0.55, 0.9, 0.7]  # luz fixa por direção (sem iluminação dinâmica)


# d: blocos do chunk. nb: vizinhos [+X, -X, +Z, -Z]; PackedByteArray vazio = fora do mundo (ar).
# Retorna os arrays para ArrayMesh.add_surface_from_arrays, ou [] se não houver faces.
static func build(d: PackedByteArray, nb: Array, tile_count: int) -> Array:
	var solid := Blocks.solid
	var tiles := Blocks.tiles
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	var tw := 1.0 / tile_count
	var top := d.size() - 1
	while top >= 0 and d[top] == 0:
		top -= 1
	for y in top / CC + 1:
		for z in C:
			for x in C:
				var i := x + z * C + y * CC
				var b := d[i]
				if b == 0:
					continue
				# Caminho rápido: bloco interno cercado por sólidos não tem face visível.
				if x > 0 and x < C - 1 and z > 0 and z < C - 1 and y > 0 and y < H - 1 \
						and solid[d[i + 1]] and solid[d[i - 1]] and solid[d[i + C]] and solid[d[i - C]] \
						and solid[d[i + CC]] and solid[d[i - CC]]:
					continue
				for f in 6:
					var dir := DIRS[f]
					var nx := x + dir.x
					var ny := y + dir.y
					var nz := z + dir.z
					var n := 0
					if ny < 0:
						continue  # fundo do mundo nunca aparece
					elif ny >= H:
						n = 0
					elif nx >= C:
						n = _at(nb[0], 0, ny, nz)
					elif nx < 0:
						n = _at(nb[1], C - 1, ny, nz)
					elif nz >= C:
						n = _at(nb[2], nx, ny, 0)
					elif nz < 0:
						n = _at(nb[3], nx, ny, C - 1)
					else:
						n = d[nx + nz * C + ny * CC]
					if solid[n]:
						continue
					var base := verts.size()
					var u0 := tiles[b * Blocks.FACES + f] * tw
					var p := Vector3(x, y, z)
					var c := Color(SHADE[f], SHADE[f], SHADE[f])
					for k in 4:
						verts.append(p + CORNERS[f][k])
						norms.append(Vector3(dir))
						cols.append(c)
					uvs.append_array([Vector2(u0, 1), Vector2(u0, 0), Vector2(u0 + tw, 0), Vector2(u0 + tw, 1)])
					idx.append_array([base, base + 2, base + 1, base, base + 3, base + 2])
	if verts.is_empty():
		return []
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	return arrays


static func _at(d: PackedByteArray, x: int, y: int, z: int) -> int:
	return 0 if d.is_empty() else d[x + z * C + y * CC]
