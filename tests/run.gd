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
	Buffs.load_pack()
	Loot.load_pack()
	# Erro de script aborta a função, que então retorna null em vez de true.
	for t in ["test_blocks", "test_atlas", "test_mesher", "test_gen", "test_raycast", "test_player", "test_items", "test_crafting", "test_mining", "test_day_night", "test_combat", "test_drops", "test_save", "test_wiki_sprites", "test_item_model", "test_projectiles", "test_progression", "test_boss", "test_armor", "test_enemy_models", "test_lighting", "test_visuals", "test_liquids", "test_flow", "test_swim_out", "test_ui", "test_cursor", "test_gui_extras", "test_evil", "test_minimap", "test_tree", "test_binds", "test_attack", "test_damage", "test_wings", "test_consumables", "test_life_crystal", "test_loot", "test_mana", "test_npc", "test_worm", "test_brain", "test_forge", "test_king_meteor", "test_dungeon", "test_skeletron", "test_hardmode", "test_tools"]:
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
	p.creative = true
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


# A vida perdida cabe no golpe de `dmg` contra defesa `def`: variância de ±15% antes da defesa (⌈def/2⌉) e, se foi crítico, ×2 depois dela.
func dmg_ok(lost: int, dmg: int, def: int) -> bool:
	var lo := maxi(1, roundi(dmg * 0.85) - ceili(def / 2.0))
	var hi := maxi(1, roundi(dmg * 1.15) - ceili(def / 2.0))
	return (lost >= lo and lost <= hi) or (lost >= lo * 2 and lost <= hi * 2)


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
	check(dmg_ok(hp - z.hp, 4 + 5, 6) and p.inv.total(Items.ids.wooden_arrow) == 1, "flecha gasta munição e fere com arco + flecha − defesa (%d)" % (hp - z.hp))
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
	var chosen := {"skin": Color("#a86a44"), "hair": Color("#3a2a5a"), "shirt": Color("#4fa8a8"), "pants": Color("#5a2a3a")}
	var bia := SaveGame.create_player("Bia", chosen)
	check(SaveGame.look(bia) == chosen and SaveGame.look(pp) == SaveGame.look_for("Ana"), "cores escolhidas na criação ficam no save; sem escolha, vêm do nome")
	SaveGame.delete(bia)
	check(SaveGame.list(SaveGame.players_dir).map(func(s): return s.name) == ["Ana"], "lista de personagens")
	check(SaveGame.list(SaveGame.worlds_dir)[0].info.seed == 777, "mundo guarda a seed")
	var w := floor_world()
	var p := make_player(w)
	check(not SaveGame.load_player(p, pp), "personagem novo: jogo dá os itens iniciais")
	w.set_block(20, 11, 20, Blocks.ids.dirt)
	p.inv.add(Items.ids.iron_pickaxe, 1)
	p.inv.add(Items.ids.stone, 42)
	p.hp = 37
	p.max_hp = 140
	p.add_buff("ironskin", 300.0)
	p.inv.add(Items.ids.iron_helmet, 1)
	p.inv.equip_from(p.inv.item.find(Items.ids.iron_helmet))
	p.spawn = Vector3(21.5, 11, 22.5)
	p.inv.add(Items.ids.gold_coin, 3)
	p.inv.ammo[1] = Items.ids.wooden_arrow
	p.inv.ammo_count[1] = 77
	p.inv.acc[2] = Items.ids.hermes_boots
	p.inv.fav[0] = 1
	w.chest_at(Vector3i(5, 6, 7)).item[0] = Items.ids.gold_bar
	p.clock.time = 123.0
	w.hardmode = true
	w.skeletron_down = true
	w.evil_boss_down = true
	w.orbs_broken = 5
	w.map_img.set_pixel(30, 40, Color("#ff8800"))
	w.saplings[Vector3i(9, 11, 9)] = 42.0
	check(SaveGame.save_world(w, p, p.clock, wp) == OK and SaveGame.save_player(p, pp) == OK, "salvar mundo e personagem")
	var w2: Node3D = load("res://scripts/world.gd").new()
	w2.gen = WorldGen.new(1)
	var p2 := make_player(w2)
	check(SaveGame.load_world(w2, p2, p2.clock, wp) and SaveGame.load_player(p2, pp), "carregar")
	check(w2.get_block(20, 11, 20) == Blocks.ids.dirt and w2.world_seed == w.world_seed, "bloco editado volta, seed do mundo")
	check(p2.inv.total(Items.ids.stone) == 42 and p2.inv.total(Items.ids.iron_pickaxe) == 1 and p2.hp == 37, "inventário e vida voltam")
	check(p2.max_hp == 140 and is_equal_approx(p2.buffs.get("ironskin", 0.0), 300.0), "vida máxima e buffs voltam")
	check(p2.inv.equip[0] == Items.ids.iron_helmet, "armadura vestida volta")
	check(p2.spawn == p.spawn and p2.clock.time == 123.0, "spawn e hora do mundo voltam")
	check(p2.inv.coin[2] == 3 and p2.inv.ammo[1] == Items.ids.wooden_arrow and p2.inv.ammo_count[1] == 77 and p2.inv.acc[2] == Items.ids.hermes_boots \
		and p2.inv.fav[0] == 1, "moedas, munição, acessórios e favoritos voltam")
	check(w2.hardmode and w2.gen.hardmode and w2.skeletron_down and w2.evil_boss_down and w2.orbs_broken == 5, "hardmode, Skeletron, chefe do mal e orbes voltam")
	check(w2.chests.has(Vector3i(5, 6, 7)) and w2.chests[Vector3i(5, 6, 7)].item[0] == Items.ids.gold_bar, "conteúdo do baú volta")
	check(w2.map_img.get_pixel(30, 40).is_equal_approx(Color("#ff8800")) and w2.map_img.get_pixel(31, 40).a == 0.0, "mapa explorado volta")
	check(w2.saplings.get(Vector3i(9, 11, 9)) == 42.0, "mudas plantadas voltam")
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
	check(dmg_ok(45 - z1.hp, 23, 6), "feixe acerta longe com o dano da espada − defesa (%d)" % (45 - z1.hp))
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
	# Tocha entre chunks: a do chunk diagonal também acende o canto (a luz de 10 blocos cruza a quina)
	var flat := chunk(0)
	for i in C * C * (Y + 1):
		flat[i] = Blocks.ids.stone
	var lamp := chunk(0)
	lamp[0 + 0 * C + (Y + 1) * C * C] = Blocks.ids.torch   # canto (0,0) do chunk (+X,+Z): em (16,Y+1,16) no quadro do chunk
	var E := PackedByteArray()
	var seam_off := face_light(ChunkMesher.build(flat, [E, E, E, E], n), Vector3i(15, Y, 15), Vector3.UP)
	var seam_on := face_light(ChunkMesher.build(flat, [E, E, E, E], n, [], [lamp, E, E, E]), Vector3i(15, Y, 15), Vector3.UP)
	check(seam_off.g == 0.0 and seam_on.g > 0.6, "tocha no chunk diagonal ilumina o canto (%.2f, sem ela %.2f)" % [seam_on.g, seam_off.g])
	# pôr ou tirar tocha refaz os chunks que a luz alcança (raio 10), não só os da borda
	var lw := floor_world()   # 3x3 chunks
	var touched := func(ids: Array) -> Array:   # quais chunks foram marcados para refazer
		var out := []
		for z in 3:
			for x in 3:
				if lw.versions.get(Vector2i(x, z), 0) > 0:
					out.append(Vector2i(x, z))
		lw.versions.clear()
		return out
	lw.set_block(21, 11, 21, Blocks.ids.torch)   # chunk (1,1), local (5,5): a luz chega ao chunk −X, ao −Z e ao canto −X−Z
	check(touched.call([]) == [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)], "tocha a 5 blocos da borda: refaz o chunk, os dois vizinhos e o de canto que ela alcança")
	lw.set_block(21, 11, 21, 0)
	check(touched.call([]).size() == 4, "tirar a tocha refaz os mesmos chunks")
	lw.set_block(21, 11, 21, Blocks.ids.dirt)
	check(touched.call([]) == [Vector2i(1, 1)], "bloco comum no meio do chunk só refaz o próprio chunk")
	lw.set_block(24, 11, 24, Blocks.ids.torch)   # local (8,8): alcança −X (8 < 10) e +X (8+10 >= 16): todos os 8 em volta
	check(touched.call([]).size() == 9, "tocha no meio do chunk alcança os 8 vizinhos")
	lw.free()
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


func test_gui_extras():
	var inv := Inventory.new()
	inv.add(Items.ids.copper_coin, 250)
	check(inv.coin[0] == 50 and inv.coin[1] == 2 and inv.total(Items.ids.copper_coin) == 0 and inv.coin_value() == 250, "moedas vão para os slots e sobem de tipo a cada 100")
	inv.add(Items.ids.wooden_arrow, 10)
	inv.ammo[0] = Items.ids.unholy_arrow
	inv.ammo_count[0] = 1
	check(inv.take_ammo("arrow") == Items.ids.unholy_arrow and inv.ammo[0] == -1, "slot de munição é usado antes do inventário")
	check(inv.take_ammo("arrow") == Items.ids.wooden_arrow and inv.total(Items.ids.wooden_arrow) == 9 and inv.take_ammo("bala") == -1, "depois a munição do inventário")
	inv.cursor_id = Items.ids.dirt
	inv.cursor_count = 5
	inv.click_ammo(2)
	check(inv.ammo[2] == -1 and inv.cursor_id == Items.ids.dirt, "slot de munição recusa o que não é munição")
	inv.click_acc(0)
	check(inv.acc[0] == -1, "slot de acessório recusa o que não é acessório")
	inv = Inventory.new()
	inv.item[0] = Items.ids.hermes_boots
	inv.count[0] = 1
	inv.click(0)
	inv.click_acc(1)
	check(inv.acc[1] == Items.ids.hermes_boots and is_equal_approx(inv.acc_sum("speed"), 0.4), "acessório vestido soma o bônus")
	for e in [[12, Items.ids.stone], [14, Items.ids.dirt], [20, Items.ids.stone]]:
		inv.item[e[0]] = e[1]
		inv.count[e[0]] = 5
	inv.item[10] = Items.ids.wood
	inv.count[10] = 1
	inv.fav[10] = 1
	inv.sort_items()
	check(inv.item[10] == Items.ids.wood and inv.fav[10] == 1, "ordenar não mexe no favorito")
	check(inv.item[11] == Items.ids.dirt and inv.item[12] == Items.ids.stone and inv.item[13] == Items.ids.stone, "ordenar agrupa por nome, fora da hotbar")
	var chest := {"item": PackedInt32Array([-1, -1, -1]), "count": PackedInt32Array([0, 0, 0])}
	var from := PackedInt32Array([Items.ids.stone, Items.ids.stone])
	var cnt := PackedInt32Array([9990, 30])
	check(Inventory.move_stack(from, cnt, 0, chest.item, chest.count) and chest.count[0] == 9990 and from[0] == -1, "Shift+clique move a pilha ao baú")
	Inventory.move_stack(from, cnt, 1, chest.item, chest.count)
	check(chest.count[0] == 9999 and chest.count[1] == 21, "…junta no que já tem e o resto vai para um slot vazio")
	var w := floor_world()
	w.world_seed = 5
	var a: Dictionary = w.chest_at(Vector3i(3, 4, 5))
	check(a.item.count(-1) < 40 and a.item[0] != -1, "baú novo traz tesouro")
	var w3: Node3D = load("res://scripts/world.gd").new()
	check(w3.chest_at(Vector3i(3, 4, 5)).item[0] != -1, "baú sem seed também sorteia (nunca vazio)")
	w3.free()
	w.free()
	return true


func test_evil():
	var kinds := {}
	for sd in [1, 2, 3, 4, 5, 6, 7, 8]:
		kinds[WorldGen.new(sd).evil] = true
	check(kinds.has("corruption") and kinds.has("crimson"), "a seed escolhe Corrupção ou Carmesim (ambos aparecem)")
	var g := WorldGen.new(1337)
	var reach := g.evil_center.distance_to(WorldGen.CENTER)
	check(reach >= 60.0 and g.evil_center.x - 30 > 0 and g.evil_center.x + 30 < WorldGen.SIZE_CHUNKS * C and g.evil_center.y - 30 > 0 \
		and g.evil_center.y + 30 < WorldGen.SIZE_CHUNKS * C, "o bioma fica longe do nascimento e dentro do mundo")
	var stone := 0
	var grass := 0
	var c0 := Vector2i(floori(g.evil_center.x / C), floori(g.evil_center.y / C))
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var d := g.generate(c0.x + dx, c0.y + dz)
			stone += d.count(g.EVIL_STONE)
			grass += d.count(g.EVIL_GRASS)
	check(stone > 500 and grass > 100, "pedra e grama do mal cobrem o centro (%d, %d)" % [stone, grass])
	check(g.generate(1, 1).count(g.EVIL_STONE) == 0 and g.generate(1, 1).count(g.ORB) == 0, "o resto do mundo fica intacto")
	var orbs := 0
	for k in WorldGen.CHASMS:
		var o := g.chasm_orb(k)
		var d := g.generate(floori(o.x / float(C)), floori(o.z / float(C)))
		var i := posmod(o.x, C) + posmod(o.z, C) * C + o.y * C * C
		if d[i] == g.ORB and d[i + C * C] == 0 and d[i + 2 * C * C] == 0 and d[i - C * C] == g.EVIL_STONE:
			orbs += 1
	check(orbs == WorldGen.CHASMS, "cada abismo tem um orbe no chão, com ar em cima (%d/%d)" % [orbs, WorldGen.CHASMS])
	var again := WorldGen.new(1337)
	check(again.generate(c0.x, c0.y) == g.generate(c0.x, c0.y), "geração do bioma é determinística")
	return true


# Cores lidas de uma imagem de 8 bits por canal (a ida e volta perde até 1/255).
func near(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) < 0.01 and absf(a.g - b.g) < 0.01 and absf(a.b - b.b) < 0.01 and absf(a.a - b.a) < 0.01


func key(code: int) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.keycode = code
	e.pressed = true
	return e


# Minimapa: imagem do mundo inteiro com origem fixa. A seta fica no centro, o mapa desliza 1:1 com o jogador (nada "teleporta"),
# o que foi explorado continua depois de sair da faixa, e Tab/M/+/- trocam estilo, mapa cheio e zoom.
func test_minimap():
	var w: Node3D = load("res://scripts/world.gd").new()
	w.gen = WorldGen.new(1)
	for z in 16:
		for x in 16:
			var d := chunk(0)
			for i in C * C * 11:
				d[i] = Blocks.ids.stone
			w.chunks[Vector2i(x, z)] = d
	var p := make_player(w)
	var colors := Blocks.tile_colors
	Blocks.tile_colors = PackedColorArray()   # cada tile com uma cor própria, para o pixel provar de que coluna veio
	for t in Blocks.textures.size():
		Blocks.tile_colors.append(Color.from_hsv(fmod(t * 0.137, 1.0), 0.8, 0.9))
	w.set_block(110, 11, 105, Blocks.ids.gold_ore)   # marcador: 1 bloco acima do chão
	var mm := Minimap.new()
	mm.setup(w, p)
	mm.size = Vector2(Minimap.PORTRAIT, Minimap.PORTRAIT)
	root.add_child(mm)
	p.position = Vector3(100.5, 11, 100.5)
	var s: float = Minimap.ZOOMS[mm.zoom]
	var last_marker := Vector2.ZERO
	var last_pos := Vector2.ZERO
	var worst_arrow := 0.0
	var worst_jump := 0.0
	var started_ms := Time.get_ticks_msec()
	for f in 200 * 9:   # 200 blocos a 6,6 blocos/s
		p.position.z += 6.6 / 60.0
		p.position.x += 0.5 / 60.0
		mm._process(1.0 / 60)
		var marker := mm.to_view(Vector2(110.5, 105.5))
		var pos := Vector2(p.position.x, p.position.z)
		worst_arrow = maxf(worst_arrow, (mm.to_view(pos) - mm.size / 2.0).length())
		if f > 0:   # o marcador anda exatamente o que o jogador andou (× escala), a cada quadro
			worst_jump = maxf(worst_jump, (marker - last_marker + (pos - last_pos) * s).length())
		last_marker = marker
		last_pos = pos
	var per_frame := float(Time.get_ticks_msec() - started_ms) / (200 * 9)
	print("minimapa: %.2f ms por quadro" % per_frame)
	check(worst_arrow <= 1.0, "a seta fica no centro do retrato em toda a caminhada (%.2f px)" % worst_arrow)
	check(worst_jump <= 1.5, "o mapa desliza junto do jogador sem saltos (erro máx. %.2f px por quadro: só o arredondamento a pixel inteiro)" % worst_jump)
	check(near(w.map_img.get_pixel(110, 105), Minimap.color_of(Blocks.ids.gold_ore, 11)), "o pixel do marcador tem a cor do bloco dele")
	check(near(w.map_img.get_pixel(111, 105), Minimap.color_of(Blocks.ids.stone, 10)) and not near(w.map_img.get_pixel(110, 105), w.map_img.get_pixel(111, 105)), "e o vizinho a cor do chão")
	check(w.map_img.get_pixel(110, 105).a == 1.0 and w.map_img.get_pixel(240, 30).a == 0.0, "o explorado persiste depois de sair da faixa; o longe segue não visto")
	# estilos e mapa cheio
	mm.zoom = 1
	mm._unhandled_input(key(KEY_TAB))
	check(mm.style == Minimap.STYLE_OVERLAY and mm.visible and mm.anchor_bottom == 1.0 and mm.modulate.a < 1.0, "Tab: sobreposição translúcida na tela toda")
	mm._unhandled_input(key(KEY_TAB))
	check(mm.style == Minimap.STYLE_HIDDEN and not mm.visible, "Tab: minimapa oculto")
	mm._process(0.0)
	mm._unhandled_input(key(KEY_M))
	check(mm.full and mm.visible and p.map_open and mm.modulate.a == 1.0, "M: mapa cheio aparece mesmo com o minimapa oculto e o jogador fica parado")
	mm.size = Vector2(1280, 720)
	var a := mm.to_view(Vector2.ZERO)
	var b := mm.to_view(Vector2(WorldGen.SIZE, WorldGen.SIZE))
	check(a.x > 0 and a.y >= 0 and b.x < 1280 and b.y <= 720 and absf((a.x + b.x) / 2.0 - 640.0) < 1.0, "mapa cheio mostra o mundo inteiro, centrado")
	mm._unhandled_input(key(KEY_ESCAPE))
	check(not mm.full and not p.map_open, "Esc fecha o mapa cheio")
	mm._unhandled_input(key(KEY_TAB))
	check(mm.style == Minimap.STYLE_PORTRAIT and mm.anchor_left == 1.0, "Tab: volta ao retrato no canto")
	mm._unhandled_input(key(KEY_EQUAL))
	mm._unhandled_input(key(KEY_EQUAL))
	check(mm.zoom == 2, "+ dá zoom no retrato (até o máximo)")
	mm._unhandled_input(key(KEY_MINUS))
	mm._unhandled_input(key(KEY_MINUS))
	mm._unhandled_input(key(KEY_MINUS))
	check(mm.zoom == 0, "− afasta (até o mínimo)")
	Blocks.tile_colors = colors
	mm.free()
	free_player(p)
	w.free()
	return true


