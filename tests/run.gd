# Testes headless: .tools/godot --headless -s tests/run.gd
# Sai com código != 0 se algum check falhar.
extends SceneTree

const C := WorldGen.CHUNK
const H := WorldGen.HEIGHT
var failures := 0


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		printerr("FALHOU: ", msg)


func _init() -> void:
	check(ProjectSettings.get_setting("rendering/renderer/rendering_method") == "gl_compatibility", "renderer Compatibility")
	var m: Node = load("res://game.tscn").instantiate()
	check(m is Node3D, "game.tscn instancia um Node3D")
	m.free()
	Blocks.load_pack()
	Items.load_pack()
	Crafting.load_pack()
	# Erro de script aborta a função, que então retorna null em vez de true.
	for t in ["test_blocks", "test_atlas", "test_mesher", "test_gen", "test_raycast", "test_player", "test_items", "test_crafting", "test_mining", "test_day_night", "test_combat", "test_drops", "test_save", "test_wiki_sprites", "test_item_model", "test_projectiles", "test_progression", "test_boss", "test_armor", "test_enemy_models", "test_lighting", "test_visuals", "test_liquids", "test_ui", "test_cursor"]:
		check(call(t) == true, t + " terminou sem erro de script")
	# Integração: a cena principal monta todos os chunks no alcance usando as threads.
	main = load("res://game.tscn").instantiate()
	world = main.get_node("World")
	player = main.get_node("Player")
	root.add_child(main)
	started = Time.get_ticks_msec()


# Mundo de teste: 3x3 chunks com chão de pedra até y = 10 (topo em y = 11).
func floor_world() -> Node3D:
	var w: Node3D = load("res://scripts/world.gd").new()
	w.gen = WorldGen.new(1)
	for z in 3:
		for x in 3:
			var d := chunk(0)
			for i in C * C * 11:
				d[i] = Blocks.ids.stone
			w.chunks[Vector2i(x, z)] = d
	return w


func test_raycast():
	var w := floor_world()
	var hit: Dictionary = w.raycast(Vector3(20.5, 15.5, 20.5), Vector3.DOWN, 10)
	check(hit.get("pos") == Vector3i(20, 10, 20) and hit.get("normal") == Vector3i(0, 1, 0), "raio para baixo acerta o topo do chão")
	check(w.raycast(Vector3(20.5, 15.5, 20.5), Vector3.DOWN, 3).is_empty(), "raio curto não alcança")
	w.set_block(24, 12, 20, Blocks.ids.dirt)
	hit = w.raycast(Vector3(20.5, 12.5, 20.5), Vector3(1, 0.1, 0).normalized(), 10)
	check(hit.get("pos") == Vector3i(24, 12, 20) and hit.get("normal") == Vector3i(-1, 0, 0), "raio lateral acerta a face -X")
	check(w.get_block(24, 12, 20) == Blocks.ids.dirt, "set_block grava no chunk")
	w.set_block(16, 12, 20, Blocks.ids.dirt)
	check(w.versions.get(Vector2i(1, 1)) == 2 and w.versions.get(Vector2i(0, 1)) == 1, "editar a borda remonta o vizinho")
	w.free()
	return true


func test_player():
	var w := floor_world()
	var p: Node3D = load("res://scripts/player.gd").new()
	p.world = w
	p.position = Vector3(24.5, 15, 24.5)
	for i in 90:
		p.step(1.0 / 60, Vector3.ZERO, false)
	check(p.on_floor and absf(p.position.y - 11) < 0.01, "cai e para em cima do chão (y=%.3f)" % p.position.y)
	p.step(1.0 / 60, Vector3.ZERO, true)
	var peak := 0.0
	for i in 60:
		p.step(1.0 / 60, Vector3.ZERO, false)
		peak = maxf(peak, p.position.y - 11)
	check(peak > 1.1 and peak < 1.6 and p.on_floor, "pulo sobe ~1,4 bloco e volta ao chão (%.2f)" % peak)
	for y in [11, 12]:
		w.set_block(27, y, 24, Blocks.ids.dirt)
	for i in 60:
		p.step(1.0 / 60, Vector3(1, 0, 0), false)
	check(absf(p.position.x - (27 - 0.3)) < 0.01, "parede de 2 blocos para o jogador (x=%.3f)" % p.position.x)
	check(not p.overlaps_solid(p.position), "jogador nunca fica dentro de bloco")
	p.flying = true
	p.step(1.0, Vector3(1, 0, 0), false)
	check(p.position.x > 28, "voo atravessa blocos")
	p.free()
	w.free()
	return true


# Jogador + entidades fora da árvore de cena, sobre floor_world.
func make_player(w: Node3D) -> Node3D:
	var p: Node3D = load("res://scripts/player.gd").new()
	var ent: Node3D = load("res://scripts/entities.gd").new()
	var clock: Node = load("res://scripts/day_night.gd").new()
	p.world = w
	p.entities = ent
	p.clock = clock
	ent.world = w
	ent.player = p
	ent.clock = clock
	ent.load_defs()
	p.position = Vector3(24.5, 11, 24.5)
	p.spawn = p.position
	return p


func free_player(p: Node3D) -> void:
	p.entities.free()
	p.clock.free()
	p.free()


func enemy_def(n: String) -> Dictionary:
	var ent: Node3D = load("res://scripts/entities.gd").new()
	ent.load_defs()
	var d: Dictionary = ent.defs.filter(func(x): return x.name == n)[0]
	ent.free()
	return d


func run(node: Node, seconds: float) -> void:
	for i in int(seconds * 60):
		if not is_instance_valid(node) or node.is_queued_for_deletion():
			return
		node._physics_process(1.0 / 60)


func test_day_night():
	var c: Node = load("res://scripts/day_night.gd").new()
	c.time = 0
	check(c.clock() == "04:30" and is_equal_approx(c.light(), c.NIGHT_LIGHT), "amanhecer às 4:30, ainda escuro")
	c.time = 600
	check(not c.is_night() and c.light() == 1.0, "meio do dia claro")
	c.time = c.DAY_SECONDS
	check(c.is_night() and c.clock() == "19:30", "noite começa às 19:30")
	check(c.CYCLE == 24 * 60, "ciclo de 24 min")
	c.time = 0
	check(c.sun_dir().x > 0.9 and absf(c.sun_dir().y) < 0.01, "sol nasce a leste")
	c.time = c.DAY_SECONDS / 2
	check(c.sun_dir().y > 0.9, "sol a pino no meio do dia")
	c.time = c.DAY_SECONDS - 0.01
	check(c.sun_dir().x < -0.9, "sol se põe a oeste")
	c.time = c.DAY_SECONDS + c.NIGHT_SECONDS / 2
	check(c.sun_dir().y < -0.9, "sol sob o mundo à meia-noite (a lua fica do lado oposto)")
	c.free()
	return true


