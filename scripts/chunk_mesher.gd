class_name ChunkMesher
# Monta os arrays de mesh de um chunk só com as faces que dão para blocos não sólidos, já com luz:
# cor do vértice r = luz do céu × tom da face × oclusão ambiente, g = luz de tochas × o mesmo,
# b = tipo (0 bloco, 0.25 chama de tocha, 0.5 planta que balança, 1 brilha sozinho, como a lava) (ver shaders/chunk.gdshader).
# Formas (tocha, plantas), lava e a água (superfície à parte, shaders/water.gdshader) saem daqui também.
# Não toca em nada compartilhado: pode rodar em thread. Neste Godot, chamadas de função GDScript disputam uma
# trava entre threads (arrays, operadores e métodos nativos não): por isso o laço quente só indexa arrays, e o
# chunk é copiado com margem (_padded) para as vizinhanças não precisarem de função nenhuma.

const C := WorldGen.CHUNK
const H := WorldGen.HEIGHT
const CC := C * C
const P := C + 2      # largura da cópia com margem de 1 bloco em X e Z
const PP := P * P
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
const SHADE := [0.8, 0.8, 1.0, 0.55, 0.9, 0.7]  # tom fixo por direção da face (o shader soma a direção do sol)
const SKY_FADE := 12.0   # blocos abaixo da superfície da coluna até a luz do céu sumir
const SKY_MIN := 0.05
const AO_LIGHT := [0.5, 0.68, 0.84, 1.0]   # brilho de um canto conforme a oclusão (0 = dois lados tapados)
const JITTER := 0.07     # cada bloco fica até 7% mais escuro, para o gramado não ser uma cor só
const LIQUID_TOP := Blocks.LIQUID_TOP # a superfície do líquido cheio fica um pouco abaixo do topo do bloco
const PLANT_H := 0.9     # altura das plantas (<1: o shader identifica a ponta pela parte fracionária de y)
const HELL_AMBIENT := 0.5  # brilho quente do submundo (canal de tocha) perto do fundo do mundo
const CANOPY_SHADE := 0.66 # a luz do céu que passa por baixo de uma copa de árvore

# Deslocamento de índice (na cópia com margem) de cada face f: DIR_IDX[f]; e, por face e canto, dos dois vizinhos
# laterais da célula à frente da face e do diagonal (oclusão ambiente): AO_IDX[(f * 4 + k) * 3 + j].
static var DIR_IDX := _dir_index()
static var AO_IDX := _ao_index()


static func _dir_index() -> PackedInt32Array:
	var out := PackedInt32Array()
	for dir in DIRS:
		out.append(dir.x + dir.z * P + dir.y * PP)
	return out


static func _ao_index() -> PackedInt32Array:
	var out := PackedInt32Array()
	for f in 6:
		var axes := []
		for a in 3:
			if DIRS[f][a] == 0:
				axes.append(a)
		for k in 4:
			var c: Vector3 = CORNERS[f][k]
			var s1 := Vector3i.ZERO
			var s2 := Vector3i.ZERO
			s1[axes[0]] = int(c[axes[0]] * 2 - 1)
			s2[axes[1]] = int(c[axes[1]] * 2 - 1)
			for o in [s1, s2, s1 + s2]:
				out.append(o.x + o.z * P + o.y * PP)
	return out


# Cópia do chunk com 1 bloco de margem: X e Z vêm dos vizinhos [+X, -X, +Z, -Z] (vazio = fora do mundo = ar; as
# quinas ficam ar) e 1 de ar acima e abaixo. Índice de (x, y, z) local: (x + 1) + (z + 1) * P + (y + 1) * PP.
static func _padded(d: PackedByteArray, nb: Array) -> PackedByteArray:
	var p := PackedByteArray()
	p.resize(PP * (H + 2))
	var px: PackedByteArray = nb[0]
	var mx: PackedByteArray = nb[1]
	var pz: PackedByteArray = nb[2]
	var mz: PackedByteArray = nb[3]
	for y in H:
		var base := (y + 1) * PP
		var yo := y * CC
		for z in C:
			var s := z * C + yo
			var o := base + (z + 1) * P + 1
			for x in C:
				p[o + x] = d[s + x]
			if not mx.is_empty():
				p[o - 1] = mx[s + C - 1]
			if not px.is_empty():
				p[o + C] = px[s]
		for x in C:
			if not mz.is_empty():
				p[base + 1 + x] = mz[x + (C - 1) * C + yo]
			if not pz.is_empty():
				p[base + (C + 1) * P + 1 + x] = pz[x + yo]
	return p


