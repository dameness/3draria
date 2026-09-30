class_name WorldGen
extends RefCounted
# Gera os blocos de um chunk por ruído em camadas: superfície (colinas, serras, lagos, praias, árvores, plantas),
# subterrâneo, cavernas (com poças de água e lava) e submundo (mar de lava).
# Mudar qualquer regra daqui muda o mundo de uma seed: mundos salvos antes ficam com emendas (crie outro).

const CHUNK := 16
const HEIGHT := 128
const SIZE_CHUNKS := 120       # mundo finito: 120x120 chunks = 1920x1920 blocos (uma ilha redonda; o resto é oceano). Só a região perto do jogador existe na memória; mude aqui para encolher tudo
const SIZE := SIZE_CHUNKS * CHUNK   # lado do mundo em blocos
const UNDERWORLD_TOP := 20     # abaixo disto: submundo
const CAVERN_TOP := 48         # abaixo disto: camada de cavernas (pedra)
const SURFACE := 76            # altura média da superfície
const WATER_LEVEL := 70        # colunas da superfície abaixo disto viram lago, cheio até aqui
const LAVA_LEVEL := 5          # submundo: o que está aberto até esta altura é lava
const LAVA_CAVE := 24          # cavernas: o que está aberto abaixo disto é lava
const ROCK_LINE := 100         # acima disto a superfície é pedra pelada
const MARGIN := 5              # alturas calculadas além do chunk: inclinação e árvores dos chunks vizinhos
const TREE_CELL := 5           # no máximo uma árvore por célula 5x5 (posição sorteada dentro dela)
const DUNGEON_CELL := 10       # dungeon: grade de salas de 10 blocos (parede incluída), 6 x 5 salas em 2 andares
const DUNGEON_W := 6
const DUNGEON_D := 5
const DUNGEON_Y := 30          # chão do 1º andar
const DUNGEON_FLOORS := 2
const SKY_BASE := 110          # de y = 110 para cima é céu: só há as ilhas flutuantes; a luz do céu e surface_y ignoram isso (a terra embaixo não escurece)
const SKY_ISLANDS := 10        # ilhas (wiki Floating Island), cada uma com uma casa e um Skyware Chest
const SKY_R := 9               # raio de uma ilha
const LAND_RADIUS := 790.0     # o mundo é uma ilha: até este raio do centro é terra; daí a costa desce e fora dela é oceano
const COAST := 70.0            # largura da costa (do fim da terra ao fundo do mar)
const OCEAN_DEPTH := 30        # o fundo do oceano fica tantos blocos abaixo do nível da água
const SEA_CHESTS := 0.02       # chance por chunk de oceano de ter uma ruína submersa com baú (loot "water")
const CHASMS := 12             # abismos por bioma, cada um com um orbe (Shadow Orb / Crimson Heart) no fundo
const CHASM_DEPTH := 38
const MINES := 16              # minas abandonadas (wiki Abandoned Minecart Track): corredor escorado com trilho, fundo no subsolo, poço de corda até a superfície
const MINE_Y0 := 50            # o trilho fica entre estas alturas (acima das cavernas alagadas, abaixo da superfície)
const MINE_Y1 := 58
const LIVING_H := 30           # Living Tree (wiki): altura do tronco acima do chão; o poço interno 5x5 desce até a sala do tesouro (14 abaixo do chão)
const LIVING_TOP := 20         # altura da plataforma do topo do poço (a escada sobe até aqui)
const LIVING_GROUPS := 14        # grupos de Living Trees por mundo (no máximo; o terreno decide)
const LIVING_R := 15           # alcance horizontal de uma árvore (copa e galhos)
const LIVING_RING: Array[Vector2i] = [Vector2i(2, 0), Vector2i(2, 1), Vector2i(2, 2), Vector2i(1, 2), Vector2i(0, 2), Vector2i(-1, 2), Vector2i(-2, 2), Vector2i(-2, 1),
	Vector2i(-2, 0), Vector2i(-2, -1), Vector2i(-2, -2), Vector2i(-1, -2), Vector2i(0, -2), Vector2i(1, -2), Vector2i(2, -2), Vector2i(2, -1)]   # degraus da escada em espiral do poço
const CENTER := Vector2(SIZE_CHUNKS * CHUNK / 2.0, SIZE_CHUNKS * CHUNK / 2.0)   # nascimento: planície
enum {TOP_GRASS, TOP_STONE, TOP_SAND}   # o que cobre a superfície de uma coluna
const DIRS4: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

var height_noise := FastNoiseLite.new()
var rock_noise := FastNoiseLite.new()
var cave_noise := FastNoiseLite.new()
var hell_noise := FastNoiseLite.new()
var ridge_noise := FastNoiseLite.new()
var mount_noise := FastNoiseLite.new()
var pool_noise := FastNoiseLite.new()
var forest_noise := FastNoiseLite.new()
var AIR := 0
var GRASS: int
var DIRT: int
var STONE: int
var ASH: int
var BEDROCK: int
var WOOD: int
var LEAVES: int
var ALTAR: int
var CHEST: int
var CRYSTAL: int
var SAND: int
var WATER: int
var LAVA: int
var TUFT: int
var CACTUS: int
var FLOWERS: Array
var MUSHROOM: int
var seed: int
var evil := "corruption"          # "corruption" ou "crimson": um por mundo, escolhido pela seed
var evil_center := Vector2.ZERO   # centro do bioma do mal (longe do nascimento)
var chasm_centers: Array[Vector2i] = []   # abismos com um orbe no fundo
var chasm_heights := PackedInt32Array()   # altura da superfície em cada abismo
var dungeon_x := 0                # canto (x, z) do dungeon, do lado oposto ao bioma do mal
var dungeon_z := 0
var dungeon_entrance := Vector3i.ZERO   # torre de entrada (centro, altura da superfície)
var test_world := false           # mundo de teste: generate carimba a arena (test_world.gd)
var mines: Array[Dictionary] = []   # [{axis: 0 (x) ou 1 (z), x, z (início), len, ys: altura do trilho em cada passo}]
var living_trees: Array[Dictionary] = []   # Living Trees: [{x, z, y (chão), main (tem a sala do tesouro), branches: [{dir, dy, len}]}]
var living_tunnels: Array[Dictionary] = []   # túneis entre as árvores de um grupo: {axis, lo, hi, fixed, y (chão do túnel)}
var living_chests: Array[Vector3i] = []      # baús do tesouro (loot "living" em loot.json); os dos túneis e do topo são baús comuns e sorteiam pela altura (superfície)
var sky_islands: Array[Vector3i] = []   # (x, y da superfície, z) do centro de cada ilha
var sky_chests: Array[Vector3i] = []     # o baú de cada ilha (mesmo índice)
var hardmode := false             # Wall of Flesh derrotado: minérios novos e o Hallow entram na geração (world.start_hardmode converte o que já existe)
var hm_ores: Array = []           # ores.json com "hardmode": true (um por grupo, escolhido pela seed)
var hallow_center := Vector2.ZERO
# Biomas em faixas (anéis em volta do nascimento, raios em frações de LAND_RADIUS; ângulos a partir da direção do dungeon). Os *_center são um ponto
# representativo de cada faixa (chasmas, colmeia, atalhos de teste); quem decide o bioma de uma coluna são os *_weight.
var lateral := 1.0                 # +1 ou -1 (seed): em que lado ficam neve e deserto
var dungeon_dir := 0.0             # ângulo do centro do mundo para o dungeon (borda); o mal fica do lado oposto
var snow_center := Vector2.ZERO    # neve: anel 0,22-0,50, lado +90°
var desert_center := Vector2.ZERO  # deserto: anel 0,22-0,50, lado -90°
var jungle_center := Vector2.ZERO  # selva: anel 0,50-0,78, lado do dungeon; a colmeia com a larva fica debaixo dela
var hive_center := Vector3i.ZERO   # centro da câmara da colmeia (a larva no chão dela)
var SNOW: int
var MUD: int
var JGRASS: int
var HIVE: int
var LIVING_WOOD: int
var LIVING_LOOM: int
var CHAIR: int
var LARVA: int
var HSAND: int
var SANDSTONE: int
var ICE: int
var HALLOW_GRASS: int
var PEARLSTONE: int
var BRICK: int
var TORCH: int
var TRACK: int
var ROPE: int
var EVIL_STONE: int
var EVIL_GRASS: int
var ORB: int
var ores: Array = []   # de ores.json, com "block" já convertido em id


