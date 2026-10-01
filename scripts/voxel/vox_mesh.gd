class_name VoxMesh
# Mesher genérico dos modelos voxel: só as faces expostas (as internas somem), cor por vértice (sem textura) e oclusão ambiente
# por canto, como o mesher dos chunks. Cor do vértice = cor do voxel × AO; alfa 0 = voxel emissivo (brilha e pulsa no shader).
# Retorna o ArrayMesh com a origem no pivô (o voxel de encaixe, senão o centro da base) e, em meta "glow", os topos emissivos
# (posições em blocos, relativas ao pivô) de onde saem as fagulhas.
# Não usa textura nem o atlas: funciona igual para item na mão, armadura, bloco com modelo e (nas próximas levas) inimigo.

const V := 0.0375        # 1 voxel em blocos: 1 tile do Terraria (16 px) = 0.6 bloco
const FP_V := 0.02        # 1 voxel do braço em 1ª pessoa, em blocos (o item na mão é ~0,012)
const AO_LIGHT := [0.6, 0.75, 0.88, 1.0]
const DIRS := ChunkMesher.DIRS
const CORNERS := ChunkMesher.CORNERS

static var _mats := {}


# item = true: o modelo é visto de +Z (sprite de frente, como o ItemModel), com x para a direita; senão a frente (y pequeno) olha
# para -Z, como o personagem. `origin` (em voxels, coordenadas contínuas) troca o pivô.
static func build(m: VoxModel, vs := V, item := false, origin := Vector3.INF) -> ArrayMesh:
	var s := 1 if item else -1
	var cells := {}   # célula do Godot -> cor (+ 1 << 24 se emissiva)
	var lo := Vector3(1e9, 1e9, 1e9)
	var hi := Vector3(-1e9, -1e9, -1e9)
	for p in m.v:
		if m.has_anchor and p == m.anchor:
			continue   # o encaixe é um ponto, não um voxel (o .vox o grava no lugar do que houvesse ali)
		var g := Vector3i(p.x if item else -p.x - 1, p.z, -p.y - 1 if item else p.y)
		cells[g] = m.v[p] | (1 << 24 if m.emit.has(m.v[p]) else 0)
		lo = lo.min(Vector3(p))
		hi = hi.max(Vector3(p) + Vector3.ONE)
	var o := origin
	if o == Vector3.INF:
		o = Vector3(m.anchor) + Vector3(0.5, 0.5, 0.5) if m.has_anchor else Vector3((lo.x + hi.x) / 2, (lo.y + hi.y) / 2, lo.z)
	var og := Vector3(s * o.x, o.z, -s * o.y)
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	var glow := PackedVector3Array()
	var ao := PackedInt32Array([0, 0, 0, 0])
	for key in cells:
		var g: Vector3i = key
		var cv: int = cells[g]
		var emissive := cv >> 24 == 1
		var c := VoxModel.color(cv & 0xffffff)
		if emissive:
			c.a = 0.0
			if not cells.has(g + Vector3i.UP):
				glow.append((Vector3(g) + Vector3(0.5, 0.5, 0.5) - og) * vs)
		for f in 6:
			var dir: Vector3i = DIRS[f]
			if cells.has(g + dir):
				continue
			var n: Vector3i = g + dir
			var axes := []
			for a in 3:
				if dir[a] == 0:
					axes.append(a)
			for k in 4:
				var corner: Vector3 = CORNERS[f][k]
				var s1 := Vector3i.ZERO
				var s2 := Vector3i.ZERO
				s1[axes[0]] = int(corner[axes[0]] * 2 - 1)
				s2[axes[1]] = int(corner[axes[1]] * 2 - 1)
				var o1 := 1 if cells.has(n + s1) else 0
				var o2 := 1 if cells.has(n + s2) else 0
				ao[k] = 0 if o1 + o2 == 2 else 3 - (o1 + o2 + (1 if cells.has(n + s1 + s2) else 0))
			var base := verts.size()
			for k in 4:
				verts.append((Vector3(g) + CORNERS[f][k] - og) * vs)
				norms.append(Vector3(dir))
				var l: float = 1.0 if emissive else AO_LIGHT[ao[k]]
				cols.append(Color(c.r * l, c.g * l, c.b * l, c.a))
			if ao[0] + ao[2] <= ao[1] + ao[3]:   # a diagonal liga os cantos mais escuros
				idx.append_array([base, base + 2, base + 1, base, base + 3, base + 2])
			else:
				idx.append_array([base, base + 3, base + 1, base + 1, base + 3, base + 2])
	var mesh := ArrayMesh.new()
	if not verts.is_empty():
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = norms
		arrays[Mesh.ARRAY_COLOR] = cols
		arrays[Mesh.ARRAY_INDEX] = idx
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.set_meta("glow", glow)
	return mesh


# Material único por luz mínima (`ambient`: quanto do modelo aparece na sombra). Quem precisa de luz própria (bloco no mundo)
# duplica e muda `world_light`.
static func material(ambient := 0.35) -> ShaderMaterial:
	if not _mats.has(ambient):
		var m := ShaderMaterial.new()
		m.shader = load("res://shaders/voxel.gdshader")
		m.set_shader_parameter("ambient", ambient)
		_mats[ambient] = m
	return _mats[ambient]
