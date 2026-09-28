extends Control
# Menu inicial como no Terraria, com o mundo de verdade ao fundo: Um jogador → personagem → mundo → jogar.
# O fundo é o mundo real (world.gd + day_night.gd, distância 4) com a câmera girando devagar em volta da planície de
# nascimento e o dia passando depressa; o personagem escolhido (PlayerModel, com a armadura salva) aparece de pé no gramado,
# à esquerda, e a lista fica num painel à direita. Multijogador fica desativado por enquanto. Saves em user:// (save_game.gd).

# O que o PlayerModel lê de um jogador (ver tests/character_preview.gd).
class Avatar extends Node3D:
	var velocity := Vector3.ZERO
	var pitch := 0.0
	var cooldown := 0.0
	var on_floor := true
	var inv := Inventory.new()
	var atlas: Texture2D
	var entities: Object = self   # PlayerModel pede os ícones por aqui
	func held() -> int:
		return -1
	func icon(id: int) -> Texture2D:
		return Items.icon_texture(id, atlas)


const SPAWN := Vector2(128.5, 128.5)   # meio da planície de nascimento (world_gen.gd: sem árvores num raio de 26)
# Vistas da câmera: r = distância do centro, h = altura acima do chão, ty = altura do ponto olhado, side = quanto o ponto
# olhado fica à direita do personagem (ele aparece à esquerda), speed = giro em rad/s (0 = balança de leve).
const TITLE_VIEW := {"r": 13.0, "h": 3.2, "ty": 5.6, "side": 0.0, "speed": 0.03}
const AVATAR_VIEW := {"r": 3.7, "h": 1.45, "ty": 1.0, "side": 1.2, "speed": 0.0}
const DAY_SPEED := 9.0                 # o dia passa 9x mais depressa ao fundo
const LIST_ROW := 66                   # altura de uma linha da lista (nome + informação)

var box: VBoxContainer                 # conteúdo da tela atual (botões, lista, campo de nome)
var chosen_player := ""
var screen := "title"                  # title | players | worlds
var world: Node3D
var clock: Node
var cam: Camera3D
var avatar: Node3D
var view := TITLE_VIEW.duplicate()     # vista atual da câmera: segue a da tela por interpolação
var want := TITLE_VIEW
var angle := 0.6
var elapsed := 0.0
var ground := 76.0
var faded := false
var panel: PanelContainer
var logo: Control
var fade: ColorRect


func _ready() -> void:
	theme = Ui.theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	SaveGame.player_path = ""   # voltar do jogo para cá: a escolha recomeça
	SaveGame.world_path = ""
	_build_backdrop()
	_build_ui()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	show_title()


# O mundo de verdade, o céu e o dia, igual ao jogo (game.tscn), só que com distância de renderização 4.
func _build_backdrop() -> void:
	var back := Node3D.new()
	back.name = "Backdrop"
	add_child(back)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.53, 0.75, 0.95)
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = Color(0.53, 0.75, 0.95)
	env.fog_density = 1.0
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.78, 0.85)
	env.ambient_light_energy = 0.6
	var we := WorldEnvironment.new()
	we.environment = env
	back.add_child(we)
	world = load("res://scripts/world.gd").new()
	world.name = "World"
	world.render_distance = 4
	back.add_child(world)   # carrega blocos e itens no _ready
	var sun := DirectionalLight3D.new()
	back.add_child(sun)
	clock = load("res://scripts/day_night.gd").new()
	clock.world = world
	clock.sun = sun
	clock.time = 120.0
	back.add_child(clock)
	cam = Camera3D.new()
	cam.fov = 62.0
	cam.near = 0.1
	back.add_child(cam)
	cam.current = true
	ground = world.surface_y(int(SPAWN.x), int(SPAWN.y))
	_frame(0.0)


