class_name VoxRecipes
# Receitas dos modelos voxel: cada uma monta um VoxModel com as operações de vox_model.gd a partir do sprite da wiki e da paleta dele.
# `find(nome)` entrega o modelo na ordem: assets/models/ (retoque à mão no MagicaVoxel) → assets/models/gen/ (gerado pelo build.gd no
# update.sh) → a receita em memória (testes e sessão sem arquivos) → null (o chamador usa o automático: sprite inflado).
# Parâmetros por modelo (sprite da wiki, cores emissivas...) ficam em data/<pacote>/models.json; aqui só a forma.
# Convenção do personagem: cada peça do corpo tem o pivô no voxel de encaixe (0,0,0) e os mesmos nomes de articulação do
# player_model.gd; a armadura é uma casca por peça, no mesmo quadro.

const DIRS := ["res://assets/models/", "res://assets/models/gen/"]
const SPECS := "res://data/base/models.json"
const LOOK := {"skin": "#f0b890", "hair": "#5a3220", "shirt": "#c0503c", "pants": "#3c4c98"}   # cores-etiqueta do corpo; o personagem troca por estas
const EYE := 0xffffff
const IRIS := 0x3a68c0
const PUPIL := 0x10131c
const BOOT := 0x5a3a2a
# Pivôs do corpo em blocos, como no player_model.gd: upper (cintura) no mundo; head e arm em relação a upper (arm: x de um lado); leg no mundo.
const PIV := {"upper": Vector3(0, 0.72, 0), "head": Vector3(0, 0.56, 0), "arm": Vector3(0.232, 0.47, 0), "leg": Vector3(0.09375, 0.769, 0)}
const EYE_L := Vector3(3, -5.5, 5)    # olhos: ponto do modelo (voxels, quadro da cabeça) onde fica o centro da base de body_eye_l / body_eye_r
const EYE_R := Vector3(-2, -5.5, 5)

static var _specs := {}
static var _models := {}    # arquivo -> VoxModel (ou null)
static var _made := {}      # receita -> {arquivo: VoxModel}
static var _meshes := {}


static func specs() -> Dictionary:
	if _specs.is_empty():
		_specs = Blocks.read(SPECS)
	return _specs


static func clear_cache() -> void:
	_models.clear()
	_made.clear()
	_meshes.clear()
	_specs.clear()


# Modelo `name` (ou a peça `part` dele: arquivo name_part); null se não há arquivo nem receita.
static func find(name: String, part := "") -> VoxModel:
	var file := name if part == "" else name + "_" + part
	if not _models.has(file):
		var m: VoxModel = null
		for d in DIRS:
			m = VoxModel.read(d + file + ".vox")
			if m:
				break
		_models[file] = m if m else make(name).get(file)
	return _models[file]


# Todos os arquivos que a receita `name` gera ({arquivo: VoxModel}); {} se não há receita com esse nome.
static func make(name: String) -> Dictionary:
	if not _made.has(name):
		var spec: Dictionary = specs().get(name, {})
		var out := {}
		match spec.get("recipe", name):
			"body":
				out = body()
			"loom":
				out = {name: loom(spec)}
			"armor_set":
				out = armor_set(name, spec)
			"armor_plate":
				out = armor_plate(name, spec)
			"prop":
				out = {name: prop(spec)}
			"weapon":
				var w := weapon(spec)
				if w:
					out = {name: w}
		for f in out:   # cores emissivas do models.json
			for h in spec.get("emissive", []):
				out[f].emit[Color(h).to_rgba32() >> 8 & 0xffffff] = true
		_made[name] = out
	return _made[name]


# Sprite da wiki pelo nome do arquivo (sem .png), ou null se não foi baixado.
static func sprite(wiki: String) -> Image:
	return Atlas.wiki_image({"wiki": wiki})


# Cap (meia espessura máxima, em voxels) do modelo automático de um item: lâmina e arco finos, arma de fogo e varinha cheias, cabeça de
# flail redonda, ferramenta fina; o resto segue o tamanho do sprite. Item sem regra aqui = `VoxModel.auto_cap`.
static func auto_cap(name: String, img: Image) -> int:
	var d: Dictionary = Items.defs[Items.ids[name]] if Items.ids.has(name) else {}
	var side := mini(img.get_width(), img.get_height())
	if d.has("flail"):
		return clampi(side / 6, 3, 6)
	if d.has("pick_power") or d.has("axe_power") or d.has("hammer_power") or d.get("ammo", "") == "arrow" or (d.get("damage", 0) > 0 and not d.has("ammo") and not d.has("shoot") and not d.has("throw")):
		return 2   # ferramenta, arco, lâmina
	if d.has("shoot") or d.has("cost") or d.has("ammo"):
		return clampi(side / 5, 2, 4)   # arma de fogo, varinha, livro
	return VoxModel.auto_cap(img)


