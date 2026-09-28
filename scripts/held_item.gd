extends Node3D
# O item da mão em 3D (visão em 1ª pessoa), com animação pelo estilo de uso:
# swing (golpe em arco), thrust (estocada), shoot (recuo), hold (parado). Filho da câmera.

const REST := Vector3(0.3, -0.34, -0.5)   # posição da mão em relação à câmera
const LENGTH := 0.55                       # tamanho do maior lado do item, em blocos

@export var player: Node3D
var mesh: MeshInstance3D
var shown := -2


func _ready() -> void:
	mesh = MeshInstance3D.new()
	add_child(mesh)
	position = REST


# Estilo de uso: campo "use_style" do item, senão deduzido (munição → shoot, arma/ferramenta → swing).
static func style(id: int) -> String:
	var d: Dictionary = Items.defs[id]
	if d.has("use_style"):
		return d.use_style
	if d.has("ammo"):
		return "shoot"
	if d.get("damage", 0) > 0 or Items.pick_power[id] > 0:
		return "swing"
	return "hold"


# Pose da mão para o estilo em t (0 = início do uso, 1 = fim). Fora do uso: descanso.
static func pose(st: String, t: float) -> Transform3D:
	var tr := Transform3D(Basis(), REST)
	match st:
		"swing":
			tr.basis = Basis(Vector3.RIGHT, lerpf(0.9, -1.3, ease(t, 0.5)))
		"thrust":
			tr.origin += Vector3(-0.1, 0.08, -0.35) * sin(PI * t)
		"shoot":
			tr.origin += Vector3(0, 0, 0.08) * (1.0 - t)
	return tr


func _process(_delta: float) -> void:
	var id: int = player.held()
	if id != shown:
		shown = id
		mesh.visible = id != -1
		if id != -1:
			_show(id)
	if id == -1:
		return
	var st := style(id)
	var dur: float = Items.defs[id].get("use_time", 0.25)
	var t: float = 1.0 - player.cooldown / dur if player.cooldown > 0 else 1.0
	transform = pose(st, clampf(t, 0, 1))


func _show(id: int) -> void:
	var st := style(id)
	var m := ItemModel.for_item(id, player.entities.icon(id), LENGTH if st != "hold" else LENGTH * 0.5)
	mesh.mesh = m[0]
	mesh.material_override = m[1]
	# Sprites de arma do Terraria apontam para cima-direita: gira 45° para a lâmina ficar para cima
	# com o cabo na mão; arco fica de lado; o resto fica centrado.
	var aabb: AABB = m[0].get_aabb()
	match st:
		"swing", "thrust":
			mesh.transform = Transform3D(Basis(Vector3.BACK, deg_to_rad(45)), Vector3.ZERO)
			mesh.rotate_object_local(Vector3.UP, deg_to_rad(-25))
		_:
			mesh.transform = Transform3D(Basis(Vector3.UP, deg_to_rad(-25)), -aabb.get_center().rotated(Vector3.UP, deg_to_rad(-25)))
