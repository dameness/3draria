class_name Housing
# Moradia de habitante (wiki Housing, adaptada a 3D: o jogo não tem parede de fundo). Um cômodo é o ar conectado a partir de uma célula (busca em 3D),
# fechado por blocos sólidos e portas (aberta ou fechada, a porta é parede), com volume entre MIN_CELLS e MAX_CELLS, uma luz (tocha), uma mesa
# (bancada de trabalho) e uma cadeira encostadas no espaço. Nenhum estado: tudo se lê do mundo.

const MIN_CELLS := 12      # 3 x 2 x 2
const MAX_CELLS := 400     # acima disto o "cômodo" escapou (sem teto, sem parede, porta faltando)
const SEARCH := 40.0       # raio (blocos) em volta do jogador em que se procuram cadeiras de casas novas
const DIRS: Array[Vector3i] = [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]


static func is_wall(b: int) -> bool:
	return Blocks.solid[b] == 1 or b == Blocks.door_open


# O cômodo que contém `at`: {cells: {Vector3i: true}, open: escapou, light, table, chair}. `at` dentro de uma parede: sem células.
static func room(world: Node3D, at: Vector3i) -> Dictionary:
	var out := {"cells": {}, "open": false, "light": false, "table": false, "chair": false}
	if is_wall(world.get_block(at.x, at.y, at.z)):
		return out
	var workbench: int = Blocks.ids.workbench
	var chair: int = Blocks.ids.chair
	var cells: Dictionary = out.cells
	cells[at] = true
	var queue: Array[Vector3i] = [at]
	while not queue.is_empty():
		var c: Vector3i = queue.pop_back()
		if Blocks.light[world.get_block(c.x, c.y, c.z)] > 0:
			out.light = true
		for d in DIRS:
			var n: Vector3i = c + d
			var b: int = world.get_block(n.x, n.y, n.z)
			if b == chair:
				out.chair = true
			elif Blocks.station_as[b] == workbench:
				out.table = true
			if is_wall(b) or cells.has(n):
				continue
			if n.y < 0 or n.y >= WorldGen.HEIGHT or cells.size() >= MAX_CELLS:
				out.open = true
				return out
			cells[n] = true
			queue.append(n)
	return out


# Confere a moradia em `at`: room() mais valid e reason (o que falta, em português).
static func check(world: Node3D, at: Vector3i) -> Dictionary:
	var r := room(world, at)
	r.reason = ""
	if r.cells.is_empty():
		r.reason = "sem espaço livre aqui"
	elif r.open:
		r.reason = "não está fechada: falta parede, teto ou porta"
	elif r.cells.size() < MIN_CELLS:
		r.reason = "pequena demais (%d de %d blocos de ar)" % [r.cells.size(), MIN_CELLS]
	elif not r.light:
		r.reason = "falta uma luz (tocha)"
	elif not r.table:
		r.reason = "falta uma mesa (bancada de trabalho)"
	elif not r.chair:
		r.reason = "falta uma cadeira"
	r.valid = r.reason == ""
	return r


# A 1ª casa válida com uma cadeira a até SEARCH de `center` que não guarda nenhuma das casas em `taken` (células de moradores): {home: célula em cima da cadeira, cells}, ou {}.
# Acha as cadeiras pelos chunks já gerados (PackedByteArray.find, nativo).
static func find(world: Node3D, center: Vector3, taken: Array) -> Dictionary:
	var chair: int = Blocks.ids.chair
	var c := Vector2i(floori(center.x / WorldGen.CHUNK), floori(center.z / WorldGen.CHUNK))
	var layer := WorldGen.CHUNK * WorldGen.CHUNK
	for dz in range(-2, 3):
		for dx in range(-2, 3):
			var k := c + Vector2i(dx, dz)
			if not world.chunks.has(k):
				continue
			var d: PackedByteArray = world.chunks[k]
			var i := d.find(chair, 0)
			while i != -1:
				var pos := Vector3i(k.x * WorldGen.CHUNK + i % WorldGen.CHUNK, i / layer, k.y * WorldGen.CHUNK + (i / WorldGen.CHUNK) % WorldGen.CHUNK)
				if Vector2(pos.x + 0.5 - center.x, pos.z + 0.5 - center.z).length() <= SEARCH:
					var r := check(world, pos + Vector3i.UP)
					if r.valid and not taken.any(func(h): return r.cells.has(h)):
						return {"home": pos + Vector3i.UP, "cells": r.cells}
				i = d.find(chair, i + 1)
	return {}


# Botão direito na cadeira: o que a moradia precisa (ou que está tudo certo).
static func report(world: Node3D, chair: Vector3i) -> String:
	var r := check(world, chair + Vector3i.UP)
	if r.valid:
		return "Casa válida (%d blocos de ar): Guide, Merchant e Nurse podem morar aqui" % r.cells.size()
	return "Esta casa %s" % r.reason if not r.cells.is_empty() else "Cadeira sem espaço livre em cima"
