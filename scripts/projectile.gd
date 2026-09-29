extends Node3D
# Projétil de projectiles.json: voa com gravidade opcional, some ao bater em bloco ou ao fim da vida,
# fere até `pierce` inimigos (cada um uma vez). Visual: ícone de item extrudado (model_item) ou sprite
# da wiki virado para a câmera (sprite), com brilho aditivo opcional (glow).

var def: Dictionary
var velocity: Vector3
var damage: int
var knockback: float
var crit := Combat.CRIT
var entities: Node3D
var age := 0.0
var hit: Array[Node3D] = []


func _ready() -> void:
	var atlas: Texture2D = entities.world.atlas_texture
	if def.has("model_item") or def.get("solid", false):   # solid: o sprite da wiki (pixel art pequeno) extrudado em 3D, como o ícone de item
		var m: Array
		var ang := 45.0
		if def.has("model_item"):
			var id: int = Items.ids[def.model_item]
			m = ItemModel.for_item(id, Items.icon_texture(id, atlas), def.size)
			ang = Items.defs[id].get("sprite_angle", 45.0)
		else:
			m = ItemModel.for_item(def.name.hash(), Atlas.texture(def.sprite, Blocks.textures.keys().find(def.sprite), atlas), def.size)
			ang = def.get("sprite_angle", 45.0)
		var mi := MeshInstance3D.new()
		mi.mesh = m[0]
		mi.material_override = m[1]
		# Gira a direção para onde o sprite aponta (sprite_angle) até a frente do projétil (-Z).
		mi.transform = Transform3D(Basis(Vector3.UP, PI / 2) * Basis(Vector3.BACK, -deg_to_rad(ang)), Vector3.ZERO)
		mi.position = -(mi.transform.basis * m[0].get_aabb().get_center())
		add_child(mi)
	if def.has("sprite") and not def.get("solid", false):
		var sp := Sprite3D.new()
		sp.texture = Atlas.texture(def.sprite, Blocks.textures.keys().find(def.sprite), atlas)
		var big := maxf(sp.texture.get_width(), sp.texture.get_height())
		sp.pixel_size = def.size / big
		sp.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		sp.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR if big > 64 else BaseMaterial3D.TEXTURE_FILTER_NEAREST
		sp.shaded = false
		sp.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
		if def.get("beam", false):   # faixa fina (laser): dois planos cruzados ao longo do voo (-Z), visíveis de qualquer lado, engrossados
			sp.billboard = BaseMaterial3D.BILLBOARD_DISABLED
			sp.scale.y = def.get("thick", 3.0)
			sp.transform.basis = Basis(Vector3.UP, PI / 2) * Basis.from_scale(sp.scale)
			var cross: Sprite3D = sp.duplicate()
			cross.transform.basis = Basis(Vector3.UP, PI / 2) * Basis(Vector3.RIGHT, PI / 2) * Basis.from_scale(sp.scale)
			add_child(cross)
		add_child(sp)
	if def.has("glow"):
		var halo := Sprite3D.new()
		var g := GradientTexture2D.new()
		g.fill = GradientTexture2D.FILL_RADIAL
		g.fill_from = Vector2(0.5, 0.5)
		g.gradient = Gradient.new()
		g.gradient.set_color(0, Color(def.glow))
		g.gradient.set_color(1, Color(Color(def.glow), 0))
		halo.texture = g
		halo.pixel_size = def.size * 1.6 / 64
		halo.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		halo.shaded = false
		halo.modulate = Color(1, 1, 1, 0.6)
		add_child(halo)
		_trail()


# Rastro: faíscas aditivas na cor do brilho, soltas no mundo (local_coords falso) para ficarem para trás; estilo do pó do Terraria.
func _trail() -> void:
	var p := CPUParticles3D.new()
	p.amount = 24
	p.lifetime = 0.45
	p.local_coords = false
	p.mesh = Fx._mesh(clampf(def.size * 0.12, 0.06, 0.14), true)
	p.color = Color(def.glow)
	p.color_ramp = Fx.fade()
	p.scale_amount_curve = Fx.shrink()
	p.direction = Vector3.BACK
	p.spread = 25.0
	p.initial_velocity_min = 0.2
	p.initial_velocity_max = 0.9
	p.gravity = Vector3.ZERO
	p.position.z = def.size * 0.3   # na cauda (o projétil voa para -Z)
	add_child(p)


# Bomba/dinamite (def.fuse): cai, quica e explode depois do pavio (def.radius em blocos).
func _bomb(delta: float) -> void:
	velocity.y -= def.get("gravity", 20.0) * delta
	var r := VoxelBody.move(entities.world, position, 0.15, 0.3, velocity * delta)
	position = r[0]
	var hit: Vector3i = r[1]
	if hit.y < 0:
		velocity = Vector3(velocity.x * 0.6, -velocity.y * 0.35, velocity.z * 0.6)
	elif hit.y > 0 or hit.x != 0 or hit.z != 0:
		velocity = Vector3(-velocity.x * 0.35 if hit.x != 0 else velocity.x, velocity.y * 0.5, -velocity.z * 0.35 if hit.z != 0 else velocity.z)
	if fmod(age, 0.12) < delta:
		Fx.sparks(entities, position + Vector3.UP * 0.45, Color("#ffb040"), 1, Vector3.UP)
	if age >= def.fuse:
		entities.explode(position + Vector3.UP * 0.2, def.radius, damage)
		queue_free()


func _physics_process(delta: float) -> void:
	age += delta
	if def.has("fuse"):
		_bomb(delta)
		return
	velocity.y -= def.get("gravity", 0.0) * delta
	var next := position + velocity * delta
	var b: Vector3i = Vector3i(next.floor())
	if age > def.get("life", 5.0) or (Blocks.solid[entities.world.get_block(b.x, b.y, b.z)] and not def.get("ghost", false)):
		queue_free()
		return
	var r: float = def.get("size", 0.2) * 0.35
	if def.get("hostile", false):   # laser do chefe: fere o jogador
		var p: Node3D = entities.player
		if def.has("homing"):   # teleguiado: gira até `homing` rad/s para o jogador
			var want: Vector3 = p.position + Vector3.UP - position
			var turn := minf(velocity.angle_to(want), def.homing * delta)
			if turn > 0.0001 and velocity.cross(want).length() > 0.0001:
				velocity = velocity.rotated(velocity.cross(want).normalized(), turn)
		if VoxelBody.touches(next - Vector3.UP * r, r, r * 2, p.position, p.HALF, p.TALL):
			p.hurt(Combat.vary(damage, entities.rng), velocity)
			queue_free()
			return
		position = next
		return
	for n in entities.get_children():   # projétil do jogador destrói esfera de conjurador
		if n != self and n.get("def") is Dictionary and n.def.get("destroy", false) and n.position.distance_to(next) < r + n.def.size * 0.5:
			entities.pop_sphere(n)
			queue_free()
			return
	for e in entities.enemies.duplicate():
		if not e in hit and VoxelBody.touches(next - Vector3.UP * r, r, r * 2, e.position, e.half, e.tall):
			hit.append(e)
			e.hurt(Combat.vary(damage, entities.rng), velocity, knockback, Combat.is_crit(entities.rng, crit))
			if hit.size() >= def.get("pierce", 1):
				queue_free()
				return
	position = next
	if is_inside_tree() and velocity.normalized().cross(Vector3.UP).length() > 0.01:
		look_at(position + velocity)
