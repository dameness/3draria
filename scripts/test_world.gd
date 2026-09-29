class_name TestWorld
# Mundo de teste (menu → "Mundo de teste"): uma arena plana e iluminada no nascimento com um baú por categoria de item, todos os blocos no chão,
# os habitantes e uma vitrine de inimigos parados. Nada é escrito à mão: os baús saem de Items e a fileira de Blocks, então o que entrar
# depois nos JSON aparece sozinho. Determinístico: WorldGen.generate carimba a arena (stamp) e World.chest_at enche os baús (stock);
# o .wld só guarda a flag "test". build() roda na thread principal antes de gerar chunks; as threads só leem.

const CX := 128                 # centro da arena = nascimento (WorldGen.CENTER)
const CZ := 128
const FLAT := WorldGen.SURFACE + 2   # y do gramado (a planície do nascimento já fica por aqui)
const ARENA := Rect2i(CX - 44, CZ - 32, 89, 74)   # x, z, largura, profundidade: gramado limpo, sem árvore nem lago
const CATEGORIES := ["Armas", "Ferramentas", "Armaduras", "Acessórios", "Poções e consumíveis", "Blocos e minérios", "Moedas e munição", "Materiais e barras", "Chefes e invocadores"]
const STACKS := {"Poções e consumíveis": 30, "Blocos e minérios": 999, "Moedas e munição": 99, "Materiais e barras": 99, "Chefes e invocadores": 5}   # o resto: 1
const CHEST_SLOTS := 40
const CHEST_Z := CZ - 8         # fileira de baús, à frente do nascimento
const CHEST_STEP := 4
const BLOCK_Z := CZ - 14        # fileiras de blocos (4 por vez, para o norte)
const BLOCK_ROW := 14           # blocos por fileira, de 3 em 3 (o nome de cada um cabe em cima)
const BLOCK_STEP := 3
const SHOWCASE_Z := CZ + 14     # vitrine de inimigos, atrás do nascimento
const SHOWCASE_STEP := 3.0
const NAME := 0.0045            # tamanho do texto dos letreiros (blocos por pixel de fonte)

static var chests: Array = []   # [{pos: Vector3i, title, item: PackedInt32Array, count: PackedInt32Array}]
static var blocks: Array = []   # [{pos: Vector3i, id}] os blocos no chão
static var torches: Array = []  # Vector3i
static var labels: Array = []   # [{pos: Vector3, text, size}]
static var chest_at_pos := {}   # Vector3i -> índice em chests


# Categoria de um item (a primeira regra que casa vale).
static func category(id: int) -> String:
	var d: Dictionary = Items.defs[id]
	if Inventory.coin_kind(id) != -1 or d.has("ammo_class"):
		return "Moedas e munição"
	if d.has("armor"):
		return "Armaduras"
	if d.has("accessory"):
		return "Acessórios"
	if d.has("summon"):
		return "Chefes e invocadores"
	if d.get("consumable", false) or d.has("heal") or d.has("buff") or d.has("recall") or d.has("life") or d.has("mana") or d.has("mana_max"):
		return "Poções e consumíveis"
	if Items.pick_power[id] > 0 or Items.axe_power[id] > 0 or Items.hammer_power[id] > 0 or d.has("bucket"):
		return "Ferramentas"
	if d.get("damage", 0) > 0:
		return "Armas"
	if Items.places[id] != -1:
		return "Blocos e minérios"
	return "Materiais e barras"


