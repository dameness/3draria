extends CanvasLayer
# Interface no layout e com o comportamento do Terraria (spec em docs/UI.md; visual em ui.gd):
# - hotbar = 1ª fileira do inventário, canto superior esquerdo; Tab abre as outras 4 fileiras logo abaixo, mais a lixeira;
# - criação em coluna à esquerda, embaixo do inventário: só o que dá para criar agora (estações + ingredientes), roda do
#   mouse rola, ingredientes do item sob o mouse em fileira ao lado, clicar cria para a mão (segurar repete);
# - equipamento (defesa e armadura) e botão de menu à direita; vida (corações) no canto superior direito;
# - clique esquerdo pega/solta/junta/troca (item preso ao cursor), direito pega 1 ou veste armadura; dica ao passar o mouse.
# A lógica de itens fica em inventory.gd (com teste); aqui só desenho e entrada.

const SLOT := 48
const PITCH := 52
const X0 := 20
const Y0 := 20
const HP_PER_HEART := 20
const ARMOR_NAMES := ["cabeça", "corpo", "pernas"]   # na ordem de Inventory.ARMOR
const REPEAT_FIRST := 0.4    # segurar para criar de novo: espera e depois intervalo
const REPEAT_EVERY := 0.12

@export var world: Node3D
@export var player: Node3D
@export var clock: Node
var root: Control
var slots: Array[Slot] = []
var trash_slot: Slot
var hearts: Array[TextureRect] = []
var life_label: Label
var defense_label: Label
var item_label: Label
var note_label: Label
var debug_label: Label
var craft_root: Control
var craft_list: VBoxContainer
var craft_info: HBoxContainer
var station_label: Label
var toggle_all: Button
var equip_root: Control
var equip_slots: Array[Slot] = []
var cursor_view: Control
var boss_bar: ProgressBar
var pause: PanelContainer
var tint: ColorRect
var flash: ColorRect
var stations := {}
var show_all := false         # criação: false = só o que dá para criar agora (como o Terraria)
var hovered := {}             # receita sob o mouse (seus ingredientes aparecem ao lado)
var hold_recipe := {}         # receita sendo criada com o botão segurado
var hold_timer := 0.0
var shown_version := -1
var shown_slot := -1
var shown_held := -2
var was_open := false
var item_until := 0
var sel_style := Ui.box(Ui.BLUE_HOVER, Ui.GOLD, 3)


# Botão de slot; tooltip_text guarda a dica em BBCode (nome na cor da raridade e estatísticas).
class Slot extends Button:
	func _make_custom_tooltip(for_text: String) -> Object:
		var tip := RichTextLabel.new()
		tip.bbcode_enabled = true
		tip.fit_content = true
		tip.scroll_active = false
		tip.autowrap_mode = TextServer.AUTOWRAP_OFF
		tip.custom_minimum_size = Vector2(180, 0)
		tip.text = for_text
		return tip


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS   # segue vivo com o jogo pausado (menu de pausa)
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = Ui.theme()
	add_child(root)
	tint = _overlay()
	flash = _overlay()
	_build_grid()
	_build_craft()
	_build_equipment()
	_build_life()
	_build_boss()
	_build_pause()
	var cross := _label("+", 22)
	cross.set_anchors_preset(Control.PRESET_CENTER)
	cross.grow_horizontal = Control.GROW_DIRECTION_BOTH
	cross.grow_vertical = Control.GROW_DIRECTION_BOTH
	root.add_child(cross)
	note_label = _label("", 20)
	note_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	note_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	note_label.offset_top = -150
	root.add_child(note_label)
	debug_label = _label("", 12)
	debug_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	debug_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	debug_label.offset_left = 12
	debug_label.offset_bottom = -8
	debug_label.modulate = Color(1, 1, 1, 0.8)
	root.add_child(debug_label)
	cursor_view = Control.new()   # o item preso ao mouse, sempre por cima
	cursor_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ic := TextureRect.new()
	ic.name = "Icon"
	ic.custom_minimum_size = Vector2(36, 36)
	ic.size = Vector2(36, 36)
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cursor_view.add_child(ic)
	var cn := _label("", 14, HORIZONTAL_ALIGNMENT_RIGHT)
	cn.name = "Count"
	cn.position = Vector2(2, 20)
	cn.size = Vector2(36, 18)
	cursor_view.add_child(cn)
	cursor_view.visible = false
	root.add_child(cursor_view)
	_set_open(false)


