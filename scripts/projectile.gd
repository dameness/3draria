class_name Projectile
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
var returning := false   # bumerangue: já está voltando
var mode := "spin"       # flail: spin (gira em volta do jogador) | out (arremessado) | back (recolhe)
var item_id := -1        # flail: o item que o jogador precisa manter na mão
var spin := 0.0          # flail: ângulo do giro
var throw_from := Vector3.ZERO   # flail: de onde (olho) e para onde (mira) foi arremessado
var throw_dir := Vector3.FORWARD
var last_hit := {}       # flail: inimigo -> instante do último golpe do giro
var chain: Array[Node3D] = []
var npc := false         # disparado por habitante: não fere o jogador
var stuck := false       # sinalizador: grudou num bloco e fica aceso até o fim da vida


func _ready() -> void:
	var atlas: Texture2D = entities.world.atlas_texture
	if def.has("flail"):
		_flail_build()
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


# Glowstick (wiki): voa em arco sem ferir ninguém e, ao bater num bloco, vira o bloco aceso na última célula livre (quebrar devolve o item).
func _land(delta: float) -> void:
	velocity.y -= def.gravity * delta
	var next := position + velocity * delta
	var b := Vector3i(next.floor())
	if age > def.life:
		queue_free()
	elif Blocks.solid[entities.world.get_block(b.x, b.y, b.z)]:
		var c := Vector3i(position.floor())
		var there: int = entities.world.get_block(c.x, c.y, c.z)
		if there == 0 or Blocks.soft[there]:
			entities.world.set_block(c.x, c.y, c.z, Blocks.ids[def.land])
		queue_free()
	else:
		position = next


# Flail: bola de ferro com espinhos na ponta de uma corrente de elos (nós soltos no mundo, reposicionados a cada quadro).
static func flail_ball(def: Dictionary) -> MeshInstance3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(def.color)
	mat.metallic = 0.6
	mat.roughness = 0.45
	var ball := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = def.size * 0.5
	sph.height = def.size
	sph.radial_segments = 12
	sph.rings = 6
	ball.mesh = sph
	ball.material_override = mat
	var spike := CylinderMesh.new()   # cone: 6 espinhos nos eixos
	spike.top_radius = 0.0
	spike.bottom_radius = def.size * 0.16
	spike.height = def.size * 0.5
	spike.radial_segments = 5
	for dir in [Vector3.UP, Vector3.DOWN, Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK]:
		var sp := MeshInstance3D.new()
		sp.mesh = spike
		sp.material_override = mat
		sp.position = dir * def.size * 0.62
		sp.basis = Basis(Quaternion(Vector3.UP, dir))
		ball.add_child(sp)
	return ball


# Pegada do flail na mão (1ª e 3ª pessoa; `s` = escala): cabo com anel na cor da bola, `tip` na ponta do cabo (de onde sai a corrente) e, com o
# flail guardado, a corrente curta com a bola pendurada ("idle"; `down` = a gravidade no espaço do cabo). O jogador esconde o "idle" quando a bola sai.
static func flail_grip(def: Dictionary, s: float, down: Vector3) -> Node3D:
	var g := Node3D.new()
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color("#6b4a2a")
	var rod := CylinderMesh.new()
	rod.top_radius = 0.02 * s
	rod.bottom_radius = 0.022 * s
	rod.height = 0.26 * s
	var h := MeshInstance3D.new()
	h.mesh = rod
	h.material_override = wood
	h.position = Vector3(0, 0.06 * s, 0)
	g.add_child(h)
	var cap := SphereMesh.new()
	cap.radius = 0.03 * s
	cap.height = 0.06 * s
	var ring := MeshInstance3D.new()
	ring.mesh = cap
	ring.material_override = flail_ball(def).material_override
	ring.position = Vector3(0, 0.2 * s, 0)
	g.add_child(ring)
	var tip := Node3D.new()
	tip.name = "tip"
	tip.position = Vector3(0, 0.22 * s, 0)
	g.add_child(tip)
	var idle := Node3D.new()
	idle.name = "idle"
	tip.add_child(idle)
	var link := BoxMesh.new()
	link.size = Vector3(0.012, 0.012, 0.028) * s
	var lm := StandardMaterial3D.new()
	lm.albedo_color = Color("#6b6f78")
	for i in 3:
		var l := MeshInstance3D.new()
		l.mesh = link
		l.material_override = lm
		l.position = down * 0.04 * s * (i + 1)
		l.basis = Basis(Quaternion(Vector3.BACK, down))
		idle.add_child(l)
	var ball := flail_ball(def)
	ball.scale = Vector3.ONE * 0.2 * s
	ball.position = down * 0.19 * s
	idle.add_child(ball)
	return g