func _init(world_seed: int, dir := "res://data/base") -> void:
	seed = world_seed
	for n in [height_noise, rock_noise, cave_noise, hell_noise, ridge_noise, mount_noise, pool_noise, forest_noise]:
		n.seed = world_seed
		world_seed += 1
	height_noise.frequency = 0.008
	height_noise.fractal_octaves = 4
	rock_noise.frequency = 0.06
	cave_noise.frequency = 0.035
	hell_noise.frequency = 0.05
	ridge_noise.frequency = 0.012
	ridge_noise.fractal_type = FastNoiseLite.FRACTAL_NONE
	mount_noise.frequency = 0.005
	mount_noise.fractal_octaves = 2
	pool_noise.frequency = 0.03
	forest_noise.frequency = 0.018
	GRASS = Blocks.ids.grass
	DIRT = Blocks.ids.dirt
	STONE = Blocks.ids.stone
	ASH = Blocks.ids.ash
	BEDROCK = Blocks.ids.bedrock
	WOOD = Blocks.ids.wood
	LEAVES = Blocks.ids.leaves
	ALTAR = Blocks.ids.demon_altar
	CHEST = Blocks.ids.chest
	CRYSTAL = Blocks.ids.life_crystal
	SAND = Blocks.ids.sand
	WATER = Blocks.ids.water
	LAVA = Blocks.ids.lava
	TUFT = Blocks.ids.grass_tuft
	CACTUS = Blocks.ids.cactus
	FLOWERS = [Blocks.ids.flower_yellow, Blocks.ids.flower_red, Blocks.ids.flower_pink]
	MUSHROOM = Blocks.ids.mushroom
	var er := RandomNumberGenerator.new()   # bioma do mal: tipo, posição e abismos só dependem da seed
	er.seed = hash([seed, "evil"])
	evil = "corruption" if er.randi() % 2 == 0 else "crimson"
	dungeon_dir = er.randf() * TAU   # o dungeon fica na borda, nesta direção; o mal, do lado oposto; neve e deserto, nas laterais
	lateral = 1.0 if er.randi() % 2 == 0 else -1.0
	evil_center = _at(PI, 0.68)
	EVIL_STONE = Blocks.ids.ebonstone if evil == "corruption" else Blocks.ids.crimstone
	EVIL_GRASS = Blocks.ids.corrupt_grass if evil == "corruption" else Blocks.ids.crimson_grass
	ORB = Blocks.ids.shadow_orb if evil == "corruption" else Blocks.ids.crimson_heart
	var sr := RandomNumberGenerator.new()   # ilhas flutuantes: posição só da seed, longe do nascimento e umas das outras
	sr.seed = hash([seed, "sky"])
	for k in SKY_ISLANDS:
		for attempt in 60:
			var c := Vector2(sr.randi_range(SKY_R + 4, SIZE - SKY_R - 5), sr.randi_range(SKY_R + 4, SIZE - SKY_R - 5))
			if c.distance_to(CENTER) > 45.0 and c.distance_to(CENTER) < LAND_RADIUS and sky_islands.all(func(o): return c.distance_to(Vector2(o.x, o.z)) > 55.0):
				var y := SKY_BASE + 8 + sr.randi_range(0, 4)
				sky_islands.append(Vector3i(int(c.x), y, int(c.y)))
				sky_chests.append(Vector3i(int(c.x), y + 1, int(c.y) - 1))   # no chão da casa, ao norte
				break
	for k in CHASMS:
		var c := _at(PI + er.randf_range(-0.42, 0.42), er.randf_range(0.52, 0.86))   # espalhados pela faixa do mal
		chasm_centers.append(Vector2i(c))
		chasm_heights.append(surface_height(int(c.x), int(c.y)))
	HALLOW_GRASS = Blocks.ids.hallowed_grass
	PEARLSTONE = Blocks.ids.pearlstone
	hallow_center = _at(lateral * PI / 2, 0.65)
	SNOW = Blocks.ids.snow_block
	MUD = Blocks.ids.mud
	JGRASS = Blocks.ids.jungle_grass
	HIVE = Blocks.ids.hive
	LARVA = Blocks.ids.bee_larva
	HSAND = Blocks.ids.hardened_sand
	SANDSTONE = Blocks.ids.sandstone
	ICE = Blocks.ids.ice_block
	BRICK = Blocks.ids.dungeon_brick
	TORCH = Blocks.ids.torch
	TRACK = Blocks.ids.minecart_track
	ROPE = Blocks.ids.rope
	LIVING_WOOD = Blocks.ids.living_wood
	LIVING_LOOM = Blocks.ids.living_loom
	CHAIR = Blocks.ids.chair
	snow_center = _at(-lateral * PI / 2, 0.36)
	desert_center = _at(lateral * PI / 2, 0.36)
	jungle_center = _at(0.0, 0.64)
	var ex := 0   # o dungeon, na borda da terra: se a entrada cair num lago, anda um pouco pela borda até achar chão seco
	var ez := 0
	for k in 16:
		var dc := _at((k / 2 + 1) * 0.03 * (1.0 if k % 2 == 0 else -1.0) if k > 0 else 0.0, 0.9)
		dungeon_x = int(dc.x) - DUNGEON_W * DUNGEON_CELL / 2
		dungeon_z = int(dc.y) - DUNGEON_D * DUNGEON_CELL / 2
		ex = dungeon_x + DUNGEON_W / 2 * DUNGEON_CELL + DUNGEON_CELL / 2
		ez = dungeon_z + DUNGEON_D / 2 * DUNGEON_CELL + DUNGEON_CELL / 2
		if surface_height(ex, ez) > WATER_LEVEL + 2:
			break
	dungeon_entrance = Vector3i(ex, surface_height(ex, ez), ez)
	hive_center = Vector3i(int(jungle_center.x), surface_height(int(jungle_center.x), int(jungle_center.y)) - 16, int(jungle_center.y))
	_plan_living()
	_plan_mines()
	# Minérios com "group" são alternativos (cobre/estanho...): a seed escolhe um de cada grupo, como no Terraria.
	var groups := {}
	for o in Blocks.read(dir + "/ores.json"):
		if o.has("evil") and o.evil != evil:   # demonita só em mundos de Corrupção, crimtano só nos de Carmesim
			continue
		o.block = Blocks.ids[o.block]
		o.in = o.get("in", ["stone", "dirt"]).map(func(n): return Blocks.ids[n])
		var target: Array = hm_ores if o.get("hardmode", false) else ores
		if o.has("group"):
			groups.get_or_add(o.group, []).append(o)
		else:
			target.append(o)
	for g in groups:
		var pick: Dictionary = groups[g][hash([seed, g]) % groups[g].size()]
		(hm_ores if pick.get("hardmode", false) else ores).append(pick)


# Colinas largas + serras (cristas de ruído onde a máscara de montanha é alta) + terraços de 5 blocos, como as
# saliências de rocha do Terraria; o meio do mundo é uma planície para o nascimento e em volta há oceano (o mundo é uma ilha).
func surface_height(wx: int, wz: int) -> int:
	var hills := height_noise.get_noise_2d(wx, wz)
	var ridge := 1.0 - absf(ridge_noise.get_noise_2d(wx, wz))
	var mount := clampf(mount_noise.get_noise_2d(wx, wz) * 2.5 - 0.3, 0.0, 1.0)
	var h := SURFACE + hills * 16.0 + mount * ridge * ridge * 40.0
	var q := h / 5.0
	h = lerpf(h, (floorf(q) + smoothstep(0.55, 1.0, q - floorf(q))) * 5.0, 0.38)
	var flat := 1.0 - smoothstep(16.0, 46.0, Vector2(wx, wz).distance_to(CENTER))
	h = lerpf(h, SURFACE + 2.0 + hills * 2.0, flat)
	var sea := smoothstep(LAND_RADIUS, LAND_RADIUS + COAST, Vector2(wx, wz).distance_to(CENTER))   # ilha: a costa desce até o fundo do oceano em volta
	h = lerpf(h, WATER_LEVEL - OCEAN_DEPTH + hills * 2.0, sea)
	return clampi(int(h), 24, HEIGHT - 20)


