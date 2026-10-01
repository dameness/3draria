extends SceneTree
# Folha de modelos voxel (sem GPU): cada linha = o sprite da wiki + o modelo em 4 ângulos (frente, lado, 3/4, costas).
# Uso: .tools/godot --headless -s tests/model_preview.gd [-- alvo ...]  → textures/model_sheet.png
# Alvos: nome de item (copper_pickaxe), `block:living_loom`, `body`, `armor:molten` (corpo vestido com o conjunto); `@2` no fim aproxima
# a parte de cima (ex.: `armor:molten@2`). Sem alvo: os pilotos.
# Antes de desenhar, refaz os .vox derivados (scripts/voxel/build.gd), então a folha mostra o que o jogo carregaria.
# Rasterizador de CPU ortográfico com z-buffer; emissivo (alfa 0) sai mais claro e sem sombra.
const SIZE := 400
const LIGHT := Vector3(0.4, 0.8, 0.6)


# [[malha, Transform3D]] → imagem; yaw gira o conjunto em volta de Y; front_yaw = PI para o que olha para -Z (personagem).
func render(parts: Array, yaw: float, zoom := 1.0) -> Image:
	var out := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	out.fill(Color(0.15, 0.16, 0.2))
	var zb := PackedFloat32Array()
	zb.resize(SIZE * SIZE)
	zb.fill(-1e9)
	var spin := Basis(Vector3.RIGHT, deg_to_rad(12)) * Basis(Vector3.UP, yaw)
	var box := AABB()
	var first := true
	for p in parts:
		var bb: AABB = p[1] * p[0].get_aabb()
		box = bb if first else box.merge(bb)
		first = false
	var c := box.get_center()
	var sc := SIZE * 0.86 / maxf(box.size.y, maxf(box.size.x, box.size.z) * 0.9) * zoom
	if zoom > 1.0:
		c.y = box.position.y + box.size.y * 0.72   # zoom: foca na parte de cima (cabeça e tronco)
	var lit := LIGHT.normalized()
	for p in parts:
		if p[0].get_surface_count() == 0:
			continue
		var a: Array = p[0].surface_get_arrays(0)
		var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var nr: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
		var col: PackedColorArray = a[Mesh.ARRAY_COLOR]
		var ix: PackedInt32Array = a[Mesh.ARRAY_INDEX]
		var xf: Transform3D = p[1]
		for t in range(0, ix.size(), 3):
			var q := []
			for k in 3:
				var w: Vector3 = spin * (xf * v[ix[t + k]] - c)
				q.append(Vector3(SIZE / 2 + w.x * sc, SIZE / 2 - w.y * sc, w.z))
			var n: Vector3 = spin * (xf.basis * nr[ix[t]])
			if n.z <= 0:
				continue
			var area: float = (q[1].x - q[0].x) * (q[2].y - q[0].y) - (q[2].x - q[0].x) * (q[1].y - q[0].y)
			if absf(area) < 1e-6:
				continue
			var lo := Vector2(minf(q[0].x, minf(q[1].x, q[2].x)), minf(q[0].y, minf(q[1].y, q[2].y))).floor()
			var hi := Vector2(maxf(q[0].x, maxf(q[1].x, q[2].x)), maxf(q[0].y, maxf(q[1].y, q[2].y))).ceil()
			var shade: float = 0.72 + 0.28 * maxf(n.dot(lit), 0.0)
			for y in range(maxi(0, lo.y), mini(SIZE, hi.y + 1)):
				for x in range(maxi(0, lo.x), mini(SIZE, hi.x + 1)):
					var w0: float = ((q[1].x - x) * (q[2].y - y) - (q[2].x - x) * (q[1].y - y)) / area
					var w1: float = ((q[2].x - x) * (q[0].y - y) - (q[0].x - x) * (q[2].y - y)) / area
					var w2: float = 1.0 - w0 - w1
					if w0 < 0 or w1 < 0 or w2 < 0:
						continue
					var z: float = w0 * q[0].z + w1 * q[1].z + w2 * q[2].z
					if z <= zb[y * SIZE + x]:
						continue
					zb[y * SIZE + x] = z
					var cc: Color = col[ix[t]] * w0 + col[ix[t + 1]] * w1 + col[ix[t + 2]] * w2
					out.set_pixel(x, y, Color(minf(cc.r * 1.15, 1), minf(cc.g * 1.15, 1), minf(cc.b * 1.15, 1)) if col[ix[t]].a < 0.5 else Color(cc.r * shade, cc.g * shade, cc.b * shade))
	return out


func sprite_panel(img: Image) -> Image:
	var out := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	out.fill(Color(0.3, 0.3, 0.35))
	if img == null:
		return out
	img = img.duplicate()
	img.convert(Image.FORMAT_RGBA8)
	var k := maxi(1, mini(SIZE / img.get_width(), SIZE / img.get_height()))
	img.resize(img.get_width() * k, img.get_height() * k, Image.INTERPOLATE_NEAREST)
	out.blend_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), (Vector2i(SIZE, SIZE) - img.get_size()) / 2)
	return out


