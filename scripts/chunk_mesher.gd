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
const HELL_COLOR := Color(1.0, 0.5, 0.25)   # o brilho do submundo é laranja
const LAVA_COLOR := Color(1.0, 0.45, 0.15)
const LAVA_GLOW := 0.9     # luz da lava no ar logo acima dela
const LIGHT_R := 10       # maior raio de luz de um bloco (margem da grade de propagação)
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
# water_out (opcional) recebe os arrays da superfície da água, se houver. models_out (opcional) recebe [id, posição local, luz (Color de _light)]
# de cada bloco com modelo voxel (shape "model"): o world.gd os instancia à parte, fora da malha.
static func build(d: PackedByteArray, nb: Array, tile_count: int, water_out := [], corners := [], models_out := []) -> Array:
	var solid := Blocks.cull
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
	var lights := _light_field(d, nb, corners)
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
					elif Blocks.model[b] != "":
						models_out.append([b, Vector3i(x, y, z), _light(p, hts, lights, x, y, z)])
					else:
						_shape(a, b, Vector3(x, y, z), tw, _light(p, hts, lights, x, y, z), p, pi)
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
						light.r *= _underwater(p, x + dir.x, ny, z + dir.z)
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
						cols.append(Color(l * light.r, l * light.g, 0, light.a))
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


# Luz (r = céu, g = força da luz das fontes, a = cor dela empacotada: pack_hue) na célula (x, y, z) do chunk (ou 1 além da borda em X e Z): o céu cai com a
# profundidade abaixo do chão da coluna (tronco e folhas não contam), menos uma sombra fixa sob a copa; a tocha cai
# com a distância. No submundo há um brilho quente de fundo.
static func _light(p: PackedByteArray, hts: PackedInt32Array, lights: Array, x: int, y: int, z: int) -> Color:
	var col := (x + 1) + (z + 1) * P
	var ground := hts[col]
	if ground < 0:
		var solid := Blocks.cull
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
	var hell := clampf((WorldGen.UNDERWORLD_TOP + 2.0 - y) / 8.0, 0.0, 1.0) * HELL_AMBIENT
	var r := hell * HELL_COLOR.r
	var g := hell * HELL_COLOR.g
	var bl := hell * HELL_COLOR.b
	if lights[0] != null:   # campo das fontes (tochas, orbes...): _light_field
		var fi := col + (y + 1) * PP
		r = maxf(r, lights[0][fi])
		g = maxf(g, lights[1][fi])
		bl = maxf(bl, lights[2][fi])
	if lights[3]:   # lava logo abaixo (até 6 blocos de ar) clareia de laranja
		var lava: int = Blocks.ids.lava
		for dy in range(1, 7):
			if y - dy < 0:
				break
			var under := p[col + (y - dy + 1) * PP]
			if Blocks.liquid[under] and Blocks.liquid_kind[under] == lava:
				var k := (1.0 - dy / 7.0) * LAVA_GLOW
				r = maxf(r, k * LAVA_COLOR.r)
				g = maxf(g, k * LAVA_COLOR.g)
				bl = maxf(bl, k * LAVA_COLOR.b)
				break
			if Blocks.cull[under]:
				break
	var m := maxf(r, maxf(g, bl))
	if m <= 0.0:
		return Color(sky, 0.0, 0.0, 1.0)
	return Color(sky, m, 0.0, pack_hue(r / m, g / m, bl / m))


# Cor da luz num canal de 8 bits (o alfa do vértice): 3 bits de vermelho, 3 de verde, 2 de azul. A cor é a mesma nos 4 vértices da
# face (a luz é por face), então não há interpolação que estrague o pacote; o chunk.gdshader desfaz.
static func pack_hue(r: float, g: float, b: float) -> float:
	return ((roundi(r * 7.0) << 5) | (roundi(g * 7.0) << 2) | roundi(b * 3.0)) / 255.0


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


# Inclinação do trilho no eixo de passo s (1 = x, P = z): altura do fim de baixo do eixo (0) e do de cima (1); rampa só se o vizinho do mesmo nível não existe.
static func _track_rise(p: PackedByteArray, pi: int, b: int, s: int) -> Vector2:
	if p[pi + s + PP] == b and p[pi + s] != b:
		return Vector2(0, 1)
	if p[pi - s + PP] == b and p[pi - s] != b:
		return Vector2(1, 0)
	return Vector2.ZERO


# Placa do trilho ao longo de x (ou de z), com a altura h.x na ponta de trás e h.y na da frente; dupla face.
static func _track_quad(a: Dictionary, pos: Vector3, along_x: bool, h: Vector2, u0: float, tw: float, c: Color) -> void:
	var base: int = a.v.size()
	for k in 4:
		var s := float(k in [2, 3])   # posição ao longo do eixo
		var t := float(k in [1, 2])   # posição de lado
		a.v.append(pos + (Vector3(s, 0.05 + lerpf(h.x, h.y, s), t) if along_x else Vector3(t, 0.05 + lerpf(h.x, h.y, s), s)))
		a.n.append(Vector3.UP)
		a.c.append(c)
		a.uv.append(Vector2(u0 + s * tw, t))
	a.i.append_array([base, base + 1, base + 2, base, base + 2, base + 3, base, base + 2, base + 1, base, base + 3, base + 2])


