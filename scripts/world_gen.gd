class_name WorldGen
extends RefCounted
# Gera os blocos de um chunk por ruído em camadas: superfície (colinas, serras, lagos, praias, árvores, plantas),
# subterrâneo, cavernas (com poças de água e lava) e submundo (mar de lava).
# Mudar qualquer regra daqui muda o mundo de uma seed: mundos salvos antes ficam com emendas (crie outro).

const CHUNK := 16
const HEIGHT := 128
const SIZE_CHUNKS := 16        # mundo finito: 16x16 chunks = 256x256 blocos
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
const EVIL_RADIUS := 30.0      # raio do bioma do mal
const DUNGEON_CELL := 10       # dungeon: grade de salas de 10 blocos (parede incluída), 6 x 5 salas em 2 andares
const DUNGEON_W := 6
const DUNGEON_D := 5
const DUNGEON_Y := 30          # chão do 1º andar
const DUNGEON_FLOORS := 2
const CHASMS := 6              # abismos por bioma, cada um com um orbe (Shadow Orb / Crimson Heart) no fundo
const CHASM_DEPTH := 38
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
var SAND: int
var WATER: int
var LAVA: int
var TUFT: int
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
var hardmode := false             # Wall of Flesh derrotado: minérios novos e o Hallow entram na geração (world.start_hardmode converte o que já existe)
var hm_ores: Array = []           # ores.json com "hardmode": true (um por grupo, escolhido pela seed)
var hallow_center := Vector2.ZERO
var HALLOW_GRASS: int
var PEARLSTONE: int
var BRICK: int
var TORCH: int
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
	SAND = Blocks.ids.sand
	WATER = Blocks.ids.water
	LAVA = Blocks.ids.lava
	TUFT = Blocks.ids.grass_tuft
	FLOWERS = [Blocks.ids.flower_yellow, Blocks.ids.flower_red, Blocks.ids.flower_pink]
	MUSHROOM = Blocks.ids.mushroom
	var er := RandomNumberGenerator.new()   # bioma do mal: tipo, posição e abismos só dependem da seed
	er.seed = hash([seed, "evil"])
	evil = "corruption" if er.randi() % 2 == 0 else "crimson"
	evil_center = CENTER + Vector2.from_angle(er.randf() * TAU) * er.randf_range(62.0, 80.0)
	EVIL_STONE = Blocks.ids.ebonstone if evil == "corruption" else Blocks.ids.crimstone
	EVIL_GRASS = Blocks.ids.corrupt_grass if evil == "corruption" else Blocks.ids.crimson_grass
	ORB = Blocks.ids.shadow_orb if evil == "corruption" else Blocks.ids.crimson_heart
	for k in CHASMS:
		var c := evil_center + Vector2.from_angle(TAU * k / CHASMS + er.randf_range(-0.15, 0.15)) * er.randf_range(13.0, 19.0)
		chasm_centers.append(Vector2i(c))
		chasm_heights.append(surface_height(int(c.x), int(c.y)))
	HALLOW_GRASS = Blocks.ids.hallowed_grass
	PEARLSTONE = Blocks.ids.pearlstone
	hallow_center = CENTER + Vector2(0, -72.0 if evil_center.y > CENTER.y else 72.0)   # entre o mal e o dungeon, nunca em cima de um
	BRICK = Blocks.ids.dungeon_brick
	TORCH = Blocks.ids.torch
	dungeon_x = 6 if evil_center.x > CENTER.x else SIZE_CHUNKS * CHUNK - 6 - DUNGEON_W * DUNGEON_CELL - 1
	dungeon_z = int(CENTER.y) - DUNGEON_D * DUNGEON_CELL / 2
	var ex := dungeon_x + DUNGEON_W / 2 * DUNGEON_CELL + DUNGEON_CELL / 2
	var ez := dungeon_z + DUNGEON_D / 2 * DUNGEON_CELL + DUNGEON_CELL / 2
	dungeon_entrance = Vector3i(ex, surface_height(ex, ez), ez)
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
# saliências de rocha do Terraria; o meio do mundo é uma planície para o nascimento.
func surface_height(wx: int, wz: int) -> int:
	var hills := height_noise.get_noise_2d(wx, wz)
	var ridge := 1.0 - absf(ridge_noise.get_noise_2d(wx, wz))
	var mount := clampf(mount_noise.get_noise_2d(wx, wz) * 2.5 - 0.3, 0.0, 1.0)
	var h := SURFACE + hills * 16.0 + mount * ridge * ridge * 40.0
	var q := h / 5.0
	h = lerpf(h, (floorf(q) + smoothstep(0.55, 1.0, q - floorf(q))) * 5.0, 0.38)
	var flat := 1.0 - smoothstep(16.0, 46.0, Vector2(wx, wz).distance_to(CENTER))
	h = lerpf(h, SURFACE + 2.0 + hills * 2.0, flat)
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
	_dungeon(d, cx, cz)
	_ores(d, rng)
	_trees(d, hs, W, cx, cz)
	_plants(d, hs, W, rng)
	rng.seed = hash([seed, cx, cz, "altar"])
	_altar(d, rng)
	rng.seed = hash([seed, cx, cz, "chest"])
	_chest(d, rng)
	if hardmode:
		hardmode_pass(d, cx, cz)
	return d


