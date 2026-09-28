class_name Blocks
# Tabela de blocos lida de data/<pacote>/. O id é a posição em blocks.json (0 = ar).

const FACES := 6  # +X, -X, +Y, -Y, +Z, -Z

static var ids := {}                       # nome -> id
static var solid := PackedByteArray()      # id -> 1 se sólido
static var breakable := PackedByteArray()  # id -> 1 se o jogador pode quebrar
static var power := PackedInt32Array()     # id -> poder de picareta mínimo
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
		icons.append(b.get("icon", ""))
		drop_names.append(b.get("drop", b.name if solid[-1] and breakable[-1] else ""))
		var t: Dictionary = b.get("tiles", {})
		var side: String = t.get("side", t.get("all", ""))
		for n in [side, side, t.get("top", side), t.get("bottom", side), side, side]:
			assert(n == "" or tile_index.has(n), "textura desconhecida: " + n)
			tiles.append(tile_index.get(n, 0))
	for b in list:
		station_as.append(ids[b.get("station_as", b.name)])


static func read(path: String) -> Variant:
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	assert(data != null, "JSON inválido: " + path)
	return data