# d: blocos do chunk. nb: vizinhos [+X, -X, +Z, -Z]; PackedByteArray vazio = fora do mundo (ar).
# corners: vizinhos de canto [+X+Z, +X-Z, -X+Z, -X-Z], só como fontes de luz (vazio ou ausente = sem tocha de lá).
# Retorna os arrays da superfície opaca para ArrayMesh.add_surface_from_arrays, ou [] se não houver faces.
# water_out (opcional) recebe os arrays da superfície da água, se houver.
static func build(d: PackedByteArray, nb: Array, tile_count: int, water_out := [], corners := []) -> Array:
	var solid := Blocks.solid
	var special := Blocks.special
	var liquid := Blocks.liquid
	var tiles := Blocks.tiles
	var p := _padded(d, nb)
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	var a := _new()   # formas especiais e lava, juntadas à superfície opaca no fim
	var wd := _new()  # água
	var tw := 1.0 / tile_count
	var lights := _lights(d, nb, corners)
	var hts := PackedInt32Array()   # por coluna da cópia com margem: [0, PP) primeiro y livre acima do chão, [PP, 2 PP) acima da copa; -1 = ainda não calculado
	hts.resize(PP * 2)
	hts.fill(-1)
	var ao := PackedInt32Array([0, 0, 0, 0])   # oclusão dos 4 cantos da face em curso
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
				var pi := (x + 1) + (z + 1) * P + (y + 1) * PP   # o mesmo bloco na cópia com margem
				if special[b]:
					if liquid[b]:
						_liquid(a if Blocks.glow[b] else wd, p, hts, lights, b, x, y, z, tw)
					else:
						_shape(a, b, Vector3(x, y, z), tw, _light(p, hts, lights, x, y, z))
					continue
				# Caminho rápido: bloco interno cercado por sólidos não tem face visível.
				if solid[p[pi + 1]] and solid[p[pi - 1]] and solid[p[pi + P]] and solid[p[pi - P]] \
						and solid[p[pi + PP]] and solid[p[pi - PP]]:
					continue
				var jit := 1.0 - JITTER * fposmod(sin(x * 12.9898 + y * 78.233 + z * 37.719) * 43758.5453, 1.0)
				for f in 6:
					var dir := DIRS[f]
					var ny := y + dir.y
					if ny < 0:
						continue  # fundo do mundo nunca aparece
					var ni := pi + DIR_IDX[f]   # célula à frente da face
					var n := p[ni]
					if solid[n]:
						continue
					var light := _light(p, hts, lights, x + dir.x, ny, z + dir.z)
					if liquid[n]:
						light.x *= _underwater(p, x + dir.x, ny, z + dir.z)
					var sh: float = SHADE[f] * jit
					var u0 := tiles[b * Blocks.FACES + f] * tw
					# Oclusão ambiente por canto: 3 = aberto ... 0 = os dois lados tapados.
					for k in 4:
						var j := (f * 4 + k) * 3
						var s1 := solid[p[ni + AO_IDX[j]]]
						var s2 := solid[p[ni + AO_IDX[j + 1]]]
						ao[k] = 0 if s1 and s2 else 3 - (s1 + s2 + solid[p[ni + AO_IDX[j + 2]]])
					var base := verts.size()
					var v0 := Vector3(x, y, z)
					for k in 4:
						var l: float = AO_LIGHT[ao[k]] * sh
						verts.append(v0 + CORNERS[f][k])
						norms.append(Vector3(dir))
						cols.append(Color(l * light.x, l * light.y, 0))
					uvs.append_array([Vector2(u0, 1), Vector2(u0, 0), Vector2(u0 + tw, 0), Vector2(u0 + tw, 1)])
					# A diagonal liga os dois cantos mais escuros: o vinco fica no lugar certo.
					if ao[0] + ao[2] <= ao[1] + ao[3]:
						idx.append_array([base, base + 2, base + 1, base, base + 3, base + 2])
					else:
						idx.append_array([base, base + 3, base + 1, base + 1, base + 3, base + 2])
	var offset := verts.size()
	verts.append_array(a.v)
	norms.append_array(a.n)
	cols.append_array(a.c)
	uvs.append_array(a.uv)
	for i in a.i:
		idx.append(i + offset)
	water_out.clear()
	if not wd.v.is_empty():
		water_out.append_array(_arrays(wd))
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