func hallow_weight(wx: int, wz: int) -> float:
	var dist := Vector2(wx, wz).distance_to(hallow_center)
	if dist > EVIL_RADIUS + 8.0:
		return 0.0
	return clampf((EVIL_RADIUS - dist + rock_noise.get_noise_2d(wx + 500, wz) * 8.0) / 4.0, 0.0, 1.0)


# Hardmode: veios de cobalto/paládio na pedra e o Hallow (grama e pedra) num disco do outro lado do mundo. Determinístico por chunk:
# vale tanto na geração quanto para converter (world.start_hardmode) o que já estava gerado.
func hardmode_pass(d: PackedByteArray, cx: int, cz: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed, cx, cz, "hardmode"])
	_ores(d, rng, hm_ores)
	var ox := cx * CHUNK
	var oz := cz * CHUNK
	if Vector2(ox + CHUNK / 2.0, oz + CHUNK / 2.0).distance_to(hallow_center) > EVIL_RADIUS + 8.0 + CHUNK:
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


# Quanto do bioma do mal cobre a coluna (0 a 1): disco com a borda irregular por ruído.
func evil_weight(wx: int, wz: int) -> float:
	var d := Vector2(wx, wz).distance_to(evil_center)
	if d > EVIL_RADIUS + 8.0:
		return 0.0
	return clampf((EVIL_RADIUS - d + rock_noise.get_noise_2d(wx, wz) * 8.0) / 4.0, 0.0, 1.0)


# Corrupção/Carmesim: grama e pedra do bioma trocadas, mais os abismos estreitos com um orbe no fundo.
func _evil(d: PackedByteArray, hs: PackedInt32Array, W: int, cx: int, cz: int) -> void:
	var ox := cx * CHUNK
	var oz := cz * CHUNK
	if Vector2(ox + CHUNK / 2.0, oz + CHUNK / 2.0).distance_to(evil_center) > EVIL_RADIUS + 8.0 + CHUNK:
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


# Baú de tesouro no chão de uma caverna (o conteúdo sai de World.chest_at na primeira vez que abre).
func _chest(d: PackedByteArray, rng: RandomNumberGenerator) -> void:
	if rng.randf() > 0.3:
		return
	for attempt in 8:
		var x := rng.randi_range(1, CHUNK - 2)
		var z := rng.randi_range(1, CHUNK - 2)
		for y in range(CAVERN_TOP, UNDERWORLD_TOP + 1, -1):
			var i := x + z * CHUNK + y * CHUNK * CHUNK
			if d[i] == AIR and d[i + CHUNK * CHUNK] == AIR and d[i - CHUNK * CHUNK] == STONE:
				d[i] = CHEST
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
			if ix < 1 or iz < 1 or ix > W - 2 or iz > W - 2 or Vector2(wx, wz).distance_to(CENTER) < 26.0 or evil_weight(wx, wz) >= 0.5:
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
