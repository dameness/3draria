class_name Loot
# Tesouro dos baús pela camada (data/base/loot.json, tabelas da wiki Gold Chest): 1 item principal sorteado entre os da lista e, para cada entrada
# de "common", a chance de vir UM item do conjunto (os do mesmo conjunto nunca vêm juntos) na quantidade min-max. Só entram itens que existem no jogo.

static var tables := {}


static func load_pack(dir := "res://data/base") -> void:
	tables = Blocks.read(dir + "/loot.json")


# Camada do baú pela altura: perto do submundo ("lava"), cavernas ou subsolo.
static func layer_of(y: int) -> String:
	return "lava" if y < WorldGen.UNDERWORLD_TOP + 12 else "cavern" if y < WorldGen.CAVERN_TOP else "underground"


# Conteúdo de um baú de 40 slots, sorteado com rng. O principal vem sempre.
static func chest(layer: String, rng: RandomNumberGenerator) -> Dictionary:
	var t: Dictionary = tables[layer]
	var c := {"item": PackedInt32Array(), "count": PackedInt32Array()}
	c.item.resize(40)
	c.item.fill(-1)
	c.count.resize(40)
	var main: Array = t.main
	c.item[0] = Items.ids[main[rng.randi() % main.size()]]
	c.count[0] = 1
	var k := 1
	for e in t.common:
		if rng.randf() < e.chance:
			var items: Array = e.items
			c.item[k] = Items.ids[items[rng.randi() % items.size()]]
			c.count[k] = rng.randi_range(int(e.min), int(e.max))
			k += 1
	return c
