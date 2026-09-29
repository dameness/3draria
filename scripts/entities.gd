extends Node3D
# Inimigos, itens soltos e flechas vivem aqui. Também faz nascer inimigos de enemies.json
# conforme o horário ("day"/"night"/"any") em volta do jogador, na superfície.

const MAX_DAY := 4
const MAX_NIGHT := 8
const SPAWN_MIN := 24.0
const SPAWN_MAX := 40.0
const DESPAWN := 64.0
const Enemy := preload("res://scripts/enemy.gd")
const ItemDrop := preload("res://scripts/item_drop.gd")
const Projectile := preload("res://scripts/projectile.gd")

@export var world: Node3D
@export var player: Node3D
@export var clock: Node
var defs: Array = []
var projectiles := {}   # nome -> entrada de projectiles.json
var enemies: Array[Node3D] = []
var boss: Node3D = null
var meteor: Node3D = null    # bola de fogo em queda
var old_man: Node3D = null   # guarda do dungeon: à noite, até o Skeletron cair, espera na entrada
var boss_max := 0           # vida total do chefe ao nascer (a de todos os segmentos, se for verme)
var rng := RandomNumberGenerator.new()
var spawn_timer := 3.0


func _ready() -> void:
	load_defs()


func load_defs(dir := "res://data/base") -> void:
	defs = Blocks.read(dir + "/enemies.json")
	for d in defs:
		for dr in d.drops:
			assert(Items.ids.has(dr.item), "drop desconhecido: " + dr.item)
	projectiles.clear()
	for p in Blocks.read(dir + "/projectiles.json"):
		projectiles[p.name] = p
	for it in Items.defs:
		for k in ["shoot", "projectile"]:
			assert(not it.has(k) or projectiles.has(it[k]), "projétil desconhecido: " + str(it.get(k)))


func icon(item: int) -> Texture2D:
	return Items.icon_texture(item, world.atlas_texture)


func _physics_process(delta: float) -> void:
	if world.meteor_due and meteor == null and clock.is_night() and clock.time >= clock.DAY_SECONDS + clock.NIGHT_SECONDS / 2.0:
		start_meteor()   # depois do 1º chefe do mal, um meteorito cai na 1ª meia-noite (ou já, se ele caiu depois dela)
	_old_man()
	if meteor:
		meteor.position.y -= 40.0 * delta
		Fx.sparks(self, meteor.position, Color("#ffb050"), 3, Vector3.UP)
		if meteor.position.y <= meteor.get_meta("ground"):
			var at: Vector3 = meteor.position
			meteor.queue_free()
			meteor = null
			crater(int(at.x), int(at.z))
	spawn_timer -= delta
	if spawn_timer <= 0:
		spawn_timer = 1.0
		try_spawn()
	for e in enemies.duplicate():
		if not e.def.get("boss") and e.position.distance_to(player.position) > DESPAWN:
			remove_enemy(e)


# Bioma sob os pés de pos: dungeon, underworld (submundo), o mal do mundo (corruption/crimson), hallow (só no hardmode) ou "".
func biome_at(pos: Vector3) -> String:
	var x := floori(pos.x)
	var z := floori(pos.z)
	if world.gen.in_dungeon(x, floori(pos.y), z):
		return "dungeon"
	if pos.y < WorldGen.UNDERWORLD_TOP:
		return "underworld"
	if world.gen.evil_weight(x, z) >= 0.5:
		return world.gen.evil
	return "hallow" if world.hardmode and world.gen.hallow_weight(x, z) >= 0.5 else ""


func try_spawn() -> void:
	var night: bool = clock.is_night()
	if enemies.size() >= (MAX_NIGHT if night else MAX_DAY) or rng.randf() > 0.5:
		return
	var when := "night" if night else "day"
	var biome := biome_at(player.position)
	var options := defs.filter(func(d): return (d.spawn == when or d.spawn == "any") and (d.biome == biome if d.has("biome") else not biome in ["dungeon", "underworld"]) \
			and (world.hardmode or not d.get("hardmode", false)))
	if options.is_empty():
		return
	var d: Dictionary = options[rng.randi() % options.size()]
	if biome in ["dungeon", "underworld"]:   # sem superfície: numa sala/caverna perto do jogador (voadores em qualquer ar, os outros com chão)
		for attempt in 12:
			var p := Vector3i(floori(player.position.x) + rng.randi_range(-14, 14), floori(player.position.y) + rng.randi_range(-2, 4), floori(player.position.z) + rng.randi_range(-14, 14))
			if world.get_block(p.x, p.y, p.z) == 0 and world.get_block(p.x, p.y + 1, p.z) == 0 and (d.ai == "fly" or Blocks.solid[world.get_block(p.x, p.y - 1, p.z)]) \
					and Vector3(p).distance_to(player.position) > 6.0:
				spawn_enemy(d, Vector3(p.x + 0.5, p.y, p.z + 0.5))
				return
		return
	var ang := rng.randf() * TAU
	var dist := rng.randf_range(SPAWN_MIN, SPAWN_MAX)
	var x := floori(player.position.x + cos(ang) * dist)
	var z := floori(player.position.z + sin(ang) * dist)
	if not world.in_world(Vector2i(floori(x / 16.0), floori(z / 16.0))):
		return
	spawn_enemy(d, Vector3(x + 0.5, world.surface_y(x, z) + (6 if d.ai == "fly" else 0), z + 0.5))


