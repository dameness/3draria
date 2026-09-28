extends SceneTree
# Prévia dos personagens (corpo em blocos arredondados + armaduras) de frente, lado e costas, sem abrir o jogo:
#   xvfb-run -a -s "-screen 0 1280x720x24" .tools/godot -s tests/character_preview.gd [-- conjunto1 conjunto2 ...]
# Salva textures/personagens.png (fora do git). Sem argumentos: sem armadura + os conjuntos de metal.

const SETS := ["", "copper", "iron", "gold", "platinum"]


# O que o PlayerModel lê de um jogador.
class Dummy extends Node3D:
	var velocity := Vector3.ZERO
	var pitch := 0.0
	var cooldown := 0.0
	var inv := Inventory.new()
	var atlas: Texture2D
	var entities: Object = self   # PlayerModel pede os ícones por aqui
	func held() -> int:
		return -1
	func icon(id: int) -> Texture2D:
		return Items.icon_texture(id, atlas)


var frames := 0


func _initialize() -> void:
	Blocks.load_pack()
	Items.load_pack()
	var atlas := ImageTexture.create_from_image(Atlas.build(Blocks.textures))
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#8fb4d8")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#c0c8dc")
	env.ambient_light_energy = 0.6
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.9, 0.6, 0)
	root.add_child(sun)
	var names := SETS
	if OS.get_cmdline_user_args().size() > 0:
		names = Array(OS.get_cmdline_user_args())
	for i in names.size():
		for view in 3:   # frente, três quartos, costas
			var d := Dummy.new()
			d.atlas = atlas
			if names[i] != "":
				for k in 3:
					d.inv.equip[k] = Items.ids["%s_%s" % [names[i], ["helmet", "chainmail", "greaves"][k]]]
			var m: Node3D = load("res://scripts/player_model.gd").new()
			m.player = d
			d.add_child(m)
			d.position = Vector3((i - (names.size() - 1) / 2.0) * 1.25, -view * 2.15, 0)
			d.rotation.y = [0.0, PI / 4, PI][view] + PI * 0   # frente para a câmera (o modelo olha para -Z)
			root.add_child(d)
	var cam := Camera3D.new()
	cam.position = Vector3(0, -2.15 + 0.9, 11.0 + names.size() * 0.5)
	cam.fov = 36
	root.add_child(cam)
	cam.current = true
	root.size = Vector2i(1280, 720)


func _process(_delta: float) -> bool:
	frames += 1
	if frames == 8:
		DirAccess.make_dir_recursive_absolute("res://textures")
		root.get_texture().get_image().save_png("res://textures/personagens.png")
		print("salvo textures/personagens.png")
		quit()
		return true
	return false
