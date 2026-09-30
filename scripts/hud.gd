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
var guide_box: VBoxContainer           # Guia > Criação: um espaço para o item e a lista do que dá para criar com ele
var guide_slot: Slot
var guide_list: VBoxContainer
var guide_id := -1                     # item no espaço do Guia (volta ao inventário ao fechar)
var guide_count := 0
var guide_craft := false              # o Guia está no modo Criação (senão, nas dicas)
var test_panel: PanelContainer         # painel de atalhos do mundo de teste (F9)
var test_open := false
var test_footer: Label
var test_syncs: Array[Callable] = []   # textos dos botões que dependem do estado (relógio, hardmode)
var chest_title: Label
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
var radar_label: Label                # Radar: quantos inimigos há por perto, sob o minimapa
var breath_label: Label               # bolhas de ar (10) sob a mira, só quando o fôlego não está cheio
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
var dark: ColorRect                   # tela escura quando a câmera está dentro de bloco (fica atrás do minimapa e da interface)
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
	_build_test()
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
	breath_label = _label("", 30, HORIZONTAL_ALIGNMENT_CENTER)
	breath_label.set_anchors_preset(Control.PRESET_CENTER)
	breath_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	breath_label.offset_top = 40
	breath_label.add_theme_color_override("font_color", Color("#9ad8ff"))
	breath_label.add_theme_constant_override("outline_size", 4)
	breath_label.add_theme_color_override("font_outline_color", Color("#0a2a5a"))
	root.add_child(breath_label)
	radar_label = _label("", 16, HORIZONTAL_ALIGNMENT_RIGHT)
	radar_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	radar_label.offset_left = -300.0
	radar_label.offset_right = -44.0
	radar_label.add_theme_constant_override("outline_size", 4)
	radar_label.add_theme_color_override("font_outline_color", Color.BLACK)
	root.add_child(radar_label)
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
	toggle_all.icon = Items.icon_texture(Items.ids.wooden_hammer, world.atlas_texture)   # o martelo, como no Terraria
	toggle_all.add_theme_constant_override("icon_max_width", 22)
	toggle_all.custom_minimum_size = Vector2(40, 30)
	toggle_all.toggle_mode = true
	toggle_all.focus_mode = Control.FOCUS_NONE
	toggle_all.tooltip_text = "Martelo: mostra a lista completa (o que ainda não dá para criar fica apagado)"
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
	dark = _overlay()
	dark.color = Color(0.03, 0.02, 0.02)
	dark.visible = false
	root.move_child(dark, 0)
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
		box.mouse_filter = Control.MOUSE_FILTER_STOP   # clicável: pega a pilha de moedas para a mão ou guarda uma moeda do mesmo tipo
		box.gui_input.connect(func(e: InputEvent):
			if _pressed(e, MOUSE_BUTTON_LEFT):
				last_click = Engine.get_process_frames()
				player.inv.click_coin(r))
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
	chest_title = _label("Baú", 18)
	chest_root.add_child(chest_title)
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
					inv.take_stack(chest.item, chest.count, i)
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
	chest_title.text = c.get("title", "Baú")
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


