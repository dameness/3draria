extends Node3D
# Um inimigo de enemies.json com IA genérica por "ai": hop (slime), walk (zumbi), fly (olho demoníaco).

const GRAVITY := 28.0
const JUMP := 8.0

var def: Dictionary
var entities: Node3D
var hp: int
var half: float
var tall: float
var velocity := Vector3.ZERO
var on_floor := false
var hit_wall := false
var timer := 0.0   # espera entre pulos do slime
var stun := 0.0    # após levar golpe a IA para e o knockback age
var rng := RandomNumberGenerator.new()


func _ready() -> void:
	hp = def.life
	half = def.size[0] / 2.0
	tall = def.size[1]
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


func _physics_process(delta: float) -> void:
	think(delta)
	move(delta)
	var p: Node3D = entities.player
	if VoxelBody.touches(position, half, tall, p.position, p.HALF, p.TALL):
		p.hurt(def.damage, p.position - position)


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
	if flat != Vector3.ZERO:
		rotation.y = atan2(flat.x, flat.z)


func move(delta: float) -> void:
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
func hurt(damage: int, dir: Vector3, knockback: float) -> int:
	var taken := maxi(1, damage - ceili(def.defense / 2.0))
	hp -= taken
	var flat := Vector3(dir.x, 0, dir.z).normalized()
	velocity = flat * knockback + Vector3.UP * (3.0 if def.ai != "fly" else 0.0)
	stun = 0.25
	if hp <= 0:
		for d in def.drops:
			if rng.randf() < d.chance:
				entities.spawn_drop(Items.ids[d.item], rng.randi_range(d.min, d.max), position + Vector3.UP * 0.3)
		entities.remove_enemy(self)
	return taken
