# Teste de rede (M3): servidor + 2 clientes no mesmo processo (um SceneMultiplayer por cena), WebSocket em 127.0.0.1.
# .tools/godot --headless -s tests/net.gd   (código de saída != 0 em falha)
extends SceneTree

const PORT := 18070
var failures := 0


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		printerr("FALHOU: ", msg)


func _initialize() -> void:
	_run()


func until(cond: Callable, sec := 30.0) -> bool:
	var t := Time.get_ticks_msec()
	while not cond.call():
		if Time.get_ticks_msec() - t > sec * 1000:
			return false
		await process_frame
	return true


func client(nick: String) -> Node3D:
	var m: Node3D = load("res://game.tscn").instantiate()
	m.name = nick
	m.get_node("Net").address = "ws://127.0.0.1:%d" % PORT
	m.get_node("Net").nick = nick
	root.add_child(m)
	return m


func _run() -> void:
	await process_frame   # a árvore só aceita cenas depois do primeiro quadro
	var srv: Node3D = load("res://server.tscn").instantiate()
	root.add_child(srv)
	var sw: Node3D = srv.get_node("World")
	var sn: Node = srv.get_node("Net")
	sw.set_seed(7)
	var mid := WorldGen.SIZE_CHUNKS * WorldGen.CHUNK / 2
	sn.spawn = Vector3(mid + 0.5, sw.surface_y(mid, mid), mid + 0.5)
	check(sn.host(PORT) == OK, "servidor abre a porta")

	var a := client("A")
	var an: Node = a.get_node("Net")
	var aw: Node3D = a.get_node("World")
	check(an.waiting and a.get_node("Player").process_mode == Node.PROCESS_MODE_DISABLED, "A espera o mundo parado")
	check(await until(func(): return not an.waiting), "A entra (welcome + chunks em volta)")
	check(a.get_node("Player").position.distance_to(sn.spawn) < 1.0, "A nasce no ponto do servidor")
	check(not aw.authority and aw.world_seed == 7, "A recebeu a seed e não manda no mundo")
	# A quebra um bloco antes de B chegar
	var x := mid + 3
	var z := mid
	var y: int = sw.surface_y(x, z) - 1
	check(aw.get_block(x, y, z) == sw.get_block(x, y, z) and Blocks.solid[aw.get_block(x, y, z)], "A vê o mesmo chão do servidor")
	aw.set_block(x, y, z, 0)
	check(await until(func(): return sw.get_block(x, y, z) == 0), "servidor recebe a quebra de A")

	var b := client("B")
	var bn: Node = b.get_node("Net")
	var bw: Node3D = b.get_node("World")
	check(await until(func(): return not bn.waiting), "B entra")
	check(bw.get_block(x, y, z) == 0, "B, que entrou depois, recebe o chunk já editado")
	aw.set_block(x, y + 3, z, Blocks.ids.stone)
	check(await until(func(): return bw.get_block(x, y + 3, z) == Blocks.ids.stone), "A coloca pedra → B vê")
	bw.set_block(x, y + 3, z, 0)
	check(await until(func(): return aw.get_block(x, y + 3, z) == 0), "B tira a pedra → A vê")

	# Água: só o servidor faz fluir; o fluxo chega aos dois
	var wx := mid - 4
	var wy: int = sw.surface_y(wx, z)
	aw.set_block(wx, wy + 1, z, Blocks.ids.water)
	var spread := func():
		for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			for dy in [0, 1]:
				var id: int = bw.get_block(wx + o.x, wy + dy, z + o.y)
				if id > 0 and Blocks.liquid[id]:
					return true
		return false
	check(await until(spread, 10.0), "a água que A pôs flui no servidor e B vê o fluxo")

	# Jogadores: A anda, B vê o boneco com o nome
	var a_id: int = an.multiplayer.get_unique_id()
	check(await until(func(): return bn.puppets.has(a_id) and an.puppets.size() == 1), "cada um vê o boneco do outro")
	var pa: Node3D = a.get_node("Player")
	pa.position += Vector3(4, 2, 0)
	check(await until(func(): return bn.puppets[a_id].visible and bn.puppets[a_id].position.distance_to(pa.position) < 0.5), "A anda → B vê o boneco chegar lá")
	check(bn.puppets[a_id].get_child(-1) is Label3D and bn.puppets[a_id].get_child(-1).text == "A", "nome em cima do boneco")
	pa.inv.equip[0] = Items.ids.get("copper_helmet", 0)
	check(await until(func(): return bn.puppets[a_id].inv.equip[0] == pa.inv.equip[0]), "armadura de A aparece no boneco em B")

	# M4a: inimigo do servidor fere o jogador (RPC hurt ao dono; a vida é do cliente)
	var se: Node3D = srv.get_node("Entities")
	check(se.remotes.size() == 2 and se.player == null, "o servidor tem um alvo por jogador")
	var hp0: float = pa.hp
	var z0: Node3D = se.spawn_enemy(se.def_named("zombie"), sn.peers[a_id].body.position)
	check(await until(func(): return pa.hp < hp0), "zumbi do servidor encosta em A → a vida de A cai")
	se.remove_enemy(z0)

	# Relógio: o do servidor manda
	srv.get_node("DayNight").time = 500.0
	check(await until(func(): return absf(b.get_node("DayNight").time - 500.0) < 5.0), "B segue a hora do servidor")

	# Versão diferente é recusada
	sn.version = "outra"
	var c := client("C")
	check(await until(func(): return not c.get_node("Net").waiting and c.get_node("Net").multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED), "versão diferente: recusado")
	c.queue_free()

	a.queue_free()
	check(await until(func(): return bn.puppets.is_empty()), "A sai → o boneco some em B")
	b.queue_free()
	srv.queue_free()
	await process_frame
	await process_frame
	print("net: ", "OK" if failures == 0 else "%d falhas" % failures)
	quit(1 if failures else 0)
