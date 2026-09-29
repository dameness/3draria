extends Node3D
# Um inimigo de enemies.json com IA genérica por "ai": hop (slime), walk (zumbi), fly (olho demoníaco)
# e eye_of_cthulhu (chefe: paira, invoca servos e investe; fase 2 abaixo de phase2.below da vida).
# Visual: EnemyModel (modelo 3D por "model"; senão o sprite da wiki extrudado).

const GRAVITY := 28.0
const JUMP := 8.0
const FLASH_TIME := 0.25   # o inimigo fica vermelho e volta ao normal neste tempo depois de levar um golpe

var def: Dictionary
var entities: Node3D
var hp: int
var damage: int
var defense: int
var half: float
var tall: float
var velocity := Vector3.ZERO
var on_floor := false
var hit_wall := false
var timer := 0.0   # espera entre pulos do slime / tempo no estado do chefe
var stun := 0.0    # após levar golpe a IA para e o knockback age
var flash := 0.0
var flashing := false   # a sobreposição vermelha está ligada nos modelos
var rng := RandomNumberGenerator.new()
var model: Node3D
var flash_mat: StandardMaterial3D
# chefe
var mode := "hover"
var dashes := 0
var summoned := 0
var phase := 1
# verme (Eater of Worlds): cada segmento é um inimigo que segue o da frente; sem `follow` ele é a cabeça
var follow: Node3D = null
var heading := Vector3.ZERO
var summoned_timer := 3.0   # king slime: espera até soltar mais um slime
var teleport_timer := 9.0
var angle := 0.0    # creeper: fase da órbita em volta do cérebro (follow = o cérebro)


# Números do def (a entidade nasce com eles; _ready só monta o visual).
func stats() -> void:
	hp = def.life
	damage = def.damage
	defense = def.defense
	half = def.size[0] / 2.0
	tall = def.size[1]


func _ready() -> void:
	stats()
	model = EnemyModel.build(def)
	model.rotation.y = PI  # modelos olham para -Z; o nó gira para o jogador por +Z
	angle = rng.randf() * TAU
	if def.ai == "brain":   # fase 1: translúcido e imune
		set_ghost(true)
	if def.ai == "worm":
		model.position.y = tall / 2.0   # o modelo é centrado na origem e gira inteiro (cima/baixo também)
	add_child(model)
	flash_mat = StandardMaterial3D.new()
	flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flash_mat.albedo_color = Color(1, 0.1, 0.1, 0.65)
	flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA


func _process(delta: float) -> void:
	if model == null:
		return
	flash = maxf(flash - delta, 0.0)
	if flash > 0.0:   # vermelho ao levar dano, esmaecendo até sumir
		flash_mat.albedo_color.a = 0.65 * minf(flash / FLASH_TIME, 1.0)
	if (flash > 0.0) != flashing:
		flashing = flash > 0.0
		for m in model.find_children("", "MeshInstance3D", true, false):
			m.material_overlay = flash_mat if flashing else null
	if def.ai == "skeletron":   # gira na fase 2, senão encara o jogador
		model.rotation.y = model.rotation.y + delta * 14.0 if phase == 2 else PI
	if def.ai == "worm":
		var ahead := (follow.position - position) if follow else velocity   # a frente do segmento: para quem ele segue
		if ahead.length() > 0.01:
			model.basis = Basis.looking_at(ahead.normalized(), Vector3.UP)
	EnemyModel.animate(model, self, entities.player.eye(), Time.get_ticks_msec() / 1000.0)


func _physics_process(delta: float) -> void:
	think(delta)
	move(delta)
	var p: Node3D = entities.player
	if damage > 0 and VoxelBody.touches(position, half, tall, p.position, p.HALF, p.TALL):
		p.hurt(damage, p.position - position)


func think(delta: float) -> void:
	stun -= delta
	if stun > 0:
		return
	var p: Node3D = entities.player
	var to: Vector3 = p.position + Vector3.UP - (position + Vector3.UP * tall / 2)
	var flat := Vector3(to.x, 0, to.z).normalized()
	match def.ai:
		"hop":
			if on_floor:
				velocity.x *= 0.7
				velocity.z *= 0.7
				timer -= delta
				if timer <= 0:
					timer = rng.randf_range(1.0, 2.0)
					velocity = flat * def.speed + Vector3.UP * JUMP
		"walk":
			velocity.x = flat.x * def.speed
			velocity.z = flat.z * def.speed
			if on_floor and hit_wall:
				velocity.y = JUMP
		"fly":
			velocity = velocity.lerp(to.normalized() * def.speed, delta * 1.5)
		"eye_of_cthulhu":
			eye_of_cthulhu(delta, to)
		"worm":
			worm(delta, to)
			return
		"brain":
			brain(delta, to)
		"creeper":
			creeper(delta, to)
		"king_slime":
			king_slime(delta, to, flat)
		"skeletron":
			skeletron(delta, to)
		"wall":
			wall(delta, flat)
		"npc":
			velocity.x = 0.0
			velocity.z = 0.0
	if flat != Vector3.ZERO:
		rotation.y = atan2(flat.x, flat.z)


