extends RefCounted
# Receitas dos modelos de inimigos/chefes (uma função por modelo → BbRig). Regras (docs/VOXEL_STYLE.md): 1 texel do sprite = 1 voxel (modelos
# grandes usam `k` texels por célula), cores da paleta do sprite da wiki (1 tom de luz e 1 de sombra por cor; o AO do mesher faz o resto),
# frente = y menor (-Z no jogo), ossos e clipes com os nomes que enemy_model.gd espera. Para conferir: tests/model_preview.gd -- enemy:nome

const BEE := {"head": [0xf0c830, 0xd8a820, 0xa87c10], "body": [0xf0c830, 0xd8a820, 0xa87c10], "abd": [0xf0c830, 0xd8a820, 0xa87c10],
	"stripe": [0x4a3a20, 0x3a2a14, 0x2a1c0c], "eye": 0x1a1030, "wing": 0xc8e0f0}
const HORNET := {"head": [0xd88aa0, 0xb86a88, 0x904868], "body": [0xc07088, 0xa05870, 0x784058], "abd": [0xf0b030, 0xd89020, 0xa06810],
	"stripe": [0xa06810, 0x8a5010, 0x6a3c08], "eye": 0x1a1030, "wing": 0xb8d0e8}
const QUEEN := {"head": [0xf4d238, 0xdcb020, 0xac8410], "body": [0xf4d238, 0xdcb020, 0xac8410], "abd": [0xf4d238, 0xdcb020, 0xac8410],
	"stripe": [0x4a3a78, 0x2a1a50, 0x1a1038], "eye": 0x2a1a50, "wing": 0xa8c8e8}
const IMP := {"skin": [0xe88a80, 0xd06a68, 0xa04a50], "horn": 0xe8e0d0, "eye": 0xf0c030, "wing": [0x8a7a80, 0x6a5a62], "doll": 0xe08030}
const FIRE := {"skin": [0xf08a78, 0xd66a5a, 0xa84a48], "horn": 0xf4e8d0, "eye": 0xfff060, "wing": [0x8a7a80, 0x6a5a62], "doll": 0xe08030}