# Planta uma árvore de verdade (WorldGen.tree) com o tronco em (x, z) sobre o chão de pedra do floor_world (chão em y = 10).
func grow_tree(w: Node3D, x: int, z: int, seed_: int) -> void:
	for dz in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			var k := Vector2i(x / C + dx, z / C + dz)
			if w.chunks.has(k):
				w.gen.tree(w.chunks[k], k.x, k.y, x, z, 10, PackedInt32Array([10, 10, 10, 10]), seed_)


func count_in(w: Node3D, id: int, lo: Vector3i, hi: Vector3i) -> int:
	var n := 0
	for y in range(lo.y, hi.y + 1):
		for z in range(lo.z, hi.z + 1):
			for x in range(lo.x, hi.x + 1):
				n += int(w.get_block(x, y, z) == id)
	return n


# Folhas que ficaram sem madeira a até 4 passos de folha (flutuando).
func floating_leaves(w: Node3D, lo: Vector3i, hi: Vector3i) -> int:
	var seen := {}
	var queue := []
	for y in range(lo.y, hi.y + 1):
		for z in range(lo.z, hi.z + 1):
			for x in range(lo.x, hi.x + 1):
				if w.get_block(x, y, z) == Blocks.ids.wood:
					seen[Vector3i(x, y, z)] = 0
					queue.append(Vector3i(x, y, z))
	var i := 0
	while i < queue.size():
		var q: Vector3i = queue[i]
		i += 1
		if seen[q] >= 4:
			continue
		for n in Timber.N6:
			var r: Vector3i = q + n
			if not seen.has(r) and w.get_block(r.x, r.y, r.z) == Blocks.ids.leaves:
				seen[r] = seen[q] + 1
				queue.append(r)
	return count_in(w, Blocks.ids.leaves, lo, hi) - (seen.size() - count_in(w, Blocks.ids.wood, lo, hi))


func test_tree():
	var lo := Vector3i(14, 11, 14)
	var hi := Vector3i(38, 40, 34)
	var w := floor_world()
	var p := make_player(w)
	var ent: Node3D = p.entities
	p.position = Vector3(2.5, 11, 2.5)   # longe: a árvore cai para o lado oposto
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	grow_tree(w, 24, 24, 4242)
	var base := Vector3i(24, 11, 24)
	var logs0 := count_in(w, Blocks.ids.wood, lo, hi)
	var leaves0 := count_in(w, Blocks.ids.leaves, lo, hi)
	check(Timber.is_tree(w, base) and Timber.is_tree(w, Vector3i(24, 14, 24)), "o tronco de uma árvore gerada é árvore (base e meio)")
	check(logs0 >= 8 and leaves0 > 30, "árvore gerada: tronco %d e folhas %d" % [logs0, leaves0])
	w.set_block(36, 11, 30, Blocks.ids.wood)
	w.set_block(36, 12, 30, Blocks.ids.wood)
	check(not Timber.is_tree(w, Vector3i(36, 11, 30)), "madeira colocada, sem folhas, não é árvore")
	# base: derruba tudo (tronco, raízes, galhos e copa); nada fica flutuando
	var cut := Timber.fell(ent, base, 35, p.position, rng)
	check(cut.logs == logs0 and cut.leaves == leaves0, "cortar a base derruba a árvore inteira (%d de madeira, %d de folhas)" % [cut.logs, cut.leaves])
	check(count_in(w, Blocks.ids.wood, lo, Vector3i(34, 40, 34)) == 0 and count_in(w, Blocks.ids.leaves, lo, hi) == 0, "…e não sobra tronco nem folha")
	var dropped := 0
	var acorn_drops := 0
	for n in ent.get_children():
		dropped += n.count if n.get("item") == Items.ids.wood else 0
		acorn_drops += n.count if n.get("item") == Items.ids.acorn else 0
	check(dropped == cut.wood and cut.wood >= cut.logs and cut.wood <= 2 * cut.logs and acorn_drops == cut.acorns, "madeira por tile (1 a 2: %d de %d tiles) e acorns (%d)" % [cut.wood, cut.logs, cut.acorns])
	# meio do tronco: só o que está acima cai; o toco fica
	grow_tree(w, 24, 24, 4242)
	Timber.fell(ent, Vector3i(24, 15, 24), 35, p.position, rng)
	check(count_in(w, Blocks.ids.wood, lo, Vector3i(34, 12, 34)) >= 4 and w.get_block(24, 14, 24) == Blocks.ids.wood and w.get_block(24, 15, 24) == 0, "cortar o meio deixa o toco (o de baixo) e derruba o de cima")
	check(count_in(w, Blocks.ids.leaves, lo, hi) == 0 and count_in(w, Blocks.ids.wood, Vector3i(14, 16, 14), hi) == 0, "…com a copa (nada flutua)")
	w.set_block(24, 14, 24, 0)
	for y in range(11, 14):
		w.set_block(24, y, 24, 0)
	# árvore vizinha de copa encostada: a que fica não perde o tronco nem fica com folha solta
	grow_tree(w, 24, 24, 4242)
	grow_tree(w, 29, 24, 777)
	var b_logs := count_in(w, Blocks.ids.wood, Vector3i(27, 11, 14), hi)
	var b_leaves := count_in(w, Blocks.ids.leaves, lo, hi)
	Timber.fell(ent, base, 35, p.position, rng)
	check(count_in(w, Blocks.ids.wood, Vector3i(28, 11, 14), Vector3i(38, 40, 34)) >= b_logs - 4 and count_in(w, Blocks.ids.leaves, lo, hi) > 20, "a árvore vizinha continua de pé")
	check(floating_leaves(w, lo, hi) == 0, "nenhuma folha flutua depois (%d de %d)" % [count_in(w, Blocks.ids.leaves, lo, hi), b_leaves])
	Timber.fell(ent, Vector3i(29, 11, 24), 35, p.position, rng)   # some com a vizinha para os próximos testes
	# golpes: 100 de vida por tile e ⌊poder × 24%⌋ por golpe (cobre 35 → 8 → 13 golpes; ferro 45 → 10 → 10)
	for kind in [["copper_axe", 13], ["iron_axe", 10]]:
		grow_tree(w, 24, 24, 4242)
		p.inv = Inventory.new()
		p.inv.add(Items.ids[kind[0]], 1)
		p.slot = 0
		p.target = {"pos": base, "normal": Vector3i.UP}
		for hit in kind[1] - 1:
			p.break_target()
		check(w.get_block(24, 11, 24) == Blocks.ids.wood, "%s: com %d golpes a árvore ainda está de pé" % [kind[0], kind[1] - 1])
		p.break_target()
		check(w.get_block(24, 11, 24) == 0 and count_in(w, Blocks.ids.leaves, lo, hi) == 0, "%s: o golpe %d derruba a árvore" % [kind[0], kind[1]])
	p.inv = Inventory.new()
	p.inv.add(Items.ids.copper_axe, 1)
	p.target = {"pos": Vector3i(36, 11, 30), "normal": Vector3i.UP}
	p.break_target()
	p.break_target()
	check(w.get_block(36, 11, 30) == 0 and w.get_block(36, 12, 30) == Blocks.ids.wood, "madeira colocada: 2 golpes por bloco, sem derrubar o de cima")
	# rendimento (wiki): 1 por tile, chance (2·poder + 175)/525 de virar 2
	var total := 0
	for i in 30000:
		total += Timber.yield_wood(1, 35, rng)
	check(absf(float(total) / 30000.0 - (1.0 + (2.0 * 35 + 175.0) / 525.0)) < 0.015, "madeira média por tile com o machado de cobre ≈ 1,47 (%.3f)" % (float(total) / 30000.0))
	total = 0
	for i in 30000:
		total += Timber.yield_wood(1, 0, rng)
	check(absf(float(total) / 30000.0 - 4.0 / 3.0) < 0.015, "sem machado a chance é 1/3 (%.3f)" % (float(total) / 30000.0))
	check(Timber.patches([Vector3i(0, 0, 0), Vector3i(1, 0, 0), Vector3i(5, 5, 5)]) == 2, "tufos de folhas = pedaços ligados")
	# muda: acorn em grama, cresce com espaço e vira a árvore da semente da posição
	check(Items.places[Items.ids.acorn] == Blocks.sapling and Blocks.sapling > 0, "o acorn coloca a muda")
	p.inv = Inventory.new()
	p.inv.add(Items.ids.acorn, 3)
	p.slot = 0
	p.target = {"pos": Vector3i(24, 10, 24), "normal": Vector3i.UP}   # pedra
	p.place_block()
	check(w.get_block(24, 11, 24) == 0 and p.inv.total(Items.ids.acorn) == 3, "muda não pega em pedra")
	w.set_block(24, 10, 24, Blocks.ids.grass)
	p.place_block()
	check(w.get_block(24, 11, 24) == Blocks.sapling and p.inv.total(Items.ids.acorn) == 2 and w.saplings.has(base), "muda pega na grama e gasta o acorn")
	w.set_block(24, 14, 24, Blocks.ids.stone)   # sem espaço em cima: não cresce e tenta de novo depois
	check(not w.grow_sapling(base) and w.saplings[base] == 60.0 and w.get_block(24, 11, 24) == Blocks.sapling, "sem espaço livre a muda espera")
	w.set_block(24, 14, 24, 0)
	check(w.grow_sapling(base) and Timber.is_tree(w, base) and not w.saplings.has(base), "com espaço a muda vira árvore")
	p.target = {"pos": Vector3i(24, 10, 24), "normal": Vector3i.UP}
	free_player(p)
	w.free()
	return true


# Teclas como no Terraria (wiki Controls): Esc = inventário, botão esquerdo usa (também coloca bloco), direito só interage, Shift = Auto Select
# (a ferramenta certa para o alvo, senão a tocha) e não há corrida; Ctrl+clique joga no lixo; as opções do Configurações persistem.
func test_binds():
	var w := floor_world()
	var p := make_player(w)
	p.cam = Camera3D.new()
	p._unhandled_input(key(KEY_ESCAPE))
	check(p.inventory_open, "Esc abre o inventário")
	p._unhandled_input(key(KEY_ESCAPE))
	check(not p.inventory_open, "Esc fecha o inventário")
	p._unhandled_input(key(KEY_E))
	p._unhandled_input(key(KEY_TAB))
	check(not p.inventory_open, "E e Tab não abrem o inventário (E é o gancho e Tab o mapa no Terraria)")
	p.map_open = true
	p._unhandled_input(key(KEY_ESCAPE))
	check(not p.inventory_open, "com o mapa cheio o Esc é do mapa")
	p.map_open = false
	p.menu_open = true
	p._unhandled_input(key(KEY_ESCAPE))
	check(not p.inventory_open, "pausado o Esc é do HUD")
	p.menu_open = false
	p._unhandled_input(key(KEY_3))
	check(p.slot == 2, "3 escolhe o 3º slot")
	p._unhandled_input(key(KEY_0))
	check(p.slot == 9, "0 escolhe o 10º slot")
	p.set_inventory(true)
	p._unhandled_input(key(KEY_2))
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel.pressed = true
	p._unhandled_input(wheel)
	check(p.slot == 2, "com o inventário aberto as teclas 1-0 e a roda também trocam de slot")
	p.set_inventory(false)
	# sem corrida: a base é a da wiki (11 tiles/s = 6,6 blocos/s) com ou sem Shift
	p.position = Vector3(20.5, 11, 24.5)
	p.step(1.0 / 60, Vector3.RIGHT, false)
	var x0: float = p.position.x
	for i in 60:
		p.step(1.0 / 60, Vector3.RIGHT, false)
	check(absf(p.position.x - x0 - 6.6) < 0.05, "anda 6,6 blocos em 1 s (%.2f)" % (p.position.x - x0))
	# esquerdo coloca o bloco da mão, direito só interage
	p.inv = Inventory.new()
	p.inv.add(Items.ids.dirt, 5)
	p.slot = 0
	p.position = Vector3(30.5, 11, 30.5)
	p.target = {"pos": Vector3i(24, 10, 24), "normal": Vector3i.UP}
	p.interact()
	var rmb := InputEventMouseButton.new()
	rmb.button_index = MOUSE_BUTTON_RIGHT
	rmb.pressed = true
	p._unhandled_input(rmb)
	check(w.get_block(24, 11, 24) == 0 and p.inv.total(Items.ids.dirt) == 5, "botão direito não coloca bloco")
	p.use_item()
	check(w.get_block(24, 11, 24) == Blocks.ids.dirt and p.inv.total(Items.ids.dirt) == 4 and is_equal_approx(p.cooldown, 0.25), "botão esquerdo coloca o bloco da mão (a cada 0,25 s segurando)")
	# Auto Select
	p.inv = Inventory.new()
	for n in ["copper_pickaxe", "copper_axe", "iron_pickaxe", "torch"]:
		p.inv.add(Items.ids[n], 1)
	p.slot = 1
	p.target = {"pos": Vector3i(24, 10, 24), "normal": Vector3i.UP}   # pedra
	p.auto_pick(true)
	check(p.slot == 2 and p.auto_prev == 1, "Shift em pedra: a melhor picareta (ferro), lembrando o slot da mão")
	w.set_block(24, 11, 24, Blocks.ids.wood)
	p.target = {"pos": Vector3i(24, 11, 24), "normal": Vector3i.UP}
	p.auto_pick(true)
	check(p.slot == 1 and p.auto_prev == 1, "segurando Shift e mirando o tronco: o machado (o slot de antes não se perde)")
	p.target = {}
	p.auto_pick(true)
	check(p.slot == 3, "Shift sem bloco na mira: a tocha")
	p.auto_pick(false)
	check(p.slot == 1 and p.auto_prev == -1, "soltar o Shift devolve o slot de antes")
	p.inv = Inventory.new()
	p.inv.add(Items.ids.dirt, 1)
	p.slot = 0
	p.target = {"pos": Vector3i(24, 10, 24), "normal": Vector3i.UP}
	p.auto_pick(true)
	check(p.slot == 0 and p.auto_prev == -1, "sem ferramenta adequada na hotbar o Auto Select não troca")
	# Ctrl+clique: lixeira
	var inv := Inventory.new()
	inv.add(Items.ids.dirt, 30)
	inv.add(Items.ids.stone, 5)
	check(inv.quick_trash(0) and inv.trash_id == Items.ids.dirt and inv.trash_count == 30 and inv.item[0] == -1, "Ctrl+clique manda o item para a lixeira")
	inv.toggle_fav(1)
	check(not inv.quick_trash(1) and inv.item[1] == Items.ids.stone and not inv.quick_trash(7), "favorito e slot vazio não vão para a lixeira")
	inv.toggle_fav(1)
	check(inv.quick_trash(1) and inv.trash_id == Items.ids.stone and inv.trash_count == 5, "outro item destrói o que estava na lixeira")
	# sensibilidade do mouse (Configurações)
	p.rotation.y = 0.0
	p.look(Vector2(100, 0))
	var turn: float = p.rotation.y
	p.rotation.y = 0.0
	Settings.mouse_sens = 2.0
	p.look(Vector2(100, 0))
	check(turn < 0.0 and is_equal_approx(p.rotation.y, turn * 2.0), "a sensibilidade das Configurações multiplica o giro do mouse")
	Settings.mouse_sens = 1.0
	p.look(Vector2(0, -100000))
	check(is_equal_approx(p.pitch, 1.55), "olhar para cima para em 1,55 rad")
	# opções: valem sem arquivo (padrões), gravam e leem de volta, e valores absurdos do arquivo são limitados
	check(Settings.path == "" and Settings.render_distance == 6, "sem menu as opções são as padrão e nada é gravado")
	Settings.path = "user://settings_test.cfg"
	Settings.render_distance = 9
	Settings.volume = 0.4
	Settings.mouse_sens = 1.5
	Settings.save()
	Settings.render_distance = 6
	Settings.volume = 1.0
	Settings.mouse_sens = 1.0
	Settings.load_file()
	check(Settings.render_distance == 9 and is_equal_approx(Settings.volume, 0.4) and is_equal_approx(Settings.mouse_sens, 1.5), "as opções gravadas voltam ao abrir")
	var cfg := ConfigFile.new()
	cfg.set_value("game", "render_distance", 99)
	cfg.set_value("game", "volume", -3.0)
	cfg.set_value("game", "mouse_sens", 50.0)
	cfg.save(Settings.path)
	Settings.load_file()
	check(Settings.render_distance == 16 and Settings.volume == 0.0 and Settings.mouse_sens == 3.0, "valores fora da faixa no arquivo são limitados")
	DirAccess.remove_absolute(Settings.path)
	Settings.path = ""
	Settings.render_distance = 6
	Settings.volume = 1.0
	Settings.mouse_sens = 1.0
	p.cam.free()
	free_player(p)
	w.free()
	return true


