extends Node3D
# O item da mão em 3D (visão em 1ª pessoa) e o braço do personagem que o segura, animados pelo estilo de uso:
# swing (golpe em arco), thrust (estocada), shoot (recuo), hold (parado). Filho da câmera.
# A mão tem inércia (fica para trás ao girar a câmera), balança ao andar e dá um empurrão ao colocar bloco.
# Efeitos do item ("effects" em items.json): glow (halo aditivo com a silhueta), trail (arco do golpe), particles (faíscas).
# Toda arma de golpe deixa um arco pálido (Trail), na cor de effects.trail se o item tiver.

const REST := Vector3(0.34, -0.36, -0.62)  # posição da mão em relação à câmera
const ROLL := -90.0                        # giro da arma de golpe em torno do eixo da lâmina, em graus (-90 = o plano do sprite acompanha o golpe para a frente, como na 3ª pessoa)
const GRIP := 0.3                         # onde a mão segura a ferramenta, de 0 (ponta do cabo) a 1 (a ponta da cabeça), ao longo do sprite
const LENGTH := 0.42                       # tamanho do maior lado do item, em blocos
const SHOULDER := Vector3(0.55, -1.0, 0.4)    # o ombro (no espaço da câmera) fica fora da tela: o braço vem do canto de baixo à direita
const PLACE_TIME := 0.18                   # duração do empurrão ao colocar bloco (player.gd place_anim)

@export var player: Node3D

var mesh: MeshInstance3D
var grip: Node3D               # flail: a pegada 3D (cabo e corrente) no lugar do sprite do item
var shown := -2
var glow: MeshInstance3D
var sparks: CPUParticles3D
var trail: Trail
var trail_on := false          # o item atual deixa arco
var arm: Node3D
var arm_mesh: MeshInstance3D
var arm_look := {}             # cores do personagem com que o braço foi montado
var sway := Vector2.ZERO       # deslocamento da mão pela rotação da câmera (yaw, pitch)
var last_yaw := 0.0
var last_pitch := 0.0


func _ready() -> void:
	mesh = MeshInstance3D.new()
	add_child(mesh)
	trail = Trail.new()
	add_child(trail)
	_build_arm()
	position = REST


# Braço em 1ª pessoa: punho na mão (o cabo do item fica nele) e antebraço + manga esticados até o ombro, que fica fixo na câmera:
# a cada quadro o braço gira para o ombro, então a mão balança no golpe sem soltar do corpo.
func _build_arm() -> void:
	arm = Node3D.new()
	arm.top_level = true
	add_child(arm)
	arm_mesh = MeshInstance3D.new()   # voxels como o corpo: a malha vem do personagem (_sync_arm)
	arm_mesh.material_override = VoxMesh.material(0.9)
	arm.add_child(arm_mesh)
	_sync_arm()


# Estilo de uso: campo "use_style" do item, senão deduzido (munição → shoot, arma/ferramenta → swing).
static func style(id: int) -> String:
	var d: Dictionary = Items.defs[id]
	if d.has("use_style"):
		return d.use_style
	if d.has("ammo") or (d.get("sprite_angle", 45.0) == 0.0 and d.get("damage", 0) > 0):   # arco, arma de fogo (sprite deitado)
		return "shoot"
	if d.get("damage", 0) > 0 or Items.pick_power[id] > 0 or Items.axe_power[id] > 0 or d.has("bucket"):
		return "swing"
	return "hold"


# Pose da mão para o estilo em t (0 = início do uso, 1 = fim). Fora do uso: descanso.
static func pose(st: String, t: float) -> Transform3D:
	var tr := Transform3D(Basis(), REST)
	match st:
		"swing":   # golpe para a frente (para dentro da tela, no sentido da mira): ergue a arma atrás/alto, desce batendo para a frente até o cursor e, nos últimos 30%, volta ao descanso
			var w := 1.0 - smoothstep(0.7, 1.0, t)
			var e := smoothstep(0.0, 0.7, t)
			tr.basis = Basis(Vector3.RIGHT, lerpf(0.8, -0.9, e) * w) * Basis(Vector3.BACK, lerpf(-0.15, 0.05, e) * w)
			tr.origin += Vector3(lerpf(0.04, -0.1, e), lerpf(0.22, -0.12, e), lerpf(0.12, -0.4, e)) * w
		"thrust":
			tr.origin += Vector3(-0.1, 0.08, -0.35) * sin(PI * t)
		"shoot":
			tr.origin += Vector3(0, 0, 0.08) * (1.0 - t)
	return tr


