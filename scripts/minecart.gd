class_name Minecart
# Carrinho de mina (wiki Minecarts / Minecart Track): anda pelos blocos minecart_track, de um bloco ao vizinho do mesmo nível ou um acima/abaixo
# (rampa). Sem tecla o carrinho mantém a velocidade; W acelera, S freia e, parado, inverte. No fim da linha (ou com teto sólido no caminho) ele para.
# Velocidades da wiki em tiles/s ÷ 1,67 (1 bloco = 1,67 tile): carrinho de madeira 37,5 / 6,75 por s², os outros (aqui: carregar o item Minecart) 48,75 / 9.

const WOOD_SPEED := 22.5
const WOOD_ACCEL := 4.05
const FAST_SPEED := 29.25
const FAST_ACCEL := 5.4
const RAIL := 0.05    # altura do trilho sobre o chão do bloco (chunk_mesher._track_quad)
const SEAT := -0.3    # o jogador vai sentado: o corpo afunda no carrinho (as pernas vão esticadas para a frente, ver player_model.gd)

var world: Node3D
var from: Vector3i
var to: Vector3i
var t := 0.0               # 0..1 de from até to
var dir := Vector3i.RIGHT  # direção horizontal do movimento
var speed := 0.0
var fast := false
var reversing := false     # S segurado depois de parar: acelera para trás
var spin := 0.0            # giro das rodas (rad)


static func is_track(w: Node3D, c: Vector3i) -> bool:
	return w.get_block(c.x, c.y, c.z) == Blocks.ids.minecart_track


# Próximo trilho saindo de c na direção d: em frente (mesmo nível, depois um acima, um abaixo), senão curva para um lado e para o outro.
# Sem trilho, ou com bloco sólido na cabeça do carrinho, devolve o próprio c (fim da linha).
static func next_cell(w: Node3D, c: Vector3i, d: Vector3i) -> Vector3i:
	for side in [d, Vector3i(d.z, 0, -d.x), Vector3i(-d.z, 0, d.x)]:
		for dy in [0, 1, -1]:
			var n: Vector3i = c + side + Vector3i(0, dy, 0)
			if is_track(w, n) and not Blocks.solid[w.get_block(n.x, n.y + 1, n.z)]:
				return n
	return c


# Ponto do trilho no centro da célula c (a rampa fica a meia altura, como o desenho em chunk_mesher).
func node(c: Vector3i) -> Vector3:
	var h := 0.0
	for s in [Vector3i.RIGHT, Vector3i.LEFT, Vector3i.BACK, Vector3i.FORWARD]:
		if is_track(world, c + s + Vector3i.UP) and not is_track(world, c + s):
			h = 0.5
			break
	return Vector3(c) + Vector3(0.5, RAIL + h, 0.5)


func pos() -> Vector3:
	return node(from).lerp(node(to), t)


func valid() -> bool:
	return is_track(world, from) and is_track(world, to)


func top_speed() -> float:
	return FAST_SPEED if fast else WOOD_SPEED


# Dano e recuo do encontrão (wiki: 25 + 55 × v/vmax, o de madeira 15 + 30 ×; ×1,5 no Hardmode). O recuo da wiki (10 + 40 × v/vmax) vai ×0,3 nesta escala.
# ponytail: sem a versão Expert (×1,5 de novo) nem o Minecart Upgrade Kit.
func damage() -> int:
	var sp := speed / top_speed()
	return int(((25.0 + 55.0 * sp) if fast else (15.0 + 30.0 * sp)) * (1.5 if world.hardmode else 1.0))


func knockback() -> float:
	return (10.0 + 40.0 * speed / top_speed()) * 0.3


func start(at: Vector3i, facing: Vector3i) -> void:
	from = at
	to = next_cell(world, at, facing)
	if to == at:   # trilho isolado ou sem saída nesse sentido: tenta o contrário
		facing = -facing
		to = next_cell(world, at, facing)
	dir = hdir(from, to, facing)
	t = 0.0
	speed = 0.0


static func hdir(a: Vector3i, b: Vector3i, fallback: Vector3i) -> Vector3i:
	var v := Vector3i(signi(b.x - a.x), 0, signi(b.z - a.z))
	return v if v != Vector3i.ZERO else fallback


# Inverte o sentido (o carrinho para no fim e S inverte).
func reverse() -> void:
	var tmp := from
	from = to
	to = tmp
	t = 1.0 - t
	if from == to:   # parado num trilho sem saída: olha para o outro lado
		to = next_cell(world, from, -dir)
		t = 0.0
	dir = hdir(from, to, -dir)


# axis: +1 acelera (W), -1 freia e, parado, inverte (S), 0 mantém a velocidade.
func advance(delta: float, axis: float) -> void:
	var acc := FAST_ACCEL if fast else WOOD_ACCEL
	if axis < 0.0:
		if speed > 0.0 and not reversing:
			speed = maxf(speed - acc * 2.0 * delta, 0.0)
			if speed == 0.0:
				reversing = true
				reverse()
		else:
			if not reversing:   # já parado: a primeira pressão inverte
				reverse()
			reversing = true
			speed = minf(speed + acc * delta, top_speed())
	else:
		reversing = false
		if axis > 0.0:
			speed = minf(speed + acc * delta, top_speed())
	spin += speed * delta / 0.14
	var dist := speed * delta
	for i in 8:   # vários trilhos por quadro, se a velocidade pedir
		if dist <= 0.0 or from == to:
			break
		var run := node(from).distance_to(node(to))
		var left := (1.0 - t) * run
		if dist < left:
			t += dist / run
			break
		dist -= left
		var nxt := next_cell(world, to, dir)
		if nxt == to:   # fim da linha
			t = 1.0
			speed = 0.0
			break
		from = to
		to = nxt
		t = 0.0
		dir = hdir(from, to, dir)
	if from == to:
		speed = 0.0


# Modelo 3D do carrinho (comprimento no eixo x local): caixa de madeira, cantos de ferro e quatro rodas. Devolve a raiz e os pivôs das rodas.
static func build_model() -> Node3D:
	var root := Node3D.new()
	var wood := _mat(Color("#8a5a2c"))
	var iron := _mat(Color("#6b737d"))
	_box(root, Vector3(1.0, 0.07, 0.76), Vector3(0, 0.26, 0), iron)
	for s in [-1, 1]:
		_box(root, Vector3(1.0, 0.3, 0.06), Vector3(0, 0.4, s * 0.35), wood)
		_box(root, Vector3(0.06, 0.3, 0.76), Vector3(s * 0.47, 0.4, 0), wood)
		_box(root, Vector3(1.04, 0.05, 0.1), Vector3(0, 0.56, s * 0.35), iron)
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			var wheel := Node3D.new()
			wheel.name = "Wheel"
			wheel.position = Vector3(sx * 0.3, 0.14, sz * 0.41)
			var m := MeshInstance3D.new()
			var cyl := CylinderMesh.new()
			cyl.top_radius = 0.14
			cyl.bottom_radius = 0.14
			cyl.height = 0.06
			cyl.radial_segments = 10
			m.mesh = cyl
			m.material_override = iron
			m.rotation.x = PI / 2.0
			wheel.add_child(m)
			_box(wheel, Vector3(0.22, 0.04, 0.07), Vector3(0, 0, sz * 0.02), wood)   # um raio, para a roda girar aparecer
			root.add_child(wheel)
	return root


static func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.9
	return m


static func _box(parent: Node3D, size: Vector3, at: Vector3, mat: StandardMaterial3D) -> void:
	var m := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	m.mesh = b
	m.material_override = mat
	m.position = at
	parent.add_child(m)
