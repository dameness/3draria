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


func client(nick: String, secret := "", pass_ := "amigos") -> Node3D:
	var m: Node3D = load("res://game.tscn").instantiate()
	m.name = nick
	var n: Node = m.get_node("Net")
	n.address = "ws://127.0.0.1:%d" % PORT
	n.nick = nick
	n.secret = secret if secret != "" else "pw_" + nick
	n.password = pass_
	root.add_child(m)
	return m


func wipe(dir: String) -> void:   # apaga a pasta do teste (arquivos e subpastas)
	if not DirAccess.dir_exists_absolute(dir):
		return
	for d in DirAccess.get_directories_at(dir):
		wipe(dir + d + "/")
		DirAccess.remove_absolute(dir + d)
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir + f)


func _run() -> void:
	await process_frame   # a árvore só aceita cenas depois do primeiro quadro
	var Net_: GDScript = load("res://scripts/net.gd")
	Net_.root = "user://test_srv/"   # contas e cópias do servidor de teste (apagadas aqui e no fim)
	wipe(Net_.root)
	var world_file := "user://test_srv/mundo.wld"
	var srv: Node3D = load("res://server.tscn").instantiate()
	root.add_child(srv)
	var sw: Node3D = srv.get_node("World")
	var sn: Node = srv.get_node("Net")
	sw.set_seed(7)
	sn.password = "amigos"
	sn.key = world_file.get_file()
	srv.path = world_file
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
	var zid: int = z0.net_id
	check(await until(func(): return an.foes.has(zid) and bn.foes.has(zid)), "A e B veem o boneco do zumbi")
	check(a.get_node("Entities").enemies.all(func(e): return e.puppet) and b.get_node("Entities").enemies.all(func(e): return e.puppet), "cliente não faz nascer inimigo")
	var life: int = z0.hp
	an.foes[zid].hurt(20, Vector3.FORWARD, 0.0)
	check(await until(func(): return z0.hp < life and an.foes[zid].hp == z0.hp and bn.foes[zid].hp == z0.hp), "A bate → a vida cai no servidor e nos dois")
	var pb: Node3D = b.get_node("Player")
	var b_id: int = bn.multiplayer.get_unique_id()
	pa.position.x += 40.0
	pb.position = z0.position
	check(await until(func(): return z0.chase == sn.peers[b_id].body), "B chega perto e A se afasta → o zumbi troca de alvo")
	bn.foes[zid].hurt(999, Vector3.FORWARD, 0.0)
	check(await until(func(): return not sn.foes.has(zid) and not an.foes.has(zid) and not bn.foes.has(zid)), "B mata → some no servidor e nos dois")

	check(await until(func(): return an.drops.size() == sn.drops.size() and bn.drops.size() == sn.drops.size(), 5.0), "os drops do zumbi (se houver) são os do servidor, iguais nos dois")

	# Itens no chão: nascem no servidor; o primeiro pedido leva
	var gel: int = Items.ids.gel
	var gd: Node3D = sn.get_parent().get_node("Entities").spawn_drop(gel, 5, sn.peers[b_id].body.position + Vector3(20, 3, 0))
	var gid: int = gd.net_id
	check(await until(func(): return an.drops.has(gid) and bn.drops.has(gid)), "item do servidor aparece nos dois")
	var had: int = pa.inv.total(gel) + pb.inv.total(gel)
	an.grab.rpc_id(1, gid)
	bn.grab.rpc_id(1, gid)
	check(await until(func(): return pa.inv.total(gel) + pb.inv.total(gel) == had + 5 and not an.drops.has(gid) and not bn.drops.has(gid)), "dois pedidos juntos: um só leva, some nos dois")
	await process_frame
	check(pa.inv.total(gel) + pb.inv.total(gel) == had + 5 and not sn.drops.has(gid), "nada duplicado")
	pb.inv.add(Items.ids.wood, 3)
	var wood0: int = pb.inv.total(Items.ids.wood)
	pb.throw_drop(Items.ids.wood, 3)
	check(await until(func(): return sn.drops.values().any(func(d): return d.item == Items.ids.wood) and an.drops.values().any(func(d): return d.item == Items.ids.wood)), "B joga madeira → nasce no servidor e A vê")
	var ndrops: int = sn.drops.size()
	pb.position = sn.drops.values().filter(func(d): return d.item == Items.ids.wood)[0].position
	check(await until(func(): return sn.drops.size() < ndrops and pb.inv.total(Items.ids.wood) == wood0 + 3), "B encosta → pede e recolhe")

	# Projéteis: o de A só voa em B (cópia); o do inimigo é simulado no servidor e fere A pelo hurt
	var is_copy := func(n: Node, what: String): return n is Projectile and n.puppet and n.def.name == what
	a.get_node("Entities").spawn_projectile("wooden_arrow", pa.eye(), Vector3.UP, 20.0, 5, 0.0)
	check(await until(func(): return b.get_node("Entities").get_children().any(is_copy.bind("wooden_arrow"))), "flecha de A aparece em B (só o voo)")
	var hp1: float = pa.hp
	await create_timer(0.8).timeout   # fora dos quadros de invencibilidade
	se.spawn_projectile("stinger", sn.peers[a_id].body.position + Vector3.UP * 4.0, Vector3.DOWN, 12.0, 30, 0.0)
	check(await until(func(): return a.get_node("Entities").get_children().any(is_copy.bind("stinger"))), "ferrão do servidor aparece em A")
	check(await until(func(): return pa.hp < hp1), "o ferrão (simulado no servidor) fere A")

	# M4b: chefe invocado por A nasce no servidor; os dois veem o boneco, a barra e a mensagem
	a.get_node("Entities").summon("king_slime", pa)
	check(await until(func(): return se.boss != null and se.boss.def.name == "king_slime"), "A invoca → o chefe nasce no servidor")
	var ae: Node3D = a.get_node("Entities")
	var be: Node3D = b.get_node("Entities")
	check(await until(func(): return ae.boss != null and be.boss != null and be.boss_max == se.boss_max and be.boss_life() > 0), "A e B veem o chefe com a barra de vida")
	check(pb.message.contains("despertou"), "B recebe a mensagem do chefe")
	ae.summon("king_slime", pa)
	check(await until(func(): return pa.message == "já há um chefe"), "segundo chefe: recusado")
	se.clear_enemies()
	# Flags do mundo e hardmode
	sw.eoc_down = true
	sw.npcs["merchant"] = true
	check(await until(func(): return aw.eoc_down and bw.npcs.has("merchant")), "flags do mundo chegam aos dois")
	sw.start_hardmode()
	check(await until(func(): return aw.hardmode and bw.hardmode), "hardmode chega aos dois")
	# Orbe quebrado por A: o servidor conta (e solta o prêmio); lápide de A aparece em B; bala no inventário de A traz o Arms Dealer
	ae.orb_broken(Blocks.ids.shadow_orb, pa.position)
	check(await until(func(): return sw.orbs_broken == 1 and bw.orbs_broken == 1 and aw.orbs_broken == 1), "orbe: o servidor conta e a flag volta aos dois")
	pa.char_name = "A"
	pa.leave_tombstone()
	check(await until(func(): return bw.tombs.values().has("A morreu") and sw.tombs.values().has("A morreu")), "lápide de A: o texto chega ao servidor e a B")
	pa.inv.add(Items.ids.musket_ball, 10)
	check(await until(func(): return sw.npcs.has("arms_dealer") and bw.npcs.has("arms_dealer")), "bala com A → o Arms Dealer pode chegar (o servidor vê o inventário)")
	# Baú: um por vez; o que A guarda B vê
	var cp := Vector3i(x + 2, y + 1, z + 2)
	sw.set_block(cp.x, cp.y, cp.z, Blocks.ids.chest)
	check(await until(func(): return aw.get_block(cp.x, cp.y, cp.z) == Blocks.ids.chest), "baú chega a A")
	var ahud: Node = a.get_node("HUD")
	an.chest_ask.rpc_id(1, cp)
	check(await until(func(): return ahud.chest.get("pos") == cp and pa.inventory_open), "A abre o baú")
	bn.chest_ask.rpc_id(1, cp)
	check(await until(func(): return pb.message.contains("baú aberto")), "B não abre enquanto A está nele")
	ahud.chest.item[0] = Items.ids.gel
	ahud.chest.count[0] = 7
	pa.set_inventory(false)
	check(await until(func(): return bw.chests.has(cp) and bw.chests[cp].item[0] == Items.ids.gel and not sn.locks.has(cp)), "A fecha → destranca e B vê o gel")
	bn.chest_ask.rpc_id(1, cp)
	check(await until(func(): return b.get_node("HUD").chest.get("pos") == cp and b.get_node("HUD").chest.count[0] == 7), "B abre depois e acha o gel")
	pb.set_inventory(false)
	# Sono: a hora só acelera com todos dormindo
	var bed_a := Vector3i(x - 2, y + 1, z + 4)
	var bed_b := Vector3i(x + 2, y + 1, z + 4)
	sw.set_block(bed_a.x, bed_a.y, bed_a.z, Blocks.ids.bed)
	sw.set_block(bed_b.x, bed_b.y, bed_b.z, Blocks.ids.bed)
	check(await until(func(): return aw.get_block(bed_a.x, bed_a.y, bed_a.z) == Blocks.ids.bed and bw.get_block(bed_b.x, bed_b.y, bed_b.z) == Blocks.ids.bed), "camas chegam")
	pa.use_bed(bed_a)
	await create_timer(0.3).timeout
	check(pa.sleeping and srv.get_node("DayNight").speed == 1.0, "só A dormindo: a hora não acelera")
	pb.use_bed(bed_b)
	check(await until(func(): return srv.get_node("DayNight").speed > 1.0 and b.get_node("DayNight").speed > 1.0), "os dois dormindo: acelera (e chega aos clientes)")
	pa.wake_up()
	pb.wake_up()

	# Relógio: o do servidor manda
	srv.get_node("DayNight").time = 500.0
	check(await until(func(): return absf(b.get_node("DayNight").time - 500.0) < 5.0), "B segue a hora do servidor")

	# Contas: recusas (a versão, a senha do servidor, o nome repetido, a senha do personagem)
	sn.version = "outra"
	var c := client("C")
	var cq: Node3D = c.get_node("Player")
	check(await until(func(): return cq.message.contains("versão diferente")), "versão diferente: recusado")
	c.queue_free()
	sn.version = an.version
	c = client("C", "", "errada")
	cq = c.get_node("Player")
	check(await until(func(): return cq.message == "senha do servidor errada"), "senha do servidor errada: recusado")
	c.queue_free()
	c = client("a", "errada")   # (a conta A já está dentro; o nome conta sem maiúsculas)
	cq = c.get_node("Player")
	check(await until(func(): return cq.message == "senha do personagem errada") and sn.peers.has(a_id), "mesmo nome com a senha errada: recusado, e quem está dentro fica")
	c.queue_free()
	c = client("a/b")
	cq = c.get_node("Player")
	check(await until(func(): return cq.message == "nome inválido"), "nome que não vira arquivo: recusado")
	c.queue_free()
	check(FileAccess.file_exists("user://test_srv/players/a.plr") and not FileAccess.file_exists("user://test_srv/players/c.plr"), "a conta nasce no servidor (e só das entradas aceitas)")

	# Persistência: A muda inventário, mundo, cama e mapa; o servidor cai e sobe; A volta e acha tudo
	var rare: int = Items.ids.gold_bar
	pa.inv.add(rare, 7)
	pa.bed = Vector3i(x + 9, y + 1, z + 9)
	check(await until(func(): return sn.peers[a_id].acct.inv.any(func(e): return e[0] == "gold_bar" and e[1] >= 7), 12.0), "o inventário mudado vai sozinho ao servidor (5 s depois)")
	var mark := Vector3i(x + 2, y + 6, z)
	aw.set_block(mark.x, mark.y, mark.z, Blocks.ids.stone)
	aw.map_img.set_pixel(10, 10, Color("#ff8800"))
	aw.map_dirty = true
	await an.leave()
	check(an.pending == 0, "salvar e sair: o servidor confirmou")
	check(await until(func(): return sw.get_block(mark.x, mark.y, mark.z) == Blocks.ids.stone), "o bloco de A chegou ao servidor")
	a.queue_free()
	check(await until(func(): return bn.puppets.is_empty()), "A sai → o boneco some em B")
	b.queue_free()
	await process_frame
	srv.save()
	check(FileAccess.file_exists(world_file) and not DirAccess.get_directories_at("user://test_srv/backups/").is_empty(), "o servidor grava o mundo e a cópia do dia")
	srv.free()   # (cai sem avisar: tudo o que importa já está em disco)
	await process_frame
	await process_frame
	var srv2: Node3D = load("res://server.tscn").instantiate()
	root.add_child(srv2)
	var sn2: Node = srv2.get_node("Net")
	srv2.open(world_file)
	sn2.password = "amigos"
	check(sn2.host(PORT) == OK, "servidor sobe de novo")
	var a2 := client("A")
	var pa2: Node3D = a2.get_node("Player")
	check(await until(func(): return not a2.get_node("Net").waiting), "A volta e entra")
	check(pa2.inv.total(rare) >= 7 and a2.get_node("Net").char.beds.get(a2.get_node("Net").key) == Vector3i(x + 9, y + 1, z + 9), "o inventário e a cama de A voltam (a cama some no home() porque o quarto de teste não vale: igual a um jogador só)")
	check(srv2.get_node("World").get_block(mark.x, mark.y, mark.z) == Blocks.ids.stone and a2.get_node("World").get_block(mark.x, mark.y, mark.z) == Blocks.ids.stone, "o bloco de A voltou (servidor e cliente)")
	check(a2.get_node("World").map_img.get_pixel(10, 10).is_equal_approx(Color("#ff8800")) and a2.get_node("World").map_img.get_pixel(11, 10).a == 0.0, "o mapa de A volta")
	var a3 := client("A")   # a conexão antiga ficou presa (wifi caiu, aba recarregada): quem acerta a senha toma o lugar
	check(await until(func(): return not a3.get_node("Net").waiting) and sn2.peers.size() == 1, "A entra de novo com a senha certa: toma o lugar da sessão antiga")
	check(await until(func(): return pa2.message == "entrou de outro lugar"), "a sessão antiga é avisada e cortada")
	check(a3.get_node("Player").inv.total(rare) >= 7, "e o inventário é o mesmo")
	a2.queue_free()
	sn2.stale = 0.5
	a3.get_node("Net").process_mode = Node.PROCESS_MODE_DISABLED   # aba escondida: nada sai
	check(await until(func(): return sn2.peers.is_empty(), 8.0), "sem sinal: o servidor corta a conexão")
	a3.queue_free()
	var loaded: int = srv2.get_node("World").chunks.size()
	srv2.save()
	check(loaded > 0 and srv2.get_node("World").chunks.is_empty(), "sem ninguém por perto os chunks saem da memória do servidor na gravação")
	c = client("A", "outra senha")
	cq = c.get_node("Player")
	check(await until(func(): return cq.message == "senha do personagem errada"), "senha do personagem errada: recusado")
	c.queue_free()
	c = client("Novo", "x")   # conta nova: itens iniciais, e o nome com acento/espaço vira arquivo válido
	check(await until(func(): return not c.get_node("Net").waiting) and c.get_node("Player").inv.total(Items.ids.copper_pickaxe) == 1, "conta nova entra com os itens iniciais")
	c.queue_free()
	srv2.queue_free()
	wipe(Net_.root)
	DirAccess.remove_absolute(Net_.root.trim_suffix("/"))
	await process_frame
	await process_frame
	print("net: ", "OK" if failures == 0 else "%d falhas" % failures)
	quit(1 if failures else 0)