# O que cobre a coluna i (índice na grade de alturas hs, largura W): pedra em penhascos e picos, areia perto
# d'água (praia e fundo de lago), senão grama.
func _top(hs: PackedInt32Array, i: int, W: int) -> int:
	var h := hs[i]
	var steep := maxi(maxi(absi(h - hs[i - 1]), absi(h - hs[i + 1])), maxi(absi(h - hs[i - W]), absi(h - hs[i + W])))
	if steep >= 6 or h >= ROCK_LINE:
		return TOP_STONE
	return TOP_SAND if h <= WATER_LEVEL + 1 else TOP_GRASS


# ponytail: ~dezenas de ms por chunk em GDScript; roda no WorkerThreadPool (world.gd), não trava a tela.
func generate(cx: int, cz: int) -> PackedByteArray:
	var d := PackedByteArray()
	d.resize(CHUNK * CHUNK * HEIGHT)
	var W := CHUNK + 2 * MARGIN
	var hs := PackedInt32Array()
	hs.resize(W * W)
	for z in W:
		for x in W:
			hs[x + z * W] = surface_height(cx * CHUNK + x - MARGIN, cz * CHUNK + z - MARGIN)
	for z in CHUNK:
		for x in CHUNK:
			var wx := cx * CHUNK + x
			var wz := cz * CHUNK + z
			var hi := (x + MARGIN) + (z + MARGIN) * W
			var h := hs[hi]
			var top := _top(hs, hi, W)
			var hell := hell_noise.get_noise_2d(wx, wz)
			var floor_h := 5 + int(hell * 4.0)
			var ceil_h := UNDERWORLD_TOP - 4 + int(hell * 3.0)
			var topsoil := 3 + int((rock_noise.get_noise_2d(wx, wz) + 1.0) * 1.5)   # terra sob a superfície: 3 a 6 blocos
			var pool := pool_noise.get_noise_2d(wx, wz)
			var wet := (30 + int(pool * 16)) if pool > 0.2 else 0   # caverna alagada até esta altura (0 = seca)
			var i := x + z * CHUNK
			for y in h + 1:
				var b := STONE
				var depth := h - y
				if y == 0:
					b = BEDROCK
				elif y < UNDERWORLD_TOP:
					b = ASH if y < floor_h or y > ceil_h else (LAVA if y <= LAVA_LEVEL else AIR)
				elif depth > 4 and cave_noise.get_noise_3d(wx, y, wz) > (0.35 if y < CAVERN_TOP else 0.5):
					b = LAVA if y <= LAVA_CAVE else (WATER if y <= wet else AIR)
				elif depth == 0:
					b = [GRASS, STONE, SAND][top]
				elif top == TOP_STONE:
					b = STONE
				elif top == TOP_SAND and depth <= 3:
					b = SAND
				elif depth <= topsoil:
					b = DIRT
				elif y >= CAVERN_TOP:
					b = STONE if rock_noise.get_noise_3d(wx, y, wz) > 0.35 else DIRT
				elif rock_noise.get_noise_3d(wx, y, wz) > 0.55:
					b = DIRT
				d[i + y * CHUNK * CHUNK] = b
			for y in range(h + 1, WATER_LEVEL + 1):   # lago
				d[i + y * CHUNK * CHUNK] = WATER
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed, cx, cz])
	_evil(d, hs, W, cx, cz)
	_snow(d, hs, W, cx, cz)
	_desert(d, hs, W, cx, cz)
	_jungle(d, hs, W, cx, cz)
	_dungeon(d, cx, cz)
	_mines(d, cx, cz)
	_ores(d, rng)
	_trees(d, hs, W, cx, cz)
	_plants(d, hs, W, rng)
	_cactus(d, hs, W, cx, cz)
	rng.seed = hash([seed, cx, cz, "altar"])
	_altar(d, rng)
	rng.seed = hash([seed, cx, cz, "chest"])
	_chest(d, rng)
	rng.seed = hash([seed, cx, cz, "crystal"])
	_crystal(d, rng)
	_living(d, cx, cz)
	_sea(d, cx, cz)
	_sky(d, cx, cz)
	if hardmode:
		hardmode_pass(d, cx, cz)
	if test_world:
		TestWorld.stamp(d, cx, cz)
	return d


# Onde (x, z dentro do chunk) fica a ruína submersa do chunk, ou (-1, -1) se não tem.
func sea_spot(cx: int, cz: int) -> Vector2i:
	if Vector2(cx * CHUNK + CHUNK / 2.0, cz * CHUNK + CHUNK / 2.0).distance_to(CENTER) < LAND_RADIUS + COAST + 12.0:
		return Vector2i(-1, -1)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed, cx, cz, "sea"])
	if rng.randf() > SEA_CHESTS:
		return Vector2i(-1, -1)
	return Vector2i(rng.randi_range(2, CHUNK - 3), rng.randi_range(2, CHUNK - 3))


# Ruínas submersas (no fundo do mar aberto, de vez em quando): plataforma de arenito com quatro pilares e um baú de loot "water". Os pilares são o marco para achá-las.
func _sea(d: PackedByteArray, cx: int, cz: int) -> void:
	var spot := sea_spot(cx, cz)
	if spot.x < 0:
		return
	var x := spot.x
	var z := spot.y
	var layer := CHUNK * CHUNK
	var floors := PackedInt32Array()
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var y := WATER_LEVEL
			while y > 0 and not Blocks.solid[d[x + dx + (z + dz) * CHUNK + y * layer]]:
				y -= 1
			floors.append(y)
	var pad := floors[0]
	for f in floors:
		pad = maxi(pad, f)
	for k in 9:
		var i := x + k % 3 - 1 + (z + k / 3 - 1) * CHUNK
		var corner := k % 2 == 0 and k != 4
		for y in range(floors[k], pad + (5 if corner else 1)):
			d[i + y * layer] = SANDSTONE
	d[x + z * CHUNK + (pad + 1) * layer] = CHEST


# Ilhas flutuantes (wiki Floating Island): um disco de terra com grama em cima, nuvens embaixo, e no meio uma casinha de sunplate com um Skyware Chest.
# Só toca nos chunks que a ilha alcança.
func _sky(d: PackedByteArray, cx: int, cz: int) -> void:
	for n in sky_islands.size():
		var isl := sky_islands[n]
		if absi(isl.x - cx * CHUNK - CHUNK / 2) > SKY_R + CHUNK / 2 or absi(isl.z - cz * CHUNK - CHUNK / 2) > SKY_R + CHUNK / 2:
			continue
		for z in CHUNK:
			for x in CHUNK:
				var dx := cx * CHUNK + x - isl.x
				var dz := cz * CHUNK + z - isl.z
				var u := 1.0 - Vector2(dx, dz).length() / SKY_R
				if u <= 0.0:
					continue
				var top := isl.y if maxi(absi(dx), absi(dz)) <= 3 else isl.y - int((1.0 - u) * 3.0)   # o centro é plano (a casa); a borda desce
				var bottom := top - 1 - int(u * 6.0)
				for y in range(bottom, top + 1):
					_write(d, cx, cz, isl.x + dx, y, isl.z + dz, Blocks.ids.cloud if y <= bottom + 1 else GRASS if y == top else DIRT)
		# a casa: paredes de sunplate (5x5, 3 de altura) com uma porta de 1x2 ao sul, teto, o baú ao norte e uma tocha
		var base := isl.y + 1
		for dz in range(-2, 3):
			for dx in range(-2, 3):
				var wall := maxi(absi(dx), absi(dz)) == 2
				for y in range(base - 1, base + 4):
					var door := dx == 0 and dz == 2 and y in [base, base + 1]
					var solid := y == base - 1 or y == base + 3 or (wall and not door)   # piso, teto e paredes
					if solid:
						_write(d, cx, cz, isl.x + dx, y, isl.z + dz, Blocks.ids.sunplate)
					elif y >= base:
						_write(d, cx, cz, isl.x + dx, y, isl.z + dz, AIR)
		var chest := sky_chests[n]
		_write(d, cx, cz, chest.x, chest.y, chest.z, CHEST)
		_write(d, cx, cz, isl.x + 1, base, isl.z + 1, Blocks.ids.torch)


# Ponto do mundo a `frac` de LAND_RADIUS do centro, no ângulo `a` medido a partir da direção do dungeon.
func _at(a: float, frac: float) -> Vector2:
	return CENTER + Vector2.from_angle(dungeon_dir + a) * frac * LAND_RADIUS


