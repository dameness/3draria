class_name Minimap
extends Control
# Mapa de exploração (docs/UI.md; wiki Minimap): 1 pixel = 1 bloco do mundo inteiro, origem fixa em (0,0), norte (−Z) para cima.
# O jogador revela uma faixa em volta dele (a imagem mora em world.map_img e vai no save) e o que já foi visto continua.
# Tab troca o estilo (retrato no canto, sobreposição, oculto), M abre o mapa cheio e +/- dá zoom no retrato. A janela é recortada em
# pixels inteiros em volta do jogador e a seta só gira: como a imagem tem origem fixa, nada "teleporta".

const REVEAL := 56          # raio revelado em volta do jogador, em blocos (passa da janela do retrato)
const ROWS_PER_FRAME := 2
const PORTRAIT := 160       # lado do retrato, em pixels
const ZOOMS := [1.0, 2.0, 4.0]   # pixels por bloco no retrato: 160, 80 e 40 blocos de lado
const OVERLAY_SCALE := 3.0
enum {STYLE_PORTRAIT, STYLE_OVERLAY, STYLE_HIDDEN}

var world: Node3D
var player: Node3D
var tex: ImageTexture
var top := PackedByteArray()   # altura do topo de cada coluna na última leitura: a próxima começa perto dela
var style := STYLE_PORTRAIT
var corner_y := 74.0        # onde o retrato começa (a HUD desce quando a vida ocupa duas fileiras de corações)
var full := false
var zoom := 1
var row := 0
var frame: Panel


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	top.resize(WorldGen.SIZE * WorldGen.SIZE)


func setup(w: Node3D, p: Node3D) -> void:
	world = w
	player = p
	tex = ImageTexture.create_from_image(world.map_img)
	frame = Panel.new()   # moldura do retrato
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.offset_left = -3
	frame.offset_top = -3
	frame.offset_right = 3
	frame.offset_bottom = 3
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_theme_stylebox_override("panel", Ui.box(Color.TRANSPARENT, Ui.EDGE, 3, 4))
	add_child(frame)
	_layout()


# Retrato: canto superior direito, abaixo da vida. Sobreposição e mapa cheio: a tela toda (a sobreposição é translúcida).
func _layout() -> void:
	var corner := style == STYLE_PORTRAIT and not full
	anchor_left = 1.0 if corner else 0.0
	anchor_right = 1.0
	anchor_top = 0.0
	anchor_bottom = 0.0 if corner else 1.0
	offset_left = -PORTRAIT - 44.0 if corner else 0.0
	offset_right = -44.0 if corner else 0.0
	offset_top = corner_y if corner else 0.0
	offset_bottom = corner_y + PORTRAIT if corner else 0.0
	modulate.a = 0.6 if style == STYLE_OVERLAY and not full else 1.0
	visible = style != STYLE_HIDDEN or full
	frame.visible = corner
	if player:
		player.map_open = full


func _unhandled_input(e: InputEvent) -> void:
	if world == null or not (e is InputEventKey and e.pressed and not e.echo):
		return
	if e.physical_keycode == KEY_TAB and not full:
		style = (style + 1) % 3
	elif e.physical_keycode == KEY_M:
		full = not full
	elif e.physical_keycode == KEY_ESCAPE and full:
		full = false
	elif e.keycode in [KEY_EQUAL, KEY_PLUS, KEY_KP_ADD] and style == STYLE_PORTRAIT:
		zoom = mini(zoom + 1, ZOOMS.size() - 1)
	elif e.keycode in [KEY_MINUS, KEY_KP_SUBTRACT] and style == STYLE_PORTRAIT:
		zoom = maxi(zoom - 1, 0)
	else:
		return
	accept_event()
	_layout()


func _process(_delta: float) -> void:
	if world == null:
		return
	_reveal()
	if visible:
		queue_redraw()


# Lê poucas linhas por quadro da faixa em volta do jogador e as grava na imagem do mundo (o que sai da faixa fica como estava).
func _reveal() -> void:
	var x0 := clampi(floori(player.position.x) - REVEAL, 0, WorldGen.SIZE)
	var x1 := clampi(floori(player.position.x) + REVEAL, 0, WorldGen.SIZE)
	var z0 := clampi(floori(player.position.z) - REVEAL, 0, WorldGen.SIZE)
	var z1 := clampi(floori(player.position.z) + REVEAL, 0, WorldGen.SIZE)
	for i in ROWS_PER_FRAME:
		if row < z0 or row >= z1:
			row = z0
		for x in range(x0, x1):
			var c := _column(x, row)
			if c.a > 0.0:
				world.map_img.set_pixel(x, row, c)
		row += 1
	if Engine.get_process_frames() % 3 == 0:   # 256 KB de imagem: sobe para a GPU 20 vezes por segundo, não 60
		tex.update(world.map_img)