func test_combat():
	var w := floor_world()
	var p := make_player(w)
	var ent: Node3D = p.entities
	var z: Node3D = ent.spawn_enemy(enemy_def("zombie"), Vector3(26, 11, 24.5))
	z._ready()
	check(z.hurt(10, Vector3.RIGHT, 0) == 7, "defesa 6 reduz 10 de dano para 7")
	var sword: Dictionary = Items.defs[Items.ids.wooden_sword]
	var eye: Vector3 = p.position + Vector3.UP * p.EYE
	check(p.swing(sword, eye, Vector3.RIGHT) == 1, "espada acerta o zumbi à frente")
	check(p.swing(sword, eye, Vector3.LEFT) == 0, "espada não acerta atrás")
	z.position = Vector3(24.5, 11, 25.4)   # colado ao lado, na altura dos pés: o arco horizontal acerta mesmo com a mira reta
	check(p.swing(sword, eye, Vector3.FORWARD * -1) == 1 and p.swing(sword, eye, Vector3.FORWARD) == 0, "acerta o que está colado ao corpo (sem precisar olhar para baixo)")
	z.position = Vector3(26, 11, 24.5)
	p.slot = p.inv.item.find(Items.ids.copper_shortsword)
	var hp0: int = z.hp
	p.swing_item = Items.defs[Items.ids.copper_shortsword]
	p.swing_timer = 0.05
	check(z.hp == hp0, "o golpe ainda não acertou antes do impacto")
	var hp: int = z.hp
	p.inv.add(Items.ids.wooden_arrow, 2)
	p.shoot(Items.defs[Items.ids.wooden_bow], eye, Vector3.RIGHT)
	var arrow: Node = ent.get_children().back()
	run(arrow, 1.0)
	check(z.hp == hp - (4 + 5 - 3) and p.inv.total(Items.ids.wooden_arrow) == 1, "flecha gasta munição e fere com arco + flecha − defesa")
	run(z, 1.0)
	check(p.hp < p.MAX_HP, "zumbi anda até o jogador e causa dano ao encostar")
	var after: float = p.hp
	z._physics_process(1.0 / 60)
	check(p.hp == after, "invencibilidade após levar dano")
	ent.remove_enemy(z)
	var s: Node3D = ent.spawn_enemy(enemy_def("green_slime"), Vector3(32.5, 11, 24.5))
	s._ready()
	var d0: float = s.position.distance_to(p.position)
	run(s, 4.0)
	check(s.position.distance_to(p.position) < d0 - 2, "slime pula na direção do jogador")
	s.hurt(100, Vector3.RIGHT, 0)
	check(not ent.enemies.has(s) and ent.get_children().any(func(n): return n.get("item") == Items.ids.gel), "slime morto some e dropa gel")
	var e: Node3D = ent.spawn_enemy(enemy_def("demon_eye"), Vector3(24.5, 18, 34.5))
	e._ready()
	d0 = e.position.distance_to(p.position)
	run(e, 2.0)
	check(e.position.distance_to(p.position) < d0 - 3, "olho demoníaco voa até o jogador")
	p.iframes = 0
	p.hurt(1000, Vector3.RIGHT)
	check(p.hp == p.MAX_HP and p.position == p.spawn, "morrer renasce no spawn com vida cheia")
	free_player(p)
	w.free()
	return true


func test_drops():
	var w := floor_world()
	var p := make_player(w)
	var d: Node3D = p.entities.spawn_drop(Items.ids.dirt, 3, p.position + Vector3(2, 0.5, 0))
	d._ready()
	check(Items.rarity_color(Items.ids.dirt) == Color.WHITE, "raridade 0 = feixe branco")
	run(d, 2.0)
	check(p.inv.total(Items.ids.dirt) == 3 and d.is_queued_for_deletion(), "item solto é puxado e coletado")
	var far: Node3D = p.entities.spawn_drop(Items.ids.dirt, 1, p.position + Vector3(8, 3, 0))
	far._ready()
	run(far, 2.0)
	check(not far.is_queued_for_deletion() and absf(far.position.y - 11) < 0.01, "item longe cai e fica no chão")
	free_player(p)
	w.free()
	return true


func test_save():
	var saved_dirs := [SaveGame.players_dir, SaveGame.worlds_dir]
	SaveGame.players_dir = "user://test_players/"
	SaveGame.worlds_dir = "user://test_worlds/"
	for d in [SaveGame.players_dir, SaveGame.worlds_dir]:  # sobras de uma execução interrompida
		for f in DirAccess.get_files_at(d):
			DirAccess.remove_absolute(d + f)
	var pp := SaveGame.create_player("Ana")
	var wp := SaveGame.create_world("Mundo 1", 777)
	check(pp != "" and wp != "", "criar personagem e mundo")
	check(SaveGame.create_player("Ana") == "" and SaveGame.create_world("  ", 1) == "", "nome repetido ou vazio é recusado")
	check(SaveGame.list(SaveGame.players_dir).map(func(s): return s.name) == ["Ana"], "lista de personagens")
	check(SaveGame.list(SaveGame.worlds_dir)[0].info.seed == 777, "mundo guarda a seed")
	var w := floor_world()
	var p := make_player(w)
	check(not SaveGame.load_player(p, pp), "personagem novo: jogo dá os itens iniciais")
	w.set_block(20, 11, 20, Blocks.ids.dirt)
	p.inv.add(Items.ids.iron_pickaxe, 1)
	p.inv.add(Items.ids.stone, 42)
	p.hp = 37
	p.inv.add(Items.ids.iron_helmet, 1)
	p.inv.equip_from(p.inv.item.find(Items.ids.iron_helmet))
	p.spawn = Vector3(21.5, 11, 22.5)
	p.clock.time = 123.0
	check(SaveGame.save_world(w, p, p.clock, wp) == OK and SaveGame.save_player(p, pp) == OK, "salvar mundo e personagem")
	var w2: Node3D = load("res://scripts/world.gd").new()
	w2.gen = WorldGen.new(1)
	var p2 := make_player(w2)
	check(SaveGame.load_world(w2, p2, p2.clock, wp) and SaveGame.load_player(p2, pp), "carregar")
	check(w2.get_block(20, 11, 20) == Blocks.ids.dirt and w2.world_seed == w.world_seed, "bloco editado volta, seed do mundo")
	check(p2.inv.total(Items.ids.stone) == 42 and p2.inv.total(Items.ids.iron_pickaxe) == 1 and p2.hp == 37, "inventário e vida voltam")
	check(p2.inv.equip[0] == Items.ids.iron_helmet, "armadura vestida volta")
	check(p2.spawn == p.spawn and p2.clock.time == 123.0, "spawn e hora do mundo voltam")
	check(SaveGame.list(SaveGame.players_dir)[0].name == "Ana", "salvar mantém o nome")
	SaveGame.delete(pp)
	check(SaveGame.list(SaveGame.players_dir).is_empty(), "apagar personagem")
	for d in [SaveGame.players_dir, SaveGame.worlds_dir]:
		for f in DirAccess.get_files_at(d):
			DirAccess.remove_absolute(d + f)
	SaveGame.players_dir = saved_dirs[0]
	SaveGame.worlds_dir = saved_dirs[1]
	free_player(p)
	free_player(p2)
	w.free()
	w2.free()
	return true

