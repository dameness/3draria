extends SceneTree
# Prévia dos personagens (corpo em blocos arredondados + armaduras), sem abrir o jogo:
#   xvfb-run -a -s "-screen 0 1280x720x24" .tools/godot -s tests/character_preview.gd [-- conjunto1 conjunto2 ... opções]
# Salva textures/personagens.png (fora do git). Sem conjuntos: sem armadura + os de metal, de frente, três quartos e costas.
# Opções: big (um conjunto por linha, 4 vistas grandes: frente, 3/4, lado, costas), walk (pose de caminhada),
# swing (meio do golpe), seq (o golpe em 5 quadros, de lado), item:nome (item na mão), none (sem armadura),
# name:Fulano (aparência tirada do nome, como no jogo).

const SETS := ["none", "copper", "iron", "gold", "platinum"]


# O que o PlayerModel lê de um jogador.
class Dummy extends Node3D:
	var velocity := Vector3.ZERO
	var pitch := 0.0
	var cooldown := 0.0
	var inv := Inventory.new()
	var atlas: Texture2D
	var item := -1
	var entities: Object = self   # PlayerModel pede os ícones por aqui
	func held() -> int:
		return item
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
	var args := Array(OS.get_cmdline_user_args())
	var big := args.has("big")
	var item := -1
	var who := ""
	var names := []
	for a in args:
		if a.begins_with("item:"):
			item = Items.ids[a.substr(5)]
		elif a.begins_with("name:"):
			who = a.substr(5)
		elif not a in ["big", "walk", "swing", "seq"]:
			names.append(a)
	if names.is_empty():
		names = SETS
	var seq := args.has("seq")
	var views := 5 if seq else 4 if big else 3
	for i in names.size():
		for view in views:
			var d := Dummy.new()
			d.atlas = atlas
			d.item = item
			if names[i] != "none":
				for k in 3:
					d.inv.equip[k] = Items.ids["%s_%s" % [names[i], ["helmet", "chainmail", "greaves"][k]]]
			var m: Node3D = load("res://scripts/player_model.gd").new()
			m.player = d
			if who != "":   # mesma aparência que o jogo dá a um personagem com este nome
				var h := who.hash()
				m.skin = Color(SaveGame.SKINS[h % SaveGame.SKINS.size()])
				m.hair = Color(SaveGame.HAIRS[(h >> 3) % SaveGame.HAIRS.size()])
				m.shirt = Color(SaveGame.SHIRTS[(h >> 6) % SaveGame.SHIRTS.size()])
				m.pants = Color(SaveGame.PANTS[(h >> 9) % SaveGame.PANTS.size()])
			if args.has("walk"):
				d.velocity = Vector3(4.5, 0, 0)
				m.phase = 1.2
			if args.has("swing"):
				d.cooldown = 0.13
			if seq:   # o golpe em 5 quadros (do começo ao fim de use_time), sempre de lado
				d.cooldown = Items.defs[item].get("use_time", 0.25) * (0.96 - 0.23 * view)
			d.add_child(m)
			if seq:
				d.position = Vector3((view - 2) * 1.5, -i * 2.3, 0)
				d.rotation.y = -PI / 2   # de lado, olhando para a direita da imagem
			elif big:
				d.position = Vector3((view - 1.5) * 1.35, -i * 2.3, 0)
				d.rotation.y = [0.0, PI / 4, PI / 2, PI][view] + PI   # o modelo olha para -Z: PI = de frente para a câmera
			else:
				d.position = Vector3((i - (names.size() - 1) / 2.0) * 1.25, -view * 2.15, 0)
				d.rotation.y = [0.0, PI / 4, PI][view]
			root.add_child(d)
	var cam := Camera3D.new()
	if big or seq:
		cam.position = Vector3(0, 0.9 - (names.size() - 1) * 1.15, maxf(7.2 if seq else 6.2, names.size() * 4.3))
		cam.fov = 30
	else:
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
