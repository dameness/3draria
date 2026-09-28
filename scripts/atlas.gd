class_name Atlas
# Gera o atlas de texturas 16x16 (uma fileira de tiles) a partir de textures.json.
# Padrões: noise, grass_side, stripes, rings, ore, planks, bricks (blocos); bar, pickaxe (ícones, fundo transparente).

const TILE := 16


static func build(textures: Dictionary) -> Image:
	var img := Image.create(TILE * textures.size(), TILE, false, Image.FORMAT_RGBA8)
	var i := 0
	for name in textures:
		_paint(img, i * TILE, textures[name], hash(name))
		i += 1
	return img


static func _paint(img: Image, ox: int, spec: Dictionary, seed: int) -> void:
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
			for i in 9:
				set_px.call(2 + i, 13 - i, top[0])
			for t in range(-3, 4):
				set_px.call(11 + t, 4 + t, cols[0])
				set_px.call(11 + t, 3 + t, cols[1])
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