func _process(delta: float) -> void:
	_sync_arm()
	var id: int = player.held()
	if id != shown:
		shown = id
		mesh.visible = id != -1
		if id != -1:
			_show(id)
	var st := style(id) if id != -1 else "hold"
	var dur: float = player.use_len if id != -1 else 0.25
	var t: float = 1.0 - player.cooldown / dur if player.cooldown > 0 else 1.0
	var tr := pose(st, clampf(t, 0, 1))
	if grip:
		tr = _flail_pose(tr)
	# inércia ao girar a câmera, balanço ao andar e o empurrão de colocar bloco
	var yaw: float = player.rotation.y
	var vel := Vector2(wrapf(yaw - last_yaw, -PI, PI), player.pitch - last_pitch) / maxf(delta, 0.001)
	last_yaw = yaw
	last_pitch = player.pitch
	sway = sway.lerp((vel * 0.012).limit_length(0.22), 1.0 - exp(-10.0 * delta))
	tr.origin += Vector3(sway.x, -sway.y, 0) * 0.9
	tr.basis = Basis(Vector3.UP, sway.x * 0.6) * Basis(Vector3.RIGHT, -sway.y * 0.6) * tr.basis
	var walk: float = clampf(Vector2(player.velocity.x, player.velocity.z).length() / player.WALK, 0.0, 1.4) if player.on_floor and not player.creative else 0.0
	tr.origin += Vector3(cos(player.bob * 0.5) * 0.012, -absf(sin(player.bob)) * 0.02, 0) * walk
	if player.place_anim > 0.0:
		tr.origin += Vector3(0, 0.03, -0.14) * sin(PI * (1.0 - player.place_anim / PLACE_TIME))
	transform = tr
	var cam: Node3D = get_parent()
	var to_shoulder: Vector3 = (cam.global_transform * SHOULDER - global_position).normalized()
	arm.global_transform = Transform3D(Basis(Quaternion(Vector3.UP, to_shoulder)), global_position)
	if id == -1:
		return
	var using: bool = player.cooldown > 0
	if sparks:
		sparks.emitting = using
	if using and trail_on:
		var box: AABB = mesh.mesh.get_aabb()
		trail.push(mesh.global_transform * box.end, mesh.global_transform * (box.position + box.size * 0.6))


# Cores do braço: as do personagem (pele e camiseta do PlayerModel).
func _sync_arm() -> void:
	var model: Node = player.get_node_or_null("Model") if player else null
	var look := {"skin": model.skin, "hair": model.hair, "shirt": model.shirt, "pants": model.pants} if model else {"skin": Color(VoxRecipes.LOOK.skin), "hair": Color(VoxRecipes.LOOK.hair), "shirt": Color(VoxRecipes.LOOK.shirt), "pants": Color(VoxRecipes.LOOK.pants)}
	if look != arm_look:
		arm_look = look
		arm_mesh.mesh = VoxRecipes.part_mesh("body", "fparm", look, VoxMesh.FP_V)


