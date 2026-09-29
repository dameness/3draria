extends CanvasLayer
# Interface no layout e com o comportamento do Terraria (spec em docs/UI.md; visual em ui.gd):
# - hotbar = 1ª fileira do inventário, canto superior esquerdo; Esc abre as outras 4 fileiras logo abaixo, mais a lixeira;
# - criação em coluna à esquerda, embaixo do inventário: só o que dá para criar agora (estações + ingredientes), roda do
#   mouse rola, ingredientes do item sob o mouse em fileira ao lado, clicar cria para a mão (segurar repete);
# - equipamento (defesa e armadura) e o botão Configurações (pausa, distância, volume, sensibilidade) à direita; vida (corações) no canto superior direito;
# - clique esquerdo pega/solta/junta/troca (item preso ao cursor), direito pega 1 ou veste armadura; dica ao passar o mouse.
# - à direita da grade: 4 slots de moedas (giram) e 4 de munição; acessórios embaixo da armadura; minimapa sob a vida; lixeira e Ordenar;
#   Alt+clique favorita; Ctrl+clique joga no lixo; Shift+clique manda para o baú (ou veste); baú aberto ocupa o lugar da criação; F10 esconde o FPS, F11 o HUD.
# - animação: slots crescem sob o mouse e "pulam" ao receber item (que voa da tela até o slot), painéis deslizam ao abrir/fechar,
#   corações batem com pouca vida, dicas surgem com fade, item preso ao cursor balança.
# A lógica de itens fica em inventory.gd (com teste); aqui só desenho e entrada.

const SLOT := 48
const PITCH := 52
const X0 := 20
const Y0 := 20
const HP_PER_HEART := 20
const ARMOR_NAMES := ["cabeça", "corpo", "pernas"]   # na ordem de Inventory.ARMOR
const CHEST_SLOTS := 40
const OPEN_SPEED := 7.0
const REPEAT_FIRST := 0.4    # segurar para criar de novo: espera e depois intervalo
const REPEAT_EVERY := 0.12

@export var world: Node3D
@export var player: Node3D
@export var clock: Node
var root: Control
var slots: Array[Slot] = []
var trash_slot: Slot
var hearts: Array[TextureRect] = []
var heart_rows: Array[HBoxContainer] = []
var hearts_shown := 0                 # corações visíveis (a vida máxima sobe com Life Crystals: 20 por coração, 10 por fileira)
var npc_panel: PanelContainer
var npc_kind := ""                    # quem está falando (guide, merchant, nurse); vazio = ninguém
var npc_text: Label
var npc_buttons: HFlowContainer
var tip_index := 0
var buff_row: HBoxContainer
var buff_key := ""                    # quais buffs a fileira mostra (refaz quando muda)
var life_label: Label
var defense_label: Label
var item_label: Label
var note_label: Label
var debug_label: Label
var cross: Label
var creative_label: Label
var flight_bar: ProgressBar
var craft_root: Control
var craft_list: VBoxContainer
var craft_info: HBoxContainer
var station_label: Label
var toggle_all: Button
var equip_root: Control
var equip_slots: Array[Slot] = []
var acc_slots: Array[Slot] = []
var ammo_slots: Array[Slot] = []
var coin_views: Array[Control] = []   # 4 slots de moeda: painel + ícone que gira + quantidade
var side_nodes: Array[Control] = []   # coisas que só aparecem com o inventário aberto e animam junto (moedas, munição, Ordenar)
var sort_button: Button
var minimap: Minimap
var life_box: VBoxContainer
var stars: Array[Label] = []          # mana: uma estrela por 20 (coluna à direita dos corações)
var star_col: VBoxContainer
var open_t := 0.0                     # 0 fechado, 1 aberto: anima o deslizar dos painéis
var prev_item := PackedInt32Array()   # para achar o slot que ganhou item (pulo e item voando)
var prev_count := PackedInt32Array()
var last_click := -10                 # quadro do último clique nosso: mudança de item nesse quadro não é "pegou do chão"
var chest_root: Control
var chest_slots: Array[Slot] = []
var chest: Dictionary = {}            # baú aberto: {item, count, pos}; vazio = nenhum
var spin := 0.0
var cursor_view: Control
var boss_bar: ProgressBar
var pause: PanelContainer
var syncs: Array[Callable] = []       # Configurações: cada linha recarrega o valor atual ao abrir
var was_menu := false
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