# Sprites da wiki: com arquivo usa o recorte/ícone original; sem arquivo cai no procedural. Não depende de rede.
func test_wiki_sprites():
	var saved := Atlas.wiki_dir
	var plain := {}
	for k in Blocks.textures:
		var spec: Dictionary = Blocks.textures[k].duplicate()
		spec.erase("wiki")
		plain[k] = spec
	Atlas.wiki_dir = "user://sem_sprites/"
	check(Atlas.build(Blocks.textures).get_data() == Atlas.build(plain).get_data(), "sem sprites: atlas procedural")
	var dir := "user://wiki_test/"
	DirAccess.make_dir_recursive_absolute(dir)
	var placed := Image.create(48, 48, false, Image.FORMAT_RGBA8)
	placed.fill_rect(Rect2i(16, 16, 16, 16), Color.MAGENTA)
	placed.save_png(dir + "Dirt_Block_(placed).png")
	var pick := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	pick.save_png(dir + "Copper_Pickaxe.png")
	Atlas.wiki_dir = dir
	var tile: int = Blocks.textures.keys().find("dirt")
	check(Atlas.build(Blocks.textures).get_pixel(tile * 16 + 5, 5) == Color.MAGENTA, "com sprite: face = tile central do bloco colocado")
	Atlas.texture_cache.clear()
	var tex := Items.icon_texture(Items.ids.copper_pickaxe, null)
	check(tex.get_width() == 32, "ícone da wiki em tamanho original")
	check(Items.icon_texture(Items.ids.gel, null) is AtlasTexture, "sem sprite do item: ícone do atlas")
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir + f)
	Atlas.wiki_dir = saved
	Atlas.texture_cache.clear()
	return true


func test_projectiles():
	var w := floor_world()
	var p := make_player(w)
	var ent: Node3D = p.entities
	var eye: Vector3 = p.position + Vector3.UP * p.EYE
	var z1: Node3D = ent.spawn_enemy(enemy_def("zombie"), Vector3(32.5, 11, 24.5))
	z1._ready()
	check(p.swing(Items.defs[Items.ids.enchanted_sword], eye, Vector3.RIGHT) == 0, "zumbi longe está fora do alcance da lâmina")
	var beam: Node3D = ent.get_children().back()
	check(beam.def.name == "enchanted_beam", "Enchanted Sword dispara o feixe dos dados")
	run(beam, 1.0)
	check(z1.hp == 45 - (23 - 3), "feixe acerta longe com o dano da espada − defesa")
	z1.hp = 1000
	var z2: Node3D = ent.spawn_enemy(enemy_def("zombie"), Vector3(36.5, 11, 24.5))
	z2._ready()
	p.swing(Items.defs[Items.ids.terra_blade], eye, Vector3.RIGHT)
	var terra: Node3D = ent.get_children().back()
	run(terra, 1.0)
	check(z1.hp < 1000 and z2.hp < 45, "Terra Beam atravessa e acerta os dois zumbis")
	free_player(p)
	w.free()
	return true


func test_progression():
	var pairs := {"t1": ["copper_ore", "tin_ore"], "t2": ["iron_ore", "lead_ore"], "t3": ["silver_ore", "tungsten_ore"], "t4": ["gold_ore", "platinum_ore"]}
	var seen := {}
	for sd in 12:
		var names: Array = WorldGen.new(sd).ores.map(func(o): return Blocks.ids.keys()[o.block])
		for g in pairs:
			var chosen: Array = pairs[g].filter(func(n): return n in names)
			check(chosen.size() == 1, "seed %d: um minério do par %s" % [sd, g])
			for n in chosen:
				seen[n] = true
	check(seen.size() == 8, "as seeds alternam entre os dois minérios de cada par")
	var gen := WorldGen.new(3)
	var altar := false
	for c in 32:
		var d := gen.generate(c % 16, 5 + c / 16)
		var i := d.find(gen.ALTAR)
		if i != -1:
			var y := i / (C * C)
			altar = altar or (y > WorldGen.UNDERWORLD_TOP and y <= WorldGen.CAVERN_TOP and d[i - C * C] == gen.STONE)
	check(altar, "altar demoníaco no chão das cavernas")
	var w := floor_world()
	w.set_block(22, 11, 20, Blocks.ids.lead_anvil)
	check(Crafting.stations_near(w, Vector3(20.5, 11, 20.5)).has(Blocks.ids.anvil), "bigorna de chumbo vale como bigorna")
	w.free()
	var mines := func(pick: String, block: String): return Items.pick_power[Items.ids[pick]] >= Blocks.power[Blocks.ids[block]]
	check(not mines.call("silver_pickaxe", "demonite_ore") and mines.call("gold_pickaxe", "demonite_ore") and mines.call("platinum_pickaxe", "demonite_ore"), "demonita pede picareta de ouro/platina (55)")
	check(not mines.call("platinum_pickaxe", "hellstone"), "pedra infernal (65) fica para depois")
	return true


func test_boss():
	var w := floor_world()
	var p := make_player(w)
	var ent: Node3D = p.entities
	p.inv.add(Items.ids.suspicious_looking_eye, 2)
	p.slot = p.inv.item.find(Items.ids.suspicious_looking_eye)
	p.clock.time = 300
	p.use_item()
	check(ent.boss == null and p.message.contains("noite"), "invocar de dia não funciona")
	p.clock.time = p.clock.DAY_SECONDS + 60
	p.use_item()
	var boss: Node3D = ent.boss
	check(boss != null and p.inv.total(Items.ids.suspicious_looking_eye) == 1, "à noite o olho invoca o chefe e é gasto")
	p.use_item()
	check(ent.boss == boss and p.inv.total(Items.ids.suspicious_looking_eye) == 1, "só um chefe por vez")
	boss._ready()
	var fastest := 0.0
	for i in 60 * 8:
		boss._physics_process(1.0 / 60)
		fastest = maxf(fastest, boss.velocity.length())
	var servants: int = ent.enemies.filter(func(e): return e.def.name == "servant_of_cthulhu").size()
	check(servants >= 3 and fastest > 15, "fase 1: invoca servos (%d) e investe (%.0f blocos/s)" % [servants, fastest])
	check(boss.hurt(100, Vector3.RIGHT, 10) == 100 - 6 and boss.velocity.length() < 30, "defesa 12 e imune a knockback")
	boss.hp = 1300
	boss.think(1.0 / 60)
	check(boss.phase == 2 and boss.hurt(50, Vector3.RIGHT, 0) == 50 and boss.damage == 23, "fase 2 abaixo de 50%: defesa 0, dano 23")
	boss.hurt(5000, Vector3.RIGHT, 0)
	var drops: Array = ent.get_children().filter(func(n): return n.get("item") == Items.ids.demonite_ore)
	check(ent.boss == null and drops.size() == 1 and drops[0].count >= 30 and drops[0].count <= 90, "morto: dropa 30–90 de demonita")
	check(ent.get_children().any(func(n): return n.get("item") == Items.ids.unholy_arrow), "dropa Unholy Arrows")
	p.use_item()
	var b2: Node3D = ent.boss
	b2._ready()
	p.clock.time = 10  # amanheceu
	for i in 60 * 5:
		if ent.boss == null:
			break
		b2._physics_process(1.0 / 60)
	check(ent.boss == null, "ao amanhecer o chefe vai embora")
	# Arco usa qualquer flecha; Unholy Arrow atravessa vários inimigos.
	p.inv = Inventory.new()
	p.inv.add(Items.ids.unholy_arrow, 5)
	var eye: Vector3 = p.position + Vector3.UP * p.EYE
	p.shoot(Items.defs[Items.ids.wooden_bow], eye, Vector3.RIGHT)
	var arrow: Node3D = ent.get_children().back()
	check(arrow.def.name == "unholy_arrow" and p.inv.total(Items.ids.unholy_arrow) == 4, "arco atira Unholy Arrow")
	free_player(p)
	w.free()
	return true


