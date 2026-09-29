class_name Inventory
extends RefCounted
# Slots de itens. Os primeiros HOTBAR slots são a hotbar.

const SIZE := 50      # como no Terraria: 5 fileiras de 10 (a primeira é a hotbar)
const HOTBAR := 10
const ARMOR := ["head", "body", "legs"]   # slots de equipamento
const ACC := 5                            # slots de acessório
const AMMO := 4                           # slots de munição (usados antes do inventário)
const COINS := ["copper_coin", "silver_coin", "gold_coin", "platinum_coin"]   # 100 de um valem 1 do próximo

var item := PackedInt32Array()    # -1 = vazio
var count := PackedInt32Array()
var equip := PackedInt32Array([-1, -1, -1])   # armadura vestida, na ordem de ARMOR
var acc := PackedInt32Array([-1, -1, -1, -1, -1])   # acessórios vestidos
var ammo := PackedInt32Array([-1, -1, -1, -1])      # slots de munição
var ammo_count := PackedInt32Array([0, 0, 0, 0])
var coin := PackedInt32Array([0, 0, 0, 0])          # moedas nos slots de moeda (cobre, prata, ouro, platina)
var fav := PackedByteArray()                        # 1 = favorito (Alt+clique): o ordenar não mexe
var version := 0                  # muda a cada alteração (a interface redesenha)
var cursor_id := -1               # item preso ao mouse, como no Terraria (-1 = mão vazia)
var cursor_count := 0
var trash_id := -1                # lixeira: um slot; item novo destrói o que estava lá
var trash_count := 0


func _init() -> void:
	item.resize(SIZE)
	item.fill(-1)
	count.resize(SIZE)
	fav.resize(SIZE)


# Empilha onde já existe e depois usa slots vazios. Retorna quanto não coube.
func add(id: int, n: int) -> int:
	var c := coin_kind(id)
	if c != -1:   # moeda vai direto para os slots de moeda e sobe de tipo a cada 100
		coin[c] += n
		for k in 3:
			coin[k + 1] += coin[k] / 100
			coin[k] %= 100
		version += 1
		return 0
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
# it/ct = as listas de slots (o inventário ou as de um baú: ambos usam o mesmo cursor).
func click(i: int, it := item, ct := count) -> void:
	if it == item:
		fav[i] = 0
	if cursor_id == -1:
		cursor_id = it[i]
		cursor_count = ct[i]
		it[i] = -1
		ct[i] = 0
	elif it[i] == -1:
		it[i] = cursor_id
		ct[i] = cursor_count
		cursor_id = -1
		cursor_count = 0
	elif it[i] == cursor_id and Items.stack[cursor_id] > 1:
		var moved := mini(Items.stack[cursor_id] - ct[i], cursor_count)
		ct[i] += moved
		cursor_count -= moved
		if cursor_count == 0:
			cursor_id = -1
	else:
		var t := it[i]
		it[i] = cursor_id
		cursor_id = t
		t = ct[i]
		ct[i] = cursor_count
		cursor_count = t
	version += 1


# Clique direito no slot i: pega 1 item da pilha para a mão (o mesmo item vai somando).
func right_click(i: int, it := item, ct := count) -> void:
	if it[i] == -1 or not (cursor_id == -1 or (cursor_id == it[i] and cursor_count < Items.stack[cursor_id])):
		return
	cursor_id = it[i]
	cursor_count += 1
	ct[i] -= 1
	if ct[i] == 0:
		it[i] = -1
	version += 1


# Shift+clique: manda a pilha do slot i de origem para o destino (baú <-> inventário): junta onde há o mesmo item e depois usa vazios.
# Retorna false se nada coube.
static func move_stack(from_it: PackedInt32Array, from_ct: PackedInt32Array, i: int, to_it: PackedInt32Array, to_ct: PackedInt32Array, first := 0) -> bool:
	var id := from_it[i]
	if id == -1:
		return false
	var n := from_ct[i]
	for empty_pass in [false, true]:
		for k in range(first, to_it.size()):
			if n > 0 and (to_it[k] == id or (empty_pass and to_it[k] == -1)):
				var moved := mini(Items.stack[id] - (to_ct[k] if to_it[k] == id else 0), n)
				if moved > 0:
					to_it[k] = id
					to_ct[k] += moved
					n -= moved
	var moved_any := n < from_ct[i]
	from_ct[i] = n
	if n == 0:
		from_it[i] = -1
	return moved_any


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


