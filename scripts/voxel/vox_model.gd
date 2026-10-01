class_name VoxModel
extends RefCounted
# Modelo de voxels no formato do MagicaVoxel (.vox), como o Trove: 1 pixel do sprite do Terraria = 1 voxel.
# Eixos como no MagicaVoxel: x largura, y profundidade (frente = y pequeno), z altura. Cada voxel é uma cor 0xRRGGBB.
# Convenções: 255,0,255 é o ponto de encaixe (pivô: empunhadura, osso), tirado da malha; as cores em `emit` brilham (vão no .json ao
# lado do .vox); preto puro vira quase preto. Receitas (recipes.gd) montam o modelo com as operações daqui; o .vox é só o resultado.

const ANCHOR := 0xff00ff
const NEAR_BLACK := 0x0c0c0c

var v := {}          # Vector3i -> int (0xRRGGBB)
var emit := {}       # int (0xRRGGBB) -> true: cores emissivas
var anchor := Vector3i.ZERO
var has_anchor := false


static func rgb(c: Color) -> int:
	return (c.to_rgba32() >> 8) & 0xffffff


static func color(c: int) -> Color:
	return Color((c >> 16 & 255) / 255.0, (c >> 8 & 255) / 255.0, (c & 255) / 255.0)


func put(p: Vector3i, c: int) -> void:
	if c == ANCHOR:
		anchor = p
		has_anchor = true
	else:
		v[p] = NEAR_BLACK if c == 0 else c


func box(a: Vector3i, b: Vector3i, c: int) -> void:   # cantos inclusivos, em qualquer ordem
	for z in range(mini(a.z, b.z), maxi(a.z, b.z) + 1):
		for y in range(mini(a.y, b.y), maxi(a.y, b.y) + 1):
			for x in range(mini(a.x, b.x), maxi(a.x, b.x) + 1):
				put(Vector3i(x, y, z), c)


# Cilindro vertical (eixo z) de raios rx, ry em torno de (cx, cy), de z0 a z1 inclusive.
func cylinder(cx: float, cy: float, rx: float, ry: float, z0: int, z1: int, c: int) -> void:
	for y in range(floori(cy - ry), ceili(cy + ry) + 1):
		for x in range(floori(cx - rx), ceili(cx + rx) + 1):
			if pow((x - cx) / (rx + 0.5), 2) + pow((y - cy) / (ry + 0.5), 2) <= 1.0:
				for z in range(z0, z1 + 1):
					put(Vector3i(x, y, z), c)


func mirror_x(axis2 := 0) -> void:   # espelha em x: x' = axis2 - x (axis2 = 0 espelha em volta da coluna x = 0)
	for p in v.keys():
		var q := Vector3i(axis2 - p.x, p.y, p.z)
		if not v.has(q):
			v[q] = v[p]


func merge(o: VoxModel, offset := Vector3i.ZERO) -> void:
	for p in o.v:
		v[p + offset] = o.v[p]
	for c in o.emit:
		emit[c] = true
	if o.has_anchor and not has_anchor:
		anchor = o.anchor + offset
		has_anchor = true


func bounds() -> Array:   # [mín, máx] inclusivos
	var lo := Vector3i(1 << 30, 1 << 30, 1 << 30)
	var hi := Vector3i(-(1 << 30), -(1 << 30), -(1 << 30))
	for p in v:
		lo = Vector3i(mini(lo.x, p.x), mini(lo.y, p.y), mini(lo.z, p.z))
		hi = Vector3i(maxi(hi.x, p.x), maxi(hi.y, p.y), maxi(hi.z, p.z))
	return [lo, hi]


func size() -> Vector3i:
	if v.is_empty():
		return Vector3i.ZERO
	var b := bounds()
	return b[1] - b[0] + Vector3i.ONE


# Troca as cores pela tabela {rgb: rgb}; o que não está nela fica.
func recolor(map: Dictionary) -> VoxModel:
	var m := VoxModel.new()
	m.anchor = anchor
	m.has_anchor = has_anchor
	for p in v:
		m.v[p] = map.get(v[p], v[p])
	for c in emit:
		m.emit[map.get(c, c)] = true
	return m


