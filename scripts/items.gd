class_name Items
# Itens: cada bloco quebrável vira um item que o coloca; data/<pacote>/items.json adiciona os demais.
# O id do item é a posição na lista (blocos primeiro, na ordem de blocks.json). Chame depois de Blocks.load_pack.

static var ids := {}                      # nome -> id
static var names: Array[String] = []
static var icon := PackedInt32Array()     # id -> índice no atlas (ícone procedural / fallback)
static var icon_name: Array[String] = []  # id -> entrada de textures.json com o sprite da wiki
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
	icon_name.clear()
	icon_cache.clear()
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
			_add({"name": block, "icon": Blocks.icons[b]}, Blocks.tiles[b * Blocks.FACES], b)
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
	icon_name.append(def.get("icon", ""))
	places.append(pl)
	pick_power.append(def.get("pick_power", 0))
	stack.append(def.get("stack", 9999))
	defs.append(def)


static func label(id: int) -> String:
	return names[id].replace("_", " ")


static func rarity_color(id: int) -> Color:
	return rarity_colors.get(int(defs[id].get("rarity", 0)), Color.WHITE)


static var icon_cache := {}


# Ícone para a interface e itens soltos: sprite da wiki em tamanho original, senão o tile do atlas.
static func icon_texture(id: int, atlas: Texture2D) -> Texture2D:
	if not icon_cache.has(id):
		var wiki := Atlas.wiki_image(Blocks.textures.get(icon_name[id], {}))
		if wiki and not Blocks.textures[icon_name[id]].has("crop"):
			icon_cache[id] = ImageTexture.create_from_image(wiki)
		else:
			var t := AtlasTexture.new()
			t.atlas = atlas
			t.region = Rect2(icon[id] * Atlas.TILE, 0, Atlas.TILE, Atlas.TILE)
			icon_cache[id] = t
	return icon_cache[id]