static func all() -> Dictionary:
	return {
		"eye_of_cthulhu": eye_of_cthulhu,
		"demon_eye": func(): return small_eye(9, 0x3a1a6a, 4),
		"servant_of_cthulhu": func(): return small_eye(6, 0x25102e, 3, true),
		"cave_bat": func(): return bat([0x177fba, 0x006299, 0x004166, 0x002e4a]),
		"ice_bat": func(): return bat([0xaff2f3, 0x51a4af, 0x336e81, 0x254b5a]),
		"jungle_bat": func(): return bat([0xba7318, 0x9a5700, 0x663a00, 0x402400]),
		"hellbat": func(): return bat([0xfb4f03, 0xc21604, 0x860704, 0x450400]),
		"skeletron": func(): return skull(13, 3, true),
		"cursed_skull": func(): return skull(10, 1, false),
		"skeletron_hand": skeleton_hand,
		"wall_of_flesh": wall_of_flesh,
		"brain_of_cthulhu": brain,
		"creeper": func(): return small_eye(9, 0x1a0a2a, 4, true),
		"the_hungry": hungry,
		"bee": func(): return bee(2, 1, BEE),
		"hornet": func(): return bee(4, 1, HORNET),
		"queen_bee": func(): return bee(4, 3, QUEEN),
		"demon": func(): return imp(IMP, 0, true, false, false),
		"voodoo_demon": func(): return imp(IMP, 10, true, true, false),
		"fire_imp": func(): return imp(FIRE, 4, false, false, true),
		"eater_of_souls": func(): return hanging(false),
		"crimera": func(): return hanging(true),
		"blood_crawler": func(): return spider([0x8a4a3a, 0x6a3a30, 0x4a2822], 6, 0xc02020),
		"antlion_charger": antlion,
		"vulture": vulture,
		"unicorn": unicorn,
		"snow_flinx": snow_flinx,
		"meteor_head": meteor_head,
		"pixie": pixie,
		"face_monster": face_monster,
		"king_slime": king_slime,
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


# ---- Caveira (Cursed Skull R=10; Skeletron R=13 k=3, com brilho nas órbitas): crânio, mandíbula que bate e dentes ----
static func tone(n: Vector3, cols: Array) -> int:   # 3 tons pela luz (alto-esquerda-frente): luz, meio, sombra
	var lit := n.normalized().dot(Vector3(0.4, -0.5, 0.75).normalized())
	return cols[0 if lit > 0.35 else (1 if lit > -0.25 else 2)]


static func skull(R: int, k: int, big: bool) -> BbRig:
	var rig := BbRig.new()
	rig.k = k
	rig.center = Vector3(0.5, 0.5, 0)
	var jaw_h := roundi(R * 0.45)
	var cz := jaw_h + R * 0.88
	var c := Vector3(0, 0, cz)
	var bone := [0xe0dcc8, 0xc4bea4, 0x9c967c]
	var body := rig.bone("body", "", Vector3(0.5, 0.5, cz + 0.5))
	var r := Vector3(R, R * 0.9, R * 0.88)
	body.ellipsoid(c, r, func(p: Vector3i): return tone((Vector3(p) - c) / r, bone))
	for side in [-1, 1]:
		var at := Vector3(side * R * 0.42, -R * 0.78, cz + R * 0.1)
		body.ellipsoid(at, Vector3(R * 0.26, R * 0.2, R * 0.28), 0x1a1410)
		if big:   # brilho vermelho dentro da órbita
			body.ellipsoid(at + Vector3(0, -1, 0), Vector3(R * 0.1, R * 0.1, R * 0.1), 0xff3020)
	body.box(Vector3i(-1, roundi(-R * 0.9), roundi(cz - R * 0.3)), Vector3i(0, roundi(-R * 0.82), roundi(cz - R * 0.1)), 0x1a1410)   # nariz
	for x in range(-roundi(R * 0.4) + 1, roundi(R * 0.4) + 1, 2):   # dentes de cima (entre os de baixo)
		body.box(Vector3i(x, roundi(-R * 0.62), jaw_h - 2), Vector3i(x, roundi(-R * 0.62), jaw_h), 0xf4f0e0)
	var jaw := rig.bone("jaw", "body", Vector3(0.5, R * 0.45, jaw_h + 0.5))
	for z in range(0, jaw_h - 1):   # mandíbula afunilada para o queixo
		var w := roundi(R * 0.44 * (0.55 + 0.45 * z / maxf(1.0, jaw_h - 2)))
		jaw.box(Vector3i(-w, roundi(-R * 0.62) + (jaw_h - 2 - z) / 3, z), Vector3i(w, roundi(R * 0.2), z), 0xc4bea4 if z > 0 else 0x9c967c)
	for x in range(-roundi(R * 0.4), roundi(R * 0.4) + 1, 2):
		jaw.box(Vector3i(x, roundi(-R * 0.62), jaw_h - 1), Vector3i(x, roundi(-R * 0.62), jaw_h), 0xf4f0e0)
	for a in ["idle", "move", "attack"]:
		var f: Array = {"idle": [0.0, 5.0, 2.0], "move": [0.0, 6.0, 0.8], "attack": [-6.0, 10.0, 0.5]}[a]
		rig.anim(a, f[2])
		rig.sway(a, "jaw", "rot", Vector3(f[1], 0, 0), 0.0, 1, Vector3(-f[1] - 2 + f[0], 0, 0))
		rig.sway(a, "body", "pos", Vector3(0, 0.6 * (1 if a == "idle" else 2), 0), 0.25)
		rig.sway(a, "body", "rot", Vector3(0, 0, 0 if a == "idle" else 6))
	rig.std_hurt("body", 0.25)
	rig.std_death("body", 0.8, 360.0)
	return rig


# ---- Mão de osso do Skeletron (k=2): antebraço, palma, quatro dedos de 2 falanges e polegar; fecha ao atacar ----
static func skeleton_hand() -> BbRig:
	var rig := BbRig.new()
	rig.k = 2
	rig.center = Vector3(0.5, 0.5, 0)
	var bone := [0xd8d4c0, 0xbab69f, 0x96927c]
	var palm := rig.bone("hand", "", Vector3(0.5, 0.5, 6.5))
	palm.box(Vector3i(-2, -2, 0), Vector3i(1, 1, 5), bone[2])
	palm.box(Vector3i(-5, -2, 6), Vector3i(4, 1, 12), bone[0])
	palm.box(Vector3i(-5, -2, 6), Vector3i(4, -2, 12), bone[1])
	var lens := [5, 6, 6, 5]
	for i in 4:
		var x := -5 + i * 3
		var a := rig.bone("f%da" % i, "hand", Vector3(x + 1, 0.5, 13))
		a.box(Vector3i(x, -1, 13), Vector3i(x + 1, 0, 12 + lens[i]), bone[0])
		var b := rig.bone("f%db" % i, "f%da" % i, Vector3(x + 1, 0.5, 13 + lens[i]))
		b.box(Vector3i(x, -1, 13 + lens[i]), Vector3i(x + 1, 0, 12 + lens[i] * 2 - 1), bone[1])
	var th := rig.bone("th", "hand", Vector3(5, 0.5, 8))
	line(th, Vector3(5, -1, 8), Vector3(9, -1, 12), bone[0], 2)
	rig.anim("idle", 2.4)
	rig.anim("move", 1.2)
	rig.anim("attack", 0.6)
	for a in ["idle", "move", "attack"]:
		var amp: float = {"idle": 6.0, "move": 10.0, "attack": 25.0}[a]
		var base: float = {"idle": -8.0, "move": -14.0, "attack": -35.0}[a]
		for i in 4:
			rig.sway(a, "f%da" % i, "rot", Vector3(amp, 0, 0), i / 4.0, 1 if a != "attack" else 2, Vector3(base, 0, 0))
			rig.sway(a, "f%db" % i, "rot", Vector3(amp, 0, 0), i / 4.0 + 0.15, 1 if a != "attack" else 2, Vector3(base * 1.2, 0, 0))
		rig.sway(a, "th", "rot", Vector3(0, 0, amp * 0.6), 0.0, 1, Vector3(0, 0, -amp))
		rig.sway(a, "hand", "pos", Vector3(0, 0.5, 0.4), 0.3)
	rig.std_hurt("hand", 0.25)
	rig.std_death("hand", 0.7, 300.0)
	return rig


# ---- Wall of Flesh (k=8, 12x24 blocos): parede de carne com lóbulos e veias, dois olhos em cima, boca com dentes embaixo; frente = -y ----
static func wall_of_flesh() -> BbRig:
	var rig := BbRig.new()
	rig.k = 8
	rig.center = Vector3(0.5, 0.5, 0)
	var flesh := [0xd05a6a, 0xb83a4a, 0x8a2a3a]
	var body := rig.bone("body", "", Vector3(0.5, 0.5, 0))
	body.box(Vector3i(-20, -4, 0), Vector3i(19, 4, 79), 0xb83a4a)
	var rng := RandomNumberGenerator.new()
	rng.seed = 113
	for i in 18:   # lóbulos na frente
		var at := Vector3(rng.randf_range(-17, 17), -5, rng.randf_range(4, 76))
		var rr := Vector3(rng.randf_range(3, 6), 2.5, rng.randf_range(3, 6))
		body.ellipsoid(at, rr, func(p: Vector3i): return tone((Vector3(p) - at) / rr, flesh))
	for i in 14:   # lóbulos nas costas e nas bordas (a carne tem volume, não é uma chapa)
		var at := Vector3(rng.randf_range(-18, 18), 5, rng.randf_range(4, 76))
		var rr := Vector3(rng.randf_range(4, 7), 3, rng.randf_range(4, 7))
		body.ellipsoid(at, rr, func(p: Vector3i): return tone((Vector3(p) - at) / rr, [0xb83a4a, 0x9a3040, 0x8a2a3a]))
	for i in 9:   # veias escuras
		var x := rng.randf_range(-18, 18)
		var z0 := rng.randf_range(4, 40)
		line(body, Vector3(x, -8, z0), Vector3(x + rng.randf_range(-4, 4), -8, z0 + rng.randf_range(15, 32)), 0x5a0a18)
	var eyes := rig.bone("eyes", "body", Vector3(0.5, -5, 58))
	for side in [-1, 1]:
		var at := Vector3(side * 10, -6, 58)
		eyes.ellipsoid(at, Vector3(6, 4, 6), func(p: Vector3i): return tone((Vector3(p) - at) / Vector3(6, 4, 6), [0xf4f4f4, 0xd8d8d8, 0xb8b8b8]))
		eyes.ellipsoid(at + Vector3(0, -3, 0), Vector3(3, 1, 3), 0xb01820)
		eyes.ellipsoid(at + Vector3(0, -4, 0), Vector3(1.5, 1, 1.5), 0x151515)
	var mouth := rig.bone("mouth", "body", Vector3(0.5, -6, 23))
	mouth.box(Vector3i(-15, -8, 18), Vector3i(14, -5, 27), 0x3a0810)
	for x in range(-15, 15, 2):
		mouth.box(Vector3i(x, -9, 25), Vector3i(x, -9, 27), 0xf4ecd8)
		mouth.box(Vector3i(x + 1, -9, 18), Vector3i(x + 1, -9, 20), 0xf4ecd8)
	for a in ["idle", "move", "attack"]:
		var T: float = {"idle": 3.0, "move": 1.6, "attack": 0.8}[a]
		rig.anim(a, T)
		rig.sway(a, "body", "scl", Vector3(0.01, 0.0, 0.0), 0.0, 1, Vector3.ONE)
		rig.sway(a, "body", "scl", Vector3(0.012, 0.07, 0.006), 0.0, 1, Vector3.ONE)
		rig.sway(a, "mouth", "scl", Vector3(0, 0.35 if a == "attack" else 0.06, 0), 0.0, 2 if a == "attack" else 1, Vector3.ONE)
		rig.sway(a, "eyes", "scl", Vector3(0.05, 0.05, 0.05), 0.2, 1, Vector3.ONE)
	rig.std_hurt("body", 0.25)
	rig.std_death("body", 1.6, 0.0)
	return rig


# ---- Brain of Cthulhu (k=3): cérebro rosa com dobras, dois olhos na frente e tentáculos embaixo ----
static func brain() -> BbRig:
	var rig := BbRig.new()
	rig.k = 3
	rig.center = Vector3(0.5, 0.5, 0)
	var pink := [0xe88a98, 0xd86a78, 0xb04858]
	var c := Vector3(0, 0, 17)
	var r := Vector3(13, 11, 10)
	var body := rig.bone("body", "", Vector3(0.5, 0.5, 17.5))
	body.ellipsoid(c, r, func(p: Vector3i):
		var d := Vector3(p) - c
		var f := sin(d.x * 0.9 + sin(d.z * 0.7) * 1.5) + sin(d.y * 0.8 + d.x * 0.3)
		if f > 1.55 or (absf(d.x) < 0.8 and d.z > 1):
			return 0x8a3040
		return tone(d / r, pink))
	var eyes := rig.bone("eyes", "body", Vector3(0.5, -10, 15.5))
	for side in [-1, 1]:
		var at := Vector3(side * 5, -9, 15)
		eyes.ellipsoid(at, Vector3(3, 2, 3), 0xf4f4f4)
		eyes.ellipsoid(at + Vector3(0, -1, 0), Vector3(1.5, 1, 1.5), 0xb01820)
	var n := 6
	for i in n:
		var a := TAU * i / n
		var root := Vector3(cos(a) * 8, sin(a) * 7, 9)
		var mid := root + Vector3(cos(a) * 2, sin(a) * 2, -5)
		var tip := mid + Vector3(cos(a), sin(a), -4)
		line(rig.bone("t%da" % i, "body", root + Vector3(0.5, 0.5, 0.5)), root, mid, 0xb04858, 2)
		line(rig.bone("t%db" % i, "t%da" % i, mid + Vector3(0.5, 0.5, 0.5)), mid, tip, 0x8a3040, 2)
	for a in ["idle", "move", "attack"]:
		var T: float = {"idle": 2.0, "move": 1.0, "attack": 0.5}[a]
		var sw: float = {"idle": 12.0, "move": 20.0, "attack": 28.0}[a]
		rig.anim(a, T)
		rig.sway(a, "body", "pos", Vector3(0, 0.8, 0))
		rig.sway(a, "body", "scl", Vector3(0.02, 0.02, 0.03), 0.25, 1, Vector3.ONE)
		for i in n:
			rig.sway(a, "t%da" % i, "rot", Vector3(sw, 0, sw * 0.6), i / float(n))
			rig.sway(a, "t%db" % i, "rot", Vector3(sw * 1.3, 0, sw * 0.8), i / float(n) + 0.15)
	rig.std_hurt("body", 0.3)
	rig.std_death("body", 1.0, 360.0)
	return rig


# ---- The Hungry: bolha de carne com boca de dentes na frente e a veia que a prende ao Muro, atrás ----
static func hungry() -> BbRig:
	var rig := BbRig.new()
	rig.center = Vector3(0.5, 0.5, 0)
	var pink := [0xc06088, 0xa04068, 0x783050]
	var c := Vector3(0, 0, 12)
	var r := Vector3(11, 10, 11)
	var rng := RandomNumberGenerator.new()
	rng.seed = 271
	var lumps := []
	for i in 6:
		lumps.append(Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.2, 1), rng.randf_range(-0.6, 1)).normalized() * 9)
	var body := rig.bone("body", "", Vector3(0.5, 0.5, 12.5))
	body.ellipsoid(c, r, func(p: Vector3i): return tone((Vector3(p) - c) / r, pink))
	for l in lumps:
		body.ellipsoid(c + l, Vector3(3, 3, 3), func(p: Vector3i): return tone((Vector3(p) - c - l), [0xd890a8, 0xc06088, 0xa04068]))
	var mouth := rig.bone("mouth", "body", Vector3(0.5, -9, 12.5))
	mouth.ellipsoid(Vector3(0, -9, 12), Vector3(7, 2, 4), 0x2a0610)
	for x in range(-6, 7, 2):
		mouth.box(Vector3i(x, -12, 14), Vector3i(x, -11, 15), 0xf0e4d0)
		mouth.box(Vector3i(x + 1, -12, 9), Vector3i(x + 1, -11, 10), 0xf0e4d0)
	var vein := rig.bone("vein", "body", Vector3(0.5, 10, 12.5))
	line(vein, Vector3(0, 10, 12), Vector3(0, 24, 13), 0xb01820, 2)
	for a in ["idle", "move", "attack"]:
		var T: float = {"idle": 1.6, "move": 0.9, "attack": 0.5}[a]
		rig.anim(a, T)
		rig.sway(a, "body", "pos", Vector3(0, 0.6, 0))
		rig.sway(a, "body", "scl", Vector3(0.03, 0.03, 0.04), 0.25, 1, Vector3.ONE)
		rig.sway(a, "mouth", "scl", Vector3(0, 0.45 if a == "attack" else 0.12, 0), 0.0, 2 if a == "attack" else 1, Vector3.ONE)
		rig.sway(a, "vein", "rot", Vector3(0, 12, 0))
	rig.std_hurt("body", 0.2)
	rig.std_death("body", 0.6, 300.0)
	return rig


