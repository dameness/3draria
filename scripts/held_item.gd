extends Node3D
# O item da mão em 3D (visão em 1ª pessoa) e o braço do personagem que o segura, animados pelo estilo de uso:
# swing (golpe em arco), thrust (estocada), shoot (recuo), hold (parado). Filho da câmera.
# A mão tem inércia (fica para trás ao girar a câmera), balança ao andar e dá um empurrão ao colocar bloco.
# Efeitos do item ("effects" em items.json): glow (halo aditivo com a silhueta), trail (arco do golpe), particles (faíscas).
# Toda arma de golpe deixa um arco pálido (Trail), na cor de effects.trail se o item tiver.

const REST := Vector3(0.34, -0.36, -0.62)  # posição da mão em relação à câmera
const LENGTH := 0.42                       # tamanho do maior lado do item, em blocos
const SHOULDER := Vector3(0.55, -1.0, 0.4)    # o ombro (no espaço da câmera) fica fora da tela: o braço vem do canto de baixo à direita
const PLACE_TIME := 0.18                   # duração do empurrão ao colocar bloco (player.gd place_anim)

@export var player: Node3D

var mesh: MeshInstance3D
var shown := -2
var glow: MeshInstance3D
var sparks: CPUParticles3D
var trail: Trail
var trail_on := false          # o item atual deixa arco
var arm: Node3D
var skin_mat: StandardMaterial3D
var sleeve_mat: StandardMaterial3D
var sway := Vector2.ZERO       # deslocamento da mão pela rotação da câmera (yaw, pitch)
var last_yaw := 0.0
var last_pitch := 0.0


func _ready() -> void:
	mesh = MeshInstance3D.new()
	add_child(mesh)
	trail = Trail.new()
	add_child(trail)
	_build_arm()
	position = REST


# Braço em 1ª pessoa: punho na mão (o cabo do item fica nele) e antebraço + manga esticados até o ombro, que fica fixo na câmera:
# a cada quadro o braço gira para o ombro, então a mão balança no golpe sem soltar do corpo.
func _build_arm() -> void:
	arm = Node3D.new()
	arm.top_level = true
	add_child(arm)
	skin_mat = _lit(Color("#f0b890"))
	sleeve_mat = _lit(Color("#c0503c"))
	for part in [[0.043, 0.34, 0.15, skin_mat], [0.06, 1.6, 1.07, sleeve_mat]]:   # raio, comprimento, centro ao longo do braço
		var c := CapsuleMesh.new()
		c.radius = part[0]
		c.height = part[1]
		c.radial_segments = 12
		c.rings = 4
		var mi := MeshInstance3D.new()
		mi.mesh = c
		mi.material_override = part[3]
		mi.position = Vector3(0, part[2], 0)
		arm.add_child(mi)
	var fist := SphereMesh.new()
	fist.radius = 0.062
	fist.height = 0.124
	fist.radial_segments = 12
	fist.rings = 6
	var f := MeshInstance3D.new()
	f.mesh = fist
	f.material_override = skin_mat
	arm.add_child(f)


