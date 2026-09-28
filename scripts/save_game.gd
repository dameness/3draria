class_name SaveGame
# Saves como no Terraria: personagens em user://players/*.plr (nome, vida, inventário) e mundos em
# user://worlds/*.wld (nome, seed, hora, spawn, só os chunks editados). O menu escolhe os dois e
# guarda os caminhos em player_path/world_path; o jogo carrega ao entrar e salva no F5, no "Salvar e
# sair" e ao fechar a janela. Sem caminhos (testes, rodar game.tscn direto) nada é lido nem gravado.

const VERSION := 2
const SKINS := ["#f0b890", "#e0a070", "#c98a5c", "#a86a44", "#f6cfae"]
const HAIRS := ["#5a3220", "#2a1c14", "#d6a94a", "#a83a1e", "#8a8a90", "#3a2a5a"]
const SHIRTS := ["#c0503c", "#3f8f4f", "#3e6fbf", "#c9a13a", "#8a4fb0", "#4fa8a8", "#b0b0b8"]
const PANTS := ["#3c4c98", "#3a3a48", "#6a4a2a", "#2a5a4a", "#5a2a3a"]
static var players_dir := "user://players/"
static var worlds_dir := "user://worlds/"
static var player_path := ""
static var world_path := ""


# [{path, name, info}] dos saves de um diretório, ordenados pelo nome.
static func list(dir: String) -> Array:
	var out := []
	DirAccess.make_dir_recursive_absolute(dir)
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".plr") or f.ends_with(".wld"):
			var data := _read(dir + f)
			if not data.is_empty():
				out.append({"path": dir + f, "name": data.name, "info": data})
	out.sort_custom(func(a, b): return a.name.naturalnocasecmp_to(b.name) < 0)
	return out


# Cria o arquivo e retorna o caminho, ou "" se o nome for vazio ou já existir.
static func create_player(name: String) -> String:
	var path := _path(players_dir, name, ".plr")
	if path == "" or _write(path, {"version": VERSION, "name": name.strip_edges(), "new": true}) != OK:
		return ""
	return path


static func create_world(name: String, seed: int) -> String:
	var path := _path(worlds_dir, name, ".wld")
	if path == "" or _write(path, {"version": VERSION, "name": name.strip_edges(), "seed": seed, "time": 60.0, "chunks": {}}) != OK:
		return ""
	return path


# Aparência (cores) do personagem, tirada do nome: cada personagem tem a sua sem guardar nada no save.
static func look_for(name: String) -> Dictionary:
	var h := name.hash()
	return {"skin": Color(SKINS[h % SKINS.size()]), "hair": Color(HAIRS[(h >> 3) % HAIRS.size()]),
		"shirt": Color(SHIRTS[(h >> 6) % SHIRTS.size()]), "pants": Color(PANTS[(h >> 9) % PANTS.size()])}


static func look(path: String) -> Dictionary:
	return look_for(str(_read(path).get("name", "")))


static func delete(path: String) -> void:
	DirAccess.remove_absolute(path)


static func save_all(world, player, clock) -> Error:
	var err := OK
	if world_path != "":
		err = save_world(world, player, clock, world_path)
	if player_path != "" and err == OK:
		err = save_player(player, player_path)
	return err


static func save_player(player, path: String) -> Error:
	var inv := []
	for i in Inventory.SIZE:
		var id: int = player.inv.item[i]
		inv.append([Items.names[id] if id != -1 else "", player.inv.count[i]])
	var equip := Array(player.inv.equip).map(func(id): return Items.names[id] if id != -1 else "")
	return _write(path, {"version": VERSION, "name": _read(path).get("name", player.name), "hp": player.hp, "inv": inv, "equip": equip})


# Retorna false para personagem novo (o jogo dá os itens iniciais).
static func load_player(player, path: String) -> bool:
	var data := _read(path)
	if data.is_empty() or data.get("new", false):
		return false
	player.hp = data.hp
	player.inv = Inventory.new()
	for i in mini(Inventory.SIZE, data.inv.size()):   # saves antigos têm menos slots
		var entry: Array = data.inv[i]
		if Items.ids.has(entry[0]):  # item removido dos dados some do save
			player.inv.item[i] = Items.ids[entry[0]]
			player.inv.count[i] = entry[1]
	var equip: Array = data.get("equip", [])
	for k in equip.size():
		player.inv.equip[k] = Items.ids.get(equip[k], -1)
	return true


static func save_world(world, player, clock, path: String) -> Error:
	var chunks := {}
	for k in world.edited:
		chunks[k] = world.chunks[k].compress(FileAccess.COMPRESSION_ZSTD)
	return _write(path, {"version": VERSION, "name": _read(path).get("name", "mundo"), "seed": world.world_seed,
		"time": clock.time, "spawn": player.spawn, "chunks": chunks})


static func load_world(world, player, clock, path: String) -> bool:
	var data := _read(path)
	if data.is_empty():
		return false
	world.set_seed(data.seed)
	var size := WorldGen.CHUNK * WorldGen.CHUNK * WorldGen.HEIGHT
	for k in data.chunks:
		world.chunks[k] = data.chunks[k].decompress(size, FileAccess.COMPRESSION_ZSTD)
		world.edited[k] = true
	clock.time = data.time
	if data.has("spawn"):
		player.spawn = data.spawn
	return true


static func _path(dir: String, name: String, ext: String) -> String:
	var file := name.strip_edges().validate_filename()
	if file == "":
		return ""
	DirAccess.make_dir_recursive_absolute(dir)
	var path := dir + file + ext
	return "" if FileAccess.file_exists(path) else path


static func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var data = FileAccess.open(path, FileAccess.READ).get_var()
	if typeof(data) != TYPE_DICTIONARY or data.get("version") != VERSION:
		push_warning("save ignorado (inválido ou de outra versão): " + path)
		return {}
	return data


# Grava num temporário e renomeia, para um crash no meio não estragar o save anterior.
static func _write(path: String, data: Dictionary) -> Error:
	var f := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_var(data)
	f.close()
	return DirAccess.rename_absolute(path + ".tmp", path)