# Mostra ou esconde a parte do inventário (fileiras 2 a 5, criação, equipamento e lixeira); a hotbar fica sempre.
func _set_open(open: bool) -> void:
	for i in slots.size():
		slots[i].visible = i < Inventory.HOTBAR or open
		slots[i].mouse_filter = Control.MOUSE_FILTER_STOP if open or i >= Inventory.HOTBAR else Control.MOUSE_FILTER_IGNORE
	for n in [craft_root, equip_root, trash_slot]:
		n.visible = open


func _label(text: String, size: int, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", size)
	return l


func _overlay() -> ColorRect:
	var c := ColorRect.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.color = Color.TRANSPARENT
	root.add_child(c)
	return c


# Botão de slot: ícone do item e quantidade no canto (sem tratar o clique: quem cria liga o gui_input).
func _slot() -> Slot:
	var b := Slot.new()
	b.custom_minimum_size = Vector2(SLOT, SLOT)
	b.expand_icon = true
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_constant_override("icon_max_width", 34)
	b.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var n := _label("", 13, HORIZONTAL_ALIGNMENT_RIGHT)
	n.name = "Count"
	n.position = Vector2(SLOT - 34, SLOT - 21)
	n.size = Vector2(30, 18)
	b.add_child(n)
	return b


func _grid(columns: int) -> GridContainer:
	var g := GridContainer.new()
	g.columns = columns
	g.add_theme_constant_override("h_separation", PITCH - SLOT)
	g.add_theme_constant_override("v_separation", PITCH - SLOT)
	return g


# Uma grade só de 5 x 10: a 1ª fileira é a hotbar, sempre visível; as outras 4 aparecem com o inventário aberto.
func _build_grid() -> void:
	var grid := _grid(Inventory.HOTBAR)
	grid.position = Vector2(X0, Y0)
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(grid)
	for i in Inventory.SIZE:
		var s := _slot()
		s.gui_input.connect(_on_slot_input.bind(i))
		if i < Inventory.HOTBAR:
			var num := _label(str((i + 1) % 10), 12)
			num.position = Vector2(5, 1)
			s.add_child(num)
		slots.append(s)
		grid.add_child(s)
	trash_slot = _slot()   # a lixeira fica embaixo, no canto direito da grade
	trash_slot.position = Vector2(X0 + 9 * PITCH, Y0 + 5 * PITCH + 4)
	trash_slot.tooltip_text = "[color=#ff9a8a]Lixeira[/color]\nO item que cair aqui é destruído\nquando outro chegar."
	trash_slot.gui_input.connect(func(e: InputEvent):
		if _pressed(e, MOUSE_BUTTON_LEFT):
			player.inv.click_trash())
	root.add_child(trash_slot)
	item_label = _label("", 18)
	item_label.position = Vector2(X0 + 4, Y0 + PITCH + 6)
	root.add_child(item_label)


func _pressed(e: InputEvent, button: int) -> bool:
	return e is InputEventMouseButton and e.pressed and e.button_index == button


# Clique num slot do inventário: esquerdo pega/solta/junta/troca (Shift veste armadura), direito pega 1 ou veste.
func _on_slot_input(e: InputEvent, i: int) -> void:
	var inv: Inventory = player.inv
	if _pressed(e, MOUSE_BUTTON_LEFT):
		if not (e.shift_pressed and inv.cursor_id == -1 and inv.equip_from(i)):
			inv.click(i)
	elif _pressed(e, MOUSE_BUTTON_RIGHT):
		if not (inv.cursor_id == -1 and inv.equip_from(i)):
			inv.right_click(i)


# Coluna de criação à esquerda, embaixo do inventário.
func _build_craft() -> void:
	craft_root = Control.new()
	craft_root.position = Vector2(X0, Y0 + 5 * PITCH + 14)
	craft_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(craft_root)
	craft_root.add_child(_label("Criação", 18))
	toggle_all = Button.new()
	toggle_all.text = "Todas"
	toggle_all.toggle_mode = true
	toggle_all.focus_mode = Control.FOCUS_NONE
	toggle_all.tooltip_text = "Mostrar também o que ainda não dá para criar"
	toggle_all.position = Vector2(PITCH + 30, -2)
	toggle_all.toggled.connect(func(on: bool):
		show_all = on
		shown_version = -1)
	craft_root.add_child(toggle_all)
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(0, 30)
	scroll.custom_minimum_size = Vector2(PITCH + 6, 5 * PITCH)
	scroll.size = Vector2(PITCH + 6, 5 * PITCH)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER   # a roda do mouse rola
	craft_list = VBoxContainer.new()
	craft_list.add_theme_constant_override("separation", PITCH - SLOT)
	scroll.add_child(craft_list)
	craft_root.add_child(scroll)
	craft_info = HBoxContainer.new()   # ingredientes do item sob o mouse
	craft_info.position = Vector2(PITCH + 14, 34)
	craft_info.add_theme_constant_override("separation", PITCH - SLOT)
	craft_info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	craft_root.add_child(craft_info)
	station_label = _label("", 14)
	station_label.position = Vector2(PITCH + 14, 34 + PITCH + 2)
	craft_root.add_child(station_label)


# Equipamento à direita: defesa, 3 slots de armadura e o botão de menu (a "engrenagem" do Terraria).
func _build_equipment() -> void:
	equip_root = VBoxContainer.new()
	equip_root.anchor_left = 1.0
	equip_root.anchor_right = 1.0
	equip_root.offset_left = -190
	equip_root.offset_right = -14
	equip_root.offset_top = 140
	equip_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(equip_root)
	defense_label = _label("", 18)
	equip_root.add_child(defense_label)
	for k in Inventory.ARMOR.size():
		var line := HBoxContainer.new()
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var b := _slot()
		b.gui_input.connect(func(e: InputEvent):
			if _pressed(e, MOUSE_BUTTON_LEFT):
				player.inv.click_equip(k)
			elif _pressed(e, MOUSE_BUTTON_RIGHT):
				player.inv.unequip(k))
		equip_slots.append(b)
		line.add_child(b)
		line.add_child(_label(ARMOR_NAMES[k], 14))
		equip_root.add_child(line)
	var menu := Button.new()
	menu.text = "Menu"
	menu.focus_mode = Control.FOCUS_NONE
	menu.pressed.connect(func():
		player.inventory_open = false
		player.set_menu(true))
	equip_root.add_child(menu)


func _build_life() -> void:
	var box := VBoxContainer.new()
	box.anchor_left = 1.0
	box.anchor_right = 1.0
	box.offset_left = -330
	box.offset_right = -14
	box.offset_top = 10
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(box)
	life_label = _label("", 18, HORIZONTAL_ALIGNMENT_RIGHT)
	box.add_child(life_label)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 2)
	box.add_child(row)
	for i in ceili(player.MAX_HP / float(HP_PER_HEART)):
		var h := TextureRect.new()
		h.texture = Ui.heart()
		h.custom_minimum_size = Vector2(30, 30)
		h.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		h.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		h.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		h.pivot_offset = Vector2(15, 15)
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(h)
		hearts.append(h)