# Arma/item com receita própria (models.json, `recipe: weapon`): o sprite da wiki inflado com `cap` voxels (padrão: auto_cap), ou esférico com
# `round` (bomba, granada); `emissive` lista as cores que brilham. null sem o sprite baixado (o automático assume).
static func weapon(spec: Dictionary) -> VoxModel:
	var img := sprite(spec.get("wiki", ""))
	if img == null:
		return null
	img = img.duplicate()
	img.convert(Image.FORMAT_RGBA8)
	var cap: int = mini(img.get_width(), img.get_height()) / 2 if spec.get("round", false) else spec.get("cap", VoxModel.auto_cap(img))
	return VoxModel.from_sprite(img, VoxModel.inflate(img, cap))


# ---------- malhas com cache ----------

# Item na mão/solto: [malha, material]. Modelo = campo `model` do item (senão o nome); sem modelo, o sprite (`icon`) inflado.
static func item_mesh(name: String, icon: Image, length: float) -> ArrayMesh:
	var key := ["item", name, length]
	if not _meshes.has(key):
		var m := find(name)
		var dim := 0
		if m == null:
			m = VoxModel.from_sprite(icon, VoxModel.inflate(icon, auto_cap(name, icon)))
			dim = maxi(icon.get_width(), icon.get_height())
		else:
			dim = maxi(m.size().x, m.size().z)
		var lo: Vector3i = m.bounds()[0]
		_meshes[key] = VoxMesh.build(m, length / dim, true, Vector3(0, lo.y + m.size().y / 2.0, lo.z))   # origem: canto de baixo à esquerda, no meio da espessura
	return _meshes[key]


# Peça da armadura/corpo (pivô no encaixe), na escala do personagem.
static func part_mesh(name: String, part: String, look := {}, vs := VoxMesh.V) -> ArrayMesh:
	var key := ["part", name, part, look, vs]
	if not _meshes.has(key):
		var m := find(name, part)
		if m == null:
			return null
		if not look.is_empty():
			m = m.recolor(look_map(look))
		_meshes[key] = VoxMesh.build(m, vs)
	return _meshes[key]


# Bloco com modelo: o modelo inteiro cabe em `tiles.x` tiles de largura (1 tile = 0,6 bloco); base no chão, centrado.
static func block_mesh(name: String, tiles: Vector2) -> ArrayMesh:
	var key := ["block", name, tiles]
	if not _meshes.has(key):
		var m := find(name)
		if m == null:
			return null
		_meshes[key] = VoxMesh.build(m, tiles.x * 0.6 / m.size().x)
	return _meshes[key]


# ---------- personagem ----------

static func tone(c: Color, k: int) -> int:   # 0 luz, 1 base, 2 sombra
	return VoxModel.rgb(c.lightened(0.14) if k == 0 else c if k == 1 else c.darkened(0.22))


# {rgb etiqueta: rgb do personagem}: pele, cabelo, camisa e calça nos três tons.
static func look_map(look: Dictionary) -> Dictionary:
	var map := {}
	for key in LOOK:
		for k in 3:
			map[tone(Color(LOOK[key]), k)] = tone(look[key], k)
	return map


# Posição (em blocos, relativa ao pivô da peça) de um ponto do modelo em coordenadas de voxel contínuas, para quem prende algo nela.
static func pivot_pos(p: Vector3) -> Vector3:
	return Vector3(-(p.x - 0.5), p.z - 0.5, p.y - 0.5) * VoxMesh.V