func _build_ui() -> void:
	logo = _make_logo()
	add_child(logo)
	panel = PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	box = VBoxContainer.new()
	box.custom_minimum_size = Vector2(440, 0)
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	add_child(panel)
	var version := Label.new()
	version.text = "3draria · protótipo · Esc volta"
	version.add_theme_font_size_override("font_size", 13)
	version.modulate = Color(1, 1, 1, 0.75)
	version.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	version.grow_vertical = Control.GROW_DIRECTION_BEGIN
	version.offset_left = 14
	version.offset_bottom = -8
	add_child(version)
	fade = ColorRect.new()   # entra do preto quando o mundo termina de montar
	fade.color = Color.BLACK
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(fade)


# Logo em blocos: três camadas do mesmo texto (sombra, terra, grama) dão a espessura, como o logo do Terraria.
func _make_logo() -> Control:
	var holder := Control.new()
	holder.set_anchors_preset(Control.PRESET_CENTER_TOP)
	holder.offset_left = -380
	holder.offset_right = 380
	holder.offset_top = 28
	holder.offset_bottom = 218
	holder.pivot_offset = Vector2(380, 0)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for layer in [[16, Color("#24130a"), Color("#24130a"), 30], [8, Color("#7a4a22"), Color("#24130a"), 20], [0, Color("#86e04e"), Color("#1a380d"), 13]]:
		var l := Label.new()
		l.text = "3DRARIA"
		l.set_anchors_preset(Control.PRESET_FULL_RECT)
		l.position.y = layer[0]
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.add_theme_font_size_override("font_size", 132)
		l.add_theme_color_override("font_color", layer[1])
		l.add_theme_color_override("font_outline_color", layer[2])
		l.add_theme_constant_override("outline_size", layer[3])
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(l)
	var tag := Label.new()
	tag.text = "Terraria em 3D"
	tag.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	tag.grow_horizontal = Control.GROW_DIRECTION_BOTH
	tag.offset_bottom = 10
	tag.add_theme_font_size_override("font_size", 22)
	tag.add_theme_color_override("font_color", Ui.GOLD)
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(tag)
	return holder


# --- câmera e boneco ---------------------------------------------------------------------------------------------

# Posiciona a câmera na vista atual, olhando o ponto ao lado do personagem.
func _frame(delta: float) -> void:
	var a := angle + (sin(elapsed * 0.3) * 0.5 if want.speed == 0.0 else 0.0)
	var base := Vector3(SPAWN.x, ground, SPAWN.y)
	cam.position = base + Vector3(sin(a) * view.r, view.h, cos(a) * view.r)
	var flat := base - cam.position
	flat.y = 0.0
	var right := flat.normalized().cross(Vector3.UP)
	cam.look_at(base + Vector3.UP * view.ty + right * view.side)
	if avatar:   # de frente para a câmera, olhando para ela
		var away := cam.position - avatar.position
		avatar.rotation.y = lerp_angle(avatar.rotation.y, atan2(-away.x, -away.z), 1.0 - exp(-5.0 * delta))
		avatar.pitch = atan2(cam.position.y - (base.y + 1.5), Vector2(away.x, away.z).length())


func _process(delta: float) -> void:
	elapsed += delta
	clock.time += delta * (DAY_SPEED - 1.0)   # o DayNight já soma o delta
	var k := 1.0 - exp(-2.5 * delta)
	for key in want:
		view[key] = lerpf(view[key], want[key], k)
	angle += view.speed * delta
	_frame(delta)
	logo.rotation = sin(elapsed * 0.7) * 0.012   # o logo balança de leve
	if not faded and (world.is_idle() or elapsed > 6.0):
		faded = true
		create_tween().tween_property(fade, "color:a", 0.0, 1.0)