# Configurações (o botão do inventário), no layout do Menu de Configurações do Terraria: categorias à esquerda, opções à direita.
# Pausa o jogo; o que se muda vale na hora e fica em user://settings.cfg (Settings).
func _build_pause() -> void:
	pause = PanelContainer.new()
	pause.set_anchors_preset(Control.PRESET_CENTER)
	pause.grow_horizontal = Control.GROW_DIRECTION_BOTH
	pause.grow_vertical = Control.GROW_DIRECTION_BOTH
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 10)
	outer.add_child(_label("Menu de Configurações", 22, HORIZONTAL_ALIGNMENT_CENTER))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	var cats := VBoxContainer.new()
	cats.custom_minimum_size = Vector2(190, 0)
	cats.add_theme_constant_override("separation", 6)
	var pages := PanelContainer.new()
	pages.custom_minimum_size = Vector2(400, 250)
	var pages_box := VBoxContainer.new()
	pages_box.add_theme_constant_override("separation", 8)
	pages.add_child(pages_box)
	var page_nodes := {}
	var cat_buttons := {}
	var show_page := func(name: String):
		for k in page_nodes:
			page_nodes[k].visible = k == name
			cat_buttons[k].add_theme_color_override("font_color", Ui.GOLD if k == name else Color.WHITE)
	for c in ["Geral", "Vídeo", "Controle"]:
		var page := VBoxContainer.new()
		page.add_theme_constant_override("separation", 8)
		page.add_child(_label({"Geral": "Volume", "Vídeo": "Vídeo", "Controle": "Controle"}[c], 18, HORIZONTAL_ALIGNMENT_CENTER))
		pages_box.add_child(page)
		page_nodes[c] = page
		var cb := Ui.menu_button(c)
		cb.pressed.connect(func(): show_page.call(c))
		cats.add_child(cb)
		cat_buttons[c] = cb
	_setting(page_nodes["Geral"], "Som", 0, 100, 5, "%", func(): return Settings.volume * 100.0, func(v: float): Settings.volume = v / 100.0)
	_setting(page_nodes["Vídeo"], "Distância de renderização", Settings.DISTANCE.x, Settings.DISTANCE.y, 1, " chunks", func(): return world.render_distance, _set_distance)
	_setting(page_nodes["Controle"], "Sensibilidade do mouse", Settings.SENS.x * 100, Settings.SENS.y * 100, 5, "%", func(): return Settings.mouse_sens * 100.0, func(v: float): Settings.mouse_sens = v / 100.0)
	for b in [["Fechar Menu", func(): player.set_menu(false)], ["Salvar e Sair", _save_and_quit]]:
		var btn := Ui.menu_button(b[0])
		btn.pressed.connect(b[1])
		cats.add_child(btn)
	show_page.call("Geral")
	row.add_child(cats)
	row.add_child(pages)
	outer.add_child(row)
	pause.add_child(outer)
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


# Painel do mundo de teste (F9): atalhos de hora, jogador, hardmode, chefes, inimigos, viagem e baús. Só aparece em mundo de teste.
func _build_test() -> void:
	test_panel = PanelContainer.new()
	test_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	test_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	test_panel.offset_top = 70
	test_panel.visible = false
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(500, 0)
	box.add_theme_constant_override("separation", 5)
	box.add_child(_label("Painel de teste  (F9 fecha)", 22, HORIZONTAL_ALIGNMENT_CENTER))
	var ent: Node3D = player.entities
	_test_row(box, "Hora", [["Dia", func(): clock.time = 60.0], ["Meio-dia", func(): clock.time = 450.0], ["Noite", func(): clock.time = clock.DAY_SECONDS + 60.0],
		["Relógio", func(): clock.hold = not clock.hold, func(): return "Relógio: %s" % ("parado" if clock.hold else "correndo")]])
	_test_row(box, "Jogador", [["Vida e mana máximas", func():
			player.max_hp = player.MAX_HP_CAP
			player.max_mana = player.MAX_MANA_CAP
			player.hp = player.max_hp
			player.mana = player.max_mana], ["Curar", func():
			player.hp = player.max_hp
			player.mana = player.max_mana], ["+10 de ouro", func(): player.inv.add(Items.ids.gold_coin, 10)],
		["Criativo", func(): player.creative = not player.creative, func(): return "Criativo: %s" % ("sim" if player.creative else "não")]])
	_test_row(box, "Hardmode", [["Hardmode", func():
			if world.hardmode:
				world.hardmode = false   # ponytail: desligar só volta os spawns e a geração; o terreno já convertido fica
				world.gen.hardmode = false
			else:
				world.start_hardmode(), func(): return "Hardmode: %s" % ("ligado" if world.hardmode else "desligado")]])
	var bosses := []
	for n in ent.boss_names():
		bosses.append([Items.title(n), func():
			ent.test_boss(n)
			player.set_inventory(false)])
	_test_row(box, "Chefes", bosses)
	_test_row(box, "Inimigos", [["Chamar vitrine", ent.showcase], ["Limpar inimigos", ent.clear_enemies], ["Meteorito", func():
			ent.start_meteor()
			player.set_inventory(false)], ["Reabastecer baús", func():
			for k in TestWorld.chests:
				world.chests.erase(k.pos)
			player.say("baús reabastecidos")]])
	var trips := []
	for t in [["Nascimento", "spawn"], ["Submundo", "underworld"], ["Dungeon", "dungeon"], ["Bioma do mal", "evil"], ["Hallow", "hallow"], ["Ilha no céu", "sky"]]:
		trips.append([t[0], func():
			ent.goto(t[1])
			player.set_inventory(false)])
	trips.append(["Reiniciar mundo", func():   # apaga o save do mundo de teste e recomeça do zero (blocos, baús e inimigos)
		DirAccess.remove_absolute(SaveGame.test_world())
		SaveGame.world_path = SaveGame.test_world()
		get_tree().change_scene_to_file("res://game.tscn")])
	_test_row(box, "Ir para", trips)
	test_panel.add_child(box)
	root.add_child(test_panel)
	test_footer = _label("MUNDO DE TESTE  ·  F9 painel  ·  F8 kit  ·  F criativo  ·  V 3ª pessoa  ·  F5 salvar", 13, HORIZONTAL_ALIGNMENT_CENTER)
	test_footer.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	test_footer.grow_horizontal = Control.GROW_DIRECTION_BOTH
	test_footer.grow_vertical = Control.GROW_DIRECTION_BEGIN
	test_footer.offset_bottom = -26
	test_footer.add_theme_color_override("font_color", Ui.GOLD)
	test_footer.visible = false
	root.add_child(test_footer)


