extends RefCounted
# Receitas dos modelos de inimigos/chefes (uma função por modelo → BbRig). Regras (docs/VOXEL_STYLE.md): 1 texel do sprite = 1 voxel (modelos
# grandes usam `k` texels por célula), cores da paleta do sprite da wiki (1 tom de luz e 1 de sombra por cor; o AO do mesher faz o resto),
# frente = y menor (-Z no jogo), ossos e clipes com os nomes que enemy_model.gd espera. Para conferir: tests/model_preview.gd -- enemy:nome

static func all() -> Dictionary:
	return {
		"eye_of_cthulhu": eye_of_cthulhu,
		"demon_eye": func(): return small_eye(9, 0x3a1a6a, 4),
		"servant_of_cthulhu": func(): return small_eye(6, 0x25102e, 3, true),
		"cave_bat": func(): return bat([0x177fba, 0x006299, 0x004166, 0x002e4a]),
		"ice_bat": func(): return bat([0xaff2f3, 0x51a4af, 0x336e81, 0x254b5a]),
		"jungle_bat": func(): return bat([0xba7318, 0x9a5700, 0x663a00, 0x402400]),
		"hellbat": func(): return bat([0xfb4f03, 0xc21604, 0x860704, 0x450400]),
	}


# ---- utilidades ----

# Linha de células conectada por faces (nunca só por quina), com `w` células de espessura.
static func line(m: VoxModel, a: Vector3, b: Vector3, col: int, w := 1) -> void:
	var prev := Vector3i(a.round())
	m.box(prev, prev + Vector3i.ONE * (w - 1), col)
	var n := int(maxf(1.0, maxf(absf(b.x - a.x), maxf(absf(b.y - a.y), absf(b.z - a.z)))))
	for i in range(1, n + 1):
		var c := Vector3i((a + (b - a) * float(i) / n).round())
		while prev != c:
			var d := c - prev
			var ax := 0 if absi(d.x) >= absi(d.y) and absi(d.x) >= absi(d.z) else (1 if absi(d.y) >= absi(d.z) else 2)
			prev[ax] += signi(d[ax])
			m.box(prev, prev + Vector3i.ONE * (w - 1), col)


