extends SceneTree
# Uso: .tools/godot --headless -s tests/model_preview.gd [item ...]  → textures/item_models.png
# Rasterizador de CPU (ortográfico, z-buffer) para ver os modelos 3D dos itens sem GPU (sessão remota).
const SIZE := 360
func render(mesh: ArrayMesh, tex: Image, basis: Basis) -> Image:
	var out := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	out.fill(Color(0.15, 0.16, 0.2))
	var zb := PackedFloat32Array(); zb.resize(SIZE * SIZE); zb.fill(-1e9)
	var a := mesh.surface_get_arrays(0)
	var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var uv: PackedVector2Array = a[Mesh.ARRAY_TEX_UV]
	var col: PackedColorArray = a[Mesh.ARRAY_COLOR]
	var ix: PackedInt32Array = a[Mesh.ARRAY_INDEX]
	var c := mesh.get_aabb().get_center()
	var sc := SIZE * 0.8 / mesh.get_aabb().size.length()
	var light := Vector3(0.4, 0.8, 0.6).normalized()
	for t in range(0, ix.size(), 3):
		var p := []
		for k in 3:
			var q: Vector3 = basis * (v[ix[t + k]] - c)
			p.append(Vector3(SIZE / 2 + q.x * sc, SIZE / 2 - q.y * sc, q.z))
		var n: Vector3 = basis * a[Mesh.ARRAY_NORMAL][ix[t]]
		if n.z < 0: continue
		var lo := Vector2(min(p[0].x, p[1].x, p[2].x), min(p[0].y, p[1].y, p[2].y)).floor()
		var hi := Vector2(max(p[0].x, p[1].x, p[2].x), max(p[0].y, p[1].y, p[2].y)).ceil()
		var area: float = (p[1].x - p[0].x) * (p[2].y - p[0].y) - (p[2].x - p[0].x) * (p[1].y - p[0].y)
		if absf(area) < 1e-6: continue
		for y in range(maxi(0, lo.y), mini(SIZE, hi.y + 1)):
			for x in range(maxi(0, lo.x), mini(SIZE, hi.x + 1)):
				var w0: float = ((p[1].x - x) * (p[2].y - y) - (p[2].x - x) * (p[1].y - y)) / area
				var w1: float = ((p[2].x - x) * (p[0].y - y) - (p[0].x - x) * (p[2].y - y)) / area
				var w2: float = 1.0 - w0 - w1
				if w0 < 0 or w1 < 0 or w2 < 0: continue
				var z: float = w0 * p[0].z + w1 * p[1].z + w2 * p[2].z
				if z <= zb[y * SIZE + x]: continue
				var u: Vector2 = uv[ix[t]] * w0 + uv[ix[t + 1]] * w1 + uv[ix[t + 2]] * w2
				var px := tex.get_pixel(clampi(int(u.x * tex.get_width()), 0, tex.get_width() - 1), clampi(int(u.y * tex.get_height()), 0, tex.get_height() - 1))
				if px.a < 0.5: continue
				zb[y * SIZE + x] = z
				var sh: float = col[ix[t]].r * (0.75 + 0.25 * maxf(n.dot(light), 0))
				out.set_pixel(x, y, Color(px.r * sh, px.g * sh, px.b * sh))
	return out
func _init():
	Blocks.load_pack(); Items.load_pack()
	var atlas := ImageTexture.create_from_image(Atlas.build(Blocks.textures))
	var names: Array = Array(OS.get_cmdline_user_args())
	if names.is_empty():
		names = ["copper_pickaxe", "wooden_sword", "wooden_bow", "dirt"]
	var sheet := Image.create(SIZE * names.size(), SIZE, false, Image.FORMAT_RGBA8)
	for i in names.size():
		var img := Items.icon_texture(Items.ids[names[i]], atlas).get_image()
		img.convert(Image.FORMAT_RGBA8)
		var mesh := ItemModel.build(img, 1.0)
		sheet.blit_rect(render(mesh, img, Basis(Vector3.RIGHT, deg_to_rad(15)) * Basis(Vector3.UP, deg_to_rad(-40))), Rect2i(0, 0, SIZE, SIZE), Vector2i(i * SIZE, 0))
	DirAccess.make_dir_recursive_absolute("res://textures")
	sheet.save_png("res://textures/item_models.png")
	quit()
