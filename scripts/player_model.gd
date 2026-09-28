extends Node3D
# Corpo do jogador em blocos (visto em 3ª pessoa): cabeça, tronco, braços e pernas com articulações,
# animação de andar e de uso do item, a arma 3D na mão direita e a armadura vestida por cima.
# Armadura: uma "casca" um pouco maior sobre cada parte, com as cores do sprite da peça.

const SHOES := Color("#5a3a2a")

@export var player: Node3D           # jogador ou inimigo humanoide (usa velocity; held/inv/pitch se existirem)
var skin := Color("#e8b890")
var hair := Color("#4a2e1a")
var shirt := Color("#b04a3a")
var pants := Color("#3a4a8a")
var arms_forward := false            # zumbi
var parts := {}      # nome -> pivô (Node3D) na articulação
var shells := {}     # slot de armadura -> [MeshInstance3D]
var held: MeshInstance3D
var held_id := -2
var worn := PackedInt32Array([-2, -2, -2])
var phase := 0.0


func _ready() -> void:
	# [nome, pivô (articulação), tamanho, cor, deslocamento da caixa a partir do pivô]
	for p in [["leg_l", Vector3(-0.12, 0.75, 0), Vector3(0.22, 0.75, 0.24), pants, Vector3(0, -0.375, 0)],
			["leg_r", Vector3(0.12, 0.75, 0), Vector3(0.22, 0.75, 0.24), pants, Vector3(0, -0.375, 0)],
			["torso", Vector3(0, 0.75, 0), Vector3(0.46, 0.6, 0.26), shirt, Vector3(0, 0.3, 0)],
			["head", Vector3(0, 1.35, 0), Vector3(0.44, 0.44, 0.44), skin, Vector3(0, 0.22, 0)],
			["arm_l", Vector3(-0.32, 1.32, 0), Vector3(0.18, 0.62, 0.18), skin, Vector3(0, -0.28, 0)],
			["arm_r", Vector3(0.32, 1.32, 0), Vector3(0.18, 0.62, 0.18), skin, Vector3(0, -0.28, 0)]]:
		var pivot := Node3D.new()
		pivot.position = p[1]
		add_child(pivot)
		parts[p[0]] = pivot
		pivot.add_child(_box(p[2], p[3], p[4]))
	for leg in ["leg_l", "leg_r"]:
		parts[leg].add_child(_box(Vector3(0.23, 0.12, 0.28), SHOES, Vector3(0, -0.69, -0.02)))
	for arm in ["arm_l", "arm_r"]:
		parts[arm].add_child(_box(Vector3(0.19, 0.24, 0.19), shirt, Vector3(0, -0.1, 0)))  # manga
	var head: Node3D = parts.head
	head.add_child(_box(Vector3(0.46, 0.16, 0.46), hair, Vector3(0, 0.38, 0.01)))
	head.add_child(_box(Vector3(0.46, 0.3, 0.1), hair, Vector3(0, 0.28, 0.2)))
	for x in [-0.1, 0.1]:
		head.add_child(_box(Vector3(0.08, 0.06, 0.02), Color.WHITE, Vector3(x, 0.24, -0.225)))
		head.add_child(_box(Vector3(0.04, 0.06, 0.02), Color("#2a4aa0"), Vector3(x + 0.02, 0.24, -0.23)))
	held = MeshInstance3D.new()
	parts.arm_r.add_child(held)


static func _box(size: Vector3, color: Color, offset: Vector3) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.9
	b.material = mat
	m.mesh = b
	m.position = offset
	return m


func _process(delta: float) -> void:
	if player == null:
		player = get_parent().get_parent() if get_parent() else null  # modelo de inimigo: dono é o avô
		if player == null:
			return
	var speed := Vector2(player.velocity.x, player.velocity.z).length()
	phase += delta * speed * 2.2
	var swing := sin(phase) * clampf(speed / 4.5, 0, 1) * 0.8
	parts.leg_l.rotation.x = swing
	parts.leg_r.rotation.x = -swing
	parts.arm_l.rotation.x = -swing * 0.8
	if arms_forward:
		parts.arm_l.rotation.x = -PI / 2 + swing * 0.2
		parts.arm_r.rotation.x = -PI / 2 - swing * 0.2
		return
	parts.head.rotation.x = player.pitch * 0.6
	var id: int = player.held()
	var dur: float = Items.defs[id].get("use_time", 0.25) if id != -1 else 0.25
	var t: float = clampf(1.0 - player.cooldown / dur, 0, 1) if player.cooldown > 0 else 1.0
	# braço da arma: golpe de cima para baixo durante o uso; parado, um pouco à frente
	parts.arm_r.rotation.x = lerpf(-2.6, -0.3, ease(t, 0.5)) if player.cooldown > 0 else swing * 0.8 - 0.3
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
	held.transform = Transform3D(Basis(Vector3.RIGHT, -PI / 4) * Basis(Vector3.BACK, deg_to_rad(90.0 - ang)), Vector3(0, -0.58, 0))


# Cores da peça tiradas do sprite: média da metade mais clara dos pixels (o contorno escuro do
# Terraria deixaria tudo apagado) e a média do quarto seguinte para os detalhes.
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
		return [Color.GRAY, Color.DIM_GRAY]
	px.sort_custom(func(a, b): return a.get_luminance() > b.get_luminance())
	return [_avg(px.slice(0, maxi(1, px.size() / 2))), _avg(px.slice(px.size() / 2, maxi(px.size() / 2 + 1, px.size() * 3 / 4)))]


static func _avg(list: Array) -> Color:
	var sum := Color(0, 0, 0, 0)
	for c in list:
		sum += c
	sum /= list.size()
	sum.a = 1.0
	return sum


func _dress() -> void:
	for list in shells.values():
		for m in list:
			m.queue_free()
	shells.clear()
	for k in Inventory.ARMOR.size():
		var id: int = worn[k]
		if id == -1:
			continue
		var c := _colors(id)
		# [parte, tamanho, cor, deslocamento] das cascas de cada slot
		var pieces: Array = {
			"head": [["head", Vector3(0.5, 0.3, 0.5), c[0], Vector3(0, 0.34, 0)], ["head", Vector3(0.52, 0.06, 0.52), c[1], Vector3(0, 0.2, 0)]],
			"body": [["torso", Vector3(0.5, 0.64, 0.3), c[0], Vector3(0, 0.3, 0)], ["arm_l", Vector3(0.22, 0.3, 0.22), c[1], Vector3(0, -0.1, 0)],
				["arm_r", Vector3(0.22, 0.3, 0.22), c[1], Vector3(0, -0.1, 0)]],
			"legs": [["leg_l", Vector3(0.25, 0.6, 0.27), c[0], Vector3(0, -0.3, 0)], ["leg_r", Vector3(0.25, 0.6, 0.27), c[0], Vector3(0, -0.3, 0)]],
		}[Inventory.ARMOR[k]]
		var list := []
		for p in pieces:
			var m := _box(p[1], p[2], p[3])
			parts[p[0]].add_child(m)
			list.append(m)
		shells[Inventory.ARMOR[k]] = list