# Veias: passeios aleatórios sobre a esfera (chave = longitude e latitude em células da casca).
static func veins(seed: int, R: float, n: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var set := {}
	for i in n:
		var lon := rng.randf_range(-PI, PI)
		var lat := rng.randf_range(-1.0, 1.2)
		var dir := rng.randf() * TAU
		for s in rng.randi_range(8, 22):
			set[Vector2i(roundi(lon * R * cos(lat)), roundi(lat * R))] = true
			dir += rng.randf_range(-0.7, 0.7)
			lat = clampf(lat + sin(dir) / R, -1.3, 1.3)
			lon += cos(dir) / (R * cos(lat))
	return set


# Cor do globo ocular: branco com veias vermelhas, carne vermelha nas costas e no topo (`flesh`), 3 tons pela luz (alto-esquerda-frente).
static func eyeball(R: float, vein: Dictionary, flesh: bool) -> Callable:
	var light := Vector3(0.4, -0.5, 0.75).normalized()
	return func(p: Vector3i) -> int:
		var n := Vector3(p).normalized()
		var key := Vector2i(roundi(atan2(n.x, -n.y) * R * cos(asin(clampf(n.z, -1, 1)))), roundi(asin(clampf(n.z, -1, 1)) * R))
		var lit := n.dot(light)
		var t := 0 if lit > 0.35 else (1 if lit > -0.25 else 2)
		if flesh and (n.z > 0.74 or n.y > 0.72):
			return [0xc42a2a, 0xa81f1f, 0x7e1414][t] if not vein.has(key) else [0x8a1414, 0x701010, 0x560c0c][t]
		if vein.has(key):
			return [0xd02020, 0xb01818, 0x8a1010][t]
		return [0xf4f4f4, 0xd8d8d8, 0xb8b8b8][t]


# ---- Olho de Cthulhu (fase 1: íris; fase 2: boca com dentes, as duas em grupos que o set_phase alterna) ----
static func eye_of_cthulhu() -> BbRig:
	var rig := BbRig.new()
	rig.k = 3
	var R := 16.0
	var c := Vector3(0.5, 0.5, 0.5)
	rig.center = c
	rig.bone("body", "", c).ellipsoid(Vector3.ZERO, Vector3.ONE * R, eyeball(R, veins(7, R, 40), true), 2)
	var iris := rig.bone("iris", "body", c)   # azul com o miolo oliva e a pupila preta, saindo da frente
	iris.ellipsoid(Vector3(0, -R + 1, 0), Vector3(6, 2, 6), 0x3a4aa8)
	iris.ellipsoid(Vector3(0, -R, 0), Vector3(4, 2, 4), 0x6a6a20)
	iris.ellipsoid(Vector3(0, -R - 1, 0), Vector3(2, 2, 2), 0x151515)
	var mouth := rig.bone("mouth", "body", c)
	mouth.ellipsoid(Vector3(0, -R + 2, 0), Vector3(10, 3, 9), 0x3a0810)
	for i in 14:   # dentes em volta da borda, para dentro
		var a := TAU * i / 14.0
		var rim := Vector3(cos(a) * 10, -R - 1, sin(a) * 9)
		line(mouth, rim, rim * Vector3(0.45, 1, 0.45) + Vector3(0, 0, 0), 0xe8dcb0, 1)
	var legs := 7
	for i in legs:   # tendões saindo do alto e das costas
		var a := lerpf(-1.1, 1.1, i / float(legs - 1))
		var dir := Vector3(sin(a) * 0.6, 0.45, cos(a) * 0.9).normalized()
		var root := dir * (R - 1)
		var mid := root + dir * 7 + Vector3(sin(a * 2.0), 0, 0)
		var tip := mid + dir * 7 + Vector3(0, 0, 1)
		line(rig.bone("t%da" % i, "body", c + root), root, mid, 0xc42a2a)
		line(rig.bone("t%db" % i, "t%da" % i, c + mid), mid, tip, 0x8a1414)
	rig.anim("idle", 2.0)
	rig.sway("idle", "body", "pos", Vector3(0, 0.8, 0))
	rig.anim("move", 1.0)
	rig.sway("move", "body", "pos", Vector3(0, 0.6, 0))
	rig.sway("move", "body", "rot", Vector3(4, 0, 3), 0.0, 1, Vector3(-6, 0, 0))
	rig.anim("attack", 0.5)
	rig.sway("attack", "body", "pos", Vector3(0, 0.4, 0), 0.0, 2)
	rig.track("attack", "body", "scl", [[0.0, Vector3(1.08, 1.08, 0.9)], [0.5, Vector3(1.08, 1.08, 0.9)]])
	rig.anim("phase2", 0.8)
	rig.sway("phase2", "body", "rot", Vector3(0, 0, 3))
	rig.sway("phase2", "mouth", "scl", Vector3(0.06, 0.0, 0.06), 0.0, 1, Vector3.ONE)
	for i in legs:
		var f := i / float(legs)
		rig.sway("idle", "t%da" % i, "rot", Vector3(0, 0, 12), f)
		rig.sway("idle", "t%db" % i, "rot", Vector3(0, 0, 22), f + 0.15)
		rig.sway("move", "t%da" % i, "rot", Vector3(0, 0, 14), f, 1, Vector3(28, 0, 0))
		rig.sway("move", "t%db" % i, "rot", Vector3(0, 0, 26), f + 0.15, 1, Vector3(20, 0, 0))
		rig.sway("attack", "t%da" % i, "rot", Vector3(0, 0, 10), f, 2, Vector3(40, 0, 0))
		rig.sway("attack", "t%db" % i, "rot", Vector3(0, 0, 16), f + 0.1, 2, Vector3(30, 0, 0))
		rig.sway("phase2", "t%da" % i, "rot", Vector3(0, 0, 26), f, 1, Vector3(12, 0, 0))
		rig.sway("phase2", "t%db" % i, "rot", Vector3(0, 0, 34), f + 0.15, 1, Vector3(10, 0, 0))
	rig.std_hurt("body", 0.3)
	rig.std_death("body", 1.2, 540.0)
	return rig


# ---- Olho pequeno (Demon Eye, Servant of Cthulhu): globo com íris na frente e nervos vermelhos atrás ----
static func small_eye(R: int, iris_col: int, iris_r: int, bloody := false) -> BbRig:
	var rig := BbRig.new()
	var c := Vector3(0.5, 0.5, R + 0.5)
	rig.center = Vector3(0.5, 0.5, 0)   # pés na origem (o inimigo inteiro gira para o jogador)
	var ball := eyeball(R, veins(R, R, 14 if bloody else 5), false)
	rig.bone("body", "", c).ellipsoid(Vector3(0, 0, R), Vector3.ONE * R, func(p: Vector3i): return ball.call(p - Vector3i(0, 0, R)))
	var iris := rig.bone("iris", "body", c)
	iris.ellipsoid(Vector3(0, -R + 1, R), Vector3(iris_r, 1, iris_r), iris_col)
	iris.ellipsoid(Vector3(0, -R, R), Vector3(iris_r - 2, 1, iris_r - 2), 0x0c0c0c)
	var strands := 3
	for i in strands:
		var a := lerpf(-0.8, 0.8, i / float(strands - 1))
		var root := Vector3(sin(a) * R * 0.4, R - 1, R + cos(a) * R * 0.3)
		var tip := root + Vector3(sin(a) * 3, R * 0.9, -1)
		line(rig.bone("n%d" % i, "body", root), root, tip, 0xb52525 if i != 1 else 0x9d2929)
	rig.anim("idle", 1.6)
	rig.sway("idle", "body", "pos", Vector3(0, 0.5, 0))
	rig.anim("move", 0.8)
	rig.sway("move", "body", "rot", Vector3(0, 0, 5))
	rig.anim("attack", 0.4)
	rig.sway("attack", "body", "rot", Vector3(0, 0, 8))
	rig.sway("attack", "body", "pos", Vector3(0, 0, 0.6), 0.0, 2)
	for i in strands:
		rig.sway("idle", "n%d" % i, "rot", Vector3(0, 0, 14), i / 3.0)
		rig.sway("move", "n%d" % i, "rot", Vector3(0, 0, 24), i / 3.0, 1, Vector3(15, 0, 0))
		rig.sway("attack", "n%d" % i, "rot", Vector3(0, 0, 20), i / 3.0, 2, Vector3(25, 0, 0))
	rig.std_hurt("body", 0.2)
	rig.std_death("body", 0.5, 300.0)
	return rig


# ---- Morcego (Cave/Ice/Jungle/Hell): corpo pequeno, orelhas, duas asas de duas partes que batem ----
static func bat(pal: Array) -> BbRig:
	var rig := BbRig.new()
	rig.center = Vector3(0.5, 0.5, 0)
	var body := rig.bone("body", "", Vector3(0.5, 0.5, 6.5))
	body.ellipsoid(Vector3(0, 1, 6), Vector3(3, 3, 3), pal[1])
	body.ellipsoid(Vector3(0, -2, 7), Vector3(2, 2, 2), pal[0])
	body.box(Vector3i(-2, -2, 10), Vector3i(-2, -2, 11), pal[2])
	body.box(Vector3i(2, -2, 10), Vector3i(2, -2, 11), pal[2])
	body.box(Vector3i(-1, -4, 7), Vector3i(-1, -4, 7), 0xffffff)   # olhos e presas
	body.box(Vector3i(1, -4, 7), Vector3i(1, -4, 7), 0xffffff)
	body.box(Vector3i(-1, -4, 5), Vector3i(-1, -4, 5), 0xf4f4f4)
	body.box(Vector3i(1, -4, 5), Vector3i(1, -4, 5), 0xf4f4f4)
	for side in [1, -1]:
		var tag := "a" if side == 1 else "b"
		var inner := rig.bone("w1" + tag, "body", Vector3(side * 2 + 0.5, 0.5, 8.5))
		var outer := rig.bone("w2" + tag, "w1" + tag, Vector3(side * 7 + 0.5, 0.5, 8.5))
		for x in range(2, 7):   # membrana interna: larga, com o braço mais escuro na frente
			for y in range(-3, 5):
				inner.put(Vector3i(side * x, y, 8), pal[1] if y > -3 else pal[2])
		for x in range(7, 13):  # membrana externa: afina para a ponta; borda recortada
			var span := 4 - (x - 7) / 2
			for y in range(-span - 1, span + 2 - ((x + side) % 2)):
				outer.put(Vector3i(side * x, y, 8), pal[1] if y > -span else pal[2])
		outer.put(Vector3i(side * 12, -2, 8), pal[0])
	rig.anim("idle", 0.8)
	rig.anim("move", 0.5)
	rig.anim("attack", 0.4)
	for a in ["idle", "move", "attack"]:
		var amp: float = {"idle": 22.0, "move": 38.0, "attack": 45.0}[a]
		rig.sway(a, "body", "pos", Vector3(0, amp * 0.03, 0), 0.5)
		rig.sway(a, "w1a", "rot", Vector3(0, 0, -amp), 0.0, 1, Vector3(0, 0, -30))
		rig.sway(a, "w1b", "rot", Vector3(0, 0, amp), 0.0, 1, Vector3(0, 0, 30))
		rig.sway(a, "w2a", "rot", Vector3(0, 0, -amp * 0.8), 0.15, 1, Vector3(0, 0, -20))
		rig.sway(a, "w2b", "rot", Vector3(0, 0, amp * 0.8), 0.15, 1, Vector3(0, 0, 20))
	rig.std_hurt("body", 0.2)
	rig.std_death("body", 0.5, 240.0)
	return rig