# Fase 1: paira acima do jogador invocando servos, depois 3 investidas. Fase 2: investidas em cadeia
# mais rápidas. Ao amanhecer, sobe e vai embora.
func eye_of_cthulhu(delta: float, to: Vector3) -> void:
	if not entities.clock.is_night():
		velocity = Vector3.UP * 20
		if position.distance_to(entities.player.position) > 60:
			entities.remove_enemy(self)
		return
	var p2: Dictionary = def.phase2
	if phase == 1 and hp < def.life * p2.below:
		phase = 2
		damage = p2.damage
		defense = p2.defense
		if model:
			EnemyModel.set_phase(model, 2)
	timer -= delta
	match mode:
		"hover":
			var t := Time.get_ticks_msec() / 1000.0
			var target: Vector3 = entities.player.position + Vector3(cos(t) * 6, 8, sin(t) * 6)
			velocity = velocity.lerp((target - position).limit_length(def.speed * 1.5), delta * 2.0)
			if phase == 1 and summoned < 3 and timer < 3.0 - summoned:
				summoned += 1
				entities.spawn_enemy(entities.def_named(def.minion), position + Vector3.DOWN)
			if timer <= 0:
				mode = "dash"
				dashes = 3 if phase == 1 else 5
				timer = 0
		"dash":
			if timer <= 0:
				if dashes == 0:
					mode = "hover"
					timer = 4.0 if phase == 1 else 2.0
					summoned = 0
					return
				dashes -= 1
				velocity = to.normalized() * (16.0 if phase == 1 else 24.0)
				timer = 0.8 if phase == 1 else 0.45
			velocity *= 1.0 - delta * 0.8


func set_ghost(on: bool) -> void:
	if model == null:
		return
	for m in model.find_children("", "MeshInstance3D", true, false):
		m.transparency = 0.5 if on else 0.0


# Brain of Cthulhu. Fase 1: translúcido e imune, teleporta em volta do jogador enquanto os Creepers atacam; quando o último
# Creeper morre vira sólido (fase 2): some, reaparece perto do jogador e investe.
func brain(delta: float, to: Vector3) -> void:
	var p: Node3D = entities.player
	timer -= delta
	if phase == 1 and entities.group_count(def.group) <= 1:
		phase = 2
		mode = "wait"
		timer = 1.0
		set_ghost(false)
		Fx.puff(entities, position + Vector3.UP * tall * 0.5, Color(def.color), 30)
		p.say("o Brain of Cthulhu está furioso!")
	if phase == 1:
		velocity = velocity.lerp(to.normalized() * 2.5, delta * 1.5)
		if timer <= 0:
			timer = 4.0
			_teleport(p, 12.0)
		return
	match mode:
		"wait":   # paira devagar
			velocity = velocity.lerp(to.normalized() * 3.0, delta * 2.0)
			if timer <= 0:
				_teleport(p, 9.0)
				mode = "aim"
				timer = 0.7
		"aim":
			velocity = Vector3.ZERO
			if timer <= 0:
				mode = "dash"
				timer = 0.9
				velocity = to.normalized() * 17.0
		"dash":
			velocity *= 1.0 - delta * 0.6
			if timer <= 0:
				mode = "wait"
				timer = 1.6


# King Slime: pulos grandes atrás do jogador (a cada 3º, um salto alto), teleporta perto dele de tempos em tempos ou se ficar
# longe, e solta slimes menores.
func king_slime(delta: float, to: Vector3, flat: Vector3) -> void:
	var p: Node3D = entities.player
	summoned_timer -= delta
	teleport_timer -= delta
	if teleport_timer <= 0.0 or position.distance_to(p.position) > 30.0:
		teleport_timer = 9.0
		Fx.puff(entities, position + Vector3.UP * tall * 0.5, Color(def.color), 20)
		var a := rng.randf() * TAU
		var x := floori(p.position.x + cos(a) * 9.0)
		var z := floori(p.position.z + sin(a) * 9.0)
		position = Vector3(x + 0.5, entities.world.surface_y(x, z) + 0.2, z + 0.5)
		velocity = Vector3.ZERO
		Fx.puff(entities, position + Vector3.UP * tall * 0.5, Color(def.color), 20)
	if summoned_timer <= 0.0 and entities.enemies.size() < 10:
		summoned_timer = 5.0
		var names: Array = def.minion
		entities.spawn_enemy(entities.def_named(names[rng.randi() % names.size()]), position + Vector3(rng.randf_range(-1, 1), tall, rng.randf_range(-1, 1)))
	if on_floor:
		velocity.x *= 0.6
		velocity.z *= 0.6
		timer -= delta
		if timer <= 0:
			dashes += 1
			var big := dashes % 3 == 0
			timer = rng.randf_range(0.9, 1.6)
			velocity = flat * def.speed * (1.7 if big else 1.2) + Vector3.UP * (JUMP * (1.5 if big else 1.0))


