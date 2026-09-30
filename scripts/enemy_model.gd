class_name EnemyModel
# Modelos 3D dos inimigos, escolhidos por "model" em enemies.json:
#   eye      esfera com veias, íris, pupila e tentáculos (Olho de Cthulhu, olho demoníaco, servos);
#            set_phase(2) troca a íris por uma boca com dentes.
#   slime    gelatina translúcida com núcleo; achata/estica com a velocidade vertical.
#   wall     coluna de carne (Wall of Flesh): olhos, boca com dentes e veias; a frente é -Z.
#   skull    caveira (Cursed Skull; "big" = Skeletron, com brilho vermelho nas órbitas)   hand  mão de osso (Skeletron).
#   hungry   The Hungry: bolha de carne rosada com lóbulos, boca de dentes na frente e a veia vermelha que a prende ao Muro (atrás).
#   brain    cérebro rosado com dobras, olhos e tentáculos (Brain of Cthulhu).
#   worm     segmento de verme (esfera com anéis; cabeça com mandíbula, rabo mais fino), centrado na origem; enemy.gd gira inteiro.
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
			_slime(root, size, Color(def.color), def)
		"worm":
			_worm(root, size[0], def)
		"hungry":
			_hungry(root, size, Color(def.color))
		"brain":
			_brain(root, size, Color(def.color))
		"skull":
			_skull(root, size[0], def)
		"wall":
			_wall(root, size)
		"hand":
			_hand(root, size[0], Color(def.color))
		"humanoid":
			var body: Node3D = PlayerModel.new()
			var c: Dictionary = def.get("colors", {})
			body.skin = Color(c.get("skin", "#6a9a5a"))
			body.shirt = Color(c.get("shirt", "#4a5a7a"))
			body.pants = Color(c.get("pants", "#3a3a4a"))
			body.hair = Color(c.get("hair", "#2a3a2a"))
			body.arms_forward = def.ai != "npc"   # zumbi de braços esticados; habitante de braços soltos
			body.townsfolk = def.ai == "npc"
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


# Wall of Flesh: coluna de carne (largura x altura), olhos com veias na parte de cima, boca com dentes embaixo e veias escuras.
static func _wall(root: Node3D, size: Array) -> void:
	var w: float = size[0]
	var h: float = size[1]
	var pulse := Node3D.new()
	pulse.name = "Pulse"
	root.add_child(pulse)
	var flesh := _mat(Color("#b83a4a"))
	flesh.roughness = 0.35
	flesh.rim_enabled = true
	flesh.rim = 0.5
	_part(pulse, BoxMesh.new(), Vector3(w, h, w * 0.3), Color("#b83a4a"), Vector3(0, h / 2.0, 0), flesh)
	var rng := RandomNumberGenerator.new()
	rng.seed = 113
	for i in 14:   # lóbulos e bolhas na superfície
		_part(pulse, SphereMesh.new(), Vector3.ONE * w * rng.randf_range(0.14, 0.3), Color("#c84a5a").darkened(rng.randf_range(0.0, 0.3)),
			Vector3(rng.randf_range(-0.45, 0.45) * w, rng.randf_range(0.05, 0.95) * h, -w * 0.13), flesh)
	var vein := _mat(Color("#5a0a18"))
	for i in 7:
		var v := _part(pulse, CylinderMesh.new(), Vector3(w * 0.03, h * rng.randf_range(0.3, 0.6), w * 0.03), Color("#5a0a18"), Vector3(rng.randf_range(-0.45, 0.45) * w, rng.randf_range(0.2, 0.8) * h, -w * 0.16), vein)
		v.rotation.z = rng.randf_range(-0.3, 0.3)
	for side in [-1, 1]:   # olhos
		var ball := _mat(Color.WHITE)
		ball.albedo_texture = _veins(113 + side)
		_part(pulse, SphereMesh.new(), Vector3.ONE * w * 0.27, Color.WHITE, Vector3(side * w * 0.24, h * 0.66, -w * 0.2), ball)
		_part(pulse, SphereMesh.new(), Vector3(w * 0.13, w * 0.13, w * 0.06), Color("#b01820"), Vector3(side * w * 0.24, h * 0.66, -w * 0.33))
		_part(pulse, SphereMesh.new(), Vector3(w * 0.06, w * 0.06, w * 0.04), Color("#0a0a10"), Vector3(side * w * 0.24, h * 0.66, -w * 0.36))
	var mouth := _mat(Color("#3a0810"))
	_part(pulse, BoxMesh.new(), Vector3(w * 0.7, h * 0.16, w * 0.06), Color("#3a0810"), Vector3(0, h * 0.3, -w * 0.16), mouth)
	for i in 12:
		var x := (i - 5.5) * w * 0.055
		_part(pulse, BoxMesh.new(), Vector3(w * 0.03, h * 0.05, w * 0.03), Color("#f4ecd8"), Vector3(x, h * 0.36, -w * 0.19))
		_part(pulse, BoxMesh.new(), Vector3(w * 0.03, h * 0.05, w * 0.03), Color("#f4ecd8"), Vector3(x, h * 0.24, -w * 0.19))


