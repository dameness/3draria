extends SceneTree
# Uso: .tools/godot --headless -s tests/atlas_preview.gd  → textures/preview.png (fora do git)
# Linha(s) de cima: faces de bloco do atlas. Abaixo: ícones de item como aparecem no jogo. Ampliado 6x.

const CELL := 34
const PER := 14


func _init() -> void:
	Blocks.load_pack()
	Items.load_pack()
	var atlas := Atlas.build(Blocks.textures)
	var faces: Array[Image] = []
	for k in Blocks.textures:
		var spec: Dictionary = Blocks.textures[k]
		if spec.has("crop") or (spec.has("pattern") and not spec.pattern in ["bar", "pickaxe", "sword", "bow", "arrow", "blob", "torch"]):
			faces.append(atlas.get_region(Rect2i(Blocks.textures.keys().find(k) * 16, 0, 16, 16)))
	var icons: Array[Image] = []
	var tex := ImageTexture.create_from_image(atlas)
	for id in Items.names.size():
		icons.append(Items.icon_texture(id, tex).get_image())
	var rows := ceili(faces.size() / float(PER)) + ceili(icons.size() / float(PER))
	var out := Image.create(PER * CELL, rows * CELL, false, Image.FORMAT_RGBA8)
	out.fill(Color(0.12, 0.12, 0.15))
	var i := 0
	for group in [faces, icons]:
		for img in group:
			img.convert(Image.FORMAT_RGBA8)
			if img.get_width() > 32 or img.get_height() > 32:
				var s := 32.0 / maxi(img.get_width(), img.get_height())
				img.resize(int(img.get_width() * s), int(img.get_height() * s), Image.INTERPOLATE_NEAREST)
			var at := Vector2i((i % PER) * CELL + (CELL - img.get_width()) / 2, (i / PER) * CELL + (CELL - img.get_height()) / 2)
			out.blend_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), at)
			i += 1
		i = ceili(i / float(PER)) * PER  # grupo novo começa em linha nova
	out.resize(out.get_width() * 6, out.get_height() * 6, Image.INTERPOLATE_NEAREST)
	DirAccess.make_dir_recursive_absolute("res://textures")
	out.save_png("res://textures/preview.png")
	quit()
