extends Node3D
# Um inimigo de enemies.json com IA genérica por "ai": hop (slime), walk (zumbi), fly (olho demoníaco)
# e eye_of_cthulhu (chefe: paira, invoca servos e investe; fase 2 abaixo de phase2.below da vida).
# Visual: EnemyModel (modelo 3D por "model"; senão o sprite da wiki extrudado).

const GRAVITY := 28.0
const JUMP := 8.0
const FLASH_TIME := 0.25   # o inimigo fica vermelho e volta ao normal neste tempo depois de levar um golpe
const WORM_GRAVITY := 14.85   # verme no ar: 0,11 px/quadro² da wiki (24,75 tiles/s²) × 0,6 bloco por tile
const WORM_FREE := 37.0       # a wiki: cabeça a mais de 62,5 tiles (~37 blocos) do jogador voa livre
const WORM_TURN := 3.0        # rad/s da cabeça dentro do terreno (a wiki não dá o número; tirado do jogo)
const NPC_SPEED := 1.5        # habitante andando (a wiki não dá o número; tirado do jogo)
const WANDER := 6.0           # de dia o habitante anda até tantos blocos de casa
const HOME_WAIT := 12.0       # à noite, tantos segundos sem chegar em casa e ele aparece lá

var def: Dictionary
var display := false   # vitrine do mundo de teste: parado, sem IA nem dano (ainda leva golpe e solta os drops)
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
var skull_timer := 1.33     # skeletron: espera até a próxima caveira
var shots := 0            # conjurador: esferas que faltam depois do teleporte
var shot_timer := 0.0
var spin_timer := 13.33   # skeletron: segundos até trocar de fase (mãos ↔ giro)
var angle := 0.0    # creeper: fase da órbita em volta do cérebro (follow = o cérebro)
var home := Vector3.ZERO    # habitante: a casa (ou o ponto perto do nascimento); quem põe é Entities
var goal := Vector3.ZERO    # habitante: para onde anda de dia
var walk_timer := 0.0       # habitante: segundos até escolher outro destino
var stuck := 0.0            # habitante: segundos tentando chegar em casa à noite
var door_at := Vector3i(-1, -1, -1)   # habitante: a porta que ele abriu e vai fechar depois de passar


# Números do def (a entidade nasce com eles; _ready só monta o visual).
func stats() -> void:
	hp = def.life
	damage = def.damage
	defense = def.defense
	half = def.size[0] / 2.0
	tall = def.size[1]
	if def.ai == "caster":
		timer = 2.5   # wiki: teleporta 2,5 s depois de nascer


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
			model.basis = orient(model.basis, ahead.normalized(), delta)
	EnemyModel.animate(model, self, entities.player.eye(), Time.get_ticks_msec() / 1000.0)


func _physics_process(delta: float) -> void:
	if display:
		return
	think(delta)
	move(delta)
	var p: Node3D = entities.player
	if damage > 0 and def.ai != "npc" and VoxelBody.touches(position, half, tall, p.position, p.HALF, p.TALL):
		p.hurt(Combat.vary(damage, rng), p.position - position)


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
		"caster":
			caster(delta)
		"queen_bee":
			queen_bee(delta, to)
		"npc":
			flat = npc(delta, to, flat)
	if flat != Vector3.ZERO:
		rotation.y = atan2(flat.x, flat.z)


