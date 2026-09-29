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
var new_look := {}                     # cores do personagem que está sendo criado (pele, cabelo, camisa, calça)
var new_name := ""
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
	Settings.path = "user://settings.cfg"   # as opções do Configurações valem em todos os mundos
	Settings.load_file()
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
	var img := Atlas.wiki_image(Blocks.textures.get("logo", {}))   # o logo do Terraria (wiki, fora do git); sem ele, o logo em texto
	if img:
		var pic := TextureRect.new()
		pic.texture = ImageTexture.create_from_image(img)
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		pic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		pic.set_anchors_preset(Control.PRESET_FULL_RECT)
		pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var frame := Control.new()
		frame.set_anchors_preset(Control.PRESET_CENTER_TOP)
		frame.offset_left = -380
		frame.offset_right = 380
		frame.offset_top = 28
		frame.offset_bottom = 218
		frame.pivot_offset = Vector2(380, 0)
		frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		frame.add_child(pic)
		return frame
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
func _show_avatar(who: String, equip: Array, look := {}) -> void:
	if avatar:
		avatar.queue_free()
	avatar = Avatar.new()
	avatar.atlas = world.atlas_texture
	for k in mini(equip.size(), 3):
		avatar.inv.equip[k] = Items.ids.get(equip[k], -1)
	var model: Node3D = load("res://scripts/player_model.gd").new()
	model.player = avatar
	avatar.add_child(model)
	model.restyle(look if not look.is_empty() else SaveGame.look_for(who))
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
	_show_avatar(entry.name, entry.info.get("equip", []), SaveGame.look_of(entry.info, entry.name))


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
	box.custom_minimum_size.x = 560 if framed else 440
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
	for b in [["Um Jogador", show_players, false], ["Multijogador (em breve)", func(): pass, true], ["Sair", func(): get_tree().quit(), false]]:
		var btn := Ui.menu_button(b[0], 34)
		btn.disabled = b[2]
		btn.pressed.connect(b[1])
		box.add_child(btn)
	_pop_in()


# Placa azul com o título da tela (como "Selecionar Personagem" do Terraria).
func _plate(text: String) -> void:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", Ui.box(Color("#3f52a0"), Ui.EDGE, 3, 8))
	p.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 26)
	p.add_child(l)
	box.add_child(p)


# Lista de saves em cartões como a do Terraria: retrato, nome, plaquinhas de informação e a linha Jogar / apagar (com segundo clique).
# `hover` (opcional) recebe a entrada quando o mouse passa por cima do cartão.
func _save_list(dir: String, pick: Callable, hover := Callable()) -> void:
	var entries := SaveGame.list(dir)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	for s in entries:
		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel", Ui.box(Color("#4a5cad"), Ui.EDGE, 2, 6))
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 4)
		var top := HBoxContainer.new()
		top.add_theme_constant_override("separation", 8)
		top.add_child(_portrait(dir, s))
		var right := VBoxContainer.new()
		right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		right.add_theme_constant_override("separation", 3)
		var name_l := Label.new()
		name_l.text = s.name
		name_l.add_theme_font_size_override("font_size", 19)
		right.add_child(name_l)
		var chips := HBoxContainer.new()
		chips.add_theme_constant_override("separation", 4)
		_chips(dir, s, chips)
		right.add_child(chips)
		top.add_child(right)
		col.add_child(top)
		var bottom := HBoxContainer.new()
		bottom.add_theme_constant_override("separation", 6)
		var play_btn := Button.new()
		play_btn.text = "▶ Jogar"
		play_btn.pressed.connect(pick.bind(s.path))
		bottom.add_child(play_btn)
		var gap := Control.new()
		gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bottom.add_child(gap)
		var del := Button.new()
		del.text = "apagar"
		del.pressed.connect(func():
			if del.text == "apagar":
				del.text = "confirmar?"
			else:
				SaveGame.delete(s.path)
				_refresh(dir))
		bottom.add_child(del)
		col.add_child(bottom)
		card.add_child(col)
		if hover.is_valid():
			card.mouse_entered.connect(hover.bind(s))
		list.add_child(card)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 300)   # a moldura tem sempre o mesmo tamanho, com ou sem saves
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.add_child(list)
	box.add_child(scroll)