func test_armor():
	var inv := Inventory.new()
	for n in ["copper_helmet", "copper_chainmail", "copper_greaves", "iron_helmet", "dirt"]:
		inv.add(Items.ids[n], 1)
	check(not inv.equip_from(4) and inv.equip == PackedInt32Array([-1, -1, -1]), "terra não é armadura")
	inv.equip_from(0)
	inv.equip_from(1)
	check(inv.defense() == 1 + 2, "defesa soma as peças (%d)" % inv.defense())
	inv.equip_from(2)
	check(inv.defense() == 1 + 2 + 1 + 2, "conjunto de cobre completo: +2 de bônus (%d)" % inv.defense())
	inv.equip_from(3)
	check(inv.equip[0] == Items.ids.iron_helmet and inv.item[3] == Items.ids.copper_helmet and inv.defense() == 2 + 2 + 1, "trocar capacete devolve o antigo e perde o bônus")
	inv.unequip(1)
	check(inv.equip[1] == -1 and inv.total(Items.ids.copper_chainmail) == 1, "tirar armadura volta ao inventário")
	var w := floor_world()
	var p := make_player(w)
	for n in ["gold_helmet", "gold_chainmail", "gold_greaves"]:
		p.inv.add(Items.ids[n], 1)
		p.inv.equip_from(p.inv.item.find(Items.ids[n]))
	check(p.inv.defense() == 4 + 5 + 4 + 3 and p.hurt(30, Vector3.RIGHT) == 30 - 8, "conjunto de ouro: defesa 16 reduz o dano em 8")
	free_player(p)
	w.free()
	return true


func test_enemy_models():
	var ent: Node3D = load("res://scripts/entities.gd").new()
	ent.load_defs()
	for d in ent.defs:
		var m := EnemyModel.build(d)
		check(m.find_children("", "MeshInstance3D", true, false).size() > 0 or m.get_node_or_null("Body") != null, "%s tem modelo 3D" % d.name)
		m.free()
	var eye := EnemyModel.build(ent.def_named("eye_of_cthulhu"))
	EnemyModel.set_phase(eye, 2)
	check(not eye.get_node("Look/Iris").visible and eye.get_node("Look/Mouth").visible, "fase 2: íris vira boca")
	eye.free()
	check(ent.def_named("zombie").model == "humanoid", "zumbi usa o corpo humanoide")
	var icon := Items.icon_texture(Items.ids.copper_pickaxe, ImageTexture.create_from_image(Atlas.build(Blocks.textures)))
	var small: Array = ItemModel.for_item(Items.ids.copper_pickaxe, icon, 0.4)
	var big: Array = ItemModel.for_item(Items.ids.copper_pickaxe, icon, 0.9)
	check(small[0] != big[0] and big[0].get_aabb().size.x > small[0].get_aabb().size.x, "modelo do item cacheado por tamanho")
	ent.free()
	return true


# Cor (luz) da face virada para `normal` do bloco em p, num build do mesher.
func face_light(arrays: Array, p: Vector3i, normal: Vector3) -> Color:
	var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var n: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var c: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	for i in range(0, v.size(), 4):
		var center := (v[i] + v[i + 2]) / 2
		if n[i] == normal and Vector3i((center - normal * 0.5).floor()) == p:
			return c[i]
	return Color(-1, -1, -1)


func test_lighting():
	var n := Blocks.textures.size()
	var Y := 60   # longe do brilho quente do submundo
	# Chão de pedra até y=Y com um teto 10 blocos acima sobre metade do chunk (caverna rasa).
	var d := chunk(0)
	for i in C * C * (Y + 1):
		d[i] = Blocks.ids.stone
	for z in C:
		for x in 8:
			d[x + z * C + (Y + 10) * C * C] = Blocks.ids.stone
	var nb := [d, d, d, d]
	var a := ChunkMesher.build(d, nb, n)
	var open_top := face_light(a, Vector3i(12, Y, 8), Vector3.UP)
	var under_roof := face_light(a, Vector3i(3, Y, 8), Vector3.UP)
	check(open_top.r > 0.9 and open_top.r <= 1.0, "chão a céu aberto: luz do céu quase cheia (%.2f; o tom varia por bloco)" % open_top.r)
	check(under_roof.r < 0.4 and under_roof.r > 0, "sob um teto 10 blocos acima: penumbra (%.2f)" % under_roof.r)
	check(open_top.g == 0, "sem tocha: sem luz de tocha")
	d[4 + 8 * C + (Y + 1) * C * C] = Blocks.ids.torch
	a = ChunkMesher.build(d, [d, d, d, d], n)
	var near := face_light(a, Vector3i(3, Y, 8), Vector3.UP)
	var far := face_light(a, Vector3i(0, Y, 0), Vector3.UP)
	check(near.g > 0.6 and near.g > far.g, "tocha ilumina perto (%.2f) mais que longe (%.2f)" % [near.g, far.g])
	check(Items.places[Items.ids.torch] == Blocks.ids.torch and not Blocks.solid[Blocks.ids.torch], "tocha é item que coloca bloco não sólido")
	check(Items.drop[Blocks.ids.torch] == Items.ids.torch, "quebrar tocha devolve a tocha")
	var w := floor_world()
	w.set_block(20, 11, 20, Blocks.ids.torch)
	check(w.raycast(Vector3(20.5, 15.5, 20.5), Vector3.DOWN, 10).get("pos") == Vector3i(20, 11, 20), "mira acerta a tocha")
	w.free()
	# Submundo: brilho quente de fundo sem tocha nenhuma.
	var low := chunk(0)
	for i in C * C * 11:
		low[i] = Blocks.ids.stone
	check(face_light(ChunkMesher.build(low, [low, low, low, low], n), Vector3i(8, 10, 8), Vector3.UP).g > 0.3, "submundo tem brilho quente de fundo")
	return true


# Cores dos 4 vértices da face virada para `normal` do bloco em p.
func face_corners(arrays: Array, p: Vector3i, normal: Vector3) -> Array:
	var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var nr: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var c: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	for i in range(0, v.size(), 4):
		if nr[i] == normal and Vector3i(((v[i] + v[i + 2]) / 2 - normal * 0.5).floor()) == p:
			return [c[i], c[i + 1], c[i + 2], c[i + 3]]
	return []


