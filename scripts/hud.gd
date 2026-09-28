extends CanvasLayer
# Interface no estilo do Terraria (visual em ui.gd): hotbar no canto, corações de vida, nome do item na cor da
# raridade, janela de inventário/criação (E) com dicas ao passar o mouse, barra do chefe, avisos, tela de água/lava
# e de dano, e o menu de pausa (Esc).

const SLOT := 50
const HP_PER_HEART := 20
const ARMOR_NAMES := ["cabeça", "corpo", "pernas"]   # na ordem de Inventory.ARMOR

@export var world: Node3D
@export var player: Node3D
@export var clock: Node
var root: Control
var hotbar: HBoxContainer
var hearts: Array[TextureRect] = []
var life_label: Label
var defense_label: Label
var item_label: Label
var note_label: Label
var debug_label: Label
var panel: PanelContainer
var grid: GridContainer
var craft_grid: GridContainer
var equip_slots: Array[Slot] = []
var boss_bar: ProgressBar
var pause: PanelContainer
var tint: ColorRect
var flash: ColorRect
var stations := {}
var shown_version := -1
var was_open := false
var shown_slot := -1
var shown_held := -2
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
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = Ui.theme()
	add_child(root)
	tint = _overlay()
	flash = _overlay()
	_build_hotbar()
	_build_life()
	_build_inventory()
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


# Botão de slot: ícone do item e quantidade no canto. i = -1 para exibição (hotbar) ou botões próprios.
func _slot(i: int) -> Slot:
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
	if i == -1:
		b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	else:
		b.pressed.connect(_on_slot.bind(i))
	return b


func _build_hotbar() -> void:
	hotbar = HBoxContainer.new()
	hotbar.position = Vector2(14, 12)
	hotbar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hotbar.add_theme_constant_override("separation", 4)
	root.add_child(hotbar)
	for i in Inventory.HOTBAR:
		var s := _slot(-1)
		var num := _label(str((i + 1) % 10), 12)
		num.position = Vector2(5, 1)
		s.add_child(num)
		hotbar.add_child(s)
	item_label = _label("", 18)
	item_label.position = Vector2(16, 12 + SLOT + 8)
	root.add_child(item_label)


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
	defense_label = _label("", 16, HORIZONTAL_ALIGNMENT_RIGHT)
	box.add_child(defense_label)


func _build_inventory() -> void:
	panel = PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	root.add_child(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 22)
	panel.add_child(row)
	var craft := VBoxContainer.new()
	craft.add_child(_label("Criação", 18))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(5 * (SLOT + 4) + 14, 300)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	craft_grid = _grid(5)
	scroll.add_child(craft_grid)
	craft.add_child(scroll)
	craft.add_child(_label("Estações a %d blocos." % Crafting.STATION_RANGE, 13))
	row.add_child(craft)
	var inv := VBoxContainer.new()
	inv.add_child(_label("Inventário", 18))
	grid = _grid(Inventory.HOTBAR)
	for i in Inventory.SIZE:
		grid.add_child(_slot(i))
	inv.add_child(grid)
	inv.add_child(_label("Clique: veste armadura; senão troca com o slot da mão. E fecha.", 13))
	row.add_child(inv)
	var eq := VBoxContainer.new()
	eq.add_child(_label("Armadura", 18))
	for k in Inventory.ARMOR.size():
		var line := HBoxContainer.new()
		var b := _slot(-1)
		b.mouse_filter = Control.MOUSE_FILTER_STOP
		b.pressed.connect(func(): player.inv.unequip(k))
		equip_slots.append(b)
		line.add_child(b)
		line.add_child(_label(ARMOR_NAMES[k], 14))
		eq.add_child(line)
	eq.add_child(_label("Clique para tirar.", 13))
	row.add_child(eq)


func _grid(columns: int) -> GridContainer:
	var g := GridContainer.new()
	g.columns = columns
	g.add_theme_constant_override("h_separation", 4)
	g.add_theme_constant_override("v_separation", 4)
	return g


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


func _save_and_quit() -> void:
	SaveGame.save_all(world, player, clock)
	get_tree().change_scene_to_file("res://menu.tscn")


func _show_slot(b: Slot, i: int) -> void:
	var id: int = player.inv.item[i]
	_fill(b, id, player.inv.count[i])
	b.add_theme_stylebox_override("normal", sel_style if i == player.slot and i < Inventory.HOTBAR else Ui.theme().get_stylebox("normal", "Button"))


func _fill(b: Slot, id: int, count: int) -> void:
	b.icon = _icon(id) if id != -1 else null
	b.get_node("Count").text = str(count) if id != -1 and count > 1 else ""
	b.tooltip_text = Ui.item_tip(id) if id != -1 else ""


