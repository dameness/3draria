class_name Timber
# Árvores (wiki Tree / Axe power). O tronco é `wood` com folhas em volta (mesmo bloco da madeira colocada, então funciona nos mundos antigos).
# Cada tile de árvore tem 100 de vida e leva ⌊poder do machado × 24%⌋ por golpe; quebrado o tile, cai ele e tudo o que está acima
# (galhos e copa); a base derruba a árvore inteira, raízes incluídas, e cortar no meio deixa o toco. A madeira é 1 por tile, com chance
# (2·poder + 175)/525 de virar 2; acorn ~1/2 por tufo de folhas (a wiki não dá o número).

const HIT := 0.24         # dano por golpe = ⌊poder × HIT⌋ contra os 100 de vida do tile
const REACH := 8          # folhas a até tantos passos de folha da madeira derrubada entram na conta
const HOLD := 4           # ...e ficam se houver outra madeira de pé a até tantos passos (copa de outra árvore)
const FALL_TIME := 1.2
const ACORN_CHANCE := 0.5
const N6: Array[Vector3i] = [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]


# Topo da coluna de madeira que começa em p.
static func run_top(world: Node3D, p: Vector3i) -> Vector3i:
	var top := p
	while world.get_block(top.x, top.y + 1, top.z) == Blocks.ids.wood:
		top.y += 1
	return top


# O bloco de madeira em p é de uma árvore (o topo da coluna dele encosta em folhas) e não madeira colocada.
static func is_tree(world: Node3D, p: Vector3i) -> bool:
	if world.get_block(p.x, p.y, p.z) != Blocks.ids.wood:
		return false
	var top := run_top(world, p)
	for n in N6:
		if world.get_block(top.x + n.x, top.y + n.y, top.z + n.z) == Blocks.ids.leaves:
			return true
	return false


# Blocos que caem quando o tronco em p é cortado: [madeira, folhas]. Madeira: a coluna de p para cima, os galhos e (se p é a base) as
# raízes; nunca outro tronco. Folhas: as ligadas a essa madeira que não ficam presas a outra madeira que continua de pé.
static func felled(world: Node3D, p: Vector3i) -> Array:
	var wood: int = Blocks.ids.wood
	var leaf: int = Blocks.ids.leaves
	var logs := {p: true}
	var todo := [p]
	while not todo.is_empty():
		var q: Vector3i = todo.pop_back()
		for n in N6:
			var r := q + n
			if r.y < p.y or logs.has(r) or world.get_block(r.x, r.y, r.z) != wood:
				continue
			# madeira empilhada fora da coluna de p é o tronco de outra árvore; galho e raiz não têm madeira em cima nem embaixo
			if (r.x != p.x or r.z != p.z) and (world.get_block(r.x, r.y + 1, r.z) == wood or world.get_block(r.x, r.y - 1, r.z) == wood):
				continue
			logs[r] = true
			todo.append(r)
	var near := {}   # folha -> passos de folha desde a madeira derrubada
	var queue := []
	for q in logs:
		for n in N6:
			var r: Vector3i = q + n
			if not near.has(r) and world.get_block(r.x, r.y, r.z) == leaf:
				near[r] = 1
				queue.append(r)
	var i := 0
	while i < queue.size():
		var q: Vector3i = queue[i]
		i += 1
		if near[q] >= REACH:
			continue
		for n in N6:
			var r: Vector3i = q + n
			if not near.has(r) and world.get_block(r.x, r.y, r.z) == leaf:
				near[r] = near[q] + 1
				queue.append(r)
	var held := {}   # folha -> passos até madeira que continua de pé
	var hq := []
	for q in near:
		for n in N6:
			var r: Vector3i = q + n
			if world.get_block(r.x, r.y, r.z) == wood and not logs.has(r):
				held[q] = 1
				hq.append(q)
				break
	i = 0
	while i < hq.size():
		var q: Vector3i = hq[i]
		i += 1
		if held[q] >= HOLD:
			continue
		for n in N6:
			var r: Vector3i = q + n
			if near.has(r) and not held.has(r):
				held[r] = held[q] + 1
				hq.append(r)
	return [logs.keys(), near.keys().filter(func(q): return not held.has(q))]


# Cada golpe sacode a copa: umas folhas caem do topo da árvore.
static func rustle(entities: Node3D, world: Node3D, p: Vector3i) -> void:
	var top := run_top(world, p)
	Fx.burst(entities, Vector3(top.x + 0.5, top.y + 1.0, top.z + 0.5), Blocks.color_of(Blocks.ids.leaves), 4, {"size": 0.12, "life": 1.1, "speed": 1.2, "spread": 180.0, "gravity": 2.0})


# Madeira de n tiles com um machado de poder `power`: 1 por tile, 2 com chance (2·poder + 175)/525 (média 1,47 com o de cobre).
static func yield_wood(n: int, power: int, rng: RandomNumberGenerator) -> int:
	var chance := minf((2.0 * power + 175.0) / 525.0, 1.0)
	var total := 0
	for i in n:
		total += 2 if rng.randf() < chance else 1
	return total