static func body() -> Dictionary:
	var t := func(key: String, k: int) -> int: return tone(Color(LOOK[key]), k)
	var out := {}
	# cabeça: cubo de 11 com os cantos verticais cortados; olhos à parte (piscam; ficam 1 voxel à frente do rosto, senão o piscar abre um buraco escuro), nariz, orelhas e boca
	var head := VoxModel.new()
	head.put(Vector3i.ZERO, VoxModel.ANCHOR)
	for z in range(1, 12):
		for y in range(-5, 6):
			for x in range(-5, 6):
				if (absi(x) == 5 and absi(y) == 5) or (z == 11 and (absi(x) == 5 or absi(y) == 5)) or (z == 1 and absi(x) == 5 and absi(y) >= 4):
					continue
				head.put(Vector3i(x, y, z), t.call("skin", 2) if absi(x) == 5 or z == 1 else t.call("skin", 0) if z == 11 else t.call("skin", 1))
	head.box(Vector3i(-1, -5, 3), Vector3i(1, -5, 3), t.call("skin", 2))   # boca
	head.put(Vector3i(0, -6, 5), t.call("skin", 2))                        # nariz
	head.put(Vector3i(0, -6, 4), t.call("skin", 2))
	for side in [-1, 1]:
		head.box(Vector3i(side * 6, -1, 4), Vector3i(side * 6, 0, 6), t.call("skin", 2))   # orelhas
	out["body_head"] = head
	# cabelo: casca por fora do crânio (franja, nuca, laterais acima das orelhas) e tufos espetados
	var hair := VoxModel.new()
	hair.put(Vector3i.ZERO, VoxModel.ANCHOR)
	for z in range(1, 13):
		for y in range(-6, 7):
			for x in range(-6, 7):
				var shell := absi(x) == 6 or absi(y) == 6 or z == 12
				var top := z >= 10
				if not shell or (absi(x) == 6 and absi(y) == 6) or (z == 12 and (absi(x) == 6 or absi(y) == 6)):
					continue
				var keep := top or (y > 0 and z >= 3) or (absi(x) == 6 and z >= 8)
				if y == -6 and (z < 10 or (z == 10 and absi(x) in [1, 4])):   # franja irregular
					keep = false
				if keep:
					hair.put(Vector3i(x, y, z), t.call("hair", 0) if z == 12 else t.call("hair", 2) if y == 6 or absi(x) == 6 else t.call("hair", 1))
	for s in [[-4, -1, 3], [-1, 0, 4], [2, -1, 3], [4, 1, 2], [0, 3, 2]]:   # tufos: x, y, altura
		hair.box(Vector3i(s[0], s[1], 13), Vector3i(s[0] + 1, s[1] + 1, 12 + s[2]), t.call("hair", 0))
	out["body_hair"] = hair
	for side in ["l", "r"]:   # olho 2x1x3: branco fora, íris e pupila para o meio do rosto
		var eye := VoxModel.new()
		var inner := 0 if side == "l" else 1   # x da coluna de dentro
		eye.box(Vector3i(0, 0, 0), Vector3i(1, 0, 2), EYE)
		eye.box(Vector3i(inner, 0, 1), Vector3i(inner, 0, 1), IRIS)
		eye.put(Vector3i(inner, 0, 0), PUPIL)
		out["body_eye_" + side] = eye
	# tronco: camiseta, cós da calça, ombros e pescoço
	var torso := VoxModel.new()
	torso.put(Vector3i.ZERO, VoxModel.ANCHOR)
	for z in range(1, 14):
		for y in range(-3, 4):
			for x in range(-5, 6):
				if (absi(x) == 5 and absi(y) == 3) or (z == 13 and absi(x) == 5):
					continue
				var c: int = t.call("shirt", 1)
				if z <= 3:
					c = t.call("pants", 1) if z > 1 else t.call("pants", 2)
				elif absi(x) == 5 or z == 4:
					c = t.call("shirt", 2)
				elif z >= 12:
					c = t.call("shirt", 0)
				torso.put(Vector3i(x, y, z), c)
	torso.box(Vector3i(-1, -1, 14), Vector3i(1, 1, 15), t.call("skin", 2))   # pescoço
	out["body_torso"] = torso
	# braço: manga, antebraço e mão; o ombro é o encaixe
	var arm := VoxModel.new()
	arm.put(Vector3i.ZERO, VoxModel.ANCHOR)
	for z in range(-16, 3):
		for y in range(-2, 3):
			for x in range(-2, 3):
				if z == 2 and (absi(x) == 2 or absi(y) == 2):
					continue
				var c: int = t.call("shirt", 1) if z >= -8 else t.call("skin", 1)
				if z == -8:
					c = t.call("shirt", 2)
				elif absi(x) == 2 and z < -8:
					c = t.call("skin", 2)
				elif z <= -14:
					c = t.call("skin", 2) if z == -16 else t.call("skin", 0)
				arm.put(Vector3i(x, y, z), c)
	out["body_arm"] = arm
	# perna: calça e bota com a ponta para a frente; o quadril é o encaixe
	var leg := VoxModel.new()
	leg.put(Vector3i.ZERO, VoxModel.ANCHOR)
	for z in range(-20, 2):
		for y in range(-2, 3):
			for x in range(-2, 3):
				leg.put(Vector3i(x, y, z), BOOT if z <= -16 else t.call("pants", 2) if absi(x) == 2 or z == -8 else t.call("pants", 1))
	leg.box(Vector3i(-2, -4, -20), Vector3i(2, -3, -18), BOOT)   # ponta da bota
	leg.box(Vector3i(-2, -2, -16), Vector3i(2, 2, -16), 0x73503c)  # cano da bota (luz)
	out["body_leg"] = leg
	# braço da 1ª pessoa: punho no encaixe (a mão) e antebraço + manga esticados para cima até o ombro, fora da tela; 1 voxel = 0,02 bloco (VoxMesh.FP_V)
	var fp := VoxModel.new()
	fp.put(Vector3i.ZERO, VoxModel.ANCHOR)
	for z in range(1, 93):
		for y in range(-2, 3):
			for x in range(-2, 3):
				var c: int = t.call("shirt", 1) if z >= 18 else t.call("skin", 1)
				if z == 18:
					c = t.call("shirt", 2)   # punho da manga
				elif z <= 6 and (z == 1 or y == -2):
					c = t.call("skin", 1) if z == 1 else t.call("skin", 0)   # ponta do punho e dedos à frente (tons claros)
				if z <= 6 and (absi(x) == 2 and absi(y) == 2):
					continue   # punho de cantos cortados
				fp.put(Vector3i(x, y, z), c)
	out["body_fparm"] = fp
	return out


