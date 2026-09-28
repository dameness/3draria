class_name Blocks
# Tabela de blocos lida de data/<pacote>/. O id é a posição em blocks.json (0 = ar).

const FACES := 6  # +X, -X, +Y, -Y, +Z, -Z
const LIQUID_TOP := 0.88   # altura da superfície de um bloco de líquido cheio (fica um pouco abaixo do topo)

static var ids := {}                       # nome -> id
static var solid := PackedByteArray()      # id -> 1 se sólido
static var breakable := PackedByteArray()  # id -> 1 se o jogador pode quebrar
static var power := PackedInt32Array()     # id -> poder de picareta mínimo
static var shape: Array[String] = []       # id -> "" (cubo) ou forma não sólida: "torch", "plant" (cruz), "liquid" (água/lava)
static var special := PackedByteArray()    # id -> 1 se tem forma própria (shape != "")
static var liquid := PackedByteArray()     # id -> 1 se é líquido (água/lava em qualquer nível; liquid.gd faz fluir)
static var liquid_kind := PackedInt32Array()  # id -> id do líquido cheio (water, lava) a que o nível pertence; o próprio id se não é líquido
static var liquid_level := PackedByteArray()  # id -> nível 1-8 do líquido (8 = bloco cheio), 0 se não é líquido
static var level_ids := {}                 # id do líquido cheio -> PackedInt32Array de 9 ids (índice = nível; 0 = ar)
static var soft := PackedByteArray()       # id -> 1 se a mira atravessa e colocar bloco substitui (plantas, líquidos)
static var clear := PackedByteArray()      # id -> 1 se a luz do céu passa (tronco e folhas: a copa só sombreia de leve)
static var glow := PackedByteArray()       # id -> 1 se brilha sozinho (lava)
static var light := PackedInt32Array()     # id -> raio de luz em blocos (0 = não ilumina)
static var station_as := PackedInt32Array() # id -> bloco de estação que ele equivale (bigorna de chumbo = bigorna)
static var icons: Array[String] = []       # id -> textura do ícone do item-bloco ("" = face lateral)
static var drop_names: Array[String] = []  # id -> item que dropa ("" = nada); Items resolve
static var tiles := PackedInt32Array()     # id * FACES + face -> índice no atlas
static var textures := {}                  # nome -> spec, na ordem do atlas


static func load_pack(dir := "res://data/base") -> void:
	textures = read(dir + "/textures.json")
	var tile_index := {}
	for t in textures:
		tile_index[t] = tile_index.size()
	ids.clear()
	solid.clear()
	breakable.clear()
	power.clear()
	shape.clear()
	special.clear()
	liquid.clear()
	liquid_kind.clear()
	liquid_level.clear()
	level_ids.clear()
	soft.clear()
	glow.clear()
	clear.clear()
	light.clear()
	drop_names.clear()
	icons.clear()
	station_as.clear()
	tiles.clear()
	var list: Array = read(dir + "/blocks.json")
	for b in list:
		ids[b.name] = ids.size()
		solid.append(1 if b.get("solid", true) else 0)
		breakable.append(1 if b.get("breakable", true) else 0)
		power.append(b.get("power", 0))
		shape.append(b.get("shape", ""))
		special.append(1 if shape[-1] != "" else 0)
		liquid.append(1 if shape[-1] == "liquid" else 0)
		liquid_kind.append(ids[b.get("liquid", b.name)] if liquid[-1] else ids[b.name])
		liquid_level.append(b.get("level", 8) if liquid[-1] else 0)
		if liquid[-1]:   # nível -> id, por líquido
			var by_level: PackedInt32Array = level_ids.get(liquid_kind[-1], PackedInt32Array([0, 0, 0, 0, 0, 0, 0, 0, 0]))
			by_level[liquid_level[-1]] = ids[b.name]
			level_ids[liquid_kind[-1]] = by_level
		soft.append(1 if shape[-1] in ["plant", "liquid"] else 0)
		glow.append(1 if b.get("glow", false) else 0)
		clear.append(1 if b.get("clear", false) else 0)
		light.append(b.get("light", 0))
		icons.append(b.get("icon", ""))
		drop_names.append(b.get("drop", b.name if breakable[-1] and (solid[-1] or shape[-1] != "") else ""))
		var t: Dictionary = b.get("tiles", {})
		var side: String = t.get("side", t.get("all", ""))
		for n in [side, side, t.get("top", side), t.get("bottom", side), side, side]:
			assert(n == "" or tile_index.has(n), "textura desconhecida: " + n)
			tiles.append(tile_index.get(n, 0))
	for b in list:
		station_as.append(ids[b.get("station_as", b.name)])


# Altura (em blocos, a partir da base do bloco) da superfície do líquido id, quando não há líquido igual em cima.
static func liquid_height(id: int) -> float:
	return LIQUID_TOP * liquid_level[id] / 8.0


static func read(path: String) -> Variant:
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	assert(data != null, "JSON inválido: " + path)
	return data
