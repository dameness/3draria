class_name ItemModel
# Transforma o ícone 2D num objeto 3D. `build`: extrusão fina (frente e verso com a própria imagem, bordas só onde o vizinho é
# transparente) para inimigos de sprite; `for_item`: o modelo voxel (scripts/voxel), que dá volume a todo item.

const THICK := 1.5          # espessura em pixels do sprite
const SHADE_FRONT := 1.0
const SHADE_SIDE := 0.7

static var cache := {}      # [item, tamanho] -> [ArrayMesh, Material]


# Malha com origem no canto inferior esquerdo da imagem; o lado maior mede `length`.
static func build(img: Image, length: float, thick_px := THICK) -> ArrayMesh:
	var w := img.get_width()
	var h := img.get_height()
	var s := length / maxi(w, h)
	var d := thick_px * s / 2
	var a := {"v": PackedVector3Array(), "n": PackedVector3Array(), "c": PackedColorArray(), "uv": PackedVector2Array(), "i": PackedInt32Array()}
	var W := w * s
	var H := h * s
	var full := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
	_quad(a, [Vector3(0, 0, d), Vector3(W, 0, d), Vector3(W, H, d), Vector3(0, H, d)], full, Vector3.BACK, SHADE_FRONT)
	_quad(a, [Vector3(0, 0, -d), Vector3(W, 0, -d), Vector3(W, H, -d), Vector3(0, H, -d)], full, Vector3.FORWARD, SHADE_FRONT)
	for py in h:
		for px in w:
			if not _solid(img, px, py):
				continue
			var x0 := px * s
			var x1 := x0 + s
			var y0 := (h - py - 1) * s
			var y1 := y0 + s
			var uv := Vector2((px + 0.5) / w, (py + 0.5) / h)
			var uvs := [uv, uv, uv, uv]
			if not _solid(img, px + 1, py):
				_quad(a, [Vector3(x1, y0, -d), Vector3(x1, y1, -d), Vector3(x1, y1, d), Vector3(x1, y0, d)], uvs, Vector3.RIGHT, SHADE_SIDE)
			if not _solid(img, px - 1, py):
				_quad(a, [Vector3(x0, y0, -d), Vector3(x0, y1, -d), Vector3(x0, y1, d), Vector3(x0, y0, d)], uvs, Vector3.LEFT, SHADE_SIDE)
			if not _solid(img, px, py - 1):
				_quad(a, [Vector3(x0, y1, -d), Vector3(x1, y1, -d), Vector3(x1, y1, d), Vector3(x0, y1, d)], uvs, Vector3.UP, SHADE_SIDE)
			if not _solid(img, px, py + 1):
				_quad(a, [Vector3(x0, y0, -d), Vector3(x1, y0, -d), Vector3(x1, y0, d), Vector3(x0, y0, d)], uvs, Vector3.DOWN, SHADE_SIDE)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = a.v
	arrays[Mesh.ARRAY_NORMAL] = a.n
	arrays[Mesh.ARRAY_COLOR] = a.c
	arrays[Mesh.ARRAY_TEX_UV] = a.uv
	arrays[Mesh.ARRAY_INDEX] = a.i
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func _solid(img: Image, x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height() and img.get_pixel(x, y).a > 0.5


# Acrescenta um quad virado para `n`, acertando a ordem dos cantos para o sentido horário do Godot.
static func _quad(a: Dictionary, c: Array, uvs: Array, n: Vector3, shade: float) -> void:
	if (c[1] - c[0]).cross(c[2] - c[0]).dot(n) > 0:
		c = [c[0], c[3], c[2], c[1]]
		uvs = [uvs[0], uvs[3], uvs[2], uvs[1]]
	var base: int = a.v.size()
	for k in 4:
		a.v.append(c[k])
		a.n.append(n)
		a.c.append(Color(shade, shade, shade))
		a.uv.append(uvs[k])
	a.i.append_array([base, base + 1, base + 2, base, base + 2, base + 3])


# [malha, material] do item na mão: modelo voxel (campo `model` do item, senão o nome; sem nada, o sprite inflado), cacheado.
# Itens soltos do código (projétil com sprite) passam um id que não é de item: valem só o ícone. A extrusão fina acima (`build`) fica
# para os inimigos.
static func for_item(id: int, icon: Texture2D, length: float) -> Array:
	var key := [id, length]
	if not cache.has(key):
		var img := icon.get_image()
		img.convert(Image.FORMAT_RGBA8)
		var name := ""
		if id >= 0 and id < Items.names.size():
			name = Items.defs[id].get("model", Items.names[id])
		cache[key] = [VoxRecipes.item_mesh(name, img, length), VoxMesh.material(0.6)]
	return cache[key]
