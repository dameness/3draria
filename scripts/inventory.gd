class_name Inventory
extends RefCounted
# Slots de itens. Os primeiros HOTBAR slots são a hotbar.

const SIZE := 50      # como no Terraria: 5 fileiras de 10 (a primeira é a hotbar)
const HOTBAR := 10
const ARMOR := ["head", "body", "legs"]   # slots de equipamento

var item := PackedInt32Array()    # -1 = vazio
var count := PackedInt32Array()
var equip := PackedInt32Array([-1, -1, -1])   # armadura vestida, na ordem de ARMOR
var version := 0                  # muda a cada alteração (a interface redesenha)
var cursor_id := -1               # item preso ao mouse, como no Terraria (-1 = mão vazia)
var cursor_count := 0
var trash_id := -1                # lixeira: um slot; item novo destrói o que estava lá
var trash_count := 0


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


# Veste a armadura do slot i (troca com a peça que estava vestida). Retorna false se não for armadura.
func equip_from(i: int) -> bool:
	var id := item[i]
	if id == -1 or not Items.defs[id].has("armor"):
		return false
	var k := ARMOR.find(Items.defs[id].armor)
	item[i] = equip[k]
	count[i] = 1 if equip[k] != -1 else 0
	equip[k] = id
	version += 1
	return true


# Tira a peça do slot de equipamento k para o inventário (se couber).
func unequip(k: int) -> void:
	if equip[k] != -1 and add(equip[k], 1) == 0:
		equip[k] = -1
	version += 1


# Clique esquerdo no slot i: mão vazia pega a pilha inteira; com item na mão solta, junta (até o limite) ou troca.
func click(i: int) -> void:
	if cursor_id == -1:
		cursor_id = item[i]
		cursor_count = count[i]
		item[i] = -1
		count[i] = 0
	elif item[i] == -1:
		item[i] = cursor_id
		count[i] = cursor_count
		cursor_id = -1
		cursor_count = 0
	elif item[i] == cursor_id and Items.stack[cursor_id] > 1:
		var moved := mini(Items.stack[cursor_id] - count[i], cursor_count)
		count[i] += moved
		cursor_count -= moved
		if cursor_count == 0:
			cursor_id = -1
	else:
		var t := item[i]
		item[i] = cursor_id
		cursor_id = t
		t = count[i]
		count[i] = cursor_count
		cursor_count = t
	version += 1


# Clique direito no slot i: pega 1 item da pilha para a mão (o mesmo item vai somando).
func right_click(i: int) -> void:
	if item[i] == -1 or not (cursor_id == -1 or (cursor_id == item[i] and cursor_count < Items.stack[cursor_id])):
		return
	cursor_id = item[i]
	cursor_count += 1
	count[i] -= 1
	if count[i] == 0:
		item[i] = -1
	version += 1


# Clique no slot de armadura k: com a peça certa na mão veste (a antiga vai para a mão); mão vazia tira a peça.
func click_equip(k: int) -> void:
	if cursor_id != -1 and Items.defs[cursor_id].get("armor") != ARMOR[k]:
		return   # não é peça deste slot
	var old := equip[k]
	equip[k] = cursor_id
	cursor_id = old
	cursor_count = 1 if old != -1 else 0
	version += 1


# Lixeira: com item na mão joga fora (o que estava lá some para sempre); mão vazia recupera o que está lá.
func click_trash() -> void:
	if cursor_id != -1:
		trash_id = cursor_id
		trash_count = cursor_count
		cursor_id = -1
		cursor_count = 0
	else:
		cursor_id = trash_id
		cursor_count = trash_count
		trash_id = -1
		trash_count = 0
	version += 1


# Devolve o item da mão ao inventário (ao fechar a janela). Retorna quantos não couberam.
func release_cursor() -> int:
	var left := 0
	if cursor_id != -1:
		left = add(cursor_id, cursor_count)
	cursor_id = -1
	cursor_count = 0
	version += 1
	return left


# Defesa das peças vestidas + bônus do conjunto completo (como no Terraria).
func defense() -> int:
	var d := 0
	for id in equip:
		if id != -1:
			d += Items.defs[id].defense
	for s in Items.sets.values():
		if s.pieces.all(func(p): return p in equip):
			d += s.defense
	return d
