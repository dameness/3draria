extends Node3D
# Corpo do jogador (3ª pessoa, inimigos humanoides e menu): boneco de formas arredondadas com sombreado "toon" e contorno
# escuro (o traço do sprite do Terraria), cabeça grande, olhos, cabelo espetado, mãos, botas; a arma 3D na mão direita e
# a armadura por cima, peça a peça (capacete com aba e protetores, peitoral com ombreiras e cinto, grevas com joelheiras
# e botas), pintada com a paleta do ícone. Animação: respirar, piscar, andar (com balanço do corpo), pular, cair, nadar e
# golpear. Tudo por código; nada de arquivo de arte.

const HeldItem := preload("res://scripts/held_item.gd")
const OUTLINE := 0.014            # espessura do contorno em blocos
const SPHERE_SEGMENTS := 14
const HEAD := 0.78                # escala da cabeça (o boneco tem ~1,85 de altura com o cabelo)

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
var trail: Trail            # arco do golpe da arma na mão
var trail_on := false
var worn := PackedInt32Array([-2, -2, -2])
var wing_id := -2
var wing_sprites: Array[Sprite3D] = []
var phase := 0.0
var blink := 0.0
var hair_nodes: Array[Node3D] = []
var eyes: Array[Node3D] = []
static var _mats := {}
static var _outline: StandardMaterial3D


func _ready() -> void:
	_build()


# Troca as cores (aparência do personagem) e refaz o corpo.
func restyle(look: Dictionary) -> void:
	skin = look.skin
	hair = look.hair
	shirt = look.shirt
	pants = look.pants
	for c in get_children():
		c.free()
	parts.clear()
	shells.clear()
	eyes.clear()
	hair_nodes.clear()
	worn = PackedInt32Array([-2, -2, -2])   # o próximo quadro veste a armadura de novo
	wing_id = -2
	wing_sprites.clear()
	held_id = -2
	_build()


func _build() -> void:
	var upper := _pivot(self, "upper", Vector3(0, 0.72, 0))   # tronco, cabeça e braços: inclinam juntos a partir da cintura
	for side in [-1, 1]:
		var leg := _pivot(self, "leg_l" if side < 0 else "leg_r", Vector3(side * 0.105, 0.75, 0))
		_part(leg, _capsule(0.1, 0.62), pants, Vector3(0, -0.33, 0))
		_part(leg, _sphere(), pants, Vector3(0, -0.02, 0), Vector3(0.24, 0.22, 0.24))   # quadril
		_part(leg, _sphere(), Color("#5a3a2a"), Vector3(0, -0.67, -0.035), Vector3(0.21, 0.16, 0.34))   # bota (a sola toca o chão)
	_part(upper, _capsule(0.15, 0.56), shirt, Vector3(0, 0.28, 0), Vector3(1.4, 1.0, 0.98))    # camiseta
	_part(upper, _sphere(), shirt, Vector3(0, 0.46, 0), Vector3(0.5, 0.2, 0.28))               # ombros: a camiseta cobre a parte de cima
	_part(upper, _sphere(), pants, Vector3(0, 0.04, 0), Vector3(0.4, 0.15, 0.28))               # cós da calça
	_part(upper, _capsule(0.055, 0.15), skin, Vector3(0, 0.57, 0), Vector3(1, 1, 1), Vector3.ZERO, false)   # pescoço
	var head := _pivot(upper, "head", Vector3(0, 0.56, 0))
	head.scale = Vector3.ONE * HEAD   # cabeça, cabelo e capacete escalam juntos
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
	for side in [-1, 1]:   # o pivô do braço é o ombro, dentro do tronco: girar o braço não abre vão
		var arm := _pivot(upper, "arm_l" if side < 0 else "arm_r", Vector3(side * 0.232, 0.47, 0))
		_part(arm, _capsule(0.072, 0.6), skin, Vector3(0, -0.26, 0))
		_part(arm, _capsule(0.092, 0.29), shirt, Vector3(0, -0.11, 0))    # manga
		_part(arm, _sphere(), shirt, Vector3.ZERO, Vector3(0.19, 0.19, 0.19))   # ombro
		_part(arm, _sphere(), skin, Vector3(0, -0.55, 0), Vector3(0.17, 0.17, 0.17))   # mão
	held = MeshInstance3D.new()
	parts.arm_r.add_child(held)
	trail = Trail.new()
	add_child(trail)


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
	m.scale = size
	parent.add_child(m)
	return m