# ---------- Living Loom ----------

# Sprite do bloco colocado (48x48 = 3x3 tiles) com profundidade inventada: base cheia, dois montantes e o fio de trás mais fundos
# que a trama de vinhas, cujos fios claros saem 1 voxel para a frente.
static func loom(spec: Dictionary) -> VoxModel:
	var img := sprite(spec.get("wiki", ""))
	if img == null:
		var m := VoxModel.new()   # sem o sprite baixado: caixa de madeira na cor do bloco
		m.box(Vector3i(0, 0, 0), Vector3i(47, 9, 11), 0x744c40)
		m.box(Vector3i(4, 2, 12), Vector3i(11, 7, 44), 0x956a4b)
		m.box(Vector3i(36, 2, 12), Vector3i(43, 7, 44), 0x956a4b)
		m.box(Vector3i(12, 4, 12), Vector3i(35, 5, 40), 0x345401)
		return m
	var d: int = spec.get("depth", 10)
	var m := VoxModel.from_sprite(img, func(px: int, py: int, c: int) -> Vector2i:
		var green: bool = (c >> 8 & 255) > (c >> 16 & 255)
		if py >= 36:
			return Vector2i(0, d)
		if green:
			return Vector2i(d / 2 - 2, d / 2 + 1) if (c >> 8 & 255) > 0x7a else Vector2i(d / 2 - 1, d / 2 + 1)
		return Vector2i(2, d - 2))
	if spec.get("sides", false):
		side_texture(m, img, {})
	return m


# ---------- estações, baús e gemas (leva 1) ----------

# Laterais com a textura da frente: as 2 colunas de cada ponta da linha amostram o sprite de dentro para o centro (profundidade y = distância
# da borda); contorno escuro, vão e cores emissivas ficam como estão. Padrão de toda estrutura com modelo (`"sides": true` no models.json).
static func side_texture(m: VoxModel, img: Image, glow: Dictionary) -> void:
	var lo := {}
	var hi := {}
	for p in m.v:
		lo[p.z] = mini(lo.get(p.z, 999), p.x)
		hi[p.z] = maxi(hi.get(p.z, -999), p.x)
	for p in m.v.keys():
		var left: bool = p.x <= lo[p.z] + 1
		if not left and p.x < hi[p.z] - 1:
			continue
		var px: int = (lo[p.z] + 2 if left else hi[p.z] - 2) + maxi(p.y, 0) * (1 if left else -1)
		var c := img.get_pixel(clampi(px, 0, img.get_width() - 1), img.get_height() - 1 - p.z)
		if c.a > 0.5 and c.get_luminance() >= 0.2 and not glow.has(VoxModel.rgb(c)):
			m.v[p] = VoxModel.rgb(c)


