extends CanvasLayer
# Mira, hotbar, avisos, texto de depuração e a janela de inventário/criação (tecla E).

@export var world: Node3D
@export var player: Node3D
@export var clock: Node
@onready var info: Label = $Info
@onready var bar: HBoxContainer = $Hotbar
var panel: PanelContainer
var grid: GridContainer
var recipe_list: VBoxContainer
var shown_version := -1
var boss_bar: ProgressBar
var pause: PanelContainer
var stations := {}


func _ready() -> void:
	panel = PanelContainer.new()
	grid = GridContainer.new()
	recipe_list = VBoxContainer.new()
	for i in Inventory.HOTBAR:
		bar.add_child(_slot(-1))
	grid.columns = Inventory.HOTBAR
	for i in Inventory.SIZE:
		grid.add_child(_slot(i))
	var box := VBoxContainer.new()
	var title := Label.new()
	title.text = "Inventário — clique num slot para trocar com o da mão. Criação (estações a %d blocos):" % Crafting.STATION_RANGE
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 240)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.add_child(recipe_list)
	recipe_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(grid)
	box.add_child(title)
	box.add_child(scroll)
	panel.add_child(box)
	for a in ["anchor_left", "anchor_top", "anchor_right", "anchor_bottom"]:
		panel.set(a, 0.5)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(panel)
	boss_bar = ProgressBar.new()
	boss_bar.custom_minimum_size = Vector2(420, 26)
	boss_bar.anchor_left = 0.5
	boss_bar.anchor_right = 0.5
	boss_bar.offset_top = 12
	boss_bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	boss_bar.show_percentage = false
	boss_bar.add_theme_stylebox_override("fill", _flat(Color("#c02a2a")))
	boss_bar.add_theme_stylebox_override("background", _flat(Color(0, 0, 0, 0.6)))
	var name_label := Label.new()
	name_label.name = "Name"
	name_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	boss_bar.add_child(name_label)
	add_child(boss_bar)
	pause = PanelContainer.new()
	var pbox := VBoxContainer.new()
	pbox.add_theme_constant_override("separation", 12)
	for b in [["Continuar", func(): player.set_menu(false)], ["Salvar e sair", _save_and_quit]]:
		var btn := Button.new()
		btn.text = b[0]
		btn.custom_minimum_size = Vector2(260, 44)
		btn.pressed.connect(b[1])
		pbox.add_child(btn)
	pause.add_child(pbox)
	for a in ["anchor_left", "anchor_top", "anchor_right", "anchor_bottom"]:
		pause.set(a, 0.5)
	pause.grow_horizontal = Control.GROW_DIRECTION_BOTH
	pause.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(pause)


func _save_and_quit() -> void:
	SaveGame.save_all(world, player, clock)
	get_tree().change_scene_to_file("res://menu.tscn")


static func _flat(c: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = c
	return sb


# Botão de slot: ícone do item e quantidade. i = -1 para a hotbar (só exibição).
func _slot(i: int) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(52, 52)
	b.expand_icon = true
	b.focus_mode = Control.FOCUS_NONE
	b.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	b.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
	b.add_theme_constant_override("icon_max_width", 36)
	b.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if i == -1:
		b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	else:
		b.pressed.connect(_on_slot.bind(i))
	return b


func _show_slot(b: Button, i: int) -> void:
	var id: int = player.inv.item[i]
	b.icon = _icon(id) if id != -1 else null
	b.text = str(player.inv.count[i]) if id != -1 and player.inv.count[i] > 1 else ""
	b.tooltip_text = Items.label(id) if id != -1 else ""
	b.modulate = Color.WHITE if i == player.slot or i >= Inventory.HOTBAR else Color(1, 1, 1, 0.55)


func _icon(id: int) -> Texture2D:
	return player.entities.icon(id)


func _on_slot(i: int) -> void:
	if i < Inventory.HOTBAR:
		player.slot = i
	else:
		player.inv.swap(i, player.slot)
	shown_version = -1


func _on_craft(r: Dictionary) -> void:
	Crafting.craft(r, player.inv, stations)


func _refresh_recipes() -> void:
	for c in recipe_list.get_children():
		c.queue_free()
	# Como no Terraria, o que dá para criar agora vem primeiro.
	var ordered := Crafting.recipes.filter(func(r): return Crafting.can_craft(r, player.inv, stations))
	ordered += Crafting.recipes.filter(func(r): return not Crafting.can_craft(r, player.inv, stations))
	for r in ordered:
		var b := Button.new()
		var needs := ", ".join(r.needs.keys().map(func(id): return "%d %s" % [r.needs[id], Items.label(id)]))
		var at := "" if r.station == -1 else "  [%s]" % Blocks.ids.keys()[r.station]
		b.text = "%s ← %s%s" % [Items.label(r.result), needs, at]
		b.icon = _icon(r.result)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.focus_mode = Control.FOCUS_NONE
		b.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		b.add_theme_constant_override("icon_max_width", 24)
		b.disabled = not Crafting.can_craft(r, player.inv, stations)
		b.pressed.connect(_on_craft.bind(r))
		recipe_list.add_child(b)


func _process(_delta: float) -> void:
	panel.visible = player.inventory_open
	pause.visible = player.menu_open
	var boss: Node3D = player.entities.boss
	boss_bar.visible = boss != null
	if boss:
		boss_bar.max_value = boss.def.life
		boss_bar.value = boss.hp
		boss_bar.get_node("Name").text = "%s  %d/%d" % [boss.def.name.replace("_", " "), maxi(boss.hp, 0), boss.def.life]
	var changed: bool = player.inv.version != shown_version
	if changed or Engine.get_process_frames() % 30 == 0:
		for i in Inventory.HOTBAR:
			_show_slot(bar.get_child(i), i)
	if panel.visible:
		var near := Crafting.stations_near(world, player.position) if Engine.get_process_frames() % 30 == 0 or changed else stations
		if changed or near != stations:
			stations = near
			for i in Inventory.SIZE:
				_show_slot(grid.get_child(i), i)
			_refresh_recipes()
	shown_version = player.inv.version
	var p: Vector3 = player.position
	var id: int = player.held()
	var msg: String = player.message if Time.get_ticks_msec() < player.message_until else ""
	info.text = "Vida %d/%d | %s %s\nFPS %d | distância %d chunks (+/-) | %s | na mão: %s\npos %d %d %d\n%s" % [
		ceili(player.hp), player.MAX_HP, clock.clock(), "(noite)" if clock.is_night() else "",
		Engine.get_frames_per_second(), world.render_distance, "voo (F)" if player.flying else "andando (F voa)",
		Items.label(id) if id != -1 else "nada", p.x, p.y, p.z, msg]