# Mostra o personagem `who` (nome + armadura salva) de pé no gramado, com um pulinho de entrada.
func _show_avatar(who: String, equip: Array) -> void:
	if avatar:
		avatar.queue_free()
	avatar = Avatar.new()
	avatar.atlas = world.atlas_texture
	for k in mini(equip.size(), 3):
		avatar.inv.equip[k] = Items.ids.get(equip[k], -1)
	var model: Node3D = load("res://scripts/player_model.gd").new()
	model.player = avatar
	avatar.add_child(model)
	model.restyle(SaveGame.look_for(who))
	avatar.position = Vector3(SPAWN.x, ground, SPAWN.y)
	avatar.scale = Vector3.ONE * 0.01
	world.get_parent().add_child(avatar)
	var tw := avatar.create_tween()
	tw.tween_property(avatar, "scale", Vector3.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _hide_avatar() -> void:
	if avatar:
		var old := avatar
		avatar = null
		var tw := old.create_tween()
		tw.tween_property(old, "scale", Vector3.ONE * 0.01, 0.2)
		tw.tween_callback(old.queue_free)


func _avatar_of(entry: Dictionary) -> void:
	_show_avatar(entry.name, entry.info.get("equip", []))


# --- telas ------------------------------------------------------------------------------------------------------

# Esvazia o painel (com um título, se houver) e o leva para (ax, ay) da tela, com ou sem moldura.
func _clear(title: String, framed: bool, ax: float, ay: float, size := 26) -> void:
	for c in box.get_children():
		c.queue_free()
	if title != "":
		var l := Label.new()
		l.text = title
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.add_theme_font_size_override("font_size", size)
		box.add_child(l)
	panel.add_theme_stylebox_override("panel", Ui.box(Ui.NAVY, Ui.EDGE, 3, 8) if framed else StyleBoxEmpty.new())
	var tw := create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	for a in ["anchor_left", "anchor_right"]:
		tw.tween_property(panel, a, ax, 0.4)
	for a in ["anchor_top", "anchor_bottom"]:
		tw.tween_property(panel, a, ay, 0.4)


# Os itens da tela entram em sequência, subindo e aparecendo.
func _pop_in() -> void:
	var i := 0
	for c in box.get_children():
		c.modulate.a = 0.0
		var tw := create_tween().set_parallel()
		tw.tween_property(c, "modulate:a", 1.0, 0.25).set_delay(0.05 * i)
		i += 1


func _button(text: String, action: Callable, disabled := false, parent: Control = box) -> Button:
	var b := Button.new()
	b.text = text
	b.disabled = disabled
	b.custom_minimum_size = Vector2(0, 36)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(action)
	parent.add_child(b)
	return b


func _go(to_view: Dictionary, logo_scale: float) -> void:
	want = to_view
	create_tween().tween_property(logo, "scale", Vector2.ONE * logo_scale, 0.4).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func show_title() -> void:
	screen = "title"
	_hide_avatar()
	_clear("", false, 0.5, 0.68)
	_go(TITLE_VIEW, 1.0)
	for b in [["Um jogador", show_players, false], ["Multijogador (em breve)", func(): pass, true], ["Sair", func(): get_tree().quit(), false]]:
		var btn := Ui.menu_button(b[0], 34)
		btn.disabled = b[2]
		btn.pressed.connect(b[1])
		box.add_child(btn)
	_pop_in()


# Lista de saves: nome, uma linha de informação e "apagar" (que pede um segundo clique). `hover` (opcional) recebe a entrada
# quando o mouse passa por cima.
func _save_list(dir: String, pick: Callable, hover := Callable()) -> void:
	var entries := SaveGame.list(dir)
	if entries.is_empty():
		var none := Label.new()
		none.text = "Nada aqui ainda. Crie um abaixo."
		none.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(none)
		return
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	for s in entries:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_theme_constant_override("separation", -2)
		var b := _button(s.name, pick.bind(s.path), false, col)
		b.add_theme_font_size_override("font_size", 21)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var info := Label.new()
		info.text = _info(dir, s.info)
		info.add_theme_font_size_override("font_size", 13)
		info.modulate = Color(1, 1, 1, 0.72)
		col.add_child(info)
		if hover.is_valid():
			b.mouse_entered.connect(hover.bind(s))
		row.add_child(col)
		var del := Button.new()
		del.text = "apagar"
		del.custom_minimum_size = Vector2(86, 40)
		del.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		del.pressed.connect(func():
			if del.text == "apagar":
				del.text = "confirmar?"
			else:
				SaveGame.delete(s.path)
				_refresh(dir))
		row.add_child(del)
		list.add_child(row)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, mini(entries.size(), 4) * LIST_ROW)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.add_child(list)
	box.add_child(scroll)


