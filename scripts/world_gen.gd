class_name WorldGen
extends RefCounted
# Gera os blocos de um chunk por ruído em camadas: superfície, subterrâneo, cavernas, submundo.

const CHUNK := 16
const HEIGHT := 128
const SIZE_CHUNKS := 16        # mundo finito: 16x16 chunks = 256x256 blocos
const UNDERWORLD_TOP := 20     # abaixo disto: submundo
const CAVERN_TOP := 48         # abaixo disto: camada de cavernas (pedra)
const SURFACE := 76            # altura média da superfície

var height_noise := FastNoiseLite.new()
var rock_noise := FastNoiseLite.new()
var cave_noise := FastNoiseLite.new()
var hell_noise := FastNoiseLite.new()
var AIR := 0
var GRASS: int
var DIRT: int
var STONE: int
var ASH: int
var BEDROCK: int
var WOOD: int
var LEAVES: int
var ALTAR: int
var seed: int
var ores: Array = []   # de ores.json, com "block" já convertido em id


func _init(world_seed: int, dir := "res://data/base") -> void:
	seed = world_seed
	for n in [height_noise, rock_noise, cave_noise, hell_noise]:
		n.seed = world_seed
		world_seed += 1
	height_noise.frequency = 0.008
	height_noise.fractal_octaves = 4
	rock_noise.frequency = 0.06
	cave_noise.frequency = 0.035
	hell_noise.frequency = 0.05
	GRASS = Blocks.ids.grass
	DIRT = Blocks.ids.dirt
	STONE = Blocks.ids.stone
	ASH = Blocks.ids.ash
	BEDROCK = Blocks.ids.bedrock
	WOOD = Blocks.ids.wood
	LEAVES = Blocks.ids.leaves
	ALTAR = Blocks.ids.demon_altar
	# Minérios com "group" são alternativos (cobre/estanho...): a seed escolhe um de cada grupo, como no Terraria.
	var groups := {}
	for o in Blocks.read(dir + "/ores.json"):
		o.block = Blocks.ids[o.block]
		o.in = o.get("in", ["stone", "dirt"]).map(func(n): return Blocks.ids[n])
		if o.has("group"):
			groups.get_or_add(o.group, []).append(o)
		else:
			ores.append(o)
	for g in groups:
		ores.append(groups[g][hash([seed, g]) % groups[g].size()])


func surface_height(wx: int, wz: int) -> int:
	return SURFACE + int(height_noise.get_noise_2d(wx, wz) * 14.0)


# ponytail: ~dezenas de ms por chunk em GDScript na thread principal; se travar, mover para WorkerThreadPool.
func generate(cx: int, cz: int) -> PackedByteArray:
	var d := PackedByteArray()
	d.resize(CHUNK * CHUNK * HEIGHT)
	for z in CHUNK:
		for x in CHUNK:
			var wx := cx * CHUNK + x
			var wz := cz * CHUNK + z
			var h := surface_height(wx, wz)
			var hell := hell_noise.get_noise_2d(wx, wz)
			var floor_h := 5 + int(hell * 4.0)
			var ceil_h := UNDERWORLD_TOP - 4 + int(hell * 3.0)
			var i := x + z * CHUNK
			for y in h + 1:
				var b := STONE
				if y == 0:
					b = BEDROCK
				elif y < UNDERWORLD_TOP:
					b = ASH if y < floor_h or y > ceil_h else AIR
				elif y < h - 4 and cave_noise.get_noise_3d(wx, y, wz) > (0.35 if y < CAVERN_TOP else 0.5):
					b = AIR
				elif y == h:
					b = GRASS
				elif y >= CAVERN_TOP:
					b = STONE if rock_noise.get_noise_3d(wx, y, wz) > 0.35 else DIRT
				elif rock_noise.get_noise_3d(wx, y, wz) > 0.55:
					b = DIRT
				d[i + y * CHUNK * CHUNK] = b
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed, cx, cz])
	_ores(d, rng)
	_trees(d, rng)
	_altar(d, rng)
	return d


# Altar demoníaco raro no chão de uma caverna (camada de cavernas).
func _altar(d: PackedByteArray, rng: RandomNumberGenerator) -> void:
	if rng.randf() > 0.15:
		return
	for attempt in 8:  # procura uma coluna que corte uma caverna
		var x := rng.randi_range(1, CHUNK - 2)
		var z := rng.randi_range(1, CHUNK - 2)
		for y in range(CAVERN_TOP, UNDERWORLD_TOP + 1, -1):
			var i := x + z * CHUNK + y * CHUNK * CHUNK
			if d[i] == AIR and d[i + CHUNK * CHUNK] == AIR and d[i - CHUNK * CHUNK] == STONE:
				d[i] = ALTAR
				return


# Veios por passeio aleatório; só trocam os blocos de "in" (padrão: pedra e terra) e ficam dentro do chunk.
func _ores(d: PackedByteArray, rng: RandomNumberGenerator) -> void:
	for o in ores:
		for v in int(o.veins):
			var p := Vector3i(rng.randi() % CHUNK, rng.randi_range(o.min_y, o.max_y), rng.randi() % CHUNK)
			for s in int(o.size):
				var i := p.x + p.z * CHUNK + p.y * CHUNK * CHUNK
				if d[i] in o.in:
					d[i] = o.block
				p[rng.randi() % 3] += 1 if rng.randf() < 0.5 else -1
				p = p.clamp(Vector3i(0, o.min_y, 0), Vector3i(CHUNK - 1, o.max_y, CHUNK - 1))


# Árvores longe da borda do chunk, para as folhas não cruzarem para o vizinho.
func _trees(d: PackedByteArray, rng: RandomNumberGenerator) -> void:
	for z in range(2, CHUNK - 2):
		for x in range(2, CHUNK - 2):
			if rng.randf() > 0.015:
				continue
			var y := HEIGHT - 8
			while y > 0 and d[x + z * CHUNK + y * CHUNK * CHUNK] == AIR:
				y -= 1
			if d[x + z * CHUNK + y * CHUNK * CHUNK] != GRASS:
				continue
			var top := y + rng.randi_range(4, 6)
			for ly in range(top - 2, top + 2):
				var r := 2 if ly < top else 1
				for lz in range(-r, r + 1):
					for lx in range(-r, r + 1):
						var i := x + lx + (z + lz) * CHUNK + ly * CHUNK * CHUNK
						if absi(lx) + absi(lz) < r * 2 and d[i] == AIR:
							d[i] = LEAVES
			for ty in range(y + 1, top + 1):
				d[x + z * CHUNK + ty * CHUNK * CHUNK] = WOOD