# Habitante (wiki Town NPCs): de dia anda perto de casa (WANDER), à noite volta para ela; com o jogador a menos de 3 blocos para e olha para ele.
# Abre a porta que o barra e a fecha depois de passar. Devolve para onde olha (ZERO = onde já olhava).
# ponytail: sem busca de caminho: anda em linha reta e, se uma parede o segura por HOME_WAIT s à noite, aparece em casa (a wiki também teleporta);
# upgrade: busca de caminho pela moradia.
func npc(delta: float, to: Vector3, flat: Vector3) -> Vector3:
	velocity.x = 0.0
	velocity.z = 0.0
	if def.has("attack"):
		npc_attack(delta)
	var look := flat if to.length() < 7.0 else Vector3.ZERO
	if not def.talk in entities.TOWN or to.length() < 3.0:   # o Velho fica onde está
		return look
	if door_at.y >= 0 and Vector2(door_at.x + 0.5 - position.x, door_at.z + 0.5 - position.z).length() > 1.2:
		if entities.world.get_block(door_at.x, door_at.y, door_at.z) == Blocks.door_open:
			entities.player.toggle_door(door_at)
		door_at = Vector3i(-1, -1, -1)
	var h := Vector3(home.x - position.x, 0.0, home.z - position.z)
	if entities.clock.is_night():
		if h.length() < 0.5:
			stuck = 0.0
			return look
		stuck += delta
		if stuck > HOME_WAIT:
			stuck = 0.0
			Fx.puff(entities, position + Vector3.UP * tall * 0.5, Color(def.color), 14)
			position = home
			Fx.puff(entities, position + Vector3.UP * tall * 0.5, Color(def.color), 14)
			return look
		return _walk(h.normalized())
	stuck = 0.0
	walk_timer -= delta
	if walk_timer <= 0.0:
		walk_timer = rng.randf_range(3.0, 8.0)
		goal = home + Vector3(rng.randf_range(-WANDER, WANDER), 0.0, rng.randf_range(-WANDER, WANDER)) if rng.randf() < 0.6 else position
	var g := Vector3(goal.x - position.x, 0.0, goal.z - position.z)
	return _walk(g.normalized()) if g.length() > 0.4 else look


# Anda na direção dir: abre a porta fechada à frente, ou pula o degrau. Devolve dir.
func _walk(dir: Vector3, speed := NPC_SPEED) -> Vector3:
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed
	if on_floor and hit_wall:
		var ahead := position + dir * (half + 0.3)
		for dy in 2:
			var c := Vector3i(floori(ahead.x), floori(position.y) + dy, floori(ahead.z))
			if entities.world.get_block(c.x, c.y, c.z) == Blocks.door_closed:
				entities.player.toggle_door(c)
				door_at = c
				return dir
		velocity.y = JUMP
	return dir


# Habitante: a cada `cooldown` atira em quem estiver a até `range` blocos (dano = o da wiki, `damage`).
# ponytail: sem linha de visada (o tiro que bate em parede some); habitante segue invulnerável.
func npc_attack(delta: float) -> void:
	timer -= delta
	if timer > 0.0:
		return
	var a: Dictionary = def.attack
	var from := position + Vector3.UP * tall * 0.7
	var target: Node3D = null
	for e in entities.enemies:
		if e.def.ai != "npc" and not e.display and from.distance_to(e.position) < a.range \
				and (target == null or from.distance_to(e.position) < from.distance_to(target.position)):
			target = e
	if target == null:
		return
	timer = a.cooldown
	var aim: Vector3 = target.position + Vector3.UP * target.tall / 2
	var t: float = from.distance_to(aim) / a.speed   # a gravidade do projétil derruba o tiro: mira mais alto
	aim.y += 0.5 * entities.projectiles[a.projectile].get("gravity", 0.0) * t * t
	var shot: Node3D = entities.spawn_projectile(a.projectile, from, aim - from, a.speed, damage, 3.0)
	shot.npc = true


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
				dashes = 3
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


# Fase 1 do cérebro (imune): modelo translúcido. O alpha vai no material porque o renderer Compatibility ignora MeshInstance3D.transparency.
func set_ghost(on: bool) -> void:
	if model == null:
		return
	for m in model.find_children("", "MeshInstance3D", true, false):
		var mat := m.material_override as StandardMaterial3D
		if mat:
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if on else BaseMaterial3D.TRANSPARENCY_DISABLED
			mat.albedo_color.a = 0.5 if on else 1.0