# Botão de slot; tooltip_text guarda a dica em BBCode (nome na cor da raridade e estatísticas). Cresce sob o mouse e pula ao receber item.
class Slot extends Button:
	var grow := 1.0
	var pop_tween: Tween

	func _init() -> void:
		resized.connect(func(): pivot_offset = size / 2.0)
		mouse_entered.connect(func(): _grow(1.1))
		mouse_exited.connect(func(): _grow(1.0))

	func _grow(to: float) -> void:
		grow = to
		if pop_tween == null or not pop_tween.is_running():
			create_tween().tween_property(self, "scale", Vector2.ONE * to, 0.08)

	func pop() -> void:
		if pop_tween:
			pop_tween.kill()
		scale = Vector2.ONE * 1.42
		pop_tween = create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		pop_tween.tween_property(self, "scale", Vector2.ONE * grow, 0.32)

	func _make_custom_tooltip(for_text: String) -> Object:
		var tip := RichTextLabel.new()
		tip.bbcode_enabled = true
		tip.fit_content = true
		tip.scroll_active = false
		tip.autowrap_mode = TextServer.AUTOWRAP_OFF
		tip.custom_minimum_size = Vector2(180, 0)
		tip.text = for_text
		tip.modulate.a = 0.0
		tip.tree_entered.connect(func(): tip.create_tween().tween_property(tip, "modulate:a", 1.0, 0.15))   # a dica surge com fade
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
	_build_side()
	_build_chest()
	_build_boss()
	_build_pause()
	_build_npc()
	cross = _label("+", 22)
	cross.set_anchors_preset(Control.PRESET_CENTER)
	cross.grow_horizontal = Control.GROW_DIRECTION_BOTH
	cross.grow_vertical = Control.GROW_DIRECTION_BOTH
	root.add_child(cross)
	note_label = _label("", 20)
	note_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	note_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	note_label.offset_top = -150
	root.add_child(note_label)
	creative_label = _label("MODO CRIATIVO  ·  atravessa blocos e não leva dano  ·  Espaço sobe, C desce, F sai", 16, HORIZONTAL_ALIGNMENT_CENTER)
	creative_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	creative_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	creative_label.offset_top = 104   # no meio do topo, abaixo da hotbar e dos buffs
	creative_label.add_theme_color_override("font_color", Ui.GOLD)
	root.add_child(creative_label)
	flight_bar = ProgressBar.new()   # tempo de voo das asas: só aparece enquanto não está cheio
	flight_bar.set_anchors_preset(Control.PRESET_CENTER)
	flight_bar.offset_left = -50
	flight_bar.offset_right = 50
	flight_bar.offset_top = 30
	flight_bar.offset_bottom = 40
	flight_bar.show_percentage = false
	flight_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flight_bar.add_theme_stylebox_override("fill", Ui.box(Color("#9ad0ff"), Ui.EDGE, 1, 3))
	root.add_child(flight_bar)
	debug_label = _label("", 12)
	debug_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	debug_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	debug_label.offset_left = 12
	debug_label.offset_bottom = -8
	debug_label.modulate = Color(1, 1, 1, 0.8)
	root.add_child(debug_label)
	buff_row = HBoxContainer.new()   # à direita da hotbar, na mesma altura
	buff_row.position = Vector2(X0 + 10 * PITCH + 14, Y0)
	buff_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	buff_row.add_theme_constant_override("separation", 6)
	root.add_child(buff_row)
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


# Abre ou fecha a parte do inventário: só liga/desliga os cliques; o aparecer/sumir animado é _animate_open.
func _set_open(open: bool) -> void:
	for i in slots.size():
		slots[i].mouse_filter = Control.MOUSE_FILTER_STOP if open or i >= Inventory.HOTBAR else Control.MOUSE_FILTER_IGNORE
	if not open:
		chest = {}
	_animate_open()


# Desliza e some/aparece conforme open_t (0-1): fileiras 2-5 da grade, criação/baú, equipamento, moedas, munição e lixeira.
func _animate_open() -> void:
	var e := ease(open_t, -2.0)
	var shown := open_t > 0.0
	for i in range(Inventory.HOTBAR, slots.size()):
		slots[i].visible = shown
		slots[i].modulate.a = e
	for n in [craft_root, equip_root, chest_root, trash_slot, sort_button] + side_nodes:
		n.visible = shown and (n != craft_root or chest.is_empty()) and (n != chest_root or not chest.is_empty())
		n.modulate.a = e
	craft_root.position.x = X0 - (1.0 - e) * 60.0
	chest_root.position.x = X0 - (1.0 - e) * 60.0
	equip_root.offset_left = -190 + (1.0 - e) * 60.0
	equip_root.offset_right = -14 + (1.0 - e) * 60.0


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
	trash_slot.position = Vector2(X0 + 10 * PITCH + 6, Y0 + 5 * PITCH)
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


