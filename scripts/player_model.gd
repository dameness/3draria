extends Node3D
# Corpo do jogador (3ª pessoa, inimigos humanoides e menu): boneco de voxels na escala do sprite do Terraria (scripts/voxel:
# 1 voxel = 1 pixel), uma malha por articulação (cabeça, tronco, braços, pernas, cabelo, olhos), com as cores do personagem; a arma 3D
# na mão direita e a armadura por cima, peça a peça. Conjuntos com `model` em armor_sets.json (Molten) vestem cascas voxel; os outros
# ainda são formas em código (capacete com aba, peitoral com ombreiras, grevas...) pintadas com a paleta do ícone, até a leva deles.
# Animação: respirar, piscar, andar (com balanço do corpo), pular, cair, nadar e golpear.

const HeldItem := preload("res://scripts/held_item.gd")
const OUTLINE := 0.014            # espessura do contorno em blocos
const SPHERE_SEGMENTS := 14
const LOOKS := ["meteor", "ninja"]       # conjuntos com formato próprio em código (_look); os outros usam o genérico por metal
const HEAD := 0.68                # escala da cabeça (o boneco tem ~1,8 de altura com o cabelo): proporção mais adulta que a do chibi

@export var player: Node3D           # jogador, inimigo humanoide ou boneco do menu (lê velocity, pitch, held(), cooldown, inv, entities)
var skin := Color("#f0b890")
var hair := Color("#5a3220")
var shirt := Color("#c0503c")
var pants := Color("#3c4c98")
var arms_forward := false            # zumbi
var townsfolk := false               # habitante: braços soltos balançando ao andar (sem mira, item nem armadura)
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
var spark_pts := PackedVector3Array()   # topos emissivos do capacete voxel (em relação ao nó), de onde saem as fagulhas (Molten)
var spark_node: MeshInstance3D
var spark_color := Color.WHITE
var spark_t := 0.0
var blink := 0.0
var hair_nodes: Array[Node3D] = []
var eyes: Array[Node3D] = []
static var _mats := {}
static var _outline: StandardMaterial3D
static var _plate: ImageTexture


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
	var piv := VoxRecipes.PIV
	var upper := _pivot(self, "upper", piv.upper)   # tronco, cabeça e braços: inclinam juntos a partir da cintura
	for side in [-1, 1]:
		_vox(_pivot(self, "leg_l" if side < 0 else "leg_r", Vector3(side * piv.leg.x, piv.leg.y, 0)), "leg")
	_vox(upper, "torso")
	var head := _pivot(upper, "head", piv.head)
	_vox(head, "head")
	hair_nodes.append(_vox(head, "hair"))
	for e in ["eye_l", "eye_r"]:
		eyes.append(_vox(head, e, VoxRecipes.pivot_pos(VoxRecipes.EYE_L if e == "eye_l" else VoxRecipes.EYE_R)))
	var old := Node3D.new()   # as armaduras em código foram feitas para a cabeça em escala HEAD
	old.scale = Vector3.ONE * HEAD
	head.add_child(old)
	parts["head_old"] = old
	for side in [-1, 1]:   # o pivô do braço é o ombro, dentro do tronco: girar o braço não abre vão
		_vox(_pivot(upper, "arm_l" if side < 0 else "arm_r", Vector3(side * piv.arm.x, piv.arm.y, 0)), "arm")
	held = MeshInstance3D.new()
	parts.arm_r.add_child(held)
	trail = Trail.new()
	add_child(trail)


