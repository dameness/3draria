class_name Items
# Itens: cada bloco quebrável vira um item que o coloca; data/<pacote>/items.json adiciona os demais.
# O id do item é a posição na lista (blocos primeiro, na ordem de blocks.json). Chame depois de Blocks.load_pack.

static var ids := {}                      # nome -> id
static var names: Array[String] = []
static var icon := PackedInt32Array()     # id -> índice no atlas
static var places := PackedInt32Array()   # id -> bloco que coloca, ou -1
static var pick_power := PackedInt32Array()
static var stack := PackedInt32Array()
static var drop := PackedInt32Array()     # bloco -> item que dropa, ou -1


static func load_pack(dir := "res://data/base") -> void:
	ids.clear()
	names.clear()
	icon.clear()
	places.clear()
	pick_power.clear()
	stack.clear()
	drop.clear()
	for block in Blocks.ids:
		var b: int = Blocks.ids[block]
		if Blocks.solid[b] and Blocks.breakable[b]:
			_add(block, Blocks.tiles[b * Blocks.FACES], b, 0, 9999)
	var tile_index := Blocks.textures.keys()
	for it in Blocks.read(dir + "/items.json"):
		assert(tile_index.has(it.icon), "ícone desconhecido: " + it.icon)
		_add(it.name, tile_index.find(it.icon), -1, it.get("pick_power", 0), it.get("stack", 9999))
	for n in Blocks.drop_names:
		assert(n == "" or ids.has(n), "drop desconhecido: " + n)
		drop.append(ids.get(n, -1))


static func _add(n: String, ic: int, pl: int, pp: int, st: int) -> void:
	ids[n] = names.size()
	names.append(n)
	icon.append(ic)
	places.append(pl)
	pick_power.append(pp)
	stack.append(st)


static func label(id: int) -> String:
	return names[id].replace("_", " ")