static func _new() -> Dictionary:
	return {"v": PackedVector3Array(), "n": PackedVector3Array(), "c": PackedColorArray(), "uv": PackedVector2Array(), "i": PackedInt32Array()}


static func _arrays(a: Dictionary) -> Array:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = a.v
	arrays[Mesh.ARRAY_NORMAL] = a.n
	arrays[Mesh.ARRAY_COLOR] = a.c
	arrays[Mesh.ARRAY_TEX_UV] = a.uv
	arrays[Mesh.ARRAY_INDEX] = a.i
	return arrays


# Luz (x = céu, y = tocha) na célula (x, y, z) do chunk (ou 1 além da borda em X e Z): o céu cai com a
# profundidade abaixo do chão da coluna (tronco e folhas não contam), menos uma sombra fixa sob a copa; a tocha cai
# com a distância. No submundo há um brilho quente de fundo.
static func _light(p: PackedByteArray, hts: PackedInt32Array, lights: Array, x: int, y: int, z: int) -> Vector2:
	var col := (x + 1) + (z + 1) * P
	var ground := hts[col]
	if ground < 0:
		var solid := Blocks.solid
		var clear := Blocks.clear
		ground = 0
		var canopy := 0
		for yy in range(WorldGen.SKY_BASE - 1, -1, -1):   # o céu (ilhas flutuantes) não faz sombra na terra
			var b := p[col + (yy + 1) * PP]
			if solid[b]:
				if canopy == 0:
					canopy = yy + 1
				if not clear[b]:
					ground = yy + 1
					break
		hts[col] = ground
		hts[PP + col] = canopy
	var sky := clampf(1.0 - (ground - y) / SKY_FADE, SKY_MIN, 1.0)
	if y < hts[PP + col] and hts[PP + col] > ground:
		sky *= CANOPY_SHADE
	var cell := Vector3(x + 0.5, y + 0.5, z + 0.5)
	var torch := clampf((WorldGen.UNDERWORLD_TOP + 2.0 - y) / 8.0, 0.0, 1.0) * HELL_AMBIENT
	for l in lights:
		torch = maxf(torch, 1.0 - cell.distance_to(l[0]) / l[1])
	return Vector2(sky, torch)


# A luz do céu escurece a cada bloco de água por cima (até um mínimo).
static func _underwater(p: PackedByteArray, x: int, y: int, z: int) -> float:
	var depth := 1
	var i := (x + 1) + (z + 1) * P + (y + 1) * PP
	while depth < 8 and y + depth < H and Blocks.liquid[p[i + depth * PP]]:
		depth += 1
	return maxf(0.4, 1.0 - 0.09 * depth)


# Face f de uma caixa com canto em pos e tamanho s (formas especiais).
static func _face(a: Dictionary, pos: Vector3, f: int, s: Vector3, u0: float, tw: float, c: Color) -> void:
	var base: int = a.v.size()
	for k in 4:
		a.v.append(pos + CORNERS[f][k] * s)
		a.n.append(Vector3(DIRS[f]))
		a.c.append(c)
	a.uv.append_array([Vector2(u0, 1), Vector2(u0, 0), Vector2(u0 + tw, 0), Vector2(u0 + tw, 1)])
	a.i.append_array([base, base + 2, base + 1, base, base + 3, base + 2])