# Quanto a coluna está dentro do setor (anel de frac r0 a r1, ângulo a0 ± hw): distância em blocos até a borda mais próxima (negativa fora).
func _sector(wx: int, wz: int, r0: float, r1: float, a0: float, hw: float) -> float:
	var v := Vector2(wx, wz) - CENTER
	var r := v.length()
	var da := absf(wrapf(v.angle() - dungeon_dir - a0, -PI, PI))
	return minf(minf(r - r0 * LAND_RADIUS, r1 * LAND_RADIUS - r), (hw - da) * r)


# Peso 0-1 da faixa: borda irregular (ruído largo + ruído fino), 1 dentro, 0 fora. Sai cedo, sem ruído, longe da borda.
func _band(wx: int, wz: int, d_in: float, salt: int) -> float:
	if d_in < -45.0:
		return 0.0
	d_in += mount_noise.get_noise_2d(wx + salt, wz) * 30.0
	if d_in < -10.0:
		return 0.0
	return clampf((d_in + rock_noise.get_noise_2d(wx + salt, wz) * 8.0) / 4.0, 0.0, 1.0)


# O chunk (por ox, oz) está perto do anel r0..r1 (frações de LAND_RADIUS)? Descarta os outros sem olhar coluna por coluna.
func _near_ring(ox: int, oz: int, r0: float, r1: float) -> bool:
	var r := Vector2(ox + CHUNK / 2.0, oz + CHUNK / 2.0).distance_to(CENTER)
	return r > r0 * LAND_RADIUS - 60.0 and r < r1 * LAND_RADIUS + 60.0


func hallow_weight(wx: int, wz: int) -> float:
	return _band(wx, wz, _sector(wx, wz, 0.5, 0.8, lateral * PI / 2, 0.5), 500)


func snow_weight(wx: int, wz: int) -> float:
	return _band(wx, wz, _sector(wx, wz, 0.22, 0.5, -lateral * PI / 2, 1.05), 900)


func desert_weight(wx: int, wz: int) -> float:
	return _band(wx, wz, _sector(wx, wz, 0.22, 0.5, lateral * PI / 2, 1.05), 1300)


func jungle_weight(wx: int, wz: int) -> float:
	return _band(wx, wz, _sector(wx, wz, 0.5, 0.78, 0.0, 0.95), 1700)


# Corrupção/Carmesim: setor do lado oposto ao dungeon, do anel da neve até perto da praia.
func evil_weight(wx: int, wz: int) -> float:
	return _band(wx, wz, _sector(wx, wz, 0.45, 0.92, PI, 0.6), 0)


# Lado do oceano: true = o da direção do dungeon (no Calamity, o Sulphurous Sea substitui o oceano desse lado), false = o oposto.
func sea_side_dungeon(wx: int, wz: int) -> bool:
	return absf(wrapf((Vector2(wx, wz) - CENTER).angle() - dungeon_dir, -PI, PI)) < PI / 2


# Fora da terra (costa e mar aberto)?
func in_sea(wx: int, wz: int) -> bool:
	return Vector2(wx, wz).distance_to(CENTER) > LAND_RADIUS + COAST * 0.5


# Hardmode: veios de cobalto/paládio na pedra e o Hallow (grama e pedra) num disco do outro lado do mundo. Determinístico por chunk:
# vale tanto na geração quanto para converter (world.start_hardmode) o que já estava gerado.
func hardmode_pass(d: PackedByteArray, cx: int, cz: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed, cx, cz, "hardmode"])
	_ores(d, rng, hm_ores)
	var ox := cx * CHUNK
	var oz := cz * CHUNK
	if not _near_ring(ox, oz, 0.5, 0.8):
		return
	var layer := CHUNK * CHUNK
	for z in CHUNK:
		for x in CHUNK:
			if hallow_weight(ox + x, oz + z) < 0.5:
				continue
			var i := x + z * CHUNK
			var top := HEIGHT - 1
			while top > 0 and (d[i + top * layer] == AIR or Blocks.shape[d[i + top * layer]] != "" or d[i + top * layer] == LEAVES or d[i + top * layer] == WOOD):
				top -= 1
			if d[i + top * layer] == GRASS:
				d[i + top * layer] = HALLOW_GRASS
			for y in range(UNDERWORLD_TOP + 8, top + 1):
				if d[i + y * layer] == STONE:
					d[i + y * layer] = PEARLSTONE


# Selva (wiki Jungle): grama de selva e lama no lugar da grama e da terra (as árvores ficam) e, debaixo do centro, a colmeia: uma bola de favo
# de 5 blocos com uma câmara oca e a larva no chão dela (quebrar a larva chama a Queen Bee).
func _jungle(d: PackedByteArray, hs: PackedInt32Array, W: int, cx: int, cz: int) -> void:
	var ox := cx * CHUNK
	var oz := cz * CHUNK
	if not _near_ring(ox, oz, 0.5, 0.78):
		return
	var layer := CHUNK * CHUNK
	for z in CHUNK:
		for x in CHUNK:
			if jungle_weight(ox + x, oz + z) < 0.5 or evil_weight(ox + x, oz + z) >= 0.5 or snow_weight(ox + x, oz + z) >= 0.5 or desert_weight(ox + x, oz + z) >= 0.5:
				continue
			var i := x + z * CHUNK
			var h := hs[(x + MARGIN) + (z + MARGIN) * W]
			for y in range(UNDERWORLD_TOP + 8, h + 1):
				var b := d[i + y * layer]
				if b == GRASS:
					d[i + y * layer] = JGRASS
				elif b == DIRT:
					d[i + y * layer] = MUD
	var hc := hive_center
	for dz in range(-6, 7):
		for dy in range(-6, 7):
			for dx in range(-6, 7):
				var lx := hc.x + dx - ox
				var lz := hc.z + dz - oz
				if lx < 0 or lx >= CHUNK or lz < 0 or lz >= CHUNK:
					continue
				var r := Vector3(dx, dy, dz).length()
				var i := lx + lz * CHUNK + (hc.y + dy) * layer
				if r <= 2.6 and dy >= 0:
					d[i] = AIR
				elif r <= 5.4 and d[i] != WATER and d[i] != LAVA:
					d[i] = HIVE
	var lx := hc.x - ox
	var lz := hc.z - oz
	if lx >= 0 and lx < CHUNK and lz >= 0 and lz < CHUNK:
		d[lx + lz * CHUNK + hc.y * layer] = LARVA   # no chão da câmara (o piso é de favo)


# Deserto (wiki Desert): areia na superfície (6 blocos), areia endurecida no resto da terra e arenito em manchas na pedra. Sem grama, árvores nem plantas.
func _desert(d: PackedByteArray, hs: PackedInt32Array, W: int, cx: int, cz: int) -> void:
	var ox := cx * CHUNK
	var oz := cz * CHUNK
	if not _near_ring(ox, oz, 0.22, 0.5):
		return
	var layer := CHUNK * CHUNK
	for z in CHUNK:
		for x in CHUNK:
			if desert_weight(ox + x, oz + z) < 0.5 or evil_weight(ox + x, oz + z) >= 0.5 or snow_weight(ox + x, oz + z) >= 0.5:
				continue
			var i := x + z * CHUNK
			var h := hs[(x + MARGIN) + (z + MARGIN) * W]
			for y in range(UNDERWORLD_TOP + 8, h + 1):
				var b := d[i + y * layer]
				if b == GRASS or b == DIRT or b == SAND:
					d[i + y * layer] = SAND if h - y <= 6 else HSAND
				elif b == STONE and rock_noise.get_noise_3d(ox + x + 300, y, oz + z) > -0.1:
					d[i + y * layer] = SANDSTONE


# Neve (wiki Snow biome): neve no lugar da grama e da terra, gelo em manchas na pedra (do submundo para cima). Sem grama, sem árvores nem plantas.
func _snow(d: PackedByteArray, hs: PackedInt32Array, W: int, cx: int, cz: int) -> void:
	var ox := cx * CHUNK
	var oz := cz * CHUNK
	if not _near_ring(ox, oz, 0.22, 0.5):
		return
	var layer := CHUNK * CHUNK
	for z in CHUNK:
		for x in CHUNK:
			if snow_weight(ox + x, oz + z) < 0.5 or evil_weight(ox + x, oz + z) >= 0.5:
				continue
			var i := x + z * CHUNK
			var h := hs[(x + MARGIN) + (z + MARGIN) * W]
			for y in range(UNDERWORLD_TOP + 8, h + 1):
				var b := d[i + y * layer]
				if b == GRASS or b == DIRT:
					d[i + y * layer] = SNOW
				elif b == STONE and rock_noise.get_noise_3d(ox + x + 300, y, oz + z) > -0.1:
					d[i + y * layer] = ICE


