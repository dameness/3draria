class_name Atlas
# Gera o atlas de texturas 16x16 (uma fileira de tiles) a partir de textures.json.
# Padrões: noise, grass_side, stripes, rings, ore, planks, bricks (blocos);
# bar, pickaxe, sword, bow, arrow, blob, torch (ícones, fundo transparente).

const TILE := 16

static var wiki_dir := "res://assets/wiki/"   # sprites baixados por scripts/fetch-sprites.sh


static var texture_cache := {}


# Textura para interface/sprites: imagem da wiki inteira (sem crop), senão o tile `fallback` do atlas.
static func texture(name: String, fallback: int, atlas: Texture2D) -> Texture2D:
	if not texture_cache.has(name + str(fallback)):
		var spec: Dictionary = Blocks.textures.get(name, {})
		var wiki := wiki_image(spec)
		var t: Texture2D
		if wiki and not spec.has("crop"):
			t = ImageTexture.create_from_image(wiki)
		else:
			t = AtlasTexture.new()
			t.atlas = atlas
			t.region = Rect2(fallback * TILE, 0, TILE, TILE)
		texture_cache[name + str(fallback)] = t
	return texture_cache[name + str(fallback)]


# Sprite da wiki para a textura, ou null se não foi baixado (aí vale o procedural).
static func wiki_image(spec: Dictionary) -> Image:
	if not spec.has("wiki"):
		return null
	var path := ProjectSettings.globalize_path(wiki_dir + spec.wiki + ".png")
	if not FileAccess.file_exists(path):
		return null
	var img := Image.load_from_file(path)
	if img:
		img.convert(Image.FORMAT_RGBA8)
	return img


static func build(textures: Dictionary) -> Image:
	var img := Image.create(TILE * textures.size(), TILE, false, Image.FORMAT_RGBA8)
	var i := 0
	for name in textures:
		_paint(img, i * TILE, textures[name], hash(name))
		i += 1
	return img


static func _paint(img: Image, ox: int, spec: Dictionary, seed: int) -> void:
	var wiki := wiki_image(spec)
	if wiki and spec.has("crop"):
		img.blit_rect(wiki, Rect2i(spec.crop[0], spec.crop[1], TILE, TILE), Vector2i(ox, 0))
		return
	if not spec.has("pattern"):
		return  # entrada só de ícone da wiki; não ocupa pixels no atlas
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var cols: Array = spec.colors.map(func(c): return Color(c))
	var top: Array = spec.get("top_colors", spec.colors).map(func(c): return Color(c))
	var pick := func(pal: Array) -> Color: return pal[rng.randi() % pal.size()]
	var set_px := func(x: int, y: int, c: Color) -> void: img.set_pixel(ox + x, y, c)
	match spec.pattern:
		"bar":
			for y in range(6, 12):
				for x in range(3 if y > 6 else 4, 13 if y > 6 else 12):
					set_px.call(x, y, cols[2] if y == 6 else cols[1] if y == 11 else cols[0])
		"pickaxe":
			for i in 10:
				set_px.call(2 + i, 13 - i, top[0])  # cabo na diagonal
			# cabeça em arco, perpendicular ao cabo, com borda interna mais escura
			for p in [Vector2i(3, 3), Vector2i(4, 2), Vector2i(5, 1), Vector2i(6, 1), Vector2i(7, 1), Vector2i(8, 1), Vector2i(9, 2), Vector2i(10, 2),
					Vector2i(11, 3), Vector2i(12, 4), Vector2i(13, 5), Vector2i(13, 6), Vector2i(14, 7), Vector2i(14, 8), Vector2i(14, 9), Vector2i(14, 10), Vector2i(13, 11)]:
				set_px.call(p.x, p.y, cols[0])
				if p.y < 12 and p.x > 3:
					set_px.call(p.x - 1, p.y + 1, cols[1])
		"sword":
			for i in 9:
				set_px.call(5 + i, 10 - i, cols[0])
				set_px.call(6 + i, 10 - i, cols[1])
			for i in 5:
				set_px.call(2 + i, 8 + i, top[0])  # guarda
			for i in 3:
				set_px.call(2 + i, 13 - i, top[0])  # cabo
		"bow":
			for y in range(2, 14):
				var dx := int(round(4.0 * sin(PI * (y - 2) / 11.0)))
				set_px.call(4 + dx, y, cols[0])
				set_px.call(5 + dx, y, cols[1])
				set_px.call(4, y, top[0])  # corda
		"arrow":
			for i in 10:
				set_px.call(3 + i, 12 - i, cols[0])
			for p in [Vector2i(12, 2), Vector2i(13, 2), Vector2i(12, 3), Vector2i(11, 2), Vector2i(13, 4)]:
				set_px.call(p.x, p.y, cols[1])
			for p in [Vector2i(2, 12), Vector2i(3, 13), Vector2i(2, 13)]:
				set_px.call(p.x, p.y, top[0])
		"blob":
			for y in TILE:
				for x in TILE:
					var r := Vector2(x - 7.5, (y - 8.5) * 1.2).length()
					if r < 5.5:
						set_px.call(x, y, cols[2] if x < 6 and y < 7 else cols[0] if r < 4.5 else cols[1])
			if spec.has("top_colors"):
				for p in [Vector2i(7, 8), Vector2i(8, 8), Vector2i(7, 9), Vector2i(8, 9)]:
					set_px.call(p.x, p.y, top[0])  # pupila da lente
		"torch":
			for y in range(6, 15):
				set_px.call(7, y, top[0])
				set_px.call(8, y, top[0])
			for p in [Vector2i(7, 3), Vector2i(8, 3), Vector2i(7, 4), Vector2i(8, 4), Vector2i(7, 5), Vector2i(8, 5), Vector2i(6, 4), Vector2i(9, 4), Vector2i(7, 2)]:
				set_px.call(p.x, p.y, cols[0] if p.y < 4 else cols[1])
		_:
			for x in TILE:
				var edge := 3 + rng.randi() % 3  # borda irregular do grass_side
				for y in TILE:
					var c: Color = pick.call(cols)
					match spec.pattern:
						"grass_side":
							if y < edge:
								c = pick.call(top)
						"stripes":
							c = cols[1] if (x + rng.randi() % 2) % 4 == 0 else c
						"rings":
							var r := Vector2(x - 7.5, y - 7.5).length()
							c = cols[int(r) % 2] if r < 7.0 else cols[1].darkened(0.4)
						"planks":
							c = cols[1].darkened(0.3) if y % 4 == 3 or (x + (y / 4) * 5) % 11 == 0 else c
						"bricks":
							c = top[0] if y % 4 == 3 or (x + (y / 4 % 2) * 4) % 8 == 7 else c
					set_px.call(x, y, c)
			if spec.pattern == "ore":
				for n in 5:
					var cx := 1 + rng.randi() % 13
					var cy := 1 + rng.randi() % 13
					for p in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
						if rng.randf() < 0.85:
							set_px.call(cx + p.x, cy + p.y, pick.call(top))
