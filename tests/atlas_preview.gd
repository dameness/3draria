extends SceneTree
# Uso: .tools/godot --headless -s tests/atlas_preview.gd  → docs/atlas.png
# Atlas ampliado 8x com o nome de cada tile (em ordem) impresso no terminal.
func _init():
	Blocks.load_pack()
	var img := Atlas.build(Blocks.textures)
	var bg := Image.create(img.get_width(), 16, false, Image.FORMAT_RGBA8)
	bg.fill(Color(0.2, 0.22, 0.28))
	bg.blend_rect(img, Rect2i(0, 0, img.get_width(), 16), Vector2i.ZERO)
	# quebra em 2 linhas para caber na tela
	var per := 12
	var rows := ceili(Blocks.textures.size() / float(per))
	var out := Image.create(per * 16 + (per - 1) * 2, rows * 18, false, Image.FORMAT_RGBA8)
	out.fill(Color(0.12, 0.12, 0.15))
	for i in Blocks.textures.size():
		out.blit_rect(bg, Rect2i(i * 16, 0, 16, 16), Vector2i((i % per) * 18, (i / per) * 18))
	out.resize(out.get_width() * 8, out.get_height() * 8, Image.INTERPOLATE_NEAREST)
	out.save_png("res://docs/atlas.png")
	var names := Blocks.textures.keys()
	for r in rows: print("linha %d: %s" % [r + 1, ", ".join(names.slice(r * per, r * per + per))])
	quit()