func in_dungeon(x: int, y: int, z: int) -> bool:
	return x >= dungeon_x and x <= dungeon_x + DUNGEON_W * DUNGEON_CELL and z >= dungeon_z and z <= dungeon_z + DUNGEON_D * DUNGEON_CELL \
		and y >= DUNGEON_Y and y <= DUNGEON_Y + DUNGEON_FLOORS * DUNGEON_CELL


# Dungeon: labirinto de tijolos azuis (salas de 10 blocos em 2 andares) do lado oposto ao mal, com portas entre as salas de cada fileira,
# uma passagem entre fileiras e entre andares, tochas, baús e uma torre de entrada aberta na superfície. Tudo por coordenada:
# cada chunk escreve a sua parte.
func _dungeon(d: PackedByteArray, cx: int, cz: int) -> void:
	var ox := cx * CHUNK
	var oz := cz * CHUNK
	var x1 := dungeon_x + DUNGEON_W * DUNGEON_CELL
	var z1 := dungeon_z + DUNGEON_D * DUNGEON_CELL
	if ox > x1 or oz > z1 or ox + CHUNK <= dungeon_x or oz + CHUNK <= dungeon_z:
		return
	var layer := CHUNK * CHUNK
	var top := DUNGEON_Y + DUNGEON_FLOORS * DUNGEON_CELL
	var e := dungeon_entrance
	for z in CHUNK:
		for x in CHUNK:
			var wx := ox + x
			var wz := oz + z
			var i := x + z * CHUNK
			if wx >= dungeon_x and wx <= x1 and wz >= dungeon_z and wz <= z1:
				for y in range(DUNGEON_Y, top + 1):
					d[i + y * layer] = _dungeon_block(wx, y, wz)
			var ring := maxi(absi(wx - e.x), absi(wz - e.z))   # torre de entrada: poço 3x3 aberto até o céu, parede de tijolos em volta
			if ring <= 2:
				for y in range(top, e.y + 7):
					if ring <= 1:
						d[i + y * layer] = AIR
					elif y <= e.y + 5 and not (wz - e.z == 2 and wx == e.x and y <= e.y + 2):   # a porta é o vão da frente
						d[i + y * layer] = BRICK


# Sorteia as minas pela seed: 70 a 110 blocos em x ou z, dentro da ilha, longe do dungeon e da colmeia; o trilho sobe e desce um bloco por passo em trechos de 4 a 9.
func _plan_mines() -> void:
	var r := RandomNumberGenerator.new()
	r.seed = hash([seed, "mines"])
	var dun := Rect2(dungeon_x - 10, dungeon_z - 10, DUNGEON_W * DUNGEON_CELL + 20, DUNGEON_D * DUNGEON_CELL + 20)
	for n in MINES:
		for attempt in 40:
			var axis := r.randi() % 2
			var span := r.randi_range(70, 110)
			var x := int(CENTER.x) + r.randi_range(-650, 650)
			var z := int(CENTER.y) + r.randi_range(-650, 650)
			var a := Vector2(x, z)
			var b := a + (Vector2(span, 0) if axis == 0 else Vector2(0, span))
			var ok := a.distance_to(CENTER) < 0.85 * LAND_RADIUS and b.distance_to(CENTER) < 0.85 * LAND_RADIUS
			for k in 5:
				var q := a.lerp(b, k / 4.0)
				ok = ok and not dun.has_point(q) and q.distance_to(Vector2(hive_center.x, hive_center.z)) > 25.0 and q.distance_to(CENTER) > 40.0
			for t in living_trees:
				ok = ok and Geometry2D.get_closest_point_to_segment(Vector2(t.x, t.z), a, b).distance_to(Vector2(t.x, t.z)) > 16.0   # a sala do tesouro fica na altura das minas
			var box := Rect2(a, b - a).abs().grow(6.0)   # uma mina não cruza outra (o corredor de uma apagaria o trilho da outra)
			for other in mines:
				ok = ok and not box.intersects(Rect2(Vector2(other.x, other.z), Vector2(other.len if other.axis == 0 else 0, 0 if other.axis == 0 else other.len)).abs().grow(6.0))
			if not ok:
				continue
			var ys := PackedInt32Array()
			var y := r.randi_range(MINE_Y0 + 2, MINE_Y1 - 2)
			var slope := 0
			var run := 0
			for k in span:
				if run == 0:
					slope = [-1, 0, 0, 1][r.randi() % 4]
					run = r.randi_range(4, 9)
				run -= 1
				y = clampi(y + slope, MINE_Y0, MINE_Y1)
				ys.append(y)
			mines.append({"axis": axis, "x": x, "z": z, "len": span, "ys": ys})
			break


# Uma mina: corredor 3x4 com o chão firme e um trilho no meio, escoras de madeira a cada 6 blocos, tocha a cada 12 e, no início, um poço 3x3 com corda até a superfície.
# Tudo por coordenada (cada chunk escreve a sua parte).
func _mines(d: PackedByteArray, cx: int, cz: int) -> void:
	var layer := CHUNK * CHUNK
	var ox := cx * CHUNK
	var oz := cz * CHUNK
	for m in mines:
		var along: bool = m.axis == 0
		var x1: int = m.x + (m.len if along else 0) + 3
		var z1: int = m.z + (0 if along else m.len) + 3
		if x1 < ox or m.x - 3 >= ox + CHUNK or z1 < oz or m.z - 3 >= oz + CHUNK:
			continue
		var shaft_top := surface_height(m.x + (1 if along else 0), m.z + (0 if along else 1)) + 3
		for k in m.len:
			var y: int = m.ys[k]
			var frame: bool = k % 6 == 0 and k > 0 and k < m.len - 1
			for lane in range(-1, 2):
				var wx: int = m.x + (k if along else lane)
				var wz: int = m.z + (lane if along else k)
				var lx := wx - ox
				var lz := wz - oz
				if lx < 0 or lx >= CHUNK or lz < 0 or lz >= CHUNK:
					continue
				var i := lx + lz * CHUNK
				if d[i + (y - 1) * layer] == AIR or Blocks.liquid[d[i + (y - 1) * layer]] == 1 or Blocks.soft[d[i + (y - 1) * layer]] == 1:
					d[i + (y - 1) * layer] = STONE   # chão firme onde a caverna abre por baixo
				for dy in 4:
					d[i + (y + dy) * layer] = AIR
				if k <= 2:   # poço de entrada: sobe até a superfície, com a corda numa ponta
					for yy in range(y + 4, mini(shaft_top, HEIGHT - 1) + 1):
						d[i + yy * layer] = AIR
					if k == 1 and lane == 1:
						for yy in range(y, mini(shaft_top, HEIGHT - 1) - 2):
							d[i + yy * layer] = ROPE
				if lane == 0 and d[i + y * layer] == AIR:
					d[i + y * layer] = TRACK
				if frame:
					d[i + (y + 3) * layer] = WOOD
					if lane != 0:
						d[i + y * layer] = WOOD
						d[i + (y + 1) * layer] = WOOD
						d[i + (y + 2) * layer] = WOOD
				elif k % 12 == 3 and lane == 1:
					d[i + (y + 1) * layer] = TORCH


