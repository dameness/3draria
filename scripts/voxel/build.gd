extends SceneTree
# Gera os .vox derivados em assets/models/gen/ (fora do git, como os sprites): as receitas (models.json + corpo) e, para todo
# item cujo ícone é um sprite da wiki, o modelo automático (sprite inflado). Retoques à mão ficam em assets/models/ e têm
# prioridade (nunca são tocados). Uso: .tools/godot --headless -s scripts/voxel/build.gd   (o update.sh roda isto)

const OUT := "res://assets/models/gen/"
const AUTO_VERSION := 2   # muda quando o algoritmo do automático muda: refaz todos


static func run() -> int:
	Blocks.load_pack()
	Items.load_pack()
	VoxRecipes.clear_cache()
	var ver := OUT + ".version"
	var redo := not FileAccess.file_exists(ver) or FileAccess.get_file_as_string(ver) != str(AUTO_VERSION)
	var done := {}
	for name in ["body"] + VoxRecipes.specs().keys():
		var made := VoxRecipes.make(name)
		for f in made:
			made[f].write(OUT + f + ".vox")
			done[f] = true
	var atlas := ImageTexture.create_from_image(Atlas.build(Blocks.textures))
	var n := 0
	for id in Items.names.size():
		var name: String = Items.defs[id].get("model", Items.names[id])
		var spec: Dictionary = Blocks.textures.get(Items.icon_name[id], {})
		if done.has(name) or spec.has("crop") or Atlas.wiki_image(spec) == null:
			continue
		if not redo and FileAccess.file_exists(OUT + name + ".vox"):
			continue
		var img := Items.icon_texture(id, atlas).get_image()
		img.convert(Image.FORMAT_RGBA8)
		VoxModel.from_sprite(img, VoxModel.inflate(img, VoxRecipes.auto_cap(name, img))).write(OUT + name + ".vox")
		done[name] = true
		n += 1
	DirAccess.make_dir_recursive_absolute(OUT)
	FileAccess.open(ver, FileAccess.WRITE).store_string(str(AUTO_VERSION))
	print("modelos voxel: %d receitas, %d itens automáticos novos em %s" % [done.size() - n, n, ProjectSettings.globalize_path(OUT)])
	return done.size()


func _init() -> void:
	run()
	quit()
