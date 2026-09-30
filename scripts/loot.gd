class_name Loot
# Tesouro dos baús pela camada (data/base/loot.json, tabelas da wiki Gold Chest): 1 item principal sorteado entre os da lista e, para cada entrada
# de "common", a chance de vir UM item do conjunto (os do mesmo conjunto nunca vêm juntos) na quantidade min-max. Só entram itens que existem no jogo.

static var tables := {}


static func load_pack(dir := "res://data/base") -> void:
	tables = Blocks.read(dir + "/loot.json")


# Camada do baú pela altura: superfície, subsolo, cavernas ou perto do submundo ("lava"); ilhas do céu à parte.
static func layer_of(y: int) -> String:
	return "sky" if y >= WorldGen.SKY_BASE else "surface" if y > WorldGen.SURFACE - 14 else "lava" if y < WorldGen.UNDERWORLD_TOP + 12 else "cavern" if y < WorldGen.CAVERN_TOP else "underground"


# Conteúdo de um baú de 40 slots, sorteado com rng. O principal vem sempre.
# `nth` >= 0: é o baú de ilha número nth (Skyware Chest: as primeiras ilhas dão cada item principal na ordem, como na wiki); senão o principal é sorteado.
# Um principal pode ter peso ({"item", "weight"}; os outros pesam 1). "bundle" junta um item ao outro (Flare Gun + Flares).
static func chest(layer: String, rng: RandomNumberGenerator, nth := -1) -> Dictionary:
	var t: Dictionary = tables[layer]
	var c := {"item": PackedInt32Array(), "count": PackedInt32Array()}
	c.item.resize(40)
	c.item.fill(-1)
	c.count.resize(40)
	var main: Array = t.main
	var k := _add(c, 0, _main(main, rng, nth), 1, 1, rng)
	for e in t.common:
		if rng.randf() < e.chance:
			var items: Array = e.items
			k = _add(c, k, items[rng.randi() % items.size()], int(e.min), int(e.max), rng)
	return c


static func main_name(e) -> String:
	return e if e is String else e.item


static func _main(main: Array, rng: RandomNumberGenerator, nth: int) -> String:
	if nth >= 0:
		return main_name(main[nth % main.size()])
	if main.all(func(e): return e is String):
		return main[rng.randi() % main.size()]
	var r: float = rng.randf() * main.reduce(func(sum, e): return sum + (1.0 if e is String else float(e.weight)), 0.0)
	for e in main:
		r -= 1.0 if e is String else float(e.weight)
		if r < 0.0:
			return main_name(e)
	return main_name(main[-1])


# Põe o item no slot k (e o que vem junto) e retorna o próximo slot livre.
static func _add(c: Dictionary, k: int, name: String, lo: int, hi: int, rng: RandomNumberGenerator) -> int:
	c.item[k] = Items.ids[name]
	c.count[k] = rng.randi_range(lo, hi) if hi > lo else lo
	k += 1
	if tables.bundle.has(name):
		var b: Dictionary = tables.bundle[name]
		c.item[k] = Items.ids[b.item]
		c.count[k] = rng.randi_range(int(b.min), int(b.max))
		k += 1
	return k
