extends SceneTree
# Fluxo real menu → personagem → mundo → jogo → salvar e sair → entrar de novo, com prints dos menus:
#   xvfb-run -a -s "-screen 0 1280x720x24" .tools/godot -s tests/menu_flow.gd
# Usa diretórios de save temporários; sai com código != 0 se o save não voltar igual.

var step := 0
var frames := 0
var failures := 0
var broken := Vector3i.ZERO
var settle := 0   # quadros extras antes dos prints das listas (os cartões entram com fade)


func _initialize() -> void:
	SaveGame.players_dir = "user://flow_players/"
	SaveGame.worlds_dir = "user://flow_worlds/"
	for d in [SaveGame.players_dir, SaveGame.worlds_dir]:
		DirAccess.make_dir_recursive_absolute(d)
		for f in DirAccess.get_files_at(d):
			DirAccess.remove_absolute(d + f)
	change_scene_to_file("res://menu.tscn")


func shot(n: String) -> void:
	root.get_texture().get_image().save_png("res://textures/menu_%s.png" % n)


# Campo de nome da tela atual (ignora nós da tela anterior que ainda vão ser liberados).
func name_field() -> LineEdit:
	for n in current_scene.box.find_children("", "LineEdit", true, false):
		if not n.is_queued_for_deletion() and not n.get_parent().is_queued_for_deletion():
			return n
	return null


func type_name(text: String) -> void:
	var edit := name_field()
	check(edit != null, "campo de nome na tela")
	if edit:
		edit.text = text
		edit.text_submitted.emit(text)


func check(ok: bool, msg: String) -> void:
	if not ok:
		failures += 1
		printerr("FALHOU: ", msg)


func _process(_delta: float) -> bool:
	frames += 1
	if frames < 5:
		return false
	frames = 0
	var scene := current_scene
	if step == 0 and not (scene.world.is_idle() and scene.faded):   # espera o mundo do fundo montar e o preto sumir
		frames = 3
		return false
	if step in [1, 5] and scene.fade.color.a > 0.05:
		return false
	if step in [3, 6] and settle < 4:
		settle += 1
		return false
	settle = 0
	match step:
		0:
			shot("1_titulo")
			scene.show_players()
		1:
			shot("2b_vazio")   # lista de personagens sem nenhum, com Voltar / Novo
			scene.show_new_player()
		2:
			shot("2a_novo")   # a tela de criação, com as amostras de cor
			var swatches: Array = scene.box.find_children("", "Button", true, false).filter(func(b): return b.custom_minimum_size == Vector2(28, 28))
			var third: Button = swatches[SaveGame.SKINS.size() + SaveGame.HAIRS.size() + 2]   # a 3ª amostra de camisa
			third.pressed.emit()
			check(scene.new_look.shirt == Color(SaveGame.SHIRTS[2]) and is_instance_valid(third) and not third.is_queued_for_deletion(), "escolher uma cor não refaz a tela (a amostra continua a mesma)")
			type_name("Ana")
		3:
			shot("2_personagens")
			check(SaveGame.list(SaveGame.players_dir).size() == 1, "personagem criado pelo menu")
			scene.pick_player(SaveGame.list(SaveGame.players_dir)[0].path)
		4:
			shot("3b_mundos_vazio")
			scene.show_new_world()
		5:
			type_name("Mundo 1")
		6:
			shot("3_mundos")
			check(SaveGame.list(SaveGame.worlds_dir).size() == 1, "mundo criado pelo menu")
			scene.play(SaveGame.list(SaveGame.worlds_dir)[0].path)
		7:
			var world: Node3D = scene.get_node("World")
			if not world.is_idle() or world.center.x < 0:
				return false
			var p: Node3D = scene.get_node("Player")
			check(p.inv.total(Items.ids.copper_pickaxe) == 1, "personagem novo recebe itens iniciais")
			broken = Vector3i(p.position.floor()) + Vector3i(2, -1, 0)
			world.set_block(broken.x, broken.y, broken.z, 0)
			p.inv.add(Items.ids.gel, 7)
			p.set_menu(true)
		8:
			shot("4_pausa")
			scene.get_node("HUD")._save_and_quit()
		9:
			check(scene.name == "Menu", "Salvar e sair volta ao menu")
			scene.pick_player(SaveGame.list(SaveGame.players_dir)[0].path)
			scene.play(SaveGame.list(SaveGame.worlds_dir)[0].path)
		10:
			var world: Node3D = scene.get_node("World")
			if not world.is_idle() or world.center.x < 0:
				return false
			var p: Node3D = scene.get_node("Player")
			check(p.inv.total(Items.ids.gel) == 7 and p.inv.total(Items.ids.copper_pickaxe) == 1, "inventário voltou")
			check(world.get_block(broken.x, broken.y, broken.z) == 0, "bloco quebrado continua quebrado")
			scene.get_node("HUD")._save_and_quit()
		11:   # o botão "Mundo de teste" da tela de mundos abre a arena de teste
			check(scene.name == "Menu", "voltou ao menu")
			scene.pick_player(SaveGame.list(SaveGame.players_dir)[0].path)
			var button: Button = scene.box.find_children("", "Button", true, false).filter(func(b): return b.text == "Mundo de teste" and not b.is_queued_for_deletion()).front()
			check(button != null, "a tela de mundos tem o botão Mundo de teste")
			button.pressed.emit()
		12:
			var world: Node3D = scene.get_node("World")
			if not world.is_idle() or world.center.x < 0:
				return false
			var p: Node3D = scene.get_node("Player")
			check(world.test_world and scene.get_node("Entities").enemies.any(func(e): return e.display) and p.spawn.y == TestWorld.FLAT + 1, "o botão abre o mundo de teste com a vitrine")
			check(SaveGame.list(SaveGame.worlds_dir).size() == 2 and SaveGame.test_world() == SaveGame.world_path, "o mundo de teste ficou salvo na lista (e abre o mesmo da próxima vez)")
			p.rotation.y = 0.0
			shot("5_teste")
			print("fluxo de menu e save: " + ("OK" if failures == 0 else "%d falha(s)" % failures))
			quit(1 if failures else 0)
			return true
	step += 1
	return false
