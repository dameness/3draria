class_name Ui
# Estilo de interface do Terraria: texto branco em negrito com contorno escuro, painéis azuis translúcidos,
# corações de vida e dicas de item com o nome na cor da raridade. Tudo procedural: sem arquivos de arte nem fonte
# embutida (usa a fonte do sistema, Ubuntu no Ubuntu; sem ela cai na padrão do Godot).

const BLUE := Color(0.243, 0.322, 0.592, 0.82)   # slots do Terraria: (63, 82, 151)
const BLUE_HOVER := Color(0.36, 0.45, 0.78, 0.92)
const NAVY := Color(0.07, 0.09, 0.22, 0.92)
const EDGE := Color(0.03, 0.04, 0.12)
const GOLD := Color(1.0, 0.87, 0.3)
const GOOD := "#7dff7d"
const BAD := "#ff7d7d"

static var _theme: Theme
static var _heart: Texture2D
static var _tips := {}   # id do item -> BBCode da dica


static func box(bg: Color, border := EDGE, width := 2, radius := 5) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(width)
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(6)
	return sb


static func theme() -> Theme:
	if _theme:
		return _theme
	_theme = Theme.new()
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Andy", "Ubuntu", "Liberation Sans", "DejaVu Sans"])
	font.font_weight = 700
	_theme.default_font = font
	_theme.default_font_size = 16
	for t in ["Label", "Button", "CheckBox", "LineEdit", "RichTextLabel"]:
		_theme.set_color("font_outline_color", t, EDGE)
		_theme.set_constant("outline_size", t, 4)
	_theme.set_color("default_color", "RichTextLabel", Color.WHITE)
	_theme.set_stylebox("normal", "Button", box(BLUE))
	_theme.set_stylebox("hover", "Button", box(BLUE_HOVER, GOLD))
	_theme.set_stylebox("pressed", "Button", box(BLUE.darkened(0.25), GOLD))
	_theme.set_stylebox("disabled", "Button", box(BLUE.darkened(0.4)))
	_theme.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	_theme.set_color("font_hover_color", "Button", GOLD)
	_theme.set_color("font_disabled_color", "Button", Color(1, 1, 1, 0.5))
	_theme.set_stylebox("panel", "PanelContainer", box(NAVY, EDGE, 3, 8))
	_theme.set_stylebox("panel", "TooltipPanel", box(NAVY, EDGE, 2, 6))
	_theme.set_stylebox("normal", "LineEdit", box(NAVY))
	_theme.set_stylebox("focus", "LineEdit", box(NAVY, GOLD))
	_theme.set_stylebox("fill", "ProgressBar", box(Color("#c62a2a"), Color("#ff9a8a"), 1, 3))
	_theme.set_stylebox("background", "ProgressBar", box(Color(0, 0, 0, 0.7), EDGE, 2, 3))
	var track := box(Color(0, 0, 0, 0.6), EDGE, 2, 3)   # controle deslizante do Configurações: trilho escuro, parte cheia dourada, puxador quadrado
	track.set_content_margin_all(5)
	_theme.set_stylebox("slider", "HSlider", track)
	_theme.set_stylebox("grabber_area", "HSlider", box(GOLD.darkened(0.4), EDGE, 2, 3))
	_theme.set_stylebox("grabber_area_highlight", "HSlider", box(GOLD.darkened(0.25), EDGE, 2, 3))
	_theme.set_icon("grabber", "HSlider", _knob(GOLD.darkened(0.1)))
	_theme.set_icon("grabber_highlight", "HSlider", _knob(GOLD))
	return _theme


# Puxador do controle deslizante: retângulo de borda escura.
static func _knob(color: Color) -> Texture2D:
	var img := Image.create(14, 26, false, Image.FORMAT_RGBA8)
	img.fill(EDGE)
	img.fill_rect(Rect2i(2, 2, 10, 22), color)
	return ImageTexture.create_from_image(img)


# Botão de menu como no Terraria: só o texto, que fica dourado sob o mouse.
static func menu_button(text: String, size := 30) -> Button:
	var b := Button.new()
	b.text = text
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_constant_override("outline_size", 6)
	for s in ["normal", "hover", "pressed", "disabled", "focus"]:
		b.add_theme_stylebox_override(s, StyleBoxEmpty.new())
	b.resized.connect(func(): b.pivot_offset = b.size / 2.0)
	var grow := func(to: float): if not b.disabled: b.create_tween().tween_property(b, "scale", Vector2.ONE * to, 0.1)
	b.mouse_entered.connect(grow.bind(1.14))   # cresce sob o mouse, como no Terraria
	b.mouse_exited.connect(grow.bind(1.0))
	return b


