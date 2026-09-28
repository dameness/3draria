extends Node3D
# Corpo do jogador (3ª pessoa, inimigos humanoides e menu): boneco de formas arredondadas com sombreado "toon" e contorno
# escuro (o traço do sprite do Terraria), cabeça grande, olhos, cabelo espetado, mãos, botas; a arma 3D na mão direita e
# a armadura por cima, peça a peça (capacete com aba e protetores, peitoral com ombreiras e cinto, grevas com joelheiras
# e botas), pintada com a paleta do ícone. Animação: respirar, piscar, andar (com balanço do corpo), pular, cair, nadar e
# golpear. Tudo por código; nada de arquivo de arte.

const OUTLINE := 0.014            # espessura do contorno em blocos
const SPHERE_SEGMENTS := 14

@export var player: Node3D           # jogador, inimigo humanoide ou boneco do menu (lê velocity, pitch, held(), cooldown, inv, entities)
var skin := Color("#f0b890")
var hair := Color("#5a3220")
var shirt := Color("#c0503c")
var pants := Color("#3c4c98")
var arms_forward := false            # zumbi
var parts := {}      # nome -> pivô (Node3D) na articulação
var shells := {}     # slot de armadura -> [MeshInstance3D]
var held: MeshInstance3D
var held_id := -2
var worn := PackedInt32Array([-2, -2, -2])
var phase := 0.0
var blink := 0.0
var hair_nodes: Array[Node3D] = []
var eyes: Array[Node3D] = []
static var _mats := {}
static var _outline: StandardMaterial3D


func _ready() -> void:
	var upper := _pivot(self, "upper", Vector3(0, 0.62, 0))   # tronco, cabeça e braços: inclinam juntos
	for side in [-1, 1]:
		var leg := _pivot(self, "leg_l" if side < 0 else "leg_r", Vector3(side * 0.115, 0.64, 0))
		_part(leg, _capsule(0.105, 0.56), pants, Vector3(0, -0.27, 0))
		_part(leg, _sphere(), pants, Vector3(0, -0.02, 0), Vector3(0.23, 0.2, 0.23))
		_part(leg, _sphere(), Color("#5a3a2a"), Vector3(0, -0.57, -0.04), Vector3(0.2, 0.14, 0.32))   # bota
	_part(upper, _capsule(0.17, 0.5), shirt, Vector3(0, 0.27, 0), Vector3(1.32, 1.0, 0.92))
	_part(upper, _sphere(), pants, Vector3(0, 0.03, 0), Vector3(0.44, 0.1, 0.32))   # cós da calça
	var head := _pivot(upper, "head", Vector3(0, 0.53, 0))
	_part(head, _sphere(), skin, Vector3(0, 0.3, 0), Vector3(0.62, 0.6, 0.6))
	for side in [-1, 1]:
		var eye := Node3D.new()   # olho: branco, íris e brilho
		eye.position = Vector3(side * 0.115, 0.3, -0.265)
		head.add_child(eye)
		eyes.append(eye)
		_part(eye, _sphere(), Color.WHITE, Vector3.ZERO, Vector3(0.115, 0.15, 0.06), Vector3.ZERO, false)
		_part(eye, _sphere(), Color("#3a68c0"), Vector3(side * -0.006, -0.008, -0.026), Vector3(0.07, 0.1, 0.04), Vector3.ZERO, false)
		_part(eye, _sphere(), Color("#10131c"), Vector3(side * -0.006, -0.008, -0.04), Vector3(0.036, 0.06, 0.03), Vector3.ZERO, false)
		_part(head, _capsule(0.012, 0.09), hair.darkened(0.15), Vector3(side * 0.115, 0.42, -0.262), Vector3(1, 1, 1), Vector3(0, 0, PI / 2 + side * 0.15), false)   # sobrancelha
	_part(head, _sphere(), skin.darkened(0.08), Vector3(0, 0.24, -0.29), Vector3(0.06, 0.05, 0.05), Vector3.ZERO, false)   # nariz
	_part(head, _sphere(), skin.darkened(0.08), Vector3(-0.29, 0.28, 0), Vector3(0.05, 0.11, 0.09), Vector3.ZERO, false)   # orelhas
	_part(head, _sphere(), skin.darkened(0.08), Vector3(0.29, 0.28, 0), Vector3(0.05, 0.11, 0.09), Vector3.ZERO, false)
	_hair(head)
	for side in [-1, 1]:
		var arm := _pivot(upper, "arm_l" if side < 0 else "arm_r", Vector3(side * 0.3, 0.5, 0))
		_part(arm, _capsule(0.075, 0.5), skin, Vector3(0, -0.2, 0))
		_part(arm, _capsule(0.09, 0.3), shirt, Vector3(0, -0.11, 0))   # manga
		_part(arm, _sphere(), skin, Vector3(0, -0.46, 0), Vector3(0.17, 0.17, 0.17))   # mão
	held = MeshInstance3D.new()
	parts.arm_r.add_child(held)