func test_cursor():
	var inv := Inventory.new()
	inv.add(Items.ids.dirt, 30)
	inv.add(Items.ids.stone, 5)
	inv.click(0)
	check(inv.cursor_id == Items.ids.dirt and inv.cursor_count == 30 and inv.item[0] == -1, "clique esquerdo pega a pilha inteira")
	inv.click(5)
	check(inv.cursor_id == -1 and inv.item[5] == Items.ids.dirt and inv.count[5] == 30, "clique em slot vazio solta a pilha")
	inv.right_click(5)
	inv.right_click(5)
	check(inv.cursor_count == 2 and inv.count[5] == 28, "clique direito pega 1 item de cada vez")
	inv.click(5)
	check(inv.cursor_id == -1 and inv.count[5] == 30, "soltar no mesmo item junta a pilha")
	inv.click(1)
	inv.click(5)
	check(inv.item[5] == Items.ids.stone and inv.cursor_id == Items.ids.dirt and inv.cursor_count == 30, "item diferente: troca com a mão")
	inv = Inventory.new()
	inv.item[0] = Items.ids.dirt
	inv.count[0] = 9990
	inv.item[1] = Items.ids.dirt
	inv.count[1] = 30
	inv.click(1)
	inv.click(0)
	check(inv.count[0] == 9999 and inv.cursor_count == 21, "junta só até o limite da pilha, o resto fica na mão")
	inv = Inventory.new()
	inv.add(Items.ids.iron_helmet, 1)
	inv.add(Items.ids.gold_helmet, 1)
	inv.click(0)
	inv.click_equip(1)
	check(inv.equip[1] == -1 and inv.cursor_id == Items.ids.iron_helmet, "capacete não entra no slot do corpo")
	inv.click_equip(0)
	check(inv.equip[0] == Items.ids.iron_helmet and inv.cursor_id == -1, "peça certa na mão veste")
	inv.click(1)
	inv.click_equip(0)
	check(inv.equip[0] == Items.ids.gold_helmet and inv.cursor_id == Items.ids.iron_helmet and inv.cursor_count == 1, "vestir por cima devolve a peça antiga à mão")
	inv.click(5)
	inv.click_equip(0)
	check(inv.equip[0] == -1 and inv.cursor_id == Items.ids.gold_helmet, "clicar na peça vestida com a mão vazia tira a peça para a mão")
	inv = Inventory.new()
	inv.add(Items.ids.dirt, 5)
	inv.add(Items.ids.stone, 7)
	inv.click(0)
	inv.click_trash()
	check(inv.trash_id == Items.ids.dirt and inv.trash_count == 5 and inv.cursor_id == -1, "lixeira recebe o item da mão")
	inv.click(1)
	inv.click_trash()
	check(inv.trash_id == Items.ids.stone and inv.trash_count == 7 and inv.total(Items.ids.dirt) == 0, "item novo na lixeira destrói o anterior")
	inv.click_trash()
	check(inv.cursor_id == Items.ids.stone and inv.trash_id == -1, "mão vazia recupera o que está na lixeira")
	check(inv.release_cursor() == 0 and inv.total(Items.ids.stone) == 7 and inv.cursor_id == -1, "fechar devolve o item da mão ao inventário")
	# Criar direto para a mão (só cabe se a mão está vazia ou já tem o mesmo item).
	var by_result := {}
	for r in Crafting.recipes:
		by_result[Items.names[r.result]] = r
	inv = Inventory.new()
	inv.add(Items.ids.wood, 25)
	check(Crafting.craft_to_cursor(by_result.workbench, inv, {}) and inv.cursor_id == Items.ids.workbench and inv.cursor_count == 1 and inv.total(Items.ids.wood) == 15, "criar pega o resultado na mão")
	check(Crafting.craft_to_cursor(by_result.workbench, inv, {}) and inv.cursor_count == 2, "criar de novo soma na mão")
	inv.cursor_id = Items.ids.dirt
	check(not Crafting.craft_to_cursor(by_result.workbench, inv, {}) and inv.total(Items.ids.wood) == 5, "mão ocupada por outro item: não cria")
	return true


func test_ui():
	var tip := Ui.item_tip(Items.ids.terra_blade)
	check(tip.begins_with("[color=#ffff0a]Terra Blade[/color]") and tip.contains("85 de dano") and tip.contains("Velocidade"), "dica do item: nome na cor da raridade e estatísticas")
	check(Ui.item_tip(Items.ids.copper_pickaxe).contains("35% de poder de picareta") and Ui.item_tip(Items.ids.gold_helmet).contains("4 de defesa"), "dica: picareta e armadura")
	check(Ui.heart().get_width() == 24 and Ui.heart().get_image().get_pixel(12, 9).a > 0.5 and Ui.heart().get_image().get_pixel(0, 0).a == 0.0, "coração procedural com fundo transparente")
	check(Ui.theme().get_constant("outline_size", "Label") > 0 and Ui.theme().get_default_font() != null, "tema: texto com contorno")
	var slot = load("res://scripts/hud.gd").Slot.new()
	var label = slot._make_custom_tooltip(tip)
	check(label is RichTextLabel and label.bbcode_enabled and label.text.contains("Terra Blade"), "slot mostra a dica em BBCode")
	label.free()
	slot.free()
	return true


func test_liquids():
	var w := floor_world()   # chão de pedra até y = 10
	for y in range(11, 17):
		for x in range(20, 25):
			for z in range(20, 25):
				w.set_block(x, y, z, Blocks.ids.water)
	var p := make_player(w)
	p.position = Vector3(22.5, 15, 22.5)
	check(p.liquid_at() == Blocks.ids.water, "corpo dentro d'água é detectado")
	for i in 20:
		p.step(1.0 / 60, Vector3.ZERO, false)
	check(p.velocity.y > -p.SWIM_SINK - 0.01 and p.velocity.y < 0 and p.position.y < 15, "na água afunda devagar (%.2f)" % p.velocity.y)
	var y0: float = p.position.y
	for i in 30:
		p.step(1.0 / 60, Vector3.ZERO, true)
	check(p.position.y > y0 + 1.0, "Espaço sobe na água")
	p.velocity = Vector3.ZERO
	p.position = Vector3(22.5, 11, 22.5)
	var x0: float = p.position.x
	p.step(1.0 / 60, Vector3.RIGHT, false)
	var wet: float = p.position.x - x0
	p.position = Vector3(30.5, 11, 30.5)
	x0 = p.position.x
	p.step(1.0 / 60, Vector3.RIGHT, false)
	check(wet < p.position.x - x0, "na água anda mais devagar")
	# Lava: queima uma vez por golpe (invencibilidade entre um e outro).
	for y in range(11, 14):
		for x in range(28, 33):
			for z in range(28, 33):
				w.set_block(x, y, z, Blocks.ids.lava)
	p.position = Vector3(30.5, 11, 30.5)
	p.velocity = Vector3.ZERO
	p.hp = 100
	p.step(1.0 / 60, Vector3.ZERO, false)
	check(p.hp == 100 - p.LAVA_DAMAGE and p.iframes > 0, "lava tira %d de vida (%d)" % [p.LAVA_DAMAGE, p.hp])
	p.step(1.0 / 60, Vector3.ZERO, false)
	check(p.hp == 100 - p.LAVA_DAMAGE, "lava não fere de novo durante a invencibilidade")
	free_player(p)
	w.free()
	return true