func _icon(id: int) -> Texture2D:
	return player.entities.icon(id)


func _on_slot(i: int) -> void:
	if player.inv.equip_from(i):  # armadura: veste
		return
	if i < Inventory.HOTBAR:
		player.slot = i
	else:
		player.inv.swap(i, player.slot)
	shown_version = -1


func _on_craft(r: Dictionary) -> void:
	Crafting.craft(r, player.inv, stations)


# Dica da receita: o item com as estatísticas, e o que falta (verde = tem, vermelho = falta).
func _recipe_tip(r: Dictionary) -> String:
	var lines := [Ui.item_tip(r.result), "[color=#ffe27a]Precisa de:[/color]"]
	for id in r.needs:
		var have: int = player.inv.total(id)
		lines.append("[color=%s]%s  %d/%d[/color]" % [Ui.GOOD if have >= r.needs[id] else Ui.BAD, Items.label(id), have, r.needs[id]])
	if r.station != -1:
		lines.append("[color=%s]estação: %s[/color]" % [Ui.GOOD if stations.has(r.station) else Ui.BAD, Blocks.ids.keys()[r.station].replace("_", " ")])
	return "\n".join(lines)


func _refresh_recipes() -> void:
	for c in craft_grid.get_children():
		craft_grid.remove_child(c)
		c.queue_free()
	# Como no Terraria, o que dá para criar agora vem primeiro.
	var ordered := Crafting.recipes.filter(func(r): return Crafting.can_craft(r, player.inv, stations))
	ordered += Crafting.recipes.filter(func(r): return not Crafting.can_craft(r, player.inv, stations))
	for r in ordered:
		var b := _slot(-1)
		b.mouse_filter = Control.MOUSE_FILTER_STOP
		_fill(b, r.result, r.count)
		b.tooltip_text = _recipe_tip(r)
		b.modulate = Color.WHITE if Crafting.can_craft(r, player.inv, stations) else Color(1, 1, 1, 0.42)
		b.pressed.connect(_on_craft.bind(r))
		craft_grid.add_child(b)


func _process(_delta: float) -> void:
	panel.visible = player.inventory_open
	pause.visible = player.menu_open
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
	item_label.modulate.a = clampf((item_until - now) / 500.0, 0.0, 1.0)
	var boss: Node3D = player.entities.boss
	boss_bar.visible = boss != null
	if boss:
		boss_bar.max_value = boss.def.life
		boss_bar.value = boss.hp
		boss_bar.get_node("Name").text = "%s  %d/%d" % [boss.def.name.replace("_", " ").capitalize(), maxi(boss.hp, 0), boss.def.life]
	var changed: bool = player.inv.version != shown_version
	if changed or player.slot != shown_slot or Engine.get_process_frames() % 30 == 0:
		shown_slot = player.slot
		for i in Inventory.HOTBAR:
			_show_slot(hotbar.get_child(i), i)
	if panel.visible:
		var fresh := not was_open   # acabou de abrir: preenche tudo
		var near := Crafting.stations_near(world, player.position) if fresh or changed or Engine.get_process_frames() % 30 == 0 else stations
		if fresh or changed or near != stations:
			stations = near
			for i in Inventory.SIZE:
				_show_slot(grid.get_child(i), i)
			for k in Inventory.ARMOR.size():
				_fill(equip_slots[k], player.inv.equip[k], 1)
			_refresh_recipes()
	shown_version = player.inv.version
	was_open = panel.visible
	var cam: Vector3 = player.cam.global_position
	var block: int = world.get_block(floori(cam.x), floori(cam.y), floori(cam.z))
	tint.color = Color(0.08, 0.28, 0.7, 0.4) if block == Blocks.ids.water else Color(1.0, 0.3, 0.05, 0.55) if block == Blocks.ids.lava else Color.TRANSPARENT
	flash.color = Color(0.9, 0.05, 0.05, clampf((player.iframes - (player.IFRAMES - 0.3)) / 0.3, 0.0, 1.0) * 0.3)
	note_label.text = player.message if now < player.message_until else ""
	var p: Vector3 = player.position
	debug_label.text = "FPS %d  |  distância %d chunks (+/-)  |  %s%s  |  %s  |  %s  |  pos %d %d %d" % [
		Engine.get_frames_per_second(), world.render_distance, clock.clock(), " (noite)" if clock.is_night() else "",
		("voo (F)" if player.flying else "andando (F voa)"), "3ª pessoa (V)" if player.third_person else "1ª pessoa (V)", p.x, p.y, p.z]