# Brain of Cthulhu. Fase 1: translúcido e imune, teleporta em volta do jogador enquanto os Creepers atacam; quando o último
# Creeper morre vira sólido (fase 2): some, reaparece perto do jogador e investe.
func brain(delta: float, to: Vector3) -> void:
	var p: Node3D = entities.player
	timer -= delta
	if phase == 1 and entities.group_count(def.group) <= 1:
		phase = 2
		mode = "wait"
		timer = 1.0
		entities.boss_max = entities.boss_life()   # a barra passa a contar só o cérebro
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
	spin_timer -= delta   # wiki Skeletron: ~13,3 s com as mãos atacando, ~6,7 s girando atrás do jogador (+30% de dano, defesa −10), em ciclo até o fim
	if spin_timer <= 0.0:
		phase = 3 - phase
		spin_timer = 6.67 if phase == 2 else 13.33
		damage = roundi(def.damage * 1.3) if phase == 2 else def.damage
		defense = maxi(def.defense - 10, 0) if phase == 2 else def.defense
		if phase == 2:
			entities.player.say("o Skeletron gira, furioso!")
	if phase == 2:
		velocity = velocity.lerp(to.normalized() * def.speed * 1.4, delta * 3.0)
		return
	# wiki: com uma mão morta ou abaixo de 75% da vida, solta uma caveira teleguiada a cada ~1,33 s (0,67 s sem as mãos); não atira girando
	var hands: int = entities.enemies.filter(func(e): return e.def.name == "skeletron_hand").size()
	if hands < def.hands or hp < def.life * 0.75:
		skull_timer -= delta
		if skull_timer <= 0.0:
			skull_timer = 1.33 if hands > 0 else 0.67
			entities.spawn_projectile("skull_bolt", position + Vector3.UP * tall * 0.4, to, 8.0, 34, 0.0)
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


# Queen Bee (wiki), três ataques em ciclo: nivela com o jogador e investe 3 vezes; paira em cima soltando 6 abelhas; paira e atira ferrões.
# ponytail: sem o enfurecimento fora da selva nem o veneno.
func queen_bee(delta: float, to: Vector3) -> void:
	var p: Node3D = entities.player
	timer -= delta
	var away := Vector3(-to.x, 0, -to.z).normalized() if Vector2(to.x, to.z).length() > 0.5 else Vector3.RIGHT
	match mode:
		"align":   # 9 blocos ao lado do jogador, na altura dele
			velocity = velocity.lerp(((p.position + away * 9.0 + Vector3.UP) - position).limit_length(def.speed * 2.0), delta * 3.0)
			if position.distance_to(p.position + away * 9.0) < 2.5 or timer <= 0.0:
				mode = "charge"
				dashes = 3
				timer = 0.0
		"charge":
			if timer <= 0.0:
				if dashes == 0:
					mode = "bees"
					timer = 4.0
					summoned = 0
					return
				dashes -= 1
				velocity = to.normalized() * 22.0
				timer = 0.9
			velocity *= 1.0 - delta * 0.8
		"bees":
			velocity = velocity.lerp(((p.position + Vector3.UP * 7.0) - position).limit_length(def.speed), delta * 2.0)
			if summoned < 6 and timer < 4.0 - summoned * 0.5 and entities.enemies.filter(func(e): return e.def.name == "bee").size() < 12:
				summoned += 1
				entities.spawn_enemy(entities.def_named(def.minion), position + Vector3.DOWN)
			if timer <= 0.0:
				mode = "stingers"
				timer = 4.0
				shot_timer = 0.0
		_:   # "stingers" (e o começo)
			if mode != "stingers":
				mode = "align"
				timer = 3.0
				return
			velocity = velocity.lerp(((p.position + Vector3.UP * 6.0 + away * 3.0) - position).limit_length(def.speed), delta * 2.0)
			shot_timer -= delta
			if shot_timer <= 0.0:
				shot_timer = 0.45
				entities.spawn_projectile("stinger", position, p.position + Vector3.UP - position, 14.0, 22, 0.0)
			if timer <= 0.0:
				mode = "align"
				timer = 3.0


# Conjurador (wiki Caster AI: Dark Caster, Tim, Fire Imp): parado; 2,5 s depois de nascer e a cada 10,8 s teleporta para um ponto livre perto do jogador e
# solta 3 esferas (def.shoot) com 1,67 s entre elas; levar um golpe cancela os tiros e adia o teleporte para 4,2 s.
# As esferas atravessam blocos e um golpe ou projétil do jogador as destrói.
func caster(delta: float) -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	timer -= delta
	var p: Node3D = entities.player
	if timer <= 0.0:
		timer = 10.83
		shots = 0
		if _blink(p.position):
			shots = int(def.shoot.get("count", 3))
			shot_timer = 1.67
	if shots > 0:
		shot_timer -= delta
		if shot_timer <= 0.0:
			shot_timer = 1.67
			shots -= 1
			var from := position + Vector3.UP * tall * 0.7
			entities.spawn_projectile(def.shoot.projectile, from, p.position + Vector3.UP - from, def.shoot.speed, def.shoot.damage, 0.0)


