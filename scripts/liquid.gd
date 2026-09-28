class_name Liquid
extends RefCounted
# Fluxo de água e lava. Cada bloco de líquido tem um nível de 1 a 8 (ids water_1..water_7 e water = cheio; o mesmo na lava).
# Uma geração processa os blocos acordados, de baixo para cima: o líquido cai para o bloco de baixo se ele tiver espaço e o que
# sobrar é repartido com os vizinhos laterais mais baixos (uma unidade por vez, para o mais baixo) até a diferença ficar em 1.
# O volume se conserva (nada nasce nem some), como no Terraria: um lago esvazia devagar para a cova que se abre nele.
# Só reage a edições: o mundo recém-gerado fica parado; cada mudança acorda o bloco e os seus 6 vizinhos.
# Lava encostada em água vira obsidiana (bloco cheio) ou pedra (lava rasa), como no Terraria.
# ponytail: sem pressão (nada sobe por canos em U além do que o cair e o espalhar já fazem).

const C := WorldGen.CHUNK
const H := WorldGen.HEIGHT
const PERIOD := 0.1       # segundos por geração
const LAVA_EVERY := 4     # a lava anda uma geração a cada 4 (mais viscosa)
const BUDGET := 400       # blocos processados por quadro (uma geração grande se espalha por vários quadros)
const SIDES: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
const AROUND: Array[Vector3i] = [Vector3i(0, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]

var cur := PackedInt64Array()   # geração em andamento (chaves x | z << 20 | y << 40: ordenar dá y crescente)
var at := 0                     # próximo índice de cur
var nxt := PackedInt64Array()   # acordados durante a geração; viram a próxima
var queued := {}                # chaves já em nxt
var clock := 0.0
var generation := 0


# Acorda o bloco e os vizinhos (chamado a cada edição do mundo e a cada mudança do próprio fluxo).
func wake(x: int, y: int, z: int) -> void:
	for o in AROUND:
		var wx := x + o.x
		var wy := y + o.y
		var wz := z + o.z
		if wx >= 0 and wy >= 0 and wz >= 0:
			var k := wx | (wz << 20) | (wy << 40)
			if not queued.has(k):
				queued[k] = true
				nxt.append(k)


func is_idle() -> bool:
	return at >= cur.size() and nxt.is_empty()


# Chamado todo quadro pelo mundo: uma geração a cada PERIOD, em fatias de BUDGET blocos.
func step(world: Node, delta: float) -> void:
	if at >= cur.size():
		if nxt.is_empty():
			return
		clock += delta
		if clock < PERIOD:
			return
		clock = 0.0
		_next_generation()
	var end := mini(at + BUDGET, cur.size())
	while at < end:
		_cell(world, cur[at])
		at += 1


# Roda até assentar (testes). Retorna quantas gerações levou.
func settle(world: Node, max_generations := 400) -> int:
	var n := 0
	while not is_idle() and n < max_generations:
		if at >= cur.size():
			_next_generation()
		while at < cur.size():
			_cell(world, cur[at])
			at += 1
		n += 1
	return n


func _next_generation() -> void:
	cur = nxt
	nxt = PackedInt64Array()
	queued.clear()
	cur.sort()
	at = 0
	generation += 1


# -1 = fora do mundo ou chunk ainda não gerado: conta como parede (o fluxo nunca força a geração de um chunk).
static func _at(chunks: Dictionary, x: int, y: int, z: int) -> int:
	if y < 0 or y >= H:
		return -1
	var c = chunks.get(Vector2i(x >> 4, z >> 4))
	return -1 if c == null else c[(x & 15) + (z & 15) * C + y * C * C]


# Quanto do líquido `kind` cabe no bloco n: ar e plantas recebem tudo (a planta é levada), o mesmo líquido só o que falta.
static func _room(n: int, kind: int) -> int:
	if n < 0:
		return 0
	if n == 0 or (Blocks.soft[n] and not Blocks.liquid[n]):
		return 8
	if Blocks.liquid[n] and Blocks.liquid_kind[n] == kind:
		return 8 - Blocks.liquid_level[n]
	return 0


func _put(world: Node, x: int, y: int, z: int, kind: int, level: int) -> void:
	world.set_block(x, y, z, Blocks.level_ids[kind][level], false)   # nível 0 = ar
	wake(x, y, z)


func _cell(world: Node, k: int) -> void:
	var x := k & 0xFFFFF
	var z := (k >> 20) & 0xFFFFF
	var y := k >> 40
	var chunks: Dictionary = world.chunks
	var b := _at(chunks, x, y, z)
	if b <= 0 or not Blocks.liquid[b]:
		return
	var kind: int = Blocks.liquid_kind[b]
	if kind == Blocks.ids.lava:   # reage na hora, sem esperar a vez lenta da lava
		var lv8: int = Blocks.liquid_level[b]
		for o in AROUND:
			var nb := _at(chunks, x + o.x, y + o.y, z + o.z)
			if nb > 0 and Blocks.liquid[nb] and Blocks.liquid_kind[nb] == Blocks.ids.water:
				world.set_block(x, y, z, Blocks.ids.obsidian if lv8 == 8 else Blocks.ids.stone, false)
				wake(x, y, z)
				return
	if kind == Blocks.ids.lava and generation % LAVA_EVERY != 0:
		if not queued.has(k):   # a lava espera a sua vez
			queued[k] = true
			nxt.append(k)
		return
	var level: int = Blocks.liquid_level[b]
	var room := _room(_at(chunks, x, y - 1, z), kind)
	if room > 0:   # cai para o bloco de baixo, o quanto couber
		var m := mini(level, room)
		_put(world, x, y - 1, z, kind, 8 - room + m)
		level -= m
		_put(world, x, y, z, kind, level)
		if level == 0:
			return
	var lv := PackedInt32Array([-1, -1, -1, -1])   # nível de cada vizinho lateral que aceita líquido (-1 = fechado)
	var open := false
	for i in 4:
		var r := _room(_at(chunks, x + SIDES[i].x, y, z + SIDES[i].y), kind)
		if r > 0:
			lv[i] = 8 - r
			open = true
	if not open:
		return
	var gave := PackedInt32Array([0, 0, 0, 0])
	var start := (x + z + generation) & 3   # o desempate gira, senão o líquido escorre sempre para o mesmo lado
	var moved := false
	while level >= 2:
		var best := -1
		for j in 4:
			var i := (start + j) & 3
			if lv[i] >= 0 and lv[i] <= level - 2 and (best < 0 or lv[i] < lv[best]):
				best = i
		if best < 0:
			break
		lv[best] += 1
		gave[best] += 1
		level -= 1
		moved = true
	if moved:
		for i in 4:
			if gave[i] > 0:
				_put(world, x + SIDES[i].x, y, z + SIDES[i].y, kind, lv[i])
		_put(world, x, y, z, kind, level)
