extends Node3D
# Flecha: voa em linha com gravidade leve, some ao bater num bloco e fere o primeiro inimigo que tocar.

const GRAVITY := 10.0
const LIFETIME := 5.0

var velocity: Vector3
var damage: int
var knockback: float
var entities: Node3D
var age := 0.0


func _ready() -> void:
	var box := BoxMesh.new()
	box.size = Vector3(0.06, 0.06, 0.6)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color("#a0784a")
	box.material = mat
	var m := MeshInstance3D.new()
	m.mesh = box
	add_child(m)


func _physics_process(delta: float) -> void:
	age += delta
	velocity.y -= GRAVITY * delta
	var next := position + velocity * delta
	var b: Vector3i = Vector3i(next.floor())
	if age > LIFETIME or Blocks.solid[entities.world.get_block(b.x, b.y, b.z)]:
		queue_free()
		return
	for e in entities.enemies:
		if VoxelBody.touches(next - Vector3.UP * 0.05, 0.05, 0.1, e.position, e.half, e.tall):
			e.hurt(damage, velocity, knockback)
			queue_free()
			return
	position = next
	if is_inside_tree() and velocity.normalized().cross(Vector3.UP).length() > 0.01:
		look_at(position + velocity)