# Teleporta para o chão livre (3 de altura) a 6-12 blocos do alvo, na altura dele ±6. false = não achou lugar.
func _blink(target: Vector3) -> bool:
	var world: Node3D = entities.world
	for attempt in 20:
		var a := rng.randf() * TAU
		var d := rng.randf_range(6.0, 12.0)
		var x := floori(target.x + cos(a) * d)
		var z := floori(target.z + sin(a) * d)
		for y in range(floori(target.y) + 6, floori(target.y) - 7, -1):
			if Blocks.solid[world.get_block(x, y - 1, z)] and not Blocks.solid[world.get_block(x, y, z)] and not Blocks.solid[world.get_block(x, y + 1, z)] and not Blocks.solid[world.get_block(x, y + 2, z)]:
				Fx.puff(entities, position + Vector3.UP * tall * 0.5, Color(def.color), 14)
				position = Vector3(x + 0.5, y, z + 0.5)
				velocity = Vector3.ZERO
				Fx.puff(entities, position + Vector3.UP * tall * 0.5, Color(def.color), 14)
				return true
	return false


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


# Cabeça: dentro do terreno escava e vira para o jogador (giro limitado); fora dele, no ar, só cai (arco balístico, gravidade da wiki) até
# voltar a escavar; a mais de WORM_FREE do jogador voa livre. Corpo: mantém a distância do segmento da frente (a fila segue a cabeça).
func worm(delta: float, to: Vector3) -> void:
	if follow == null:
		var world: Node3D = entities.world
		var inside: bool = Blocks.solid[world.get_block(floori(position.x), floori(position.y + tall / 2.0), floori(position.z))]
		if heading == Vector3.ZERO:
			heading = to.normalized() if to.length() > 0.01 else Vector3.FORWARD
		if inside or to.length() > WORM_FREE:
			if to.length() > 0.01:
				heading = turn(heading, to.normalized(), WORM_TURN * (1.0 if inside else 0.5) * delta)
			velocity = heading * def.speed
		else:
			velocity.y -= WORM_GRAVITY * delta
			velocity = velocity.limit_length(def.speed * 1.6)
			if velocity.length() > 0.5:
				heading = velocity.normalized()
		return
	velocity = Vector3.ZERO
	var d := position - follow.position
	var spacing: float = def.size[0] * 0.8
	position = follow.position + (d.normalized() if d.length() > 0.001 else Vector3.BACK) * spacing


# Gira `from` na direção de `to` por no máximo `max_angle` (radianos), pelo menor arco; de frente para trás escolhe um eixo qualquer.
static func turn(from: Vector3, to: Vector3, max_angle: float) -> Vector3:
	var ang := from.angle_to(to)
	if ang < 0.0001:
		return to
	var axis := from.cross(to)
	if axis.length() < 0.001:
		axis = from.cross(Vector3.UP if absf(from.y) < 0.99 else Vector3.RIGHT)
	return from.rotated(axis.normalized(), minf(ang, max_angle))


# Gira o modelo `b` para a frente `fwd` pelo menor arco, sem rolagem em volta do eixo (`looking_at` com UP dá um flip de ~155° quando a
# frente fica vertical), e devolve devagar o "cima" do modelo para o do mundo, para a placa das costas ficar por cima.
static func orient(b: Basis, fwd: Vector3, delta: float) -> Basis:
	b = Basis(Quaternion((-b.z).normalized(), fwd)) * b
	var up := Vector3.UP - fwd * fwd.y
	if up.length() > 0.3:
		b = Basis(fwd, clampf(b.y.signed_angle_to(up.normalized(), fwd), -delta * 3.0, delta * 3.0)) * b
	return b.orthonormalized()


# Troca o papel do segmento (head, body, tail) pelo def do papel: dano/defesa da wiki e o modelo com a boca ou a ponta do rabo.
func set_role(role: String) -> void:
	var head_def: Dictionary = entities.def_named(def.group)   # a cabeça tem o nome do grupo e a tabela `worm`
	def = head_def if role == "head" else entities.def_named(head_def.worm[role])
	damage = def.damage
	defense = def.defense
	half = def.size[0] / 2.0
	tall = def.size[1]
	if model:   # (fora da árvore, nos testes, o modelo ainda não existe)
		model.queue_free()
		model = EnemyModel.build(def)
		model.position.y = tall / 2.0
		add_child(model)
		flashing = false