# ---- Abelha (Bee u=2, Hornet u=4, Queen Bee u=6 k=3): cabeça, tórax, abdômen listrado com ferrão, antenas e asas que zumbem ----
static func bee(u: int, k: int, pal: Dictionary) -> BbRig:
	var rig := BbRig.new()
	rig.k = k
	rig.center = Vector3(0.5, 0.5, 0)
	var zc := u * 3
	var body := rig.bone("body", "", Vector3(0.5, 0.5, zc + 0.5))
	var th := Vector3(0, 0, zc)
	var tr := Vector3(1.3 * u, 1.3 * u, 1.2 * u)
	body.ellipsoid(th, tr, func(p: Vector3i): return tone((Vector3(p) - th) / tr, pal.body))
	var hc := Vector3(0, -2.1 * u, zc - 0.1 * u)
	var hr := Vector3(0.95 * u, 0.9 * u, 0.95 * u)
	body.ellipsoid(hc, hr, func(p: Vector3i): return tone((Vector3(p) - hc) / hr, pal.head))
	for side in [-1, 1]:
		body.ellipsoid(hc + Vector3(side * 0.55 * u, -0.55 * u, 0.2 * u), Vector3(0.4 * u, 0.35 * u, 0.5 * u), pal.eye)
	var ac := Vector3(0, 3.0 * u, zc - 0.1 * u)
	var ar := Vector3(1.15 * u, 1.9 * u, 1.05 * u)
	body.ellipsoid(ac, ar, func(p: Vector3i):
		var band := int(floorf((p.y - ac.y) / (0.75 * u))) % 2 != 0
		return tone((Vector3(p) - ac) / ar, pal.stripe if band else pal.abd))
	line(body, Vector3(0, ac.y + ar.y, ac.z - 0.2 * u), Vector3(0, ac.y + ar.y + 1.6 * u, ac.z - 0.5 * u), 0x2a1a1a, maxi(1, u / 3))
	for i in 3:   # pernas
		var y := (i - 1) * 0.8 * u
		for side in [-1, 1]:
			line(body, Vector3(side * 0.7 * u, y, zc - u), Vector3(side * 1.2 * u, y - 0.3 * u, zc - 2.1 * u), 0x2a1a10)
	var ant := rig.bone("ant", "body", Vector3(0.5, hc.y, hc.z + 0.9 * u))
	for side in [-1, 1]:
		line(ant, hc + Vector3(side * 0.4 * u, -0.4 * u, 0.8 * u), hc + Vector3(side * 0.8 * u, -1.6 * u, 2.0 * u), 0x2a1a50)
	for side in [1, -1]:
		var tag := "a" if side == 1 else "b"
		var at := Vector3(side * 0.8 * u + 0.5, 0.5, zc + 1.2 * u + 0.5)
		var wing := rig.bone("w" + tag, "body", at)
		for x in range(0, roundi(2.6 * u) + 1):
			for y in range(-roundi(1.2 * u), roundi(1.2 * u) + 1):
				if pow(x / (2.6 * u + 0.5), 2) + pow(y / (1.2 * u + 0.5), 2) <= 1.0:
					wing.put(Vector3i(side * (x + roundi(0.8 * u)), y, zc + roundi(1.2 * u)), pal.wing if (x + y) % 5 != 0 else 0xe8f4ff)
	var T := 0.2
	for a in ["idle", "move", "attack"]:
		var amp: float = {"idle": 30.0, "move": 38.0, "attack": 45.0}[a]
		rig.anim(a, T)
		rig.sway(a, "wa", "rot", Vector3(0, 0, -amp), 0.0, 1, Vector3(0, 0, -30))
		rig.sway(a, "wb", "rot", Vector3(0, 0, amp), 0.0, 1, Vector3(0, 0, 30))
		rig.sway(a, "body", "pos", Vector3(0, 0.3, 0), 0.0, 1)
		rig.sway(a, "ant", "rot", Vector3(8, 0, 0))
	rig.std_hurt("body", 0.2)
	rig.std_death("body", 0.5, 300.0)
	return rig