# Caveira centrada na origem, de frente para -Z: crânio, mandíbula com dentes, órbitas escuras (com brilho se "big") e nariz.
static func _skull(root: Node3D, w: float, def: Dictionary) -> void:
	var c := Color(def.color)
	var r := w / 2.0
	var pivot := Node3D.new()
	pivot.position.y = def.size[1] / 2.0
	pivot.name = "Squash"
	root.add_child(pivot)
	var bone := _mat(c)
	bone.rim_enabled = true
	bone.rim = 0.4
	_part(pivot, SphereMesh.new(), Vector3(r * 2.0, r * 1.8, r * 2.0), c, Vector3(0, r * 0.1, 0), bone)
	_part(pivot, BoxMesh.new(), Vector3(r * 1.1, r * 0.5, r * 1.1), c.darkened(0.08), Vector3(0, -r * 0.85, -r * 0.35), bone)   # mandíbula
	for i in 5:
		_part(pivot, BoxMesh.new(), Vector3(r * 0.14, r * 0.22, r * 0.08), Color("#f4f0e0"), Vector3((i - 2) * r * 0.22, -r * 0.62, -r * 0.92))
	for side in [-1, 1]:
		_part(pivot, SphereMesh.new(), Vector3(r * 0.5, r * 0.55, r * 0.3), Color("#0a0a10"), Vector3(side * r * 0.42, r * 0.15, -r * 0.88))
		if def.get("big", false):
			var glow := StandardMaterial3D.new()
			glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			glow.albedo_color = Color("#ff3020")
			_part(pivot, SphereMesh.new(), Vector3.ONE * r * 0.16, Color.RED, Vector3(side * r * 0.42, r * 0.15, -r * 1.02), glow)
	_part(pivot, SphereMesh.new(), Vector3(r * 0.2, r * 0.3, r * 0.15), Color("#1a1a20"), Vector3(0, -r * 0.15, -r * 0.95))


# Mão de osso: palma, quatro dedos em leque e o polegar (para -Z, para o jogador).
static func _hand(root: Node3D, w: float, c: Color) -> void:
	var r := w / 2.0
	var pivot := Node3D.new()
	pivot.position.y = w / 2.0
	pivot.name = "Squash"
	root.add_child(pivot)
	var bone := _mat(c)
	_part(pivot, BoxMesh.new(), Vector3(r * 1.3, r * 0.4, r * 1.2), c, Vector3.ZERO, bone)
	for i in 4:
		var f := _part(pivot, CylinderMesh.new(), Vector3(r * 0.2, r * 1.0, r * 0.2), c.lightened(0.05), Vector3((i - 1.5) * r * 0.36, 0, -r * 1.05), bone)
		f.rotation = Vector3(PI / 2, 0, (i - 1.5) * 0.12)
	var thumb := _part(pivot, CylinderMesh.new(), Vector3(r * 0.22, r * 0.7, r * 0.22), c, Vector3(r * 0.85, 0, -r * 0.4), bone)
	thumb.rotation = Vector3(PI / 2, 0, -0.7)