func _build_boss() -> void:
	boss_bar = ProgressBar.new()
	boss_bar.anchor_left = 0.5
	boss_bar.anchor_right = 0.5
	boss_bar.anchor_top = 1.0
	boss_bar.anchor_bottom = 1.0
	boss_bar.offset_left = -240
	boss_bar.offset_right = 240
	boss_bar.offset_top = -100
	boss_bar.offset_bottom = -68
	boss_bar.show_percentage = false
	boss_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var name_label := _label("", 16, HORIZONTAL_ALIGNMENT_CENTER)
	name_label.name = "Name"
	name_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	boss_bar.add_child(name_label)
	root.add_child(boss_bar)


func _build_pause() -> void:
	pause = PanelContainer.new()
	pause.set_anchors_preset(Control.PRESET_CENTER)
	pause.grow_horizontal = Control.GROW_DIRECTION_BOTH
	pause.grow_vertical = Control.GROW_DIRECTION_BOTH
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(280, 0)
	box.add_theme_constant_override("separation", 8)
	box.add_child(_label("Pausado", 30, HORIZONTAL_ALIGNMENT_CENTER))
	for b in [["Continuar", func(): player.set_menu(false)], ["Salvar e sair", _save_and_quit]]:
		var btn := Ui.menu_button(b[0])
		btn.pressed.connect(b[1])
		box.add_child(btn)
	pause.add_child(box)
	root.add_child(pause)


