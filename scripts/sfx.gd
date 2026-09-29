class_name Sfx
# Sons gerados por código (sem arquivos de áudio): rajadas de ruído filtrado e tons com envelope, como os efeitos curtos do Terraria.
# Sfx.play(entities, "dig", pos) toca em 3D no ponto; fora da árvore (testes) ou com o volume das Configurações em zero nada acontece.
#   dig / stone (picareta em terra / pedra)  break (bloco quebrou)  place  swing  hit  hurt (o jogador)  die (inimigo)
#   pickup / coin  splash  boss  bow  flap  drink

const RATE := 22050
const MAX_ACTIVE := 12

static var enabled := true
static var _cache := {}
static var active := 0
static var last := ""   # o último som pedido (os testes conferem sem precisar de áudio)


# Ruído passa-baixa (k perto de 0 = grave e abafado, 1 = chiado) com decaimento exponencial; `tone` soma um seno (freq, ganho).
static func _burst(dur: float, k: float, decay: float, tone := Vector2.ZERO) -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var y := 0.0
	for i in n:
		var t := float(i) / n
		y += (rng.randf_range(-1.0, 1.0) - y) * k
		var s := y * 2.2
		if tone.x > 0.0:
			s += sin(TAU * tone.x * i / RATE) * tone.y
		out[i] = s * exp(-t * decay)
	return out


# Seno que varia de f0 a f1 (varredura), com decaimento; `saw` mistura dente de serra (som mais áspero).
static func _sweep(dur: float, f0: float, f1: float, decay: float, saw := 0.0) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var ph := 0.0
	for i in n:
		var t := float(i) / n
		ph += TAU * lerpf(f0, f1, t) / RATE
		var s := sin(ph) * (1.0 - saw) + (fmod(ph / TAU, 1.0) * 2.0 - 1.0) * saw
		out[i] = s * exp(-t * decay) * minf(1.0, i / 120.0)
	return out


static func _mix(a: PackedFloat32Array, b: PackedFloat32Array, delay := 0) -> PackedFloat32Array:
	var out := a.duplicate()
	if b.size() + delay > out.size():
		out.resize(b.size() + delay)
	for i in b.size():
		out[i + delay] += b[i]
	return out


static func build(name: String) -> PackedFloat32Array:
	match name:
		"dig": return _burst(0.10, 0.18, 6.0)
		"stone": return _mix(_burst(0.10, 0.35, 7.0), _sweep(0.05, 1500.0, 900.0, 8.0))
		"break": return _burst(0.22, 0.22, 4.5, Vector2(90.0, 0.5))
		"place": return _burst(0.08, 0.12, 8.0, Vector2(170.0, 0.6))
		"swing": return _burst(0.20, 0.5, 5.0)   # o silvo sobe: o volume cresce e cai
		"hit": return _mix(_burst(0.12, 0.3, 7.0), _sweep(0.12, 140.0, 70.0, 5.0))
		"hurt": return _sweep(0.28, 260.0, 110.0, 3.5, 0.7)
		"die": return _mix(_sweep(0.35, 220.0, 60.0, 3.0, 0.5), _burst(0.3, 0.25, 5.0))
		"pickup": return _mix(_sweep(0.07, 660.0, 700.0, 6.0), _sweep(0.10, 990.0, 1000.0, 6.0), 700)
		"coin": return _mix(_sweep(0.05, 1568.0, 1568.0, 5.0), _sweep(0.16, 2093.0, 2093.0, 6.0), 900)
		"splash": return _burst(0.32, 0.3, 4.0)
		"boss": return _mix(_sweep(1.3, 55.0, 38.0, 1.6, 0.8), _sweep(1.3, 82.0, 50.0, 1.8, 0.6))
		"bow": return _mix(_sweep(0.10, 300.0, 120.0, 8.0), _burst(0.08, 0.6, 9.0))
		"flap": return _burst(0.14, 0.3, 7.0)   # batida de asas: um sopro grave
		"drink": return _mix(_sweep(0.10, 180.0, 120.0, 6.0), _sweep(0.10, 160.0, 110.0, 6.0), 2200)   # dois goles
	return PackedFloat32Array()


static func stream(name: String) -> AudioStreamWAV:
	if not _cache.has(name):
		var samples := build(name)
		var data := PackedByteArray()
		data.resize(samples.size() * 2)
		for i in samples.size():
			data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 30000.0))
		var w := AudioStreamWAV.new()
		w.format = AudioStreamWAV.FORMAT_16_BITS
		w.mix_rate = RATE
		w.data = data
		_cache[name] = w
	return _cache[name]


static func play(parent: Node3D, name: String, pos: Vector3, volume_db := -6.0, pitch := 1.0) -> void:
	last = name
	if not enabled or Settings.volume <= 0.0 or parent == null or not parent.is_inside_tree() or active >= MAX_ACTIVE:
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = stream(name)
	p.volume_db = volume_db + linear_to_db(Settings.volume)
	p.pitch_scale = pitch * randf_range(0.93, 1.07)   # cada toque um pouco diferente
	p.unit_size = 10.0
	p.max_distance = 70.0
	p.position = pos
	active += 1
	p.finished.connect(func():
		active -= 1
		p.queue_free())
	parent.add_child(p)
	p.play()