# Clique num slot do inventário: esquerdo pega/solta/junta/troca; direito pega 1; Alt favorita; Ctrl joga no lixo; Shift manda para o baú aberto ou veste.
func _on_slot_input(e: InputEvent, i: int) -> void:
	var inv: Inventory = player.inv
	if _pressed(e, MOUSE_BUTTON_LEFT):
		last_click = Engine.get_process_frames()
		if e.alt_pressed:
			inv.toggle_fav(i)
		elif e.ctrl_pressed and inv.cursor_id == -1 and inv.quick_trash(i):
			pass
		elif e.shift_pressed and inv.cursor_id == -1 and inv.fav[i] == 0 and (_to_chest(i) or inv.equip_from(i)):
			pass
		else:
			inv.click(i)
	elif _pressed(e, MOUSE_BUTTON_RIGHT):
		last_click = Engine.get_process_frames()
		if not (inv.cursor_id == -1 and inv.equip_from(i)):
			inv.right_click(i)


func _to_chest(i: int) -> bool:
	if chest.is_empty():
		return false
	var ok := Inventory.move_stack(player.inv.item, player.inv.count, i, chest.item, chest.count)
	player.inv.version += 1
	return ok


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


# Equipamento à direita: defesa, 3 slots de armadura, acessórios e o botão Configurações.
func _build_equipment() -> void:
	equip_root = VBoxContainer.new()
	equip_root.anchor_left = 1.0
	equip_root.anchor_right = 1.0
	equip_root.offset_left = -190
	equip_root.offset_right = -14
	equip_root.offset_top = 250
	equip_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(equip_root)
	defense_label = _label("", 18)
	equip_root.add_child(defense_label)
	var grid := GridContainer.new()   # armadura (cabeça, corpo, pernas) na 1ª fileira e os 5 acessórios nas outras duas
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", PITCH - SLOT)
	grid.add_theme_constant_override("v_separation", PITCH - SLOT)
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	equip_root.add_child(grid)
	for k in Inventory.ARMOR.size():
		var b := _slot()
		b.gui_input.connect(func(e: InputEvent):
			if _pressed(e, MOUSE_BUTTON_LEFT):
				last_click = Engine.get_process_frames()
				player.inv.click_equip(k)
			elif _pressed(e, MOUSE_BUTTON_RIGHT):
				last_click = Engine.get_process_frames()
				player.inv.unequip(k))
		equip_slots.append(b)
		grid.add_child(b)
	for k in Inventory.ACC:
		var b := _slot()
		b.gui_input.connect(func(e: InputEvent):
			if _pressed(e, MOUSE_BUTTON_LEFT):
				last_click = Engine.get_process_frames()
				player.inv.click_acc(k)
			elif _pressed(e, MOUSE_BUTTON_RIGHT):
				last_click = Engine.get_process_frames()
				if player.inv.acc[k] != -1 and player.inv.add(player.inv.acc[k], 1) == 0:
					player.inv.acc[k] = -1)
		acc_slots.append(b)
		grid.add_child(b)
	var menu := Button.new()   # a engrenagem do Terraria: a pausa mora aqui, não no Esc
	menu.text = "Configurações"
	menu.focus_mode = Control.FOCUS_NONE
	menu.pressed.connect(func():
		player.set_inventory(false)
		player.set_menu(true))
	equip_root.add_child(menu)


func _build_life() -> void:
	minimap = Minimap.new()
	root.add_child(minimap)
	root.move_child(minimap, 0)   # a sobreposição (Tab) fica atrás da interface
	minimap.setup(world, player)
	var box := VBoxContainer.new()
	life_box = box
	box.anchor_left = 1.0
	box.anchor_right = 1.0
	box.offset_left = -360
	box.offset_right = -44
	box.offset_top = 10
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(box)
	life_label = _label("", 18, HORIZONTAL_ALIGNMENT_RIGHT)
	box.add_child(life_label)
	star_col = VBoxContainer.new()
	star_col.anchor_left = 1.0
	star_col.anchor_right = 1.0
	star_col.offset_left = -40
	star_col.offset_right = -10
	star_col.offset_top = 10
	star_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	star_col.add_theme_constant_override("separation", -4)
	root.add_child(star_col)
	star_col.add_child(_label("Mana", 14, HORIZONTAL_ALIGNMENT_CENTER))
	for k in 10:
		var st := _label("★", 28, HORIZONTAL_ALIGNMENT_CENTER)
		st.pivot_offset = Vector2(15, 16)
		star_col.add_child(st)
		stars.append(st)
	for r in 2:   # até 20 corações (400 de vida) em duas fileiras de 10, como no Terraria
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_END
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_theme_constant_override("separation", 0)
		box.add_child(row)
		heart_rows.append(row)
		for k in 10:
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