# Convenção: rotation.x positivo balança o braço/perna para a FRENTE (o corpo olha para -Z).
func _process(delta: float) -> void:
	if player == null:
		player = get_parent().get_parent() if get_parent() else null  # modelo de inimigo: dono é o avô
		if player == null:
			return
	var t := Time.get_ticks_msec() / 1000.0
	var speed := Vector2(player.velocity.x, player.velocity.z).length()
	var grounded: bool = player.get("on_floor") != false
	var swimming: bool = player.get("swimming") == true
	phase += delta * speed * 2.2
	var walk := clampf(speed / 4.5, 0, 1.5)
	var swing := sin(phase) * minf(walk, 1.0) * 0.85
	var bob := absf(sin(phase)) * walk * 0.035 if grounded and not swimming else 0.0
	var breathe := sin(t * 2.0) * 0.012
	position.y = bob + breathe
	parts.upper.rotation.x = -walk * 0.08 if not swimming else -0.5   # inclina para a frente ao andar; nadando, deitado
	parts.upper.scale.y = 1.0 + breathe * 0.6
	# pernas e braços: andar; no ar, abertos; nadando, braçadas
	var leg := swing
	var arm := -swing * 0.8
	if swimming:
		leg = sin(t * 7.0) * 0.5
		arm = sin(t * 5.0) * 0.9 + 1.2
	elif not grounded:
		leg = 0.5 if player.velocity.y > 0 else 0.25
		arm = 2.4 if player.velocity.y > 0 else 0.6
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
	if arms_forward:   # zumbi: braços esticados para a frente
		parts.arm_l.rotation.x = PI / 2 + swing * 0.2
		parts.arm_r.rotation.x = PI / 2 - swing * 0.2
		return
	parts.head.rotation.x = player.pitch * 0.6
	var id: int = player.held()
	var st := HeldItem.style(id) if id != -1 else ""
	var dur: float = Items.use_dur(id) if id != -1 else 0.25
	var use: float = clampf(1.0 - player.cooldown / dur, 0, 1) if player.cooldown > 0 else 1.0
	var rest: float = (swing * 0.5 if grounded and not swimming else arm)
	if id != -1:   # com item na mão o braço fica à frente
		rest = {"swing": 1.0, "thrust": 1.35, "shoot": 0.7, "hold": 0.8}[st] + rest * 0.3
	var target_twist := 0.0
	if player.cooldown > 0 and id != -1:
		match st:
			"swing":   # de cima para trás, por cima da cabeça, até à frente e para baixo; o corpo gira junto
				parts.arm_r.rotation.x = lerpf(rest, 3.3, use / 0.1) if use < 0.1 else lerpf(3.3, 0.35, ease((use - 0.1) / 0.9, 0.4))
				target_twist = lerpf(-0.3, 0.3, ease(use, 0.5))
			"thrust":   # estocada para a frente, com o corpo indo junto
				parts.arm_r.rotation.x = lerpf(0.5, 1.55, sin(PI * use))
				target_twist = 0.2 * sin(PI * use)
			"shoot":   # mira à frente e o recuo do disparo
				parts.arm_r.rotation.x = 1.5 - 0.2 * (1.0 - use)
				parts.arm_l.rotation.x = 1.3
			_:
				parts.arm_r.rotation.x = rest
		parts.upper.rotation.y = target_twist
	else:
		parts.arm_r.rotation.x = lerpf(parts.arm_r.rotation.x, rest, minf(1.0, delta * 14.0))
		parts.upper.rotation.y = lerpf(parts.upper.rotation.y, 0.0, minf(1.0, delta * 12.0))
	if player.cooldown > 0 and id != -1 and trail_on and held.mesh:
		var box: AABB = held.mesh.get_aabb()
		trail.push(held.global_transform * box.end, held.global_transform * (box.position + box.size * 0.6))
	if id != held_id:
		held_id = id
		_show_held(id)
	_wings(t)
	if player.inv.equip != worn:
		worn = player.inv.equip.duplicate()
		_dress()


# Asas (acessório): duas cópias espelhadas do sprite do item nas costas, presas aos ombros (o sprite tem a raiz no canto de cima, junto do corpo) e
# translúcidas (as Fledgling são). Fechadas em pé, abertas em V planando, batendo ao subir.
func _wings(t: float) -> void:
	var id: int = player.inv.wing_id()
	if id != wing_id:
		wing_id = id
		for w in wing_sprites:
			w.queue_free()
		wing_sprites.clear()
		if id != -1:
			for side in [-1, 1]:
				var sp := Sprite3D.new()
				sp.texture = player.entities.icon(id)
				var w: float = sp.texture.get_width()
				sp.pixel_size = 1.1 / maxf(sp.texture.get_height(), 1.0)
				sp.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
				sp.flip_h = side > 0   # o sprite tem a raiz à direita: a asa do lado esquerdo fica como está e a do direito espelha
				sp.centered = false
				sp.offset = Vector2(0.0 if side > 0 else -w, 0.0)   # a origem no canto da raiz (em cima, junto do corpo)
				sp.shaded = false
				sp.double_sided = true
				sp.modulate = Color(1, 1, 1, 0.9)
				sp.position = Vector3(side * 0.1, 0.46, 0.15)
				parts.upper.add_child(sp)
				wing_sprites.append(sp)
	var spread := 0.3   # ângulo da asa em relação às costas
	if player.get("flapping") == true:
		spread = 0.85 + 0.55 * sin(t * 24.0)
	elif player.get("gliding") == true:
		spread = 1.35
	for i in wing_sprites.size():
		wing_sprites[i].rotation.z = spread * (-1.0 if i == 0 else 1.0)