# Uma linha do painel de teste: nome e botões [texto, ação, texto_vivo?]; o texto vivo (uma função) é recalculado a cada clique e ao abrir.
func _test_row(box: Control, title: String, buttons: Array) -> void:
	box.add_child(_label(title, 14))
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 6)
	flow.add_theme_constant_override("v_separation", 4)
	for b in buttons:
		var btn := Button.new()
		btn.text = b[0]
		btn.focus_mode = Control.FOCUS_NONE
		var act: Callable = b[1]
		var live: Callable = b[2] if b.size() > 2 else Callable()
		btn.pressed.connect(func():
			act.call()
			if live.is_valid():
				btn.text = live.call())
		if live.is_valid():
			btn.text = live.call()
			test_syncs.append(func(): btn.text = live.call())
		flow.add_child(btn)
	box.add_child(flow)


const TIPS := ["Bem-vindo! Use o machado nas árvores para juntar madeira e faça uma bancada de trabalho.", "Ache Life Crystals nas cavernas: cada um dá +20 de vida máxima.",
	"Quebre 3 Shadow Orbs ou Crimson Hearts com um martelo para despertar um chefe.", "Fallen Stars caem à noite; 5 delas fazem um Mana Crystal.",
	"Segure Shift para escolher a ferramenta certa sozinho.", "Poções de cura deixam a Doença da poção por 1 minuto."]
const SHOPS := {   # preços em cobre (wiki)
	"merchant": [["copper_pickaxe", 500], ["copper_axe", 400], ["torch", 50], ["lesser_healing_potion", 300], ["lesser_mana_potion", 100], ["wooden_arrow", 5], ["anvil", 5000], ["mining_helmet", 40000]],
	"demolitionist": [["bomb", 300], ["dynamite", 2000]],
	"arms_dealer": [["musket_ball", 7], ["flintlock_pistol", 50000]],
}


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
	guide_box = VBoxContainer.new()
	guide_box.visible = false
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	guide_slot = _slot()
	guide_slot.tooltip_text = "Clique com um item na mão para pô-lo aqui; clique de novo para pegá-lo de volta."
	guide_slot.gui_input.connect(func(e: InputEvent):
		if _pressed(e, MOUSE_BUTTON_LEFT):
			last_click = Engine.get_process_frames()
			_guide_swap())
	row.add_child(guide_slot)
	var hint := _label("← ponha um item aqui e eu digo o que dá para criar com ele", 14)
	hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(hint)
	guide_box.add_child(row)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(500, 150)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	guide_list = VBoxContainer.new()
	guide_list.add_theme_constant_override("separation", 3)
	scroll.add_child(guide_list)
	guide_box.add_child(scroll)
	box.add_child(guide_box)
	npc_panel.add_child(box)
	npc_panel.visible = false
	root.add_child(npc_panel)