# Sprite da wiki (vista de frente) com profundidade: extrusão reta de `depth` voxels (padrão 10) ou, com `round` (teto, em voxels), "inflada" (gema, altar).
# `profile: [[linha0, linha1, y0, y1, coluna0?, coluna1?]]`: faixa de profundidade [y0, y1) (y < 0 = sai da frente) das linhas/colunas do sprite (domo da tampa, chifre fino da bigorna). `recess`: as cores emissivas começam essa quantidade de voxels atrás da frente (boca da fornalha). `legs: [linha0, linha1]`: nessas linhas do
# sprite só sobram 3 voxels em cada face (pernas da bancada: frente e trás, vão no meio). `sides`: laterais com a textura da frente (amostra o sprite do canto para dentro). `plain`: cor do contorno escuro do sprite no miolo da
# profundidade (só a frente e o fundo mantêm o contorno; senão os lados viram lajes pretas). Sem o sprite baixado: caixa na cor `color`.
static func prop(spec: Dictionary) -> VoxModel:
	var img := sprite(spec.get("wiki", ""))
	var d: int = spec.get("depth", 10)
	if img == null:
		var m := VoxModel.new()
		m.box(Vector3i(0, 0, 0), Vector3i(23, d - 1, 15), Color(spec.get("color", "#8b6a4a")).to_rgba32() >> 8 & 0xffffff)
		return m
	var glow := {}
	for h in spec.get("emissive", []):
		glow[Color(h).to_rgba32() >> 8 & 0xffffff] = true
	var recess: int = spec.get("recess", 0)
	var profile: Array = spec.get("profile", [])
	var m := VoxModel.from_sprite(img, VoxModel.inflate(img, spec.round) if spec.has("round") else func(px: int, py: int, c: int) -> Vector2i:
		var r := Vector2i(recess if glow.has(c) else 0, d)
		for e in profile:   # o último que casa vence
			if py >= e[0] and py <= e[1] and (e.size() < 6 or (px >= e[4] and px <= e[5])):
				r = Vector2i(e[2], e[3])
		return r)
	if spec.has("legs"):
		var rows: Array = spec.legs
		for p in m.v.keys():
			var row: int = img.get_height() - 1 - p.z
			if row >= rows[0] and row <= rows[1] and p.y >= 3 and p.y < d - 3:
				m.v.erase(p)
	if spec.has("plain"):
		var plain := Color(spec.plain).to_rgba32() >> 8 & 0xffffff
		for p in m.v.keys():
			if p.y > 0 and p.y < d - 1 and not glow.has(m.v[p]) and VoxModel.color(m.v[p]).get_luminance() < 0.2:
				m.v[p] = plain
	if spec.get("sides", false):
		side_texture(m, img, glow)
	return m


# ---------- armaduras de placa e de pano (leva 2) ----------

# Paleta do conjunto a partir dos ícones das peças: [luz, base, sombra, destaque] (0xRRGGBB). Luz/base/sombra = médias de faixas de luminância
# (sem o contorno quase preto); destaque = o pixel mais saturado e claro (gema, brasa, debrum). `light`/`base`/`dark`/`accent` no models.json
# retocam; `colors` vale se faltar o ícone (sessão sem sprites).
static func palette(spec: Dictionary) -> Array:
	var px: Array[Color] = []
	for n in spec.get("icons", []):
		var img := sprite(n)
		if img == null:
			continue
		for y in img.get_height():
			for x in img.get_width():
				var c := img.get_pixel(x, y)
				if c.a > 0.5 and c.get_luminance() > 0.07:
					px.append(c)
	var pal := []
	if px.size() < 20:
		pal = spec.get("colors", ["#c8c8c8", "#8a8a8a", "#4a4a4a", "#d8c040"]).map(func(h): return VoxModel.rgb(Color(h)))
	else:
		px.sort_custom(func(a, b): return a.get_luminance() > b.get_luminance())
		var n := px.size()
		var avg := func(from: int, to: int) -> int:
			var sum := Color(0, 0, 0)
			for i in range(from, to):
				sum += px[i]
			return VoxModel.rgb(sum / maxi(1, to - from))
		var best := px[0]
		for c in px:
			if c.s * c.v > best.s * best.v:
				best = c
		pal = [avg.call(0, maxi(1, n / 5)), avg.call(n / 5, n * 3 / 5), avg.call(n * 3 / 5, maxi(n * 3 / 5 + 1, n * 17 / 20)), VoxModel.rgb(best)]
	var keys := ["light", "base", "dark", "accent"]
	for i in 4:
		if spec.has(keys[i]):
			pal[i] = VoxModel.rgb(Color(spec[keys[i]]))
	return pal


static func _tone(c: int, k: float) -> int:   # k > 0 clareia, k < 0 escurece
	var col := VoxModel.color(c)
	return VoxModel.rgb(col.lightened(k) if k > 0 else col.darkened(-k))


# Casca de caixa com as quinas verticais e os cantos cortados (como `shell`), pintada por `paint.call(x, y, z)`; a metade de trás é um tom mais
# escura. `skip.call(x, y, z)` -> true deixa o voxel de fora (abertura).
static func _plates(m: VoxModel, lo: Vector3i, hi: Vector3i, paint: Callable, skip := Callable()) -> void:
	var mid := (lo.y + hi.y) / 2
	for z in range(lo.z, hi.z + 1):
		for y in range(lo.y, hi.y + 1):
			for x in range(lo.x, hi.x + 1):
				var ex := int(x == lo.x or x == hi.x)
				var ey := int(y == lo.y or y == hi.y)
				var ez := int(z == lo.z or z == hi.z)
				if ex + ey + ez >= 3 or ex + ey == 2 or (skip.is_valid() and skip.call(x, y, z)):
					continue
				var c: int = paint.call(x, y, z)
				m.put(Vector3i(x, y, z), c if y <= mid else _tone(c, -0.18))