# Skeletron (só à noite: ao amanhecer ele foge). Fase 1: paira sobre o jogador e investe de tempos em tempos, com as mãos em volta
# (ai "creeper" nelas); abaixo de 50% da vida ou sem mãos, gira sem defesa atrás do jogador.
func skeletron(delta: float, to: Vector3) -> void:
	if not entities.clock.is_night():
		velocity = Vector3.UP * 20
		if position.distance_to(entities.player.position) > 60:
			for o in entities.enemies.duplicate():
				if o.def.get("group") == def.group:
					entities.remove_enemy(o)
		return
	timer -= delta
	if phase == 1 and (hp < def.life * 0.5 or entities.group_count(def.group) <= 1):
		phase = 2
		damage = 60
		defense = 0
		entities.player.say("o Skeletron gira, furioso!")
	if phase == 2:
		velocity = velocity.lerp(to.normalized() * def.speed * 1.4, delta * 3.0)
		return
	var t := Time.get_ticks_msec() / 1000.0
	if mode == "dash":
		if timer <= 0:
			mode = "hover"
			timer = 6.0
		velocity *= 1.0 - delta * 0.7
		return
	var target: Vector3 = entities.player.position + Vector3(cos(t * 0.7) * 4.0, 5.0, sin(t * 0.7) * 4.0)
	velocity = velocity.lerp((target - position).limit_length(def.speed), delta * 2.5)
	if timer <= 0:
		mode = "dash"
		timer = 0.8
		velocity = to.normalized() * 15.0


# Wall of Flesh: coluna gigante que atravessa o submundo atrás do jogador (mais rápida quanto menos vida tem), com dois olhos que
# atiram lasers e uma boca que solta The Hungry. Vai embora se o jogador se afasta demais.
func wall(delta: float, flat: Vector3) -> void:
	var p: Node3D = entities.player
	position.y = 0.0
	velocity = flat * lerpf(6.0, def.speed, clampf(float(hp) / def.life, 0.0, 1.0))
	timer -= delta
	summoned_timer -= delta
	var right := flat.cross(Vector3.UP)
	if timer <= 0.0:
		timer = 2.4
		for side in [-1, 1]:
			var eye: Vector3 = position + Vector3.UP * tall * 0.66 + right * side * 3.2 + flat * 1.8
			entities.spawn_projectile("eye_laser", eye, (p.position + Vector3.UP * p.EYE - eye).normalized(), 16.0, 25, 0.0)
	if summoned_timer <= 0.0 and entities.enemies.filter(func(e): return e.def.name == def.minion).size() < 6:
		summoned_timer = 5.0
		entities.spawn_enemy(entities.def_named(def.minion), position + Vector3.UP * tall * 0.3 + flat * 3.0)
	if position.distance_to(p.position) > 150.0:
		entities.remove_enemy(self)


func _teleport(p: Node3D, dist: float) -> void:
	Fx.puff(entities, position + Vector3.UP * tall * 0.5, Color(def.color), 14)
	var a := rng.randf() * TAU
	position = p.position + Vector3(cos(a) * dist, rng.randf_range(1.0, 5.0), sin(a) * dist)
	Fx.puff(entities, position + Vector3.UP * tall * 0.5, Color(def.color), 14)


# Creeper: gira em volta do cérebro e, de tempos em tempos, se joga no jogador; sem cérebro, persegue direto.
func creeper(delta: float, to: Vector3) -> void:
	timer -= delta
	if not is_instance_valid(follow):
		velocity = velocity.lerp(to.normalized() * def.speed, delta * 2.0)
		return
	var t := Time.get_ticks_msec() / 1000.0
	if mode == "dash":
		velocity = to.normalized() * def.speed * 1.5
		if timer <= 0:
			mode = "orbit"
			timer = rng.randf_range(2.0, 5.0)
		return
	mode = "orbit" if mode == "hover" else mode
	var target: Vector3 = follow.position + Vector3.UP * follow.tall * 0.5 + Vector3(cos(t * 1.6 + angle), 0.4 * sin(t * 2.1 + angle), sin(t * 1.6 + angle)) * 5.5
	velocity = velocity.lerp((target - position).limit_length(def.speed), delta * 4.0)
	if timer <= 0:
		mode = "dash"
		timer = 0.9