func _info(dir: String, data: Dictionary) -> String:
	if dir == SaveGame.players_dir:
		var inv := Inventory.new()
		var equip: Array = data.get("equip", [])
		for k in mini(equip.size(), 3):
			inv.equip[k] = Items.ids.get(equip[k], -1)
		return "Vida %d · Defesa %d" % [data.get("hp", 100), inv.defense()] if not data.get("new", false) else "Personagem novo"
	return "Seed %d · %d chunks editados" % [data.seed, data.get("chunks", {}).size()]


func _refresh(dir: String) -> void:
	if dir == SaveGame.players_dir:
		show_players()
	else:
		show_worlds()


# Campo de nome + botão criar; `create` recebe o nome e retorna o caminho ("" se inválido/repetido). `typing` (opcional)
# recebe o texto a cada tecla.
func _create_row(hint: String, create: Callable, after: Callable, typing := Callable()) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var name_edit := LineEdit.new()
	name_edit.placeholder_text = hint
	name_edit.max_length = 20
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_edit.custom_minimum_size = Vector2(0, 40)
	row.add_child(name_edit)
	var status := Label.new()
	status.add_theme_color_override("font_color", Color(Ui.BAD))
	var make := func(_t = ""):
		var path: String = create.call(name_edit.text)
		if path == "":
			status.text = "nome vazio ou já existe"
		else:
			after.call(path)
	name_edit.text_submitted.connect(make)
	if typing.is_valid():
		name_edit.text_changed.connect(typing)
	_button("Criar", make, false, row).custom_minimum_size = Vector2(90, 40)
	box.add_child(row)
	box.add_child(status)


func show_players() -> void:
	screen = "players"
	_clear("Escolha o personagem", true, 0.74, 0.58)
	_go(AVATAR_VIEW, 0.62)
	var entries := SaveGame.list(SaveGame.players_dir)
	if entries.is_empty():
		_hide_avatar()
	elif avatar == null:
		_avatar_of(entries[0])
	_save_list(SaveGame.players_dir, pick_player, _avatar_of)
	_create_row("nome do novo personagem", SaveGame.create_player, func(_p): show_players(),
		func(t: String): _show_avatar(t.strip_edges() if t.strip_edges() != "" else "?", []))
	var back := Ui.menu_button("Voltar", 24)
	back.pressed.connect(show_title)
	box.add_child(back)
	_pop_in()


func pick_player(path: String) -> void:
	chosen_player = path
	var picked := SaveGame.list(SaveGame.players_dir).filter(func(s): return s.path == path)
	if not picked.is_empty():
		_avatar_of(picked[0])
	show_worlds()


func show_worlds() -> void:
	screen = "worlds"
	_clear("Escolha o mundo", true, 0.74, 0.58)
	_go(AVATAR_VIEW, 0.62)
	_save_list(SaveGame.worlds_dir, play)
	_create_row("nome do novo mundo", func(n): return SaveGame.create_world(n, randi()), func(_p): show_worlds())
	var back := Ui.menu_button("Voltar", 24)
	back.pressed.connect(show_players)
	box.add_child(back)
	_pop_in()


func play(world_path: String) -> void:
	SaveGame.player_path = chosen_player
	SaveGame.world_path = world_path
	get_tree().change_scene_to_file("res://game.tscn")


# Esc volta uma tela.
func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("ui_cancel"):
		match screen:
			"worlds":
				show_players()
			"players":
				show_title()