func _flail_build() -> void:
	add_child(flail_ball(def))
	var link := BoxMesh.new()
	link.size = Vector3(0.05, 0.05, 0.11)
	var lm := StandardMaterial3D.new()
	lm.albedo_color = Color("#6b6f78")
	lm.metallic = 0.7
	for i in 9:
		var l := MeshInstance3D.new()
		l.mesh = link
		l.material_override = lm
		l.top_level = true
		add_child(l)
		chain.append(l)


# Flail (wiki Flails): segurar o botão gira a bola num disco horizontal na frente do jogador, em volta do ponto da mira (o mouse escolhe a altura e a direção do giro; 60% do dano,
# 35% do recuo, golpes repetidos por inimigo); soltar arremessa pela linha da mira no instante da soltura (dano cheio) até `length`, ou até bater
# num bloco, e ela volta. A corrente sai da ponta do cabo na mão. ponytail: sem a fase "cair no chão" de segurar de novo.
func _flail(delta: float) -> void:
	var p: Node3D = entities.player
	var hand: Vector3 = p.flail_tip()
	if p.held() != item_id or p.dead > 0.0:
		queue_free()
		return
	var r: float = def.size * 0.5
	var full := mode != "spin"
	var eye_pos: Vector3 = p.position + Vector3.UP * p.EYE
	if mode == "spin":
		spin += delta * 9.0
		var aim: Vector3 = p.aim_dir()
		var flat := Vector3(aim.x, 0.0, aim.z)
		flat = flat.normalized() if flat.length() > 0.01 else Basis(Vector3.UP, p.rotation.y) * Vector3.FORWARD   # olhando reto para cima/baixo
		var want: Vector3 = eye_pos + aim * def.length * 0.4 + (flat.cross(Vector3.UP) * cos(spin) + flat * sin(spin)) * def.length * 0.3   # disco horizontal em volta do ponto da mira
		for i in 4:   # o chão não segura a bola: sobe até achar espaço
			if not Blocks.solid[entities.world.get_block(floori(want.x), floori(want.y), floori(want.z))]:
				break
			want.y += 0.5
		position += (want - position) * minf(delta * 25.0, 1.0)
		if not p.attack_held or p.inventory_open:
			mode = "out"
			hit.clear()
			throw_from = eye_pos
			throw_dir = aim
			velocity = aim * velocity.length() * 1.6
			p.flail_snap = 0.3
			Sfx.play(entities, "swing", position, -8.0, 1.2)
	elif mode == "out":
		var lateral: Vector3 = throw_from + throw_dir * (position - throw_from).dot(throw_dir) - position   # a bola converge para a linha da mira
		var next := position + (throw_dir * velocity.length() + lateral * 12.0) * delta
		if position.distance_to(hand) > def.length or Blocks.solid[entities.world.get_block(floori(next.x), floori(next.y), floori(next.z))]:
			mode = "back"
			hit.clear()
		else:
			position = next
	else:
		var back := hand - position
		if back.length() < 0.7 or age > def.life:
			queue_free()
			return
		position += back.normalized() * velocity.length() * 1.3 * delta
	for e in entities.enemies.duplicate():
		if VoxelBody.touches(position - Vector3.UP * r, r, r * 2, e.position, e.half, e.tall):
			if full and not e in hit:
				hit.append(e)
				e.hurt(Combat.vary(damage, entities.rng), e.position - hand, knockback, Combat.is_crit(entities.rng, crit))
				afflict(e)
			elif not full and age - last_hit.get(e, -9.0) > 0.3:
				last_hit[e] = age
				e.hurt(Combat.vary(roundi(damage * 0.6), entities.rng), e.position - hand, knockback * 0.35, Combat.is_crit(entities.rng, crit))
				afflict(e)
	for i in chain.size():   # elos entre a mão e a bola
		chain[i].global_position = hand.lerp(position, (i + 0.5) / chain.size())
		if position.distance_to(hand) > 0.05:
			chain[i].look_at(position)


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
	var boom: bool = age >= def.fuse
	if def.get("contact", false) and not boom:   # granada: explode ao tocar num inimigo, sem esperar o pavio
		boom = entities.enemies.any(func(e): return not e.display and e.def.ai != "npc" and VoxelBody.touches(position, 0.2, 0.4, e.position, e.half, e.tall))
	if boom:
		entities.explode(position + Vector3.UP * 0.2, def.radius, damage, def.get("keep_blocks", false), not npc)
		for i in def.get("bees", 0):   # Beenade: um enxame de abelhas sai da explosão
			var dir := Vector3(entities.rng.randf_range(-1, 1), entities.rng.randf_range(-0.2, 1), entities.rng.randf_range(-1, 1)).normalized()
			entities.spawn_projectile("bee_shot", position + Vector3.UP * 0.3, dir, 14.0, maxi(1, roundi(damage * 0.5)), 0.25)
		queue_free()