# O Velho na entrada do dungeon: aparece à noite (até o Skeletron cair) e some ao amanhecer.
func _old_man() -> void:
	if old_man and not enemies.has(old_man):
		old_man = null
	var e: Vector3i = world.gen.dungeon_entrance
	var near := Vector2(player.position.x, player.position.z).distance_to(Vector2(e.x, e.z)) < 90.0
	if old_man and (not clock.is_night() or world.skeletron_down):
		remove_enemy(old_man)
		old_man = null
	elif old_man == null and near and clock.is_night() and not world.skeletron_down and boss == null:
		old_man = spawn_enemy(def_named("old_man"), Vector3(e.x + 0.5, world.surface_y(e.x, e.z + 3, true) + 0.1, e.z + 3.5))


# Inimigo "npc" na mira (até `reach`), ou null.
func npc_aimed(reach: float) -> Node3D:
	for e in enemies:
		if e.def.ai == "npc":
			var eye: Vector3 = player.eye()
			var dir: Vector3 = -player.cam.global_basis.z
			var to: Vector3 = e.position + Vector3.UP * e.tall * 0.5 - eye
			if to.length() < reach and dir.dot(to.normalized()) > 0.9:
				return e
	return null


# Falar com um NPC (botão direito). O Velho: à noite amaldiçoa e vira o Skeletron.
func talk(e: Node3D) -> void:
	if e.def.talk == "skeletron":
		if not clock.is_night():
			player.say("O Velho: \"Volte à noite... se tiver coragem.\"")
		elif boss == null:
			var at: Vector3 = e.position
			remove_enemy(e)
			old_man = null
			var b := spawn_boss("skeletron")
			b.position = at + Vector3.UP * 3.0
			for o in enemies:
				if o.follow == b:
					o.position = at + Vector3.UP * 3.0
			player.say("O Velho: \"Você foi amaldiçoado!\"")


# Primeira vez que um chefe morre: o do mal libera o meteorito, o Skeletron abre o dungeon.
func boss_down(group: String) -> void:
	if group in ["eater_of_worlds", "brain_of_cthulhu"] and not world.evil_boss_down:
		world.evil_boss_down = true
		world.meteor_due = true
	elif group == "wall_of_flesh" and not world.hardmode:
		world.start_hardmode()
		player.say("o mundo foi abençoado: hardmode! (cobalto, paládio e o Hallow)")
	elif group == "skeletron" and not world.skeletron_down:
		world.skeletron_down = true
		player.say("o dungeon está aberto!")


# Escolhe um ponto de superfície seco, longe do nascimento e do bioma do mal, a 40-90 blocos do jogador, e solta a bola de fogo.
func start_meteor() -> void:
	var pos := Vector3i.ZERO
	for attempt in 30:
		var a := rng.randf() * TAU
		var d := rng.randf_range(40.0, 90.0)
		var x := floori(player.position.x + cos(a) * d)
		var z := floori(player.position.z + sin(a) * d)
		var y: int = world.surface_y(x, z, true) if world.in_world(Vector2i(floori(x / 16.0), floori(z / 16.0))) else 0
		var lo := 16
		var hi: int = WorldGen.SIZE_CHUNKS * WorldGen.CHUNK - 16
		if y > WorldGen.WATER_LEVEL + 1 and x > lo and z > lo and x < hi and z < hi and Vector2(x, z).distance_to(WorldGen.CENTER) > 30.0 \
				and world.gen.evil_weight(x, z) < 0.5:
			pos = Vector3i(x, y, z)
			break
	if pos == Vector3i.ZERO:
		return   # sem lugar bom agora: tenta de novo no próximo quadro
	world.meteor_due = false
	meteor = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 1.4
	sphere.height = 2.8
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color("#ff9a3a")
	sphere.material = mat
	meteor.mesh = sphere
	meteor.position = Vector3(pos.x + 0.5, pos.y + 90, pos.z + 0.5)
	meteor.set_meta("ground", float(pos.y))
	add_child(meteor)
	player.say("um meteorito caiu do céu! (%d blocos a %s)" % [int(Vector2(pos.x, pos.z).distance_to(Vector2(player.position.x, player.position.z))), _compass(Vector2(pos.x - player.position.x, pos.z - player.position.z))])