# Dicas do Guia (a ajuda dele, wiki Guide): primeiro as que valem para o que o jogador tem e já fez, na ordem do jogo; depois as gerais.
# O botão Ajuda passa para a próxima.
func _guide_tips() -> Array:
	var inv: Inventory = player.inv
	var count := func(n: String) -> int: return inv.total(Items.ids[n])
	var near := func(n: String) -> bool: return stations.has(Blocks.ids[n])
	var ore := Items.names.any(func(n): return n.ends_with("_ore") and inv.total(Items.ids[n]) > 0)
	var tips := []
	if count.call("wood") < 10 and count.call("workbench") == 0 and not near.call("workbench"):
		tips.append("Corte uma árvore com o machado (botão esquerdo, na base do tronco) para juntar madeira; 10 de madeira fazem uma Bancada de trabalho.")
	if count.call("wood") >= 10 and count.call("workbench") == 0 and not near.call("workbench"):
		tips.append("Você já tem madeira para uma Bancada de trabalho: ela aparece na criação, à esquerda. Coloque-a no chão: muita coisa só se cria perto dela.")
	if count.call("gel") > 0 and count.call("torch") == 0:
		tips.append("Gel e madeira fazem tochas. Elas iluminam as cavernas.")
	if count.call("stone") >= 20 and count.call("furnace") == 0 and not near.call("furnace"):
		tips.append("Uma Fornalha (20 de pedra, 4 de madeira e 3 tochas, feita na bancada) derrete minérios em barras.")
	if ore and not near.call("furnace"):
		tips.append("Minério só vira barra na Fornalha; as barras viram ferramentas, armas e armaduras na Bigorna.")
	if count.call("iron_bar") + count.call("lead_bar") >= 5 and count.call("anvil") + count.call("lead_anvil") == 0 and not near.call("anvil"):
		tips.append("5 barras de ferro fazem uma Bigorna (na bancada). Nela saem picaretas, machados, martelos, espadas, arcos e armaduras.")
	if player.max_hp < 140:
		tips.append("Ache Life Crystals nas cavernas: cada um dá +20 de vida máxima.")
	if not world.evil_boss_down:
		tips.append("Shadow Orbs e Crimson Hearts só quebram com martelo; a cada 3 quebrados um chefe acorda.")
	if count.call("chair") + count.call("door") > 0 or near.call("workbench"):
		tips.append("Habitantes moram em casas: um cômodo fechado (paredes, teto e porta) com tocha, bancada e cadeira. Botão direito na cadeira diz o que falta; eles se mudam sozinhos.")
	if count.call("lens") >= 6:
		tips.append("6 lentes num Altar Demoníaco fazem o Suspicious Looking Eye, que chama o Eye of Cthulhu à noite.")
	if clock.is_night():
		tips.append("À noite caem Fallen Stars: 5 delas fazem um Mana Crystal (+20 de mana).")
	if world.evil_boss_down and not world.skeletron_down:
		tips.append("Um meteorito caiu à meia-noite: a barra dele faz a armadura Meteor. O Velho do dungeon, à noite, chama o Skeletron.")
	if world.skeletron_down and not world.hardmode:
		tips.append("Com o dungeon aberto, jogue a Guide Voodoo Doll na lava do submundo para chamar o Wall of Flesh: ele abre o hardmode.")
	if world.hardmode:
		tips.append("O mundo mudou: cobalto e paládio brotaram na pedra e o Hallow se espalha. Há monstros novos à solta.")
	return tips + TIPS


func _guide_swap() -> void:
	var inv: Inventory = player.inv
	var t := inv.cursor_id
	var c := inv.cursor_count
	inv.cursor_id = guide_id
	inv.cursor_count = guide_count
	guide_id = t
	guide_count = c
	inv.version += 1
	_guide_refresh()


# Devolve o item do espaço do Guia ao inventário (o que não couber cai no chão).
func _guide_return() -> void:
	if guide_id == -1:
		return
	var left: int = player.inv.add(guide_id, guide_count)
	if left > 0:
		player.entities.spawn_drop(guide_id, left, player.position + Vector3.UP)
	guide_id = -1
	guide_count = 0
	_guide_refresh()