# Coração de vida: forma pela curva do coração (pixels grandes, como o sprite do Terraria), borda escura e brilho.
static func heart() -> Texture2D:
	if _heart:
		return _heart
	var s := 24
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	var inside := func(px: int, py: int) -> bool:
		if px < 0 or py < 0 or px >= s or py >= s:
			return false
		var x := (px + 0.5 - s / 2.0) / (s / 2.0) * 1.3
		var y := -(py + 0.5 - s / 2.0) / (s / 2.0) * 1.3 + 0.12
		var a := x * x + y * y - 1.0
		return a * a * a - x * x * y * y * y <= 0.0
	for py in s:
		for px in s:
			if not inside.call(px, py):
				continue
			var edge: bool = not (inside.call(px - 1, py) and inside.call(px + 1, py) and inside.call(px, py - 1) and inside.call(px, py + 1))
			var t := py / float(s)
			var c := Color("#ff5252").lerp(Color("#b81616"), t)
			if edge:
				c = Color("#3a0606")
			elif Vector2(px, py).distance_to(Vector2(s * 0.3, s * 0.32)) < 2.3:
				c = Color("#ffc4c4")   # brilho
			img.set_pixel(px, py, c)
	_heart = ImageTexture.create_from_image(img)
	return _heart


# Dica do item em BBCode: nome na cor da raridade e as estatísticas, como o balão do Terraria.
static func item_tip(id: int) -> String:
	if _tips.has(id):
		return _tips[id]
	var d: Dictionary = Items.defs[id]
	var lines := ["[color=#%s]%s[/color]" % [Items.rarity_color(id).to_html(false), Items.label(id).capitalize()]]
	if d.has("armor"):
		lines.append("%d de defesa" % d.defense)
	elif d.get("damage", 0) > 0 and not d.has("ammo_class"):
		lines.append("%d de dano" % d.damage)
		lines.append(_speed(d.get("use_time", 0.3)))
		lines.append(_knockback(d.get("knockback", 0.0)))
	elif d.has("ammo_class"):
		lines.append("%d de dano (munição)" % d.get("damage", 0))
	if d.has("accessory"):
		var a: Dictionary = d.accessory
		if a.has("speed"): lines.append("+%d%% de velocidade" % roundi(a.speed * 100))
		if a.has("jump"): lines.append("+%d%% de altura do pulo" % roundi(a.jump * 100))
		if a.has("regen"): lines.append("Regeneração de vida mais rápida")
		if a.has("wings"): lines.append("Permite voar e planar (%.2f s de voo)" % a.wings.time)
		if a.has("double_jump"): lines.append("Permite pular de novo no ar")
		if a.has("no_fall"): lines.append("Anula o dano de queda")
		if a.has("max_mana"): lines.append("+%d de mana máxima" % a.max_mana)
		if a.has("panic"): lines.append("Ao levar dano, dobra a velocidade por 8 s")
		if a.has("defense"): lines.append("+%d de defesa" % a.defense)
		lines.append("Acessório")
	if d.has("heal"):
		lines.append("Recupera %d de vida" % d.heal)
	if d.has("life"):
		lines.append("Aumenta a vida máxima em %d" % d.life)
	if d.has("buff"):
		lines.append(Buffs.defs[d.buff].tip)
		lines.append("Dura %d minutos" % roundi(d.buff_time / 60.0))
	if d.has("recall"):
		lines.append("Leva você para casa")
	if d.get("consumable", false):
		lines.append("Consumível")
	if Inventory.coin_kind(id) != -1:
		lines.append("Moeda")
	if Items.pick_power[id] > 0:
		lines.append("%d%% de poder de picareta" % Items.pick_power[id])
	if Items.axe_power[id] > 0:
		lines.append("%d%% de poder de machado" % Items.axe_power[id])
	if Items.hammer_power[id] > 0:
		lines.append("%d%% de poder de martelo" % Items.hammer_power[id])
	if d.has("bucket"):
		lines.append({"empty": "Botão esquerdo pega água ou lava", "water": "Botão esquerdo derrama a água", "lava": "Botão esquerdo derrama a lava"}[d.bucket])
	if d.has("summon"):
		lines.append("Invoca um chefe (só à noite)" if d.get("night", false) else "Invoca um chefe")
	if d.has("set"):
		lines.append("Conjunto: %s" % str(d.set))
		for w in Items.sets.get(d.set, {}).get("free_cost", []):
			lines.append("Conjunto completo: %s sem custo de mana" % Items.label(w).capitalize())
	if Items.places[id] != -1:
		lines.append("Pode ser colocado")
	_tips[id] = "\n".join(lines)
	return _tips[id]


# Velocidade de ataque pelos limites do Terraria (quadros de uso).
static func _speed(use_time: float) -> String:
	var f := use_time * 60.0
	return "Velocidade insana" if f <= 8 else "Velocidade muito rápida" if f <= 20 else "Velocidade rápida" if f <= 25 \
		else "Velocidade média" if f <= 30 else "Velocidade lenta" if f <= 35 else "Velocidade muito lenta" if f <= 45 \
		else "Velocidade extremamente lenta" if f <= 55 else "Velocidade de caracol"


static func _knockback(kb: float) -> String:
	return "Sem recuo" if kb <= 0 else "Recuo fraquíssimo" if kb <= 1.5 else "Recuo fraco" if kb <= 3 else "Recuo médio" if kb <= 4 \
		else "Recuo forte" if kb <= 6 else "Recuo fortíssimo" if kb <= 7 else "Recuo extremo" if kb <= 9 else "Recuo insano"
