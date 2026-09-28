class_name EnemyModel
# Modelos 3D dos inimigos, escolhidos por "model" em enemies.json:
#   eye      esfera com veias, íris, pupila e tentáculos (Olho de Cthulhu, olho demoníaco, servos);
#            set_phase(2) troca a íris por uma boca com dentes.
#   slime    gelatina translúcida com núcleo; achata/estica com a velocidade vertical.
#   humanoid corpo do jogador (player_model.gd) com as cores de "colors" e braços estendidos.
#   (outro)  sprite da wiki extrudado com espessura; sem sprite, caixa colorida.
# A frente de todos é -Z; enemy.gd gira o nó para o jogador.

const PlayerModel := preload("res://scripts/player_model.gd")


static func build(def: Dictionary) -> Node3D:
	var root := Node3D.new()
	var size: Array = def.size
	match def.get("model", ""):
		"eye":
			_eye(root, size[1] / 2.0, def)
		"slime":
			_slime(root, size, Color(def.color))
		"humanoid":
			var body: Node3D = PlayerModel.new()
			var c: Dictionary = def.get("colors", {})
			body.skin = Color(c.get("skin", "#6a9a5a"))
			body.shirt = Color(c.get("shirt", "#4a5a7a"))
			body.pants = Color(c.get("pants", "#3a3a4a"))
			body.hair = Color(c.get("hair", "#2a3a2a"))
			body.arms_forward = true
			body.scale = Vector3.ONE * size[1] / 1.8
			body.name = "Body"
			root.add_child(body)
		_:
			var tex: Texture2D = null
			var spec: Dictionary = Blocks.textures.get(def.get("sprite", ""), {})
			var img := Atlas.wiki_image(spec)
			if img:
				var m := MeshInstance3D.new()
				m.mesh = ItemModel.build(img, maxf(size[1], size[0]), img.get_width() * 0.25)
				m.material_override = _mat(Color.WHITE)
				m.material_override.albedo_texture = ImageTexture.create_from_image(img)
				m.material_override.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
				m.material_override.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
				m.material_override.vertex_color_use_as_albedo = true
				var box: AABB = m.mesh.get_aabb()
				m.position = Vector3(-box.get_center().x, 0, -box.get_center().z)
				root.add_child(m)
			else:
				_part(root, BoxMesh.new(), Vector3(size[0], size[1], size[0]), Color(def.color), Vector3(0, size[1] / 2.0, 0))
	return root


static func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.6
	return m


static func _part(parent: Node3D, mesh: PrimitiveMesh, size: Vector3, c: Color, pos: Vector3, mat: Material = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.scale = size
	if mesh is BoxMesh:
		mesh.size = Vector3.ONE
	elif mesh is SphereMesh:
		mesh.radius = 0.5
		mesh.height = 1.0
	elif mesh is CylinderMesh:
		mesh.top_radius = 0.5
		mesh.bottom_radius = 0.5
		mesh.height = 1.0
	mi.material_override = mat if mat else _mat(c)
	mi.position = pos
	parent.add_child(mi)
	return mi


# Textura de globo ocular: branco com veias vermelhas (passeios aleatórios), mais densas atrás.
static func _veins(seed: int) -> ImageTexture:
	var img := Image.create(64, 32, false, Image.FORMAT_RGBA8)
	img.fill(Color("#f2ebe6"))
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	for v in 14:
		var p := Vector2(rng.randf_range(0, 64), rng.randf_range(0, 32))
		var dir := Vector2.from_angle(rng.randf() * TAU)
		for s in 30:
			img.set_pixelv(Vector2i(posmod(int(p.x), 64), clampi(int(p.y), 0, 31)), Color("#c0262a"))
			dir = dir.rotated(rng.randf_range(-0.6, 0.6))
			p += dir
	return ImageTexture.create_from_image(img)


static func _eye(root: Node3D, r: float, def: Dictionary) -> void:
	var pivot := Node3D.new()  # gira inteiro para olhar o jogador
	pivot.name = "Look"
	pivot.position.y = r
	root.add_child(pivot)
	var ball_mat := _mat(Color.WHITE)
	ball_mat.albedo_texture = _veins(hash(def.name))
	_part(pivot, SphereMesh.new(), Vector3.ONE * r * 2, Color.WHITE, Vector3.ZERO, ball_mat)
	var iris := Node3D.new()
	iris.name = "Iris"
	pivot.add_child(iris)
	_part(iris, SphereMesh.new(), Vector3(r * 1.0, r * 1.0, r * 0.3), Color(def.get("iris", "#3a5aa0")), Vector3(0, 0, -r * 0.9))
	_part(iris, SphereMesh.new(), Vector3(r * 0.45, r * 0.45, r * 0.2), Color("#0a0a10"), Vector3(0, 0, -r * 1.0))
	var mouth := Node3D.new()
	mouth.name = "Mouth"
	mouth.visible = false
	pivot.add_child(mouth)
	_part(mouth, SphereMesh.new(), Vector3(r * 1.3, r * 1.3, r * 0.35), Color("#5a0a10"), Vector3(0, 0, -r * 0.85))
	for i in 10:
		var a := TAU * i / 10.0
		var tooth := _part(mouth, BoxMesh.new(), Vector3(r * 0.14, r * 0.3, r * 0.14), Color("#f0ecd8"), Vector3(cos(a) * r * 0.55, sin(a) * r * 0.55, -r * 1.0))
		tooth.rotation.z = a + PI / 2
	for i in 5:  # tentáculos atrás
		var a := TAU * i / 5.0
		var t := _part(pivot, CylinderMesh.new(), Vector3(r * 0.12, r * 1.2, r * 0.12), Color("#b0202a"), Vector3(cos(a) * r * 0.45, sin(a) * r * 0.45, r * 1.3))
		t.rotation.x = PI / 2
		t.name = "Tendril%d" % i


static func _slime(root: Node3D, size: Array, c: Color) -> void:
	var body := Node3D.new()
	body.name = "Squash"
	root.add_child(body)
	var gel := _mat(Color(c, 0.72))
	gel.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gel.roughness = 0.2
	_part(body, SphereMesh.new(), Vector3(size[0], size[1] * 1.3, size[0]), c, Vector3(0, size[1] * 0.65, 0), gel)
	_part(body, SphereMesh.new(), Vector3(size[0], size[1], size[0]) * 0.35, c.darkened(0.5), Vector3(0, size[1] * 0.6, 0))
	_part(body, SphereMesh.new(), Vector3.ONE * size[0] * 0.18, Color(1, 1, 1, 1), Vector3(-size[0] * 0.2, size[1] * 1.0, -size[0] * 0.2))


# Animações por quadro: olho encara o jogador e mexe os tentáculos; slime estica com o pulo.
static func animate(model: Node3D, enemy: Node3D, target: Vector3, t: float) -> void:
	var look := model.get_node_or_null("Look")
	if look and look.is_inside_tree() and look.global_position.distance_to(target) > 0.1:
		look.look_at(target, Vector3.UP)
		for i in 5:
			var ten: Node3D = look.get_node("Tendril%d" % i)
			ten.rotation.y = sin(t * 6.0 + i) * 0.25
	var squash := model.get_node_or_null("Squash")
	if squash:
		var k := clampf(enemy.velocity.y / 10.0, -0.3, 0.35)
		squash.scale = Vector3(1.0 - k * 0.5, 1.0 + k, 1.0 - k * 0.5)


static func set_phase(model: Node3D, phase: int) -> void:
	var look := model.get_node_or_null("Look")
	if look:
		look.get_node("Iris").visible = phase == 1
		look.get_node("Mouth").visible = phase == 2
