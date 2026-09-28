extends Node
# Ciclo de dia e noite: 15 min de dia e 9 de noite, como no Terraria.
# Escurece o material dos blocos (que é sem sombreamento) e muda a cor do céu e da névoa.

const DAY_SECONDS := 15 * 60.0
const NIGHT_SECONDS := 9 * 60.0
const CYCLE := DAY_SECONDS + NIGHT_SECONDS
const SKY_DAY := Color(0.53, 0.75, 0.95)
const SKY_NIGHT := Color(0.03, 0.04, 0.1)
const NIGHT_LIGHT := 0.3

@export var world: Node3D
var time := 60.0   # segundos desde o amanhecer


func is_night() -> bool:
	return time >= DAY_SECONDS


# 1 de dia e NIGHT_LIGHT de noite, com 1 min de transição no amanhecer e no anoitecer.
func light() -> float:
	var t := 0.0 if is_night() else clampf(minf(time, DAY_SECONDS - time) / 60.0, 0, 1)
	return lerpf(NIGHT_LIGHT, 1.0, t)


func clock() -> String:
	var hours := fmod(4.5 + time / CYCLE * 24.0, 24.0)  # amanhecer às 4:30
	return "%02d:%02d" % [int(hours), int(fmod(hours, 1.0) * 60)]


func _process(delta: float) -> void:
	time = fmod(time + delta, CYCLE)
	var l := light()
	world.material.albedo_color = Color(l, l, l)
	var env := world.get_world_3d().environment
	if env:
		var sky := SKY_NIGHT.lerp(SKY_DAY, (l - NIGHT_LIGHT) / (1.0 - NIGHT_LIGHT))
		env.background_color = sky
		env.fog_light_color = sky