static func _compass(v: Vector2) -> String:
	return ("norte" if v.y < 0 else "sul") if absf(v.y) > absf(v.x) * 2.0 else ("oeste" if v.x < 0 else "leste") if absf(v.x) > absf(v.y) * 2.0 \
		else ("noroeste" if v.x < 0 else "nordeste") if v.y < 0 else ("sudoeste" if v.x < 0 else "sudeste")


# Cratera de 6 blocos de raio (cava o chão, derruba árvores) com meteorito no fundo.
func crater(cx: int, cz: int) -> void:
	var y0: int = world.surface_y(cx, cz, true)
	for dz in range(-7, 8):
		for dx in range(-7, 8):
			var r := Vector2(dx, dz).length()
			if r > 6.5:
				continue
			var floor_y := y0 - int((6.5 - r) * 0.55)
			for y in range(floor_y + 1, y0 + 14):
				var b: int = world.get_block(cx + dx, y, cz + dz)
				if b != 0 and b != Blocks.ids.bedrock:
					world.set_block(cx + dx, y, cz + dz, 0, false)
			if r < 3.6:
				world.set_block(cx + dx, floor_y, cz + dz, Blocks.ids.meteorite, false)
				world.set_block(cx + dx, floor_y - 1, cz + dz, Blocks.ids.meteorite, false)
			elif r < 5.0 and rng.randf() < 0.5:
				world.set_block(cx + dx, floor_y, cz + dz, Blocks.ids.meteorite, false)
	var at := Vector3(cx + 0.5, y0, cz + 0.5)
	Fx.puff(self, at, Color("#ff8a3a"), 40)
	Fx.sparks(self, at, Color("#ffd060"), 30, Vector3.UP)
	if player.position.distance_to(at) < 60.0:
		player.shake = maxf(player.shake, 1.0)


func spawn_enemy(d: Dictionary, pos: Vector3) -> Node3D:
	var e: Node3D = Enemy.new()
	e.def = d
	e.entities = self
	e.stats()
	e.position = pos
	add_child(e)
	enemies.append(e)
	return e


func def_named(n: String) -> Dictionary:
	return defs.filter(func(d): return d.name == n)[0]


func spawn_boss(n: String) -> Node3D:
	var ang := rng.randf() * TAU
	var d := def_named(n)
	if d.has("hands"):
		boss = spawn_enemy(d, player.position + Vector3(cos(ang) * 14, 8, sin(ang) * 14))
		for i in int(d.hands):   # as mãos giram em volta da cabeça
			var h := spawn_enemy(def_named("skeletron_hand"), boss.position + Vector3(i * 4 - 2, -1, 0))
			h.follow = boss
			h.angle = PI * i
	elif d.ai == "wall":   # nasce longe, no chão do submundo, do lado de onde a boneca foi jogada
		var at := player.position + Vector3(cos(ang), 0, sin(ang)) * 45.0
		boss = spawn_enemy(d, Vector3(clampf(at.x, 8.0, 248.0), 0.0, clampf(at.z, 8.0, 248.0)))
	elif d.has("worm"):
		var at := player.position + Vector3(cos(ang) * 22, 0, sin(ang) * 22)   # nasce debaixo da terra e sobe atrás do jogador
		at.y = maxf(world.surface_y(floori(at.x), floori(at.z), true) - 6.0, 3.0)
		boss = spawn_worm(d, at)
	else:
		boss = spawn_enemy(d, player.position + Vector3(cos(ang) * 20, 15, sin(ang) * 20))
		for i in int(d.get("creepers", 0)):   # servos que orbitam o chefe e o protegem
			var c := spawn_enemy(def_named(d.minion), boss.position + Vector3(rng.randf_range(-3, 3), rng.randf_range(-1, 3), rng.randf_range(-3, 3)))
			c.follow = boss
	boss_max = boss_life()
	Sfx.play(self, "boss", player.position, 0.0)
	return boss


