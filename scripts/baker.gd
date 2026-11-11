class_name Baker
extends RefCounted
# Assa um .wld: gera todos os chunks que ainda faltam (os editados de um save v2 ficam como estão), comprime e grava o mundo como v3
# (baked = true). Daí em diante o arquivo é a verdade; o gerador só serve para mundos novos. Roda no WorkerThreadPool (o menu mostra
# progress()), e finish() grava na thread principal. Também anota o que o jogo ainda perguntava ao gerador: o tipo de cada baú e a
# entrada do dungeon. Mundo de teste não se assa (a arena sai do gerador).

var path := ""
var data := {}
var gen: WorldGen
var keys: Array[Vector2i] = []
var out := []   # por chunk (mesmo índice de keys): [zstd, [[posição, tipo] dos baús]]; cada tarefa escreve só o seu
var group := -1
var finished := false
var old := {}   # chunks já gravados (editados, de um save v2)


# area = os chunks a assar (padrão: o mundo todo; os testes assam um pedaço).
func _init(world_path: String, area := Rect2i(0, 0, WorldGen.SIZE_CHUNKS, WorldGen.SIZE_CHUNKS)) -> void:
	path = world_path
	data = SaveGame._read(path)
	gen = WorldGen.new(data.seed)
	gen.hardmode = data.get("hardmode", false)
	old = data.chunks
	for z in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			keys.append(Vector2i(x, z))
	out.resize(keys.size())


# O .wld precisa de assar? (existe, tem o tamanho certo, não é o mundo de teste e ainda não foi assado.)
static func needs(world_path: String) -> bool:
	var d := SaveGame._read(world_path)
	return not d.is_empty() and d.get("size", 16) == WorldGen.SIZE_CHUNKS and not d.get("test", false) and not d.get("baked", false)


func start() -> void:
	group = WorkerThreadPool.add_group_task(_one, keys.size(), clampi(OS.get_processor_count() - 1, 1, 8), false, "assar o mundo")


func progress() -> float:
	if finished:
		return 1.0
	return WorkerThreadPool.get_group_processed_element_count(group) / float(maxi(1, keys.size()))


func done() -> bool:
	return finished or WorkerThreadPool.is_group_task_completed(group)


func _one(i: int) -> void:
	var k := keys[i]
	var bytes: PackedByteArray = old[k] if old.has(k) else PackedByteArray()
	var d := bytes.decompress(WorldGen.CHUNK * WorldGen.CHUNK * WorldGen.HEIGHT, FileAccess.COMPRESSION_ZSTD) if old.has(k) else gen.generate(k.x, k.y)
	if not old.has(k):
		bytes = d.compress(FileAccess.COMPRESSION_ZSTD)
	var chests := []
	var at := d.find(gen.CHEST)
	while at != -1:
		var p := Vector3i(k.x * WorldGen.CHUNK + at % WorldGen.CHUNK, at / (WorldGen.CHUNK * WorldGen.CHUNK), k.y * WorldGen.CHUNK + at / WorldGen.CHUNK % WorldGen.CHUNK)
		chests.append([p, gen.chest_kind(p)])
		at = d.find(gen.CHEST, at + 1)
	out[i] = [bytes, chests]


# Espera as tarefas e grava o .wld v3. Retorna o erro de gravação.
func finish() -> Error:
	WorkerThreadPool.wait_for_group_task_completion(group)
	finished = true
	var kinds := {}
	var chunks: Dictionary = data.chunks
	for i in keys.size():
		chunks[keys[i]] = out[i][0]
		for c in out[i][1]:
			kinds[c[0]] = c[1]
	data.merge({"version": SaveGame.VERSION, "chunks": chunks, "baked": true, "chest_kinds": kinds, "dungeon_entrance": gen.dungeon_entrance}, true)
	return SaveGame._write(path, data)