# The Hungry (sprite da wiki: bolha de carne rosa-arroxeada com boca de barras vermelhas e a veia atrás): corpo achatado com lóbulos
# claros, boca com dentes em cima e embaixo na frente (-Z) e a veia (cilindros) saindo por trás.
static func _hungry(root: Node3D, size: Array, c: Color) -> void:
	var r: float = size[0] / 2.0
	var pivot := Node3D.new()
	pivot.name = "Squash"
	pivot.position.y = size[1] / 2.0
	root.add_child(pivot)
	var flesh := _mat(c)
	flesh.roughness = 0.35
	flesh.rim_enabled = true
	flesh.rim = 0.5
	_part(pivot, SphereMesh.new(), Vector3(r * 2.0, r * 1.8, r * 2.0), c, Vector3.ZERO, flesh)
	var rng := RandomNumberGenerator.new()
	rng.seed = 271
	for i in 9:   # lóbulos claros como as manchas do sprite
		var dir := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.6, 1), rng.randf_range(-0.2, 1)).normalized()
		_part(pivot, SphereMesh.new(), Vector3.ONE * r * rng.randf_range(0.35, 0.55), c.lightened(rng.randf_range(0.15, 0.35)), dir * r * 0.82, flesh)
	_part(pivot, SphereMesh.new(), Vector3(r * 1.25, r * 0.7, r * 0.4), Color("#2a0610"), Vector3(0, -r * 0.05, -r * 0.82), _mat(Color("#2a0610")))   # boca
	for row in [-1, 1]:
		for i in 5:
			var t := _part(pivot, BoxMesh.new(), Vector3(r * 0.12, r * 0.26, r * 0.1), Color("#f0e4d0"), Vector3((i - 2) * r * 0.24, -r * 0.05 + row * r * 0.3, -r * 1.0))
			t.rotation.z = row * 0.12 * (i - 2)
	var vein := _mat(Color("#b01820"))
	for i in 3:   # veia por trás, quebrando em degraus como no sprite
		var seg := _part(pivot, CylinderMesh.new(), Vector3(r * 0.16, r * 0.9, r * 0.16), Color("#b01820"), Vector3((i % 2) * r * 0.25 - r * 0.12, r * 0.15 * (1 - i), r * (1.0 + i * 0.8)), vein)
		seg.rotation.x = PI / 2


# Cérebro: massa rosada de lóbulos com sulcos escuros e dois olhos na frente (-Z); os tentáculos pendem atrás.
static func _brain(root: Node3D, size: Array, c: Color) -> void:
	var r: float = size[0] / 2.0
	var pivot := Node3D.new()
	pivot.name = "Squash"
	pivot.position.y = size[1] / 2.0
	root.add_child(pivot)
	var flesh := _mat(c)
	flesh.rim_enabled = true
	flesh.rim = 0.6
	_part(pivot, SphereMesh.new(), Vector3(r * 2.0, r * 1.7, r * 2.0), c, Vector3.ZERO, flesh)
	var rng := RandomNumberGenerator.new()
	rng.seed = 266
	for i in 12:   # lóbulos na superfície
		var dir := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.3, 1), rng.randf_range(-1, 1)).normalized()
		_part(pivot, SphereMesh.new(), Vector3.ONE * r * rng.randf_range(0.7, 1.0), c.lightened(rng.randf_range(0.0, 0.15)), dir * r * 0.75 * Vector3(1, 0.85, 1), flesh)
	var groove := _mat(c.darkened(0.55))
	for k in 3:   # sulcos: anéis escuros em volta
		var ring := CylinderMesh.new()
		ring.radial_segments = 18
		var m := _part(pivot, ring, Vector3(r * (1.95 - k * 0.3), r * 0.05, r * (1.95 - k * 0.3)), c.darkened(0.55), Vector3(0, r * (0.15 + k * 0.35), 0), groove)
		m.rotation = Vector3(0.25 * (k - 1), k * 1.1, 0)
	for side in [-1, 1]:
		_part(pivot, SphereMesh.new(), Vector3.ONE * r * 0.42, Color("#f4ece4"), Vector3(side * r * 0.42, r * 0.1, -r * 0.82))
		_part(pivot, SphereMesh.new(), Vector3.ONE * r * 0.2, Color("#b01820"), Vector3(side * r * 0.42, r * 0.1, -r * 1.02))
	for i in 6:
		var a := TAU * i / 6.0
		var t := _part(pivot, CylinderMesh.new(), Vector3(r * 0.1, r * 1.1, r * 0.1), c.darkened(0.3), Vector3(cos(a) * r * 0.5, -r * 1.0, sin(a) * r * 0.5))
		t.rotation = Vector3(sin(a) * 0.3, 0, -cos(a) * 0.3)


