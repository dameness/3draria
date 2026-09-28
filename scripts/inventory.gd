class_name Inventory
extends RefCounted
# Slots de itens. Os primeiros HOTBAR slots são a hotbar.

const SIZE := 40
const HOTBAR := 10

var item := PackedInt32Array()    # -1 = vazio
var count := PackedInt32Array()
var version := 0                  # muda a cada alteração (a interface redesenha)


func _init() -> void:
	item.resize(SIZE)
	item.fill(-1)
	count.resize(SIZE)


# Empilha onde já existe e depois usa slots vazios. Retorna quanto não coube.
func add(id: int, n: int) -> int:
	for pass_empty in [false, true]:
		for i in SIZE:
			if n == 0:
				break
			if item[i] == id or (pass_empty and item[i] == -1):
				var room := Items.stack[id] - (count[i] if item[i] == id else 0)
				var moved := mini(room, n)
				if moved > 0:
					item[i] = id
					count[i] += moved
					n -= moved
	version += 1
	return n


func total(id: int) -> int:
	var t := 0
	for i in SIZE:
		if item[i] == id:
			t += count[i]
	return t


# Tira n unidades; só chame depois de conferir total().
func remove(id: int, n: int) -> void:
	for i in range(SIZE - 1, -1, -1):
		if item[i] == id and n > 0:
			var taken := mini(count[i], n)
			count[i] -= taken
			n -= taken
			if count[i] == 0:
				item[i] = -1
	version += 1


func take_one(slot: int) -> void:
	count[slot] -= 1
	if count[slot] == 0:
		item[slot] = -1
	version += 1


func swap(a: int, b: int) -> void:
	var t := item[a]
	item[a] = item[b]
	item[b] = t
	t = count[a]
	count[a] = count[b]
	count[b] = t
	version += 1