# Consumíveis e buffs (wiki: Lesser Healing, Ironskin, Regeneration, Swiftness, Mining, Archery, Recall, Magic Mirror, Cloud in a Bottle).
func test_consumables():
	var w := floor_world()
	var p := make_player(w)
	var ent: Node3D = p.entities
	var dt := 1.0 / 60
	var give := func(name: String, n := 1) -> int:
		p.inv = Inventory.new()
		p.inv.add(Items.ids[name], n)
		p.slot = 0
		return 0
	# dados da wiki
	var d: Dictionary = Items.defs[Items.ids.lesser_healing_potion]
	check(d.heal == 50 and absf(Items.use_dur(Items.ids.lesser_healing_potion) - 17.0 / 60.0) < 0.001 and d.consumable, "Lesser Healing: cura 50, use time 17")
	var times := {"ironskin_potion": 480, "regeneration_potion": 480, "swiftness_potion": 480, "mining_potion": 600, "archery_potion": 480}
	for n in times:
		check(Items.defs[Items.ids[n]].buff_time == times[n] and Buffs.defs.has(Items.defs[Items.ids[n]].buff), "%s dura %d s" % [n, times[n]])
	check(is_equal_approx(Items.defs[Items.ids.recall_potion].recall, 0.167) and is_equal_approx(Items.defs[Items.ids.magic_mirror].recall, 0.75) and Items.use_dur(Items.ids.magic_mirror) == 1.5, "Recall Potion 0,167 s e Magic Mirror 0,75 s de espera (uso 1,5 s)")
	# cura e Doença da poção
	give.call("lesser_healing_potion", 3)
	p.hp = 30.0
	p.use_item()
	check(is_equal_approx(p.hp, 80.0) and p.inv.total(Items.ids.lesser_healing_potion) == 2 and is_equal_approx(p.buffs.potion_sickness, 60.0), "beber cura 50, gasta a poção e dá Doença da poção (60 s)")
	p.cooldown = 0.0
	p.use_item()
	check(is_equal_approx(p.hp, 80.0) and p.inv.total(Items.ids.lesser_healing_potion) == 2 and p.message.contains("Doença"), "com a Doença da poção não bebe outra de cura")
	p.tick(60.5)
	check(not p.has_buff("potion_sickness"), "a Doença da poção passa em 60 s")
	p.hp = 90.0
	p.cooldown = 0.0
	p.use_item()
	check(is_equal_approx(p.hp, 100.0), "a cura para na vida máxima (%.0f)" % p.hp)
	p.max_hp = 200
	p.buffs.clear()
	p.hp = 100.0
	p.quick_heal()
	check(is_equal_approx(p.hp, 150.0) and p.inv.total(Items.ids.lesser_healing_potion) == 0, "H/Q: cura com a poção que há (max_hp 200)")
	p.quick_heal()
	check(p.message.contains("sem poção"), "sem poção, avisa")
	p.max_hp = 100
	# Ironskin: +8 de defesa, some no fim
	var base_def: int = p.defense()
	give.call("ironskin_potion")
	p.buffs.clear()
	p.hp = 100.0
	p.use_item()
	check(p.defense() == base_def + 8 and is_equal_approx(p.buffs.ironskin, 480.0), "Ironskin: +8 de defesa por 8 minutos")
	p.iframes = 0.0
	check(p.hurt(30, Vector3.RIGHT) == 26, "com 8 de defesa 30 de dano vira 26 (30 − 4)")
	p.tick(481.0)
	check(p.defense() == base_def and p.buffs.is_empty(), "e o buff acaba")
	# Regeneração: +2 de vida por segundo além do 1 base
	p.hp = 40.0
	p.since_hit = 99.0
	p.tick(1.0)
	var plain: float = p.hp - 40.0
	p.hp = 40.0
	p.add_buff("regeneration", 480.0)
	p.tick(1.0)
	check(is_equal_approx(plain, 1.0) and is_equal_approx(p.hp - 40.0, 3.0), "Regeneração: +2 de vida por segundo (1 → 3)")
	p.buffs.clear()
	# Rapidez: +25% de velocidade
	p.knock = Vector3.ZERO   # o golpe de antes empurrou
	p.position = Vector3(20.5, 11, 24.5)
	p.step(dt, Vector3.RIGHT, false)
	var x0: float = p.position.x
	p.add_buff("swiftness", 480.0)
	for i in 60:
		p.step(dt, Vector3.RIGHT, false)
	check(absf(p.position.x - x0 - 6.6 * 1.25) < 0.06, "Rapidez: 25%% mais rápido (%.2f blocos em 1 s)" % (p.position.x - x0))
	p.buffs.clear()
	# Mineração: só picareta, ⌊15 × 0,75⌋ = 11 quadros (wiki Tool speed)
	var pick: int = Items.ids.copper_pickaxe
	var axe: int = Items.ids.copper_axe
	p.add_buff("mining", 600.0)
	check(is_equal_approx(p.use_time(pick), 11.0 / 60.0) and is_equal_approx(p.use_time(axe), 21.0 / 60.0), "Mineração: picareta de 15 para 11 quadros; o machado não muda")
	p.buffs.clear()
	check(is_equal_approx(p.use_time(pick), 15.0 / 60.0), "sem o buff volta a 15")
	# Arquearia: +10% de dano e +20% de velocidade nas flechas
	p.inv = Inventory.new()
	p.inv.add(Items.ids.wooden_arrow, 4)
	var eye: Vector3 = p.position + Vector3.UP * p.EYE
	p.shoot(Items.defs[Items.ids.wooden_bow], eye, Vector3.RIGHT)
	var plain_arrow: Node3D = ent.get_children().back()
	p.add_buff("archery", 480.0)
	p.shoot(Items.defs[Items.ids.wooden_bow], eye, Vector3.RIGHT)
	var fast_arrow: Node3D = ent.get_children().back()
	check(plain_arrow.damage == 9 and fast_arrow.damage == 10 and is_equal_approx(fast_arrow.velocity.length() / plain_arrow.velocity.length(), 1.2), "Arquearia: dano 9 → 10 e flecha 20%% mais rápida (%d, %.2f×)" % [fast_arrow.damage, fast_arrow.velocity.length() / plain_arrow.velocity.length()])
	p.buffs.clear()
	# B: um de cada buff novo
	p.inv = Inventory.new()
	for n in ["ironskin_potion", "ironskin_potion", "swiftness_potion", "lesser_healing_potion"]:
		p.inv.add(Items.ids[n], 1)
	p.quick_buff()
	check(p.has_buff("ironskin") and p.has_buff("swiftness") and not p.has_buff("potion_sickness") and p.inv.total(Items.ids.ironskin_potion) == 1, "B bebe uma poção de cada buff (a de cura não)")
	p.quick_buff()
	check(p.inv.total(Items.ids.ironskin_potion) == 1, "e não repete o que já está ativo")
	p.buffs.clear()
	# Recall Potion e Magic Mirror: teleporte para casa depois da espera
	p.spawn = Vector3(30.5, 11, 30.5)
	give.call("recall_potion", 2)
	p.position = Vector3(20.5, 11, 20.5)
	p.use_item()
	check(p.inv.total(Items.ids.recall_potion) == 1 and p.recall_left > 0.0 and p.position.x == 20.5, "Recall Potion: gasta uma e espera")
	p.tick(0.2)
	check(p.position == p.spawn and p.recall_left <= 0.0, "e leva para o spawn depois de 0,167 s")
	give.call("magic_mirror")
	p.position = Vector3(20.5, 11, 20.5)
	p.cooldown = 0.0
	p.use_item()
	p.tick(0.5)
	check(p.inv.total(Items.ids.magic_mirror) == 1 and p.position.x == 20.5, "Magic Mirror: não gasta e ainda espera aos 0,5 s")
	p.tick(0.3)
	check(p.position == p.spawn, "e leva para casa aos 0,75 s")
	# Cloud in a Bottle: um pulo a mais no ar, com um aperto novo; o chão recarrega
	var land := func():
		p.position = Vector3(24.5, 11.0, 24.5)
		p.velocity = Vector3.ZERO
		p.inv.acc[0] = -1
		for i in 5:
			p.step(dt, Vector3.ZERO, false)
	var peak := func(cloud: bool, taps: Array) -> float:   # taps = quadros em que Espaço está apertado
		land.call()
		if cloud:
			p.inv.acc[0] = Items.ids.cloud_in_a_bottle
			p.step(dt, Vector3.ZERO, false)
		var top := 0.0
		for i in 240:
			p.step(dt, Vector3.ZERO, i in taps)
			top = maxf(top, p.position.y - 11.0)
		return top
	var single: float = peak.call(false, [0])
	var doubled: float = peak.call(true, [0, 30])
	var triple: float = peak.call(true, [0, 30, 60])
	print("pulo simples %.2f, com o Cloud in a Bottle %.2f, terceiro toque %.2f" % [single, doubled, triple])
	check(doubled > single + 0.5 and absf(triple - doubled) < 0.05, "Cloud in a Bottle: 1 pulo extra (%.2f contra %.2f) e nunca dois" % [doubled, single])
	free_player(p)
	w.free()
	return true


# Baús e cristais do mundo inteiro de uma seed, contados uma vez para os testes (leva ~3 s).
var census_cache := {}


func world_census() -> Dictionary:
	if census_cache.is_empty():
		var gen := WorldGen.new(4242)
		var r := {"crystals": 0, "bad_crystals": 0, "chests": {"underground": 0, "cavern": 0, "lava": 0}, "bad_chests": 0}
		for cz in WorldGen.SIZE_CHUNKS:
			for cx in WorldGen.SIZE_CHUNKS:
				var d := gen.generate(cx, cz)
				for i in d.size():
					var y := i / (C * C)
					var below := d[i - C * C] if y > 0 else 0
					if d[i] == Blocks.ids.life_crystal:
						r.crystals += 1
						r.bad_crystals += int(y <= WorldGen.UNDERWORLD_TOP or y > WorldGen.SURFACE - 14 or not (below == gen.STONE or below == gen.DIRT or below == Blocks.ids.dungeon_brick))
					elif d[i] == Blocks.ids.chest:
						r.chests[Loot.layer_of(y)] += 1
						r.bad_chests += int(y <= WorldGen.UNDERWORLD_TOP or y > WorldGen.SURFACE - 14 or not (below == gen.STONE or below == gen.DIRT or below == Blocks.ids.dungeon_brick))
		census_cache = r
	return census_cache


# Life Crystal (wiki): +20 de vida máxima até 400; brilha na caverna, quebra com qualquer picareta e cai como item; gerado no subsolo/cavernas, nunca no submundo.
func test_life_crystal():
	var b: int = Blocks.ids.life_crystal
	var id: int = Items.ids.life_crystal
	check(Blocks.breakable[b] == 1 and Blocks.solid[b] == 0 and Blocks.shape[b] == "crystal" and Blocks.light[b] > 0 and Blocks.soft[b] == 0, "o cristal é um bloco que brilha, sem colisão e que a mira acerta")
	check(Items.places[id] == -1 and Items.defs[id].life == 20 and Items.defs[id].consumable and Items.drop[b] == id, "o item é consumível (+20) e não se coloca; o bloco solta ele")
	var w := floor_world()
	var p := make_player(w)
	var ent: Node3D = p.entities
	w.set_block(20, 11, 20, b)
	p.target = {"pos": Vector3i(20, 11, 20), "normal": Vector3i.UP}
	p.inv.add(Items.ids.copper_pickaxe, 1)
	p.slot = p.inv.item.find(Items.ids.copper_pickaxe)
	p.break_target()
	check(w.get_block(20, 11, 20) == 0 and ent.get_children().any(func(n): return n.get("item") == id), "1 golpe com a picareta de cobre quebra e solta o item")
	p.inv = Inventory.new()
	p.inv.add(id, 20)
	p.slot = 0
	p.hp = 60.0
	p.use_item()
	check(p.max_hp == 120 and is_equal_approx(p.hp, 80.0) and p.inv.total(id) == 19, "usar: +20 de vida máxima e de vida, e gasta o cristal")
	for i in 14:
		p.cooldown = 0.0
		p.use_item()
	check(p.max_hp == 400 and p.inv.total(id) == 5, "15 cristais levam a vida máxima a 400")
	p.cooldown = 0.0
	p.use_item()
	check(p.max_hp == 400 and p.inv.total(id) == 5 and p.message.contains("400"), "o 16º é recusado e não se gasta")
	p.iframes = 0.0
	p.hp = 400.0
	p.hurt(1000, Vector3.RIGHT)
	check(p.hp == 400.0, "morrer renasce com a vida máxima nova")
	# geração: cristais no chão das cavernas, do subsolo às cavernas, nunca no submundo; ~1 a cada 3 chunks
	var cs: Dictionary = world_census()
	print("cristais: %d no mundo de %d chunks" % [cs.crystals, WorldGen.SIZE_CHUNKS * WorldGen.SIZE_CHUNKS])
	check(cs.crystals >= 40 and cs.crystals <= 110 and cs.bad_crystals == 0, "o mundo tem ~1 cristal a cada 3 chunks (%d), no chão e fora do submundo (%d fora do lugar)" % [cs.crystals, cs.bad_crystals])
	free_player(p)
	w.free()
	return true


# Loot dos baús (wiki Gold Chest): 1 item principal + comuns sorteados por camada (data/base/loot.json), conjuntos que não vêm juntos, quantidades
# dentro da faixa, determinístico por seed e posição; o mundo gera baús nas três camadas.
func test_loot():
	for layer in ["underground", "cavern", "lava"]:
		var t: Dictionary = Loot.tables[layer]
		var ok: bool = t.main.all(func(n): return Items.ids.has(n))
		for e in t.common:
			ok = ok and e.items.all(func(n): return Items.ids.has(n)) and e.min <= e.max and e.chance > 0.0 and e.chance <= 1.0
		check(ok, "loot %s: todos os itens existem, faixas e chances válidas" % layer)
	check(Loot.layer_of(60) == "underground" and Loot.layer_of(WorldGen.CAVERN_TOP - 1) == "cavern" and Loot.layer_of(WorldGen.CAVERN_TOP) == "underground" and Loot.layer_of(40) == "cavern" and Loot.layer_of(25) == "lava" and Loot.layer_of(WorldGen.UNDERWORLD_TOP + 2) == "lava", "a altura decide a camada")
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var n := 4000
	var main_count := {}
	var lesser := 0
	var lesser_min := 99
	var lesser_max := 0
	var regen := 0
	var both_bars := 0
	var torches_ok := true
	var first_is_main := true
	for i in n:
		var c: Dictionary = Loot.chest("underground", rng)
		var items: Array = Array(c.item).filter(func(id): return id != -1)
		first_is_main = first_is_main and Loot.tables.underground.main.has(Items.names[c.item[0]]) and c.count[0] == 1 and items.count(c.item[0]) == 1
		main_count[c.item[0]] = main_count.get(c.item[0], 0) + 1
		for k in 40:
			var id: int = c.item[k]
			if id == Items.ids.lesser_healing_potion:
				lesser += 1
				lesser_min = mini(lesser_min, c.count[k])
				lesser_max = maxi(lesser_max, c.count[k])
			elif id == Items.ids.regeneration_potion:
				regen += 1
			elif id == Items.ids.torch:
				torches_ok = torches_ok and c.count[k] >= 10 and c.count[k] <= 20
		both_bars += int(items.has(Items.ids.iron_bar) and items.has(Items.ids.lead_bar))
	check(first_is_main, "cada baú tem exatamente 1 item principal, no 1º slot")
	var even := true
	for id in main_count:
		even = even and absf(main_count[id] / float(n) - 0.25) < 0.03
	check(even and main_count.size() == 4, "os 4 principais saem com ~1/4 cada (renormalizado do 1/6 da wiki)")
	check(absf(lesser / float(n) - 0.5) < 0.03 and lesser_min == 3 and lesser_max == 5, "Lesser Healing: 3-5 em ~50%% dos baús (%.3f)" % (lesser / float(n)))
	check(absf(regen / float(n) - 0.667) < 0.03, "Regeneration em ~2/3 (%.3f)" % (regen / float(n)))
	check(both_bars == 0 and torches_ok, "ferro e chumbo nunca juntos (mesmo conjunto); tochas 10-20 no subsolo")
	rng.seed = 6
	var meteor := 0
	for i in 1000:
		var c: Dictionary = Loot.chest("lava", rng)
		for k in 40:
			meteor += int(c.item[k] == Items.ids.meteorite_bar)
	check(meteor > 50, "baús perto do submundo podem ter barra de meteorito (%d em 1000)" % meteor)
	# determinístico por seed e posição
	var w1: Node3D = load("res://scripts/world.gd").new()
	var w2: Node3D = load("res://scripts/world.gd").new()
	var w3: Node3D = load("res://scripts/world.gd").new()
	w1.world_seed = 9
	w2.world_seed = 9
	w3.world_seed = 10
	var pos := Vector3i(30, 40, 30)
	check(w1.chest_at(pos).item == w2.chest_at(pos).item and w1.chest_at(pos).count == w2.chest_at(pos).count, "o mesmo baú, a mesma seed: o mesmo conteúdo")
	check(w1.chest_at(pos).item != w3.chest_at(pos).item or w1.chest_at(pos).count != w3.chest_at(pos).count or w1.chest_at(Vector3i(31, 40, 30)).item != w1.chest_at(pos).item, "outra seed ou posição muda o conteúdo")
	w1.free()
	w2.free()
	w3.free()
	# orbes: a 1ª dá arma + 100 balas; as seguintes 20% (wiki Shadow Orb / Crimson Heart)
	var w4 := floor_world()
	var pl := make_player(w4)
	var ent: Node3D = pl.entities
	var guns := func(item: String) -> int:
		return ent.get_children().filter(func(n): return n.get("item") == Items.ids[item]).size()
	ent.orb_broken(Blocks.ids.shadow_orb)
	check(guns.call("musket") == 1 and ent.get_children().any(func(n): return n.get("item") == Items.ids.musket_ball and n.count == 100), "1ª Shadow Orb: Musket + 100 Musket Balls")
	ent.rng.seed = 3
	for i in 200:
		ent.orb_broken(Blocks.ids.crimson_heart)
	var extra: int = guns.call("the_undertaker")
	check(extra > 20 and extra < 60 and guns.call("musket") == 1, "as outras: ~20%% (%d de 200; a arma é a do bioma)" % extra)
	var gd: Dictionary = Items.defs[Items.ids.musket]
	check(gd.damage == 31 and gd.ammo == "bullet" and Items.defs[Items.ids.musket_ball].damage == 7 and Items.defs[Items.ids.musket_ball].ammo_class == "bullet", "Musket 31 de dano + Musket Ball 7 (wiki)")
	free_player(pl)
	w4.free()
	# geração: baús no chão das três camadas
	var cs: Dictionary = world_census()
	var total: int = cs.chests.underground + cs.chests.cavern + cs.chests.lava
	print("baús: %s (%d, fora do lugar %d)" % [str(cs.chests), total, cs.bad_chests])
	check(cs.chests.underground >= 5 and cs.chests.cavern >= 5 and cs.chests.lava >= 5 and total >= 40 and total <= 90 and cs.bad_chests == 0, "baús nas 3 camadas, em cima de pedra, fora do submundo e da superfície")
	return true


