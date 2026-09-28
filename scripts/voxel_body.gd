class_name VoxelBody
# Colisão de caixa (AABB) contra os voxels, usada por jogador, inimigos e itens soltos.
# pos = centro da base da caixa; half = meia largura; tall = altura.

const EPS := 0.001


# Move eixo a eixo (Y, X, Z) e encosta no bloco quando bate.
# Retorna [nova posição, Vector3i com o sinal do movimento bloqueado em cada eixo (0 = livre)].
# ponytail: assume movimento < 1 bloco por eixo por passo (ok até 60 blocos/s a 60 Hz).
static func move(world, pos: Vector3, half: float, tall: float, motion: Vector3) -> Array:
	var hit := Vector3i.ZERO
	var lo := Vector3(-half, 0, -half)
	var hi := Vector3(half, tall, half)
	for a in [1, 0, 2]:
		if motion[a] == 0.0:
			continue
		pos[a] += motion[a]
		if overlaps(world, pos, half, tall):
			if motion[a] > 0:
				pos[a] = floorf(pos[a] + hi[a]) - hi[a] - EPS
			else:
				pos[a] = floorf(pos[a] + lo[a]) + 1 - lo[a] + EPS
			hit[a] = 1 if motion[a] > 0 else -1
	return [pos, hit]


static func overlaps(world, pos: Vector3, half: float, tall: float) -> bool:
	var lo := Vector3i((pos + Vector3(-half, 0, -half)).floor())
	var hi := Vector3i((pos + Vector3(half, tall, half) - Vector3.ONE * EPS).floor())
	for y in range(lo.y, hi.y + 1):
		for z in range(lo.z, hi.z + 1):
			for x in range(lo.x, hi.x + 1):
				if Blocks.solid[world.get_block(x, y, z)]:
					return true
	return false


# Caixas se tocam? (a e b = centro da base)
static func touches(a: Vector3, a_half: float, a_tall: float, b: Vector3, b_half: float, b_tall: float) -> bool:
	return absf(a.x - b.x) < a_half + b_half and absf(a.z - b.z) < a_half + b_half \
		and a.y < b.y + b_tall and b.y < a.y + a_tall
