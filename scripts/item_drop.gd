extends Node3D
# Item solto: ícone em miniatura girando com um feixe de luz na cor da raridade.
# Cai com gravidade; perto do jogador é puxado e entra no inventário.

const GRAVITY := 20.0
const MAGNET := 3.0
const PICKUP := 0.9
const LIFETIME := 300.0
const DELAY := 0.4   # tempo antes de poder ser puxado

var item: int
var count: int
var entities: Node3D
var velocity := Vector3(0, 4, 0)
var age := 0.0
var icon: Sprite3D


func _ready() -> void:
	icon = Sprite3D.new()
	icon.texture = entities.icon(item)
	icon.pixel_size = 0.45 / maxf(icon.texture.get_width(), icon.texture.get_height())
	icon.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	icon.position.y = 0.25
	add_child(icon)
	var beam := CylinderMesh.new()
	beam.top_radius = 0.03
	beam.bottom_radius = 0.08
	beam.height = 2.5
	beam.radial_segments = 6
	beam.rings = 1
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Items.rarity_color(item) * Color(1, 1, 1, 0.35)
	beam.material = mat
	var m := MeshInstance3D.new()
	m.mesh = beam
	m.position.y = beam.height / 2
	add_child(m)


func _physics_process(delta: float) -> void:
	age += delta
	if age > LIFETIME:
		queue_free()
		return
	icon.rotation.y += delta * 2.0
	var p: Node3D = entities.player
	var to: Vector3 = p.position + Vector3.UP * 0.9 - position
	if age > DELAY and to.length() < MAGNET:
		if to.length() < PICKUP:
			count = p.inv.add(item, count)
			if count == 0:
				queue_free()
				return
		else:
			position += to.normalized() * 8.0 * delta
			return
	velocity.y = maxf(velocity.y - GRAVITY * delta, -30.0)
	var r := VoxelBody.move(entities.world, position, 0.15, 0.3, velocity * delta)
	position = r[0]
	if r[1].y != 0:
		velocity = Vector3.ZERO