# Mana e magia (wiki Mana): 20 iniciais, +20 por Mana Crystal até 200 (5 Fallen Stars), regeneração pela fórmula, sem mana ainda usa com 60% de penalidade.
func test_mana():
	var w := floor_world()
	var p := make_player(w)
	var dt := 1.0 / 60
	check(p.max_mana == 20 and is_equal_approx(p.mana, 20.0), "começa com 20 de mana")
	# regeneração parado: (20/3+1) × 2 × (mana/máx × 0,5 + 0,5) ÷ 2 por segundo; com mana 0 o fator é 0,5
	p.mana = 0.0
	p.mana_use = 9.0
	for i in 60:
		p.tick(dt)
	var want := (20.0 / 3.0 + 1.0) * 2.0 * 0.5 / 2.0
	check(absf(p.mana - want) < 0.6, "parado com 0 de mana: %.2f por segundo (fórmula %.2f)" % [p.mana, want])
	p.mana = 0.0
	p.velocity = Vector3(5, 0, 0)
	for i in 60:
		p.tick(dt)
	check(absf(p.mana - want / 2.0) < 0.4, "andando regenera a metade (%.2f)" % p.mana)
	p.velocity = Vector3.ZERO
	p.mana = 10.0
	p.mana_use = 0.0
	p.tick(dt)
	check(p.mana - 10.0 < 0.01, "usando mana a regeneração cai a 5%")
	# varinha
	var wand: Dictionary = Items.defs[Items.ids.wand_of_sparking]
	check(wand.damage == 14 and wand.cost == 2 and absf(wand.use_time - 26.0 / 60.0) < 0.001 and is_equal_approx(wand.crit, 0.14), "Wand of Sparking: 14 de dano, 2 de mana, use 26, crítico 14%")
	check(Items.defs[Items.ids.space_gun].cost == 6 and Items.defs[Items.ids.vilethorn].cost == 10 and Items.autoswing(Items.ids.space_gun) and not Items.autoswing(Items.ids.vilethorn), "Space Gun 6 (autoswing), Vilethorn 10")
	# poções e cristal
	p.inv = Inventory.new()
	p.inv.add(Items.ids.mana_potion, 1)
	p.inv.add(Items.ids.lesser_mana_potion, 1)
	p.inv.add(Items.ids.mana_crystal, 12)
	p.mana = 0.0
	p.quick_mana()
	check(is_equal_approx(p.mana, 20.0) and p.inv.total(Items.ids.lesser_mana_potion) == 0 and p.inv.total(Items.ids.mana_potion) == 1, "J: a poção menor que enche o que falta (a de 50 sobra 30)")
	p.slot = p.inv.item.find(Items.ids.mana_crystal)
	for i in 9:
		p.cooldown = 0.0
		p.use_item()
	check(p.max_mana == 200 and p.inv.total(Items.ids.mana_crystal) == 3, "9 cristais: 20 → 200")
	p.cooldown = 0.0
	p.use_item()
	check(p.max_mana == 200 and p.inv.total(Items.ids.mana_crystal) == 3, "o 10º é recusado")
	var rec: Array = Crafting.recipes.filter(func(r): return r.result == Items.ids.mana_crystal)
	check(rec.size() == 1 and rec[0].needs == {Items.ids.fallen_star: 5}, "Mana Crystal = 5 Fallen Stars")
	# estrela cadente: só à noite, some ao amanhecer
	var ent: Node3D = p.entities
	ent.rng.seed = 1
	p.clock.time = p.clock.DAY_SECONDS + 60
	for i in 400:
		ent._stars()
	var stars: Array = ent.get_children().filter(func(n): return n.get("item") == Items.ids.fallen_star)
	check(stars.size() > 3, "à noite caem estrelas (%d)" % stars.size())
	p.clock.time = 60.0
	ent._stars()
	check(ent.get_children().filter(func(n): return n.get("item") == Items.ids.fallen_star and not n.is_queued_for_deletion()).is_empty(), "de dia elas somem")
	free_player(p)
	w.free()
	return true


# Habitantes (wiki Guide/Merchant/Nurse): o Guide já está no mundo, o Merchant chega com mais de 50 de prata, a Nurse com mais de 100 de vida máxima;
# loja cobra as moedas certas e a Nurse cura pelo que falta.
func test_npc():
	var w := floor_world()
	var p := make_player(w)
	var ent: Node3D = p.entities
	var has := func(n: String) -> bool: return ent.enemies.any(func(e): return e.def.name == n)
	ent._town()
	check(has.call("guide") and not has.call("merchant") and not has.call("nurse"), "o Guide está no mundo; os outros ainda não chegaram")
	p.inv.coin = PackedInt32Array([0, 49, 0, 0])
	ent._town()
	check(not has.call("merchant"), "com 49 de prata o Merchant não chega")
	p.inv.coin = PackedInt32Array([1, 50, 0, 0])
	ent._town()
	check(has.call("merchant") and w.npcs.has("merchant"), "com mais de 50 de prata o Merchant chega")
	p.max_hp = 120
	ent._town()
	check(has.call("nurse"), "com mais de 100 de vida máxima a Nurse chega")
	var guide: Node3D = ent.enemies.filter(func(e): return e.def.name == "guide")[0]
	ent.remove_enemy(guide)
	ent._town()
	check(has.call("guide"), "quem some volta a aparecer perto do spawn")
	# pagar e o troco
	p.inv.coin = PackedInt32Array([0, 0, 1, 0])   # 1 de ouro = 10000 cobre
	check(p.inv.pay(500) and p.inv.coin_value() == 9500 and p.inv.coin[1] == 95 and not p.inv.pay(9999), "pagar 5 de prata de 1 de ouro sobra 95 de prata; sem saldo recusa")
	# a loja: preço da wiki (Copper Pickaxe 5 de prata) e a Nurse
	var hud: CanvasLayer = load("res://scripts/hud.gd").new()
	check(hud.SHOP[0] == ["copper_pickaxe", 500] and Items.ids.has(hud.SHOP[3][0]), "loja: Copper Pickaxe a 5 de prata")
	hud.free()
	free_player(p)
	w.free()
	return true


# Voo como o Terraria: asas (acessório) dão voo enquanto se segura Espaço no ar e há tempo de voo (Fledgling: 0,42 s), depois planam (gravidade e queda
# em 1/3); o chão recarrega. O modo criativo (F) é à parte: atravessa blocos e não leva dano.
func test_wings():
	var w := floor_world()
	var p := make_player(w)
	var dt := 1.0 / 60
	var land := func():
		p.position = Vector3(24.5, 11.0, 24.5)
		p.velocity = Vector3.ZERO
		for i in 5:
			p.step(dt, Vector3.ZERO, false)
	var jump_peak := func(hold_frames: int) -> float:   # pico da altura pulando com Espaço apertado nos primeiros hold_frames quadros
		land.call()
		var top := 0.0
		for i in 240:
			p.step(dt, Vector3.ZERO, i < hold_frames)
			top = maxf(top, p.position.y - 11.0)
		return top
	var base: float = jump_peak.call(1)
	check(absf(float(jump_peak.call(240)) - base) < 0.05 and p.flight_left == 0.0 and not p.flapping, "sem asas, segurar Espaço no ar não muda nada (pulo de %.2f)" % base)
	var id: int = Items.ids.fledgling_wings
	p.inv.acc[0] = id
	var data: Dictionary = Items.defs[id].accessory.wings
	check(is_equal_approx(data.time, 0.42) and absf(data.lift - 22.0 * 0.733 / 1.667) < 0.3 and p.inv.wing_id() == id and p.inv.wings() == data, "Fledgling: 0,42 s de voo e 22 mph de subida (≈ 9,7 blocos/s)")
	check(Ui.item_tip(id).contains("voar") and Items.autoswing(id) == false, "a dica diz que permite voar")
	land.call()
	check(is_equal_approx(p.flight_left, 0.42), "no chão o tempo de voo está cheio")
	# segurando Espaço: sobe mais que o pulo, gasta 0,42 s e planeia
	land.call()
	var flap_frames := 0
	var top := 0.0
	var glide_speed := 0.0
	for i in 300:
		p.step(dt, Vector3.ZERO, true)
		flap_frames += int(p.flapping)
		top = maxf(top, p.position.y - 11.0)
		if p.gliding:
			glide_speed = minf(glide_speed, p.velocity.y)
		if p.on_floor and i > 5:   # pousou: segurando Espaço pularia de novo
			break
	p.step(dt, Vector3.ZERO, false)
	print("voo: pulo de %.2f blocos, com as asas %.2f, %d quadros de batida, planeio a %.2f blocos/s" % [base, top, flap_frames, glide_speed])
	check(flap_frames >= 24 and flap_frames <= 27, "o voo dura 0,42 s (%d quadros de batida)" % flap_frames)
	check(top > base + 1.5 and top < base + 5.0, "voando sobe ~3 blocos acima do pulo simples (%.2f contra %.2f)" % [top, base])
	check(absf(glide_speed + p.GLIDE_FALL) < 0.15, "depois planeia: a queda para em 1/3 da máxima (%.2f blocos/s)" % glide_speed)
	check(p.on_floor and is_equal_approx(p.flight_left, 0.42), "e o chão recarrega o tempo de voo")
	# sem segurar Espaço cai normal, mais rápido que o planeio
	land.call()
	p.position.y += 20.0
	var free_fall := 0.0
	for i in 60:
		p.step(dt, Vector3.ZERO, false)
		free_fall = minf(free_fall, p.velocity.y)
	check(free_fall < -14.0 and is_equal_approx(p.flight_left, 0.42) and not p.gliding, "sem Espaço cai de verdade (%.1f blocos/s) e o tempo de voo não gasta" % free_fall)
	# o tempo só gasta segurando
	land.call()
	for i in 12:
		p.step(dt, Vector3.ZERO, true)
	var after_hold: float = p.flight_left
	for i in 30:
		p.step(dt, Vector3.ZERO, false)
	check(after_hold < 0.42 - 0.1 and is_equal_approx(p.flight_left, after_hold), "o tempo de voo gasta só enquanto Espaço está apertado (%.2f)" % after_hold)
	# tirar as asas: volta a gravidade normal
	p.inv.acc[0] = -1
	p.step(dt, Vector3.ZERO, true)
	check(not p.flapping and p.inv.wings().is_empty(), "sem as asas não voa")
	# modo criativo: F liga e desliga, atravessa blocos e ninguém machuca
	land.call()
	p._unhandled_input(key(KEY_F))
	check(p.creative, "F liga o modo criativo")
	p.iframes = 0.0
	check(p.hurt(50, Vector3.RIGHT) == 0, "no modo criativo não leva dano")
	w.set_block(26, 11, 24, Blocks.ids.stone)
	p.step(1.0, Vector3(1, 0, 0), false)
	check(p.position.x > 30.0, "e atravessa blocos")
	p._unhandled_input(key(KEY_F))
	check(not p.creative, "F de novo desliga")
	free_player(p)
	w.free()
	return true


# Danos da wiki: variância de ±15% antes da defesa (⌈def/2⌉), crítico de 4% que dobra depois dela (+40% de recuo), jogador leva ⌊dano − def × 0,5⌋,
# recuos das criaturas pela wiki, martelos (só martelo quebra Shadow Orb / Crimson Heart).
func test_damage():
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var lo := 999
	var hi := 0
	var sum := 0
	var n := 20000
	for i in n:
		var v := Combat.vary(100, rng)
		lo = mini(lo, v)
		hi = maxi(hi, v)
		sum += v
	check(lo == 85 and hi == 115 and absf(float(sum) / n - 100.0) < 0.3, "variância: 100 de dano vai de 85 a 115 e a média é 100 (%d a %d, média %.2f)" % [lo, hi, float(sum) / n])
	var crits := 0
	for i in 50000:
		crits += int(Combat.is_crit(rng))
	check(absf(crits / 50000.0 - 0.04) < 0.004, "crítico de 4%% (%.3f)" % (crits / 50000.0))
	var w := floor_world()
	var p := make_player(w)
	var ent: Node3D = p.entities
	var zombie := func() -> Node3D:
		var z: Node3D = ent.spawn_enemy(enemy_def("zombie"), Vector3(26, 11, 24.5))
		z._ready()
		return z
	var z: Node3D = zombie.call()
	check(z.hurt(20, Vector3.RIGHT, 0.0) == 17, "defesa 6: 20 de dano vira 17 (20 − ⌈6/2⌉)")
	ent.remove_enemy(z)
	z = zombie.call()
	check(z.hurt(20, Vector3.RIGHT, 0.0, true) == 34, "crítico dobra DEPOIS da defesa: (20 − 3) × 2 = 34 e não 20 × 2 − 3")
	ent.remove_enemy(z)
	z = zombie.call()
	z.hurt(10, Vector3.RIGHT, 6.0)
	var kb_normal: float = z.velocity.x
	ent.remove_enemy(z)
	z = zombie.call()
	z.hurt(10, Vector3.RIGHT, 6.0, true)
	check(is_equal_approx(kb_normal, 3.0) and is_equal_approx(z.velocity.x, 4.2), "recuo 6 com o zumbi (50% de resistência) = 3; crítico dá +40% = 4,2")
	ent.remove_enemy(z)
	# recuos (resistência) de cada criatura, da tabela NPCs da wiki
	var wiki_kb := {"green_slime": -0.2, "blue_slime": 0.0, "zombie": 0.5, "demon_eye": 0.2, "servant_of_cthulhu": 0.0, "eye_of_cthulhu": 1.0, "eater_of_souls": 0.5, "crimera": 0.5,
		"eater_of_worlds": 1.0, "creeper": 0.2, "brain_of_cthulhu": 0.55, "king_slime": 1.0, "angry_bones": 0.2, "cursed_skull": 0.8, "dark_caster": 0.4, "old_man": 0.5, "skeletron": 1.0,
		"voodoo_demon": 0.2, "hellbat": 0.2, "the_hungry": -0.1, "wall_of_flesh": 1.0, "pixie": 0.4, "unicorn": 0.7}
	var wrong := []
	for name in wiki_kb:
		if not is_equal_approx(enemy_def(name).get("kb_resist", 0.0), wiki_kb[name]):
			wrong.append(name)
	check(wrong.is_empty(), "resistência a recuo de todas as criaturas bate com a wiki (erradas: %s)" % str(wrong))
	# jogador: ⌊dano − defesa × 0,5⌋, mínimo 1, depois da variância (quem chama sorteia)
	for set_name in [[], ["copper_helmet", "copper_chainmail", "copper_greaves"], ["gold_helmet", "gold_chainmail", "gold_greaves"], ["platinum_helmet", "platinum_chainmail", "platinum_greaves"]]:
		p.inv = Inventory.new()
		for k in set_name.size():
			p.inv.equip[k] = Items.ids[set_name[k]]
		var def: int = p.inv.defense()
		p.iframes = 0.0
		p.hp = 100.0
		var taken: int = p.hurt(30, Vector3.RIGHT)
		check(taken == maxi(1, floori(30.0 - def * 0.5)), "jogador com %d de defesa leva ⌊30 − %d × 0,5⌋ = %d (levou %d)" % [def, def, floori(30.0 - def * 0.5), taken])
	p.iframes = 0.0
	check(p.hurt(2, Vector3.RIGHT) == 1, "o mínimo é 1")
	# martelos: poder e tool speed da wiki; orbe e coração só quebram com martelo
	var power := {"wooden_hammer": 25, "copper_hammer": 35, "tin_hammer": 38, "iron_hammer": 40, "lead_hammer": 43, "silver_hammer": 45, "tungsten_hammer": 50, "gold_hammer": 55, "platinum_hammer": 59}
	var speed := {"wooden_hammer": 25, "copper_hammer": 23, "tin_hammer": 21, "iron_hammer": 20, "lead_hammer": 19, "silver_hammer": 19, "tungsten_hammer": 25, "gold_hammer": 23, "platinum_hammer": 21}
	for name in power:
		var id: int = Items.ids[name]
		check(Items.hammer_power[id] == power[name] and is_equal_approx(Items.use_dur(id), speed[name] / 60.0) and Items.autoswing(id) and Crafting.recipes.any(func(r): return r.result == id), "%s: poder %d%%, tool speed %d, autoswing e receita" % [name, power[name], speed[name]])
	for orb in ["shadow_orb", "crimson_heart"]:
		var b: int = Blocks.ids[orb]
		w.set_block(20, 11, 20, b)
		p.target = {"pos": Vector3i(20, 11, 20), "normal": Vector3i.UP}
		p.mine_damage = 0.0
		p.inv = Inventory.new()
		p.inv.add(Items.ids.iron_pickaxe, 1)
		p.slot = 0
		p.break_target()
		check(w.get_block(20, 11, 20) == b and p.mine_damage == 0.0 and p.message.contains("martelo"), "%s: a picareta não quebra e avisa que precisa de martelo" % orb)
		p.inv.add(Items.ids.wooden_hammer, 1)
		p.slot = 1
		for i in 3:
			p.break_target()
		check(w.get_block(20, 11, 20) == b and is_equal_approx(p.mine_damage, 75.0), "%s: o martelo de madeira (25%%) racha 25 por golpe (3 golpes = 75)" % orb)
		p.break_target()
		check(w.get_block(20, 11, 20) == 0 and w.orbs_broken >= 1, "%s: o 4º golpe quebra e conta como orbe quebrada" % orb)
		w.set_block(20, 11, 20, b)
		p.slot = 0
		p.target = {"pos": Vector3i(20, 11, 20), "normal": Vector3i.UP}
		p.auto_pick(true)
		check(p.slot == 1 and p.auto_prev == 0, "Auto Select em %s escolhe o martelo" % orb)
		p.auto_pick(false)
		w.set_block(20, 11, 20, 0)
	free_player(p)
	w.free()
	return true


