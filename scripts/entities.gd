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
	return Items.icon_texture(item, world.material.albedo_texture)


func _physics_process(delta: float) -> void:
	spawn_timer -= delta
	if spawn_timer <= 0:
		spawn_timer = 1.0
		try_spawn()
	for e in enemies.duplicate():
		if e.position.distance_to(player.position) > DESPAWN:
			remove_enemy(e)


func try_spawn() -> void:
	var night: bool = clock.is_night()
	if enemies.size() >= (MAX_NIGHT if night else MAX_DAY) or rng.randf() > 0.5:
		return
	var when := "night" if night else "day"
	var options := defs.filter(func(d): return d.spawn == when or d.spawn == "any")
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
	e.position = pos
	add_child(e)
	enemies.append(e)
	return e


func remove_enemy(e: Node3D) -> void:
	enemies.erase(e)
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