# Cabelo espetado como o do Terraria: calota na cabeça, tufos para cima e para trás e uma franja.
func _hair(head: Node3D) -> void:
	var cap := _part(head, _sphere(), hair, Vector3(0, 0.4, 0.03), Vector3(0.66, 0.42, 0.66))
	hair_nodes.append(cap)
	var back := _part(head, _sphere(), hair, Vector3(0, 0.27, 0.13), Vector3(0.62, 0.5, 0.42))
	hair_nodes.append(back)
	for s in [[-0.2, 0.55, 0.02, -0.5, 0.0], [-0.07, 0.6, 0.0, -0.15, 0.0], [0.08, 0.6, 0.04, 0.25, 0.3], [0.21, 0.55, 0.08, 0.6, 0.0], [0.0, 0.5, 0.2, 0.05, 0.9]]:
		var spike := _part(head, _cone(0.085, 0.24), hair.lightened(0.04), Vector3(s[0], s[1], s[2]), Vector3.ONE, Vector3(s[4], 0, s[3]))
		hair_nodes.append(spike)
	for x in [-0.15, 0.0, 0.15]:   # franja
		hair_nodes.append(_part(head, _cone(0.07, 0.17), hair, Vector3(x, 0.5, -0.2), Vector3.ONE, Vector3(-1.0, 0, 0)))


func _pivot(parent: Node3D, name: String, pos: Vector3) -> Node3D:
	var p := Node3D.new()
	p.position = pos
	parent.add_child(p)
	parts[name] = p
	return p


static func _sphere() -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = 0.5
	m.height = 1.0
	m.radial_segments = SPHERE_SEGMENTS
	m.rings = SPHERE_SEGMENTS / 2
	return m


static func _capsule(radius: float, height: float) -> CapsuleMesh:
	var m := CapsuleMesh.new()
	m.radius = radius
	m.height = height
	m.radial_segments = 12
	m.rings = 4
	return m


static func _cone(radius: float, height: float) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = 0.0
	m.bottom_radius = radius
	m.height = height
	m.radial_segments = 8
	m.rings = 1
	return m


# Material "toon" (luz em faixas) com o contorno escuro como segunda passada. Um por cor.
static func _mat(c: Color, outline := true) -> StandardMaterial3D:
	var key := [c, outline]
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
		m.specular_mode = BaseMaterial3D.SPECULAR_TOON
		m.roughness = 0.7
		if outline:
			if _outline == null:
				_outline = StandardMaterial3D.new()
				_outline.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				_outline.albedo_color = Color(0.06, 0.035, 0.03)
				_outline.cull_mode = BaseMaterial3D.CULL_FRONT
				_outline.grow = true
				_outline.grow_amount = OUTLINE
			m.next_pass = _outline
		_mats[key] = m
	return _mats[key]


# Malha `mesh` (esferas: `size` = diâmetros em x, y, z) com o material da cor `c`.
static func _part(parent: Node3D, mesh: Mesh, c: Color, pos: Vector3, size := Vector3.ONE, rot := Vector3.ZERO, outline := true) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.material_override = _mat(c, outline)
	m.position = pos
	m.rotation = rot
	if mesh is SphereMesh:
		m.scale = size
	parent.add_child(m)
	return m