# Usos que o item dá com o botão esquerdo apertado (só o clique inicial, sem soltar) durante `seconds`.
func hold_uses(p: Node3D, item: String, seconds: float) -> int:
	p.inv = Inventory.new()
	p.inv.add(Items.ids[item], 1)
	p.slot = 0
	p.cooldown = 0.0
	p.attack_held = true
	p.attack_buffer = p.CLICK_BUFFER
	var n := 0
	for i in int(seconds * 60):
		var before: float = p.cooldown
		p.attack(1.0 / 60)
		n += int(p.cooldown > before)
		p.cooldown -= 1.0 / 60
	p.attack_held = false
	p.attack_buffer = 0.0
	return n


# Ataque como o do Terraria: um clique = um uso (com buffer de 0,12 s), segurar só repete o que tem autoswing, no ritmo do use time (armas)
# ou do tool speed (picareta e machado), e a mira decide quem apanha (3 raios em leque contra a caixa do inimigo).
func test_attack():
	for n in ["copper_pickaxe", "copper_axe", "platinum_pickaxe", "terra_blade", "enchanted_sword", "cobalt_sword", "dirt", "torch", "empty_bucket", "acorn"]:
		check(Items.autoswing(Items.ids[n]), n + " tem autoswing (wiki)")
	for n in ["wooden_sword", "copper_shortsword", "iron_broadsword", "lights_bane", "blood_butcherer", "wooden_bow", "demon_bow", "suspicious_looking_eye"]:
		check(not Items.autoswing(Items.ids[n]), n + " exige um clique por uso (wiki)")
	check(is_equal_approx(Items.use_dur(Items.ids.copper_pickaxe), 15.0 / 60.0) and is_equal_approx(Items.use_dur(Items.ids.copper_axe), 21.0 / 60.0) and is_equal_approx(Items.use_dur(Items.ids.wooden_sword), 0.33), "ciclo: tool speed nas ferramentas (15 e 21 quadros), use time no resto")
	var w := floor_world()
	var p := make_player(w)
	var ent: Node3D = p.entities
	check(hold_uses(p, "iron_broadsword", 3.0) == 1 and hold_uses(p, "wooden_sword", 3.0) == 1, "sem autoswing: segurar o botão dá um uso só")
	var n := hold_uses(p, "copper_pickaxe", 2.0)
	check(n >= 7 and n <= 8, "picareta de cobre segurada: um golpe a cada 15 quadros, ~8 em 2 s (%d)" % n)
	n = hold_uses(p, "copper_axe", 2.0)
	check(n >= 5 and n <= 6, "machado de cobre: um golpe a cada 21 quadros, ~6 em 2 s (%d)" % n)
	n = hold_uses(p, "terra_blade", 2.0)
	check(n >= 6 and n <= 7, "Terra Blade (autoswing): a cada 18 quadros, ~7 em 2 s (%d)" % n)
	# clique no fim do golpe anterior espera (buffer); cedo demais se perde
	p.inv = Inventory.new()
	p.inv.add(Items.ids.iron_broadsword, 1)
	p.slot = 0
	for lag in [[0.08, 1], [0.30, 0]]:
		p.cooldown = lag[0]
		p.attack_buffer = p.CLICK_BUFFER
		n = 0
		for i in 40:
			var before: float = p.cooldown
			p.attack(1.0 / 60)
			n += int(p.cooldown > before)
			p.cooldown -= 1.0 / 60
		check(n == lag[1], "clique %.2f s antes de o golpe acabar: %s (buffer de %.2f s)" % [lag[0], "atendido" if lag[1] == 1 else "perdido", p.CLICK_BUFFER])
	# clique e soltar no mesmo quadro ainda bate uma vez, mesmo com autoswing
	p.inv = Inventory.new()
	p.inv.add(Items.ids.copper_pickaxe, 1)
	p.cooldown = 0.0
	p.attack_held = false
	p.attack_buffer = p.CLICK_BUFFER
	p.attack(1.0 / 60)
	check(p.cooldown > 0.0, "um clique rápido (soltou antes do quadro) ainda usa o item")
	# mira: quem está na frente, dentro do alcance, apanha; o resto não
	p.position = Vector3(24.5, 11, 24.5)
	var eye: Vector3 = p.position + Vector3.UP * p.EYE
	var at := func(v: Vector3, n: String = "zombie") -> Node3D:
		var e: Node3D = ent.spawn_enemy(enemy_def(n), v)
		e._ready()
		return e
	var z: Node3D = at.call(Vector3(26.5, 11, 24.5))
	check(p.melee_targets(eye, Vector3.RIGHT, 2.5) == [z], "o inimigo na mira, a 2 blocos, é acertado")
	check(p.melee_targets(eye, Vector3.LEFT, 2.5).is_empty(), "o que está atrás não é")
	check(p.melee_targets(eye, Vector3.RIGHT, 1.2).is_empty(), "e o que está além do alcance também não")
	z.position = eye + Vector3.RIGHT.rotated(Vector3.UP, deg_to_rad(15)) * 2.0
	z.position.y = 11
	check(p.melee_targets(eye, Vector3.RIGHT, 2.5) == [z], "15° fora da mira ainda é acertado (o leque)")
	z.position = eye + Vector3.RIGHT.rotated(Vector3.UP, deg_to_rad(45)) * 2.0
	z.position.y = 11
	check(p.melee_targets(eye, Vector3.RIGHT, 2.5).is_empty(), "45° fora da mira não é (sem cone largo)")
	z.position = Vector3(26.5, 11, 24.5)
	var z2: Node3D = at.call(Vector3(27.5, 11, 24.5))
	check(p.melee_targets(eye, Vector3.RIGHT, 3.2).size() == 2 and p.melee_targets(eye, Vector3.RIGHT, 2.0) == [z], "dois em fila: o alcance da arma decide quantos")
	var hp0: int = z.hp
	var hp1: int = z2.hp
	p.swing(Items.defs[Items.ids.terra_blade], eye, Vector3.RIGHT)
	check(z.hp < hp0 and z2.hp < hp1, "o golpe fere todos os alcançados")
	ent.remove_enemy(z)
	ent.remove_enemy(z2)
	var s: Node3D = at.call(Vector3(27.0, 11, 24.5), "green_slime")
	check(p.melee_targets(eye, Vector3.RIGHT, 3.2).is_empty(), "slime baixinho a 2,5 blocos: mirando reto por cima dele não acerta")
	check(p.melee_targets(eye, (s.position + Vector3(0, 0.4, 0) - eye).normalized(), 3.2) == [s], "olhando para ele, acerta")
	ent.remove_enemy(s)
	# recuo do projétil = arma + munição (wiki Knockback)
	p.inv = Inventory.new()
	p.inv.add(Items.ids.wooden_arrow, 2)
	p.inv.add(Items.ids.unholy_arrow, 2)
	p.shoot(Items.defs[Items.ids.wooden_bow], eye, Vector3.RIGHT)
	check(is_equal_approx(ent.get_children().back().knockback, 2.0), "arco de madeira (0) + flecha de madeira (2) = recuo 2")
	p.inv.take_ammo("arrow")
	p.shoot(Items.defs[Items.ids.demon_bow], eye, Vector3.RIGHT)
	check(is_equal_approx(ent.get_children().back().knockback, 4.0), "Demon Bow (1) + Unholy Arrow (3) = recuo 4")
	free_player(p)
	w.free()
	return true


# Verme com n segmentos (cabeça, corpos e rabo) em fila reta a partir de pos.
func make_worm(ent: Node3D, n: int, pos: Vector3) -> Array:
	var d: Dictionary = ent.def_named("eater_of_worlds").duplicate(true)
	d.worm.segments = n
	ent.spawn_worm(d, pos)
	return ent.enemies.filter(func(e): return e.def.get("group") == "eater_of_worlds")


func test_worm():
	var w := floor_world()
	var p := make_player(w)
	var ent: Node3D = p.entities
	p.position = Vector3(24.5, 11, 24.5)
	var head: Node3D = ent.spawn_boss("eater_of_worlds")
	var segs: Array = ent.enemies.filter(func(e): return e.def.get("group") == "eater_of_worlds")
	var total := 65 + 22 * 150 + 220   # wiki: cabeça 65, corpo 150, rabo 220
	check(segs.size() == 24 and ent.boss == head and ent.boss_max == total and ent.boss_life() == total, "verme: 24 segmentos com a vida da wiki (%d)" % ent.boss_life())
	check(segs[1].follow == head and segs[23].def.name == "eater_of_worlds_tail" and head.follow == null, "cada segmento segue o da frente")
	check(head.position.y < 11 - head.tall / 2.0, "o verme nasce debaixo da terra")
	var near := 99.0
	var out := 0.0
	var airborne := 0
	var gravity_ok := true
	var last_vy := 0.0
	var turn_ok := true
	var last_dir: Vector3 = head.heading
	for i in 60 * 4:
		for s in segs:
			s._physics_process(1.0 / 60)
		near = minf(near, head.position.distance_to(p.position))
		out = maxf(out, head.position.y)
		var inside: bool = Blocks.solid[w.get_block(floori(head.position.x), floori(head.position.y + head.tall / 2.0), floori(head.position.z))]
		if not inside and head.position.distance_to(p.position) < head.WORM_FREE:
			airborne += 1
			gravity_ok = gravity_ok and head.velocity.y < last_vy + 0.001   # no ar só cai: a velocidade vertical nunca sobe
		if not head.heading.is_zero_approx() and not last_dir.is_zero_approx():
			turn_ok = turn_ok and head.heading.angle_to(last_dir) <= head.WORM_TURN / 60.0 + 0.001
		last_vy = head.velocity.y
		last_dir = head.heading
	check(near < 4.0, "escavando, a cabeça chega ao jogador (%.1f)" % near)
	check(out > 11 and airborne > 20 and gravity_ok, "sai do chão e no ar só cai, em arco (%d quadros no ar)" % airborne)
	check(turn_ok, "dentro do terreno o giro da cabeça é limitado")
	var gap := 0.0
	for i in range(1, segs.size()):
		gap = maxf(gap, absf(segs[i].position.distance_to(segs[i].follow.position) - segs[i].def.size[0] * 0.8))
	check(gap < 0.05, "o corpo mantém a distância do segmento da frente (%.3f)" % gap)
	segs[10].hurt(1000, Vector3.RIGHT, 5)
	check(segs[11].follow == null and segs[11].def.head and segs[9].def.tail and not ent.enemies.has(segs[10]) and ent.boss == head, "segmento do meio morto: o de trás vira cabeça (com boca), o da frente vira rabo")
	check(segs[11].damage == 22 and segs[9].defense == 8 and ent.boss_life() == total - 150, "e trocam de papel: dano/defesa da wiki; a barra soma os vivos")
	head.hurt(1000, Vector3.RIGHT, 5)
	check(segs[1].follow == null and segs[1].def.head and ent.boss != head and ent.boss != null, "cabeça morta: outro segmento vira cabeça e o chefe da barra")
	for s in segs:
		if ent.enemies.has(s):
			s.hurt(1000, Vector3.RIGHT, 0)
	var scales := 0
	var ore := 0
	for n in ent.get_children():
		if n.get("item") == Items.ids.shadow_scale:
			scales += n.count
		if n.get("item") == Items.ids.demonite_ore:
			ore += n.count
	check(ent.boss == null and ent.enemies.is_empty() and scales >= 20 and ore >= 30, "último segmento morto: prêmio do chefe (escamas %d, demonita %d)" % [scales, ore])
	# divisão: pedaço de 1 segmento morre na hora
	var four := make_worm(ent, 4, Vector3(20, 20, 20))
	four[1].hurt(1000, Vector3.RIGHT, 0)   # [C, c1, c2, R]: sobra a cabeça sozinha (morre) e [c2, R] (c2 vira cabeça)
	check(not ent.enemies.has(four[0]) and four[2].def.head and four[2].follow == null and ent.enemies.has(four[3]) and ent.enemies.size() == 2, "corpo morto que deixa a cabeça sozinha: ela morre; o outro pedaço ganha cabeça")
	four[3].hurt(1000, Vector3.RIGHT, 0)   # rabo morto: c2 fica sozinho e morre
	check(ent.enemies.is_empty(), "rabo morto que deixa um segmento sozinho: ele morre")
	var two := make_worm(ent, 2, Vector3(20, 20, 20))
	two[0].hurt(1000, Vector3.RIGHT, 0)
	check(ent.enemies.is_empty(), "cabeça morta em verme de 2 segmentos: o rabo sozinho morre")
	var five := make_worm(ent, 5, Vector3(20, 20, 20))
	five[4].hurt(1000, Vector3.RIGHT, 0)
	check(five[3].def.tail and ent.enemies.size() == 4, "rabo morto: o segmento da frente vira rabo")
	for e in ent.enemies.duplicate():
		ent.remove_enemy(e)
	# orientação: a frente sobe por cima da vertical e desce do outro lado (a cabeça saindo do chão e voltando): o modelo não pode dar
	# flip (`looking_at` com UP gira ~180° num quadro quando a frente passa rente à vertical)
	var EnemyScript = load("res://scripts/enemy.gd")
	var b := Basis()
	var old_b := Basis()
	var worst := 0.0
	var old_worst := 0.0
	var prev_q := Quaternion(b)
	var old_prev := Quaternion(old_b)
	for i in 361:
		var phi := deg_to_rad(i * 0.5)   # de 0° a 180° no plano X–Y, com 1 mm de desvio em Z: passa rente à vertical
		var f := Vector3(cos(phi), sin(phi), 0.001).normalized()
		if i == 180:
			f = Vector3.UP   # e uma vez exatamente nela
		b = EnemyScript.orient(b, f, 1.0 / 60)
		if i != 180:
			old_b = Basis.looking_at(f, Vector3.UP)
		if i > 1:   # os primeiros quadros só alinham o modelo com a frente inicial
			worst = maxf(worst, prev_q.angle_to(Quaternion(b)))
			old_worst = maxf(old_worst, old_prev.angle_to(Quaternion(old_b)))
		prev_q = Quaternion(b)
		old_prev = Quaternion(old_b)
	check(worst < deg_to_rad(8.0), "orientação do segmento sem flip (%.1f° por passo)" % rad_to_deg(worst))
	check(old_worst > deg_to_rad(90.0), "(o looking_at antigo dava flip: %.0f° num passo)" % rad_to_deg(old_worst))
	w.world_seed = 1
	p.world.orbs_broken = 0
	for i in 3:
		ent.orb_broken(Blocks.ids.shadow_orb)
	check(ent.boss != null and ent.boss.def.name == "eater_of_worlds" and p.world.orbs_broken == 3, "o 3º orbe quebrado acorda o Eater of Worlds")
	free_player(p)
	w.free()
	return true


