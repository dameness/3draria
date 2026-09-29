class_name Fx
# Partículas por código, como a poeira do Terraria: quadradinhos que sobem, caem e esmaecem. Cada evento cria um CPUParticles3D
# de um disparo (poucas dezenas de partículas) que se apaga sozinho; malhas e materiais são compartilhados.
#   dust    nuvem de pó na cor do bloco (a cada golpe da picareta)   chips   lascas que caem (ao quebrar)
#   sparks  faíscas aditivas (pedra e minério, arma acertando)        blood   gotas (a cor vem do inimigo)
#   puff    nuvem grande (morte)   splash  respingo d'água   bubbles  bolhas subindo debaixo d'água
# `parent` é o nó que recebe os disparos (entities.gd); fora da árvore (testes) nada é criado.

static var _quads := {}    # tamanho -> QuadMesh (com o material)
static var _shrink: Curve
static var _fade: Gradient


static func _mesh(size: float, additive: bool) -> QuadMesh:
	var key := [size, additive]
	if not _quads.has(key):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.vertex_color_use_as_albedo = true
		m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		if additive:
			m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		var q := QuadMesh.new()
		q.size = Vector2.ONE * size
		q.material = m
		_quads[key] = q
	return _quads[key]


# Disparo de `n` partículas em `pos`. Opções: size, life, speed (máxima; a mínima é metade), spread (graus em torno de dir),
# dir, gravity (positivo = cai), additive, shrink (encolhe ao longo da vida; padrão sim).
static func burst(parent: Node3D, pos: Vector3, color: Color, n: int, o := {}) -> CPUParticles3D:
	if parent == null or not parent.is_inside_tree():
		return null
	if _shrink == null:
		_shrink = Curve.new()
		_shrink.add_point(Vector2(0, 1))
		_shrink.add_point(Vector2(1, 0.15))
		_fade = Gradient.new()
		_fade.offsets = PackedFloat32Array([0.0, 0.6, 1.0])
		_fade.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.9), Color(1, 1, 1, 0)])
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.emitting = false
	p.explosiveness = 1.0
	p.amount = n
	p.lifetime = o.get("life", 0.6)
	p.local_coords = false
	p.mesh = _mesh(o.get("size", 0.1), o.get("additive", false))
	p.color = color
	p.color_ramp = _fade
	p.direction = o.get("dir", Vector3.UP)
	p.spread = o.get("spread", 70.0)
	p.initial_velocity_min = o.get("speed", 2.0) * 0.5
	p.initial_velocity_max = o.get("speed", 2.0)
	p.gravity = Vector3(0, -o.get("gravity", 9.0), 0)
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.4
	if o.get("shrink", true):
		p.scale_amount_curve = _shrink
	p.position = pos
	parent.add_child(p)
	p.emitting = true
	p.finished.connect(p.queue_free)
	return p


static func dust(parent: Node3D, pos: Vector3, color: Color, n := 5, dir := Vector3.UP) -> void:
	burst(parent, pos, color, n, {"size": 0.17, "life": 0.6, "speed": 1.8, "spread": 80.0, "gravity": 3.0, "dir": dir})


static func chips(parent: Node3D, pos: Vector3, color: Color, n := 10) -> void:
	burst(parent, pos, color, n, {"size": 0.1, "life": 0.75, "speed": 3.6, "spread": 100.0, "gravity": 14.0})
	burst(parent, pos, color.lightened(0.15), n / 2, {"size": 0.2, "life": 0.6, "speed": 1.4, "spread": 180.0, "gravity": 1.0})


static func sparks(parent: Node3D, pos: Vector3, color := Color("#ffd060"), n := 6, dir := Vector3.UP) -> void:
	burst(parent, pos, color, n, {"size": 0.07, "life": 0.32, "speed": 4.5, "spread": 60.0, "gravity": 10.0, "additive": true, "dir": dir})


static func blood(parent: Node3D, pos: Vector3, color: Color, n := 8, dir := Vector3.UP) -> void:
	burst(parent, pos, color, n, {"size": 0.11, "life": 0.7, "speed": 4.0, "spread": 70.0, "gravity": 12.0, "dir": dir})


static func puff(parent: Node3D, pos: Vector3, color: Color, n := 14) -> void:
	burst(parent, pos, color, n, {"size": 0.34, "life": 0.85, "speed": 2.4, "spread": 180.0, "gravity": -0.4})
	burst(parent, pos, color.darkened(0.25), n, {"size": 0.12, "life": 0.9, "speed": 4.0, "spread": 180.0, "gravity": 10.0})


static func splash(parent: Node3D, pos: Vector3, n := 16) -> void:
	Sfx.play(parent, "splash", pos, -8.0)
	burst(parent, pos, Color("#9cc8ff"), n, {"size": 0.1, "life": 0.7, "speed": 4.6, "spread": 38.0, "gravity": 13.0})
	burst(parent, pos, Color(1, 1, 1, 0.9), n / 3, {"size": 0.16, "life": 0.5, "speed": 1.8, "spread": 90.0, "gravity": 1.0})


static func bubbles(parent: Node3D, pos: Vector3, n := 3) -> void:
	burst(parent, pos, Color(0.85, 0.95, 1.0, 0.8), n, {"size": 0.08, "life": 0.9, "speed": 0.6, "spread": 40.0, "gravity": -1.6, "shrink": false})