# Com o jogo pausado o jogador não recebe teclas: é o HUD que fecha o menu com Esc.
func _unhandled_input(e: InputEvent) -> void:
	if player.menu_open and e.is_action_pressed("ui_cancel"):
		player.set_menu(false)
		get_viewport().set_input_as_handled()


func _save_and_quit() -> void:
	get_tree().paused = false
	SaveGame.save_all(world, player, clock)
	get_tree().change_scene_to_file("res://menu.tscn")


func _icon(id: int) -> Texture2D:
	return player.entities.icon(id)


func _fill(b: Slot, id: int, count: int) -> void:
	b.icon = _icon(id) if id != -1 else null
	b.get_node("Count").text = str(count) if id != -1 and count > 1 else ""
	b.tooltip_text = Ui.item_tip(id) if id != -1 else ""


func _show_slot(i: int) -> void:
	_fill(slots[i], player.inv.item[i], player.inv.count[i])
	slots[i].add_theme_stylebox_override("normal", sel_style if i == player.slot and i < Inventory.HOTBAR else Ui.theme().get_stylebox("normal", "Button"))


# Criação: os ingredientes da receita ficam em fileira ao lado da lista (vermelho = falta).
func _hover(r: Dictionary) -> void:
	hovered = r
	_show_ingredients(r)


func _show_ingredients(r: Dictionary) -> void:
	for c in craft_info.get_children():
		craft_info.remove_child(c)
		c.queue_free()
	if r.is_empty():
		station_label.text = ""
		return
	for id in r.needs:
		var b := _slot()
		_fill(b, id, r.needs[id])
		b.get_node("Count").text = str(r.needs[id])
		b.get_node("Count").add_theme_color_override("font_color", Color.WHITE if player.inv.total(id) >= r.needs[id] else Color(1, 0.45, 0.45))
		b.mouse_filter = Control.MOUSE_FILTER_PASS
		craft_info.add_child(b)
	if r.station != -1:
		station_label.text = "Precisa de: %s" % Blocks.ids.keys()[r.station].replace("_", " ")
		station_label.add_theme_color_override("font_color", Color(Ui.GOOD) if stations.has(r.station) else Color(Ui.BAD))
	else:
		station_label.text = ""


func _craft(r: Dictionary) -> void:
	Crafting.craft_to_cursor(r, player.inv, stations)


func _refresh_recipes() -> void:
	for c in craft_list.get_children():
		craft_list.remove_child(c)
		c.queue_free()
	var now := Crafting.recipes.filter(func(r): return Crafting.can_craft(r, player.inv, stations))
	var list: Array = now + (Crafting.recipes.filter(func(r): return not Crafting.can_craft(r, player.inv, stations)) if show_all else [])
	for r in list:
		var b := _slot()
		_fill(b, r.result, r.count)
		b.modulate = Color.WHITE if Crafting.can_craft(r, player.inv, stations) else Color(1, 1, 1, 0.42)
		b.mouse_entered.connect(_hover.bind(r))
		b.gui_input.connect(func(e: InputEvent):
			if _pressed(e, MOUSE_BUTTON_LEFT):
				_craft(r)
				hold_recipe = r
				hold_timer = REPEAT_FIRST)
		craft_list.add_child(b)
	if not list.has(hovered):
		_hover(list[0] if not list.is_empty() else {})
	else:
		_show_ingredients(hovered)