func test_brain():
	var w := floor_world()
	var p := make_player(w)
	var ent: Node3D = p.entities
	var brain: Node3D = ent.spawn_boss("brain_of_cthulhu")
	var creepers: Array = ent.enemies.filter(func(e): return e.def.name == "creeper")
	check(creepers.size() == 20 and ent.boss == brain and ent.boss_max == 1250 + 20 * 100, "o cérebro nasce com 20 Creepers (barra soma tudo)")
	brain._ready()   # monta o modelo (fora da árvore ele ainda não existe)
	var parts: Array = brain.model.find_children("", "MeshInstance3D", true, false)
	check(parts.size() > 10 and parts.all(func(m): return m.material_override.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA and m.material_override.albedo_color.a < 1.0), "fase 1: cérebro translúcido (alpha no material, o Compatibility ignora transparency)")
	check(brain.hurt(500, Vector3.RIGHT, 0) == 0 and brain.hp == 1250, "fase 1: imune enquanto houver Creepers")
	var far := 0.0
	for i in 60 * 4:
		for e in ent.enemies:
			e._physics_process(1.0 / 60)
	for c in creepers:
		far = maxf(far, c.position.distance_to(brain.position))
	check(far < 14.0, "os Creepers orbitam o cérebro (%.1f)" % far)
	check(creepers[0].hurt(1000, Vector3.RIGHT, 0) == 1000 - 5 and creepers.size() == 20, "Creeper: defesa 10")
	var tissue := ent.get_children().filter(func(n): return n.get("item") == Items.ids.tissue_sample).size()
	for c in creepers.slice(1):
		c.hurt(1000, Vector3.RIGHT, 0)
	brain.think(1.0 / 60)
	check(brain.phase == 2 and brain.hurt(100, Vector3.RIGHT, 0) == 100 - 7, "sem Creepers: fase 2, vulnerável (defesa 14)")
	check(parts.all(func(m): return m.material_override.albedo_color.a == 1.0 and m.material_override.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED), "fase 2: cérebro sólido")
	check(ent.boss_max == 1250, "fase 2: a barra passa a contar só o cérebro (%d)" % ent.boss_max)
	var moved := 0.0
	var last: Vector3 = brain.position
	for i in 60 * 6:
		brain._physics_process(1.0 / 60)
		moved = maxf(moved, brain.position.distance_to(last))
		last = brain.position
	check(moved > 2.0 and brain.hp < 1250, "fase 2: teleporta e investe (%.1f de salto)" % moved)
	brain.hurt(5000, Vector3.RIGHT, 0)
	var ore := 0
	var tis := 0
	for n in ent.get_children():
		if n.get("item") == Items.ids.crimtane_ore:
			ore += n.count
		if n.get("item") == Items.ids.tissue_sample:
			tis += n.count
	check(ent.boss == null and ore >= 40 and tis >= 10 + 2 * 1, "morto: crimtano e amostras de tecido (%d, %d)" % [ore, tis])
	# orbe do Carmesim: coração quebrado 3 vezes chama o Brain
	p.world.orbs_broken = 0
	for i in 3:
		ent.orb_broken(Blocks.ids.crimson_heart)
	check(ent.boss != null and ent.boss.def.name == "brain_of_cthulhu", "o 3º Crimson Heart chama o Brain of Cthulhu")
	var has_crimtane := 0
	var has_demonite := 0
	for sd in 12:
		var gn := WorldGen.new(sd)
		var names: Array = gn.ores.map(func(o): return Blocks.ids.keys()[o.block])
		if gn.evil == "crimson":
			has_crimtane += 1 if "crimtane_ore" in names and not "demonite_ore" in names else 0
		else:
			has_demonite += 1 if "demonite_ore" in names and not "crimtane_ore" in names else 0
	check(has_crimtane > 0 and has_demonite > 0, "Carmesim só tem crimtano e Corrupção só tem demonita")
	free_player(p)
	w.free()
	return true


func test_forge():
	var mines := func(pick: String, block: String): return Items.pick_power[Items.ids[pick]] >= Blocks.power[Blocks.ids[block]]
	check(not mines.call("platinum_pickaxe", "hellstone") and mines.call("nightmare_pickaxe", "hellstone") and mines.call("deathbringer_pickaxe", "hellstone"), "Nightmare (65) e Deathbringer (70) minerem pedra infernal")
	check(not mines.call("silver_pickaxe", "obsidian") and mines.call("gold_pickaxe", "obsidian") and mines.call("molten_pickaxe", "hellstone") and Items.pick_power[Items.ids.molten_pickaxe] == 100, "obsidiana pede 55; a Molten tem 100")
	var by_result := {}
	for r in Crafting.recipes:
		by_result[Items.names[r.result]] = r
	check(by_result.nightmare_pickaxe.needs == {Items.ids.demonite_bar: 12, Items.ids.shadow_scale: 6} and by_result.deathbringer_pickaxe.needs == {Items.ids.crimtane_bar: 12, Items.ids.tissue_sample: 6}, "receitas dos dois picaretões (wiki)")
	check(by_result.molten_pickaxe.needs == {Items.ids.hellstone_bar: 20} and by_result.hellstone_bar.needs == {Items.ids.hellstone: 3, Items.ids.obsidian: 1}, "receitas da Molten e da barra infernal (wiki)")
	var w := floor_world()
	w.set_block(22, 11, 20, Blocks.ids.hellforge)
	var near := Crafting.stations_near(w, Vector3(20.5, 11, 20.5))
	check(near.has(Blocks.ids.hellforge) and near.has(Blocks.ids.furnace), "a forja infernal também vale como fornalha")
	var inv := Inventory.new()
	inv.add(Items.ids.hellstone, 3)
	inv.add(Items.ids.obsidian, 1)
	check(Crafting.craft(by_result.hellstone_bar, inv, near) and inv.total(Items.ids.hellstone_bar) == 1 and not Crafting.can_craft(by_result.hellstone_bar, inv, {}), "barra infernal só na forja")
	inv = Inventory.new()
	for n in ["molten_helmet", "molten_breastplate", "molten_greaves"]:
		inv.add(Items.ids[n], 1)
		inv.equip_from(inv.item.find(Items.ids[n]))
	check(inv.defense() == 8 + 9 + 8, "armadura Molten: 8+9+8 de defesa")
	# lava encostada em água vira obsidiana (cheia) ou pedra (rasa)
	w.set_block(20, 12, 20, Blocks.ids.lava, false)
	w.set_block(21, 12, 20, Blocks.ids.water, false)
	w.liquid.wake(20, 12, 20)
	w.liquid.settle(w)
	check(w.get_block(20, 12, 20) == Blocks.ids.obsidian, "lava cheia + água = obsidiana (%s)" % Blocks.ids.keys()[w.get_block(20, 12, 20)])
	w.set_block(24, 12, 20, Blocks.ids.lava_3, false)
	w.set_block(25, 12, 20, Blocks.ids.water, false)
	w.liquid.wake(24, 12, 20)
	w.liquid.settle(w)
	check(w.get_block(24, 12, 20) == Blocks.ids.stone, "lava rasa + água = pedra")
	w.free()
	return true


func test_king_meteor():
	var w := floor_world()
	var p := make_player(w)
	var ent: Node3D = p.entities
	p.inv.add(Items.ids.slime_crown, 2)
	p.slot = p.inv.item.find(Items.ids.slime_crown)
	p.clock.time = 300   # de dia: a coroa funciona a qualquer hora
	p.use_item()
	var king: Node3D = ent.boss
	check(king != null and king.def.name == "king_slime" and king.hp == 2000 and p.inv.total(Items.ids.slime_crown) == 1, "a Slime Crown invoca o King Slime de dia, com 2000 de vida")
	check(king.hurt(100, Vector3.RIGHT, 10) == 100 - 5 and king.velocity.length() < 1.0, "defesa 10 e imune a knockback")
	king.position = Vector3(24.5, 11, 24.5) + Vector3(6, 0, 0)
	var hops := 0
	var wasfloor := true
	for i in 60 * 12:
		king._physics_process(1.0 / 60)
		if wasfloor and not king.on_floor:
			hops += 1
		wasfloor = king.on_floor
	var minions: int = ent.enemies.filter(func(e): return e.def.name in ["blue_slime", "green_slime"]).size()
	check(hops >= 4 and minions >= 2, "pula atrás do jogador (%d pulos) e solta slimes (%d)" % [hops, minions])
	check(p.position.distance_to(king.position) < 25.0, "teleporta para perto se ficar longe")
	king.hurt(9999, Vector3.RIGHT, 0)
	var gold := 0
	var ninja := 0
	for n in ent.get_children():
		if n.get("item") == Items.ids.gold_coin:
			gold += n.count
		if n.get("item") in [Items.ids.ninja_hood, Items.ids.ninja_shirt, Items.ids.ninja_pants]:
			ninja += 1
	check(ent.boss == null and gold == 1 and ninja == 1, "morto: 1 ouro e uma (só uma) peça de Ninja")
	# meteorito: só depois do 1º chefe do mal, à meia-noite
	p.clock.time = p.clock.DAY_SECONDS + 100
	for i in 5:
		ent._physics_process(1.0 / 60)
	check(ent.meteor == null and not p.world.meteor_due, "sem chefe do mal derrotado, nada cai")
	ent.boss_down("eater_of_worlds")
	check(p.world.meteor_due and p.world.evil_boss_down, "derrotar o Eater/Brain libera o meteorito")
	ent._physics_process(1.0 / 60)
	check(ent.meteor == null, "antes da meia-noite ainda não cai")
	p.clock.time = p.clock.DAY_SECONDS + p.clock.NIGHT_SECONDS / 2.0 + 5.0
	ent._physics_process(1.0 / 60)
	check(ent.meteor != null and not p.world.meteor_due and p.message.contains("meteorito"), "à meia-noite a bola de fogo aparece e avisa a direção")
	var target := Vector3i(ent.meteor.position)
	for i in 60 * 6:
		ent._physics_process(1.0 / 60)
	var ore := 0
	for dz in range(-7, 8):
		for dx in range(-7, 8):
			for dy in range(-8, 3):
				if p.world.get_block(target.x + dx, p.world.surface_y(target.x, target.z, true) + dy, target.z + dz) == Blocks.ids.meteorite:
					ore += 1
	check(ent.meteor == null and ore > 30, "cratera com meteorito no fundo (%d blocos)" % ore)
	# pisar em meteorito queima
	p.position = Vector3(24.5, 11, 24.5)
	p.world.set_block(24, 10, 24, Blocks.ids.meteorite)
	p.on_floor = true
	p.hp = 100
	p.iframes = 0
	p.tick(0.016)
	check(p.hp < 100, "meteorito queima quem pisa")
	free_player(p)
	w.free()
	return true


func dungeon_world(seed_: int) -> Node3D:
	var w: Node3D = load("res://scripts/world.gd").new()
	w.gen = WorldGen.new(seed_)
	w.world_seed = seed_
	return w


func test_dungeon():
	for sd in [1, 2]:
		var w := dungeon_world(sd)
		var g: WorldGen = w.gen
		var x1 := g.dungeon_x + WorldGen.DUNGEON_W * WorldGen.DUNGEON_CELL
		var z1 := g.dungeon_z + WorldGen.DUNGEON_D * WorldGen.DUNGEON_CELL
		var top := WorldGen.DUNGEON_Y + WorldGen.DUNGEON_FLOORS * WorldGen.DUNGEON_CELL
		var opposite: bool = (g.dungeon_x < 128) == (g.evil_center.x > 128)
		check(opposite and g.dungeon_x >= 0 and x1 < WorldGen.SIZE_CHUNKS * C, "seed %d: o dungeon fica do lado oposto ao mal, dentro do mundo" % sd)
		# flood fill de ar a partir do poço de entrada: todas as salas têm de ser alcançáveis
		var e := g.dungeon_entrance
		var seen := {}
		var todo: Array[Vector3i] = [Vector3i(e.x, top, e.z)]
		seen[todo[0]] = true
		var air_total := 0
		for y in range(WorldGen.DUNGEON_Y + 1, top):
			for z in range(g.dungeon_z + 1, z1):
				for x in range(g.dungeon_x + 1, x1):
					if not Blocks.solid[w.get_block(x, y, z)]:
						air_total += 1
		var reached := 0
		while not todo.is_empty():
			var p: Vector3i = todo.pop_back()
			if p.y < top:
				reached += 1
			for dv in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
				var q: Vector3i = p + dv
				if seen.has(q) or q.x < g.dungeon_x or q.x > x1 or q.z < g.dungeon_z or q.z > z1 or q.y < WorldGen.DUNGEON_Y or q.y > top + 2:
					continue
				if not Blocks.solid[w.get_block(q.x, q.y, q.z)]:
					seen[q] = true
					todo.append(q)
		check(air_total > 5000 and reached >= air_total - 5, "seed %d: todas as salas do dungeon se ligam ao poço de entrada (%d/%d)" % [sd, reached, air_total])
		var open_sky := true
		for y in range(top, e.y + 6):
			open_sky = open_sky and not Blocks.solid[w.get_block(e.x, y, e.z)]
		check(open_sky and w.get_block(e.x, e.y - 1, e.z + 2) == g.BRICK or w.get_block(e.x, e.y + 4, e.z + 2) == g.BRICK, "seed %d: torre de entrada com poço aberto até o céu" % sd)
		var chests := 0
		for y in range(WorldGen.DUNGEON_Y + 1, top):
			for z in range(g.dungeon_z, z1 + 1, 1):
				for x in range(g.dungeon_x, x1 + 1, 1):
					chests += 1 if w.get_block(x, y, z) == g.CHEST else 0
		check(chests >= 6, "seed %d: baús nas salas (%d)" % [sd, chests])
		w.free()
	# tijolos protegidos até o Skeletron cair
	var w := floor_world()
	var p := make_player(w)
	w.set_block(20, 11, 20, Blocks.ids.dungeon_brick)
	p.target = {"pos": Vector3i(20, 11, 20), "normal": Vector3i(0, 1, 0)}
	p.inv.add(Items.ids.copper_pickaxe, 1)
	p.inv.add(Items.ids.nightmare_pickaxe, 1)
	p.slot = p.inv.item.find(Items.ids.copper_pickaxe)
	for i in 10:
		p.break_target()
	check(w.get_block(20, 11, 20) == Blocks.ids.dungeon_brick and p.message.contains("Skeletron"), "tijolo do dungeon resiste à picareta de cobre")
	p.slot = p.inv.item.find(Items.ids.nightmare_pickaxe)
	for i in 10:
		p.break_target()
	check(w.get_block(20, 11, 20) == 0, "…mas cede à Nightmare (65)")
	w.set_block(20, 11, 20, Blocks.ids.dungeon_brick)
	w.skeletron_down = true
	p.slot = p.inv.item.find(Items.ids.copper_pickaxe)
	for i in 20:
		p.break_target()
	check(w.get_block(20, 11, 20) == 0, "com o Skeletron derrotado qualquer picareta serve")
	free_player(p)
	w.free()
	# inimigos do dungeon nascem dentro dele
	var dw := dungeon_world(1)
	var dp := make_player(dw)
	var ent: Node3D = dp.entities
	var g: WorldGen = dw.gen
	dp.position = Vector3(g.dungeon_x + 15.5, WorldGen.DUNGEON_Y + 1, g.dungeon_z + 15.5)
	dp.clock.time = 300
	for i in 40:
		ent.try_spawn()
	var inside: int = ent.enemies.filter(func(e): return e.def.get("biome") == "dungeon" and g.in_dungeon(floori(e.position.x), floori(e.position.y), floori(e.position.z))).size()
	check(inside >= 3 and ent.enemies.all(func(e): return e.def.get("biome") == "dungeon"), "no dungeon só nascem inimigos do dungeon, dentro das salas (%d)" % inside)
	free_player(dp)
	dw.free()
	return true