# Coluna de moedas (as moedas giram), coluna de munição e o botão Ordenar, à direita da grade.
func _build_side() -> void:
	var x := X0 + 10 * PITCH + 6
	for r in 4:
		var box := Panel.new()   # moeda: cobre, prata, ouro, platina (de baixo para cima no Terraria; aqui a mais valiosa em cima)
		box.position = Vector2(x, Y0 + (1 + r) * PITCH)
		box.size = Vector2(SLOT, SLOT)
		box.pivot_offset = box.size / 2.0
		box.add_theme_stylebox_override("panel", Ui.box(Ui.BLUE.darkened(0.15)))
		box.mouse_filter = Control.MOUSE_FILTER_PASS
		var ic := TextureRect.new()
		ic.name = "Icon"
		ic.position = Vector2(6, 6)
		ic.size = Vector2(30, 30)
		ic.pivot_offset = Vector2(15, 15)
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(ic)
		var n := _label("", 13, HORIZONTAL_ALIGNMENT_RIGHT)
		n.name = "Count"
		n.position = Vector2(SLOT - 34, SLOT - 21)
		n.size = Vector2(30, 18)
		box.add_child(n)
		root.add_child(box)
		coin_views.append(box)
		side_nodes.append(box)
	for r in Inventory.AMMO:
		var b := _slot()
		b.position = Vector2(x + PITCH, Y0 + (1 + r) * PITCH)
		b.gui_input.connect(func(e: InputEvent):
			if _pressed(e, MOUSE_BUTTON_LEFT):
				last_click = Engine.get_process_frames()
				player.inv.click_ammo(r))
		root.add_child(b)
		ammo_slots.append(b)
		side_nodes.append(b)
	var lab := _label("moedas  munição", 12)
	lab.position = Vector2(x - 2, Y0 + PITCH - 2)
	root.add_child(lab)
	side_nodes.append(lab)
	sort_button = Button.new()
	sort_button.text = "Ordenar"
	sort_button.focus_mode = Control.FOCUS_NONE
	sort_button.tooltip_text = "Junta o inventário por nome (favoritos e a hotbar ficam)"
	sort_button.position = Vector2(X0 + 11 * PITCH + 6, Y0 + 5 * PITCH + 8)
	sort_button.pressed.connect(func(): player.inv.sort_items())
	root.add_child(sort_button)


# Painel do baú (40 slots) no lugar da criação, embaixo do inventário; abre com o botão direito num baú.
func _build_chest() -> void:
	chest_root = Control.new()
	chest_root.position = Vector2(X0, Y0 + 5 * PITCH + 14)
	chest_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(chest_root)
	chest_root.add_child(_label("Baú", 18))
	var g := _grid(10)
	g.position = Vector2(0, 30)
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chest_root.add_child(g)
	for i in CHEST_SLOTS:
		var b := _slot()
		b.gui_input.connect(func(e: InputEvent):
			if chest.is_empty():
				return
			var inv: Inventory = player.inv
			if _pressed(e, MOUSE_BUTTON_LEFT):
				last_click = Engine.get_process_frames()
				if e.shift_pressed and inv.cursor_id == -1:
					Inventory.move_stack(chest.item, chest.count, i, inv.item, inv.count)
					inv.version += 1
				else:
					inv.click(i, chest.item, chest.count)
			elif _pressed(e, MOUSE_BUTTON_RIGHT):
				last_click = Engine.get_process_frames()
				inv.right_click(i, chest.item, chest.count))
		g.add_child(b)
		chest_slots.append(b)


# Chamado pelo jogador ao clicar num baú: mostra o painel (e abre o inventário).
func open_chest(c: Dictionary) -> void:
	chest = c
	shown_version = -1
	_animate_open()


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