# Monta o layout a partir dos dados carregados (Blocks/Items). Chame de novo se os pacotes mudarem.
static func build() -> void:
	chests.clear()
	blocks.clear()
	torches.clear()
	labels.clear()
	chest_at_pos.clear()
	var by_cat := {}
	for id in Items.names.size():
		by_cat.get_or_add(category(id), []).append(id)
	for c in by_cat.keys():
		assert(c in CATEGORIES, "categoria sem lugar: " + c)
	for c in CATEGORIES:
		var ids: Array = by_cat.get(c, [])
		var pages := ceili(ids.size() / float(CHEST_SLOTS))
		for p in pages:
			var box := {"pos": Vector3i.ZERO, "title": c.to_upper() + (" %d/%d" % [p + 1, pages] if pages > 1 else ""), "item": PackedInt32Array(), "count": PackedInt32Array()}
			box.item.resize(CHEST_SLOTS)
			box.item.fill(-1)
			box.count.resize(CHEST_SLOTS)
			for k in mini(CHEST_SLOTS, ids.size() - p * CHEST_SLOTS):
				var id: int = ids[p * CHEST_SLOTS + k]
				box.item[k] = id
				box.count[k] = mini(Items.stack[id], STACKS.get(c, 1))
			chests.append(box)
	for i in chests.size():
		var pos := Vector3i(CX - CHEST_STEP * (chests.size() - 1) / 2 + CHEST_STEP * i, FLAT + 1, CHEST_Z)
		chests[i].pos = pos
		chest_at_pos[pos] = i
		labels.append({"pos": Vector3(pos.x + 0.5, FLAT + 2.4 + 0.9 * (i % 2), pos.z + 0.5), "text": chests[i].title.replace(" E ", " E\n"), "size": 0.006})   # títulos alternam a altura para não se cobrirem
	var taken := chest_at_pos.duplicate()
	var n := 0
	for id in range(1, Blocks.ids.size()):
		if Blocks.liquid_level[id] in [1, 2, 3, 4, 5, 6, 7]:   # níveis parciais são só estados do fluxo: os cheios já estão
			continue
		var pos := Vector3i(CX - BLOCK_STEP * BLOCK_ROW / 2 + BLOCK_STEP * (n % BLOCK_ROW), FLAT + (0 if Blocks.liquid[id] else 1), BLOCK_Z - 3 * (n / BLOCK_ROW))   # líquido afundado no gramado: não escorre
		blocks.append({"pos": pos, "id": id})
		taken[Vector3i(pos.x, FLAT + 1, pos.z)] = true
		labels.append({"pos": Vector3(pos.x + 0.5, FLAT + 2.1 + 0.5 * (n % 2), pos.z + 0.5), "text": Blocks.ids.keys()[id], "size": NAME})
		n += 1
	for x in range(CX - 40, CX + 41, 9):   # tochas de 9 em 9 (nunca no nascimento): a luz de 10 blocos se emenda
		for z in range(CZ - 27, CZ + 38, 9):
			var pos := Vector3i(x, FLAT + 1, z)
			if not taken.has(pos):
				torches.append(pos)
	labels.append({"pos": Vector3(CX + 0.5, FLAT + 4.0, CZ - 1.5), "text": "MUNDO DE TESTE  ·  F9: painel de atalhos", "size": 0.0055})
	labels.append({"pos": Vector3(CX + 0.5, FLAT + 5.2, CHEST_Z + 0.5), "text": "BAÚS: todos os itens, por categoria", "size": 0.008})
	labels.append({"pos": Vector3(CX + 0.5, FLAT + 5.2, BLOCK_Z - 11.5), "text": "TODOS OS BLOCOS (em ordem de id)", "size": 0.008})
	labels.append({"pos": Vector3(CX + 0.5, FLAT + 5.2, SHOWCASE_Z - 3.5), "text": "VITRINE DE INIMIGOS (parados; ainda levam golpe)", "size": 0.008})


# Posição da vitrine i (de n): fileira reta atrás do nascimento.
static func showcase_pos(i: int, n: int) -> Vector3:
	return Vector3(CX + 0.5 - SHOWCASE_STEP * (n - 1) / 2.0 + SHOWCASE_STEP * i, FLAT + 1.0, SHOWCASE_Z + 0.5)


# Baú de teste k (uma cópia nova, para o jogador mexer sem estragar o molde).
static func stock(k: int) -> Dictionary:
	return {"item": chests[k].item.duplicate(), "count": chests[k].count.duplicate()}


# Roda dentro de WorldGen.generate (thread): deixa o gramado da arena plano e limpo e escreve baús, blocos e tochas que caem neste chunk.
static func stamp(d: PackedByteArray, cx: int, cz: int) -> void:
	var c := WorldGen.CHUNK
	var layer := c * c
	if not Rect2i(cx * c, cz * c, c, c).intersects(ARENA):
		return
	var grass: int = Blocks.ids.grass
	var dirt: int = Blocks.ids.dirt
	for z in c:
		for x in c:
			if not ARENA.has_point(Vector2i(cx * c + x, cz * c + z)):
				continue
			var i := x + z * c
			for y in range(FLAT + 1, WorldGen.HEIGHT):
				d[i + y * layer] = 0
			for y in range(FLAT - 5, FLAT):
				if d[i + y * layer] == 0 or Blocks.liquid[d[i + y * layer]] == 1:
					d[i + y * layer] = dirt
			d[i + FLAT * layer] = grass
	for k in chests:
		_put(d, cx, cz, k.pos, Blocks.ids.chest)
	for b in blocks:
		_put(d, cx, cz, b.pos, b.id)
	for t in torches:
		_put(d, cx, cz, t, Blocks.ids.torch)


static func _put(d: PackedByteArray, cx: int, cz: int, p: Vector3i, id: int) -> void:
	var lx := p.x - cx * WorldGen.CHUNK
	var lz := p.z - cz * WorldGen.CHUNK
	if lx >= 0 and lx < WorldGen.CHUNK and lz >= 0 and lz < WorldGen.CHUNK:
		d[lx + lz * WorldGen.CHUNK + p.y * WorldGen.CHUNK * WorldGen.CHUNK] = id


# Um lugar de pé no submundo (chão de cinza com 2 de ar em cima), procurando em espiral em volta do centro; sem achar, o meio do ar.
static func underworld_spot(world: Node3D) -> Vector3:
	for r in range(0, 60, 4):
		for a in 8:
			var x := CX + roundi(cos(a * TAU / 8.0) * r)
			var z := CZ + roundi(sin(a * TAU / 8.0) * r)
			for y in range(WorldGen.UNDERWORLD_TOP - 1, 7, -1):
				if world.get_block(x, y, z) == 0 and world.get_block(x, y + 1, z) == 0 and Blocks.solid[world.get_block(x, y - 1, z)]:
					return Vector3(x + 0.5, y, z + 0.5)
	return Vector3(CX + 0.5, 12.0, CZ + 0.5)