func test_visuals():
	var n := Blocks.textures.size()
	var Y := 60
	var d := chunk(0)
	for i in C * C * (Y + 1):
		d[i] = Blocks.ids.stone
	var flat := face_corners(ChunkMesher.build(d, [d, d, d, d], n), Vector3i(8, Y, 8), Vector3.UP)
	check(flat.size() == 4 and flat.all(func(c): return is_equal_approx(c.r, flat[0].r)), "chão plano: os 4 cantos com a mesma luz")
	d[9 + 8 * C + (Y + 1) * C * C] = Blocks.ids.stone   # degrau ao lado (+X)
	var a := ChunkMesher.build(d, [d, d, d, d], n)
	var corners := face_corners(a, Vector3i(8, Y, 8), Vector3.UP)
	var lights: Array = corners.map(func(c): return c.r)
	check(lights.min() < lights.max() * 0.9, "oclusão ambiente: o canto junto da parede escurece (%.2f a %.2f)" % [lights.min(), lights.max()])
	# Planta: dois quadros em cruz, frente e verso; b = 0.5 (o shader balança a ponta); a mira e a colocação a atravessam.
	var p := chunk(0)
	for i in C * C * (Y + 1):
		p[i] = Blocks.ids.stone
	p[8 + 8 * C + (Y + 1) * C * C] = Blocks.ids.grass_tuft
	var pa := ChunkMesher.build(p, [p, p, p, p], n)
	check(faces(pa) == C * C + 4 and Array(pa[Mesh.ARRAY_COLOR]).filter(func(c): return is_equal_approx(c.b, 0.5)).size() == 16, "planta: 4 quadros com b = 0.5")
	# Água: só onde toca ar (superfície à parte), um pouco abaixo do topo; lava vai na superfície opaca com b = 1.
	var w := chunk(0)
	for i in C * C * (Y + 1):
		w[i] = Blocks.ids.stone
	w[8 + 8 * C + (Y + 1) * C * C] = Blocks.ids.water
	w[4 + 4 * C + (Y + 1) * C * C] = Blocks.ids.lava
	var water: Array = []
	var wa := ChunkMesher.build(w, [w, w, w, w], n, water)
	var wy: PackedVector3Array = water[Mesh.ARRAY_VERTEX]
	check(not water.is_empty() and wy.size() == 5 * 4, "água: 5 faces (sem a de baixo, que toca pedra)")
	var top_y := 0.0
	for v in wy:
		top_y = maxf(top_y, v.y)
	check(is_equal_approx(top_y, Y + 1 + ChunkMesher.LIQUID_TOP), "água: superfície abaixo do topo do bloco (%.2f)" % top_y)
	check(Array(wa[Mesh.ARRAY_COLOR]).any(func(c): return is_equal_approx(c.b, 1.0)), "lava brilha (b = 1) na superfície opaca")
	# Mundo: mira atravessa planta e líquido; bloco novo substitui; planta sem chão some.
	var wd := floor_world()
	wd.set_block(20, 11, 20, Blocks.ids.grass_tuft)
	wd.set_block(20, 12, 20, Blocks.ids.water)
	check(wd.raycast(Vector3(20.5, 16.5, 20.5), Vector3.DOWN, 10).get("pos") == Vector3i(20, 10, 20), "mira atravessa água e planta")
	wd.set_block(20, 11, 20, Blocks.ids.grass_tuft)
	wd.set_block(20, 10, 20, 0)
	check(wd.get_block(20, 11, 20) == 0, "quebrar o chão remove a planta em cima")
	wd.free()
	return true


func quads(mesh: ArrayMesh) -> int:
	return mesh.surface_get_array_len(0) / 4


func test_item_model():
	var plus := Image.create(3, 3, false, Image.FORMAT_RGBA8)
	for p in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1), Vector2i(1, 2)]:
		plus.set_pixel(p.x, p.y, Color.RED)
	var mesh := ItemModel.build(plus, 1.0)
	check(quads(mesh) == 2 + 12, "extrusão: frente + verso + só as 12 bordas expostas (%d)" % quads(mesh))
	var a := mesh.surface_get_arrays(0)
	var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var nr: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
	var ix: PackedInt32Array = a[Mesh.ARRAY_INDEX]
	var wound := true
	for t in range(0, ix.size(), 3):
		wound = wound and (v[ix[t + 1]] - v[ix[t]]).cross(v[ix[t + 2]] - v[ix[t]]).dot(nr[ix[t]]) < 0
	check(wound, "extrusão: todas as faces viradas para fora")
	check(is_equal_approx(mesh.get_aabb().size.x, 1.0) and mesh.get_aabb().position == Vector3(0, 0, mesh.get_aabb().position.z), "extrusão: lado maior = comprimento, origem no canto inferior esquerdo")
	var icon := Items.icon_texture(Items.ids.copper_pickaxe, ImageTexture.create_from_image(Atlas.build(Blocks.textures)))
	check(quads(ItemModel.build(icon.get_image(), 0.5)) > 10, "ícone real vira malha 3D")
	var H = load("res://scripts/held_item.gd")
	check(H.style(Items.ids.copper_shortsword) == "thrust" and H.style(Items.ids.wooden_bow) == "shoot", "estilo: espada curta estoca, arco atira")
	check(H.style(Items.ids.copper_pickaxe) == "swing" and H.style(Items.ids.dirt) == "hold", "estilo: picareta golpeia, bloco só segura")
	check(H.pose("swing", 0) != H.pose("swing", 0.5) and H.pose("swing", 1).origin == H.REST, "golpe anima e volta à mão")
	check(H.pose("hold", 0.3) == Transform3D(Basis(), H.REST), "segurar não anima")
	Atlas.texture_cache.clear()
	return true


func test_items():
	check(Items.places[Items.ids.stone] == Blocks.ids.stone, "bloco vira item que o coloca")
	check(Items.drop[Blocks.ids.grass] == Items.ids.dirt, "grama dropa terra")
	check(Items.drop[Blocks.ids.leaves] == -1 and Items.drop[Blocks.ids.bedrock] == -1, "folha e bedrock não dropam")
	check([Items.pick_power[Items.ids.copper_pickaxe], Items.pick_power[Items.ids.iron_pickaxe], Items.pick_power[Items.ids.gold_pickaxe]] == [35, 40, 55], "poder das picaretas como no Terraria (35/40/55)")
	var inv := Inventory.new()
	check(inv.add(Items.ids.dirt, 15000) == 0 and inv.item[0] == Items.ids.dirt and inv.count[0] == 9999 and inv.count[1] == 5001, "empilha até o limite")
	check(inv.add(Items.ids.copper_pickaxe, 2) == 0 and inv.count[2] == 1 and inv.count[3] == 1, "picareta não empilha")
	inv.remove(Items.ids.dirt, 6000)
	check(inv.total(Items.ids.dirt) == 9000, "remove tira a quantidade certa")
	check(inv.add(Items.ids.stone, 9999 * Inventory.SIZE) > 0, "inventário cheio devolve o que sobrou")
	return true


