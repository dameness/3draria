class_name Atlas
# Gera o atlas de texturas 16x16 (uma fileira de tiles) a partir de textures.json.

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
	var colors: Array = spec.colors
	var top: Array = spec.get("top_colors", colors)
	for x in TILE:
		var edge := 3 + rng.randi() % 3  # borda irregular do "grass_side"
		for y in TILE:
			var pal := top if spec.pattern == "grass_side" and y < edge else colors
			img.set_pixel(ox + x, y, Color(pal[rng.randi() % pal.size()]))