func _process(delta: float) -> void:
	var open: bool = player.inventory_open
	pause.visible = player.menu_open
	if open != was_open:
		_set_open(open)
		if not open:  # fechou com item na mão: volta ao inventário; o que não couber cai no chão
			var held_id: int = player.inv.cursor_id
			var left: int = player.inv.release_cursor()
			if left > 0:
				player.entities.spawn_drop(held_id, left, player.position + Vector3.UP)
		shown_version = -1
	var hp: float = player.hp
	for i in hearts.size():
		var f := clampf((hp - i * HP_PER_HEART) / HP_PER_HEART, 0.0, 1.0)
		hearts[i].modulate = Color(1, 1, 1, 0.35 + 0.65 * f) if f > 0.0 else Color(0.2, 0.2, 0.2, 0.55)
		hearts[i].scale = Vector2.ONE * (0.68 + 0.32 * f)
	life_label.text = "Vida: %d/%d" % [ceili(hp), player.MAX_HP]
	defense_label.text = "Defesa: %d" % player.inv.defense()
	var id: int = player.held()
	var now := Time.get_ticks_msec()
	if id != shown_held:  # o nome do item aparece um instante, na cor da raridade
		shown_held = id
		item_until = now + 2200
		item_label.text = Items.label(id).capitalize() if id != -1 else ""
		item_label.add_theme_color_override("font_color", Items.rarity_color(id) if id != -1 else Color.WHITE)
	item_label.visible = not open
	item_label.modulate.a = clampf((item_until - now) / 500.0, 0.0, 1.0)
	var boss: Node3D = player.entities.boss
	boss_bar.visible = boss != null
	if boss:
		boss_bar.max_value = boss.def.life
		boss_bar.value = boss.hp
		boss_bar.get_node("Name").text = "%s  %d/%d" % [boss.def.name.replace("_", " ").capitalize(), maxi(boss.hp, 0), boss.def.life]
	var inv: Inventory = player.inv
	var changed: bool = inv.version != shown_version
	if changed or player.slot != shown_slot or Engine.get_process_frames() % 30 == 0:
		shown_slot = player.slot
		for i in (Inventory.SIZE if open else Inventory.HOTBAR):
			_show_slot(i)
	if open:
		var near := Crafting.stations_near(world, player.position) if changed or Engine.get_process_frames() % 30 == 0 else stations
		if changed or near != stations:
			stations = near
			for k in Inventory.ARMOR.size():
				_fill(equip_slots[k], inv.equip[k], 1)
			_fill(trash_slot, inv.trash_id, inv.trash_count)
			_refresh_recipes()
		if not hold_recipe.is_empty():  # segurar o botão na receita cria de novo
			if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and hovered == hold_recipe:
				hold_timer -= delta
				if hold_timer <= 0.0:
					_craft(hold_recipe)
					hold_timer = REPEAT_EVERY
			else:
				hold_recipe = {}
	shown_version = inv.version
	was_open = open
	cursor_view.visible = open and inv.cursor_id != -1
	if cursor_view.visible:
		cursor_view.position = get_viewport().get_mouse_position() + Vector2(6, 6)
		cursor_view.get_node("Icon").texture = _icon(inv.cursor_id)
		cursor_view.get_node("Count").text = str(inv.cursor_count) if inv.cursor_count > 1 else ""
	var cam: Vector3 = player.cam.global_position
	var block: int = world.get_block(floori(cam.x), floori(cam.y), floori(cam.z))
	tint.color = Color(0.08, 0.28, 0.7, 0.4) if block == Blocks.ids.water else Color(1.0, 0.3, 0.05, 0.55) if block == Blocks.ids.lava else Color.TRANSPARENT
	flash.color = Color(0.9, 0.05, 0.05, clampf((player.iframes - (player.IFRAMES - 0.3)) / 0.3, 0.0, 1.0) * 0.3)
	note_label.text = player.message if now < player.message_until else ""
	var p: Vector3 = player.position
	debug_label.text = "FPS %d  |  distância %d chunks (+/-)  |  %s%s  |  %s  |  %s  |  pos %d %d %d" % [
		Engine.get_frames_per_second(), world.render_distance, clock.clock(), " (noite)" if clock.is_night() else "",
		("voo (F)" if player.flying else "andando (F voa)"), "3ª pessoa (V)" if player.third_person else "1ª pessoa (V)", p.x, p.y, p.z]