# Quadro vertical de altura h entre os pontos p0 e p1 (do chão), visto de frente quando p0 fica à esquerda.
static func _vquad(a: Dictionary, p0: Vector3, p1: Vector3, h: float, u0: float, tw: float, c: Color) -> void:
	var base: int = a.v.size()
	for v in [p0, p0 + Vector3(0, h, 0), p1 + Vector3(0, h, 0), p1]:
		a.v.append(v)
		a.n.append(Vector3.UP)
		a.c.append(c)
	a.uv.append_array([Vector2(u0, 1), Vector2(u0, 0), Vector2(u0 + tw, 0), Vector2(u0 + tw, 1)])
	a.i.append_array([base, base + 1, base + 2, base, base + 2, base + 3])


# Formas não cúbicas. Tocha: cabo fino (textura lateral) + chama (textura do topo), sempre acesas.
# Planta: dois quadros em cruz, frente e verso; balança no shader (b = 0.5).
static func _shape(a: Dictionary, b: int, pos: Vector3, tw: float, light: Vector2) -> void:
	match Blocks.shape[b]:
		"torch":
			var stick := tiles_of(b, 0) * tw
			var flame := tiles_of(b, 2) * tw
			for f in 6:
				var sh: float = SHADE[f]
				_face(a, pos + Vector3(0.44, 0, 0.44), f, Vector3(0.12, 0.55, 0.12), stick, tw, Color(sh, sh, 0))
				_face(a, pos + Vector3(0.41, 0.55, 0.41), f, Vector3(0.18, 0.2, 0.18), flame, tw, Color(1, 1, 0.25))
		"door":   # porta aberta: um painel fino na borda do bloco; a passagem fica livre
			var u0 := tiles_of(b, 0) * tw
			for f in 6:
				var sh: float = SHADE[f]
				_face(a, pos, f, Vector3(0.14, 1.0, 1.0), u0, tw, Color(sh * light.x, sh * light.y, 0.0))
		"rope":   # corda: um fio fino no meio do bloco, com a luz do lugar
			var u0 := tiles_of(b, 0) * tw
			for f in 6:
				var sh: float = SHADE[f]
				_face(a, pos + Vector3(0.43, 0, 0.43), f, Vector3(0.14, 1.0, 0.14), u0, tw, Color(sh * light.x, sh * light.y, 0.0))
		"crystal":   # Life Crystal: dois quadros em cruz do tamanho do bloco, sem balançar e brilhando sozinho (b = 1)
			var u0 := tiles_of(b, 0) * tw
			var c := Color(light.x, light.y, 1.0)
			for pair in [[Vector3(0.05, 0, 0.05), Vector3(0.95, 0, 0.95)], [Vector3(0.95, 0, 0.05), Vector3(0.05, 0, 0.95)]]:
				_vquad(a, pos + pair[0], pos + pair[1], 0.95, u0, tw, c)
				_vquad(a, pos + pair[1], pos + pair[0], 0.95, u0, tw, c)
		"plant":
			var u0 := tiles_of(b, 0) * tw
			var c := Color(light.x * 0.95, light.y * 0.95, 0.5)
			for pair in [[Vector3(0.1, 0, 0.1), Vector3(0.9, 0, 0.9)], [Vector3(0.9, 0, 0.1), Vector3(0.1, 0, 0.9)]]:
				_vquad(a, pos + pair[0], pos + pair[1], PLANT_H, u0, tw, c)
				_vquad(a, pos + pair[1], pos + pair[0], PLANT_H, u0, tw, c)


