extends SceneTree
# Gera os modelos de inimigos/chefes em assets/models/bbgen/*.glb (fora do git): cada receita em models.gd monta um BbRig (ossos de voxels +
# animações) e esta cena o grava em glTF binário, que enemy_model.gd lê em runtime. NUNCA toca em assets/models/bb/: um .glb feito à mão no
# Blockbench com o mesmo nome fica lá e vence o gerado (como os .vox retocados em assets/models/).
# Uso: .tools/godot --headless -s scripts/bb/build.gd [-- nome ...]
const OUT := "res://assets/models/bbgen/"
const Models := preload("res://scripts/bb/models.gd")
const UNIT := 1.0 / 16.0   # glTF: 1 texel = 1/16 (enemy_model.gd multiplica por BB_SCALE)


func _init() -> void:
	var only := Array(OS.get_cmdline_user_args())
	run(only)
	quit()


static func run(only := []) -> int:
	DirAccess.make_dir_recursive_absolute(OUT)
	var n := 0
	var all: Dictionary = Models.all()
	for name in all:
		if only.is_empty() or name in only:
			var rig: BbRig = all[name].call()
			var err := write(rig, OUT + name + ".glb")
			assert(err == OK, "falha ao gravar " + name)
			n += 1
	print("modelos bb: %d em %s" % [n, ProjectSettings.globalize_path(OUT)])
	return n


static func _g(rig: BbRig, p: Vector3) -> Vector3:   # célula (MagicaVoxel) → glTF
	return Vector3(-p.x, p.z, p.y) * rig.k * UNIT


static func write(rig: BbRig, path: String) -> int:
	var root := _scene(rig)
	var st := GLTFState.new()
	var doc := GLTFDocument.new()
	var err := doc.append_from_scene(root, st)
	if err == OK:
		err = doc.write_to_filesystem(st, ProjectSettings.globalize_path(path))
	root.free()
	return err


static func _scene(rig: BbRig) -> Node3D:
	var root := Node3D.new()
	root.name = "Model"
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.9
	var nodes := {}
	var rest := {}
	for name in rig.bones:   # os pais vêm antes dos filhos (a ordem de criação)
		var b: Dictionary = rig.bones[name]
		var node := Node3D.new()
		node.name = name
		var up: Node3D = nodes.get(b.parent, root)
		up.add_child(node)
		node.owner = root
		var from: Vector3 = rig.bones[b.parent].pivot if b.parent != "" else rig.center
		node.position = _g(rig, b.pivot - from)
		nodes[name] = node
		rest[name] = node.position
		var vox: VoxModel = b.vox
		if not vox.v.is_empty():
			var mi := MeshInstance3D.new()
			mi.name = name + "_mesh"
			mi.mesh = VoxMesh.build(vox, rig.k * UNIT, false, b.pivot)
			mi.mesh.surface_set_material(0, mat)
			node.add_child(mi)
			mi.owner = root
	var player := AnimationPlayer.new()
	player.name = "AnimationPlayer"
	root.add_child(player)
	player.owner = root
	var lib := AnimationLibrary.new()
	var used := {}   # osso → tipos animados em algum clipe (todo clipe os fixa no repouso quando não os mexe: senão a pose do anterior fica)
	for a in rig.anims:
		for b in rig.anims[a].tracks:
			used[b] = used.get(b, {})
			for kind in rig.anims[a].tracks[b]:
				used[b][kind] = true
	for a in rig.anims:
		var an := Animation.new()
		an.length = rig.anims[a].length
		an.loop_mode = Animation.LOOP_LINEAR if a in BbRig.LOOPED else Animation.LOOP_NONE
		for b in used:
			var tracks: Dictionary = rig.anims[a].tracks.get(b, {})
			var path := NodePath(root.get_path_to(nodes[b]))
			for kind in used[b]:
				var keys: Array = tracks.get(kind, [[0.0, Vector3.ONE if kind == "scl" else Vector3.ZERO], [an.length, Vector3.ONE if kind == "scl" else Vector3.ZERO]])
				var ti := an.add_track({"rot": Animation.TYPE_ROTATION_3D, "pos": Animation.TYPE_POSITION_3D, "scl": Animation.TYPE_SCALE_3D}[kind])
				an.track_set_path(ti, path)
				for kv in keys:
					match kind:
						"rot":
							var d: Vector3 = kv[1]
							an.rotation_track_insert_key(ti, kv[0], Quaternion.from_euler(Vector3(deg_to_rad(d.x), deg_to_rad(d.y), deg_to_rad(d.z))))
						"pos":
							an.position_track_insert_key(ti, kv[0], rest[b] + kv[1] * rig.k * UNIT)
						"scl":
							an.scale_track_insert_key(ti, kv[0], kv[1])
		lib.add_animation(a, an)
	player.add_animation_library("", lib)
	return root