func test_skeletron():
	var w := floor_world()
	var p := make_player(w)
	var ent: Node3D = p.entities
	var man: Node3D = ent.spawn_enemy(ent.def_named("old_man"), p.position + Vector3(2, 0, 0))
	check(man.hurt(500, Vector3.RIGHT, 0) == 0 and ent.enemies.has(man), "o Velho é imune")
	p.clock.time = 300
	ent.talk(man)
	check(ent.boss == null and p.message.contains("noite"), "de dia o Velho manda voltar à noite")
	p.clock.time = p.clock.DAY_SECONDS + 100
	ent.talk(man)
	var head: Node3D = ent.boss
	check(head != null and head.def.name == "skeletron" and not ent.enemies.has(man), "à noite o Velho vira o Skeletron")
	var hands: Array = ent.enemies.filter(func(e): return e.def.name == "skeletron_hand")
	check(hands.size() == 2 and ent.boss_max == 4400 + 2 * 600 and hands[0].follow == head, "duas mãos (600 de vida) seguem a cabeça; a barra soma tudo")
	check(head.hurt(100, Vector3.RIGHT, 5) == 100 - 5 and hands[0].hurt(100, Vector3.RIGHT, 0) == 100 - 7, "defesa 10 na cabeça e 14 nas mãos")
	var far := 0.0
	for i in 60 * 5:
		for e in ent.enemies:
			e._physics_process(1.0 / 60)
	for h in hands:
		far = maxf(far, h.position.distance_to(head.position))
	check(far < 14.0, "as mãos giram em volta da cabeça (%.1f)" % far)
	head.hp = 2000
	head.think(1.0 / 60)
	check(head.phase == 2 and head.damage == 60 and head.defense == 0 and head.hurt(50, Vector3.RIGHT, 0) == 50, "abaixo de 50%: gira, dano 60 e defesa 0")
	head.hurt(9999, Vector3.RIGHT, 0)
	var gold := 0
	for n in ent.get_children():
		if n.get("item") == Items.ids.gold_coin:
			gold += n.count
	check(ent.boss == null and ent.enemies.is_empty() and gold == 5 and w.skeletron_down, "cabeça morta: mãos somem, 5 de ouro e o dungeon abre")
	p.clock.time = p.clock.DAY_SECONDS + 100
	var head2: Node3D = ent.spawn_boss("skeletron")
	p.clock.time = 100   # amanheceu
	for i in 60 * 6:
		if not ent.enemies.has(head2):
			break
		head2._physics_process(1.0 / 60)
	check(ent.boss == null, "ao amanhecer o Skeletron foge")
	# o Velho só aparece à noite, perto da entrada, e não depois do Skeletron
	var dw := dungeon_world(1)
	var dp := make_player(dw)
	var e2: Node3D = dp.entities
	dp.position = Vector3(dw.gen.dungeon_entrance) + Vector3(0, 0, 20)
	dp.clock.time = dp.clock.DAY_SECONDS + 100
	e2._physics_process(1.0 / 60)
	check(e2.old_man != null and e2.old_man.position.distance_to(Vector3(dw.gen.dungeon_entrance)) < 6.0, "à noite o Velho espera na entrada do dungeon")
	dp.clock.time = 100
	e2._physics_process(1.0 / 60)
	check(e2.old_man == null, "ao amanhecer o Velho some")
	dw.skeletron_down = true
	dp.clock.time = dp.clock.DAY_SECONDS + 100
	e2._physics_process(1.0 / 60)
	check(e2.old_man == null, "com o Skeletron derrotado o Velho não volta")
	free_player(dp)
	dw.free()
	free_player(p)
	w.free()
	return true


func test_hardmode():
	var w := dungeon_world(1)
	var p := make_player(w)
	var ent: Node3D = p.entities
	p.inv.add(Items.ids.guide_voodoo_doll, 2)
	p.slot = p.inv.item.find(Items.ids.guide_voodoo_doll)
	p.position = Vector3(30.5, 60, 30.5)
	p.use_item()
	check(ent.boss == null and p.message.contains("submundo"), "a boneca só funciona no submundo")
	var g: WorldGen = w.gen
	p.position = Vector3(100.5, 6, 100.5)   # submundo, com lava por perto
	w.set_block(101, 5, 100, Blocks.ids.lava)
	p.message = ""
	p.use_item()
	var wall: Node3D = ent.boss
	check(wall != null and wall.def.name == "wall_of_flesh" and wall.position.y == 0.0 and wall.position.distance_to(p.position) > 40.0 and p.inv.total(Items.ids.guide_voodoo_doll) == 1, "boneca na lava chama o Wall of Flesh, longe e no chão do submundo")
	check(wall.hp == 8000 and ent.boss_max == 8000 and wall.hurt(100, Vector3.RIGHT, 9) == 100 - 6 and wall.velocity.length() < 10.0, "8000 de vida, defesa 12, imune a knockback")
	var start := wall.position.distance_to(p.position)
	for i in 60 * 6:
		wall._physics_process(1.0 / 60)
	var lasers: int = ent.get_children().filter(func(n): return n.get("def") is Dictionary and n.def.get("name") == "eye_laser").size()
	var hungry: int = ent.enemies.filter(func(e): return e.def.name == "the_hungry").size()
	check(wall.position.distance_to(p.position) < start - 8.0 and lasers >= 2 and hungry >= 1 and hungry <= 6, "avança, atira lasers (%d) e solta The Hungry (%d)" % [lasers, hungry])
	var slow: float = wall.velocity.length()
	wall.hp = 800
	wall.think(1.0 / 60)
	check(wall.velocity.length() > slow + 1.0, "quanto menos vida, mais rápido")
	# laser fere o jogador
	var laser: Node3D = ent.spawn_projectile("eye_laser", p.position + Vector3(0, 1, 0) + Vector3(-3, 0, 0), Vector3.RIGHT, 16.0, 25, 0.0)
	p.hp = 100
	p.iframes = 0
	for i in 60:
		laser._physics_process(1.0 / 60)
	check(p.hp < 100, "o laser do chefe fere o jogador")
	# hardmode: converte o que já existe
	var before: Array[Vector2i] = []
	var hc := Vector2i(floori(g.hallow_center.x / C), floori(g.hallow_center.y / C))
	for dz in range(-2, 3):
		for dx in range(-2, 3):
			w.get_block((hc.x + dx) * C, 30, (hc.y + dz) * C)   # gera os chunks em volta do Hallow
	var ores_before := 0
	for k in w.chunks:
		for id in [Blocks.ids.cobalt_ore, Blocks.ids.palladium_ore, Blocks.ids.pearlstone, Blocks.ids.hallowed_grass]:
			ores_before += w.chunks[k].count(id)
	var normal_chunk: PackedByteArray = w.chunks[hc].duplicate()
	check(ores_before == 0 and not w.hardmode, "antes do hardmode não há minério novo nem Hallow")
	wall.hurt(99999, Vector3.RIGHT, 0)
	var gold := 0
	for n in ent.get_children():
		if n.get("item") == Items.ids.gold_coin:
			gold += n.count
	check(w.hardmode and g.hardmode and ent.boss == null and gold == 8, "Wall of Flesh morto: hardmode ligado e 8 de ouro")
	var cobalt := 0
	var pearl := 0
	var grass := 0
	for k in w.chunks:
		cobalt += w.chunks[k].count(Blocks.ids.cobalt_ore) + w.chunks[k].count(Blocks.ids.palladium_ore)
		pearl += w.chunks[k].count(Blocks.ids.pearlstone)
		grass += w.chunks[k].count(Blocks.ids.hallowed_grass)
	check(cobalt > 20 and pearl > 300 and grass > 100, "chunks já gerados foram convertidos (minério %d, pearlstone %d, grama %d)" % [cobalt, pearl, grass])
	var fresh := WorldGen.new(1)
	fresh.hardmode = true
	check(fresh.generate(hc.x, hc.y) == w.chunks[hc] and normal_chunk != w.chunks[hc], "converter = gerar já no hardmode (mesmo resultado)")
	var pair := 0
	for sd in 10:
		var gn := WorldGen.new(sd)
		pair += 1 if gn.hm_ores.size() == 1 and gn.ores.all(func(o): return not (o.block in [Blocks.ids.cobalt_ore, Blocks.ids.palladium_ore])) else 0
	check(pair == 10, "cada mundo tem só um dos minérios do hardmode")
	check(Items.pick_power[Items.ids.molten_pickaxe] >= Blocks.power[Blocks.ids.cobalt_ore] and Items.pick_power[Items.ids.cobalt_pickaxe] == 110 \
		and Items.pick_power[Items.ids.palladium_pickaxe] == 130 and Items.pick_power[Items.ids.nightmare_pickaxe] < Blocks.power[Blocks.ids.cobalt_ore], "cobalto pede a Molten (100); Cobalt 110 e Palladium 130")
	# inimigos do hardmode só nascem no Hallow e só depois dele
	p.position = Vector3(g.hallow_center.x, 90, g.hallow_center.y)
	p.clock.time = 300
	for e in ent.enemies.duplicate():
		ent.remove_enemy(e)
	ent.rng.seed = 5   # sorteio fixo: sem semente, ~6% das vezes só nasciam slimes
	for i in 60:
		ent.try_spawn()
	check(ent.biome_at(p.position) == "hallow" and ent.enemies.any(func(e): return e.def.get("biome") == "hallow") and ent.enemies.all(func(e): return e.def.get("biome") == "hallow" or not e.def.has("biome")), "no Hallow nascem pixies/unicórnios")
	w.hardmode = false
	for e in ent.enemies.duplicate():
		ent.remove_enemy(e)
	for i in 60:
		ent.try_spawn()
	check(ent.enemies.all(func(e): return not e.def.get("hardmode", false)), "antes do hardmode nada dele nasce")
	p.position = Vector3(100.5, 12, 100.5)
	for e in ent.enemies.duplicate():
		ent.remove_enemy(e)
	for i in 60:
		ent.try_spawn()
	check(ent.biome_at(p.position) == "underworld" and ent.enemies.any(func(e): return e.def.name in ["voodoo_demon", "hellbat"]) and ent.enemies.all(func(e): return e.def.get("biome") == "underworld"), "no submundo nascem demônios voodoo e hellbats")
	free_player(p)
	w.free()
	return true


func test_tools():
	var w := floor_world()
	var p := make_player(w)
	w.set_block(20, 11, 20, Blocks.ids.wood)
	p.target = {"pos": Vector3i(20, 11, 20), "normal": Vector3i(0, 1, 0)}
	p.inv.add(Items.ids.copper_pickaxe, 1)
	p.inv.add(Items.ids.copper_axe, 1)
	p.slot = p.inv.item.find(Items.ids.copper_pickaxe)
	for i in 10:
		p.break_target()
	check(w.get_block(20, 11, 20) == Blocks.ids.wood and p.message.contains("machado"), "tronco não quebra com picareta")
	p.slot = p.inv.item.find(Items.ids.copper_axe)
	p.break_target()
	check(w.get_block(20, 11, 20) == Blocks.ids.wood, "o machado precisa de mais de um golpe (35% x 1,5)")
	p.break_target()
	check(w.get_block(20, 11, 20) == 0, "…e corta o tronco em 2")
	w.set_block(20, 11, 20, Blocks.ids.dirt)
	p.target = {"pos": Vector3i(20, 11, 20), "normal": Vector3i(0, 1, 0)}
	p.break_target()
	check(w.get_block(20, 11, 20) == Blocks.ids.dirt and p.message.contains("picareta"), "machado não escava terra")
	var by := {}
	for r in Crafting.recipes:
		by[Items.names[r.result]] = r
	check(by.copper_axe.needs == {Items.ids.copper_bar: 6, Items.ids.wood: 3} and by.platinum_axe.needs == {Items.ids.platinum_bar: 8, Items.ids.wood: 3} \
		and Items.axe_power[Items.ids.platinum_axe] == 60 and Items.axe_power[Items.ids.tin_axe] == 40 and by.empty_bucket.needs == {Items.ids.iron_bar: 2}, "receitas e poderes dos machados (wiki)")
	# balde: pega um bloco de água e derrama em outro lugar, onde ela flui
	w.set_block(24, 11, 20, Blocks.ids.water)
	p.inv.add(Items.ids.empty_bucket, 1)
	p.slot = p.inv.item.find(Items.ids.empty_bucket)
	p.position = Vector3(22.5, 11, 20.5)
	p.rotation.y = -PI / 2   # olha para +X
	p.pitch = -0.3
	p.use_bucket(Items.defs[Items.ids.empty_bucket])
	check(w.get_block(24, 11, 20) == 0 and p.held() == Items.ids.water_bucket, "balde vazio pega a água da mira")
	p.target = {"pos": Vector3i(24, 10, 20), "normal": Vector3i(0, 1, 0)}
	p.use_bucket(Items.defs[Items.ids.water_bucket])
	check(w.get_block(24, 11, 20) == Blocks.ids.water and p.held() == Items.ids.empty_bucket, "balde cheio derrama água e volta vazio")
	w.liquid.settle(w)
	var wet := 0
	for x in range(20, 29):
		for z in range(16, 25):
			wet += 1 if Blocks.liquid[w.get_block(x, 11, z)] else 0
	check(wet >= 4, "a água derramada se espalha (%d blocos)" % wet)
	p.inv.item[p.slot] = Items.ids.lava_bucket
	p.target = {"pos": Vector3i(20, 10, 16), "normal": Vector3i(0, 1, 0)}
	p.use_bucket(Items.defs[Items.ids.lava_bucket])
	check(w.get_block(20, 11, 16) == Blocks.ids.lava and p.held() == Items.ids.empty_bucket, "balde de lava derrama lava")
	free_player(p)
	w.free()
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


# Soma dos níveis (unidades de 1/8 de bloco) do líquido `kind` numa caixa.
func volume(w: Node3D, lo: Vector3i, hi: Vector3i, kind := -1) -> int:
	var total := 0
	for y in range(lo.y, hi.y + 1):
		for z in range(lo.z, hi.z + 1):
			for x in range(lo.x, hi.x + 1):
				var b: int = w.get_block(x, y, z)
				if Blocks.liquid[b] and (kind == -1 or Blocks.liquid_kind[b] == kind):
					total += Blocks.liquid_level[b]
	return total


func test_flow():
	var water: int = Blocks.ids.water
	var ids: PackedInt32Array = Blocks.level_ids[water]
	check(ids[0] == 0 and ids[8] == water and ids[3] == Blocks.ids.water_3 and Blocks.liquid_kind[Blocks.ids.water_5] == water and Blocks.liquid_level[Blocks.ids.lava_2] == 2, "níveis de líquido: 8 = cheio, ids por nível")
	var lo := Vector3i(0, 11, 0)
	var hi := Vector3i(47, 40, 47)
	# Um bloco cheio no chão se espalha em poça, sem perder volume e com níveis vizinhos a no máximo 1 de diferença.
	var w := floor_world()
	w.set_block(24, 11, 24, water)
	w.liquid.settle(w)
	check(volume(w, lo, hi) == 8 and volume(w, Vector3i(0, 12, 0), hi) == 0, "poça: o volume se conserva (8) e fica no chão")
	var wet := 0
	var flat := true
	for z in range(18, 31):
		for x in range(18, 31):
			var l: int = Blocks.liquid_level[w.get_block(x, 11, z)]
			wet += int(l > 0)
			for o in [Vector2i(1, 0), Vector2i(0, 1)]:
				flat = flat and absi(l - Blocks.liquid_level[w.get_block(x + o.x, 11, z + o.y)]) <= 1
	check(wet >= 5 and flat, "poça: espalha em volta (%d blocos) até os níveis diferirem de no máximo 1" % wet)
	check(w.liquid.is_idle(), "poça: assenta e para de gastar CPU")
	w.free()
	# Cai de longe até o chão.
	w = floor_world()
	w.set_block(24, 30, 24, water)
	w.liquid.settle(w)
	check(volume(w, Vector3i(0, 12, 0), hi) == 0 and volume(w, lo, hi) == 8, "queda: a água desce até o chão sem perder volume")
	w.free()
	# Lago com margem de 1 bloco: a margem quebra e uma cova ao lado enche (o lago baixa).
	w = floor_world()
	for x in range(19, 26):
		for z in range(19, 26):
			w.set_block(x, 11, z, water if x in range(20, 25) and z in range(20, 25) else Blocks.ids.stone)
	w.liquid.settle(w)
	check(volume(w, lo, hi) == 25 * 8, "lago cercado fica parado (%d)" % volume(w, lo, hi))
	for y in [10, 9, 8]:
		w.set_block(25, y, 22, 0)   # cova ao lado da margem
	w.set_block(25, 11, 22, 0)      # a margem se abre
	w.liquid.settle(w)
	check(volume(w, Vector3i(0, 0, 0), hi) == 25 * 8, "lago que vaza conserva o volume")
	check(Blocks.liquid[w.get_block(25, 8, 22)] == 1 and Blocks.liquid_level[w.get_block(25, 8, 22)] == 8, "a cova enche pelo fundo")
	check(volume(w, Vector3i(20, 11, 20), Vector3i(24, 11, 24)) < 25 * 8, "o lago baixa")
	# Desempenho: um lago grande que vaza não passa de poucos ms por quadro.
	w.free()
	w = floor_world()
	for x in range(14, 34):
		for z in range(14, 34):
			for y in range(11, 14):
				w.set_block(x, y, z, water if x in range(15, 33) and z in range(15, 33) else Blocks.ids.stone)
	w.liquid.settle(w)
	w.set_block(33, 11, 24, 0)
	w.set_block(33, 12, 24, 0)
	var before := volume(w, Vector3i(0, 11, 0), Vector3i(47, 20, 47))
	var t := Time.get_ticks_usec()
	var gens: int = w.liquid.settle(w, 300)
	var ms := (Time.get_ticks_usec() - t) / 1000.0
	check(volume(w, Vector3i(0, 11, 0), Vector3i(47, 20, 47)) == before, "lago grande que vaza conserva o volume")
	print("fluxo: lago 18x18x3 vazando: %d gerações, %.0f ms (%.1f ms por geração)" % [gens, ms, ms / maxi(gens, 1)])
	w.free()
	# Lava também flui, mais devagar (uma geração em cada LAVA_EVERY).
	w = floor_world()
	w.set_block(24, 11, 24, Blocks.ids.lava)
	w.liquid.settle(w)
	check(volume(w, lo, hi, Blocks.ids.lava) == 8 and volume(w, lo, hi, water) == 0 and Blocks.liquid_level[w.get_block(25, 11, 24)] > 0, "lava também se espalha")
	w.free()
	return true


