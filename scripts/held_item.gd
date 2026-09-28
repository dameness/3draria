extends Node3D
# O item da mão em 3D (visão em 1ª pessoa), com animação pelo estilo de uso:
# swing (golpe em arco), thrust (estocada), shoot (recuo), hold (parado). Filho da câmera.
# Efeitos do item ("effects" em items.json): glow (halo aditivo com a silhueta), trail (rastro do golpe),
# particles (faíscas saindo da ponta durante o uso).

const REST := Vector3(0.34, -0.36, -0.62)  # posição da mão em relação à câmera
const LENGTH := 0.42                       # tamanho do maior lado do item, em blocos

@export var player: Node3D
const TRAIL_TIME := 0.12   # segundos de rastro visível

var mesh: MeshInstance3D
var shown := -2
var glow: MeshInstance3D
var sparks: CPUParticles3D
var trail: MeshInstance3D
var trail_mesh: ImmediateMesh
var trail_color := Color.TRANSPARENT
var trail_points: Array = []   # [ponta, meio, tempo] no espaço da câmera


func _ready() -> void:
	mesh = MeshInstance3D.new()
	add_child(mesh)
	trail = MeshInstance3D.new()
	trail_mesh = ImmediateMesh.new()
	trail.mesh = trail_mesh
	trail.material_override = _additive(Color.WHITE)
	trail.material_override.vertex_color_use_as_albedo = true
	get_parent().add_child.call_deferred(trail)
	position = REST


# Estilo de uso: campo "use_style" do item, senão deduzido (munição → shoot, arma/ferramenta → swing).
static func style(id: int) -> String:
	var d: Dictionary = Items.defs[id]
	if d.has("use_style"):
		return d.use_style
	if d.has("ammo"):
		return "shoot"
	if d.get("damage", 0) > 0 or Items.pick_power[id] > 0:
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


func _process(_delta: float) -> void:
	var id: int = player.held()
	if id != shown:
		shown = id
		mesh.visible = id != -1
		if id != -1:
			_show(id)
	if id == -1:
		return
	var st := style(id)
	var dur: float = Items.defs[id].get("use_time", 0.25)
	var t: float = 1.0 - player.cooldown / dur if player.cooldown > 0 else 1.0
	transform = pose(st, clampf(t, 0, 1))
	var using: bool = player.cooldown > 0
	if sparks:
		sparks.emitting = using
	_update_trail(using)


func _update_trail(using: bool) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if using and trail_color.a > 0:
		var box: AABB = mesh.mesh.get_aabb()
		var to_cam := transform * mesh.transform
		trail_points.append([to_cam * box.end, to_cam * (box.position + box.size * 0.75), now])
	trail_points = trail_points.filter(func(p): return now - p[2] < TRAIL_TIME)
	trail_mesh.clear_surfaces()
	if trail_points.size() < 2:
		return
	trail_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for p in trail_points:
		trail_mesh.surface_set_color(Color(trail_color, 0.35 * (1.0 - (now - p[2]) / TRAIL_TIME)))
		trail_mesh.surface_add_vertex(p[0])
		trail_mesh.surface_add_vertex(p[1])
	trail_mesh.surface_end()


static func _additive(c: Color) -> StandardMaterial3D:
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
	trail_color = Color(fx.trail) if fx.has("trail") else Color.TRANSPARENT
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
