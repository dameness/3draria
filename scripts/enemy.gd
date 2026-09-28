extends Node3D
# Um inimigo de enemies.json com IA genérica por "ai": hop (slime), walk (zumbi), fly (olho demoníaco)
# e eye_of_cthulhu (chefe: paira, invoca servos e investe; fase 2 abaixo de phase2.below da vida).
# Visual: sprite da wiki virado para a câmera; sem sprite baixado, caixa colorida.

const GRAVITY := 28.0
const JUMP := 8.0

var def: Dictionary
var entities: Node3D
var hp: int
var damage: int
var defense: int
var half: float
var tall: float
var velocity := Vector3.ZERO
var on_floor := false
var hit_wall := false
var timer := 0.0   # espera entre pulos do slime / tempo no estado do chefe
var stun := 0.0    # após levar golpe a IA para e o knockback age
var flash := 0.0
var rng := RandomNumberGenerator.new()
var sprite: Sprite3D
# chefe
var mode := "hover"
var dashes := 0
var summoned := 0
var phase := 1


func _ready() -> void:
	hp = def.life
	damage = def.damage
	defense = def.defense
	half = def.size[0] / 2.0
	tall = def.size[1]
	var tex := _texture(def.get("sprite", ""))
	if tex:
		sprite = Sprite3D.new()
		sprite.texture = tex
		sprite.pixel_size = tall / tex.get_height()
		sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED if def.ai != "walk" and def.ai != "hop" else BaseMaterial3D.BILLBOARD_FIXED_Y
		sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		sprite.shaded = false
		sprite.position.y = tall / 2
		add_child(sprite)
		return
	var box := BoxMesh.new()
	box.size = Vector3(def.size[0], tall, def.size[0])
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(def.color)
	box.material = mat
	var mesh := MeshInstance3D.new()
	mesh.mesh = box
	mesh.position.y = tall / 2
	add_child(mesh)


# Sprite da wiki se baixado; senão null (usa a caixa).
static func _texture(n: String) -> Texture2D:
	if n == "" or Atlas.wiki_image(Blocks.textures.get(n, {})) == null:
		return null
	return Atlas.texture(n, 0, null)


func _process(delta: float) -> void:
	if sprite:
		flash -= delta
		sprite.modulate = Color(1, 0.4, 0.4) if flash > 0 else Color.WHITE


func _physics_process(delta: float) -> void:
	think(delta)
	move(delta)
	var p: Node3D = entities.player
	if VoxelBody.touches(position, half, tall, p.position, p.HALF, p.TALL):
		p.hurt(damage, p.position - position)


func think(delta: float) -> void:
	stun -= delta
	if stun > 0:
		return
	var p: Node3D = entities.player
	var to: Vector3 = p.position + Vector3.UP - (position + Vector3.UP * tall / 2)
	var flat := Vector3(to.x, 0, to.z).normalized()
	match def.ai:
		"hop":
			if on_floor:
				velocity.x *= 0.7
				velocity.z *= 0.7
				timer -= delta
				if timer <= 0:
					timer = rng.randf_range(1.0, 2.0)
					velocity = flat * def.speed + Vector3.UP * JUMP
		"walk":
			velocity.x = flat.x * def.speed
			velocity.z = flat.z * def.speed
			if on_floor and hit_wall:
				velocity.y = JUMP
		"fly":
			velocity = velocity.lerp(to.normalized() * def.speed, delta * 1.5)
		"eye_of_cthulhu":
			eye_of_cthulhu(delta, to)
	if flat != Vector3.ZERO:
		rotation.y = atan2(flat.x, flat.z)


# Fase 1: paira acima do jogador invocando servos, depois 3 investidas. Fase 2: investidas em cadeia
# mais rápidas. Ao amanhecer, sobe e vai embora.
func eye_of_cthulhu(delta: float, to: Vector3) -> void:
	if not entities.clock.is_night():
		velocity = Vector3.UP * 20
		if position.distance_to(entities.player.position) > 60:
			entities.remove_enemy(self)
		return
	var p2: Dictionary = def.phase2
	if phase == 1 and hp < def.life * p2.below:
		phase = 2
		damage = p2.damage
		defense = p2.defense
		var tex := _texture(p2.sprite)
		if sprite and tex:
			sprite.texture = tex
	timer -= delta
	match mode:
		"hover":
			var t := Time.get_ticks_msec() / 1000.0
			var target: Vector3 = entities.player.position + Vector3(cos(t) * 6, 8, sin(t) * 6)
			velocity = velocity.lerp((target - position).limit_length(def.speed * 1.5), delta * 2.0)
			if phase == 1 and summoned < 3 and timer < 3.0 - summoned:
				summoned += 1
				entities.spawn_enemy(entities.def_named(def.minion), position + Vector3.DOWN)
			if timer <= 0:
				mode = "dash"
				dashes = 3 if phase == 1 else 5
				timer = 0
		"dash":
			if timer <= 0:
				if dashes == 0:
					mode = "hover"
					timer = 4.0 if phase == 1 else 2.0
					summoned = 0
					return
				dashes -= 1
				velocity = to.normalized() * (16.0 if phase == 1 else 24.0)
				timer = 0.8 if phase == 1 else 0.45
			velocity *= 1.0 - delta * 0.8


func move(delta: float) -> void:
	if def.get("boss"):
		position += velocity * delta  # chefes atravessam blocos, como no Terraria
		return
	if def.ai != "fly":
		velocity.y = maxf(velocity.y - GRAVITY * delta, -50.0)
	var r := VoxelBody.move(entities.world, position, half, tall, velocity * delta)
	position = r[0]
	var hit: Vector3i = r[1]
	on_floor = hit.y < 0
	hit_wall = hit.x != 0 or hit.z != 0
	for a in 3:
		if hit[a] != 0:
			velocity[a] = -velocity[a] * 0.5 if def.ai == "fly" else 0.0
	if position.y < -10:
		entities.remove_enemy(self)


# Dano como no Terraria (modo normal): dano − defesa/2, mínimo 1. Retorna o dano causado.
func hurt(dmg: int, dir: Vector3, knockback: float) -> int:
	var taken := maxi(1, dmg - ceili(defense / 2.0))
	hp -= taken
	flash = 0.12
	var kb: float = knockback * (1.0 - def.get("kb_resist", 0.0))
	if kb > 0:
		var flat := Vector3(dir.x, 0, dir.z).normalized()
		velocity = flat * kb + Vector3.UP * (3.0 if def.ai != "fly" else 0.0)
		stun = 0.25
	if hp <= 0:
		for d in def.drops:
			if rng.randf() < d.chance:
				entities.spawn_drop(Items.ids[d.item], rng.randi_range(d.min, d.max), position + Vector3.UP * 0.3)
		entities.remove_enemy(self)
	return taken
