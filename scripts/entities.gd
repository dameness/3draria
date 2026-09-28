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
	spawn_timer -= delta
	if spawn_timer <= 0:
		spawn_timer = 1.0
		try_spawn()
	for e in enemies.duplicate():
		if not e.def.get("boss") and e.position.distance_to(player.position) > DESPAWN:
			remove_enemy(e)


func try_spawn() -> void:
	var night: bool = clock.is_night()
	if enemies.size() >= (MAX_NIGHT if night else MAX_DAY) or rng.randf() > 0.5:
		return
	var when := "night" if night else "day"
	var evil: String = world.gen.evil if world.gen.evil_weight(floori(player.position.x), floori(player.position.z)) >= 0.5 else ""
	var options := defs.filter(func(d): return (d.spawn == when or d.spawn == "any") and (not d.has("biome") or d.biome == evil))
	if options.is_empty():
		return
	var d: Dictionary = options[rng.randi() % options.size()]
	var ang := rng.randf() * TAU
	var dist := rng.randf_range(SPAWN_MIN, SPAWN_MAX)
	var x := floori(player.position.x + cos(ang) * dist)
	var z := floori(player.position.z + sin(ang) * dist)
	if not world.in_world(Vector2i(floori(x / 16.0), floori(z / 16.0))):
		return
	spawn_enemy(d, Vector3(x + 0.5, world.surface_y(x, z) + (6 if d.ai == "fly" else 0), z + 0.5))


func spawn_enemy(d: Dictionary, pos: Vector3) -> Node3D:
	var e: Node3D = Enemy.new()
	e.def = d
	e.entities = self
	e.hp = d.life
	e.position = pos
	add_child(e)
	enemies.append(e)
	return e


func def_named(n: String) -> Dictionary:
	return defs.filter(func(d): return d.name == n)[0]


func spawn_boss(n: String) -> Node3D:
	var ang := rng.randf() * TAU
	var d := def_named(n)
	if d.has("worm"):
		boss = spawn_worm(d, player.position + Vector3(cos(ang) * 22, 2, sin(ang) * 22))
	else:
		boss = spawn_enemy(d, player.position + Vector3(cos(ang) * 20, 15, sin(ang) * 20))
	boss_max = boss_life()
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


# Número de dano flutuante, como no Terraria: aparece com um salto, sobe e some. Laranja nos inimigos, vermelho no jogador.
func spawn_text(pos: Vector3, text: String, color: Color) -> void:
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
	l.scale = Vector3.ONE * 1.6
	add_child(l)
	var tw := l.create_tween().set_parallel(true)
	tw.tween_property(l, "scale", Vector3.ONE, 0.15)
	tw.tween_property(l, "position:y", l.position.y + 1.5, 0.9).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 0.0, 0.35).set_delay(0.55)
	tw.tween_property(l, "outline_modulate:a", 0.0, 0.35).set_delay(0.55)
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
