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
static var rarity_colors := {}            # raridade (int) -> Color, de rarities.json
static var defs: Array[Dictionary] = []   # id -> entrada crua do JSON (damage, use_time, reach, knockback, ammo, shoot_speed)


static func load_pack(dir := "res://data/base") -> void:
	ids.clear()
	names.clear()
	icon.clear()
	places.clear()
	pick_power.clear()
	stack.clear()
	drop.clear()
	defs.clear()
	rarity_colors.clear()
	var rc: Dictionary = Blocks.read(dir + "/rarities.json")
	for r in rc:
		rarity_colors[int(r)] = Color(rc[r])
	for block in Blocks.ids:
		var b: int = Blocks.ids[block]
		if Blocks.solid[b] and Blocks.breakable[b]:
			_add({"name": block}, Blocks.tiles[b * Blocks.FACES], b)
	var tile_index := Blocks.textures.keys()
	for it in Blocks.read(dir + "/items.json"):
		assert(tile_index.has(it.icon), "ícone desconhecido: " + it.icon)
		_add(it, tile_index.find(it.icon), -1)
	for d in defs:
		assert(not d.has("ammo") or ids.has(d.ammo), "munição desconhecida: " + str(d.get("ammo")))
	for n in Blocks.drop_names:
		assert(n == "" or ids.has(n), "drop desconhecido: " + n)
		drop.append(ids.get(n, -1))


static func _add(def: Dictionary, ic: int, pl: int) -> void:
	ids[def.name] = names.size()
	names.append(def.name)
	icon.append(ic)
	places.append(pl)
	pick_power.append(def.get("pick_power", 0))
	stack.append(def.get("stack", 9999))
	defs.append(def)


static func label(id: int) -> String:
	return names[id].replace("_", " ")


static func rarity_color(id: int) -> Color:
	return rarity_colors.get(int(defs[id].get("rarity", 0)), Color.WHITE)
