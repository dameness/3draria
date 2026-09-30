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
var doll := false        # Guide Voodoo Doll: ao queimar na lava do submundo chama o Wall of Flesh (wiki)
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
	if _burns() and _in_lava():
		_burn()


# Lava (wiki): item de raridade 0 (moedas incluídas) ou -1, fora os lava_safe, queima ao boiar nela (ponto médio do item abaixo da superfície).
func _burns() -> bool:
	var d: Dictionary = Items.defs[item]
	var r: int = d.get("rarity", 0)
	return r == -1 or (r == 0 and not d.get("lava_safe", false))


func _in_lava() -> bool:
	var at := position + Vector3.UP * 0.25
	var b: int = entities.world.get_block(floori(at.x), floori(at.y), floori(at.z))
	return Blocks.liquid[b] == 1 and Blocks.liquid_kind[b] == Blocks.ids.lava and Blocks.liquid_level[b] / 8.0 > fposmod(at.y, 1.0)


# Guide Voodoo Doll (wiki): ao queimar, o Guide morre; no submundo, com ele vivo e sem chefe, o Wall of Flesh nasce (uma vez, por mais que a pilha seja grande).
func _burn() -> void:
	var d: Dictionary = Items.defs[item]
	if doll and entities.kill_guide() and position.y < WorldGen.UNDERWORLD_TOP and entities.boss == null:
		var boss: Node3D = entities.spawn_boss(d.summon)
		entities.player.say("%s despertou!" % Items.title(boss.def.name))
	Fx.puff(entities, position + Vector3.UP * 0.3, Color("#5a5048"), 8)
	Fx.sparks(entities, position + Vector3.UP * 0.3, Color("#ff9a3a"), 8, Vector3.UP)
	Sfx.play(entities, "hit", position, -12.0, 1.6)
	queue_free()