# ---- Diabinho (Demon, Voodoo Demon: com asas; Fire Imp: de pé, com cauda): cabeça com chifres, braços longos, pernas finas ----
static func imp(pal: Dictionary, z0: int, wings: bool, doll: bool, tail: bool) -> BbRig:
	var rig := BbRig.new()
	rig.center = Vector3(0.5, 0.5, 0)
	var tc := Vector3(0, 0, 14 + z0)
	var tr := Vector3(4, 3, 5)
	var body := rig.bone("body", "", Vector3(0.5, 0.5, 14.5 + z0))
	body.ellipsoid(tc, tr, func(p: Vector3i): return tone((Vector3(p) - tc) / tr, pal.skin))
	var hc := Vector3(0, -1, 21 + z0)
	var hr := Vector3(3.5, 3, 3.5)
	body.ellipsoid(hc, hr, func(p: Vector3i): return tone((Vector3(p) - hc) / hr, pal.skin))
	for side in [-1, 1]:
		line(body, Vector3(side * 3, -1, 23 + z0), Vector3(side * 5, -1, 26 + z0), pal.horn, 1)
		body.put(Vector3i(side * 2, -4, 21 + z0), pal.eye)
	body.box(Vector3i(-1, -4, 19 + z0), Vector3i(1, -4, 19 + z0), 0x3a1018)
	for side in [1, -1]:
		var tag := "a" if side == 1 else "b"
		var sh := Vector3(side * 5, 0, 16 + z0)
		var el := sh + Vector3(side * 3, -1, -5)
		var hand := el + Vector3(side, -2, -5)
		line(rig.bone("arm1" + tag, "body", sh + Vector3(0.5, 0.5, 0.5)), sh, el, pal.skin[1], 2)
		var low := rig.bone("arm2" + tag, "arm1" + tag, el + Vector3(0.5, 0.5, 0.5))
		line(low, el, hand, pal.skin[2], 2)
		low.box(Vector3i(roundi(hand.x) - 1, roundi(hand.y) - 1, roundi(hand.z) - 2), Vector3i(roundi(hand.x) + 1, roundi(hand.y), roundi(hand.z) - 1), pal.horn)   # garras
		if doll and side == -1:   # a boneca pendurada pelo fio na mão
			var dl := rig.bone("doll", "arm2" + tag, hand + Vector3(0.5, 0.5, 0))
			line(dl, hand + Vector3(0, 0, -2), hand + Vector3(0, 0, -6), 0x6a4a30)
			dl.ellipsoid(hand + Vector3(0, 0, -9), Vector3(2, 1.5, 3), pal.doll)
		var hip := Vector3(side * 2, 0, 9 + z0)
		line(rig.bone("leg" + tag, "body", hip + Vector3(0.5, 0.5, 0.5)), hip, Vector3(side * 2, 0, 1), pal.skin[2], 2)
		if wings:
			var wing := rig.bone("wing" + tag, "body", Vector3(side * 4 + 0.5, 3.5, 17.5 + z0))
			for x in range(4, 18):
				var top := 18 + (x - 4) * 0.7
				var bot := 17.0 - (x - 4) * 0.8 - (1 if x % 3 == 0 else 0)
				for z in range(roundi(bot), roundi(top) + 1):
					wing.box(Vector3i(side * x, 3, z + z0), Vector3i(side * x, 4, z + z0), pal.wing[0] if z > bot + 1 else pal.wing[1])
			line(wing, Vector3(side * 4, 3, 18 + z0), Vector3(side * 17, 3, 28 + z0), pal.wing[1])
	if tail:
		var tb := rig.bone("tail", "body", Vector3(0.5, 3.5, 10.5 + z0))
		line(tb, Vector3(0, 3, 10 + z0), Vector3(0, 9, 5 + z0), pal.skin[1], 2)
		line(tb, Vector3(0, 9, 5 + z0), Vector3(0, 11, 11 + z0), pal.skin[2], 2)
	for a in ["idle", "move", "attack"]:
		var T: float = {"idle": 1.6, "move": 0.8, "attack": 0.5}[a]
		var amp: float = {"idle": 16.0, "move": 28.0, "attack": 40.0}[a]
		rig.anim(a, T)
		rig.sway(a, "body", "pos", Vector3(0, 0.8 if wings else 0.3, 0), 0.25)
		for s2 in ["a", "b"]:
			var sg := 1.0 if s2 == "a" else -1.0
			rig.sway(a, "arm1" + s2, "rot", Vector3(amp * 0.5, 0, 0), 0.0 if s2 == "a" else 0.5)
			rig.sway(a, "leg" + s2, "rot", Vector3(amp * 0.6, 0, 0), 0.0 if s2 == "a" else 0.5)
			if wings:
				rig.sway(a, "wing" + s2, "rot", Vector3(0, 0, -sg * amp * 1.4), 0.0, 1, Vector3(0, 0, -sg * 15))
		if tail:
			rig.sway(a, "tail", "rot", Vector3(0, 0, amp * 0.8))
	rig.std_hurt("body", 0.25)
	rig.std_death("body", 0.6, 300.0)
	return rig