# O item do espaço e a lista de receitas que o usam: ícone do resultado e "quantidade nome — ingredientes (estação)".
func _guide_refresh() -> void:
	_fill(guide_slot, guide_id, guide_count)
	for c in guide_list.get_children():
		guide_list.remove_child(c)
		c.queue_free()
	if guide_id == -1:
		return
	var uses := Crafting.uses_of(guide_id)
	if uses.is_empty():
		guide_list.add_child(_label("Não sei criar nada com isso.", 15))
	for r in uses:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var ic := TextureRect.new()
		ic.texture = _icon(r.result)
		ic.custom_minimum_size = Vector2(28, 28)
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		row.add_child(ic)
		var needs := []
		for id in r.needs:
			needs.append("%d %s" % [r.needs[id], Items.title(Items.label(id))])
		var at := " — em: %s" % Items.title(Blocks.ids.keys()[r.station]) if r.station != -1 else ""
		var l := _label("%s%s: %s%s" % ["%d " % r.count if r.count > 1 else "", Items.title(Items.label(r.result)), ", ".join(needs), at], 15)
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(l)
		guide_list.add_child(row)


func _npc_button(text: String, action: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(action)
	npc_buttons.add_child(b)


# Preço da cura (wiki Nurse): 1 de cobre por ponto de vida que falta × o maior avanço do mundo (Olho de Cthulhu 3, Eater/Brain 10, Skeletron 25, Hardmode 60).
# ponytail: sem o ajuste de felicidade (75%-150%) nem cobrança por debuff.
func nurse_cost() -> int:
	var mod := 60 if world.hardmode else 25 if world.skeletron_down else 10 if world.evil_boss_down else 3 if world.eoc_down else 1
	return maxi(ceili(player.max_hp - player.hp), 0) * mod


func _price(copper: int) -> String:
	return ("%dp" % (copper / 100)) + (" %dc" % (copper % 100) if copper % 100 else "") if copper >= 100 else "%dc" % copper


# Chamado ao falar com um habitante (botão direito): abre o painel com as opções dele.
func open_npc(kind: String) -> void:
	npc_kind = kind
	for c in npc_buttons.get_children():
		npc_buttons.remove_child(c)
		c.queue_free()
	guide_box.visible = false
	match kind:
		"guide":
			if guide_craft:
				guide_box.visible = true
				npc_text.text = "Guia: \"Pondo um item no espaço, mostro o que dá para criar com ele.\""
				_guide_refresh()
			else:
				var tips := _guide_tips()
				npc_text.text = "Guia: \"%s\"" % tips[tip_index % tips.size()]
			_npc_button("Ajuda", func():
				guide_craft = false
				tip_index += 1
				open_npc("guide"))
			_npc_button("Criação", func():
				guide_craft = true
				open_npc("guide"))
		"merchant", "demolitionist", "arms_dealer":
			npc_text.text = {"merchant": "Comerciante: \"Boa escolha! O que vai levar?\"", "demolitionist": "Demolitionist: \"Quer explodir alguma coisa?\"", "arms_dealer": "Arms Dealer: \"Bala não falta por aqui.\""}[kind]
			var goods: Array = SHOPS[kind].duplicate()
			if kind == "arms_dealer" and world.evil_boss_down and clock.is_night():   # wiki: Unholy Arrow só à noite e depois do Eater/Brain
				goods.append(["unholy_arrow", 40])
			for g in goods:
				var id: int = Items.ids[g[0]]
				_npc_button("%s (%s)" % [Items.title(Items.label(id)), _price(g[1])], func():
					if player.inv.pay(g[1]):
						player.inv.add(id, 1)
						Sfx.play(player.entities, "coin", player.position, -6.0)
					else:
						player.say("faltam moedas"))
		"nurse":
			var cost := nurse_cost()
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
	var open: bool = player.inventory_open and not test_open   # o painel de teste é modal: esconde o inventário
	pause.visible = player.menu_open
	if not player.inventory_open:
		npc_kind = ""
		test_open = false
		_guide_return()
	npc_panel.visible = open and npc_kind != ""
	var show_test: bool = player.inventory_open and test_open and world.test_world
	if show_test and not test_panel.visible:   # ao abrir, os botões de estado leem o valor atual
		for f in test_syncs:
			f.call()
	test_panel.visible = show_test
	test_footer.visible = world.test_world and root.visible
	cross.visible = not (open or player.menu_open or player.map_open) and absf(player.free_yaw) + absf(player.free_pitch) < 0.05   # no olhar livre a mira não está no centro da tela   # com o mouse solto a mira não faz sentido
	cross.add_theme_color_override("font_color", Ui.GOLD if player.smart_cursor else Color.WHITE)   # dourada: cursor inteligente ligado
	creative_label.visible = player.creative
	var radar: int = player.radar_count()
	radar_label.visible = radar >= 0 and not open
	if radar_label.visible:
		radar_label.offset_top = minimap.corner_y + minimap.PORTRAIT + 6.0
		radar_label.text = "%d inimigos por perto" % radar if radar != 1 else "1 inimigo por perto"
		radar_label.add_theme_color_override("font_color", Color("#ff8a7a") if radar > 0 else Color("#9aff9a"))
	breath_label.visible = player.breath < player.BREATH - 0.05
	if breath_label.visible:   # uma bolha por 10% do fôlego; a última treme quando está acabando
		var bubbles := ceili(player.breath / player.BREATH * 10.0)
		breath_label.text = "○".repeat(10 - bubbles).insert(0, "●".repeat(bubbles))
		breath_label.modulate = Color(1, 1, 1, 1) if player.breath > 3.0 else Color(1, 0.6, 0.6, 0.6 + 0.4 * sin(spin * 12.0))
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
		stars[k].visible = k * 20 < player.mana_cap()
		stars[k].modulate = Color(0.45, 0.65, 1.0, 0.3 + 0.7 * f) if f > 0.0 else Color(0.25, 0.3, 0.45, 0.5)
		stars[k].scale = Vector2.ONE * (0.75 + 0.25 * f)
	defense_label.text = "Defesa: %d" % player.defense()
	_show_buffs()
	var id: int = player.held()
	var now := Time.get_ticks_msec()
	if id != shown_held:  # o nome do item aparece um instante, na cor da raridade
		shown_held = id
		item_until = now + 2200
		item_label.text = Items.title(Items.label(id)) if id != -1 else ""
		item_label.add_theme_color_override("font_color", Items.rarity_color(id) if id != -1 else Color.WHITE)
	item_label.visible = open_t < 0.5
	item_label.modulate.a = clampf((item_until - now) / 500.0, 0.0, 1.0)
	var boss: Node3D = player.entities.boss
	boss_bar.visible = boss != null
	if boss:
		var life: int = player.entities.boss_life()
		boss_bar.max_value = player.entities.boss_max
		boss_bar.value = life
		boss_bar.get_node("Name").text = "%s  %d/%d" % [Items.title(player.entities.group_of(boss)), life, player.entities.boss_max]
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
	var buried: bool = Blocks.solid[world.get_block(floori(cam.x), floori(cam.y), floori(cam.z))] == 1   # câmera dentro de bloco (voo criativo): as faces de trás não existem, então a tela escurece em vez de mostrar o mundo através da terra
	dark.visible = buried
	tint.color = Color(0.08, 0.28, 0.7, 0.4) if wet == Blocks.ids.water else Color(1.0, 0.3, 0.05, 0.55) if wet == Blocks.ids.lava else Color.TRANSPARENT
	flash.color = Color(0.9, 0.05, 0.05, clampf((player.iframes - (player.IFRAMES - 0.3)) / 0.3, 0.0, 1.0) * 0.3)
	note_label.text = player.message if now < player.message_until else ""
	if player.dead > 0.0:   # wiki Death: espera de 10 s
		flash.color = Color(0.0, 0.0, 0.0, 0.55)
		note_label.text = "Você foi derrotado... %d" % ceili(player.dead)
	var p: Vector3 = player.position
	var aimed := ""
	if world.test_world and not player.target.is_empty():
		aimed = "  |  mira: %s" % Blocks.ids.keys()[world.get_block(player.target.pos.x, player.target.pos.y, player.target.pos.z)]
	debug_label.text = "FPS %d  |  distância %d chunks ([ ])  |  %s%s  |  %s  |  %s  |  pos %d %d %d" % [
		Engine.get_frames_per_second(), world.render_distance, clock.clock(), " (noite)" if clock.is_night() else "",
		("modo criativo (F)" if player.creative else "andando (F: criativo)"), "3ª pessoa (V)" if player.third_person else "1ª pessoa (V)", p.x, p.y, p.z] + aimed
