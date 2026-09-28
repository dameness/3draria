class_name Crafting
# Receitas de data/<pacote>/recipes.json: resultado, ingredientes e estação (bloco perto do jogador).

const STATION_RANGE := 4  # em blocos, em cada direção

static var recipes: Array = []   # {result: id, count, needs: {item id: n}, station: bloco ou -1}


static func load_pack(dir := "res://data/base") -> void:
	recipes.clear()
	for r in Blocks.read(dir + "/recipes.json"):
		var needs := {}
		for n in r.needs:
			assert(Items.ids.has(n), "ingrediente desconhecido: " + n)
			needs[Items.ids[n]] = int(r.needs[n])
		assert(Items.ids.has(r.result), "resultado desconhecido: " + r.result)
		var station: int = Blocks.ids.get(r.get("station", ""), -1)
		assert(station != -1 or not r.has("station"), "estação desconhecida: " + str(r.get("station")))
		recipes.append({"result": Items.ids[r.result], "count": int(r.get("count", 1)), "needs": needs, "station": station})


static func can_craft(r: Dictionary, inv: Inventory, stations: Dictionary) -> bool:
	if r.station != -1 and not stations.has(r.station):
		return false
	for id in r.needs:
		if inv.total(id) < r.needs[id]:
			return false
	return true


static func craft(r: Dictionary, inv: Inventory, stations: Dictionary) -> bool:
	if not can_craft(r, inv, stations):
		return false
	for id in r.needs:
		inv.remove(id, r.needs[id])
	# ponytail: inventário cheio perde o que sobrou; resolver quando houver itens soltos no chão (F4).
	inv.add(r.result, r.count)
	return true


# Cria um exemplar na mão do cursor, como no Terraria (mão vazia ou com o mesmo item e espaço na pilha).
static func craft_to_cursor(r: Dictionary, inv: Inventory, stations: Dictionary) -> bool:
	if not can_craft(r, inv, stations):
		return false
	if inv.cursor_id != -1 and (inv.cursor_id != r.result or inv.cursor_count + r.count > Items.stack[r.result]):
		return false
	for id in r.needs:
		inv.remove(id, r.needs[id])
	inv.cursor_id = r.result
	inv.cursor_count += r.count
	inv.version += 1
	return true


# Blocos de estação num cubo em volta de pos. Retorna {bloco: true}.
static func stations_near(world, pos: Vector3) -> Dictionary:
	var found := {}
	var ids := {}
	for r in recipes:
		if r.station != -1:
			ids[r.station] = true
	var p := Vector3i(pos.floor())
	for y in range(p.y - STATION_RANGE, p.y + STATION_RANGE + 2):
		for z in range(p.z - STATION_RANGE, p.z + STATION_RANGE + 1):
			for x in range(p.x - STATION_RANGE, p.x + STATION_RANGE + 1):
				var id: int = world.get_block(x, y, z)
				var b: int = Blocks.station_as[id]
				if ids.has(b):
					found[b] = true
				for a in Blocks.station_also.get(id, []):
					if ids.has(a):
						found[a] = true
	return found