# Item na mão: o cabo na mão e a lâmina saindo dela (inclinada para a frente em `swing`, no eixo do braço em `thrust`);
# arcos e itens de segurar ficam de pé, centrados. O plano do sprite é o do golpe (o lado da lâmina fica para fora).
func _show_held(id: int) -> void:
	held.visible = id != -1
	if id == -1:
		return
	var st := HeldItem.style(id)
	var m := ItemModel.for_item(id, player.entities.icon(id), 0.9 if st != "hold" else 0.5)
	held.mesh = m[0]
	held.material_override = m[1]
	var fx: Dictionary = Items.defs[id].get("effects", {})
	trail_on = fx.has("trail") or (st in ["swing", "thrust"] and Items.defs[id].get("damage", 0) > 0 and Items.pick_power[id] == 0 and Items.axe_power[id] == 0)
	trail.color = Color(fx.trail) if fx.has("trail") else Color(0.92, 0.96, 1.0)
	var blade := st in ["swing", "thrust"]
	var phi: float = {"swing": 0.8, "thrust": 0.0}.get(st, PI / 2)
	var b := Vector3(0, -cos(phi), -sin(phi))
	var frame := Basis(b.cross(Vector3.RIGHT), b, Vector3.RIGHT)   # x = largura do sprite, y = direção da lâmina, z = plano do golpe
	var ang: float = Items.defs[id].get("sprite_angle", 45.0)
	var align := Basis(Vector3.BACK, deg_to_rad(90.0 - ang)) if blade else Basis()
	var m3 := frame * align
	var origin := Vector3(0, -0.55, 0)
	if not blade:
		origin -= m3 * m[0].get_aabb().get_center()
	held.transform = Transform3D(m3, origin)


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
				add.call("head", _sphere(), c[1], Vector3(-0.31, 0.26, -0.02), Vector3(0.07, 0.2, 0.22))     # protetores de orelha
				add.call("head", _sphere(), c[1], Vector3(0.31, 0.26, -0.02), Vector3(0.07, 0.2, 0.22))
				add.call("head", _capsule(0.035, 0.5), c[1], Vector3(0, 0.6, 0.0), Vector3(1, 1, 1), Vector3(PI / 2, 0, 0))   # nervura do topo
				for n in hair_nodes:   # o cabelo não atravessa o capacete
					n.visible = false
			"body":
				add.call("upper", _capsule(0.168, 0.58), c[0], Vector3(0, 0.28, 0), Vector3(1.4, 1.0, 1.0))    # peitoral
				add.call("upper", _sphere(), c[1], Vector3(0, 0.46, 0), Vector3(0.56, 0.24, 0.33))             # gola / ombros
				add.call("upper", _sphere(), c[2], Vector3(0, 0.04, 0), Vector3(0.48, 0.1, 0.34))              # cinto
				add.call("upper", BoxMesh.new(), c[1], Vector3(0, 0.36, -0.155), Vector3(0.13, 0.13, 0.05), Vector3(0, 0, PI / 4))   # emblema do peito
				for side in [-1, 1]:
					add.call("arm_l" if side < 0 else "arm_r", _sphere(), c[1], Vector3(0, 0.0, 0), Vector3(0.25, 0.22, 0.25))   # ombreira
					add.call("arm_l" if side < 0 else "arm_r", _capsule(0.103, 0.3), c[0], Vector3(0, -0.12, 0))                # braçadeira
			"legs":
				for side in [-1, 1]:
					var p := "leg_l" if side < 0 else "leg_r"
					add.call(p, _capsule(0.118, 0.6), c[0], Vector3(0, -0.33, 0))                          # greva
					add.call(p, _sphere(), c[1], Vector3(0, -0.36, -0.1), Vector3(0.15, 0.15, 0.1))        # joelheira
					add.call(p, _sphere(), c[2], Vector3(0, -0.67, -0.04), Vector3(0.24, 0.17, 0.36))      # bota
					add.call(p, _sphere(), c[1], Vector3(0, -0.6, 0), Vector3(0.26, 0.09, 0.26))           # cano da bota
		shells[Inventory.ARMOR[k]] = list
	if worn[0] == -1:
		for n in hair_nodes:
			n.visible = true