# Formas não cúbicas. Tocha: cabo fino (textura lateral) + chama (textura do topo), sempre acesas.
# Planta: dois quadros em cruz, frente e verso; balança no shader (b = 0.5).
static func _shape(a: Dictionary, b: int, pos: Vector3, tw: float, light: Color, p: PackedByteArray, pi: int) -> void:
	match Blocks.shape[b]:
		"track":   # trilho: placa rente ao chão; segue os vizinhos (em x, em z ou nos dois) e sobe em rampa quando o vizinho do lado está um bloco acima
			var u0 := tiles_of(b, 0) * tw
			var c := Color(light.r * SHADE[2], light.g * SHADE[2], 0.0, light.a)
			var has_x := false
			var has_z := false
			for o in [1, -1]:
				has_x = has_x or p[pi + o] == b or p[pi + o + PP] == b or p[pi + o - PP] == b
			for o in [P, -P]:
				has_z = has_z or p[pi + o] == b or p[pi + o + PP] == b or p[pi + o - PP] == b
			if has_x or not has_z:
				_track_quad(a, pos, true, _track_rise(p, pi, b, 1), u0, tw, c)
			if has_z:
				_track_quad(a, pos, false, _track_rise(p, pi, b, P), u0, tw, c)
		"torch":
			var stick := tiles_of(b, 0) * tw
			var flame := tiles_of(b, 2) * tw
			var wall := Vector3.ZERO   # sem chão embaixo e com parede ao lado: a tocha sai da parede, inclinada para fora (em degraus)
			if Blocks.solid[p[pi - PP]] == 0:
				for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					if Blocks.solid[p[pi + d.x + d.y * P]] == 1:
						wall = Vector3(d.x, 0, d.y)
						break
			if wall != Vector3.ZERO:
				for f in 6:
					var sh: float = SHADE[f]
					for k in 3:
						_face(a, pos + Vector3(0.44, 0.22 + 0.17 * k, 0.44) + wall * (0.44 - 0.09 * k), f, Vector3(0.12, 0.2, 0.12), stick, tw, Color(sh, sh, 0))
					_face(a, pos + Vector3(0.41, 0.73, 0.41) + wall * 0.12, f, Vector3(0.18, 0.2, 0.18), flame, tw, Color(1, 1, 0.25))
				return
			for f in 6:
				var sh: float = SHADE[f]
				_face(a, pos + Vector3(0.44, 0, 0.44), f, Vector3(0.12, 0.55, 0.12), stick, tw, Color(sh, sh, 0))
				_face(a, pos + Vector3(0.41, 0.55, 0.41), f, Vector3(0.18, 0.2, 0.18), flame, tw, Color(1, 1, 0.25))
		"door":   # porta aberta: um painel fino na borda do bloco; a passagem fica livre
			var u0 := tiles_of(b, 0) * tw
			for f in 6:
				var sh: float = SHADE[f]
				_face(a, pos, f, Vector3(0.14, 1.0, 1.0), u0, tw, Color(sh * light.r, sh * light.g, 0.0, light.a))
		"rope":   # corda: um fio fino no meio do bloco, com a luz do lugar
			var u0 := tiles_of(b, 0) * tw
			for f in 6:
				var sh: float = SHADE[f]
				_face(a, pos + Vector3(0.43, 0, 0.43), f, Vector3(0.14, 1.0, 0.14), u0, tw, Color(sh * light.r, sh * light.g, 0.0, light.a))
		"glowstick":   # graveto luminoso: uma barrinha no meio do bloco, acesa sozinha (b = 1)
			var u0 := tiles_of(b, 0) * tw
			for f in 6:
				_face(a, pos + Vector3(0.43, 0, 0.43), f, Vector3(0.14, 0.45, 0.14), u0, tw, Color(light.r, light.g, 1.0, light.a))
		"cactus":   # cacto: coluna de 0,6 de largura, com a luz do lugar (atravessável, como no Terraria)
			var u0 := tiles_of(b, 0) * tw
			for f in 6:
				var sh: float = SHADE[f]
				_face(a, pos + Vector3(0.2, 0, 0.2), f, Vector3(0.6, 1.0, 0.6), u0, tw, Color(sh * light.r, sh * light.g, 0.0, light.a))
		"crystal":   # Life Crystal: dois quadros em cruz do tamanho do bloco, sem balançar e brilhando sozinho (b = 1)
			var u0 := tiles_of(b, 0) * tw
			var c := Color(light.r, light.g, 1.0, light.a)
			for pair in [[Vector3(0.05, 0, 0.05), Vector3(0.95, 0, 0.95)], [Vector3(0.95, 0, 0.05), Vector3(0.05, 0, 0.95)]]:
				_vquad(a, pos + pair[0], pos + pair[1], 0.95, u0, tw, c)
				_vquad(a, pos + pair[1], pos + pair[0], 0.95, u0, tw, c)
		"plant":
			var u0 := tiles_of(b, 0) * tw
			var c := Color(light.r * 0.95, light.g * 0.95, 0.5, light.a)
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
		var c_low := Color(sh * light.r, sh * light.g, glow, light.a)
		var c_high := Color(sh * light.r, sh * light.g, 1.0, light.a)
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