# ---- Eater of Souls (cinza, boca verde, antenas) e Crimera (vermelha com espinhos): corpo alto, pernas penduradas ----
static func hanging(crim: bool) -> BbRig:
	var rig := BbRig.new()
	rig.center = Vector3(0.5, 0.5, 0)
	var c := Vector3(0, 0, 26)
	var r := Vector3(6, 6, 12) if crim else Vector3(8, 7, 11)
	var skin := [0xc04a40, 0xa03a34, 0x782a28] if crim else [0x8a7a82, 0x6a5a62, 0x4a3a42]
	var body := rig.bone("body", "", Vector3(0.5, 0.5, 26.5))
	body.ellipsoid(c, r, func(p: Vector3i): return tone((Vector3(p) - c) / r, skin))
	if crim:
		for i in 5:   # espinhos nas costas
			var z := 18 + i * 4
			line(body, Vector3(0, 5, z), Vector3(0, 10 - (i % 2) * 2, z + 3), 0x701810, 2)
		body.box(Vector3i(-2, -6, 18), Vector3i(2, -6, 20), 0x2a0808)
		for x in [-2, 0, 2]:
			body.put(Vector3i(x, -6, 20), 0xf0e4d0)
	else:
		body.ellipsoid(Vector3(0, -6, 21), Vector3(5, 2, 4), 0x90b830)
		body.ellipsoid(Vector3(0, -7, 21), Vector3(2, 1, 2), 0x2a3a10)
		for side in [-1, 1]:
			body.put(Vector3i(side * 3, -6, 28), 0xf0e060)
	var legs := 2 if crim else 4
	for i in legs:
		var side := 1 if i % 2 == 0 else -1
		var y := -2 if i < 2 else 3
		var x := (3 if crim else 4) * side
		var l := rig.bone("leg%d" % i, "body", Vector3(x + 0.5, y + 0.5, 15.5))
		if crim:
			line(l, Vector3(x, y, 15), Vector3(x + side, y, 2), 0xc02020, 3)
		else:
			line(l, Vector3(x, y, 15), Vector3(x + side * 3, y, 4), 0xb8a878, 1)
			line(l, Vector3(x + side * 3, y, 4), Vector3(x + side * 2, y, 1), 0x8a7a58, 1)
	if not crim:
		var ant := rig.bone("ant", "body", Vector3(0.5, 0.5, 36.5))
		for i in 4:
			var a := TAU * i / 4.0 + 0.5
			line(ant, Vector3(cos(a) * 3, sin(a) * 3, 36), Vector3(cos(a) * 6, sin(a) * 6, 44), 0x80a830)
	for a in ["idle", "move", "attack"]:
		var T: float = {"idle": 1.8, "move": 0.9, "attack": 0.5}[a]
		var amp: float = {"idle": 10.0, "move": 18.0, "attack": 28.0}[a]
		rig.anim(a, T)
		rig.sway(a, "body", "pos", Vector3(0, 0.8, 0))
		rig.sway(a, "body", "rot", Vector3(amp * 0.3, 0, amp * 0.3), 0.25)
		for i in legs:
			rig.sway(a, "leg%d" % i, "rot", Vector3(amp, 0, amp * 0.4), i / float(legs))
		if not crim:
			rig.sway(a, "ant", "rot", Vector3(amp * 0.5, 0, amp * 0.5), 0.3)
	rig.std_hurt("body", 0.25)
	rig.std_death("body", 0.6, 300.0)
	return rig


# ---- Aranha de chão (Blood Crawler): abdômen redondo, cefalotórax, 4 pares de pernas em dois ossos, olhos vermelhos ----
static func spider(pal: Array, R: int, eye: int) -> BbRig:
	var rig := BbRig.new()
	rig.center = Vector3(0.5, 0.5, 0)
	var zc := R * 0.9
	var body := rig.bone("body", "", Vector3(0.5, 0.5, zc + 0.5))
	var ab := Vector3(0, R * 0.9, zc)
	var abr := Vector3(R, R * 1.1, R * 0.8)
	body.ellipsoid(ab, abr, func(p: Vector3i): return tone((Vector3(p) - ab) / abr, pal))
	var ce := Vector3(0, -R * 0.7, zc)
	var cer := Vector3(R * 0.7, R * 0.7, R * 0.6)
	body.ellipsoid(ce, cer, func(p: Vector3i): return tone((Vector3(p) - ce) / cer, pal))
	for side in [-1, 1]:
		body.put(Vector3i(side * 2, roundi(ce.y - R * 0.7), roundi(zc + 1)), eye)
		body.put(Vector3i(side, roundi(ce.y - R * 0.7), roundi(zc + 2)), eye)
	for i in 8:
		var side := 1 if i % 2 == 0 else -1
		var y := -R * 0.9 + (i / 2) * R * 0.55
		var base := Vector3(side * R * 0.6, y, zc)
		var l1 := rig.bone("leg%da" % i, "body", base + Vector3(0.5, 0.5, 0.5))
		var knee := base + Vector3(side * R * 0.9, y * 0.1 - R * 0.2, R * 0.6)
		line(l1, base, knee, pal[1], 1)
		var l2 := rig.bone("leg%db" % i, "leg%da" % i, knee + Vector3(0.5, 0.5, 0.5))
		line(l2, knee, Vector3(side * R * 1.7, y * 1.1, 0), pal[2], 1)
	for a in ["idle", "move", "attack"]:
		var T: float = {"idle": 2.0, "move": 0.6, "attack": 0.4}[a]
		var amp: float = {"idle": 3.0, "move": 22.0, "attack": 28.0}[a]
		rig.anim(a, T)
		rig.sway(a, "body", "pos", Vector3(0, 0.3, 0))
		for i in 8:
			var ph := (i % 4) / 4.0 + (0.5 if i % 2 == 0 else 0.0)
			rig.sway(a, "leg%da" % i, "rot", Vector3(0, amp, amp * 0.4), ph)
			rig.sway(a, "leg%db" % i, "rot", Vector3(0, amp * 0.5, 0), ph + 0.2)
	rig.std_hurt("body", 0.2)
	rig.std_death("body", 0.6, 200.0)
	return rig