# Living Trees (wiki): grupos de árvores gigantes de Living Wood com um poço oco por dentro (fechado: é preciso cortar o tronco), túneis entre as árvores do grupo
# com baú de superfície, e na árvore principal uma sala do tesouro no fundo (Living Loom, cadeira e o baú com as varinhas). Tudo sai da seed.
# Escala: 1 tile = 0,6 bloco, então 13-30 tiles de distância viram 14-22 blocos e a árvore tem 26 de tronco.
func _plan_living() -> void:
	var r := RandomNumberGenerator.new()
	r.seed = hash([seed, "living"])
	var dun := Rect2(dungeon_x - 14, dungeon_z - 14, DUNGEON_W * DUNGEON_CELL + 28, DUNGEON_D * DUNGEON_CELL + 28)
	var mains: Array[Vector2] = []
	for attempt in 400:
		if mains.size() >= LIVING_GROUPS:
			break
		var c := CENTER + Vector2.from_angle(r.randf() * TAU) * r.randf_range(0.12, 0.92) * LAND_RADIUS
		if not _living_ok(c, dun) or mains.any(func(m): return m.distance_to(c) < 110.0):
			continue
		mains.append(c)
		var axis := r.randi() % 2
		var group: Array[Dictionary] = [_living_tree(c, true, r)]
		for side in [-1, 1]:
			var at := c
			for k in r.randi_range(0, 2):
				at += (Vector2(side, 0) if axis == 0 else Vector2(0, side)) * r.randi_range(14, 22)
				if not _living_ok(at, dun) or surface_height(int(at.x), int(at.y)) > group[0].y + 5:   # o túnel (7 abaixo da principal) tem de cruzar o poço de todas
					break
				group.append(_living_tree(at, false, r))
		var ty: int = group[0].y - 7
		var lo: int = group.map(func(t): return t.x if axis == 0 else t.z).min()
		var hi: int = group.map(func(t): return t.x if axis == 0 else t.z).max()
		if hi > lo:
			living_tunnels.append({"axis": axis, "lo": lo, "hi": hi, "fixed": group[0].z if axis == 0 else group[0].x, "y": ty})
		living_trees.append_array(group)
	for t in living_trees:
		if t.main:
			living_chests.append(Vector3i(t.x + 4, t.y - 13, t.z))


# Terreno bom para uma Living Tree: em terra firme na floresta (nenhum outro bioma por perto), longe do dungeon e da colmeia, plano ao redor.
func _living_ok(c: Vector2, dun: Rect2) -> bool:
	if c.distance_to(CENTER) > 0.92 * LAND_RADIUS or dun.has_point(c) or c.distance_to(Vector2(hive_center.x, hive_center.z)) < 30.0:
		return false
	for k in 9:
		var q := c if k == 8 else c + Vector2.from_angle(TAU * k / 8.0) * 16.0
		if evil_weight(int(q.x), int(q.y)) > 0.0 or hallow_weight(int(q.x), int(q.y)) > 0.0 or snow_weight(int(q.x), int(q.y)) > 0.0 \
				or desert_weight(int(q.x), int(q.y)) > 0.0 or jungle_weight(int(q.x), int(q.y)) > 0.0:
			return false
	var by := surface_height(int(c.x), int(c.y))
	if by < WATER_LEVEL + 4 or by > 84:
		return false
	for k in 8:
		var q := c + Vector2.from_angle(TAU * k / 8.0) * 9.0
		if absi(surface_height(int(q.x), int(q.y)) - by) > 6:
			return false
	return true


func _living_tree(c: Vector2, main: bool, r: RandomNumberGenerator) -> Dictionary:
	var branches := []
	for k in 3:
		var a := TAU * (k + r.randf_range(0.0, 0.8)) / 3.0
		branches.append({"dir": Vector2.from_angle(a), "dy": r.randi_range(18, 26), "len": r.randi_range(5, 7)})
	return {"x": int(c.x), "z": int(c.y), "y": surface_height(int(c.x), int(c.y)), "main": main, "branches": branches}


# Escreve a parte das Living Trees que cai neste chunk (por coordenada: os chunks vizinhos calculam o mesmo).
func _living(d: PackedByteArray, cx: int, cz: int) -> void:
	var layer := CHUNK * CHUNK
	var ox := cx * CHUNK
	var oz := cz * CHUNK
	for t in living_trees:
		if t.x + LIVING_R < ox or t.x - LIVING_R >= ox + CHUNK or t.z + LIVING_R < oz or t.z - LIVING_R >= oz + CHUNK:
			continue
		for lz in CHUNK:
			for lx in CHUNK:
				var dx: int = ox + lx - t.x
				var dz: int = oz + lz - t.z
				if dx * dx + dz * dz > LIVING_R * LIVING_R:
					continue
				for dy in range(-14, LIVING_H + 12):
					var b := _living_block(t, dx, dz, dy)
					if b == -1:
						continue
					var i: int = lx + lz * CHUNK + (t.y + dy) * layer
					if b == LEAVES and d[i] != AIR:   # a copa só ocupa o ar (o morro fica)
						continue
					d[i] = b
	for tn in living_tunnels:
		var along: bool = tn.axis == 0
		if (tn.hi + 2 < ox or tn.lo - 2 >= ox + CHUNK or tn.fixed + 2 < oz or tn.fixed - 2 >= oz + CHUNK) if along else (tn.hi + 2 < oz or tn.lo - 2 >= oz + CHUNK or tn.fixed + 2 < ox or tn.fixed - 2 >= ox + CHUNK):
			continue
		for lz in CHUNK:
			for lx in CHUNK:
				var s: int = ox + lx if along else oz + lz   # ao longo do túnel
				var p: int = (oz + lz if along else ox + lx) - tn.fixed   # de lado
				if s < tn.lo or s > tn.hi or absi(p) > 1:
					continue
				d[lx + lz * CHUNK + (tn.y - 1) * layer] = LIVING_WOOD
				for k in 3:
					var b := AIR
					if k == 0 and p == 0 and s == tn.lo + 9:
						b = CHEST
					elif k == 1 and p == 1 and (s - tn.lo) % 7 == 3:
						b = TORCH
					d[lx + lz * CHUNK + (tn.y + k) * layer] = b


# O bloco da árvore t na posição relativa (dx, dy, dz) ao tronco no chão; -1 = não toca. Tronco com raiz alargada, poço 5x5 com escada em espiral,
# sala do tesouro, plataforma com baú no topo, três galhos com folhas e a copa.
func _living_block(t: Dictionary, dx: int, dz: int, dy: int) -> int:
	var b := -1
	var r2 := dx * dx + dz * dz
	var cheb := maxi(absi(dx), absi(dz))
	var rr := 4.5 + clampf((3 - dy) * 0.5, 0.0, 3.5)
	if dy <= LIVING_H + 2 and r2 <= rr * rr:
		b = LIVING_WOOD
		if cheb <= 2 and dy >= -13 and dy <= LIVING_TOP + 3:
			b = AIR
			if cheb == 2 and dy <= LIVING_TOP and LIVING_RING[posmod(dy + 13, 16)] == Vector2i(dx, dz):
				b = LIVING_WOOD   # um degrau por bloco de altura, dando a volta no poço
			elif dy == LIVING_TOP and cheb <= 1:
				b = LIVING_WOOD   # plataforma do topo
			elif dy == LIVING_TOP + 1 and cheb == 0:
				b = CHEST
			elif cheb == 2 and dx * dz == 0 and posmod(dy, 6) == 0 and dy >= -6:
				b = TORCH
	if t.main and dy >= -13 and dy <= -9 and absi(dx) <= 5 and absi(dz) <= 3:   # sala do tesouro
		b = AIR
		if dy == -13 and dx == -4 and dz == 2:
			b = LIVING_LOOM
		elif dy == -13 and dx == -4 and dz == -2:
			b = CHAIR
		elif dy == -13 and dx == 4 and dz == 0:
			b = CHEST
		elif dy == -11 and absi(dx) == 5 and absi(dz) == 2:
			b = TORCH
		elif cheb == 2 and LIVING_RING[posmod(dy + 13, 16)] == Vector2i(dx, dz):
			b = LIVING_WOOD
	if dy < 15:
		return b
	var p := Vector2(dx, dz)
	for br in t.branches:
		var along: float = clampf(p.dot(br.dir), 0.0, br.len)
		if b == -1 and absi(dy - br.dy) <= 1 and (p - br.dir * along).length() <= 1.2:
			b = LIVING_WOOD
		var e: Vector2 = br.dir * (br.len + 2)   # folhas na ponta do galho
		var lq: float = (p - e).length_squared() / 25.0 + (dy - br.dy - 1) * (dy - br.dy - 1) / 16.0
		if b == -1 and lq <= 1.0 and (lq < 0.55 or _hash01(dx, dy, dz, seed) > 0.25):
			b = LEAVES
	var q := r2 / 144.0 + (dy - LIVING_H + 2) * (dy - LIVING_H + 2) / 64.0   # copa: elipsoide 12 x 8
	if b == -1 and q <= 1.0 and (q < 0.55 or _hash01(dx, dy, dz, seed + 1) > 0.25):
		b = LEAVES
	return b