func _additive(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = false
	m.albedo_color = c
	return m


# Flail: pegada 3D (cabo com a bola pendurada; a bola some quando é arremessada) em vez do sprite do item.
func _show_flail(id: int) -> void:
	for n in [glow, sparks]:
		if n:
			n.queue_free()
	glow = null
	sparks = null
	trail_on = false
	mesh.mesh = null
	var mount := Basis(Vector3.RIGHT, -1.0)   # o cabo aponta para a frente e para cima
	mesh.transform = Transform3D(mount, Vector3(0, -0.05, 0.02))
	grip = Projectile.flail_grip(player.entities.projectiles[Items.defs[id].flail], 1.0, mount.inverse() * Vector3.DOWN)
	mesh.add_child(grip)


# Pose da mão com o flail: girando, o braço sobe e faz círculos junto com a bola; solto, dá um chicote para a frente; fora, fica esticado.
func _flail_pose(tr: Transform3D) -> Transform3D:
	var fs: String = player.flail_state()
	grip.get_node("tip/idle").visible = fs == ""
	if fs == "spin":
		var s: float = player.flail.spin
		tr.origin += Vector3(cos(s) * 0.05, 0.1 + sin(s) * 0.05, -0.2)
		tr.basis = Basis(Vector3.RIGHT, -0.3) * tr.basis
	elif fs != "":
		tr.origin += Vector3(0, 0.06, -0.15)
	if player.flail_snap > 0.0:
		var k := sin(PI * (1.0 - player.flail_snap / 0.3))
		tr.origin += Vector3(0, 0.05, -0.32) * k
		tr.basis = Basis(Vector3.RIGHT, -0.7 * k) * tr.basis
	return tr


# Ponta do cabo (de onde sai a corrente da bola), no mundo.
func flail_tip() -> Vector3:
	return grip.get_node("tip").global_position if grip else global_position


func _show(id: int) -> void:
	if grip:
		grip.queue_free()
		grip = null
	if Items.defs[id].has("flail"):
		_show_flail(id)
		return
	var st := style(id)
	var m := ItemModel.for_item(id, player.entities.icon(id), LENGTH if st != "hold" else LENGTH * 0.5)
	mesh.mesh = m[0]
	mesh.material_override = m[1]
	# Gira a direção do sprite (sprite_angle; armas do Terraria: 45° = cima-direita) para cima,
	# com o cabo na mão; arco e o resto ficam centrados.
	var aabb: AABB = m[0].get_aabb()
	for n in [glow, sparks]:
		if n:
			n.queue_free()
	glow = null
	sparks = null
	var fx: Dictionary = Items.defs[id].get("effects", {})
	trail_on = fx.has("trail") or (st in ["swing", "thrust"] and Items.defs[id].get("damage", 0) > 0 and Items.pick_power[id] == 0 and Items.axe_power[id] == 0)
	trail.color = Color(fx.trail) if fx.has("trail") else Color(0.92, 0.96, 1.0)
	if fx.has("glow"):
		glow = MeshInstance3D.new()
		glow.mesh = m[0]
		var gm := _additive(Color(Color(fx.glow), 0.16))
		glow.material_override = gm
		var c := aabb.get_center()
		glow.transform = Transform3D(Basis().scaled(Vector3.ONE * 1.08), c - c * 1.08)
		mesh.add_child(glow)
	if fx.has("particles"):
		sparks = CPUParticles3D.new()
		sparks.amount = 24
		sparks.lifetime = 0.4
		sparks.local_coords = false
		sparks.emitting = false
		sparks.direction = Vector3.UP
		sparks.spread = 60
		sparks.initial_velocity_min = 0.3
		sparks.initial_velocity_max = 0.8
		sparks.gravity = Vector3(0, -0.5, 0)
		sparks.scale_amount_min = 0.5
		var q := QuadMesh.new()
		q.size = Vector2.ONE * 0.025
		var qm := _additive(Color(fx.particles))
		qm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		q.material = qm
		sparks.mesh = q
		sparks.position = aabb.end * 0.9
		mesh.add_child(sparks)
	match st:
		"swing", "thrust":
			var ang: float = Items.defs[id].get("sprite_angle", 45.0)
			var tool: bool = Items.pick_power[id] > 0 or Items.axe_power[id] > 0 or Items.hammer_power[id] > 0
			var blade := Vector3(aabb.end.x, aabb.end.y, 0).normalized()   # o eixo maior do sprite: do canto da empunhadura ao da ponta
			var roll := ROLL if tool else -ROLL   # a cabeça da ferramenta vai para a frente; na espada é o fio que vai (o giro oposto)
			mesh.transform = Transform3D(Basis(Vector3.BACK, deg_to_rad(90.0 - ang)) * Basis(blade, deg_to_rad(roll)), Vector3.ZERO)
			if tool:   # a mão segura o cabo no meio, não na ponta: o ponto de empunhadura sobe ao longo do sprite
				mesh.position = -(mesh.transform.basis * (GRIP * Vector3(aabb.end.x, aabb.end.y, 0)))
		_:
			# arma de fogo: o cano aponta para a mira (o sprite visto por trás, espelhado); arco/poção/gancho: sobem para não sair da tela
			var yaw := 150.0 if Items.defs[id].get("sprite_angle", 45.0) == 0.0 and st == "shoot" else -25.0
			var basis := Basis(Vector3.UP, deg_to_rad(yaw))
			mesh.transform = Transform3D(basis, -(basis * aabb.get_center()) + Vector3(0, aabb.size.y * 0.22 + 0.04, 0))
