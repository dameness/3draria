extends Control
# Menu inicial como no Terraria: Um jogador → escolher/criar personagem → escolher/criar mundo → jogar.
# Multijogador fica desativado por enquanto. Os arquivos ficam em user:// (ver save_game.gd).

var box: VBoxContainer
var chosen_player := ""


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.1, 0.18)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	box = VBoxContainer.new()
	box.custom_minimum_size = Vector2(420, 0)
	box.add_theme_constant_override("separation", 10)
	center.add_child(box)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	show_title()


func _clear(title: String, size := 22) -> void:
	for c in box.get_children():
		c.queue_free()
	var l := Label.new()
	l.text = title
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	box.add_child(l)


func _button(text: String, action: Callable, disabled := false, parent: Control = box) -> Button:
	var b := Button.new()
	b.text = text
	b.disabled = disabled
	b.custom_minimum_size = Vector2(0, 40)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(action)
	parent.add_child(b)
	return b


func show_title() -> void:
	_clear("3draria", 48)
	_button("Um jogador", show_players)
	_button("Multijogador (em breve)", func(): pass, true)
	_button("Sair", func(): get_tree().quit())


# Lista de saves com botão de escolher e de apagar (apagar pede um segundo clique).
func _save_list(dir: String, pick: Callable) -> void:
	for s in SaveGame.list(dir):
		var row := HBoxContainer.new()
		_button(s.name, pick.bind(s.path), false, row)
		var del := Button.new()
		del.text = "apagar"
		del.custom_minimum_size = Vector2(90, 40)
		del.pressed.connect(func():
			if del.text == "apagar":
				del.text = "confirmar?"
			else:
				SaveGame.delete(s.path)
				_refresh(dir))
		row.add_child(del)
		box.add_child(row)


func _refresh(dir: String) -> void:
	if dir == SaveGame.players_dir:
		show_players()
	else:
		show_worlds()


# Campo de nome + botão criar; `create` recebe o nome e retorna o caminho ("" se inválido/repetido).
func _create_row(hint: String, create: Callable, after: Callable) -> void:
	var row := HBoxContainer.new()
	var name_edit := LineEdit.new()
	name_edit.placeholder_text = hint
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_edit.custom_minimum_size = Vector2(0, 40)
	row.add_child(name_edit)
	var status := Label.new()
	var make := func(_t = ""):
		var path: String = create.call(name_edit.text)
		if path == "":
			status.text = "nome vazio ou já existe"
		else:
			after.call(path)
	name_edit.text_submitted.connect(make)
	_button("Criar", make, false, row).custom_minimum_size = Vector2(90, 40)
	box.add_child(row)
	box.add_child(status)


func show_players() -> void:
	_clear("Escolha o personagem")
	_save_list(SaveGame.players_dir, pick_player)
	_create_row("nome do novo personagem", SaveGame.create_player, func(_p): show_players())
	_button("Voltar", show_title)


func pick_player(path: String) -> void:
	chosen_player = path
	show_worlds()


func show_worlds() -> void:
	_clear("Escolha o mundo")
	_save_list(SaveGame.worlds_dir, play)
	_create_row("nome do novo mundo", func(n): return SaveGame.create_world(n, randi()), func(_p): show_worlds())
	_button("Voltar", show_players)


func play(world_path: String) -> void:
	SaveGame.player_path = chosen_player
	SaveGame.world_path = world_path
	get_tree().change_scene_to_file("res://game.tscn")
