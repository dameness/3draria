class_name Minimap
extends Control
# Minimapa do canto superior direito (spec em docs/UI.md): vista de cima em volta do jogador, 1 pixel = 1 bloco, norte para cima,
# com a seta do jogador. Atualiza poucas linhas por quadro para não pesar; só lê chunks já gerados.

const SIZE := 80          # pixels = blocos de lado (±40 em volta do jogador)
const ROWS_PER_FRAME := 2
const SCAN_UP := 20       # começa a procurar o chão tantos blocos acima dos pés
const SCAN_DOWN := 40

var world: Node3D
var player: Node3D
var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
var tex := ImageTexture.create_from_image(img)
var row := 0
var origin := Vector2i.ZERO   # bloco do canto (0,0) do mapa neste ciclo
var ring: Control
var arrow: Control


func _init() -> void:
	custom_minimum_size = Vector2(SIZE * 2, SIZE * 2)
	size = custom_minimum_size
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	img.fill(Color(0, 0, 0, 0.45))


func _process(_delta: float) -> void:
	if world == null or not is_visible_in_tree():
		return
	if row == 0:
		origin = Vector2i(floori(player.position.x), floori(player.position.z)) - Vector2i(SIZE, SIZE) / 2
	var py := floori(player.position.y)
	for r in ROWS_PER_FRAME:
		for x in SIZE:
			img.set_pixel(x, row, _column(origin.x + x, origin.y + row, py))
		row += 1
		if row >= SIZE:
			row = 0
			tex.update(img)
			break
	arrow.rotation = -player.rotation.y
	arrow.position = size / 2.0 + Vector2(player.position.x - origin.x - SIZE / 2.0, player.position.z - origin.y - SIZE / 2.0) * 2.0


# Cor da coluna (x, z): o primeiro bloco visível de cima para baixo a partir de py+SCAN_UP, sombreado pela altura.
func _column(x: int, z: int, py: int) -> Color:
	var c := Vector2i(floori(x / float(WorldGen.CHUNK)), floori(z / float(WorldGen.CHUNK)))
	if not world.chunks.has(c):
		return Color(0, 0, 0, 0.45)
	var data: PackedByteArray = world.chunks[c]
	var base: int = posmod(x, WorldGen.CHUNK) + posmod(z, WorldGen.CHUNK) * WorldGen.CHUNK
	var top := mini(py + SCAN_UP, WorldGen.HEIGHT - 1)
	for y in range(top, maxi(py - SCAN_DOWN, 0), -1):
		var id: int = data[base + y * WorldGen.CHUNK * WorldGen.CHUNK]
		if id != 0 and (Blocks.solid[id] or Blocks.liquid[id]):
			var col: Color = Blocks.tile_colors[Blocks.tiles[id * Blocks.FACES + 2]]
			return col.darkened(clampf((top - y) / 60.0, 0.0, 0.5))
	return Color(0.1, 0.12, 0.2, 0.7)


func _draw() -> void:
	draw_texture_rect(tex, Rect2(Vector2.ZERO, size), false)


func setup(w: Node3D, p: Node3D) -> void:
	world = w
	player = p
	tex.update(img)
	arrow = Control.new()
	arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	arrow.draw.connect(func():
		arrow.draw_colored_polygon(PackedVector2Array([Vector2(0, -8), Vector2(6, 6), Vector2(0, 3), Vector2(-6, 6)]), Color.WHITE)
		arrow.draw_polyline(PackedVector2Array([Vector2(0, -8), Vector2(6, 6), Vector2(0, 3), Vector2(-6, 6), Vector2(0, -8)]), Ui.EDGE, 2.0))
	add_child(arrow)
