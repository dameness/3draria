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
	if def.has("model_item"):
		var id: int = Items.ids[def.model_item]
		var m := ItemModel.for_item(id, Items.icon_texture(id, atlas), def.size)
		var mi := MeshInstance3D.new()
		mi.mesh = m[0]
		mi.material_override = m[1]
		# Gira a direção para onde o sprite aponta (sprite_angle) até a frente do projétil (-Z).
		var ang := deg_to_rad(Items.defs[id].get("sprite_angle", 45.0))
		mi.transform = Transform3D(Basis(Vector3.UP, PI / 2) * Basis(Vector3.BACK, -ang), Vector3.ZERO)
		mi.position = -(mi.transform.basis * m[0].get_aabb().get_center())
		add_child(mi)
	if def.has("sprite"):
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
		if def.get("trail", false):
			Fx.trail(self, Color(def.glow), def.size * 0.09)


func _physics_process(delta: float) -> void:
	age += delta
	velocity.y -= def.get("gravity", 0.0) * delta
	var next := position + velocity * delta
	var b: Vector3i = Vector3i(next.floor())
	if age > def.get("life", 5.0) or Blocks.solid[entities.world.get_block(b.x, b.y, b.z)]:
		queue_free()
		return
	var r: float = def.get("size", 0.2) * 0.35
	if def.get("hostile", false):   # laser do chefe: fere o jogador
		var p: Node3D = entities.player
		if VoxelBody.touches(next - Vector3.UP * r, r, r * 2, p.position, p.HALF, p.TALL):
			p.hurt(Combat.vary(damage, entities.rng), velocity)
			queue_free()
			return
		position = next
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