func _dungeon_block(wx: int, y: int, wz: int) -> int:
	var ax := wx - dungeon_x
	var az := wz - dungeon_z
	var ay := y - DUNGEON_Y
	var lx := ax % DUNGEON_CELL
	var lz := az % DUNGEON_CELL
	var ly := ay % DUNGEON_CELL
	var cell_x := ax / DUNGEON_CELL
	var cell_z := az / DUNGEON_CELL
	var floor_n := ay / DUNGEON_CELL
	if ay == DUNGEON_FLOORS * DUNGEON_CELL:   # teto: só o poço de entrada fura
		var e := dungeon_entrance
		return AIR if absi(wx - e.x) <= 1 and absi(wz - e.z) <= 1 else BRICK
	if ly == 0:   # laje entre andares e chão do 1º: um buraco por andar (e o poço de entrada)
		var hole_x: int = hash([seed, "hx", floor_n]) % DUNGEON_W
		var hole_z: int = hash([seed, "hz", floor_n]) % DUNGEON_D
		var e := dungeon_entrance
		var through := (cell_x == hole_x and cell_z == hole_z) or (absi(wx - e.x) <= 1 and absi(wz - e.z) <= 1)
		return AIR if floor_n > 0 and through and lx >= 3 and lx <= 6 and lz >= 3 and lz <= 6 else BRICK
	if lx == 0:   # parede entre salas vizinhas em x: sempre tem porta (no meio), menos na borda do dungeon
		return AIR if ax != 0 and ax != DUNGEON_W * DUNGEON_CELL and lz >= 3 and lz <= 6 and ly <= 3 else BRICK
	if lz == 0:   # parede em z: porta numa coluna de salas escolhida por fileira (mais algumas ao acaso)
		var col: int = hash([seed, "dz", cell_z, floor_n]) % DUNGEON_W
		var open := cell_x == col or _hash01(cell_x, cell_z, floor_n, seed) < 0.3
		return AIR if az != 0 and az != DUNGEON_D * DUNGEON_CELL and open and lx >= 3 and lx <= 6 and ly <= 3 else BRICK
	var h := _hash01(cell_x, cell_z, floor_n, seed + 7)
	if ly == 1 and lx == 1 and lz == 1 and h < 0.3:
		return CHEST
	if ly == 3 and lx == 5 and lz == 1 and h > 0.4:
		return TORCH
	return AIR


# Corrupção/Carmesim: grama e pedra do bioma trocadas, mais os abismos estreitos com um orbe no fundo.
func _evil(d: PackedByteArray, hs: PackedInt32Array, W: int, cx: int, cz: int) -> void:
	var ox := cx * CHUNK
	var oz := cz * CHUNK
	if not _near_ring(ox, oz, 0.45, 0.92):
		return
	var layer := CHUNK * CHUNK
	for z in CHUNK:
		for x in CHUNK:
			if evil_weight(ox + x, oz + z) < 0.5:
				continue
			var h := hs[(x + MARGIN) + (z + MARGIN) * W]
			var i := x + z * CHUNK
			if d[i + h * layer] == GRASS:
				d[i + h * layer] = EVIL_GRASS
			for y in range(UNDERWORLD_TOP + 8, h + 1):
				if d[i + y * layer] == STONE:
					d[i + y * layer] = EVIL_STONE
	for k in chasm_centers.size():
		var c := chasm_centers[k]
		if absi(c.x - (ox + CHUNK / 2)) > CHUNK / 2 + 4 or absi(c.y - (oz + CHUNK / 2)) > CHUNK / 2 + 4:
			continue
		var top := chasm_heights[k]
		var bottom := maxi(top - CHASM_DEPTH, UNDERWORLD_TOP + 6)
		for y in range(bottom, top + 2):
			var r := 2.6 - 0.9 * float(top - y) / CHASM_DEPTH + rock_noise.get_noise_2d(c.x * 3 + y * 5, c.y) * 0.9   # afunila e serpenteia
			r = maxf(r, 1.6)
			var off := _chasm_off(c, y)
			for dz in range(-5, 6):
				for dx in range(-5, 6):
					var lx: int = c.x + dx - ox
					var lz: int = c.y + dz - oz
					if lx < 0 or lx >= CHUNK or lz < 0 or lz >= CHUNK:
						continue
					var q := Vector2(dx, dz).distance_to(off)
					var i := lx + lz * CHUNK + y * layer
					if q <= r and y > bottom:
						if d[i] != WATER and d[i] != LAVA:
							d[i] = AIR
					elif q <= r + 1.4 and d[i] != AIR and d[i] != WATER and d[i] != LAVA and y <= top:
						d[i] = EVIL_STONE   # parede do abismo
		var o := chasm_orb(k)   # o orbe fica no chão do abismo, no eixo dele
		var lx := o.x - ox
		var lz := o.z - oz
		if lx >= 0 and lx < CHUNK and lz >= 0 and lz < CHUNK:
			var i := lx + lz * CHUNK + o.y * layer
			d[i - layer] = EVIL_STONE
			d[i] = ORB
			d[i + layer] = AIR   # o espaço em cima do orbe não fica alagado
			d[i + 2 * layer] = AIR


# O eixo do abismo serpenteia devagar com a altura.
func _chasm_off(c: Vector2i, y: int) -> Vector2:
	return Vector2(rock_noise.get_noise_2d(y * 1.5, c.x) * 3.0, rock_noise.get_noise_2d(y * 1.5, c.y + 99) * 3.0)


# Posição do orbe do abismo k (bloco dele, no chão): o eixo do abismo balança com a altura, como em _evil.
func chasm_orb(k: int) -> Vector3i:
	var c := chasm_centers[k]
	var y := maxi(chasm_heights[k] - CHASM_DEPTH, UNDERWORLD_TOP + 6) + 1
	var off := _chasm_off(c, y)
	return Vector3i(c.x + roundi(off.x), y, c.y + roundi(off.y))


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


# Baú de tesouro no chão, numa das camadas (superfície, subsolo, cavernas, perto do submundo); o conteúdo sai de World.chest_at (Loot) na
# primeira vez que abre.
func _chest(d: PackedByteArray, rng: RandomNumberGenerator) -> void:
	if rng.randf() > 0.3:
		return
	var band: Array = [[CAVERN_TOP + 1, SURFACE - 14], [UNDERWORLD_TOP + 12, CAVERN_TOP], [UNDERWORLD_TOP + 2, UNDERWORLD_TOP + 11], [SURFACE - 13, SURFACE + 8]][rng.randi() % 4]
	for attempt in 8:
		var x := rng.randi_range(1, CHUNK - 2)
		var z := rng.randi_range(1, CHUNK - 2)
		for y in range(band[1], band[0] - 1, -1):
			var i := x + z * CHUNK + y * CHUNK * CHUNK
			if d[i] == AIR and d[i + CHUNK * CHUNK] == AIR and (d[i - CHUNK * CHUNK] == STONE or d[i - CHUNK * CHUNK] == DIRT or d[i - CHUNK * CHUNK] == GRASS):
				d[i] = CHEST
				return


# Life Crystal no chão de uma caverna (~1 a cada 3 chunks), do subsolo às cavernas; nunca no submundo nem em cima (wiki Life Crystal).
func _crystal(d: PackedByteArray, rng: RandomNumberGenerator) -> void:
	if rng.randf() > 0.34:
		return
	for attempt in 8:
		var x := rng.randi_range(1, CHUNK - 2)
		var z := rng.randi_range(1, CHUNK - 2)
		for y in range(SURFACE - 14, UNDERWORLD_TOP + 2, -1):
			var i := x + z * CHUNK + y * CHUNK * CHUNK
			if d[i] == AIR and (d[i - CHUNK * CHUNK] == STONE or d[i - CHUNK * CHUNK] == DIRT):
				d[i] = CRYSTAL
				return