# Fontes de luz (tochas, orbes, cristais...) no chunk e nos vizinhos: [[centro local, raio, cor], ...].
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
					out.append([pos, float(Blocks.light[id]), Blocks.light_color[id]])
				i = data.find(id, i + 1)
	return out


# Luz das fontes já espalhada: [r, g, b (PackedFloat32Array no índice da cópia com margem; null sem fonte por perto), o chunk tem lava].
# A luz anda de célula em célula pelo ar (não atravessa parede; dobra esquinas) e cai com a distância em linha reta até a fonte.
# ponytail: ~5 ms por fonte por chunk (GDScript, em thread); uma base com dezenas de tochas atrasa a remontagem. Subir para um campo
# de luz por chunk guardado no World (atualizado só onde muda) se pesar.
static func _light_field(d: PackedByteArray, nb: Array, corners: Array) -> Array:
	var lights := _lights(d, nb, corners)
	var has_lava := false
	for id in Blocks.level_ids[Blocks.ids.lava]:
		has_lava = has_lava or (id > 0 and d.find(id) != -1)
	if lights.is_empty():
		return [null, null, null, has_lava]
	var R := LIGHT_R
	var W := C + 2 * R
	var y0 := H
	var y1 := 0
	for l in lights:
		y0 = mini(y0, floori(l[0].y) - int(l[1]))
		y1 = maxi(y1, floori(l[0].y) + int(l[1]) + 1)
	y0 = maxi(y0, 0)
	y1 = mini(y1, H)
	# blocos da região (o chunk e R blocos dos 8 vizinhos), linha a linha
	var E := PackedByteArray()
	var c := func(k: int) -> PackedByteArray: return corners[k] if k < corners.size() else E
	var rows := [[c.call(3), nb[3], c.call(1)], [nb[1], d, nb[0]], [c.call(2), nb[2], c.call(0)]]   # [z: -1, 0, +1][x: -1, 0, +1]
	var spans := [[C - R, C], [0, C], [0, R]]   # trecho local de cada vizinho que cai na região
	var grid := PackedByteArray()
	var gap := PackedByteArray()
	gap.resize(C)
	for y in range(y0, y1):
		for zc in 3:
			for z in range(spans[zc][0], spans[zc][1]):
				for xc in 3:
					var data: PackedByteArray = rows[zc][xc]
					var o := y * CC + z * C
					grid.append_array(gap.slice(0, spans[xc][1] - spans[xc][0]) if data.is_empty() else data.slice(o + spans[xc][0], o + spans[xc][1]))
	var WW := W * W
	var out := [PackedFloat32Array(), PackedFloat32Array(), PackedFloat32Array(), has_lava]
	for k in 3:
		out[k].resize(PP * (H + 2))
	var fr: PackedFloat32Array = out[0]
	var fg: PackedFloat32Array = out[1]
	var fb: PackedFloat32Array = out[2]
	var seen := PackedInt32Array()
	seen.resize(grid.size())
	var cull := Blocks.cull
	var queue := PackedInt32Array()
	var steps := PackedByteArray()
	var n := 0
	for l in lights:
		n += 1
		var lx := floori(l[0].x) + R
		var ly := floori(l[0].y) - y0
		var lz := floori(l[0].z) + R
		if lx < 0 or lx >= W or lz < 0 or lz >= W or ly < 0:
			continue
		var radius: float = l[1]
		var col: Color = l[2]
		var budget := int(radius * 1.5)
		queue.clear()
		steps.clear()
		queue.append(lx + lz * W + ly * WW)
		steps.append(0)
		seen[queue[0]] = n
		var head := 0
		while head < queue.size():
			var i := queue[head]
			var s := steps[head]
			head += 1
			var x := i % W
			var z := (i / W) % W
			var y := i / WW
			var k := 1.0 - sqrt((x - lx) * (x - lx) + (y - ly) * (y - ly) + (z - lz) * (z - lz)) / radius
			if k <= 0.0:
				continue
			if x >= R - 1 and x <= R + C and z >= R - 1 and z <= R + C:
				var fi := (x - R + 1) + (z - R + 1) * P + (y + y0 + 1) * PP
				fr[fi] = maxf(fr[fi], col.r * k)
				fg[fi] = maxf(fg[fi], col.g * k)
				fb[fi] = maxf(fb[fi], col.b * k)
			if s >= budget:
				continue
			for j in 6:
				var ni := i
				match j:
					0:
						if x == W - 1: continue
						ni += 1
					1:
						if x == 0: continue
						ni -= 1
					2:
						if z == W - 1: continue
						ni += W
					3:
						if z == 0: continue
						ni -= W
					4:
						if y == y1 - y0 - 1: continue
						ni += WW
					5:
						if y == 0: continue
						ni -= WW
				if seen[ni] != n and not cull[grid[ni]]:
					seen[ni] = n
					queue.append(ni)
					steps.append(s + 1)
	return out