static func _lit(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.85
	return m


# Estilo de uso: campo "use_style" do item, senão deduzido (munição → shoot, arma/ferramenta → swing).
static func style(id: int) -> String:
	var d: Dictionary = Items.defs[id]
	if d.has("use_style"):
		return d.use_style
	if d.has("ammo"):
		return "shoot"
	if d.get("damage", 0) > 0 or Items.pick_power[id] > 0 or Items.axe_power[id] > 0 or d.has("bucket"):
		return "swing"
	return "hold"


# Pose da mão para o estilo em t (0 = início do uso, 1 = fim). Fora do uso: descanso.
static func pose(st: String, t: float) -> Transform3D:
	var tr := Transform3D(Basis(), REST)
	match st:
		"swing":
			tr.basis = Basis(Vector3.RIGHT, lerpf(0.9, -1.3, ease(t, 0.5)))
		"thrust":
			tr.origin += Vector3(-0.1, 0.08, -0.35) * sin(PI * t)
		"shoot":
			tr.origin += Vector3(0, 0, 0.08) * (1.0 - t)
	return tr


func _process(delta: float) -> void:
	_sync_arm()
	var id: int = player.held()
	if id != shown:
		shown = id
		mesh.visible = id != -1
		if id != -1:
			_show(id)
	var st := style(id) if id != -1 else "hold"
	var dur: float = Items.defs[id].get("use_time", 0.25) if id != -1 else 0.25
	var t: float = 1.0 - player.cooldown / dur if player.cooldown > 0 else 1.0
	var tr := pose(st, clampf(t, 0, 1))
	# inércia ao girar a câmera, balanço ao andar e o empurrão de colocar bloco
	var yaw: float = player.rotation.y
	var vel := Vector2(wrapf(yaw - last_yaw, -PI, PI), player.pitch - last_pitch) / maxf(delta, 0.001)
	last_yaw = yaw
	last_pitch = player.pitch
	sway = sway.lerp((vel * 0.012).limit_length(0.22), 1.0 - exp(-10.0 * delta))
	tr.origin += Vector3(sway.x, -sway.y, 0) * 0.9
	tr.basis = Basis(Vector3.UP, sway.x * 0.6) * Basis(Vector3.RIGHT, -sway.y * 0.6) * tr.basis
	var walk: float = clampf(Vector2(player.velocity.x, player.velocity.z).length() / player.WALK, 0.0, 1.4) if player.on_floor and not player.flying else 0.0
	tr.origin += Vector3(cos(player.bob * 0.5) * 0.012, -absf(sin(player.bob)) * 0.02, 0) * walk
	if player.place_anim > 0.0:
		tr.origin += Vector3(0, 0.03, -0.14) * sin(PI * (1.0 - player.place_anim / PLACE_TIME))
	transform = tr
	var cam: Node3D = get_parent()
	var to_shoulder: Vector3 = (cam.global_transform * SHOULDER - global_position).normalized()
	arm.global_transform = Transform3D(Basis(Quaternion(Vector3.UP, to_shoulder)), global_position)
	if id == -1:
		return
	var using: bool = player.cooldown > 0
	if sparks:
		sparks.emitting = using
	if using and trail_on:
		var box: AABB = mesh.mesh.get_aabb()
		trail.push(mesh.global_transform * box.end, mesh.global_transform * (box.position + box.size * 0.6))


# Cores do braço: as do personagem (pele e camiseta do PlayerModel).
func _sync_arm() -> void:
	var model: Node = player.get_node_or_null("Model")
	if model and model.skin != skin_mat.albedo_color:
		skin_mat.albedo_color = model.skin
		sleeve_mat.albedo_color = model.shirt


func _additive(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = false
	m.albedo_color = c
	return m


func _show(id: int) -> void:
	var st := style(id)
	var m := ItemModel.for_item(id, player.entities.icon(id), LENGTH if st != "hold" else LENGTH * 0.5)
	mesh.mesh = m[0]
	mesh.material_override = m[1]
	# Gira a direção do sprite (sprite_angle; armas do Terraria: 45° = cima-direita) para cima,
	# com o cabo na mão; arco e o resto ficam centrados.
	var aabb: AABB = m[0].get_aabb()
	for n in [glow, sparks]:
		if n:
			n.queue_free()
	glow = null
	sparks = null
	var fx: Dictionary = Items.defs[id].get("effects", {})
	trail_on = fx.has("trail") or (st in ["swing", "thrust"] and Items.defs[id].get("damage", 0) > 0 and Items.pick_power[id] == 0 and Items.axe_power[id] == 0)
	trail.color = Color(fx.trail) if fx.has("trail") else Color(0.92, 0.96, 1.0)
	if fx.has("glow"):
		glow = MeshInstance3D.new()
		glow.mesh = m[0]
		var gm := _additive(Color(Color(fx.glow), 0.45))
		gm.albedo_texture = m[1].albedo_texture  # usa a transparência do sprite: o halo segue a silhueta
		gm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		glow.material_override = gm
		var c := aabb.get_center()
		glow.transform = Transform3D(Basis().scaled(Vector3.ONE * 1.15), c - c * 1.15)
		mesh.add_child(glow)
	if fx.has("particles"):
		sparks = CPUParticles3D.new()
		sparks.amount = 24
		sparks.lifetime = 0.4
		sparks.local_coords = false
		sparks.emitting = false
		sparks.direction = Vector3.UP
		sparks.spread = 60
		sparks.initial_velocity_min = 0.3
		sparks.initial_velocity_max = 0.8
		sparks.gravity = Vector3(0, -0.5, 0)
		sparks.scale_amount_min = 0.5
		var q := QuadMesh.new()
		q.size = Vector2.ONE * 0.025
		var qm := _additive(Color(fx.particles))
		qm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		q.material = qm
		sparks.mesh = q
		sparks.position = aabb.end * 0.9
		mesh.add_child(sparks)
	match st:
		"swing", "thrust":
			var ang: float = Items.defs[id].get("sprite_angle", 45.0)
			mesh.transform = Transform3D(Basis(Vector3.BACK, deg_to_rad(90.0 - ang)), Vector3.ZERO)
			mesh.rotate_object_local(Vector3.UP, deg_to_rad(-25))
		_:
			mesh.transform = Transform3D(Basis(Vector3.UP, deg_to_rad(-25)), -aabb.get_center().rotated(Vector3.UP, deg_to_rad(-25)))