# Veios por passeio aleatório; só trocam os blocos de "in" (padrão: pedra e terra) e ficam dentro do chunk.
func _ores(d: PackedByteArray, rng: RandomNumberGenerator, list := ores) -> void:
	for o in list:
		for v in int(o.veins):
			var p := Vector3i(rng.randi() % CHUNK, rng.randi_range(o.min_y, o.max_y), rng.randi() % CHUNK)
			for s in int(o.size):
				var i := p.x + p.z * CHUNK + p.y * CHUNK * CHUNK
				if d[i] in o.in:
					d[i] = o.block
				p[rng.randi() % 3] += 1 if rng.randf() < 0.5 else -1
				p = p.clamp(Vector3i(0, o.min_y, 0), Vector3i(CHUNK - 1, o.max_y, CHUNK - 1))


# Capim, flores e cogumelos sobre a grama (só onde o ar está livre).
func _plants(d: PackedByteArray, hs: PackedInt32Array, W: int, rng: RandomNumberGenerator) -> void:
	for z in CHUNK:
		for x in CHUNK:
			var y := hs[(x + MARGIN) + (z + MARGIN) * W]
			var i := x + z * CHUNK + y * CHUNK * CHUNK
			var r := rng.randf()
			if d[i] != GRASS or d[i + CHUNK * CHUNK] != AIR or r > 0.34:
				continue
			d[i + CHUNK * CHUNK] = TUFT if r < 0.27 else MUSHROOM if r < 0.275 else FLOWERS[rng.randi() % FLOWERS.size()]


# Cactos (wiki Cactus): colunas de 3 a 5 blocos sobre a areia da superfície do deserto, com ar livre no topo; um por ~60 colunas.
func _cactus(d: PackedByteArray, hs: PackedInt32Array, W: int, cx: int, cz: int) -> void:
	var ox := cx * CHUNK
	var oz := cz * CHUNK
	if not _near_ring(ox, oz, 0.22, 0.5):
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed, cx, cz, "cactus"])
	var layer := CHUNK * CHUNK
	for z in CHUNK:
		for x in CHUNK:
			var r := rng.randf()
			var n := rng.randi_range(3, 5)
			if r > 0.016 or desert_weight(ox + x, oz + z) < 0.5 or evil_weight(ox + x, oz + z) >= 0.5 or snow_weight(ox + x, oz + z) >= 0.5:
				continue
			var i := x + z * CHUNK + hs[(x + MARGIN) + (z + MARGIN) * W] * layer
			if d[i] == SAND and range(1, n + 1).all(func(k): return d[i + k * layer] == AIR):
				for k in range(1, n + 1):
					d[i + k * layer] = CACTUS


# Árvores estilo Terraria: tronco alto e fino, raízes na base, galhos com tufos e a copa fofa no topo.
# Cada célula de uma grade TREE_CELL tem no máximo uma árvore, com tudo sorteado só por (seed, célula): os chunks
# vizinhos calculam a mesma árvore e cada um escreve a sua parte, então nada é cortado na borda.
func _trees(d: PackedByteArray, hs: PackedInt32Array, W: int, cx: int, cz: int) -> void:
	var ox := cx * CHUNK
	var oz := cz * CHUNK
	var reach := MARGIN - 1
	for gz in range(floori((oz - reach) / float(TREE_CELL)), floori((oz + CHUNK + reach) / float(TREE_CELL)) + 1):
		for gx in range(floori((ox - reach) / float(TREE_CELL)), floori((ox + CHUNK + reach) / float(TREE_CELL)) + 1):
			var h := absi(hash([seed, gx, gz]))
			var wx := gx * TREE_CELL + (h >> 8) % TREE_CELL
			var wz := gz * TREE_CELL + (h >> 16) % TREE_CELL
			var ix := wx - ox + MARGIN
			var iz := wz - oz + MARGIN
			if ix < 1 or iz < 1 or ix > W - 2 or iz > W - 2 or Vector2(wx, wz).distance_to(CENTER) < 26.0 or evil_weight(wx, wz) >= 0.5 or snow_weight(wx, wz) >= 0.5 or desert_weight(wx, wz) >= 0.5 or jungle_weight(wx, wz) >= 0.5 or living_trees.any(func(t): return Vector2(wx - t.x, wz - t.z).length() < LIVING_R + 3):
				continue
			var forest := clampf(0.3 + forest_noise.get_noise_2d(wx, wz) * 1.0, 0.0, 0.75)   # matas e clareiras
			var by := hs[ix + iz * W]
			if (h & 0xff) / 255.0 > forest or by > HEIGHT - 24 or _top(hs, ix + iz * W, W) != TOP_GRASS:
				continue
			tree(d, cx, cz, wx, wz, by, PackedInt32Array([hs[ix + 1 + iz * W], hs[ix - 1 + iz * W], hs[ix + (iz + 1) * W], hs[ix + (iz - 1) * W]]), h)


# Uma árvore com o tronco em (wx, wz) sobre o chão de altura `by`, escrita no chunk (cx, cz) (só o que cai nele e está livre). `side` = altura do chão
# ao lado nas direções de DIRS4 (raiz onde é igual a `by`). Tudo sai de `h`: a mesma semente dá a mesma árvore (a muda de world.gd usa isto também).
func tree(d: PackedByteArray, cx: int, cz: int, wx: int, wz: int, by: int, side: PackedInt32Array, h: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = h
	var th := rng.randi_range(8, 13)
	var rx := rng.randf_range(2.7, 3.5)
	var ry := rng.randf_range(2.0, 2.7)
	for k in range(1, th + 1):
		_put(d, cx, cz, wx, by + k, wz, WOOD, true)
	for i in 4:   # raízes
		if rng.randf() < 0.5 and side[i] == by:
			_put(d, cx, cz, wx + DIRS4[i].x, by + 1, wz + DIRS4[i].y, WOOD, true)
	for n in rng.randi_range(0, 2):   # galhos com um tufo de folhas na ponta
		var dir := DIRS4[rng.randi() % 4]
		var y := by + rng.randi_range(th / 2, th - 2)
		var len := rng.randi_range(1, 2)
		for k in range(1, len + 1):
			_put(d, cx, cz, wx + dir.x * k, y, wz + dir.y * k, WOOD, true)
		_blob(d, cx, cz, Vector3(wx + dir.x * (len + 1), y + 1, wz + dir.y * (len + 1)), 1.7, 1.3, h + n)
	_blob(d, cx, cz, Vector3(wx, by + th + 1, wz), rx, ry, h)
	_put(d, cx, cz, wx, by + th + 1, wz, WOOD, true)   # o tronco entra na copa


# Elipsoide de folhas (raios rx horizontal, ry vertical) com a borda esburacada por ruído.
func _blob(d: PackedByteArray, cx: int, cz: int, c: Vector3, rx: float, ry: float, salt: int) -> void:
	var r := int(ceil(rx))
	for dy in range(-int(ceil(ry)), int(ceil(ry)) + 1):
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var q := (dx * dx + dz * dz) / (rx * rx) + dy * dy / (ry * ry)
				if q <= 1.0 and (q < 0.55 or _hash01(salt, dx, dy, dz) > 0.25):
					_put(d, cx, cz, int(c.x) + dx, int(c.y) + dy, int(c.z) + dz, LEAVES)


static func _hash01(a: int, b: int, c: int, e: int) -> float:
	return float(((a * 73856093) ^ (b * 19349663) ^ (c * 83492791) ^ (e * 2654435761)) & 0xffff) / 65535.0


# Escreve um bloco se cair dentro deste chunk e a célula estiver livre (over: também troca folhas).
func _put(d: PackedByteArray, cx: int, cz: int, x: int, y: int, z: int, id: int, over := false) -> void:
	var lx := x - cx * CHUNK
	var lz := z - cz * CHUNK
	if lx < 0 or lx >= CHUNK or lz < 0 or lz >= CHUNK or y < 0 or y >= HEIGHT:
		return
	var i := lx + lz * CHUNK + y * CHUNK * CHUNK
	if d[i] == AIR or (over and d[i] == LEAVES):
		d[i] = id


# Escreve um bloco (sobrescrevendo o que houver) se cair dentro deste chunk.
func _write(d: PackedByteArray, cx: int, cz: int, x: int, y: int, z: int, id: int) -> void:
	var lx := x - cx * CHUNK
	var lz := z - cz * CHUNK
	if lx >= 0 and lx < CHUNK and lz >= 0 and lz < CHUNK and y >= 0 and y < HEIGHT:
		d[lx + lz * CHUNK + y * CHUNK * CHUNK] = id