# Corpo nu ou vestido: as peças nos pivôs do player_model (VoxRecipes.PIV), cores do personagem padrão.
func figure(set := "") -> Array:
	var look := {"skin": Color(VoxRecipes.LOOK.skin), "hair": Color(VoxRecipes.LOOK.hair), "shirt": Color(VoxRecipes.LOOK.shirt), "pants": Color(VoxRecipes.LOOK.pants)}
	var up: Vector3 = VoxRecipes.PIV.upper
	var list := []
	var shell := func(part: String, at: Vector3):
		var m := VoxRecipes.part_mesh(set, part)
		if m:
			list.append([m, Transform3D(Basis(), at)])
	var put := func(part: String, at: Vector3):
		list.append([VoxRecipes.part_mesh("body", part, look), Transform3D(Basis(), at)])
	var head_at: Vector3 = up + VoxRecipes.PIV.head
	put.call("torso", up)
	put.call("head", head_at)
	if set == "" or Items.sets.get(set, {}).get("model", "") == "":   # sem casca: o cabelo aparece
		put.call("hair", head_at)
	for e in [["eye_l", VoxRecipes.EYE_L], ["eye_r", VoxRecipes.EYE_R]]:
		put.call(e[0], head_at + VoxRecipes.pivot_pos(e[1]))
	for side in [-1, 1]:
		put.call("arm", up + Vector3(side * VoxRecipes.PIV.arm.x, VoxRecipes.PIV.arm.y, 0))
		put.call("leg", Vector3(side * VoxRecipes.PIV.leg.x, VoxRecipes.PIV.leg.y, 0))
	if set != "":
		shell.call("head", head_at)
		shell.call("body", up)
		for side in [-1, 1]:
			shell.call("arm", up + Vector3(side * VoxRecipes.PIV.arm.x, VoxRecipes.PIV.arm.y, 0))
			shell.call("leg", Vector3(side * VoxRecipes.PIV.leg.x, VoxRecipes.PIV.leg.y, 0))
	return list


# Malhas de uma árvore de nós sem cena: [[malha, transformação acumulada]].
func _collect(node: Node, xf: Transform3D) -> Array:
	var out := []
	var t: Transform3D = xf * (node.transform if node is Node3D else Transform3D())
	if node is MeshInstance3D and node.mesh != null:
		out.append([node.mesh, t])
	for c in node.get_children():
		out.append_array(_collect(c, t))
	return out


func _init() -> void:
	Blocks.load_pack()
	Items.load_pack()
	VoxRecipes.clear_cache()
	load("res://scripts/voxel/build.gd").run()
	VoxRecipes.clear_cache()
	var atlas := ImageTexture.create_from_image(Atlas.build(Blocks.textures))
	var names: Array = Array(OS.get_cmdline_user_args())
	if names.is_empty():
		names = ["block:living_loom", "body", "armor:molten", "armor:molten@1.6", "copper_pickaxe", "terra_blade"]
	var rows := []
	for target in names:
		var n: String = target.get_slice("@", 0)
		var row := {"sprite": null, "parts": [], "front": PI, "zoom": float(target.get_slice("@", 1)) if "@" in target else 1.0}
		if n.begins_with("block:"):
			var spec: Dictionary = VoxRecipes.specs().get(n.substr(6), {})
			var tiles := Vector2(3, 3)
			var b: int = Blocks.ids[n.substr(6)]
			tiles = Blocks.model_size[b] if Blocks.model_size[b] != Vector2.ZERO else tiles
			row.sprite = VoxRecipes.sprite(spec.get("wiki", ""))
			row.parts = [[VoxRecipes.block_mesh(Blocks.model[b], tiles), Transform3D()]]
		elif n.begins_with("enemy:"):   # inimigo de sprite (EnemyModel); wing: bate as asas no tempo `@` não se aplica
			var def: Dictionary = {}
			for e in Blocks.read("res://data/base/enemies.json"):
				if e.name == n.substr(6):
					def = e
			var root := EnemyModel.build(def)
			row.sprite = Atlas.wiki_image(Blocks.textures.get(def.get("sprite", def.name), {}))
			row.parts = _collect(root, Transform3D())
			row.front = 0.0
		elif n == "body":
			row.parts = figure()
		elif n.begins_with("armor:"):
			row.sprite = VoxRecipes.sprite(VoxRecipes.specs().get(n.substr(6), {}).get("wiki", ""))
			row.parts = figure(n.substr(6))
		else:
			var id: int = Items.ids[n]
			var img := Items.icon_texture(id, atlas).get_image()
			img.convert(Image.FORMAT_RGBA8)
			row.sprite = img
			row.parts = [[VoxRecipes.item_mesh(Items.defs[id].get("model", n), img, 1.0), Transform3D()]]
			row.front = 0.0
		rows.append(row)
	var sheet := Image.create(SIZE * 5, SIZE * rows.size(), false, Image.FORMAT_RGBA8)
	for i in rows.size():
		var r: Dictionary = rows[i]
		sheet.blit_rect(sprite_panel(r.sprite), Rect2i(0, 0, SIZE, SIZE), Vector2i(0, i * SIZE))
		for a in 4:
			var yaw: float = r.front + [0.0, -PI / 2, -0.6, PI][a]
			sheet.blit_rect(render(r.parts, yaw, r.zoom), Rect2i(0, 0, SIZE, SIZE), Vector2i((a + 1) * SIZE, i * SIZE))
	DirAccess.make_dir_recursive_absolute("res://textures")
	sheet.save_png("res://textures/model_sheet.png")
	print("folha: ", ProjectSettings.globalize_path("res://textures/model_sheet.png"))
	quit()
