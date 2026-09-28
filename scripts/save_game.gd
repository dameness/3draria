class_name SaveGame
# Salva e carrega: seed, hora, jogador (posição, vida, inventário por nome) e só os chunks editados.

const PATH := "user://save.dat"
const VERSION := 1


static func save(world, player, clock, path := PATH) -> Error:
	var chunks := {}
	for k in world.edited:
		chunks[k] = world.chunks[k].compress(FileAccess.COMPRESSION_ZSTD)
	var inv := []
	for i in Inventory.SIZE:
		var id: int = player.inv.item[i]
		inv.append([Items.names[id] if id != -1 else "", player.inv.count[i]])
	var data := {"version": VERSION, "seed": world.world_seed, "time": clock.time, "pos": player.position,
		"spawn": player.spawn, "hp": player.hp, "inv": inv, "chunks": chunks}
	# Grava num temporário e renomeia, para um crash no meio não estragar o save anterior.
	var f := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_var(data)
	f.close()
	return DirAccess.rename_absolute(path + ".tmp", path)


static func load_into(world, player, clock, path := PATH) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var data = FileAccess.open(path, FileAccess.READ).get_var()
	if typeof(data) != TYPE_DICTIONARY or data.get("version") != VERSION:
		push_warning("save ignorado (inválido ou de outra versão): " + path)
		return false
	world.set_seed(data.seed)
	var size := WorldGen.CHUNK * WorldGen.CHUNK * WorldGen.HEIGHT
	for k in data.chunks:
		world.chunks[k] = data.chunks[k].decompress(size, FileAccess.COMPRESSION_ZSTD)
		world.edited[k] = true
	clock.time = data.time
	player.position = data.pos
	player.spawn = data.spawn
	player.hp = data.hp
	player.inv = Inventory.new()
	for i in Inventory.SIZE:
		var entry: Array = data.inv[i]
		if Items.ids.has(entry[0]):  # item removido dos dados some do save
			player.inv.item[i] = Items.ids[entry[0]]
			player.inv.count[i] = entry[1]
	return true
