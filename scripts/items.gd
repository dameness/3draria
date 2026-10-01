class_name Items
# Itens: cada bloco quebrável vira um item que o coloca; data/<pacote>/items.json adiciona os demais.
# O id do item é a posição na lista (blocos primeiro, na ordem de blocks.json). Chame depois de Blocks.load_pack.

static var ids := {}                      # nome -> id
static var names: Array[String] = []
static var icon := PackedInt32Array()     # id -> índice no atlas (ícone procedural / fallback)
static var icon_name: Array[String] = []  # id -> entrada de textures.json com o sprite da wiki
static var places := PackedInt32Array()   # id -> bloco que coloca, ou -1
static var pick_power := PackedInt32Array()
static var axe_power := PackedInt32Array()   # id -> poder de machado (só machado corta tronco)
static var hammer_power := PackedInt32Array()   # id -> poder de martelo (só martelo quebra orbes e corações)
static var stack := PackedInt32Array()
static var drop := PackedInt32Array()     # bloco -> item que dropa, ou -1
static var sets := {}                     # conjunto de armadura -> {pieces: [ids], defense: bônus, free_cost: [ids das armas que o conjunto completo deixa sem custo de mana], model: modelo voxel das peças ("" = formas em código do player_model)}
static var rarity_colors := {}            # raridade (int) -> Color, de rarities.json
static var defs: Array[Dictionary] = []   # id -> entrada crua do JSON (damage, use_time, reach, knockback, ammo, shoot_speed)


static func load_pack(dir := "res://data/base") -> void:
	ids.clear()
	names.clear()
	icon.clear()
	icon_name.clear()
	Atlas.texture_cache.clear()
	places.clear()
	pick_power.clear()
	axe_power.clear()
	hammer_power.clear()
	stack.clear()
	drop.clear()
	defs.clear()
	rarity_colors.clear()
	sets.clear()
	var rc: Dictionary = Blocks.read(dir + "/rarities.json")
	for r in rc:
		rarity_colors[int(r)] = Color(rc[r])
	for block in Blocks.ids:
		var b: int = Blocks.ids[block]
		if Blocks.breakable[b] and (Blocks.solid[b] or Blocks.shape[b] != "") and Blocks.no_item[b] == 0:
			_add({"name": block, "icon": Blocks.icons[b]}.merged(Blocks.item_extra.get(b, {})), Blocks.tiles[b * Blocks.FACES], b)
	var tile_index := Blocks.textures.keys()
	for it in Blocks.read(dir + "/items.json"):
		assert(tile_index.has(it.icon), "ícone desconhecido: " + it.icon)
		_add(it, tile_index.find(it.icon), ids_of_block(it.get("places", "")))
	for d in defs:
		assert(not d.has("ammo") or defs.any(func(x): return x.get("ammo_class") == d.ammo), "munição sem itens: " + str(d.get("ammo")))
	var set_data: Dictionary = Blocks.read(dir + "/armor_sets.json")
	for k in set_data:
		sets[k] = {"pieces": set_data[k].pieces.map(func(n): return ids[n]), "defense": set_data[k].defense, "free_cost": set_data[k].get("free_cost", []).map(func(n): return ids[n]), "model": set_data[k].get("model", "")}
	for n in Blocks.drop_names:
		assert(n == "" or ids.has(n), "drop desconhecido: " + n)
		drop.append(ids.get(n, -1))


static func ids_of_block(name: String) -> int:
	return Blocks.ids[name] if name != "" else -1


static func _add(def: Dictionary, ic: int, pl: int) -> void:
	ids[def.name] = names.size()
	names.append(def.name)
	icon.append(ic)
	icon_name.append(def.get("icon", ""))
	places.append(pl)
	pick_power.append(def.get("pick_power", 0))
	axe_power.append(def.get("axe_power", 0))
	hammer_power.append(def.get("hammer_power", 0))
	stack.append(def.get("stack", 9999))
	defs.append(def)


# Poder do item contra o bloco b: machado no tronco, martelo nas orbes, picareta no resto.
static func power_on(id: int, b: int) -> int:
	return axe_power[id] if Blocks.axe[b] == 1 else hammer_power[id] if Blocks.hammer[b] == 1 else pick_power[id]


# Duração de um uso em segundos (o ciclo do golpe e da animação): picareta e machado usam o tool speed da wiki (o intervalo entre golpes
# no bloco; o use time da ficha é só a dica), o resto o use time.
static func use_dur(id: int) -> float:
	var d := defs[id]
	return d.tool_speed / 60.0 if d.has("tool_speed") else d.get("use_time", 0.25)


# Segurar o botão repete o uso (wiki Autoswing): só as ferramentas e armas marcadas nos dados, blocos, tochas e mudas; o resto exige um clique por uso.
static func autoswing(id: int) -> bool:
	var d := defs[id]
	return d.get("autoswing", places[id] != -1 or d.has("plants"))


static func label(id: int) -> String:
	return names[id].replace("_", " ")


# Título como na wiki: "brain_of_cthulhu" → "Brain of Cthulhu" (preposições e artigos ficam minúsculos, menos na 1ª palavra).
static func title(s: String) -> String:
	var out := []
	for w in s.replace("_", " ").split(" ", false):
		out.append(w if out.size() > 0 and w in ["of", "the", "in", "a", "an", "and", "for", "to", "on"] else w.capitalize())
	return " ".join(out)


static func rarity_color(id: int) -> Color:
	return rarity_colors.get(int(defs[id].get("rarity", 0)), Color.WHITE)


# Ícone para a interface e itens soltos: sprite da wiki em tamanho original, senão o tile do atlas.
static func icon_texture(id: int, atlas: Texture2D) -> Texture2D:
	return Atlas.texture(icon_name[id], icon[id], atlas)