# Verme: cabeça e uma fila de segmentos (d.worm: quantos, e qual def é o corpo e o rabo), cada um seguindo o da frente.
func spawn_worm(d: Dictionary, pos: Vector3) -> Node3D:
	var dir := (player.position - pos).normalized()
	var prev := spawn_enemy(d, pos)
	prev.heading = dir
	var head := prev
	for i in range(1, int(d.worm.segments)):
		var e := spawn_enemy(def_named(d.worm.tail if i == d.worm.segments - 1 else d.worm.body), pos - dir * d.size[0] * 0.8 * i)
		e.follow = prev
		prev = e
	return head


# Item de um drop: nos mundos de Carmesim o minério do mal é crimtano, onde o dado diz demonita (como o Terraria).
func drop_id(item: String) -> int:
	if item == "demonite_ore" and world.gen.evil == "crimson":
		return Items.ids.crimtane_ore
	return Items.ids[item]


func group_of(e: Node3D) -> String:
	return e.def.get("group", e.def.name)


func group_count(group: String) -> int:
	return enemies.filter(func(e): return e.def.get("group") == group).size()


func final_drops(group: String) -> Array:
	for d in defs:
		if d.get("group") == group and d.has("final_drops"):
			return d.final_drops
	return []


# Vida somada do chefe (todos os segmentos, se for verme).
func boss_life() -> int:
	if boss == null:
		return 0
	var g := group_of(boss)
	var t := 0
	for e in enemies:
		if group_of(e) == g:
			t += maxi(e.hp, 0)
	return t


# Um orbe quebrado (Shadow Orb / Crimson Heart): a cada 3º acorda o chefe do bioma.
func orb_broken(id: int) -> void:
	world.orbs_broken += 1
	if world.orbs_broken % 3 != 0:
		player.say("você sente uma presença maligna (%d/3)" % (world.orbs_broken % 3))
	elif boss == null:
		var n := "eater_of_worlds" if id == Blocks.ids.shadow_orb else "brain_of_cthulhu"
		if defs.any(func(d): return d.name == n):
			spawn_boss(n)
			player.say("%s despertou!" % n.replace("_", " "))


# Número de dano flutuante, como no Terraria: aparece com um salto, sobe e some. Laranja nos inimigos, vermelho no jogador; crítico (wiki:
# número mais forte, que sobe mais e demora mais) sai maior e fica mais tempo no ar.
func spawn_text(pos: Vector3, text: String, color: Color, crit := false) -> void:
	if not is_inside_tree():
		return
	var l := Label3D.new()
	l.text = text
	l.font_size = 64
	l.outline_size = 14
	l.outline_modulate = Color(0.12, 0.02, 0.0)
	l.modulate = color
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.shaded = false
	l.render_priority = 10
	l.pixel_size = 0.005 * maxf(1.0, pos.distance_to(player.eye()) / 7.0)   # de longe continua legível
	l.position = pos + Vector3(rng.randf_range(-0.3, 0.3), 0, rng.randf_range(-0.3, 0.3))
	var big := 1.6 if not crit else 2.4
	l.scale = Vector3.ONE * big
	add_child(l)
	var tw := l.create_tween().set_parallel(true)
	tw.tween_property(l, "scale", Vector3.ONE * (1.0 if not crit else 1.5), 0.15)
	tw.tween_property(l, "position:y", l.position.y + (1.5 if not crit else 2.2), 0.9 if not crit else 1.2).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 0.0, 0.35).set_delay(0.55 if not crit else 0.85)
	tw.tween_property(l, "outline_modulate:a", 0.0, 0.35).set_delay(0.55 if not crit else 0.85)
	tw.chain().tween_callback(l.queue_free)


func remove_enemy(e: Node3D) -> void:
	enemies.erase(e)
	if e == boss:   # verme: outro segmento vira o "chefe" da barra de vida
		boss = null
		for o in enemies:
			if e.def.has("group") and group_of(o) == e.def.group:
				boss = o
				break
	e.queue_free()


func spawn_drop(item: int, count: int, pos: Vector3) -> Node3D:
	var d: Node3D = ItemDrop.new()
	d.item = item
	d.count = count
	d.entities = self
	d.position = pos
	add_child(d)
	return d


func spawn_projectile(name: String, from: Vector3, dir: Vector3, speed: float, damage: int, knockback: float) -> Node3D:
	var a: Node3D = Projectile.new()
	a.def = projectiles[name]
	a.velocity = dir.normalized() * speed
	a.damage = damage
	a.knockback = knockback
	a.entities = self
	a.position = from
	add_child(a)
	return a
