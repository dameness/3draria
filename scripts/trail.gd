class_name Trail
extends MeshInstance3D
# Arco do golpe: uma fita entre a base e a ponta da lâmina, guardada em espaço global, que esmaece em LIFE segundos. Serve à
# mão em 1ª pessoa (held_item.gd) e ao boneco em 3ª (player_model.gd): quem usa só chama push() a cada quadro do golpe.

const LIFE := 0.17

var color := Color(0.92, 0.96, 1.0)
var alpha := 0.42
var pts: Array = []   # [ponta, base, tempo]
var im := ImmediateMesh.new()


func _init() -> void:
	top_level = true
	mesh = im
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.vertex_color_use_as_albedo = true
	material_override = m
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func push(tip: Vector3, base: Vector3) -> void:
	pts.append([tip, base, Time.get_ticks_msec() / 1000.0])


func _process(_delta: float) -> void:
	if pts.is_empty():
		return
	var now := Time.get_ticks_msec() / 1000.0
	pts = pts.filter(func(p): return now - p[2] < LIFE)
	im.clear_surfaces()
	if pts.size() < 2:
		return
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for p in pts:
		var a: float = alpha * (1.0 - (now - p[2]) / LIFE)
		im.surface_set_color(Color(color, a))
		im.surface_add_vertex(p[0])
		im.surface_set_color(Color(color, a * 0.12))
		im.surface_add_vertex(p[1])
	im.surface_end()