# Modelo a partir de um sprite: cada pixel opaco vira uma coluna de voxels ao longo de y; `depth.call(px, py, cor)` dá o
# intervalo [y0, y1) da coluna (vazio = sem voxel). O sprite vira o plano xz: x = pixel x, z = altura (de baixo para cima).
static func from_sprite(img: Image, depth: Callable) -> VoxModel:
	var m := VoxModel.new()
	var h := img.get_height()
	for py in h:
		for px in img.get_width():
			var c := img.get_pixel(px, py)
			if c.a <= 0.5:
				continue
			var col := rgb(c)
			var r: Vector2i = depth.call(px, py, col)
			for y in range(r.x, r.y):
				m.put(Vector3i(px, y, h - 1 - py), col)
	return m


# Profundidade "inflada": a coluna é tão grossa quanto a distância do pixel à borda do sprite (2 voxels por pixel de distância,
# no máximo 2 × cap), centrada: o contorno do sprite é o da vista de frente, e a de lado vira uma lente.
static func inflate(img: Image, cap: int) -> Callable:
	var w := img.get_width()
	var h := img.get_height()
	var solid := PackedByteArray()
	solid.resize(w * h)
	for py in h:
		for px in w:
			solid[py * w + px] = 1 if img.get_pixel(px, py).a > 0.5 else 0
	var dist := PackedInt32Array()
	dist.resize(w * h)
	for py in h:
		for px in w:
			if solid[py * w + px] == 0:
				continue
			var best := (cap + 1) * (cap + 1)
			for dy in range(-cap, cap + 1):
				var qy := py + dy
				for dx in range(-cap, cap + 1):
					var qx := px + dx
					if dx * dx + dy * dy < best and (qx < 0 or qy < 0 or qx >= w or qy >= h or solid[qy * w + qx] == 0):
						best = dx * dx + dy * dy
			dist[py * w + px] = mini(cap, maxi(1, roundi(sqrt(best))))
	return func(px: int, py: int, _c: int) -> Vector2i:
		var t := 2 * dist[py * w + px]
		var y0 := cap - t / 2
		return Vector2i(y0, y0 + t)


# Cap de profundidade automático: sprites pequenos ficam finos, grandes mais cheios (2 a 4 voxels para cada lado).
static func auto_cap(img: Image) -> int:
	return clampi(roundi(minf(img.get_width(), img.get_height()) / 8.0), 2, 4)


# ---------- arquivo .vox (MagicaVoxel) ----------

func write(path: String) -> void:
	var lo: Vector3i = bounds()[0]
	var cells := v.duplicate()
	if has_anchor:
		cells[anchor] = ANCHOR
		lo = Vector3i(mini(lo.x, anchor.x), mini(lo.y, anchor.y), mini(lo.z, anchor.z))
	var pal := {}   # rgb -> índice (1..255)
	var bits := 8
	var keys := _palette(cells, bits)
	while keys.size() > 255 and bits > 3:   # mais de 255 cores: perde os bits baixos de cada canal
		bits -= 1
		keys = _palette(cells, bits)
	var hi := lo
	for p in cells:
		hi = Vector3i(maxi(hi.x, p.x), maxi(hi.y, p.y), maxi(hi.z, p.z))
	var sz := hi - lo + Vector3i.ONE
	assert(sz.x <= 256 and sz.y <= 256 and sz.z <= 256, ".vox aceita até 256 voxels por lado")
	var colors := PackedInt32Array()
	for k in keys:
		colors.append(k)
		pal[k] = colors.size()
	var xyzi := PackedByteArray()
	xyzi.resize(4 + cells.size() * 4)
	xyzi.encode_s32(0, cells.size())
	var i := 4
	for p in cells:
		var q: Vector3i = p - lo
		xyzi[i] = q.x
		xyzi[i + 1] = q.y
		xyzi[i + 2] = q.z
		xyzi[i + 3] = pal[_q(cells[p], bits)] if cells[p] != ANCHOR else pal[ANCHOR]
		i += 4
	var rgba := PackedByteArray()
	rgba.resize(1024)
	for n in colors.size():
		rgba[n * 4] = colors[n] >> 16 & 255
		rgba[n * 4 + 1] = colors[n] >> 8 & 255
		rgba[n * 4 + 2] = colors[n] & 255
		rgba[n * 4 + 3] = 255
	var body := _chunk("SIZE", [sz.x, sz.y, sz.z], PackedByteArray()) + _chunk("XYZI", [], xyzi) + _chunk("RGBA", [], rgba)
	var head := StreamPeerBuffer.new()
	head.put_data("VOX ".to_ascii_buffer())
	head.put_32(150)
	head.put_data("MAIN".to_ascii_buffer())
	head.put_32(0)
	head.put_32(body.size())
	var bytes := head.data_array
	bytes.append_array(body)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(bytes)
	f.close()
	var side := path.get_basename() + ".json"
	if emit.is_empty():
		if FileAccess.file_exists(side):
			DirAccess.remove_absolute(side)
	else:
		var list := []
		for c in emit:
			list.append("#%06x" % _q(c, bits))
		FileAccess.open(side, FileAccess.WRITE).store_string(JSON.stringify({"emissive": list}))