# Configurações (o botão do inventário): pausa o jogo; o que se muda vale na hora e fica em user://settings.cfg (Settings).
func _build_pause() -> void:
	pause = PanelContainer.new()
	pause.set_anchors_preset(Control.PRESET_CENTER)
	pause.grow_horizontal = Control.GROW_DIRECTION_BOTH
	pause.grow_vertical = Control.GROW_DIRECTION_BOTH
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(360, 0)
	box.add_theme_constant_override("separation", 8)
	box.add_child(_label("Configurações", 30, HORIZONTAL_ALIGNMENT_CENTER))
	_setting(box, "Distância de renderização", Settings.DISTANCE.x, Settings.DISTANCE.y, 1, " chunks", func(): return world.render_distance, _set_distance)
	_setting(box, "Volume", 0, 100, 5, "%", func(): return Settings.volume * 100.0, func(v: float): Settings.volume = v / 100.0)
	_setting(box, "Sensibilidade do mouse", Settings.SENS.x * 100, Settings.SENS.y * 100, 5, "%", func(): return Settings.mouse_sens * 100.0, func(v: float): Settings.mouse_sens = v / 100.0)
	for b in [["Continuar", func(): player.set_menu(false)], ["Salvar e sair", _save_and_quit]]:
		var btn := Ui.menu_button(b[0])
		btn.pressed.connect(b[1])
		box.add_child(btn)
	pause.add_child(box)
	root.add_child(pause)


func _set_distance(v: float) -> void:
	Settings.render_distance = int(v)
	world.set_render_distance(int(v))


# Linha do Configurações: nome e valor sobre um controle deslizante que aplica na hora. `value` lê o valor atual (a linha se ajusta ao abrir).
func _setting(box: Control, text: String, lo: float, hi: float, step: float, unit: String, value: Callable, apply: Callable) -> void:
	var label := _label("", 16)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.focus_mode = Control.FOCUS_NONE
	s.custom_minimum_size = Vector2(0, 22)
	var show := func(v: float): label.text = "%s: %d%s" % [text, roundi(v), unit]
	s.value_changed.connect(func(v: float):
		apply.call(v)
		show.call(v))
	syncs.append(func():
		var v: float = value.call()
		s.set_value_no_signal(v)
		show.call(v))
	box.add_child(label)
	box.add_child(s)


const TIPS := ["Bem-vindo! Use o machado nas árvores para juntar madeira e faça uma bancada de trabalho.", "Ache Life Crystals nas cavernas: cada um dá +20 de vida máxima.",
	"Quebre 3 Shadow Orbs ou Crimson Hearts com um martelo para despertar um chefe.", "Fallen Stars caem à noite; 5 delas fazem um Mana Crystal.",
	"Segure Shift para escolher a ferramenta certa sozinho.", "Poções de cura deixam a Doença da poção por 1 minuto."]
const SHOP := [["copper_pickaxe", 500], ["copper_axe", 400], ["torch", 50], ["lesser_healing_potion", 300], ["lesser_mana_potion", 100], ["wooden_arrow", 5]]   # preços em cobre (wiki Merchant)


# Painel de conversa (abaixo do inventário, no meio): nome, fala e botões do que o habitante faz. Fecha com o inventário.
func _build_npc() -> void:
	npc_panel = PanelContainer.new()
	npc_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	npc_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	npc_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	npc_panel.offset_bottom = -30
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(520, 0)
	box.add_theme_constant_override("separation", 8)
	npc_text = _label("", 18)
	npc_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(npc_text)
	npc_buttons = HFlowContainer.new()   # quebra em linhas dentro dos 520 do painel
	npc_buttons.custom_minimum_size = Vector2(520, 0)
	npc_buttons.add_theme_constant_override("h_separation", 8)
	npc_buttons.add_theme_constant_override("v_separation", 6)
	box.add_child(npc_buttons)
	npc_panel.add_child(box)
	npc_panel.visible = false
	root.add_child(npc_panel)