# ---- Antlion Charger: besouro alongado cor de ferrugem, mandíbulas grandes, seis pernas ----
static func antlion() -> BbRig:
	var rig := BbRig.new()
	rig.center = Vector3(0.5, 0.5, 0)
	var pal := [0xe0883a, 0xc06a2a, 0x8a4a1c]
	var body := rig.bone("body", "", Vector3(0.5, 0.5, 7.5))
	var bc := Vector3(0, 3, 7)
	var br := Vector3(5, 8, 4)
	body.ellipsoid(bc, br, func(p: Vector3i): return tone((Vector3(p) - bc) / br, pal if (int(p.y) / 3) % 2 == 0 else [0xc06a2a, 0xa05220, 0x7a3a14]))
	var hc := Vector3(0, -7, 8)
	var hr := Vector3(4, 3.5, 3.5)
	body.ellipsoid(hc, hr, func(p: Vector3i): return tone((Vector3(p) - hc) / hr, pal))
	for side in [-1, 1]:
		body.put(Vector3i(side * 2, -10, 9), 0xe01010)
	var jaw := rig.bone("jaw", "body", Vector3(0.5, -9.5, 7.5))
	for side in [-1, 1]:
		line(jaw, Vector3(side * 2, -10, 6), Vector3(side * 5, -15, 7), 0xe8d890, 1)
		line(jaw, Vector3(side * 5, -15, 7), Vector3(side * 2, -18, 8), 0xf4ecc0, 1)
	for i in 6:
		var side := 1 if i % 2 == 0 else -1
		var y := -3 + (i / 2) * 5
		var l := rig.bone("leg%d" % i, "body", Vector3(side * 4 + 0.5, y + 0.5, 6.5))
		line(l, Vector3(side * 4, y, 6), Vector3(side * 8, y, 4), 0x8a4a1c, 1)
		line(l, Vector3(side * 8, y, 4), Vector3(side * 9, y, 0), 0x6a3a14, 1)
	for a in ["idle", "move", "attack"]:
		var T: float = {"idle": 2.0, "move": 0.6, "attack": 0.4}[a]
		var amp: float = {"idle": 3.0, "move": 26.0, "attack": 30.0}[a]
		rig.anim(a, T)
		rig.sway(a, "body", "pos", Vector3(0, 0.3, 0))
		rig.sway(a, "jaw", "rot", Vector3(0, 0, 4 if a == "idle" else 14), 0.0, 1 if a != "attack" else 2)
		for i in 6:
			rig.sway(a, "leg%d" % i, "rot", Vector3(amp, 0, 0), (i / 2) / 3.0 + (0.5 if i % 2 == 0 else 0.0))
	rig.std_hurt("body", 0.2)
	rig.std_death("body", 0.6, 200.0)
	return rig


# ---- Vulture: corpo listrado, pescoço e cabeça nua laranja com bico roxo, asas largas de penas ----
static func vulture() -> BbRig:
	var rig := BbRig.new()
	rig.center = Vector3(0.5, 0.5, 0)
	var pal := [0xd8c8a0, 0xb09a6c, 0x7a6644]
	var body := rig.bone("body", "", Vector3(0.5, 0.5, 11.5))
	var bc := Vector3(0, 1, 11)
	var br := Vector3(5, 7, 5)
	body.ellipsoid(bc, br, func(p: Vector3i): return tone((Vector3(p) - bc) / br, pal))
	line(body, Vector3(0, -3, 13), Vector3(0, -6, 17), 0xd08040, 2)   # pescoço
	var hc := Vector3(0, -7, 18)
	var hr := Vector3(2.5, 2.5, 2.5)
	body.ellipsoid(hc, hr, func(p: Vector3i): return tone((Vector3(p) - hc) / hr, [0xe09850, 0xd08040, 0xa05c28]))
	line(body, Vector3(0, -9, 18), Vector3(0, -12, 17), 0xa040a0, 2)   # bico curvo
	body.put(Vector3i(0, -13, 16), 0xa040a0)
	for side in [-1, 1]:
		body.put(Vector3i(side * 2, -8, 19), 0x1a1010)
		line(body, Vector3(side * 2, 3, 6), Vector3(side * 2, 3, 1), 0xd08040, 1)   # pernas
	for i in 3:
		line(body, Vector3(i - 1, 7, 10), Vector3(i - 1, 14, 9 - abs(i - 1)), pal[2], 2)   # cauda
	for side in [1, -1]:
		var tag := "a" if side == 1 else "b"
		var inner := rig.bone("w1" + tag, "body", Vector3(side * 4 + 0.5, 1.5, 13.5))
		var outer := rig.bone("w2" + tag, "w1" + tag, Vector3(side * 11 + 0.5, 1.5, 13.5))
		for x in range(4, 11):
			for y in range(-3, 6):
				inner.put(Vector3i(side * x, y, 13), pal[1] if (x + y) % 3 else pal[0])
		for x in range(11, 19):
			var span := 4 - (x - 11) / 3
			for y in range(-span, span + 5 - (x % 2)):
				outer.put(Vector3i(side * x, y, 13), pal[2] if y > span else pal[1])
	for a in ["idle", "move", "attack"]:
		var T: float = {"idle": 1.0, "move": 0.6, "attack": 0.45}[a]
		var amp: float = {"idle": 20.0, "move": 32.0, "attack": 40.0}[a]
		rig.anim(a, T)
		rig.sway(a, "body", "pos", Vector3(0, amp * 0.03, 0), 0.5)
		rig.sway(a, "w1a", "rot", Vector3(0, 0, -amp), 0.0, 1, Vector3(0, 0, -20))
		rig.sway(a, "w1b", "rot", Vector3(0, 0, amp), 0.0, 1, Vector3(0, 0, 20))
		rig.sway(a, "w2a", "rot", Vector3(0, 0, -amp * 0.8), 0.15, 1, Vector3(0, 0, -12))
		rig.sway(a, "w2b", "rot", Vector3(0, 0, amp * 0.8), 0.15, 1, Vector3(0, 0, 12))
	rig.std_hurt("body", 0.2)
	rig.std_death("body", 0.5, 240.0)
	return rig