# Conjunto de placas (copper...wood, meteor) ou de pano (`cloth`: ninja): capacete de rosto aberto, peitoral com ombreiras, manga até o cotovelo,
# greva com joelheira e bota; só a paleta (ícones) muda de um metal para outro. Opções do models.json: `crest`/`horns` (cor), `gem` (cor do
# peito e da testa), `spikes` (cor: espinhos, gola e visor; meteor), `closed` (visor em vez de rosto aberto), `cloth`.
static func armor_plate(name: String, spec: Dictionary) -> Dictionary:
	var pal := palette(spec)
	var light: int = pal[0]
	var base: int = pal[1]
	var dark: int = pal[2]
	var cloth: bool = spec.get("cloth", false)
	var closed: bool = spec.get("closed", false)
	var gem := VoxModel.rgb(Color(spec.gem)) if spec.has("gem") else -1
	var glow := VoxModel.rgb(Color(spec.spikes)) if spec.has("spikes") else -1
	var out := {}
	# capacete: calota (z 5-12), bochechas e nuca; a frente fica aberta do queixo à testa (o rosto aparece); no pano, capuz inteiro com fresta dos olhos
	var head := VoxModel.new()
	head.put(Vector3i.ZERO, VoxModel.ANCHOR)
	var head_paint := func(x: int, y: int, z: int) -> int:
		if z >= 11 or (z == 10 and absi(x) < 3):
			return _tone(base, 0.1) if cloth else light
		return dark if z <= 5 or (y == -6 and z == 9) else base
	var head_skip := func(x: int, y: int, z: int) -> bool:
		if cloth:
			return y <= -5 and z >= 6 and z <= 8 and absi(x) <= 4
		if z <= 4 and not ((absi(x) >= 5 and y >= -3) or y >= 5):
			return true
		return not closed and y <= -5 and absi(x) <= 3 and z <= 8
	_plates(head, Vector3i(-6, -6, 1), Vector3i(6, 6, 12), head_paint, head_skip)
	if closed:
		head.box(Vector3i(-4, -7, 4), Vector3i(4, -7, 9), base)   # placa sobre os olhos (eles ficam no plano da casca)
		head.box(Vector3i(-4, -7, 6), Vector3i(4, -7, 7), glow if glow >= 0 else light)   # visor
	elif not cloth:
		head.box(Vector3i(-1, -6, 4), Vector3i(1, -6, 8), base)   # protetor de nariz
		head.box(Vector3i(0, -7, 4), Vector3i(0, -7, 9), light)
		if gem >= 0:
			head.box(Vector3i(0, -7, 10), Vector3i(0, -7, 11), gem)
	if cloth:
		head.box(Vector3i(-5, -6, 9), Vector3i(5, -6, 9), light)   # faixa da testa
		head.box(Vector3i(0, 6, 5), Vector3i(2, 8, 6), dark)         # nó do capuz
		head.box(Vector3i(1, 7, 3), Vector3i(2, 8, 4), dark)
	if spec.has("crest"):   # crista da testa à nuca
		var col := VoxModel.rgb(Color(spec.crest))
		var profile := [2, 3, 4, 5, 5, 5, 5, 4, 4, 3, 2, 2, 1]
		for i in profile.size():
			head.box(Vector3i(0, i - 6, 13), Vector3i(0, i - 6, 12 + profile[i]), col)
	if spec.has("horns"):
		var col := VoxModel.rgb(Color(spec.horns))
		for side in [-1, 1]:
			head.box(Vector3i(side * 7, -1, 8), Vector3i(side * 8, 1, 9), col)
			head.box(Vector3i(side * 9, -1, 10), Vector3i(side * 9, 1, 12), col)
			head.box(Vector3i(side * 10, 0, 13), Vector3i(side * 10, 0, 14), col)
	if glow >= 0:   # espinhos de lava no alto
		for sp in [[-4, -3, 3], [0, 0, 5], [4, -3, 3], [-2, 3, 4], [2, 3, 4]]:
			head.box(Vector3i(sp[0], sp[1], 13), Vector3i(sp[0], sp[1], 12 + sp[2]), glow)
	out[name + "_head"] = head
	# peitoral: gola clara, cós escuro, costura e emblema; pano: faixas cruzadas
	var body := VoxModel.new()
	body.put(Vector3i.ZERO, VoxModel.ANCHOR)
	var body_paint := func(x: int, y: int, z: int) -> int:
		if z >= 13:
			return light
		if z <= 2:
			return dark
		if cloth:
			return light if y == -4 and absi(x) == absi(z - 8) else base   # faixas cruzadas
		return dark if y == -4 and (z == 7 or (x == 0 and z > 3)) else base
	_plates(body, Vector3i(-6, -4, 0), Vector3i(6, 4, 14), body_paint)
	if gem >= 0:
		body.box(Vector3i(0, -5, 8), Vector3i(0, -5, 10), gem)
		body.box(Vector3i(-1, -5, 9), Vector3i(1, -5, 9), gem)
	if glow >= 0:
		body.box(Vector3i(-1, -5, 8), Vector3i(1, -5, 10), glow)   # gema de lava
		body.box(Vector3i(-5, -4, 14), Vector3i(5, 3, 14), glow)   # gola de lava
	out[name + "_body"] = body
	# braço: ombreira grande (z 0-4) e manga até o cotovelo; a mão fica de fora
	var arm := VoxModel.new()
	arm.put(Vector3i.ZERO, VoxModel.ANCHOR)
	var sleeve := func(_x: int, _y: int, z: int) -> int: return dark if z <= -8 else base
	var pauldron := func(_x: int, _y: int, z: int) -> int: return dark if z == 0 else light if z == 4 else base
	_plates(arm, Vector3i(-3, -3, -9), Vector3i(3, 3, -1), sleeve)
	_plates(arm, Vector3i(-4, -4, 0), Vector3i(4, 4, 4), pauldron)
	if cloth:
		arm.box(Vector3i(-3, -3, -13), Vector3i(3, 3, -10), base)
		arm.box(Vector3i(-3, -3, -13), Vector3i(3, 3, -13), light)   # atadura do punho
	if glow >= 0:
		arm.box(Vector3i(0, 0, 5), Vector3i(0, 0, 7), glow)
	out[name + "_arm"] = arm
	# greva: coxa, joelheira, canela e bota com a ponta para a frente
	var leg := VoxModel.new()
	leg.put(Vector3i.ZERO, VoxModel.ANCHOR)
	var thigh := func(_x: int, _y: int, z: int) -> int: return light if z >= 2 or z == -15 else base
	var boot := func(_x: int, _y: int, z: int) -> int: return dark if z < -18 else base
	_plates(leg, Vector3i(-3, -3, -15), Vector3i(3, 3, 2), thigh)
	_plates(leg, Vector3i(-3, -3, -20), Vector3i(3, 3, -16), func(_x: int, _y: int, _z: int) -> int: return dark)
	_plates(leg, Vector3i(-3, -5, -20), Vector3i(3, -3, -17), boot)   # ponta da bota
	if not cloth:
		leg.box(Vector3i(-2, -4, -9), Vector3i(2, -4, -7), glow if glow >= 0 else light)   # joelheira
	out[name + "_leg"] = leg
	return out


