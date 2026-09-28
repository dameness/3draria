extends Node3D
# Um inimigo de enemies.json com IA genérica por "ai": hop (slime), walk (zumbi), fly (olho demoníaco)
# e eye_of_cthulhu (chefe: paira, invoca servos e investe; fase 2 abaixo de phase2.below da vida).
# Visual: EnemyModel (modelo 3D por "model"; senão o sprite da wiki extrudado).

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
var model: Node3D
var flash_mat: StandardMaterial3D
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
	model = EnemyModel.build(def)
	model.rotation.y = PI  # modelos olham para -Z; o nó gira para o jogador por +Z
	add_child(model)
	flash_mat = StandardMaterial3D.new()
	flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flash_mat.albedo_color = Color(1, 0.1, 0.1, 0.45)
	flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA


func _process(delta: float) -> void:
	if model == null:
		return
	var was := flash > 0
	flash -= delta
	if was != (flash > 0):  # pisca vermelho ao levar dano
		for m in model.find_children("", "MeshInstance3D", true, false):
			m.material_overlay = flash_mat if flash > 0 else null
	EnemyModel.animate(model, self, entities.player.eye(), Time.get_ticks_msec() / 1000.0)


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
		if model:
			EnemyModel.set_phase(model, 2)
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
	entities.spawn_text(position + Vector3.UP * (tall + 0.3), str(taken), Color("#ffa050"))
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
