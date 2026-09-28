extends CanvasLayer
# Mira, hotbar e texto de depuração (fps, distância de renderização, posição).

@export var world: Node3D
@export var player: Node3D
@onready var info: Label = $Info
@onready var bar: HBoxContainer = $Hotbar


func _ready() -> void:
	for id in player.hotbar:
		var icon := AtlasTexture.new()
		icon.atlas = world.material.albedo_texture
		icon.region = Rect2(Blocks.tiles[id * Blocks.FACES] * Atlas.TILE, 0, Atlas.TILE, Atlas.TILE)
		var slot := TextureRect.new()
		slot.texture = icon
		slot.custom_minimum_size = Vector2(48, 48)
		slot.stretch_mode = TextureRect.STRETCH_SCALE
		slot.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		bar.add_child(slot)


func _process(_delta: float) -> void:
	for i in bar.get_child_count():
		bar.get_child(i).modulate = Color.WHITE if i == player.slot else Color(1, 1, 1, 0.35)
	var p: Vector3 = player.position
	info.text = "FPS %d | distância %d chunks (+/-) | %s | bloco: %s\npos %d %d %d" % [
		Engine.get_frames_per_second(), world.render_distance, "voo (F)" if player.flying else "andando (F voa)",
		Blocks.ids.keys()[player.hotbar[player.slot]], p.x, p.y, p.z]