# ---------- conjunto de armadura ----------

# Casca (caixa de cantos arredondados) de `lo` a `hi` (inclusivos) pintada com a região `rect` do sprite do conjunto vestido: a
# imagem é projetada de frente e atravessa a profundidade (extrusão), então as cores do sprite aparecem também nos
# lados e nas costas; a metade de trás é um tom mais escura (menos as cores emissivas `glow`). A região vem escolhida à mão: sem o contorno de 2 px.
static func shell(m: VoxModel, lo: Vector3i, hi: Vector3i, img: Image, rect: Rect2i, glow: Dictionary, plain := -1) -> void:
	var r := rect
	var dx := hi.x - lo.x + 1
	var dz := hi.z - lo.z + 1
	var mid := (lo.y + hi.y) / 2
	for z in range(lo.z, hi.z + 1):
		var py := r.position.y + (hi.z - z) * r.size.y / dz
		for x in range(lo.x, hi.x + 1):
			var px := r.position.x + (x - lo.x) * r.size.x / dx
			var c := img.get_pixel(px, py)
			var col := VoxModel.rgb(c) if c.a > 0.5 else 0x1f1f14
			for y in range(lo.y, hi.y + 1):
				var ex := int(x == lo.x or x == hi.x)
				var ey := int(y == lo.y or y == hi.y)
				var ez := int(z == lo.z or z == hi.z)
				if ex + ey + ez >= 3 or (ex + ey == 2):   # cantos e quinas verticais cortados
					continue
				var cc := col
				if plain >= 0 and y > lo.y + 1 and VoxModel.color(col).get_luminance() < 0.16 and not glow.has(col):
					cc = plain   # `plain`: fora da frente, o contorno escuro vira a cor da placa (senão as listras do visor e do cinto dão a volta na cabeça)
				m.put(Vector3i(x, y, z), cc if y <= mid or glow.has(cc) else VoxModel.rgb(VoxModel.color(cc).darkened(0.25)))