# ---- Unicorn: cavalo branco de crina e cauda rosas, chifre roxo, quatro pernas que trotam ----
static func unicorn() -> BbRig:
	var rig := BbRig.new()
	rig.center = Vector3(0.5, 0.5, 0)
	var pal := [0xf4f0f8, 0xd8d0e4, 0xaaa0bc]
	var body := rig.bone("body", "", Vector3(0.5, 0.5, 19.5))
	var bc := Vector3(0, 3, 20)
	var br := Vector3(5, 11, 6)
	body.ellipsoid(bc, br, func(p: Vector3i): return tone((Vector3(p) - bc) / br, pal))
	var neck := rig.bone("neck", "body", Vector3(0.5, -7.5, 23.5))
	line(neck, Vector3(0, -7, 22), Vector3(0, -11, 29), pal[1], 4)
	var hc := Vector3(0, -14, 30)
	var hr := Vector3(3, 5, 3)
	neck.ellipsoid(hc, hr, func(p: Vector3i): return tone((Vector3(p) - hc) / hr, pal))
	neck.put(Vector3i(2, -15, 31), 0xe01040)
	neck.put(Vector3i(-3, -15, 31), 0xe01040)
	line(neck, Vector3(0, -17, 34), Vector3(0, -21, 40), 0xa070c0, 1)   # chifre
	line(neck, Vector3(0, -10, 33), Vector3(0, -6, 26), 0xe070a0, 3)   # crina
	var tail := rig.bone("tail", "body", Vector3(0.5, 14.5, 22.5))
	line(tail, Vector3(0, 14, 22), Vector3(0, 18, 12), 0xe070a0, 3)
	for i in 4:
		var side := 1 if i % 2 == 0 else -1
		var y := -5 if i < 2 else 11
		var l := rig.bone("leg%d" % i, "body", Vector3(side * 3 + 0.5, y + 0.5, 15.5))
		line(l, Vector3(side * 3, y, 15), Vector3(side * 3, y, 1), pal[1], 2)
		l.box(Vector3i(side * 3, y, 0), Vector3i(side * 3 + 1, y + 1, 1), 0x3a60c0)
	for a in ["idle", "move", "attack"]:
		var T: float = {"idle": 2.4, "move": 0.7, "attack": 0.5}[a]
		var amp: float = {"idle": 2.0, "move": 28.0, "attack": 36.0}[a]
		rig.anim(a, T)
		rig.sway(a, "body", "pos", Vector3(0, 0.4, 0), 0.25, 2 if a != "idle" else 1)
		rig.sway(a, "neck", "rot", Vector3(5 if a == "idle" else 8, 0, 0), 0.2)
		rig.sway(a, "tail", "rot", Vector3(0, 0, 10 if a == "idle" else 25), 0.3)
		for i in 4:
			rig.sway(a, "leg%d" % i, "rot", Vector3(amp, 0, 0), (0.0 if i in [0, 3] else 0.5))
	rig.std_hurt("body", 0.2)
	rig.std_death("body", 0.7, 200.0)
	return rig


# ---- Snow Flinx: bola de pelo branca com focinho rosa e patinhas; pula ----
static func snow_flinx() -> BbRig:
	var rig := BbRig.new()
	rig.center = Vector3(0.5, 0.5, 0)
	var c := Vector3(0, 0, 11)
	var r := Vector3(9, 8, 9)
	var body := rig.bone("body", "", Vector3(0.5, 0.5, 4.5))
	body.ellipsoid(c, r, func(p: Vector3i): return tone((Vector3(p) - c) / r, [0xf4f8fc, 0xd4dce8, 0xa8b4c8]))
	body.ellipsoid(Vector3(0, -8, 9), Vector3(3, 2, 2), 0xe0a0a8)
	for side in [-1, 1]:
		body.put(Vector3i(side * 3, -8, 12), 0x1a1a24)
		body.box(Vector3i(side * 4 - 1, -3, 0), Vector3i(side * 4, -2, 2), 0xd09098)
	for a in ["idle", "move", "attack"]:
		var T: float = {"idle": 1.8, "move": 0.7, "attack": 0.5}[a]
		var k: float = {"idle": 0.04, "move": 0.16, "attack": 0.22}[a]
		rig.anim(a, T)
		rig.sway(a, "body", "scl", Vector3(-k * 0.5, k * 0.5, -k * 0.5), 0.0, 1, Vector3.ONE)
		rig.sway(a, "body", "pos", Vector3(0, 0, 0 if a == "idle" else 2.0), 0.0)
	rig.std_hurt("body", 0.2)
	rig.std_death("body", 0.5, 300.0)
	return rig


# ---- Meteor Head: rocha escura com crateras e cauda de chamas; gira e queima ----
static func meteor_head() -> BbRig:
	var rig := BbRig.new()
	rig.center = Vector3(0.5, 0.5, 0)
	var c := Vector3(0, 0, 9)
	var r := Vector3(8, 8, 8)
	var body := rig.bone("body", "", Vector3(0.5, 0.5, 9.5))
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	var craters := []
	for i in 9:
		craters.append(Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 0.3), rng.randf_range(-0.8, 0.8)).normalized())
	body.ellipsoid(c, r, func(p: Vector3i):
		var n := (Vector3(p) - c).normalized()
		for cr in craters:
			if n.dot(cr) > 0.95:
				return 0x2a1618
		return tone(n, [0x8a5a60, 0x6a4048, 0x4a2a30]))
	for side in [-1, 1]:
		body.put(Vector3i(side * 3, -8, 11), 0xf0c030)
	var flame := rig.bone("flame", "body", Vector3(0.5, 7.5, 9.5))
	for i in 4:
		var a := TAU * i / 4.0
		line(flame, Vector3(cos(a) * 3, 7, 9 + sin(a) * 3), Vector3(cos(a) * 4, 16, 9 + sin(a) * 4), [0xf08020, 0xf0b030, 0xe05010, 0xf0d060][i], 2)
	for a in ["idle", "move", "attack"]:
		var T: float = {"idle": 1.6, "move": 0.8, "attack": 0.5}[a]
		rig.anim(a, T)
		rig.sway(a, "body", "pos", Vector3(0, 0.6, 0))
		rig.sway(a, "body", "rot", Vector3(0, 0, 12 if a != "idle" else 5))
		rig.sway(a, "flame", "rot", Vector3(0, 0, 15 if a != "idle" else 8), 0.3)
		rig.sway(a, "flame", "scl", Vector3(0.12, 0.2, 0.12), 0.0, 2, Vector3.ONE)
	rig.std_hurt("body", 0.2)
	rig.std_death("body", 0.5, 400.0)
	return rig


