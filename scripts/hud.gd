extends Label
# Texto de depuração: fps, distância de renderização e posição.

@export var world: Node3D


func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	text = "FPS %d | distância %d chunks (+/-) | chunks %d | pos %v" % [
		Engine.get_frames_per_second(), world.render_distance, world.meshes.size(), cam.position.floor()]