func test_crafting():
	var by_result := {}
	for r in Crafting.recipes:
		by_result[Items.names[r.result]] = r
	var inv := Inventory.new()
	inv.add(Items.ids.wood, 20)
	check(Crafting.craft(by_result.workbench, inv, {}), "bancada sem estação")
	check(inv.total(Items.ids.wood) == 10 and inv.total(Items.ids.workbench) == 1, "criar consome ingredientes e dá o item")
	inv.add(Items.ids.stone, 20)
	inv.add(Items.ids.gel, 1)
	check(Crafting.craft(by_result.torch, inv, {}) and inv.total(Items.ids.torch) == 3, "tocha: 1 gel + 1 madeira = 3")
	inv.add(Items.ids.wood, 1)
	check(not Crafting.craft(by_result.furnace, inv, {}), "fornalha exige bancada por perto")
	var w := floor_world()
	w.set_block(22, 11, 20, Blocks.ids.workbench)
	var st := Crafting.stations_near(w, Vector3(20.5, 11, 20.5))
	check(st.has(Blocks.ids.workbench) and Crafting.craft(by_result.furnace, inv, st), "bancada no mundo libera a fornalha")
	check(Crafting.stations_near(w, Vector3(30.5, 11, 20.5)).is_empty(), "estação longe não conta")
	w.free()
	# Cadeia completa até a picareta de ferro.
	inv.add(Items.ids.iron_ore, 51)
	inv.add(Items.ids.wood, 3)
	var all := {Blocks.ids.workbench: true, Blocks.ids.furnace: true, Blocks.ids.anvil: true}
	for i in 15:
		Crafting.craft(by_result.iron_bar, inv, all)
	check(Crafting.craft(by_result.anvil, inv, all) and Crafting.craft(by_result.iron_pickaxe, inv, all), "minério → barra → bigorna → picareta de ferro")
	return true


func test_mining():
	var w := floor_world()
	var p := make_player(w)
	p.target = {"pos": Vector3i(20, 10, 20), "normal": Vector3i(0, 1, 0)}
	w.set_block(20, 10, 20, Blocks.ids.gold_ore)
	# Ouro não tem tier no Terraria; o teste dá poder 40 a ele só para exercitar o bloqueio.
	var saved_power := Blocks.power[Blocks.ids.gold_ore]
	Blocks.power[Blocks.ids.gold_ore] = 40
	p.break_target()
	check(w.get_block(20, 10, 20) == Blocks.ids.gold_ore, "sem picareta não minera")
	p.inv.add(Items.ids.copper_pickaxe, 1)
	p.break_target()
	check(w.get_block(20, 10, 20) == Blocks.ids.gold_ore and p.message.contains("40"), "cobre não minera ouro e avisa o poder")
	p.inv.add(Items.ids.iron_pickaxe, 1)
	p.slot = 1
	p.break_target()
	var drops: Array = p.entities.get_children().filter(func(n): return n.get("item") == Items.ids.gold_ore)
	check(w.get_block(20, 10, 20) == 0 and drops.size() == 1, "ferro minera ouro e o drop cai no chão")
	p.inv.add(Items.ids.gold_ore, 1)
	p.slot = 2
	p.target = {"pos": Vector3i(20, 10, 21), "normal": Vector3i(0, 1, 0)}
	p.position = Vector3(25.5, 11, 25.5)
	p.place_target()
	check(w.get_block(20, 11, 21) == Blocks.ids.gold_ore and p.inv.total(Items.ids.gold_ore) == 0, "colocar usa o item da mão")
	Blocks.power[Blocks.ids.gold_ore] = saved_power
	free_player(p)
	w.free()
	return true


var main: Node
var world: Node3D
var player: Node3D
var started := 0
var phase := 0
var edit_chunk := Vector2i.ZERO
var edit_mesh_id := 0
var edit_faces := 0


func _process(_delta: float) -> bool:
	var done = integration()
	if done == null:
		check(false, "integração terminou sem erro de script")
	elif not done:
		return false
	main.free()
	print("OK" if failures == 0 else "%d falha(s)" % failures)
	quit(1 if failures else 0)
	return true


# Retorna false enquanto espera, true quando terminou (null se der erro de script).
# Fases: 0 carrega o mundo e quebra o bloco sob o jogador; 1 espera a mesh nova e o drop; 2 efeitos na mão.
func integration():
	var elapsed := Time.get_ticks_msec() - started
	if world == null:
		check(false, "cena principal não carregou")
		return true
	if elapsed > 60000:
		check(false, "integração parou na fase %d (60 s)" % phase)
		return true
	if world.center.x < 0 or not world.is_idle():
		return false
	var hand: Node3D = player.get_node("Camera/Hand")
	match phase:
		0:
			var r: int = world.render_distance
			var expected := 0
			for z in range(world.center.y - r, world.center.y + r + 1):
				for x in range(world.center.x - r, world.center.x + r + 1):
					var k := Vector2i(x, z)
					expected += int(world.in_world(k) and (k - world.center).length_squared() <= r * r)
			check(world.meshes.size() == expected, "mundo: %d de %d chunks montados" % [world.meshes.size(), expected])
			var with_mesh: int = world.meshes.values().filter(func(m): return m != null).size()
			check(with_mesh == expected, "todo chunk no alcance tem faces visíveis")
			print("mundo: %d chunks em %d ms com %d threads" % [expected, elapsed, world.max_jobs])
			check(player.on_floor, "jogador nasce e fica no chão")
			check(hand.mesh.visible and hand.mesh.mesh != null, "picareta aparece em 3D na mão")
			var k: Vector2i = world.center
			edit_mesh_id = world.meshes[k].get_instance_id()
			edit_faces = world.meshes[k].mesh.surface_get_array_len(0)
			player.cam.rotation.x = -PI / 2
			player._process(0)
			var below := Vector3i(player.position.floor()) - Vector3i(0, 1, 0)
			check(player.target.get("pos") == below, "mira olhando para baixo acerta o bloco sob os pés")
			player.break_target()
			check(world.get_block(below.x, below.y, below.z) == 0, "quebrar tira o bloco com a picareta inicial")
			var closed: CanvasLayer = main.get_node("HUD")
			check(closed.slots[0].visible and not closed.slots[Inventory.HOTBAR].visible and not closed.craft_root.visible and not closed.equip_root.visible and not closed.trash_slot.visible, "inventário fechado: só a hotbar aparece")
			player.inventory_open = true  # exercita a janela de inventário/criação
			edit_chunk = k
			phase = 1
		1:
			if player.inv.total(Items.ids.dirt) == 0:
				return false  # espera o drop de terra ser coletado
			var m: MeshInstance3D = world.meshes.get(edit_chunk)
			check(m != null and m.get_instance_id() != edit_mesh_id and m.mesh.surface_get_array_len(0) != edit_faces, "mesh do chunk editado foi refeita")
			var hud: CanvasLayer = main.get_node("HUD")
			check(hud.hearts.size() == 5 and hud.slots.size() == Inventory.SIZE and hud.slots[Inventory.HOTBAR].visible and hud.craft_root.visible and hud.equip_root.visible, "HUD: corações, hotbar + 4 fileiras, criação e equipamento ao abrir")
			hud.show_all = true
			hud.shown_version = -1
			hud._process(0.0)
			check(hud.craft_list.get_child_count() == Crafting.recipes.size(), "criação com 'Todas' lista as %d receitas" % Crafting.recipes.size())
			var click := InputEventMouseButton.new()
			click.button_index = MOUSE_BUTTON_LEFT
			click.pressed = true
			var first: int = player.inv.item[0]
			hud.slots[0].gui_input.emit(click)
			hud._process(0.0)
			check(player.inv.cursor_id == first and hud.cursor_view.visible and player.inv.item[0] == -1, "clicar no slot pega o item para o cursor (visível na tela)")
			hud.slots[Inventory.HOTBAR + 1].gui_input.emit(click)
			check(player.inv.item[Inventory.HOTBAR + 1] == first and player.inv.cursor_id == -1, "clicar em outro slot solta o item")
			hud.slots[Inventory.HOTBAR + 1].gui_input.emit(click)
			hud.slots[0].gui_input.emit(click)
			check(player.inv.item[0] == first, "e volta ao lugar")
			check(hud.life_label.text == "Vida: 100/100" and hud.get_node_or_null("Info") == null, "HUD novo mostra a vida")
			player.inv.add(Items.ids.terra_blade, 1)
			player.slot = player.inv.item.find(Items.ids.terra_blade)
			phase = 2
		2:
			player.cooldown = 0.3
			hand._process(0)
			hand._process(0)
			check(hand.glow != null and hand.sparks != null and hand.trail_points.size() >= 2, "Terra Blade na mão com brilho, faíscas e rastro (%s %s %d)" % [hand.glow, hand.sparks, hand.trail_points.size()])
			player.cooldown = 0
			player.third_person = true
			player.flying = true
			player.position += Vector3.UP * 20  # céu aberto: nada entre a cabeça e a câmera
			player._process(0)
			var model: Node3D = player.get_node("Model")
			check(player.cam.position.distance_to(Vector3(0, player.EYE, 0)) > 3.5 and model.visible and not hand.visible, "V: 3ª pessoa afasta a câmera e mostra o corpo")
			player.third_person = false
			player._process(0)
			check(player.cam.position == Vector3(0, player.EYE, 0) and not model.visible, "V de novo: volta à 1ª pessoa")
			player.set_menu(true)
			check(main.get_tree().paused and player.menu_open, "Esc: pausa de verdade (a árvore para)")
			var esc := InputEventAction.new()
			esc.action = "ui_cancel"
			esc.pressed = true
			main.get_node("HUD")._unhandled_input(esc)
			check(not main.get_tree().paused and not player.menu_open, "Esc de novo: o HUD despausa")
			return true
	return false