# Faces de um bloco de líquido. O nível 1-8 é a altura da superfície (Blocks.liquid_height); com o mesmo líquido em cima (ou
# cheio sob um teto) o bloco vai até o topo, e ao lado do mesmo líquido só aparece o degrau acima da superfície vizinha.
# `a` é a água (superfície translúcida: b = 1 nos vértices da superfície, que ondulam no shader) ou, para a lava, as formas
# opacas (b = 1: brilha sozinha).
static func _liquid(a: Dictionary, p: PackedByteArray, hts: PackedInt32Array, lights: Array, b: int, x: int, y: int, z: int, tw: float) -> void:
	var pi := (x + 1) + (z + 1) * P + (y + 1) * PP
	var kinds := Blocks.liquid_kind
	var levels := Blocks.liquid_level
	var solid := Blocks.solid
	var kind := kinds[b]
	var above := p[pi + PP]
	var sealed: bool = (levels[above] > 0 and kinds[above] == kind) or (levels[b] == 8 and solid[above] == 1)
	var h := 1.0 if sealed else LIQUID_TOP * levels[b] / 8.0
	var glow := 1.0 if Blocks.glow[b] else 0.0
	for f in 6:
		var dir := DIRS[f]
		if y + dir.y < 0:
			continue
		var n := p[pi + DIR_IDX[f]]
		var lo := 0.0
		if f == 2:
			if sealed:
				continue
		elif solid[n]:
			continue
		elif levels[n] > 0 and kinds[n] == kind:   # o mesmo líquido ao lado ou embaixo
			if f == 3:
				continue
			var na := p[pi + DIR_IDX[f] + PP]
			var hn := 1.0 if levels[na] > 0 and kinds[na] == kind else LIQUID_TOP * levels[n] / 8.0
			if hn >= h:
				continue
			lo = hn
		var light := _light(p, hts, lights, x + dir.x, y + dir.y, z + dir.z)
		var sh: float = SHADE[f]
		var c_low := Color(sh * light.x, sh * light.y, glow)
		var c_high := Color(sh * light.x, sh * light.y, 1.0)
		var u0 := tiles_of(b, f) * tw
		var base: int = a.v.size()
		for k in 4:
			var v: Vector3 = CORNERS[f][k]
			var top := v.y > 0.5
			v.y = h if top else lo
			a.v.append(Vector3(x, y, z) + v)
			a.n.append(Vector3(dir))
			a.c.append(c_high if top or lo > 0.0 else c_low)
		a.uv.append_array([Vector2(u0, 1), Vector2(u0, 0), Vector2(u0 + tw, 0), Vector2(u0 + tw, 1)])
		a.i.append_array([base, base + 2, base + 1, base, base + 3, base + 2])


static func tiles_of(b: int, face: int) -> int:
	return Blocks.tiles[b * Blocks.FACES + face]


# Fontes de luz (tochas) no chunk e nos vizinhos: [[centro local, raio], ...].
# ponytail: luz atravessa paredes (sem oclusão) e só vem do chunk e dos 8 em volta; trocar por
# propagação em BFS se ficar estranho em cavernas. Lava não entra aqui (seriam milhares de fontes): só brilha nas próprias faces.
static func _lights(d: PackedByteArray, nb: Array, corners: Array) -> Array:
	var out := []
	var sources := [[d, Vector3.ZERO], [nb[0], Vector3(C, 0, 0)], [nb[1], Vector3(-C, 0, 0)], [nb[2], Vector3(0, 0, C)], [nb[3], Vector3(0, 0, -C)]]
	for k in corners.size():   # a tocha do chunk diagonal também acende o canto
		sources.append([corners[k], Vector3(C if k < 2 else -C, 0, C if k % 2 == 0 else -C)])
	for id in Blocks.light.size():
		if Blocks.light[id] == 0:
			continue
		for s in sources:
			var data: PackedByteArray = s[0]
			var i := data.find(id)
			while i != -1:
				var pos: Vector3 = Vector3(i % C, i / CC, (i / C) % C) + s[1] + Vector3.ONE * 0.5
				if pos.x > -Blocks.light[id] and pos.x < C + Blocks.light[id] and pos.z > -Blocks.light[id] and pos.z < C + Blocks.light[id]:
					out.append([pos, float(Blocks.light[id])])
				i = data.find(id, i + 1)
	return out