# Tufos de folhas: os pedaços ligados do conjunto.
static func patches(leaves: Array) -> int:
	var left := {}
	for q in leaves:
		left[q] = true
	var count := 0
	for q in leaves:
		if not left.erase(q):
			continue
		count += 1
		var todo := [q]
		while not todo.is_empty():
			var c: Vector3i = todo.pop_back()
			for n in N6:
				if left.erase(c + n):
					todo.append(c + n)
	return count


# Corta a árvore em p: tira os blocos do mundo, faz o pedaço tombar para longe de `from` e, quando ele bate no chão, solta a madeira e os
# acorns. Fora da árvore de cena (testes) não há animação: solta na hora. Retorna {logs, leaves, wood, acorns, patches}.
static func fell(entities: Node3D, p: Vector3i, axe_power: int, from: Vector3, rng := RandomNumberGenerator.new()) -> Dictionary:
	var world: Node3D = entities.world
	var cut := felled(world, p)
	var logs: Array = cut[0]
	var leaves: Array = cut[1]
	var body := _body(entities, p, logs, leaves)
	for q in logs + leaves:
		world.set_block(q.x, q.y, q.z, 0)
	var wood := yield_wood(logs.size(), axe_power, rng)
	var tufts := patches(leaves)
	var acorns := 0
	for i in tufts:
		acorns += 1 if rng.randf() < ACORN_CHANCE else 0
	var top := p
	for q in logs:
		top.y = maxi(top.y, q.y)
	var away := Vector3(p.x + 0.5 - from.x, 0, p.z + 0.5 - from.z)
	away = away.normalized() if away.length() > 0.1 else Vector3.FORWARD
	var base := Vector3(p.x + 0.5, p.y, p.z + 0.5)
	var land := base + away * maxf(top.y - p.y, 2.0) * 0.6
	var finish := func():
		var ground: float = world.surface_y(floori(land.x), floori(land.z), true)
		var at := Vector3(land.x, maxf(ground, base.y) + 0.4, land.z)
		if wood > 0:
			entities.spawn_drop(Items.ids.wood, wood, at)
		if acorns > 0:
			entities.spawn_drop(Items.ids.acorn, acorns, at + Vector3(0.3, 0.2, 0.0))
		if body:
			var leaf := Blocks.color_of(Blocks.ids.leaves)
			Fx.chips(entities, at, leaf, 24)
			Fx.dust(entities, at, Color("#8a6a48"), 10)
			Sfx.play(entities, "break", at, -3.0, 0.7)
			if entities.player.position.distance_to(at) < 25.0:
				entities.player.shake = maxf(entities.player.shake, 0.5)
			body.queue_free()
	if body == null or not entities.is_inside_tree():
		finish.call()
	else:
		Fx.burst(entities, Vector3(top.x + 0.5, top.y + 1.0, top.z + 0.5), Blocks.color_of(Blocks.ids.leaves), 30, {"size": 0.14, "life": 1.3, "speed": 2.0, "spread": 180.0, "gravity": 2.5})
		Sfx.play(entities, "break", base + Vector3.UP, -3.0, 0.8)
		var axis := Vector3.UP.cross(away).normalized()
		var tw := body.create_tween()
		tw.tween_method(func(a: float): body.basis = Basis(axis, a), 0.0, PI / 2.0, FALL_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_callback(finish)
	return {"logs": logs.size(), "leaves": leaves.size(), "wood": wood, "acorns": acorns, "patches": tufts}


# O pedaço que cai: uma malha só (a mesma luz e textura do mundo), pivô na base do bloco cortado. null se não há árvore de cena para mostrá-lo.
static func _body(entities: Node3D, p: Vector3i, logs: Array, leaves: Array) -> Node3D:
	if not entities.is_inside_tree():
		return null
	var c := WorldGen.CHUNK
	var d := PackedByteArray()
	d.resize(c * c * WorldGen.HEIGHT)
	for pair in [[logs, Blocks.ids.wood], [leaves, Blocks.ids.leaves]]:
		for q in pair[0]:
			d[(q.x - p.x + 8) + (q.z - p.z + 8) * c + (q.y - p.y + 2) * c * c] = pair[1]   # a árvore cabe num chunk vazio, com o bloco cortado em (8, 2, 8)
	var E := PackedByteArray()
	var arrays := ChunkMesher.build(d, [E, E, E, E], Blocks.textures.size())
	if arrays.is_empty():
		return null
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, entities.world.material)
	var pivot := Node3D.new()
	pivot.position = Vector3(p.x + 0.5, p.y, p.z + 0.5)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = -Vector3(8.5, 2.0, 8.5)
	pivot.add_child(mi)
	entities.add_child(pivot)
	return pivot