func test_blocks():
	check(Blocks.ids.air == 0 and not Blocks.solid[0], "id 0 é ar")
	check(Blocks.tiles.size() == Blocks.ids.size() * Blocks.FACES, "6 tiles por bloco")
	var g: int = Blocks.ids.grass
	check(Blocks.tiles[g * 6 + 2] != Blocks.tiles[g * 6 + 0], "grama: topo difere do lado")
	return true


func test_atlas():
	var img := Atlas.build(Blocks.textures)
	check(img.get_size() == Vector2i(16 * Blocks.textures.size(), 16), "atlas: uma fileira de tiles 16x16")
	DirAccess.make_dir_recursive_absolute("res://textures")
	check(img.save_png("res://textures/atlas.png") == OK, "atlas salvo em textures/atlas.png")
	return true


func chunk(fill: int) -> PackedByteArray:
	var d := PackedByteArray()
	d.resize(C * C * H)
	d.fill(fill)
	return d


func faces(arrays: Array) -> int:
	return 0 if arrays.is_empty() else arrays[Mesh.ARRAY_VERTEX].size() / 4


func test_mesher():
	var n := Blocks.textures.size()
	var stone := chunk(Blocks.ids.stone)
	check(faces(ChunkMesher.build(stone, [stone, stone, stone, stone], n)) == C * C, "chunk sólido cercado: só as 256 faces do topo")
	check(faces(ChunkMesher.build(stone, [PackedByteArray(), stone, stone, stone], n)) == C * C + C * H, "borda do mundo mostra a parede")
	var air := chunk(0)
	var nb := [air, air, air, air]
	check(ChunkMesher.build(air, nb, n).is_empty(), "chunk vazio não gera mesh")
	air[3 + 4 * C + 10 * C * C] = Blocks.ids.dirt
	var a := ChunkMesher.build(air, nb, n)
	check(faces(a) == 6, "bloco isolado: 6 faces")
	# Godot desenha a frente dos triângulos em sentido horário: cross(v1-v0, v2-v0) aponta para dentro.
	var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var nr: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
	var ix: PackedInt32Array = a[Mesh.ARRAY_INDEX]
	var wound := true
	for t in range(0, ix.size(), 3):
		wound = wound and (v[ix[t + 1]] - v[ix[t]]).cross(v[ix[t + 2]] - v[ix[t]]).dot(nr[ix[t]]) < 0
	check(wound, "triângulos em sentido horário visto de fora")
	air[4 + 4 * C + 10 * C * C] = Blocks.ids.dirt
	check(faces(ChunkMesher.build(air, nb, n)) == 10, "dois blocos vizinhos escondem a face em comum")
	return true


func test_gen():
	var gen := WorldGen.new(42)
	var t := Time.get_ticks_usec()
	var d := gen.generate(8, 8)
	var gen_ms := (Time.get_ticks_usec() - t) / 1000.0
	check(d == WorldGen.new(42).generate(8, 8), "geração determinística por seed")
	check(d != WorldGen.new(43).generate(8, 8), "seed diferente muda o mundo")
	check(d.size() == C * C * H, "chunk tem 16x16xALTURA blocos")
	var at := func(x, y, z): return d[x + z * C + y * C * C]
	var h := gen.surface_height(8 * C + 5, 8 * C + 5)
	check(at.call(5, h, 5) == gen.GRASS and not Blocks.solid[at.call(5, h + 1, 5)], "superfície: grama no topo, ar ou planta acima")
	check(at.call(5, 0, 5) == gen.BEDROCK, "fundo: bedrock")
	var count := {}
	for y in H:
		var layer := "submundo" if y < WorldGen.UNDERWORLD_TOP else "cavernas" if y < WorldGen.CAVERN_TOP else "subterrâneo"
		for i in C * C:
			var k := "%s:%d" % [layer, d[i + y * C * C]]
			count[k] = count.get(k, 0) + 1
	check(count.has("submundo:%d" % gen.ASH) and count.has("submundo:0"), "submundo: cinza com espaço aberto")
	check(count.get("cavernas:%d" % gen.STONE, 0) > count.get("cavernas:%d" % gen.DIRT, 0), "cavernas: pedra predomina")
	check(count.has("cavernas:0"), "cavernas: há cavernas")
	check(count.get("subterrâneo:%d" % gen.DIRT, 0) > count.get("subterrâneo:%d" % gen.STONE, 0), "subterrâneo: terra predomina")
	var found := {}
	for c in 4:
		var cd := gen.generate(c, 3)
		for i in cd.size():
			found[cd[i]] = mini(found.get(cd[i], 999), i / (C * C))  # menor y de cada bloco
	for o in gen.ores:
		check(found.has(o.block) and found[o.block] >= o.min_y, "minério %s aparece a partir de y=%d" % [Blocks.ids.keys()[o.block], o.min_y])
	check(found.has(gen.WOOD) and found.has(gen.LEAVES), "há árvores")
	var nb := [gen.generate(9, 8), gen.generate(7, 8), gen.generate(8, 9), gen.generate(8, 7)]
	t = Time.get_ticks_usec()
	ChunkMesher.build(d, nb, Blocks.textures.size())
	print("chunk: geração %.1f ms, mesh %.1f ms" % [gen_ms, (Time.get_ticks_usec() - t) / 1000.0])
	return true