# Bumerangue: voa `def.out` s (ou até bater num bloco), volta para o jogador e some ao alcançá-lo; cada inimigo apanha na ida e na volta.
func _boomerang(delta: float) -> void:
	var p: Node3D = entities.player
	var back: Vector3 = p.position + Vector3.UP - position
	if not returning and (age >= def.out or Blocks.solid[entities.world.get_block(floori(position.x + velocity.x * delta), floori(position.y), floori(position.z + velocity.z * delta))]):
		returning = true
		hit.clear()
	if returning:
		if back.length() < 0.8 or age > def.life:
			queue_free()
			return
		velocity = back.normalized() * velocity.length()
	position += velocity * delta
	rotation.y += delta * 20.0
	for e in entities.enemies.duplicate():
		if not e in hit and VoxelBody.touches(position - Vector3.UP * 0.2, 0.3, 0.4, e.position, e.half, e.tall):
			hit.append(e)
			e.hurt(Combat.vary(damage, entities.rng), velocity, knockback, Combat.is_crit(entities.rng, crit))
			afflict(e)


# Debuff do projétil (`debuff`, `debuff_time` sorteado da lista, `debuff_chance`) no inimigo que ele acertou.
func afflict(e: Node3D) -> void:
	if def.has("debuff") and entities.rng.randf() < def.get("debuff_chance", 1.0):
		e.afflict(def.debuff, def.debuff_time[entities.rng.randi() % def.debuff_time.size()])


func _physics_process(delta: float) -> void:
	age += delta
	if stuck:
		if age > def.get("life", 5.0):
			queue_free()
		return
	if def.has("fuse"):
		_bomb(delta)
		return
	if def.has("land"):
		_land(delta)
		return
	if def.has("out"):
		_boomerang(delta)
		return
	if def.has("flail"):
		_flail(delta)
		return
	velocity.y -= def.get("gravity", 0.0) * delta
	var next := position + velocity * delta
	var b: Vector3i = Vector3i(next.floor())
	if age > def.get("life", 5.0):
		queue_free()
		return
	if Blocks.solid[entities.world.get_block(b.x, b.y, b.z)] and not def.get("ghost", false):
		if def.get("stick", false) and not def.get("hostile", false):
			stuck = true
		else:
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
		for n in entities.enemies:   # o tiro inimigo também fere o habitante que ele atravessa
			if n.def.ai == "npc" and VoxelBody.touches(next - Vector3.UP * r, r, r * 2, n.position, n.half, n.tall):
				n.hurt(Combat.vary(damage, entities.rng), velocity, knockback, false, true)
				queue_free()
				return
		position = next
		return
	if def.has("seek") and age > 0.5:   # abelha (wiki Bee Gun): meio segundo depois persegue o inimigo mais perto (30 blocos = 50 tiles de Manhattan)
		var best: Node3D = null
		var bd := 30.0
		for e in entities.enemies:
			var d: Vector3 = e.position + Vector3.UP * e.tall * 0.5 - position
			if e.def.ai != "npc" and not e.display and not e in hit and absf(d.x) + absf(d.y) + absf(d.z) < bd:
				bd = absf(d.x) + absf(d.y) + absf(d.z)
				best = e
		if best:
			var want: Vector3 = best.position + Vector3.UP * best.tall * 0.5 - position
			var turn := minf(velocity.angle_to(want), def.seek * delta)
			if turn > 0.0001 and velocity.cross(want).length() > 0.0001:
				velocity = velocity.rotated(velocity.cross(want).normalized(), turn)
	for n in entities.get_children():   # projétil do jogador destrói esfera de conjurador
		if n != self and n.get("def") is Dictionary and n.def.get("destroy", false) and n.position.distance_to(next) < r + n.def.size * 0.5:
			entities.pop_sphere(n)
			queue_free()
			return
	for e in entities.enemies.duplicate():
		if e.def.ai != "npc" and not e in hit and VoxelBody.touches(next - Vector3.UP * r, r, r * 2, e.position, e.half, e.tall):
			hit.append(e)
			e.hurt(Combat.vary(damage, entities.rng), velocity, knockback, Combat.is_crit(entities.rng, crit))
			afflict(e)
			if def.has("decay"):   # Terra Beam: cada alvo atravessado tira 25% do dano atual; chegou a 0, some
				damage = int(damage * (1.0 - def.decay))
				if damage <= 0:
					queue_free()
					return
			if hit.size() >= def.get("pierce", 1):
				queue_free()
				return
	position = next
	if def.has("spin"):   # shuriken: gira deitado, como o bumerangue
		rotation.y += delta * def.spin
	elif is_inside_tree() and velocity.normalized().cross(Vector3.UP).length() > 0.01:
		look_at(position + velocity)