# Piscina: chão de pedra até y = 10; água em y = 11..10+deep numa área de 5x5 e margem de pedra da mesma altura (x >= 25).
func pool_world(deep: int) -> Node3D:
	var w := floor_world()
	for y in range(11, 11 + deep):
		for z in range(18, 30):
			for x in range(20, 30):
				w.set_block(x, y, z, Blocks.ids.water if x < 25 else Blocks.ids.stone)
	return w


func test_swim_out():
	# 1 bloco de água: vadeia e pula para fora da margem (o bug do playtest).
	var w := pool_world(1)
	var p := make_player(w)
	p.position = Vector3(23.5, 11, 22.5)
	p.step(1.0 / 60, Vector3.ZERO, false)
	check(not p.swimming and p.depth > 0.5 and p.depth < 1.0, "água de 1 bloco: vadeia, não nada (%.2f)" % p.depth)
	var out := Vector3.ZERO
	for i in 120:
		p.step(1.0 / 60, Vector3.RIGHT, true)
		if out == Vector3.ZERO and p.position.x > 25.4 and p.on_floor:
			out = p.position
	check(out != Vector3.ZERO and absf(out.y - 12) < 0.05, "sai de uma poça de 1 bloco pulando para a margem (%s)" % out)
	free_player(p)
	w.free()
	# Fundo: nada até a superfície e sai pela margem com Espaço (pulo inteiro junto da parede).
	for deep in [2, 3, 5]:
		w = pool_world(deep)
		p = make_player(w)
		p.position = Vector3(22.5, 11, 22.5)
		var out2 := Vector3.ZERO
		var left := -1.0
		for i in 60 * 8:
			p.step(1.0 / 60, Vector3.RIGHT, true)
			if left < 0 and p.position.x > 25.4 and p.on_floor:
				left = i / 60.0
				out2 = p.position
		check(left > 0 and absf(out2.y - (11 + deep)) < 0.05, "água de %d blocos: nada e sai para a margem (em %.1f s, pos %s)" % [deep, left, out2])
		free_player(p)
		w.free()
	# Sem Espaço afunda; no meio da piscina de 5 blocos não há como andar no fundo sem nadar.
	w = pool_world(5)
	p = make_player(w)
	p.position = Vector3(22.5, 13, 22.5)
	for i in 240:
		p.step(1.0 / 60, Vector3.ZERO, false)
	check(p.swimming and absf(p.position.y - 11) < 0.05, "sem Espaço afunda até o fundo")
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
	# Níveis: um bloco pela metade tem a superfície na metade da altura; ao lado de um cheio só aparece o degrau.
	var lv := chunk(0)
	for i in C * C * (Y + 1):
		lv[i] = Blocks.ids.stone
	lv[8 + 8 * C + (Y + 1) * C * C] = Blocks.ids.water_4
	var lwater: Array = []
	ChunkMesher.build(lv, [lv, lv, lv, lv], n, lwater)
	var ly := 0.0
	for v in lwater[Mesh.ARRAY_VERTEX]:
		ly = maxf(ly, v.y)
	check(is_equal_approx(ly, Y + 1 + ChunkMesher.LIQUID_TOP / 2.0), "água nível 4: superfície na metade da altura (%.2f)" % ly)
	lv[9 + 8 * C + (Y + 1) * C * C] = Blocks.ids.water
	lwater = []
	ChunkMesher.build(lv, [lv, lv, lv, lv], n, lwater)
	var lo_y := 99999.0
	var strip := 0
	var lvs: PackedVector3Array = lwater[Mesh.ARRAY_VERTEX]
	var lns: PackedVector3Array = lwater[Mesh.ARRAY_NORMAL]
	for i in lvs.size():
		if lns[i] == Vector3.LEFT and is_equal_approx(lvs[i].x, 9.0) and lvs[i].y > Y + 1:   # a face -X do bloco cheio (x = 9)
			lo_y = minf(lo_y, lvs[i].y)
			strip += 1
	check(strip == 4 and is_equal_approx(lo_y, Y + 1 + ChunkMesher.LIQUID_TOP / 2.0), "água: entre níveis diferentes só o degrau acima da superfície vizinha (%.2f)" % lo_y)
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
	p.break_target()
	check(w.get_block(20, 10, 20) == Blocks.ids.gold_ore and is_equal_approx(p.mine_damage, 80.0), "ferro (40) racha o ouro: 2 golpes = 80 de 100")
	p.break_target()
	var drops: Array = p.entities.get_children().filter(func(n): return n.get("item") == Items.ids.gold_ore)
	check(w.get_block(20, 10, 20) == 0 and drops.size() == 1, "o 3º golpe quebra o ouro e o drop cai no chão")
	p.inv.add(Items.ids.gold_ore, 1)
	p.slot = 2
	p.target = {"pos": Vector3i(20, 10, 21), "normal": Vector3i(0, 1, 0)}
	p.position = Vector3(25.5, 11, 25.5)
	p.place_block()
	check(w.get_block(20, 11, 21) == Blocks.ids.gold_ore and p.inv.total(Items.ids.gold_ore) == 0, "colocar usa o item da mão")
	Blocks.power[Blocks.ids.gold_ore] = saved_power
	# Golpes até quebrar, como a tabela da wiki (poder da picareta × dureza; 100 quebra): terra 2 com cobre, pedra 3, grama 3.
	var hits := func(pick: String, block: String) -> int:
		p.inv = Inventory.new()
		p.inv.add(Items.ids[pick], 1)
		p.slot = 0
		p.mine_damage = 0.0
		p.mine_pos = Vector3i(-1, -1, -1)
		w.set_block(22, 10, 22, Blocks.ids[block])
		p.target = {"pos": Vector3i(22, 10, 22), "normal": Vector3i(0, 1, 0)}
		var n := 0
		while w.get_block(22, 10, 22) != 0 and n < 20:
			p.break_target()
			n += 1
		return n
	check(hits.call("copper_pickaxe", "dirt") == 2 and hits.call("copper_pickaxe", "stone") == 3 and hits.call("copper_pickaxe", "grass") == 3, "cobre: terra 2 golpes, pedra 3, grama 3 (a grama absorve o primeiro)")
	check(hits.call("iron_pickaxe", "stone") == 3 and hits.call("gold_pickaxe", "stone") == 2 and hits.call("gold_pickaxe", "dirt") == 1, "ferro: pedra 3; ouro: pedra 2, terra 1")
	check(hits.call("copper_pickaxe", "torch") == 1 and hits.call("copper_pickaxe", "leaves") == 1, "tocha e folha quebram num golpe")
	check(hits.call("gold_pickaxe", "demonite_ore") == 2, "demonita com picareta de ouro (55): 2 golpes")
	# Rachaduras: trocar de bloco recomeça; parar de golpear as apaga.
	p.inv = Inventory.new()
	p.inv.add(Items.ids.copper_pickaxe, 1)
	p.slot = 0
	w.set_block(22, 10, 22, Blocks.ids.stone)
	w.set_block(23, 10, 22, Blocks.ids.stone)
	p.target = {"pos": Vector3i(22, 10, 22), "normal": Vector3i(0, 1, 0)}
	p.break_target()
	p.break_target()
	p.target = {"pos": Vector3i(23, 10, 22), "normal": Vector3i(0, 1, 0)}
	p.break_target()
	check(is_equal_approx(p.mine_damage, 35.0) and p.mine_pos == Vector3i(23, 10, 22), "trocar de bloco recomeça o dano")
	p.tick(p.MINE_DECAY + 0.1)
	check(p.mine_damage == 0.0, "sem golpear, as rachaduras somem")
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
			for i in 4:
				player.break_target()
			check(world.get_block(below.x, below.y, below.z) == 0, "quebrar tira o bloco com a picareta inicial (grama: 3 golpes)")
			var lmb := InputEventMouseButton.new()   # botão esquerdo de verdade: evento → _process → golpe no bloco da mira, no ritmo do tool speed
			lmb.button_index = MOUSE_BUTTON_LEFT
			lmb.pressed = true
			player._unhandled_input(lmb)
			player._process(1.0 / 60)
			check(player.attack_held and is_equal_approx(player.cooldown, 15.0 / 60.0) and player.swing_timer > 0.0, "clicar com a picareta de cobre começa um golpe de 15 quadros")
			player.tick(0.1)
			check(player.mine_damage > 0.0 and player.swing_item.is_empty(), "o golpe chega ao bloco da mira no impacto")
			lmb.pressed = false
			player._unhandled_input(lmb)
			check(not player.attack_held, "soltar o botão para de repetir")
			player.cooldown = 0.0
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
			check(hud.hearts.filter(func(h): return h.visible).size() == 5 and hud.slots.size() == Inventory.SIZE and hud.slots[Inventory.HOTBAR].visible and hud.craft_root.visible and hud.equip_root.visible, "HUD: corações, hotbar + 4 fileiras, criação e equipamento ao abrir")
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
			check(hand.glow != null and hand.sparks != null and hand.trail.pts.size() >= 2, "Terra Blade na mão com brilho, faíscas e rastro (%s %s %d)" % [hand.glow, hand.sparks, hand.trail.pts.size()])
			check(hand.arm != null and hand.arm.get_child_count() == 3, "braço em 1ª pessoa (antebraço, manga e punho)")
			player.cooldown = 0
			player.third_person = true
			player.creative = true
			player.position += Vector3.UP * 20  # céu aberto: nada entre a cabeça e a câmera
			player._process(0)
			var model: Node3D = player.get_node("Model")
			check(player.cam.position.distance_to(Vector3(0, player.EYE, 0)) > 3.5 and model.visible and not hand.visible, "V: 3ª pessoa afasta a câmera e mostra o corpo")
			player.third_person = false
			player._process(0)
			check(player.cam.position == Vector3(0, player.EYE, 0) and not model.visible, "V de novo: volta à 1ª pessoa")
			var hud: CanvasLayer = main.get_node("HUD")
			var cp := Vector3i(player.position.floor()) + Vector3i(3, 0, 0)
			world.set_block(cp.x, cp.y, cp.z, Blocks.ids.chest)
			player.set_inventory(false)
			player.target = {"pos": cp, "normal": Vector3i(-1, 0, 0)}
			player.interact()
			hud._process(0.1)
			check(player.inventory_open and not hud.chest.is_empty(), "botão direito no baú abre o inventário com o painel do baú")
			player._unhandled_input(key(KEY_ESCAPE))
			hud._process(0.1)
			check(not player.inventory_open and hud.chest.is_empty(), "Esc fecha o inventário e o baú")
			world.set_block(cp.x, cp.y, cp.z, 0)
			world.chests.erase(cp)
			# Configurações: o botão do inventário pausa de verdade; os controles aplicam na hora e o Esc fecha
			player.set_inventory(true)
			hud._process(0.1)
			hud.equip_root.get_children().filter(func(n): return n is Button)[0].pressed.emit()
			hud._process(0.1)
			check(main.get_tree().paused and player.menu_open and not player.inventory_open and hud.pause.visible, "botão Configurações: pausa de verdade (a árvore para) e fecha o inventário")
			var sliders: Array = hud.pause.find_children("*", "HSlider", true, false)
			check(sliders.size() == 3 and sliders[0].value == world.render_distance, "Configurações: distância, volume e sensibilidade, já no valor atual")
			sliders[0].value = 5
			sliders[1].value = 50
			sliders[2].value = 200
			check(world.render_distance == 5 and Settings.render_distance == 5 and is_equal_approx(Settings.volume, 0.5) and is_equal_approx(Settings.mouse_sens, 2.0), "mexer nos controles aplica na hora")
			sliders[0].value = 6
			Settings.volume = 1.0
			Settings.mouse_sens = 1.0
			var esc := InputEventAction.new()
			esc.action = "ui_cancel"
			esc.pressed = true
			hud._unhandled_input(esc)
			hud._process(0.0)
			check(not main.get_tree().paused and not player.menu_open, "Esc dentro do Configurações: o HUD despausa")
			player.add_buff("ironskin", 125.0)
			hud._process(0.0)
			check(hud.buff_row.get_child_count() == 1 and hud.buff_row.get_child(0).get_node("Time").text == "2:05" and hud.defense_label.text == "Defesa: 8", "buff na HUD: ícone com o tempo (2:05) e a defesa sobe")
			player.buffs.clear()
			player.max_hp = 240
			player.hp = 240.0
			hud._process(0.0)
			check(hud.hearts_shown == 12 and hud.heart_rows[1].visible and hud.minimap.corner_y == 104.0 and hud.life_label.text == "Vida: 240/240", "vida máxima 240: 12 corações em duas fileiras e o minimapa desce")
			player.max_hp = 100
			player.hp = 100.0
			hud._process(0.0)
			check(hud.hearts_shown == 5 and not hud.heart_rows[1].visible and hud.minimap.corner_y == 74.0, "volta a 5 corações")
			player.set_inventory(true)
			hud.open_npc("merchant")
			player.inv.coin = PackedInt32Array([0, 30, 0, 0])
			hud._process(0.0)
			var picks: int = player.inv.total(Items.ids.copper_pickaxe)
			hud.npc_buttons.get_child(0).pressed.emit()
			check(hud.npc_panel.visible and player.inv.total(Items.ids.copper_pickaxe) == picks + 1 and player.inv.coin_value() == 2500, "loja: clicar compra a Copper Pickaxe por 5 de prata")
			hud.open_npc("nurse")
			player.hp = 40.0
			hud.open_npc("nurse")
			hud.npc_buttons.get_child(0).pressed.emit()
			check(player.hp == player.max_hp and player.inv.coin_value() == 2500 - 60, "Nurse: cura o que falta por 60 de cobre (hp %s/%s, moedas %d)" % [player.hp, player.max_hp, player.inv.coin_value()])
			player.set_inventory(false)
			hud._process(0.0)
			check(not hud.npc_panel.visible, "fechar o inventário fecha a conversa")
			player.creative = true
			hud._process(0.0)
			check(hud.creative_label.visible and not hud.flight_bar.visible, "modo criativo: aviso fixo na tela")
			player.creative = false
			player.inv.acc[0] = Items.ids.fledgling_wings
			player.flight_left = 0.2
			hud._process(0.0)
			check(hud.flight_bar.visible and is_equal_approx(hud.flight_bar.value, 0.2) and not hud.creative_label.visible, "asas: a barra de voo aparece gastando o tempo")
			player.inv.acc[0] = -1
			player.flight_left = 0.0
			hud._unhandled_input(key(KEY_F10))
			check(not hud.debug_label.visible, "F10 esconde o FPS")
			hud._unhandled_input(key(KEY_F10))
			hud._unhandled_input(key(KEY_F11))
			check(not hud.root.visible, "F11 esconde o HUD")
			hud._unhandled_input(key(KEY_F11))
			check(hud.root.visible and hud.debug_label.visible, "F10 e F11 de novo mostram tudo")
			phase = 3
		3:   # câmera em 3ª pessoa: nunca dentro de bloco, em qualquer ângulo (ver abaixo da terra era a câmera atravessando o chão)
			player.creative = false
			player.third_person = true
			var rng := RandomNumberGenerator.new()
			rng.seed = 7
			var bad := 0
			var samples := 1500
			for i in samples:
				var x := 128 + rng.randi_range(-60, 60)
				var z := 128 + rng.randi_range(-60, 60)
				player.position = Vector3(x + 0.5, world.surface_y(x, z), z + 0.5)
				player.rotation.y = rng.randf() * TAU
				player.pitch = rng.randf_range(-1.5, 1.5)
				player.cam.rotation.x = player.pitch
				player._update_camera(0.0)
				bad += int(not player.lens_clear(player.cam.global_position))
			check(bad == 0, "3ª pessoa: a câmera nunca fica dentro de bloco (%d de %d ângulos)" % [bad, samples])
			# Colado numa parede do lado do ombro: a câmera não pode entrar nela.
			var px := 128
			var pz := 128
			var gy: int = world.surface_y(px, pz)
			for dy in range(0, 4):
				for dz in range(-8, 9):
					world.set_block(px + 1, gy + dy, pz + dz, Blocks.ids.stone)
			player.position = Vector3(px + 0.5, gy, pz + 0.5)
			player.rotation.y = 0.0
			player.pitch = -0.2
			player.cam.rotation.x = -0.2
			player._update_camera(0.0)
			check(player.lens_clear(player.cam.global_position), "3ª pessoa: junto de uma parede do lado do ombro a câmera para antes dela")
			# modelos (mão, corpo, inimigos): o sol e o ambiente escurecem sob a terra e voltam na superfície
			var dn: Node = main.get_node("DayNight")
			var sun: DirectionalLight3D = main.get_node("Sun")
			var env: Environment = world.get_world_3d().environment
			player.third_person = false
			player.position = Vector3(px + 0.5, gy + 2, pz + 0.5)
			player._update_camera(0.0)
			dn.time = 300.0
			dn.depth_timer = 0.0
			dn._process(0.0)
			var sun_up: float = sun.light_energy
			var amb_up: float = env.ambient_light_energy
			player.position.y = 40.0
			player._update_camera(0.0)
			dn.depth_timer = 0.0
			dn._process(0.0)
			check(sun.light_energy < sun_up * 0.5 and env.ambient_light_energy < amb_up * 0.5, "caverna: sol e ambiente dos modelos caem a ~1/3 (%.2f → %.2f)" % [sun_up, sun.light_energy])
			player.position.y = gy + 2
			player._update_camera(0.0)
			dn.depth_timer = 0.0
			dn._process(0.0)
			check(is_equal_approx(sun.light_energy, sun_up), "…e voltam ao cheio na superfície")
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