# ---- Pixie: orbe brilhante com duas asas translúcidas de zumbido rápido ----
static func pixie() -> BbRig:
	var rig := BbRig.new()
	rig.center = Vector3(0.5, 0.5, 0)
	var c := Vector3(0, 0, 8)
	var body := rig.bone("body", "", Vector3(0.5, 0.5, 8.5))
	body.ellipsoid(c, Vector3(4, 4, 4), func(p: Vector3i): return tone((Vector3(p) - c), [0xfff8c0, 0xf8e060, 0xe0b030]))
	body.ellipsoid(c + Vector3(0, 0, 0), Vector3(2, 2, 2), 0xffffff)
	for side in [1, -1]:
		var wing := rig.bone("w" + ("a" if side == 1 else "b"), "body", Vector3(side * 3 + 0.5, 0.5, 11.5))
		for x in range(0, 11):
			for z in range(-3, 6):
				if pow((x - 5) / 6.0, 2) + pow((z - 1) / 5.0, 2) <= 1.0:
					wing.put(Vector3i(side * (x + 3), 1, 11 + z), 0xc0e0f0 if (x + z) % 4 else 0xf0f8ff)
	for a in ["idle", "move", "attack"]:
		var amp: float = {"idle": 25.0, "move": 35.0, "attack": 45.0}[a]
		rig.anim(a, 0.2)
		rig.sway(a, "wa", "rot", Vector3(0, 0, -amp), 0.0, 1, Vector3(0, 0, -25))
		rig.sway(a, "wb", "rot", Vector3(0, 0, amp), 0.0, 1, Vector3(0, 0, 25))
		rig.sway(a, "body", "pos", Vector3(0, 0.4, 0))
	rig.std_hurt("body", 0.2)
	rig.std_death("body", 0.5, 400.0)
	return rig


# ---- Face Monster: figura marrom corcunda com a cabeça de carne rosada e uma boca vertical com dentes no peito ----
static func face_monster() -> BbRig:
	var rig := BbRig.new()
	rig.center = Vector3(0.5, 0.5, 0)
	var brown := [0x9a6a42, 0x7a5030, 0x4a2c1a]
	var body := rig.bone("body", "", Vector3(0.5, 0.5, 18.5))
	var tc := Vector3(0, 1, 26)
	var tr := Vector3(6, 5, 9)
	body.ellipsoid(tc, tr, func(p: Vector3i): return tone((Vector3(p) - tc) / tr, brown))
	var hump := Vector3(0, 6, 28)
	body.ellipsoid(hump, Vector3(5, 4, 6), func(p: Vector3i): return tone((Vector3(p) - hump) / Vector3(5, 4, 6), brown))
	var hc := Vector3(0, -2, 37)
	var hr := Vector3(7, 6, 6)
	body.ellipsoid(hc, hr, func(p: Vector3i): return tone((Vector3(p) - hc) / hr, [0xd88890, 0xb85060, 0x8a3040]))
	for i in 5:   # lóbulos do "cérebro" na cabeça
		var at := hc + Vector3(sin(i * 1.7) * 4, cos(i * 2.3) * 3, 2 + cos(i) * 2)
		body.ellipsoid(at, Vector3(2, 2, 2), 0xc86a78)
	body.box(Vector3i(-1, -6, 14), Vector3i(0, -5, 30), 0x500808)   # boca vertical
	for z in range(15, 30, 2):
		body.put(Vector3i(-2, -5, z), 0xd8c8c8)
		body.put(Vector3i(1, -5, z + 1), 0xd8c8c8)
	for side in [1, -1]:
		var tag := "a" if side == 1 else "b"
		var hip := Vector3(side * 3, 0, 17)
		line(rig.bone("leg" + tag, "body", hip + Vector3(0.5, 0.5, 0.5)), hip, Vector3(side * 3, 0, 1), brown[2], 3)
		var sh := Vector3(side * 7, 0, 33)
		var arm := rig.bone("arm" + tag, "body", sh + Vector3(0.5, 0.5, 0.5))
		line(arm, sh, Vector3(side * 8, -1, 19), brown[1], 3)
		arm.box(Vector3i(side * 8 - 1, -2, 17), Vector3i(side * 8 + 1, 0, 19), 0xb08060)
	for a in ["idle", "move", "attack"]:
		var T: float = {"idle": 2.0, "move": 0.8, "attack": 0.5}[a]
		var amp: float = {"idle": 3.0, "move": 28.0, "attack": 20.0}[a]
		rig.anim(a, T)
		rig.sway(a, "body", "pos", Vector3(0, 0.5, 0), 0.25, 2 if a != "idle" else 1)
		rig.sway(a, "body", "rot", Vector3(8 if a == "attack" else 2, 0, 3 if a != "attack" else 0), 0.0, 1, Vector3(6 if a == "attack" else 0, 0, 0))
		for s2 in ["a", "b"]:
			var ph := 0.0 if s2 == "a" else 0.5
			rig.sway(a, "leg" + s2, "rot", Vector3(amp, 0, 0), ph)
			rig.sway(a, "arm" + s2, "rot", Vector3(amp * (1.2 if a == "attack" else 0.8), 0, 0), ph + 0.5, 1, Vector3(-40 if a == "attack" else 0, 0, 0))
	rig.std_hurt("body", 0.25)
	rig.std_death("body", 0.8, 0.0)
	return rig


# ---- King Slime (k=3): domo de gelatina azul com brilho, olhos e a coroa dourada; esmaga e estica ao pular ----
static func king_slime() -> BbRig:
	var rig := BbRig.new()
	rig.k = 3
	rig.center = Vector3(0.5, 0.5, 0)
	var blue := [0x7a9aff, 0x4a6ae0, 0x2c48b0]
	var c := Vector3(0, 0, 0)
	var r := Vector3(15, 13, 11)
	var body := rig.bone("body", "", Vector3(0.5, 0.5, 0))
	body.ellipsoid(c, r, func(p: Vector3i): return tone((Vector3(p) - c) / r, blue))
	for p in body.v.keys():
		if p.z < 0:
			body.v.erase(p)
	body.ellipsoid(Vector3(-6, -6, 8), Vector3(3, 2, 2), 0xb8ccff)   # brilho
	body.ellipsoid(Vector3(0, 0, 4), Vector3(8, 7, 3), 0x3a58c8)       # miolo mais escuro
	for side in [-1, 1]:
		body.ellipsoid(Vector3(side * 5, -11, 6), Vector3(2, 1, 2.5), 0xf4f4f4)
		body.ellipsoid(Vector3(side * 5, -12, 6), Vector3(1, 1, 1.5), 0x101018)
	body.box(Vector3i(-3, -12, 2), Vector3i(3, -12, 2), 0x1a2a70)   # sorriso
	var crown := rig.bone("crown", "body", Vector3(0.5, 0.5, 10.5))
	crown.box(Vector3i(-6, -4, 10), Vector3i(5, 3, 12), 0xf0c030)
	for i in 5:
		var x := -6 + i * 3
		crown.box(Vector3i(x, -4, 13), Vector3i(x + 1, 3, 15 + (i % 2)), 0xf8d850)
	for a in ["idle", "move", "attack"]:
		var T: float = {"idle": 1.6, "move": 0.9, "attack": 0.6}[a]
		var k: float = {"idle": 0.04, "move": 0.18, "attack": 0.24}[a]
		rig.anim(a, T)
		rig.sway(a, "body", "scl", Vector3(-k * 0.5, k, -k * 0.5), 0.0, 1, Vector3.ONE)
		rig.sway(a, "body", "pos", Vector3(0, 0, 0 if a == "idle" else 2.5), 0.25)
	rig.std_hurt("body", 0.25)
	rig.std_death("body", 0.9, 0.0)
	return rig