# Cor do topo da coluna (x, z): o primeiro bloco sólido ou líquido de cima para baixo (mais claro quanto mais alto);
# transparente se o chunk ainda não existe (tenta de novo na próxima volta).
func _column(x: int, z: int) -> Color:
	var c := Vector2i(x / WorldGen.CHUNK, z / WorldGen.CHUNK)
	if not world.chunks.has(c):
		return Color(0, 0, 0, 0)
	var data: PackedByteArray = world.chunks[c]
	var base := x % WorldGen.CHUNK + z % WorldGen.CHUNK * WorldGen.CHUNK
	var i := x + z * WorldGen.SIZE
	var y := mini(top[i] + 3, WorldGen.HEIGHT - 1) if top[i] > 0 else WorldGen.HEIGHT - 1   # ponytail: obra que sobe >3 blocos aparece em algumas voltas
	while y > 0:
		var id: int = data[base + y * WorldGen.CHUNK * WorldGen.CHUNK]
		if id != 0 and (Blocks.solid[id] or Blocks.liquid[id]):
			top[i] = y
			return color_of(id, y)
		y -= 1
	return Color(0.1, 0.12, 0.2)


static func color_of(id: int, y: int) -> Color:
	var t := Blocks.tiles[id * Blocks.FACES + 2]
	var col: Color = Blocks.tile_colors[t] if t < Blocks.tile_colors.size() else Color(0.6, 0.6, 0.6)
	return col.darkened(clampf((WorldGen.ROCK_LINE - y) * 0.006, 0.0, 0.4))


# Janela mostrada: [bloco do canto (0,0) da tela, pixels por bloco]. Retrato e sobreposição seguem o jogador; o mapa cheio mostra o mundo.
func view() -> Array:
	var s: float = ZOOMS[zoom] if style == STYLE_PORTRAIT else OVERLAY_SCALE
	var center := Vector2(player.position.x, player.position.z)
	if full:
		s = minf(size.x, size.y) * 0.92 / WorldGen.SIZE
		center = Vector2(WorldGen.SIZE, WorldGen.SIZE) / 2.0
	return [(center * s).round() / s - size / (2.0 * s), s]   # centro em pixels inteiros: as bordas dos blocos ficam nítidas


# Posição na tela (em pixels do controle) do ponto do mundo `block` (x, z).
func to_view(block: Vector2) -> Vector2:
	var v := view()
	return (block - v[0]) * v[1]


func _draw() -> void:
	var v := view()
	var o: Vector2 = v[0]
	var s: float = v[1]
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.03, 0.04, 0.09, 1.0 if full else 0.6))
	var seen := Rect2(o, size / s).intersection(Rect2(0, 0, WorldGen.SIZE, WorldGen.SIZE))
	if seen.has_area():
		draw_texture_rect_region(tex, Rect2((seen.position - o) * s, seen.size * s), seen)
	var sp := to_view(Vector2(player.spawn.x, player.spawn.z))   # o spawn: quadradinho dourado
	draw_rect(Rect2(sp - Vector2(3, 3), Vector2(6, 6)), Ui.GOLD)
	draw_rect(Rect2(sp - Vector2(3, 3), Vector2(6, 6)), Ui.EDGE, false, 1.0)
	if player.death != Vector3.INF:   # onde você morreu por último: um X vermelho
		var d := to_view(Vector2(player.death.x, player.death.z))
		for k in [1, -1]:
			draw_line(d + Vector2(-4, -4 * k), d + Vector2(4, 4 * k), Color("#e03030"), 2.0)
	if player.entities and player.entities.boss:   # chefe: bolinha vermelha
		var b := to_view(Vector2(player.entities.boss.position.x, player.entities.boss.position.z))
		draw_circle(b, 4.0, Color("#ff3030"))
		draw_arc(b, 4.0, 0.0, TAU, 12, Ui.EDGE, 1.5)
	draw_set_transform(to_view(Vector2(player.position.x, player.position.z)), -player.rotation.y)   # a seta só gira
	var arrow := PackedVector2Array([Vector2(0, -8), Vector2(6, 6), Vector2(0, 3), Vector2(-6, 6)])
	draw_colored_polygon(arrow, Color.WHITE)
	draw_polyline(arrow + PackedVector2Array([arrow[0]]), Ui.EDGE, 2.0)
	draw_set_transform(Vector2.ZERO)
