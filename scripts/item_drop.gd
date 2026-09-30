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
var delay := DELAY
var doll := false        # Guide Voodoo Doll: largada na lava do submundo, chama o chefe (wiki)
var icon: Sprite3D


func _ready() -> void:
	doll = Items.defs[item].get("underworld", false)
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
	if age > delay and to.length() < MAGNET:
		if to.length() < PICKUP:
			var pk: Dictionary = Items.defs[item].get("pickup", {})
			if not pk.is_empty():   # coração / estrela: curam na hora
				p.pickup(pk)
				Sfx.play(entities, "pickup", p.position + Vector3.UP, -8.0)
				queue_free()
				return
			var before := count
			count = p.inv.add(item, count)
			if count < before:
				Sfx.play(entities, "coin" if Inventory.coin_kind(item) != -1 else "pickup", p.position + Vector3.UP, -8.0)
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
	if doll and position.y < WorldGen.UNDERWORLD_TOP and entities.boss == null:
		var b: int = entities.world.get_block(floori(position.x), floori(position.y), floori(position.z))
		if Blocks.liquid[b] == 1 and Blocks.liquid_kind[b] == Blocks.ids.lava:   # (outros itens na lava só afundam; a wiki os queima)
			var boss: Node3D = entities.spawn_boss(Items.defs[item].summon)
			p.say("%s despertou!" % Items.title(boss.def.name))
			count -= 1
			if count <= 0:
				queue_free()