func _process(delta: float) -> void:
	if player == null:
		player = get_parent().get_parent() if get_parent() else null  # modelo de inimigo: dono é o avô
		if player == null:
			return
	var t := Time.get_ticks_msec() / 1000.0
	var speed := Vector2(player.velocity.x, player.velocity.z).length()
	var grounded: bool = player.get("on_floor") != false
	var swimming: bool = player.has_method("liquid_at") and player.liquid_at() != 0
	phase += delta * speed * 2.2
	var walk := clampf(speed / 4.5, 0, 1.5)
	var swing := sin(phase) * minf(walk, 1.0) * 0.85
	var bob := absf(sin(phase)) * walk * 0.035 if grounded and not swimming else 0.0
	var breathe := sin(t * 2.0) * 0.012
	position.y = bob + breathe
	parts.upper.rotation.x = walk * 0.1 if not swimming else 0.35   # inclina ao andar; nadando, para a frente
	parts.upper.scale.y = 1.0 + breathe * 0.6
	# pernas e braços: andar; no ar, abertos; nadando, batendo
	var leg := swing
	var arm := -swing * 0.8
	if swimming:
		leg = sin(t * 7.0) * 0.5
		arm = sin(t * 5.0) * 0.9 - 0.4
	elif not grounded:
		leg = 0.5 if player.velocity.y > 0 else 0.25
		arm = -1.6 if player.velocity.y > 0 else -0.5
	parts.leg_l.rotation.x = leg
	parts.leg_r.rotation.x = -leg if not (swimming or not grounded) else -leg * 0.6
	parts.arm_l.rotation.x = arm
	parts.arm_l.rotation.z = -0.12 - (0.35 if not grounded and not swimming else 0.0)
	parts.arm_r.rotation.z = 0.12 + (0.35 if not grounded and not swimming else 0.0)
	# piscar de vez em quando
	blink -= delta
	if blink < -3.0 - fmod(t * 7.3, 2.0):
		blink = 0.13
	for e in eyes:
		e.scale.y = 0.12 if blink > 0 else 1.0
	if arms_forward:
		parts.arm_l.rotation.x = -PI / 2 + swing * 0.2
		parts.arm_r.rotation.x = -PI / 2 - swing * 0.2
		return
	parts.head.rotation.x = player.pitch * 0.6
	var id: int = player.held()
	var dur: float = Items.defs[id].get("use_time", 0.25) if id != -1 else 0.25
	var use: float = clampf(1.0 - player.cooldown / dur, 0, 1) if player.cooldown > 0 else 1.0
	# braço da arma: golpe de cima para baixo durante o uso (o corpo gira junto); parado, um pouco à frente
	if player.cooldown > 0:
		parts.arm_r.rotation.x = lerpf(-2.6, -0.3, ease(use, 0.5))
		parts.upper.rotation.y = lerpf(0.35, -0.25, ease(use, 0.5))
	else:
		parts.arm_r.rotation.x = swing * 0.8 - 0.3 if grounded and not swimming else arm - 0.3
		parts.upper.rotation.y = lerpf(parts.upper.rotation.y, 0.0, minf(1.0, delta * 12.0))
	if id != held_id:
		held_id = id
		_show_held(id)
	if player.inv.equip != worn:
		worn = player.inv.equip.duplicate()
		_dress()


func _show_held(id: int) -> void:
	held.visible = id != -1
	if id == -1:
		return
	var m := ItemModel.for_item(id, player.entities.icon(id), 0.9)
	held.mesh = m[0]
	held.material_override = m[1]
	# cabo na mão (ponta do braço), lâmina para cima e para a frente
	var ang: float = Items.defs[id].get("sprite_angle", 45.0)
	held.transform = Transform3D(Basis(Vector3.RIGHT, -PI / 4) * Basis(Vector3.BACK, deg_to_rad(90.0 - ang)), Vector3(0, -0.5, 0))


# Cores da peça tiradas do sprite: média da metade mais clara dos pixels (o contorno escuro do Terraria deixaria tudo
# apagado), a do quarto seguinte e a dos mais escuros (sem o preto do contorno).
func _colors(id: int) -> Array:
	var img: Image = player.entities.icon(id).get_image()
	img.convert(Image.FORMAT_RGBA8)
	var px: Array[Color] = []
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a > 0.5:
				px.append(c)
	if px.is_empty():
		return [Color.GRAY, Color.DIM_GRAY, Color.DARK_GRAY]
	px.sort_custom(func(a, b): return a.get_luminance() > b.get_luminance())
	var n := px.size()
	var dark := px.slice(n * 3 / 4).filter(func(c): return c.get_luminance() > 0.06)
	return [_avg(px.slice(0, maxi(1, n / 2))), _avg(px.slice(n / 2, maxi(n / 2 + 1, n * 3 / 4))), _avg(dark if not dark.is_empty() else px.slice(n * 3 / 4))]