func _npc_button(text: String, action: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(action)
	npc_buttons.add_child(b)


func _price(copper: int) -> String:
	return ("%dp" % (copper / 100)) + (" %dc" % (copper % 100) if copper % 100 else "") if copper >= 100 else "%dc" % copper


# Chamado ao falar com um habitante (botão direito): abre o painel com as opções dele.
func open_npc(kind: String) -> void:
	npc_kind = kind
	for c in npc_buttons.get_children():
		npc_buttons.remove_child(c)
		c.queue_free()
	match kind:
		"guide":
			npc_text.text = "Guia: \"%s\"" % TIPS[tip_index % TIPS.size()]
			_npc_button("Ajuda", func():
				tip_index += 1
				open_npc("guide"))
		"merchant":
			npc_text.text = "Comerciante: \"Boa escolha! O que vai levar?\""
			for g in SHOP:
				var id: int = Items.ids[g[0]]
				_npc_button("%s (%s)" % [Items.label(id).capitalize(), _price(g[1])], func():
					if player.inv.pay(g[1]):
						player.inv.add(id, 1)
						Sfx.play(player.entities, "coin", player.position, -6.0)
					else:
						player.say("faltam moedas"))
		"nurse":
			var cost := maxi(ceili(player.max_hp - player.hp), 0)
			npc_text.text = "Enfermeira: \"%s\"" % ("Você está bem!" if cost == 0 else "Posso curar você por %s." % _price(cost))
			if cost > 0:
				_npc_button("Curar (%s)" % _price(cost), func():
					if player.inv.pay(cost):
						player.hp = player.max_hp
						Sfx.play(player.entities, "drink", player.position, -4.0)
						open_npc("nurse")
					else:
						player.say("faltam moedas"))
	_npc_button("Fechar", func(): player.set_inventory(false))


# Com o jogo pausado o jogador não recebe teclas: é o HUD que fecha o Configurações com Esc. F10 esconde o FPS e F11 o HUD (wiki Controls).
func _unhandled_input(e: InputEvent) -> void:
	if player.menu_open and e.is_action_pressed("ui_cancel"):
		player.set_menu(false)
		get_viewport().set_input_as_handled()
	elif e is InputEventKey and e.pressed and not e.echo:
		if e.physical_keycode == KEY_F10:
			debug_label.visible = not debug_label.visible
		elif e.physical_keycode == KEY_F11:
			root.visible = not root.visible


func _save_and_quit() -> void:
	get_tree().paused = false
	Settings.save()
	SaveGame.save_all(world, player, clock)
	get_tree().change_scene_to_file("res://menu.tscn")


func _icon(id: int) -> Texture2D:
	return player.entities.icon(id)


func _fill(b: Slot, id: int, count: int) -> void:
	b.icon = _icon(id) if id != -1 else null
	b.get_node("Count").text = str(count) if id != -1 and count > 1 else ""
	b.tooltip_text = Ui.item_tip(id) if id != -1 else ""


func _show_slot(i: int) -> void:
	var inv: Inventory = player.inv
	_fill(slots[i], inv.item[i], inv.count[i])
	slots[i].add_theme_stylebox_override("normal", sel_style if i == player.slot and i < Inventory.HOTBAR else Ui.theme().get_stylebox("normal", "Button"))
	var star: Label = slots[i].get_node_or_null("Fav")
	if inv.fav[i] == 1 and star == null:
		star = _label("★", 14)
		star.name = "Fav"
		star.position = Vector2(SLOT - 17, 1)
		star.add_theme_color_override("font_color", Ui.GOLD)
		slots[i].add_child(star)
	elif inv.fav[i] == 0 and star:
		star.queue_free()
	if prev_item.size() == Inventory.SIZE and inv.item[i] != -1 and (inv.item[i] != prev_item[i] or inv.count[i] > prev_count[i]):
		slots[i].pop()
		if Engine.get_process_frames() - last_click > 2 and inv.cursor_id == -1 and slots[i].is_visible_in_tree():   # não foi um clique: pegou algo do chão
			_fly(inv.item[i], slots[i])
	prev_item[i] = inv.item[i]
	prev_count[i] = inv.count[i]


# Ícone que voa do centro-baixo da tela até o slot que recebeu o item (e some com o pulo do slot).
func _fly(id: int, target: Control) -> void:
	var ic := TextureRect.new()
	ic.texture = _icon(id)
	ic.size = Vector2(30, 30)
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var size := root.get_viewport_rect().size
	ic.position = Vector2(size.x * 0.5, size.y * 0.72)
	root.add_child(ic)
	var t := ic.create_tween().set_parallel().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.tween_property(ic, "position", target.global_position + Vector2(9, 9), 0.4)
	t.tween_property(ic, "scale", Vector2.ONE * 0.6, 0.4)
	t.chain().tween_callback(ic.queue_free)


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


# Buffs ativos: ícone da poção com o tempo embaixo, à direita da hotbar (o clique direito, com o inventário aberto, cancela). Refaz quando muda o conjunto.
func _show_buffs() -> void:
	var names: Array = player.buffs.keys()
	names.sort()
	var key := ",".join(names)
	if key != buff_key:
		buff_key = key
		for c in buff_row.get_children():
			c.queue_free()
		for n in names:
			var def: Dictionary = Buffs.defs[n]
			var cell := VBoxContainer.new()
			cell.name = n
			cell.add_theme_constant_override("separation", -2)
			var ic := TextureRect.new()
			ic.texture = _icon(Items.ids[def.icon])
			ic.custom_minimum_size = Vector2(32, 32)
			ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			ic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			ic.tooltip_text = "%s\n%s" % [def.label, def.tip]
			ic.modulate = Color(1, 0.6, 0.6) if def.get("debuff", false) else Color.WHITE
			ic.gui_input.connect(func(e: InputEvent):
				if _pressed(e, MOUSE_BUTTON_RIGHT) and not def.get("debuff", false):
					player.buffs.erase(n))
			cell.add_child(ic)
			var t := _label("", 12, HORIZONTAL_ALIGNMENT_CENTER)
			t.name = "Time"
			cell.add_child(t)
			buff_row.add_child(cell)
	for cell in buff_row.get_children():
		if player.buffs.has(cell.name):
			cell.get_node("Time").text = Buffs.time_text(player.buffs[cell.name])


func _process(delta: float) -> void:
	var open: bool = player.inventory_open
	pause.visible = player.menu_open
	if not open:
		npc_kind = ""
	npc_panel.visible = open and npc_kind != ""
	cross.visible = not (open or player.menu_open or player.map_open)   # com o mouse solto a mira não faz sentido
	creative_label.visible = player.creative
	var wings: Dictionary = player.inv.wings()
	flight_bar.visible = not wings.is_empty() and not player.creative and player.flight_left < wings.time - 0.001
	if flight_bar.visible:
		flight_bar.max_value = wings.time
		flight_bar.value = player.flight_left
	if player.menu_open != was_menu:   # abrir recarrega os valores; fechar grava as opções
		was_menu = player.menu_open
		if was_menu:
			for f in syncs:
				f.call()
		else:
			Settings.save()
	spin += delta
	if prev_item.is_empty():
		prev_item.resize(Inventory.SIZE)
		prev_item.fill(-1)
		prev_count.resize(Inventory.SIZE)
	var t_before := open_t
	open_t = move_toward(open_t, 1.0 if open else 0.0, delta * OPEN_SPEED)
	if open_t != t_before:
		_animate_open()
	if open != was_open:
		_set_open(open)
		if not open:  # fechou com item na mão: volta ao inventário; o que não couber cai no chão
			var held_id: int = player.inv.cursor_id
			var left: int = player.inv.release_cursor()
			if left > 0:
				player.entities.spawn_drop(held_id, left, player.position + Vector3.UP)
		shown_version = -1
	var hp: float = player.hp
	var low: bool = hp <= player.max_hp * 0.3
	var want := ceili(player.max_hp / float(HP_PER_HEART))
	if want != hearts_shown:   # a vida máxima mudou: mostra os corações certos e desce o minimapa/equipamento se sobrar uma 2ª fileira
		hearts_shown = want
		for i in hearts.size():
			hearts[i].visible = i < want
		heart_rows[1].visible = want > 10
		var extra := 30.0 if want > 10 else 0.0
		minimap.corner_y = 74.0 + extra
		minimap._layout()
		equip_root.offset_top = 250.0 + extra
	var beat := 1.0 + (0.14 * maxf(sin(spin * 7.0), 0.0) if low else 0.03 * sin(spin * 2.0))   # com pouca vida os corações batem
	var hurt_shake: float = maxf(0.0, 0.35 - player.since_hit) * 14.0
	for i in hearts.size():
		var f := clampf((hp - i * HP_PER_HEART) / HP_PER_HEART, 0.0, 1.0)
		hearts[i].modulate = Color(1, 1, 1, 0.35 + 0.65 * f) if f > 0.0 else Color(0.2, 0.2, 0.2, 0.55)
		hearts[i].scale = Vector2.ONE * (0.68 + 0.32 * f) * (beat if f > 0.0 else 1.0)
		hearts[i].rotation = sin(spin * 60.0 + i) * 0.05 * hurt_shake
	life_label.text = "Vida: %d/%d" % [ceili(hp), player.max_hp]
	for k in stars.size():   # cada estrela é 20 de mana; a última cheia pisca quando a mana chega ao máximo
		var f := clampf((player.mana - k * 20.0) / 20.0, 0.0, 1.0)
		stars[k].visible = k * 20 < player.max_mana
		stars[k].modulate = Color(0.45, 0.65, 1.0, 0.3 + 0.7 * f) if f > 0.0 else Color(0.25, 0.3, 0.45, 0.5)
		stars[k].scale = Vector2.ONE * (0.75 + 0.25 * f)
	defense_label.text = "Defesa: %d" % player.defense()
	_show_buffs()
	var id: int = player.held()
	var now := Time.get_ticks_msec()
	if id != shown_held:  # o nome do item aparece um instante, na cor da raridade
		shown_held = id
		item_until = now + 2200
		item_label.text = Items.label(id).capitalize() if id != -1 else ""
		item_label.add_theme_color_override("font_color", Items.rarity_color(id) if id != -1 else Color.WHITE)
	item_label.visible = open_t < 0.5
	item_label.modulate.a = clampf((item_until - now) / 500.0, 0.0, 1.0)
	var boss: Node3D = player.entities.boss
	boss_bar.visible = boss != null
	if boss:
		var life: int = player.entities.boss_life()
		boss_bar.max_value = player.entities.boss_max
		boss_bar.value = life
		boss_bar.get_node("Name").text = "%s  %d/%d" % [player.entities.group_of(boss).replace("_", " ").capitalize(), life, player.entities.boss_max]
	var inv: Inventory = player.inv
	var changed: bool = inv.version != shown_version
	if changed or player.slot != shown_slot or Engine.get_process_frames() % 30 == 0:
		shown_slot = player.slot
		for i in Inventory.SIZE:
			_show_slot(i)
	if open:
		var near := Crafting.stations_near(world, player.position) if changed or Engine.get_process_frames() % 30 == 0 else stations
		if changed or near != stations:
			stations = near
			for k in Inventory.ARMOR.size():
				_fill(equip_slots[k], inv.equip[k], 1)
				if inv.equip[k] == -1:
					equip_slots[k].tooltip_text = "[color=#aab4ff]Armadura: %s[/color]" % ARMOR_NAMES[k]
			for k in Inventory.ACC:
				_fill(acc_slots[k], inv.acc[k], 1)
				if inv.acc[k] == -1:
					acc_slots[k].tooltip_text = "[color=#aab4ff]Acessório[/color]"
			for k in Inventory.AMMO:
				_fill(ammo_slots[k], inv.ammo[k], inv.ammo_count[k])
			for k in 4:
				var v: Control = coin_views[k]
				var cid: int = Items.ids[Inventory.COINS[k]]
				v.get_node("Icon").texture = _icon(cid)
				v.get_node("Count").text = str(inv.coin[k])
				v.tooltip_text = Ui.item_tip(cid)
				v.modulate.a = 1.0 if inv.coin[k] > 0 else 0.5
			if not chest.is_empty():
				for k in CHEST_SLOTS:
					_fill(chest_slots[k], chest.item[k], chest.count[k])
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
	for k in 4:   # as moedas giram
		coin_views[k].get_node("Icon").scale.x = cos(spin * 3.0 + k * 0.9)
	cursor_view.visible = open and inv.cursor_id != -1
	if cursor_view.visible:
		cursor_view.position = get_viewport().get_mouse_position() + Vector2(6, 6 + sin(spin * 5.0) * 2.0)   # o item preso balança de leve
		cursor_view.rotation = sin(spin * 4.0) * 0.06
		cursor_view.get_node("Icon").texture = _icon(inv.cursor_id)
		cursor_view.get_node("Count").text = str(inv.cursor_count) if inv.cursor_count > 1 else ""
	var cam: Vector3 = player.cam.global_position
	var wet: int = world.liquid_at(cam)
	tint.color = Color(0.08, 0.28, 0.7, 0.4) if wet == Blocks.ids.water else Color(1.0, 0.3, 0.05, 0.55) if wet == Blocks.ids.lava else Color.TRANSPARENT
	flash.color = Color(0.9, 0.05, 0.05, clampf((player.iframes - (player.IFRAMES - 0.3)) / 0.3, 0.0, 1.0) * 0.3)
	note_label.text = player.message if now < player.message_until else ""
	var p: Vector3 = player.position
	debug_label.text = "FPS %d  |  distância %d chunks ([ ])  |  %s%s  |  %s  |  %s  |  pos %d %d %d" % [
		Engine.get_frames_per_second(), world.render_distance, clock.clock(), " (noite)" if clock.is_night() else "",
		("modo criativo (F)" if player.creative else "andando (F: criativo)"), "3ª pessoa (V)" if player.third_person else "1ª pessoa (V)", p.x, p.y, p.z]
