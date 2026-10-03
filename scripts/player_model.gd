extends Node3D
# Corpo do jogador (3ª pessoa, inimigos humanoides e menu): boneco de voxels na escala do sprite do Terraria (scripts/voxel:
# 1 voxel = 1 pixel), uma malha por articulação (cabeça, tronco, braços, pernas, cabelo, olhos), com as cores do personagem; a arma 3D
# na mão direita e a armadura por cima, peça a peça: cada conjunto (`model` em armor_sets.json) veste cascas voxel (VoxRecipes.armor_set / armor_plate).
# Animação: respirar, piscar, andar (com balanço do corpo), pular, cair, nadar e golpear.

const HeldItem := preload("res://scripts/held_item.gd")

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
var grip: Node3D             # flail: pegada 3D na mão (no lugar do sprite)
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
	if player.get("cart") != null:   # sentado no carrinho: pernas esticadas para a frente
		parts.leg_l.rotation.x = 1.5
		parts.leg_r.rotation.x = 1.5
		parts.upper.rotation.x = 0.0
		arm = 0.9
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
	var flail_pose := id != -1 and grip != null and _flail_arm(delta)
	if flail_pose:
		pass   # o braço já foi posto por _flail_arm
	elif player.cooldown > 0 and id != -1:
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


# Braço com o flail: girando, sobe e faz círculos com a bola; solto, o chicote por cima da cabeça para a mira; fora, esticado. false = flail guardado.
func _flail_arm(delta: float) -> bool:
	var fs: String = player.flail_state()
	grip.get_node("tip/idle").visible = fs == ""
	var snap: float = player.flail_snap
	var twist := 0.0
	if snap > 0.0:
		var u: float = 1.0 - snap / 0.3
		parts.arm_r.rotation.x = lerpf(2.9, 1.4, ease(u, 0.4))
		parts.arm_r.rotation.z = lerpf(0.5, -0.1, u)
		twist = lerpf(-0.3, 0.3, ease(u, 0.5))
	elif fs == "spin":
		var s: float = player.flail.spin
		parts.arm_r.rotation.x = 2.3 + 0.35 * sin(s)
		parts.arm_r.rotation.z = 0.25 + 0.4 * cos(s)
		twist = 0.15 * cos(s)
	elif fs != "":
		parts.arm_r.rotation.x = 1.5
		parts.arm_r.rotation.z = 0.1
	else:
		return false
	parts.upper.rotation.y = lerpf(parts.upper.rotation.y, twist, minf(1.0, delta * 20.0))
	return true


# Ponta do cabo (de onde sai a corrente da bola), no mundo.
func flail_tip() -> Vector3:
	return grip.get_node("tip").global_position if grip else global_position


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
	if grip:
		grip.queue_free()
		grip = null
	if id == -1:
		return
	if Items.defs[id].has("flail"):   # pegada 3D no lugar do sprite: o cabo sai da mão no sentido do braço
		held.mesh = null
		trail_on = false
		held.transform = Transform3D(Basis(Vector3.RIGHT, PI), Vector3(0, -0.5, 0))
		grip = Projectile.flail_grip(player.entities.projectiles[Items.defs[id].flail], 2.1, (Basis(Vector3.RIGHT, 0.8) * held.transform.basis).inverse() * Vector3.DOWN)
		held.add_child(grip)
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


# Armadura por cima do corpo: cada peça vira uma casca voxel do conjunto (`model` em armor_sets.json; scripts/voxel/recipes.gd).
func _dress() -> void:
	for list in shells.values():
		for m in list:
			m.queue_free()
	shells.clear()
	spark_node = null
	for n in hair_nodes:
		n.visible = worn[0] < 0   # o cabelo não atravessa o capacete
	for e in eyes:
		e.visible = true
	for k in Inventory.ARMOR.size():
		var id: int = worn[k]
		var vset: String = Items.sets.get(Items.defs[id].get("set", ""), {}).get("model", "") if id >= 0 else ""
		if vset != "":
			_vox_shell(Inventory.ARMOR[k], vset)
			var spec: Dictionary = VoxRecipes.specs().get(vset, {})
			if Inventory.ARMOR[k] == "head" and (spec.get("recipe") == "armor_set" or spec.get("closed", false)):
				for e in eyes:
					e.visible = false   # capacete fechado: os olhos do rosto ficariam no mesmo plano da casca (z-fighting); o capacete traz os seus


# Casca voxel de `vset` para o espaço `slot`: uma malha por articulação que a peça cobre, com o encaixe no pivô. false se o modelo não existe.
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
		if t[0] != "head" and t[0] != "body":
			mi.scale = Vector3.ONE * 1.03   # braço e perna invadem a casca do tronco com faces no mesmo plano (ombreira × gola, cós × coxa): sem isto elas brigam (z-fighting) e piscam listras
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
