extends Node
# Ciclo de dia e noite: 15 min de dia e 9 de noite, como no Terraria.
# Escurece a luz do céu dos blocos (shader) e o sol dos modelos, e dirige o céu (shaders/sky.gdshader):
# cores, direção do sol e da lua, nuvens, e a névoa na cor do horizonte.

const DAY_SECONDS := 15 * 60.0
const NIGHT_SECONDS := 9 * 60.0
const CYCLE := DAY_SECONDS + NIGHT_SECONDS
const NIGHT_LIGHT := 0.2
const ZENITH := [Color("#070a1e"), Color("#3a78d6")]    # noite, dia
const HORIZON := [Color("#111830"), Color("#b3d5f0")]
const DUSK := Color("#ff8a4a")
const TINT := [Vector3(0.85, 1.05, 1.5), Vector3.ONE]   # cor da luz do céu nos blocos: luar azulado, dia branco
const DUSK_TINT := Vector3(1.0, 0.74, 0.58)

@export var world: Node3D
@export var sun: DirectionalLight3D   # ilumina só os modelos (jogador, itens); os blocos são sem sombreamento
var time := 60.0   # segundos desde o amanhecer
var sky := ShaderMaterial.new()


func is_night() -> bool:
	return time >= DAY_SECONDS


# 1 de dia e NIGHT_LIGHT de noite, com 1 min de transição no amanhecer e no anoitecer.
func light() -> float:
	var t := 0.0 if is_night() else clampf(minf(time, DAY_SECONDS - time) / 60.0, 0, 1)
	return lerpf(NIGHT_LIGHT, 1.0, t)


func clock() -> String:
	var hours := fmod(4.5 + time / CYCLE * 24.0, 24.0)  # amanhecer às 4:30
	return "%02d:%02d" % [int(hours), int(fmod(hours, 1.0) * 60)]


# Direção para o sol: nasce a leste (+X) no amanhecer, passa por cima (um pouco ao sul) e se põe a oeste.
# De noite continua o arco por baixo do mundo; a lua fica do lado oposto.
func sun_dir() -> Vector3:
	var a := PI * time / DAY_SECONDS if time < DAY_SECONDS else PI + PI * (time - DAY_SECONDS) / NIGHT_SECONDS
	return Vector3(cos(a), sin(a), 0.3).normalized()


func _ready() -> void:
	var env := world.get_world_3d().environment
	if env == null:
		return
	sky.shader = preload("res://shaders/sky.gdshader")
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = 0.012
	n.fractal_octaves = 4
	sky.set_shader_parameter("noise", ImageTexture.create_from_image(n.get_seamless_image(256, 256)))
	var s := Sky.new()
	s.sky_material = sky
	s.process_mode = Sky.PROCESS_MODE_REALTIME
	env.sky = s
	env.background_mode = Environment.BG_SKY
	env.fog_sky_affect = 0.0   # o céu cuida do próprio horizonte
	_process(0.0)


func _process(delta: float) -> void:
	time = fmod(time + delta, CYCLE)
	var l := light()
	var sd := sun_dir()
	var day := smoothstep(-0.1, 0.3, sd.y)   # claridade do céu; os blocos seguem light()
	var dusk := (1.0 - smoothstep(0.0, 0.4, absf(sd.y))) * smoothstep(-0.25, -0.02, sd.y)
	var horizon: Color = HORIZON[0].lerp(HORIZON[1], day).lerp(DUSK, dusk * 0.35)
	world.material.set_shader_parameter("daylight", l)
	world.material.set_shader_parameter("sky_tint", TINT[0].lerp(TINT[1], day).lerp(DUSK_TINT, dusk * 0.6))
	sky.set_shader_parameter("zenith", ZENITH[0].lerp(ZENITH[1], day))
	sky.set_shader_parameter("horizon", horizon)
	sky.set_shader_parameter("sun_dir", sd)
	sky.set_shader_parameter("moon_dir", -sd)
	sky.set_shader_parameter("day", day)
	sky.set_shader_parameter("cloud_time", time)
	if sun:
		sun.basis = Basis.looking_at(-sd if sd.y > 0 else sd)   # a luz vem do sol; sem sol, da lua
		sun.light_energy = l
		sun.light_color = Color.WHITE.lerp(DUSK, dusk * 0.5) if sd.y > 0 else Color("#9fb4ff")
	var env := world.get_world_3d().environment
	if env:
		env.fog_light_color = horizon
		env.ambient_light_energy = lerpf(0.3, 0.6, day)
		env.ambient_light_color = Color("#5a6aa8").lerp(Color("#c0c8dc"), day)