# Segmento de verme: esfera na cor do def, dois anéis mais escuros (placas) e, na cabeça, boca com dentes; o rabo termina em ponta.
static func _worm(root: Node3D, w: float, def: Dictionary) -> void:
	var c := Color(def.color)
	var r := w / 2.0
	var shell := _mat(c)
	shell.roughness = 0.45
	shell.rim_enabled = true
	shell.rim = 0.5
	_part(root, SphereMesh.new(), Vector3.ONE * w, c, Vector3.ZERO, shell)
	for z in [-0.25, 0.25]:
		var ring := CylinderMesh.new()
		ring.radial_segments = 14
		var m := _part(root, ring, Vector3(w * 1.02, w * 0.16, w * 1.02), c.darkened(0.4), Vector3(0, 0, r * z * 2.0))
		m.rotation.x = PI / 2
	_part(root, SphereMesh.new(), Vector3(w * 0.5, w * 0.35, w * 0.5), c.lightened(0.25), Vector3(0, r * 0.62, 0))   # placa das costas
	if def.get("head", false):
		var mouth := _mat(Color("#2a0a18"))
		_part(root, SphereMesh.new(), Vector3(w * 0.7, w * 0.7, w * 0.35), Color("#2a0a18"), Vector3(0, 0, -r * 0.85), mouth)
		for i in 8:
			var a := TAU * i / 8.0
			var tooth := _part(root, BoxMesh.new(), Vector3(w * 0.08, w * 0.22, w * 0.08), Color("#e8e0c8"), Vector3(cos(a) * r * 0.42, sin(a) * r * 0.42, -r * 1.02))
			tooth.rotation.z = a + PI / 2
	if def.get("tail", false):
		var tip := CylinderMesh.new()
		tip.top_radius = 0.0
		tip.bottom_radius = 0.5
		var m := _part(root, tip, Vector3(w * 0.7, w * 1.0, w * 0.7), c.darkened(0.2), Vector3(0, 0, r * 1.1))
		m.rotation.x = PI / 2
		tip.top_radius = 0.0   # _part deixa todo cilindro reto; aqui é um cone