# Ctrl+clique: manda o item do slot direto para a lixeira (o que estava lá é destruído). Favorito e slot vazio não vão.
func quick_trash(i: int) -> bool:
	if item[i] == -1 or fav[i] == 1:
		return false
	trash_id = item[i]
	trash_count = count[i]
	item[i] = -1
	count[i] = 0
	version += 1
	return true


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
	d += int(acc_sum("defense"))
	for s in Items.sets.values():
		if s.pieces.all(func(p): return p in equip):
			d += s.defense
	return d


# 0-3 se o item é uma moeda (cobre a platina), senão -1.
static func coin_kind(id: int) -> int:
	return COINS.find(Items.names[id])


# Valor total das moedas em cobre.
func coin_value() -> int:
	return coin[0] + coin[1] * 100 + coin[2] * 10000 + coin[3] * 1000000


# Primeira munição da classe pedida (slots de munição primeiro), tirando 1. Retorna o id ou -1.
func take_ammo(ammo_class: String) -> int:
	for k in AMMO:
		if ammo[k] != -1 and Items.defs[ammo[k]].get("ammo_class") == ammo_class:
			var id := ammo[k]
			ammo_count[k] -= 1
			if ammo_count[k] == 0:
				ammo[k] = -1
			version += 1
			return id
	for i in SIZE:
		if item[i] != -1 and Items.defs[item[i]].get("ammo_class") == ammo_class:
			var id := item[i]
			take_one(i)
			return id
	return -1


# Clique no slot de munição k: só aceita munição; mesmas regras de pegar/soltar/juntar do inventário.
func click_ammo(k: int) -> void:
	if cursor_id != -1 and not Items.defs[cursor_id].has("ammo_class"):
		return
	if cursor_id != -1 and ammo[k] == cursor_id:
		var moved := mini(Items.stack[cursor_id] - ammo_count[k], cursor_count)
		ammo_count[k] += moved
		cursor_count -= moved
		if cursor_count == 0:
			cursor_id = -1
	else:
		var t := ammo[k]
		ammo[k] = cursor_id
		cursor_id = t
		t = ammo_count[k]
		ammo_count[k] = cursor_count
		cursor_count = t
	version += 1


# Clique no acessório k: só aceita item com "accessory" nos dados; troca com o que estava vestido.
func click_acc(k: int) -> void:
	if cursor_id != -1 and not Items.defs[cursor_id].has("accessory"):
		return
	var old := acc[k]
	acc[k] = cursor_id
	cursor_id = old
	cursor_count = 1 if old != -1 else 0
	version += 1


# Soma um atributo dos acessórios vestidos (ex.: "speed", "jump", "defense").
func acc_sum(stat: String) -> float:
	var t := 0.0
	for id in acc:
		if id != -1:
			t += float(Items.defs[id].accessory.get(stat, 0))
	return t


# Alt+clique: favorita ou desfavorita o slot (favorito não é mexido pelo ordenar).
func toggle_fav(i: int) -> void:
	if item[i] != -1:
		fav[i] = 1 - fav[i]
		version += 1


# Ordena o inventário (menos a hotbar e os favoritos): mesmo item junto, por nome, pilhas cheias primeiro.
func sort_items() -> void:
	var entries := []
	for i in range(HOTBAR, SIZE):
		if item[i] != -1 and fav[i] == 0:
			entries.append([item[i], count[i]])
			item[i] = -1
			count[i] = 0
	entries.sort_custom(func(a, b): return Items.names[a[0]] < Items.names[b[0]] or (a[0] == b[0] and a[1] > b[1]))
	var i := HOTBAR
	for e in entries:
		while i < SIZE and (item[i] != -1 or fav[i] == 1):
			i += 1
		item[i] = e[0]
		count[i] = e[1]
	version += 1