# Cabeça: vira devagar para o jogador e atravessa os blocos (por isso circula ao errar). Corpo: mantém a distância do da frente.
func worm(delta: float, to: Vector3) -> void:
	if follow == null:
		if heading == Vector3.ZERO:
			heading = to.normalized()
		heading = heading.lerp(to.normalized(), clampf(delta * 1.6, 0.0, 1.0))
		heading = heading.normalized() if heading.length() > 0.05 else to.normalized()
		velocity = heading * def.speed
		return
	velocity = Vector3.ZERO
	var d := position - follow.position
	var spacing: float = def.size[0] * 0.8
	position = follow.position + (d.normalized() if d.length() > 0.001 else Vector3.BACK) * spacing


func move(delta: float) -> void:
	if def.get("noclip", def.get("boss", false)):
		position += velocity * delta  # chefes voadores atravessam blocos, como no Terraria
		return
	if def.ai != "fly":
		velocity.y = maxf(velocity.y - GRAVITY * delta, -50.0)
	var r := VoxelBody.move(entities.world, position, half, tall, velocity * delta)
	position = r[0]
	var hit: Vector3i = r[1]
	on_floor = hit.y < 0
	hit_wall = hit.x != 0 or hit.z != 0
	for a in 3:
		if hit[a] != 0:
			velocity[a] = -velocity[a] * 0.5 if def.ai == "fly" else 0.0
	if position.y < -10:
		entities.remove_enemy(self)


# Dano como no Terraria (modo normal): dano − defesa/2, mínimo 1. Retorna o dano causado.
func hurt(dmg: int, dir: Vector3, knockback: float) -> int:
	if def.get("invulnerable", false):
		return 0
	if def.ai == "brain" and phase == 1:   # imune enquanto houver Creepers
		Fx.sparks(entities, position + Vector3.UP * tall * 0.5, Color(0.8, 0.8, 1.0), 4, dir)
		return 0
	var taken := maxi(1, dmg - ceili(defense / 2.0))
	hp -= taken
	flash = FLASH_TIME
	Sfx.play(entities, "die" if hp <= 0 else "hit", position)
	entities.spawn_text(position + Vector3.UP * (tall + 0.3), str(taken), Color("#ffa050"))
	var blood := Color(def.get("blood", def.color))
	var away := Vector3(dir.x, 0.4, dir.z).normalized()
	Fx.blood(entities, position + Vector3.UP * tall * 0.55, blood, 8, away)
	Fx.sparks(entities, position + Vector3.UP * tall * 0.55, Color(1, 0.95, 0.75), 3, away)
	var kb: float = knockback * (1.0 - def.get("kb_resist", 0.0))
	if kb > 0:
		var flat := Vector3(dir.x, 0, dir.z).normalized()
		velocity = flat * kb + Vector3.UP * (3.0 if def.ai != "fly" else 0.0)
		stun = 0.25
	if hp <= 0:
		Fx.puff(entities, position + Vector3.UP * tall * 0.5, blood, 12 if not def.get("boss") else 40)
		for o in entities.enemies:   # verme: quem seguia este segmento vira cabeça de um verme novo
			if o.follow == self:
				o.follow = null
		if def.ai == "skeletron":   # matar a cabeça acaba a luta: as mãos somem
			for o in entities.enemies.duplicate():
				if o != self and o.def.get("group") == def.group:
					entities.remove_enemy(o)
		if def.has("group") and entities.group_count(def.group) <= 1:   # o último segmento solta o prêmio do chefe
			entities.boss_down(def.group)
			for d in entities.final_drops(def.group):
				if rng.randf() < d.chance:
					entities.spawn_drop(entities.drop_id(d.item), rng.randi_range(d.min, d.max), position + Vector3.UP * 0.3)
		var picked := {}   # drops com "pick": só um item de cada grupo cai (as 3 peças do Ninja: sai uma)
		for entry in def.drops:
			var d: Dictionary = entry
			if d.has("pick"):
				if picked.has(d.pick):
					continue
				var group: Array = def.drops.filter(func(x): return x.get("pick") == d.pick)
				d = group[rng.randi() % group.size()]
				picked[d.pick] = true
			if rng.randf() < d.chance:
				entities.spawn_drop(entities.drop_id(d.item), rng.randi_range(d.min, d.max), position + Vector3.UP * 0.3)
		entities.remove_enemy(self)
	return taken