# Plaquinha escura de informação: glifo colorido opcional + texto.
func _chip(parent: Control, text: String, glyph := "", glyph_color := Color.WHITE) -> void:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", Ui.box(Color("#22306b"), Ui.EDGE, 2, 4))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 4)
	if glyph != "":
		var g := Label.new()
		g.text = glyph
		g.add_theme_font_size_override("font_size", 14)
		g.add_theme_color_override("font_color", glyph_color)
		h.add_child(g)
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 14)
	h.add_child(l)
	p.add_child(h)
	parent.add_child(p)


func _chips(dir: String, s: Dictionary, chips: Control) -> void:
	var d: Dictionary = s.info
	if dir == SaveGame.players_dir:
		var inv := Inventory.new()
		var equip: Array = d.get("equip", [])
		for k in mini(equip.size(), 3):
			inv.equip[k] = Items.ids.get(equip[k], -1)
		_chip(chips, "%d PV" % d.get("max_hp", 100), "♥", Color("#ff5a5a"))
		_chip(chips, "%d PM" % d.get("max_mana", 20), "★", Color("#6aa8ff"))
		_chip(chips, "Defesa %d" % inv.defense())
	else:
		_chip(chips, "Teste" if d.get("test", false) else "Clássico")
		_chip(chips, "Mundo Pequeno")
		var t := Time.get_datetime_dict_from_unix_time(FileAccess.get_modified_time(s.path))
		_chip(chips, "Salvo: %02d/%02d/%d" % [t.day, t.month, t.year])


# Retrato do cartão: o boneco em pixels com as cores do personagem, ou uma árvore para o mundo.
func _portrait(dir: String, s: Dictionary) -> Control:
	var img := Image.create(16, 22, false, Image.FORMAT_RGBA8)
	if dir == SaveGame.players_dir:
		var look := SaveGame.look_of(s.info, s.name)
		img.fill_rect(Rect2i(4, 0, 8, 3), look.hair)
		img.fill_rect(Rect2i(4, 3, 8, 6), look.skin)
		img.set_pixel(6, 5, Color.BLACK)
		img.set_pixel(9, 5, Color.BLACK)
		img.fill_rect(Rect2i(3, 9, 10, 7), look.shirt)
		img.fill_rect(Rect2i(1, 9, 2, 6), look.skin)
		img.fill_rect(Rect2i(13, 9, 2, 6), look.skin)
		img.fill_rect(Rect2i(4, 16, 8, 4), look.pants)
		img.fill_rect(Rect2i(4, 20, 3, 2), Color("#5a3a1a"))
		img.fill_rect(Rect2i(9, 20, 3, 2), Color("#5a3a1a"))
	else:
		img.fill_rect(Rect2i(7, 10, 2, 10), Color("#7a4a22"))
		img.fill_rect(Rect2i(3, 2, 10, 8), Color("#3f9a3a"))
		img.fill_rect(Rect2i(5, 1, 6, 2), Color("#3f9a3a"))
		img.fill_rect(Rect2i(4, 3, 3, 2), Color("#63c65a"))
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", Ui.box(Color("#1a2450"), Ui.EDGE, 2, 6))
	var tr := TextureRect.new()
	tr.texture = ImageTexture.create_from_image(img)
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.custom_minimum_size = Vector2(52, 60)
	p.add_child(tr)
	return p


# Fileira de botões largos no fim da tela: [texto, ação].
func _bottom_row(buttons: Array) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	for b in buttons:
		var btn := _button(b[0], b[1], false, row)
		btn.custom_minimum_size = Vector2(0, 46)
		btn.add_theme_font_size_override("font_size", 24)
	box.add_child(row)


func _refresh(dir: String) -> void:
	if dir == SaveGame.players_dir:
		show_players()
	else:
		show_worlds()


# Campo de nome + botão criar; `create` recebe o nome e retorna o caminho ("" se inválido/repetido). `typing` (opcional)
# recebe o texto a cada tecla.
func _create_row(hint: String, create: Callable, after: Callable, typing := Callable(), initial := "") -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var name_edit := LineEdit.new()
	name_edit.placeholder_text = hint
	name_edit.max_length = 20
	name_edit.text = initial
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