static func _avg(list: Array) -> Color:
	var sum := Color(0, 0, 0, 0)
	for c in list:
		sum += c
	sum /= list.size()
	sum.a = 1.0
	return sum


# Armadura por cima do corpo: cada peça é feita de formas próprias com as 3 cores do ícone (claro, médio, escuro).
func _dress() -> void:
	for list in shells.values():
		for m in list:
			m.queue_free()
	shells.clear()
	for k in Inventory.ARMOR.size():
		var id: int = worn[k]
		if id == -1:
			continue
		var pal := _colors(id)
		var c := [pal[0], pal[0].lightened(0.22), pal[1].lightened(0.12)]   # principal, brilho, sombra/detalhe
		var list := []
		var add := func(parent: String, mesh: Mesh, col: Color, pos: Vector3, size := Vector3.ONE, rot := Vector3.ZERO):
			list.append(_part(parts[parent], mesh, col, pos, size, rot))
		match Inventory.ARMOR[k]:
			"head":
				add.call("head", _sphere(), c[0], Vector3(0, 0.33, 0.01), Vector3(0.7, 0.6, 0.68))          # calota
				add.call("head", _capsule(0.02, 0.6), c[1], Vector3(0, 0.34, 0.0), Vector3(1, 1, 1), Vector3(0, 0, PI / 2))   # aba
				add.call("head", _sphere(), c[2], Vector3(0, 0.24, 0.24), Vector3(0.66, 0.32, 0.24))         # protetor da nuca
				add.call("head", _sphere(), c[2], Vector3(-0.3, 0.26, -0.02), Vector3(0.09, 0.22, 0.24))     # protetores de orelha
				add.call("head", _sphere(), c[2], Vector3(0.3, 0.26, -0.02), Vector3(0.09, 0.22, 0.24))
				add.call("head", _capsule(0.035, 0.42), c[1], Vector3(0, 0.63, 0.0), Vector3(1, 1, 1), Vector3(PI / 2, 0, 0))   # nervura do topo
				for n in hair_nodes:   # o cabelo não atravessa o capacete
					n.visible = false
			"body":
				add.call("upper", _capsule(0.19, 0.52), c[0], Vector3(0, 0.27, 0), Vector3(1.3, 1.0, 0.96))   # peitoral
				add.call("upper", _sphere(), c[2], Vector3(0, 0.05, 0), Vector3(0.5, 0.1, 0.36))             # cinto
				add.call("upper", _sphere(), c[1], Vector3(0, 0.36, -0.12), Vector3(0.24, 0.2, 0.1))         # placa do peito
				for side in [-1, 1]:
					add.call("arm_l" if side < 0 else "arm_r", _sphere(), c[1], Vector3(0, -0.01, 0), Vector3(0.26, 0.2, 0.26))   # ombreira
					add.call("arm_l" if side < 0 else "arm_r", _capsule(0.095, 0.26), c[0], Vector3(0, -0.13, 0))                   # braçadeira
			"legs":
				for side in [-1, 1]:
					var p := "leg_l" if side < 0 else "leg_r"
					add.call(p, _capsule(0.118, 0.5), c[0], Vector3(0, -0.25, 0))                          # greva
					add.call(p, _sphere(), c[1], Vector3(0, -0.29, -0.09), Vector3(0.18, 0.18, 0.14))      # joelheira
					add.call(p, _sphere(), c[2], Vector3(0, -0.57, -0.04), Vector3(0.24, 0.17, 0.36))      # bota
					add.call(p, _sphere(), c[1], Vector3(0, -0.5, 0), Vector3(0.26, 0.09, 0.26))           # cano da bota
		shells[Inventory.ARMOR[k]] = list
	if worn[0] == -1:
		for n in hair_nodes:
			n.visible = true
