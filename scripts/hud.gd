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
	box.add_child(grid)
	box.add_child(title)
	box.add_child(recipe_list)
	panel.add_child(box)
	for a in ["anchor_left", "anchor_top", "anchor_right", "anchor_bottom"]:
		panel.set(a, 0.5)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(panel)


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
	for r in Crafting.recipes:
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
