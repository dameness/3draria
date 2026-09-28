class_name ChunkMesher
# Monta os arrays de mesh de um chunk só com as faces que dão para blocos não sólidos, já com luz:
# cor do vértice r = luz do céu × tom da face, g = luz de tochas × tom (ver shaders/chunk.gdshader).
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
const SHADE := [0.8, 0.8, 1.0, 0.55, 0.9, 0.7]  # tom fixo por direção da face
const SKY_FADE := 12.0   # blocos abaixo da superfície da coluna até a luz do céu sumir
const SKY_MIN := 0.05


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
	var a := {"v": PackedVector3Array(), "n": PackedVector3Array(), "c": PackedColorArray(), "uv": PackedVector2Array(), "i": PackedInt32Array()}  # formas especiais
	var tw := 1.0 / tile_count
	var lights := _lights(d, nb)
	var heights := PackedInt32Array()   # coluna (x+1, z+1) numa grade 18x18 -> primeiro y livre acima do topo; -1 = ainda não calculado
	heights.resize((C + 2) * (C + 2))
	heights.fill(-1)
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
				if Blocks.shape[b] != "":
					_shape(a, b, Vector3(x, y, z), tw)
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
					elif nx >= 0 and nx < C and nz >= 0 and nz < C:
						n = d[nx + nz * C + ny * CC]
					else:
						n = _block(d, nb, nx, ny, nz)
					if solid[n]:
						continue
					# Luz na célula de ar em frente à face.
					var col := (nx + 1) + (nz + 1) * (C + 2)
					if heights[col] == -1:
						heights[col] = _height(d, nb, nx, nz)
					var sky := clampf(1.0 - (heights[col] - ny) / SKY_FADE, SKY_MIN, 1.0)
					var cell := Vector3(nx + 0.5, ny + 0.5, nz + 0.5)
					var torch := 0.0
					for l in lights:
						torch = maxf(torch, 1.0 - cell.distance_to(l[0]) / l[1])
					var sh: float = SHADE[f]
					var u0 := tiles[b * Blocks.FACES + f] * tw
					var c := Color(sh * sky, sh * torch, 0)
					var base := verts.size()
					var p := Vector3(x, y, z)
					for k in 4:
						verts.append(p + CORNERS[f][k])
						norms.append(Vector3(dir))
						cols.append(c)
					uvs.append_array([Vector2(u0, 1), Vector2(u0, 0), Vector2(u0 + tw, 0), Vector2(u0 + tw, 1)])
					idx.append_array([base, base + 2, base + 1, base, base + 3, base + 2])
	var offset := verts.size()
	verts.append_array(a.v)
	norms.append_array(a.n)
	cols.append_array(a.c)
	uvs.append_array(a.uv)
	for i in a.i:
		idx.append(i + offset)
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


# Face f de uma caixa com canto em p e tamanho s (formas especiais; o laço principal faz o mesmo inline).
static func _face(a: Dictionary, p: Vector3, f: int, s: Vector3, u0: float, tw: float, c: Color) -> void:
	var base: int = a.v.size()
	for k in 4:
		a.v.append(p + CORNERS[f][k] * s)
		a.n.append(Vector3(DIRS[f]))
		a.c.append(c)
	a.uv.append_array([Vector2(u0, 1), Vector2(u0, 0), Vector2(u0 + tw, 0), Vector2(u0 + tw, 1)])
	a.i.append_array([base, base + 2, base + 1, base, base + 3, base + 2])


# Formas não cúbicas. Tocha: cabo fino (textura lateral) + chama (textura do topo), sempre acesas.
static func _shape(a: Dictionary, b: int, p: Vector3, tw: float) -> void:
	if Blocks.shape[b] == "torch":
		var stick := tiles_of(b, 0) * tw
		var flame := tiles_of(b, 2) * tw
		for f in 6:
			var sh: float = SHADE[f]
			_face(a, p + Vector3(0.44, 0, 0.44), f, Vector3(0.12, 0.55, 0.12), stick, tw, Color(sh, sh, 0))
			_face(a, p + Vector3(0.41, 0.55, 0.41), f, Vector3(0.18, 0.2, 0.18), flame, tw, Color(1, 1, 0))


static func tiles_of(b: int, face: int) -> int:
	return Blocks.tiles[b * Blocks.FACES + face]


# Bloco em coordenadas locais que podem cair no vizinho (até 1 chunk de distância em X ou Z).
static func _block(d: PackedByteArray, nb: Array, x: int, y: int, z: int) -> int:
	if y < 0 or y >= H:
		return 0
	if x >= C:
		return _at(nb[0], x - C, y, z) if z >= 0 and z < C else 0
	if x < 0:
		return _at(nb[1], x + C, y, z) if z >= 0 and z < C else 0
	if z >= C:
		return _at(nb[2], x, y, z - C)
	if z < 0:
		return _at(nb[3], x, y, z + C)
	return d[x + z * C + y * CC]


# Primeiro y livre acima do bloco sólido mais alto da coluna (x, z locais).
static func _height(d: PackedByteArray, nb: Array, x: int, z: int) -> int:
	for y in range(H - 1, -1, -1):
		if Blocks.solid[_block(d, nb, x, y, z)]:
			return y + 1
	return 0


# Fontes de luz (tochas) no chunk e nos vizinhos: [[centro local, raio], ...].
# ponytail: luz atravessa paredes (sem oclusão) e não passa dos vizinhos diretos; trocar por
# propagação em BFS se ficar estranho em cavernas.
static func _lights(d: PackedByteArray, nb: Array) -> Array:
	var out := []
	var sources := [[d, Vector3.ZERO], [nb[0], Vector3(C, 0, 0)], [nb[1], Vector3(-C, 0, 0)], [nb[2], Vector3(0, 0, C)], [nb[3], Vector3(0, 0, -C)]]
	for id in Blocks.light.size():
		if Blocks.light[id] == 0:
			continue
		for s in sources:
			var data: PackedByteArray = s[0]
			var i := data.find(id)
			while i != -1:
				var p: Vector3 = Vector3(i % C, i / CC, (i / C) % C) + s[1] + Vector3.ONE * 0.5
				if p.x > -Blocks.light[id] and p.x < C + Blocks.light[id] and p.z > -Blocks.light[id] and p.z < C + Blocks.light[id]:
					out.append([p, float(Blocks.light[id])])
				i = data.find(id, i + 1)
	return out


static func _at(d: PackedByteArray, x: int, y: int, z: int) -> int:
	return 0 if d.is_empty() else d[x + z * C + y * CC]
