class_name Spelunker
extends MultiMeshInstance3D
# Poção do Espeleólogo (wiki Spelunker Potion): brilhos amarelos, vistos através da terra, em minérios, baús e Life Crystals por perto.
# scan() lê os chunks já gerados com PackedByteArray.find (nativo), sem percorrer bloco a bloco.

const RADIUS := 20.0      # blocos em volta do jogador
const MAX := 96           # brilhos ao mesmo tempo
const EVERY := 0.75       # segundos entre uma varredura e outra

static var ids := PackedInt32Array()   # blocos que brilham (minérios, baú, Life Crystal)

var world: Node3D
var player: Node3D
var timer := 0.0
var spots: Array[Vector3] = []


static func load_ids() -> void:
	ids.clear()
	for n in Blocks.ids:
		if n.ends_with("_ore") or n in ["chest", "life_crystal"]:
			ids.append(Blocks.ids[n])


# Posições (centro do bloco) dos blocos que brilham a até RADIUS de `at`, nos chunks de perto.
static func scan(w: Node3D, at: Vector3) -> Array[Vector3]:
	if ids.is_empty():
		load_ids()
	var found: Array[Vector3] = []
	var c := Vector2i(floori(at.x / WorldGen.CHUNK), floori(at.z / WorldGen.CHUNK))
	var layer := WorldGen.CHUNK * WorldGen.CHUNK
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var k := c + Vector2i(dx, dz)
			if not w.chunks.has(k):
				continue
			var d: PackedByteArray = w.chunks[k]
			for id in ids:
				var i := d.find(id, 0)
				while i != -1 and found.size() < MAX:
					var p := Vector3(k.x * WorldGen.CHUNK + i % WorldGen.CHUNK + 0.5, i / layer + 0.5, k.y * WorldGen.CHUNK + (i / WorldGen.CHUNK) % WorldGen.CHUNK + 0.5)
					if p.distance_to(at) <= RADIUS:
						found.append(p)
					i = d.find(id, i + 1)
	return found


func _ready() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(1.1, 1.1)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.no_depth_test = true   # aparece através da terra
	mat.vertex_color_use_as_albedo = true
	var glow := GradientTexture2D.new()
	glow.fill = GradientTexture2D.FILL_RADIAL
	glow.fill_from = Vector2(0.5, 0.5)
	glow.fill_to = Vector2(1.0, 0.5)
	glow.gradient = Gradient.new()
	glow.gradient.colors = PackedColorArray([Color(1.0, 0.9, 0.4, 0.95), Color(1.0, 0.75, 0.2, 0.0)])
	glow.width = 32
	glow.height = 32
	mat.albedo_texture = glow
	quad.material = mat
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = quad
	multimesh.instance_count = MAX
	multimesh.visible_instance_count = 0
	top_level = true
	position = Vector3.ZERO


func _process(delta: float) -> void:
	timer -= delta
	if timer <= 0.0:
		timer = EVERY
		spots = scan(world, player.position)
		multimesh.visible_instance_count = spots.size()
	var t := Time.get_ticks_msec() / 1000.0
	for i in spots.size():   # cada brilho pulsa em fase própria
		var s := 0.85 + 0.25 * sin(t * 4.0 + i * 1.7)
		multimesh.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * s), spots[i]))