# Slime legível no gramado: gelatina brilhante e translúcida com um contorno escuro por trás, miolo mais escuro, olhos e uma sombra
# no chão. A frente é -Z.
static func _slime(root: Node3D, size: Array, c: Color, def: Dictionary) -> void:
	var w: float = size[0]
	var h: float = size[1]
	var shadow := CylinderMesh.new()
	shadow.top_radius = 0.5
	shadow.bottom_radius = 0.5
	shadow.height = 0.01
	shadow.radial_segments = 16
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.albedo_color = Color(0, 0, 0, 0.38)
	_part(root, shadow, Vector3(w * 1.15, 1.0, w * 1.15), Color.BLACK, Vector3(0, 0.02, 0), sm)
	var body := Node3D.new()
	body.name = "Squash"
	root.add_child(body)
	var rim := StandardMaterial3D.new()   # casca escura vista só por trás: vira o contorno da silhueta
	rim.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rim.cull_mode = BaseMaterial3D.CULL_FRONT
	rim.albedo_color = c.darkened(0.6)
	_part(body, SphereMesh.new(), Vector3(w * 1.08, h * 1.5, w * 1.08), c, Vector3(0, h * 0.4, 0), rim)   # domo: a metade de baixo fica no chão
	var gel := _mat(Color(c.lightened(0.1), 0.8))
	gel.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gel.roughness = 0.12
	gel.emission_enabled = true
	gel.emission = c * 0.4
	gel.rim_enabled = true
	gel.rim = 0.7
	_part(body, SphereMesh.new(), Vector3(w, h * 1.4, w), c, Vector3(0, h * 0.38, 0), gel)
	_part(body, SphereMesh.new(), Vector3(w * 0.4, h * 0.5, w * 0.4), c.darkened(0.5), Vector3(w * 0.05, h * 0.36, w * 0.02))   # miolo
	for side in [-1, 1]:   # olhos
		_part(body, SphereMesh.new(), Vector3(w * 0.14, h * 0.26, w * 0.09), Color("#0c1018"), Vector3(side * w * 0.2, h * 0.78, -w * 0.4))
		_part(body, SphereMesh.new(), Vector3(w * 0.05, w * 0.05, w * 0.04), Color.WHITE, Vector3(side * w * 0.2 - w * 0.02, h * 0.86, -w * 0.45))
	_part(body, SphereMesh.new(), Vector3.ONE * w * 0.16, Color(1, 1, 1), Vector3(-w * 0.22, h * 1.02, -w * 0.05))   # brilho da gelatina
	if def.get("crown", false):   # King Slime: coroa dourada de 5 pontas na cabeça
		var gold := _mat(Color("#f0c030"))
		gold.emission_enabled = true
		gold.emission = Color("#a07810")
		_part(body, CylinderMesh.new(), Vector3(w * 0.4, h * 0.1, w * 0.4), Color("#f0c030"), Vector3(0, h * 1.28, 0), gold)
		for i in 5:
			var a := TAU * i / 5.0
			var spike := _part(body, BoxMesh.new(), Vector3(w * 0.06, h * 0.2, w * 0.06), Color("#f0c030"), Vector3(cos(a) * w * 0.16, h * 1.4, sin(a) * w * 0.16), gold)
			spike.rotation = Vector3(sin(a) * 0.3, 0, -cos(a) * 0.3)


# Animações por quadro: olho encara o jogador e mexe os tentáculos; slime estica com o pulo.
static func animate(model: Node3D, enemy: Node3D, target: Vector3, t: float) -> void:
	var look := model.get_node_or_null("Look")
	if look and look.is_inside_tree() and look.global_position.distance_to(target) > 0.1:
		look.look_at(target, Vector3.UP)
		for i in 5:
			var ten: Node3D = look.get_node("Tendril%d" % i)
			ten.rotation.y = sin(t * 6.0 + i) * 0.25
		look.scale.y = 0.12 if fmod(t + enemy.get_instance_id() % 13, 3.7) < 0.1 else 1.0   # pisca de tempos em tempos
	var pulse := model.get_node_or_null("Pulse")
	if pulse:   # a carne pulsa
		pulse.scale = Vector3(1.0 + sin(t * 2.2) * 0.015, 1.0 + sin(t * 1.7) * 0.01, 1.0 + sin(t * 2.6) * 0.06)
	var squash := model.get_node_or_null("Squash")
	if squash:   # estica com o pulo e balança parada, como gelatina
		var k := clampf(enemy.velocity.y / 10.0, -0.3, 0.35) + sin(t * 4.0 + enemy.get_instance_id() % 7) * 0.04
		squash.scale = Vector3(1.0 - k * 0.5, 1.0 + k, 1.0 - k * 0.5)


static func set_phase(model: Node3D, phase: int) -> void:
	var look := model.get_node_or_null("Look")
	if look:
		look.get_node("Iris").visible = phase == 1
		look.get_node("Mouth").visible = phase == 2