static func _q(c: int, bits: int) -> int:   # cor com só `bits` bits por canal
	if bits >= 8 or c == ANCHOR:
		return c
	var m := (0xff << (8 - bits)) & 0xff
	return ((c >> 16 & m) << 16) | ((c >> 8 & m) << 8) | (c & m)


func _palette(cells: Dictionary, bits: int) -> Array:
	var seen := {}
	for p in cells:
		seen[_q(cells[p], bits)] = true
	return seen.keys()


# Chunk "id": `ints` (int32 em sequência) seguido de `data`.
static func _chunk(id: String, ints: Array, data: PackedByteArray) -> PackedByteArray:
	var b := StreamPeerBuffer.new()
	b.put_data(id.to_ascii_buffer())
	b.put_32(ints.size() * 4 + data.size())
	b.put_32(0)
	for n in ints:
		b.put_32(n)
	b.put_data(data)
	return b.data_array


# Lê o primeiro modelo de um .vox (SIZE, XYZI, RGBA; o resto do arquivo — cena, materiais — é ignorado) e o .json de cores
# emissivas ao lado, se existir. null se o arquivo não existe ou não é um .vox.
static func read(path: String) -> VoxModel:
	if not FileAccess.file_exists(path):
		return null
	var d := FileAccess.get_file_as_bytes(path)
	if d.size() < 20 or d.slice(0, 4).get_string_from_ascii() != "VOX ":
		return null
	var m := VoxModel.new()
	var pal := PackedInt32Array()
	var cells := []
	var have := false
	var i := 20   # depois do cabeçalho e do MAIN
	while i + 12 <= d.size():
		var id := d.slice(i, i + 4).get_string_from_ascii()
		var n := d.decode_s32(i + 4)
		var at := i + 12
		if id == "XYZI" and not have:
			have = true
			for k in d.decode_s32(at):
				cells.append([d[at + 4 + k * 4], d[at + 5 + k * 4], d[at + 6 + k * 4], d[at + 7 + k * 4]])
		elif id == "RGBA":
			for k in 256:
				pal.append((d[at + k * 4] << 16) | (d[at + k * 4 + 1] << 8) | d[at + k * 4 + 2])
		i = at + n
	if pal.is_empty():   # sem paleta: cinza (o MagicaVoxel sempre grava a dele)
		for k in 256:
			pal.append(k * 0x010101)
	for c in cells:
		m.put(Vector3i(c[0], c[1], c[2]), pal[maxi(c[3] - 1, 0)])
	var side := path.get_basename() + ".json"
	if FileAccess.file_exists(side):
		var j = JSON.parse_string(FileAccess.get_file_as_string(side))
		if j is Dictionary:
			for h in j.get("emissive", []):
				m.emit[Color(h).to_rgba32() >> 8 & 0xffffff] = true
	return m