# Veia de lava: caminho torto de cima para baixo na face (y = `face`) da casca, em `color`; só pinta onde já há voxel.
static func vein(m: VoxModel, face: int, x: int, z: int, len: int, color: int, seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	for i in len:
		var p := Vector3i(x, face, z - i)
		if m.v.has(p):
			m.v[p] = color
		if i % 2 == 1:
			x += rng.randi_range(-1, 1)


static func armor_set(name: String, spec: Dictionary) -> Dictionary:
	var img := sprite(spec.get("wiki", ""))
	if img == null:
		return {}   # sem o sprite do conjunto vestido: o player_model cai nas formas em código
	var glow := {}
	for h in spec.get("emissive", []):
		glow[Color(h).to_rgba32() >> 8 & 0xffffff] = true
	var red := 0xff1800
	var orange := 0xf87e00
	var yellow := 0xf8b600
	var out := {}
	# capacete fechado (13x13x13 em volta da cabeça): placas do sprite, olhos de lava, crista de fogo e o rabo de chamas que desce pela nuca
	var head := VoxModel.new()
	head.put(Vector3i.ZERO, VoxModel.ANCHOR)
	shell(head, Vector3i(-6, -6, 0), Vector3i(6, 6, 12), img, Rect2i(12, 2, 10, 11), glow, 0x7e7e5a)
	for side in [-1, 1]:
		head.box(Vector3i(side * 4, -6, 6), Vector3i(side * 2, -6, 6), yellow)   # fenda do olho
		head.put(Vector3i(side * 5, -6, 7), orange)
	var profile := [2, 3, 5, 4, 7, 6, 9, 7, 6, 4, 5, 3]   # crista da testa (y = -5) à nuca: altura acima do capacete
	for i in profile.size():
		var h: int = profile[i]
		for k in h:
			var col := red if k < h / 3 else orange if k < h - 2 else yellow
			head.box(Vector3i(-1 if k < h - 3 else 0, i - 5, 13 + k), Vector3i(1 if k < h - 3 else 0, i - 5, 13 + k), col)
	for z in range(3, 13):   # rabo: as gotas de lava do sprite (colunas 8-9) descendo atrás da cabeça
		var c := img.get_pixel(8, 13 - z)
		var col := VoxModel.rgb(c) if c.a > 0.5 and glow.has(VoxModel.rgb(c)) else red
		head.box(Vector3i(-1 if z > 6 else 0, 7, z), Vector3i(1 if z > 6 else 0, 7, z), col)
		head.box(Vector3i(0, 8, z), Vector3i(0, 8, z), orange if z % 3 else yellow)
	out[name + "_head"] = head
	# peitoral: 15 de altura, cós de lava e veias
	var body := VoxModel.new()
	body.put(Vector3i.ZERO, VoxModel.ANCHOR)
	shell(body, Vector3i(-6, -4, 0), Vector3i(6, 4, 14), img, Rect2i(10, 18, 12, 12), glow, 0x65653f)
	vein(body, -4, -4, 13, 6, orange, 11)
	vein(body, 4, 1, 12, 9, orange, 13)
	out[name + "_body"] = body
	# braço: ombreira grande, manga até a luva, brasa no cotovelo (do sprite)
	var arm := VoxModel.new()
	arm.put(Vector3i.ZERO, VoxModel.ANCHOR)
	shell(arm, Vector3i(-3, -3, -17), Vector3i(3, 3, 0), img, Rect2i(2, 20, 8, 10), glow, 0x65653f)
	shell(arm, Vector3i(-4, -4, 0), Vector3i(4, 4, 4), img, Rect2i(2, 14, 8, 4), glow)   # ombreira
	vein(arm, -3, 0, -2, 5, orange, 14)
	out[name + "_arm"] = arm
	# greva: bota com a ponta para a frente e brasa no tornozelo
	var leg := VoxModel.new()
	leg.put(Vector3i.ZERO, VoxModel.ANCHOR)
	shell(leg, Vector3i(-3, -3, -20), Vector3i(3, 3, 2), img, Rect2i(10, 30, 6, 12), glow, 0x65653f)
	shell(leg, Vector3i(-3, -5, -20), Vector3i(3, -3, -17), img, Rect2i(10, 38, 6, 4), glow)   # ponta da bota
	vein(leg, -3, 0, -3, 6, orange, 15)
	out[name + "_leg"] = leg
	return out