# Peça voxel do corpo (pivô no encaixe), com as cores do personagem.
func _vox(parent: Node3D, part: String, pos := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = VoxRecipes.part_mesh("body", part, {"skin": skin, "hair": hair, "shirt": shirt, "pants": pants})
	mi.material_override = VoxMesh.material(0.6)
	mi.position = pos
	parent.add_child(mi)
	return mi


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


# Placas de metal em tons de cinza (16x16 pixel a pixel, filtro "nearest"): luz na borda de cima/esquerda, sombra embaixo/direita,
# junta escura entre as placas, rebites e risco. Multiplicada pela cor da peça, dá a textura pixelada do Terraria.
static func _plate_tex() -> ImageTexture:
	if _plate == null:
		var img := Image.create(16, 16, false, Image.FORMAT_RGB8)
		for y in 16:
			for x in 16:
				var v := 0.9 + 0.05 * float((x * 7 + y * 13) % 5 - 2)   # grão
				if x == 0 or y == 0:
					v = 0.5   # junta entre placas
				elif x == 1 or y == 1:
					v = 1.0    # brilho
				elif x == 15 or y == 15:
					v = 0.6    # sombra
				elif (x == 4 or x == 11) and (y == 4 or y == 11):
					v = 1.0 if x == 4 and y == 4 else 0.45   # rebites
				elif y == 8 and x > 5 and x < 11:
					v = 0.66   # risco
				img.set_pixel(x, y, Color(v, v, v))
		_plate = ImageTexture.create_from_image(img)
	return _plate


# Material que brilha (lava do Molten/Meteor, olhos do elmo): sem sombreado, com contorno.
static func _glow_mat(c: Color) -> StandardMaterial3D:
	var key := ["glow", c]
	if not _mats.has(key):
		var m: StandardMaterial3D = _mat(c).duplicate()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = c.lightened(0.15)
		_mats[key] = m
	return _mats[key]


# Material da armadura: placa × cor, repetida pelo tamanho da peça (placas de ~17 cm).
static func _plate_mat(c: Color, uv: Vector3) -> StandardMaterial3D:
	var key := [c, uv]
	if not _mats.has(key):
		var m: StandardMaterial3D = _mat(c).duplicate()
		m.albedo_texture = _plate_tex()
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		m.uv1_scale = uv
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
	_sparks(delta)
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
	if townsfolk:
		parts.arm_r.rotation.x = -arm
		return
	if arms_forward:   # zumbi: braços esticados para a frente
		parts.arm_l.rotation.x = PI / 2 + swing * 0.2
		parts.arm_r.rotation.x = PI / 2 - swing * 0.2
		return
	parts.head.rotation.x = player.pitch * 0.6
	var id: int = player.held()
	var st := HeldItem.style(id) if id != -1 else ""
	var dur: float = 0.25
	if id != -1:
		dur = player.get("use_len") if player.get("use_len") != null else Items.use_dur(id)
	var use: float = clampf(1.0 - player.cooldown / dur, 0, 1) if player.cooldown > 0 else 1.0
	var rest: float = (swing * 0.5 if grounded and not swimming else arm)
	if id != -1:   # com item na mão o braço fica à frente
		rest = {"swing": 1.0, "thrust": 1.35, "shoot": 0.7, "hold": 0.8}[st] + rest * 0.3
	var target_twist := 0.0
	if player.cooldown > 0 and id != -1:
		match st:
			"swing":   # diagonal como em 1ª pessoa: do alto à direita, por cima da cabeça, cruzando o corpo até embaixo à esquerda; o corpo gira junto
				parts.arm_r.rotation.z = lerpf(0.9, -0.6, ease(use, 0.6))
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


# Fagulhas saindo da crista do capacete (fx.gd), só com o corpo à vista.
func _sparks(delta: float) -> void:
	if spark_node == null or spark_pts.is_empty() or not is_visible_in_tree():
		return
	spark_t -= delta
	var into = player.get("entities") if player else null
	if spark_t <= 0.0 and into != null:
		spark_t = randf_range(0.08, 0.22)
		Fx.burst(into, spark_node.to_global(spark_pts[randi() % spark_pts.size()]), spark_color, 1, {"size": 0.07, "life": 0.9, "speed": 1.2, "spread": 30.0, "gravity": -1.5, "additive": true})


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
func _colors(id: int, split := false) -> Array:
	var img: Image = player.entities.icon(id).get_image()
	img.convert(Image.FORMAT_RGBA8)
	var px: Array[Color] = []
	var glow: Array[Color] = []
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a > 0.5:
				if split and c.s > 0.55 and c.v > 0.3:
					glow.append(c)
				else:
					px.append(c)
	if px.is_empty():
		return [Color.GRAY, Color.DIM_GRAY, Color.DARK_GRAY, Color.ORANGE]
	px.sort_custom(func(a, b): return a.get_luminance() > b.get_luminance())
	var n := px.size()
	var dark := px.slice(n * 3 / 4).filter(func(c): return c.get_luminance() > 0.06)
	return [_avg(px.slice(0, maxi(1, n / 2))), _avg(px.slice(n / 2, maxi(n / 2 + 1, n * 3 / 4))), _avg(dark if not dark.is_empty() else px.slice(n * 3 / 4)), _avg(glow) if not glow.is_empty() else Color(0.9, 0.9, 0.95)]


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
	spark_node = null
	for k in Inventory.ARMOR.size():
		var id: int = worn[k]
		if id == -1:
			continue
		var look: String = Items.defs[id].get("set", "")
		var vset: String = Items.sets.get(look, {}).get("model", "")
		if vset != "" and _vox_shell(Inventory.ARMOR[k], vset):   # casca voxel do conjunto (Molten)
			if Inventory.ARMOR[k] == "head":
				for n in hair_nodes:
					n.visible = false
			continue
		var pal := _colors(id, look in ["meteor"])
		var c := [pal[0], pal[0].lightened(0.28), pal[1]]   # principal, brilho, sombra/detalhe (contraste alto como o sprite)
		var list := []
		var node := func(parent: String) -> Node3D: return parts["head_old" if parent == "head" else parent]
		var add := func(parent: String, mesh: Mesh, col: Color, pos: Vector3, size := Vector3.ONE, rot := Vector3.ZERO):
			var mi := _part(node.call(parent), mesh, col, pos, size, rot)
			var box := mesh.get_aabb().size * size
			mi.material_override = _plate_mat(col, Vector3(snappedf(PI * maxf(box.x, box.z) / 0.17, 1.0), maxf(1.0, snappedf(box.y / 0.17, 1.0)), 1.0))
			list.append(mi)
		var glow := func(parent: String, mesh: Mesh, pos: Vector3, size := Vector3.ONE, rot := Vector3.ZERO):
			var mi := _part(node.call(parent), mesh, pal[3], pos, size, rot)
			mi.material_override = _glow_mat(pal[3])
			list.append(mi)
		var flat := func(parent: String, mesh: Mesh, col: Color, pos: Vector3, size := Vector3.ONE, rot := Vector3.ZERO):   # tecido: sem placas
			list.append(_part(node.call(parent), mesh, col, pos, size, rot))
		if look in LOOKS:
			_look(Inventory.ARMOR[k], look, add, glow, flat, c)
			if Inventory.ARMOR[k] == "head":
				for n in hair_nodes:
					n.visible = false
			shells[Inventory.ARMOR[k]] = list
			continue
		match Inventory.ARMOR[k]:
			"head":
				add.call("head", _sphere(), c[0], Vector3(0, 0.42, 0.03), Vector3(0.72, 0.46, 0.7))          # calota (deixa o rosto aberto)
				add.call("head", _capsule(0.03, 0.62), c[1], Vector3(0, 0.44, -0.04), Vector3(1, 1, 1), Vector3(0, 0, PI / 2))   # aba da testa
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
					add.call("arm_l" if side < 0 else "arm_r", _sphere(), c[1], Vector3(side * 0.03, 0.0, 0), Vector3(0.34, 0.26, 0.32))   # ombreira grande
					add.call("arm_l" if side < 0 else "arm_r", _capsule(0.115, 0.32), c[0], Vector3(0, -0.13, 0))                # braçadeira
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


# Casca voxel de `vset` para o espaço `slot`: uma malha por articulação que a peça cobre, com o encaixe no pivô. false se o modelo não existe
# (sem o sprite baixado): o chamador cai nas formas em código.
func _vox_shell(slot: String, vset: String) -> bool:
	var targets: Array = {"head": [["head", "head"]], "body": [["body", "upper"], ["arm", "arm_l"], ["arm", "arm_r"]], "legs": [["leg", "leg_l"], ["leg", "leg_r"]]}[slot]
	var list := []
	for t in targets:
		var mesh := VoxRecipes.part_mesh(vset, t[0])
		if mesh == null:
			return false
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = VoxMesh.material(0.6)
		parts[t[1]].add_child(mi)
		list.append(mi)
	shells[slot] = list
	var sp: String = VoxRecipes.specs().get(vset, {}).get("sparks", "")
	if slot == "head" and sp != "":
		spark_node = list[0]
		spark_color = Color(sp)
		var glow: PackedVector3Array = spark_node.mesh.get_meta("glow", PackedVector3Array())
		var top := -1e9
		for g in glow:
			top = maxf(top, g.y)
		spark_pts = PackedVector3Array()
		for g in glow:
			if g.y > top - 0.15:
				spark_pts.append(g)
	return true


# Conjuntos com formato próprio em código (wiki): Meteor = elmo com espinhos de lava e ombreiras espetadas; Ninja = capuz de pano com faixa e fresta dos olhos,
# camisa cruzada por faixas, ataduras nas botas. c = [principal, brilho, sombra]; `glow` usa a cor viva do ícone (pal[3]).
func _look(slot: String, look: String, add: Callable, glow: Callable, flat: Callable, c: Array) -> void:
	var cone := _cone(0.07, 0.3)
	var box := BoxMesh.new()
	if look == "ninja":   # pano escuro com faixas claras
		c = [c[2].lightened(0.25), c[0].lightened(0.3), c[2].darkened(0.3)]
	match [look, slot]:
		["meteor", "head"]:
			add.call("head", _sphere(), c[0], Vector3(0, 0.3, 0.03), Vector3(0.74, 0.68, 0.72))
			add.call("head", _capsule(0.03, 0.56), c[2], Vector3(0, 0.44, -0.3), Vector3(1, 1, 1), Vector3(0, 0, PI / 2))   # borda do elmo
			glow.call("head", _sphere(), Vector3(0, 0.33, -0.33), Vector3(0.44, 0.09, 0.05))              # visor de lava
			for s in [[-0.22, 0.62, 0.0, -0.6, 0.3], [0.0, 0.7, 0.05, 0.0, 0.5], [0.22, 0.62, 0.0, 0.6, 0.3], [-0.1, 0.6, 0.22, -0.3, 0.9], [0.12, 0.58, 0.24, 0.35, 1.0]]:
				glow.call("head", cone, Vector3(s[0], s[1], s[2]), Vector3.ONE, Vector3(s[4], 0, s[3]))   # espinhos de lava
		["meteor", "body"]:
			add.call("upper", _capsule(0.168, 0.58), c[0], Vector3(0, 0.28, 0), Vector3(1.4, 1.0, 1.0))
			add.call("upper", _sphere(), c[2], Vector3(0, 0.04, 0), Vector3(0.5, 0.1, 0.34))
			glow.call("upper", box, Vector3(0, 0.34, -0.165), Vector3(0.12, 0.16, 0.05), Vector3(0, 0, PI / 4))   # gema de lava
			glow.call("upper", _sphere(), Vector3(0, 0.47, 0), Vector3(0.6, 0.1, 0.34))                   # gola de lava
			for side in [-1, 1]:
				var a := "arm_l" if side < 0 else "arm_r"
				add.call(a, _sphere(), c[1], Vector3(side * 0.03, 0.0, 0), Vector3(0.34, 0.27, 0.33))
				glow.call(a, cone, Vector3(side * 0.16, 0.14, 0), Vector3.ONE, Vector3(0, 0, -side * 1.1))   # espinho da ombreira
				add.call(a, _capsule(0.115, 0.32), c[0], Vector3(0, -0.13, 0))
		["meteor", "legs"]:
			for side in [-1, 1]:
				var p := "leg_l" if side < 0 else "leg_r"
				add.call(p, _capsule(0.118, 0.6), c[0], Vector3(0, -0.33, 0))
				glow.call(p, _sphere(), Vector3(0, -0.36, -0.12), Vector3(0.1, 0.1, 0.05))
				add.call(p, _sphere(), c[2], Vector3(0, -0.67, -0.04), Vector3(0.24, 0.17, 0.36))
				glow.call(p, _sphere(), Vector3(0, -0.6, 0), Vector3(0.26, 0.04, 0.26))                     # borda de lava da bota
		["ninja", "head"]:
			flat.call("head", _sphere(), c[0], Vector3(0, 0.3, 0.03), Vector3(0.72, 0.68, 0.7))           # capuz
			flat.call("head", _sphere(), skin, Vector3(0, 0.3, -0.25), Vector3(0.52, 0.17, 0.2))         # fresta dos olhos
			for side in [-1, 1]:
				flat.call("head", _sphere(), Color.WHITE, Vector3(side * 0.11, 0.3, -0.345), Vector3(0.1, 0.09, 0.03))
				flat.call("head", _sphere(), Color("#10131c"), Vector3(side * 0.11, 0.3, -0.365), Vector3(0.05, 0.07, 0.02))
			flat.call("head", _capsule(0.03, 0.66), c[1], Vector3(0, 0.44, -0.02), Vector3(1, 1, 1), Vector3(0, 0, PI / 2))   # faixa da testa
			flat.call("head", _capsule(0.05, 0.3), c[2], Vector3(0.05, 0.28, 0.4), Vector3(1, 1, 1), Vector3(0.9, 0, 0.3))   # nó do capuz
		["ninja", "body"]:
			flat.call("upper", _capsule(0.168, 0.58), c[0], Vector3(0, 0.28, 0), Vector3(1.4, 1.0, 1.0))
			flat.call("upper", _sphere(), c[2], Vector3(0, 0.04, 0), Vector3(0.5, 0.1, 0.34))
			flat.call("upper", _sphere(), c[0], Vector3(0, 0.46, 0), Vector3(0.56, 0.23, 0.32))     # ombros
			for r in [0.7, -0.7]:
				flat.call("upper", box, c[1], Vector3(0, 0.3, -0.16), Vector3(0.05, 0.4, 0.03), Vector3(0, 0, r))   # faixas cruzadas
			for side in [-1, 1]:
				var a := "arm_l" if side < 0 else "arm_r"
				flat.call(a, _sphere(), c[0], Vector3.ZERO, Vector3(0.21, 0.21, 0.21))
				flat.call(a, _capsule(0.103, 0.36), c[0], Vector3(0, -0.15, 0))                               # manga
				flat.call(a, _capsule(0.105, 0.05), c[1], Vector3(0, -0.34, 0))                               # atadura do punho
		["ninja", "legs"]:
			for side in [-1, 1]:
				var p := "leg_l" if side < 0 else "leg_r"
				flat.call(p, _capsule(0.118, 0.62), c[0], Vector3(0, -0.33, 0))
				flat.call(p, _sphere(), c[2], Vector3(0, -0.67, -0.04), Vector3(0.24, 0.17, 0.36))
				flat.call(p, _capsule(0.125, 0.06), c[1], Vector3(0, -0.55, 0))                               # atadura do tornozelo