# Fileira de amostras de cor do novo personagem: clicar troca essa parte e mostra o boneco na hora.
func _swatches(label: String, key: String, colors: Array) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(70, 0)
	row.add_child(l)
	var buttons: Array[Button] = []
	var paint := func():   # a moldura dourada fica na amostra escolhida (sem refazer a tela inteira)
		for k in buttons.size():
			var sb := Ui.box(Color(colors[k]), Ui.GOLD if Color(colors[k]).is_equal_approx(new_look[key]) else Ui.EDGE, 3, 4)
			for st in ["normal", "hover", "pressed"]:
				buttons[k].add_theme_stylebox_override(st, sb)
	for c in colors:
		var b := Button.new()
		b.custom_minimum_size = Vector2(28, 28)
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(func():
			new_look[key] = Color(c)
			paint.call()
			_show_avatar("?", [], new_look))
		buttons.append(b)
		row.add_child(b)
	paint.call()
	box.add_child(row)


func show_players() -> void:
	screen = "players"
	_clear("", true, 0.74, 0.55)
	_plate("Selecionar Personagem")
	_go(AVATAR_VIEW, 0.62)
	var entries := SaveGame.list(SaveGame.players_dir)
	if new_look.is_empty():
		new_look = SaveGame.look_for(str(randi()))
	if entries.is_empty():
		_show_avatar("?", [], new_look)   # sem saves: o boneco é o que será criado
	elif avatar == null:
		_avatar_of(entries[0])
	_save_list(SaveGame.players_dir, pick_player, _avatar_of)
	_bottom_row([["Voltar", show_title], ["Novo", show_new_player]])
	_pop_in()


func show_new_player() -> void:
	screen = "new_player"
	_clear("", true, 0.74, 0.55)
	_plate("Criar Personagem")
	_go(AVATAR_VIEW, 0.62)
	if new_look.is_empty():
		new_look = SaveGame.look_for(str(randi()))
	_show_avatar("?", [], new_look)
	_create_row("nome do novo personagem", func(n): return SaveGame.create_player(n, new_look), func(_p):
		new_look = {}
		new_name = ""
		show_players(),
		func(t: String):
			new_name = t
			_show_avatar("?", [], new_look), new_name)
	for part in [["pele", "skin", SaveGame.SKINS], ["cabelo", "hair", SaveGame.HAIRS], ["camisa", "shirt", SaveGame.SHIRTS], ["calça", "pants", SaveGame.PANTS]]:
		_swatches(part[0], part[1], part[2])
	_bottom_row([["Voltar", show_players]])
	_pop_in()


func pick_player(path: String) -> void:
	chosen_player = path
	var picked := SaveGame.list(SaveGame.players_dir).filter(func(s): return s.path == path)
	if not picked.is_empty():
		_avatar_of(picked[0])
	show_worlds()


func show_worlds() -> void:
	screen = "worlds"
	_clear("", true, 0.74, 0.55)
	_plate("Selecionar Mundo")
	_go(AVATAR_VIEW, 0.62)
	_save_list(SaveGame.worlds_dir, play)
	var test_hint := "Arena plana com baús de todos os itens, todos os blocos, NPCs, inimigos e atalhos de chefes/hora (F9)."   # abre (ou cria) o mundo com todos os itens à mão
	_bottom_row([["Voltar", show_players], ["Novo", show_new_world], ["Mundo de teste", func(): play(SaveGame.test_world())]])
	box.get_child(box.get_child_count() - 1).get_child(2).tooltip_text = test_hint
	_pop_in()


func show_new_world() -> void:
	screen = "new_world"
	_clear("", true, 0.74, 0.55)
	_plate("Criar Mundo")
	_go(AVATAR_VIEW, 0.62)
	_create_row("nome do novo mundo", func(n): return SaveGame.create_world(n, randi()), func(_p): show_worlds())
	_bottom_row([["Voltar", show_worlds]])
	_pop_in()


func play(world_path: String) -> void:
	SaveGame.player_path = chosen_player
	SaveGame.world_path = world_path
	get_tree().change_scene_to_file("res://game.tscn")


# Esc volta uma tela.
func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("ui_cancel"):
		match screen:
			"new_world":
				show_worlds()
			"new_player":
				show_players()
			"worlds":
				show_players()
			"players":
				show_title()