# Morreu um segmento: a fila se divide como na wiki. Cabeça morta: quem vinha atrás vira cabeça; corpo morto: a frente vira rabo e o de
# trás vira cabeça; rabo morto: o da frente vira rabo. Pedaço de um segmento só não sobrevive: morre na hora e solta o prêmio.
func split_worm() -> void:
	var back: Node3D = null
	for o in entities.enemies:
		if o.follow == self:
			back = o
	var lone := []
	if back:
		back.follow = null
		if entities.enemies.any(func(o): return o.follow == back):
			back.set_role("head")
			back.velocity = Vector3.ZERO   # a cabeça nova perde o embalo e cai até escavar de novo
			back.heading = Vector3.ZERO
		else:
			lone.append(back)
	if follow:
		if follow.follow == null:
			lone.append(follow)
		else:
			follow.set_role("tail")
	for o in lone:
		o.hurt(o.hp + o.defense * 2 + 10, Vector3.ZERO, 0.0)


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
# dmg já vem com a variância (Combat.vary); a defesa entra agora e o crítico dobra depois dela (wiki Damage), com 40% mais recuo.
func hurt(dmg: int, dir: Vector3, knockback: float, crit := false) -> int:
	if def.get("invulnerable", false):
		return 0
	if def.ai == "brain" and phase == 1:   # imune enquanto houver Creepers
		Fx.sparks(entities, position + Vector3.UP * tall * 0.5, Color(0.8, 0.8, 1.0), 4, dir)
		return 0
	var taken := maxi(1, dmg - ceili(defense / 2.0)) * (2 if crit else 1)
	if def.ai == "caster":   # golpe: cancela os tiros e adia o teleporte
		timer = 4.17
		shots = 0
	hp -= taken
	flash = FLASH_TIME
	Sfx.play(entities, "die" if hp <= 0 else "hit", position)
	entities.spawn_text(position + Vector3.UP * (tall + 0.3), str(taken), Color("#ff5a14") if crit else Color("#ffa050"), crit)
	var blood := Color(def.get("blood", def.color))
	var away := Vector3(dir.x, 0.4, dir.z).normalized()
	Fx.blood(entities, position + Vector3.UP * tall * 0.55, blood, 8, away)
	Fx.sparks(entities, position + Vector3.UP * tall * 0.55, Color(1, 0.95, 0.75), 3, away)
	var kb: float = knockback * (Combat.CRIT_KNOCKBACK if crit else 1.0) * (1.0 - def.get("kb_resist", 0.0))
	if kb > 0:
		var flat := Vector3(dir.x, 0, dir.z).normalized()
		velocity = flat * kb + Vector3.UP * (3.0 if def.ai != "fly" else 0.0)
		stun = 0.25
	if hp <= 0:
		Fx.puff(entities, position + Vector3.UP * tall * 0.5, blood, 12 if not def.get("boss") else 40)
		if def.ai == "worm":
			split_worm()
		if def.ai == "skeletron":   # matar a cabeça acaba a luta: as mãos somem
			for o in entities.enemies.duplicate():
				if o != self and o.def.get("group") == def.group:
					entities.remove_enemy(o)
		entities.drop_pickups(def, position + Vector3.UP * 0.3)
		if def.ai == "eye_of_cthulhu":
			entities.world.eoc_down = true
		if def.get("boss") and (not def.has("group") or entities.group_count(def.group) <= 1):
			entities.boss_hearts(position)   # o chefe inteiro caiu (o último segmento, se for grupo)
		if def.has("group") and entities.group_count(def.group) <= 1:   # o último segmento solta o prêmio do chefe
			entities.boss_down(def.group)
			var chosen := {}   # também aqui "pick" sorteia um só de cada grupo (item "" = nada)
			for entry in entities.final_drops(def.group):
				var d: Dictionary = entry
				if d.has("pick"):
					if chosen.has(d.pick):
						continue
					var group: Array = entities.final_drops(def.group).filter(func(x): return x.get("pick") == d.pick)
					d = group[rng.randi() % group.size()]
					chosen[d.pick] = true
				if d.item != "" and rng.randf() < d.chance:
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
