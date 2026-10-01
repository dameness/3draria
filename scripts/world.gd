extends Node3D
# Guarda os chunks do mundo finito e mantém malhas só dentro da distância de renderização.
# Geração (um job por chunk, uma vez só) e mesh (um job por chunk, com os vizinhos já prontos) rodam no
# WorkerThreadPool; cada job lê só a sua cópia dos chunks e a thread principal grava o resultado em `chunks`.

const C := WorldGen.CHUNK
const H := WorldGen.HEIGHT
const NB: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]  # ordem do ChunkMesher
const GROW_MIN := 120.0   # a muda vira árvore depois de 2 a 5 minutos (a wiki: tempo aleatório, sem número)
const GROW_MAX := 300.0
const SPREAD_MIN := 30.0   # a grama do mal tenta contaminar um vizinho a cada 30 a 90 s (a wiki: aleatório, sem número)
const SPREAD_MAX := 90.0
const SPREAD_CAP := 64     # teto de grama que espalha por chunk. ponytail: sem Purification Powder/Dryad para conter o mal; quando houver, tire o teto
const DIAG: Array[Vector2i] = [Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]   # vizinhos de canto: só fontes de luz

@export var render_distance := 6  # em chunks; teclas [ e ] mudam em jogo
@export var world_seed := 1337

var gen: WorldGen
var liquid := Liquid.new()   # água e lava fluindo (liquid.gd)
var chunks := {}   # Vector2i -> PackedByteArray
var meshes := {}   # Vector2i -> MeshInstance3D, ou null (sem faces / em construção)
var model_nodes := {}   # Vector2i -> [MeshInstance3D]: blocos com modelo voxel do chunk (fora da malha; o material de cada um leva a luz do lugar)
var daylight := [1.0, Vector3.ONE]   # última luz do dia (set_light), para os modelos novos
var material := ShaderMaterial.new()   # shaders/chunk.gdshader: atlas × luz do céu/tochas
var water_material := ShaderMaterial.new()   # shaders/water.gdshader: superfície translúcida da água
var atlas_texture: ImageTexture
var pending: Array[Vector2i] = []   # chunks no alcance que ainda esperam a mesh (o mais perto no fim)
var meshable: Array[Vector2i] = []     # desses, os que já têm dados (e os dos vizinhos) e podem virar mesh
var need_gen: Array[Vector2i] = []  # chunks a gerar para os pending (o mais perto no fim)
var urgent: Array[Vector2i] = []   # chunks editados que precisam de mesh nova
var npcs := {}      # habitantes que já chegaram (guide, merchant, nurse): nome -> true; salvo no mundo
var homes := {}     # onde cada habitante mora (housing.gd): nome -> Vector3i (a célula em cima da cadeira); sem casa, fica perto do nascimento; salvo no mundo
var town_wait := {}    # habitante morto: segundos até poder voltar (só volta de dia e com casa, como na wiki); salvo no mundo
var chests := {}    # Vector3i -> {item: PackedInt32Array, count: PackedInt32Array}; só os baús já abertos (os outros ainda não têm conteúdo)
var eoc_down := false        # Olho de Cthulhu já derrotado: ele deixa de nascer sozinho ao anoitecer
var evil_boss_down := false   # Eater of Worlds / Brain já derrotado: libera o meteorito e, depois, o Wall of Flesh vale
var hardmode := false       # Wall of Flesh derrotado: cobalto/paládio e Hallow (start_hardmode)
var test_world := false     # mundo de teste (test_world.gd): arena com baús de todos os itens; vai no save
var skeletron_down := false   # Skeletron derrotado: o dungeon abre para qualquer picareta
var meteor_due := false       # cai um meteorito à meia-noite
var orbs_broken := 0   # orbes/corações quebrados (a cada 3 acorda o chefe do mal); vai no save do mundo
var spread := {}     # Vector3i -> segundos até a grama do mal tentar contaminar um vizinho (a colocada e a que se espalhou; vai no save)
var saplings := {}   # Vector3i -> segundos até crescer; só as plantadas (vai no save)
var map_img := Image.create(WorldGen.SIZE, WorldGen.SIZE, false, Image.FORMAT_RGBA8)   # mapa explorado (minimap.gd; alfa 0 = não visto); vai no save
var edited := {}    # Vector2i -> true; chunks alterados pelo jogador (o save guarda só estes)
var versions := {}  # Vector2i -> nº de edições; descarta mesh de job que ficou velho
var jobs := {}     # id da task -> resultado preenchido pela thread
var generating := {}   # Vector2i -> true: chunk que um job está gerando agora
var max_jobs := clampi(OS.get_processor_count() - 1, 1, 4)
var center := Vector2i(-999, -999)


func _ready() -> void:
	Blocks.load_pack()
	Items.load_pack()
	Crafting.load_pack()
	Buffs.load_pack()
	Loot.load_pack()
	gen = WorldGen.new(world_seed)
	var atlas_image := Atlas.build(Blocks.textures)
	Blocks.tile_colors = Atlas.tile_colors(atlas_image)
	atlas_texture = ImageTexture.create_from_image(atlas_image)
	material.shader = preload("res://shaders/chunk.gdshader")
	water_material.shader = preload("res://shaders/water.gdshader")
	for m in [material, water_material]:
		m.set_shader_parameter("atlas", atlas_texture)


# Luz que anda com o jogador (poções Brilho e Coruja): power 0 desliga.
func set_aura(at: Vector3, radius: float, power: float) -> void:
	material.set_shader_parameter("aura", Vector4(at.x, at.y, at.z, radius))
	material.set_shader_parameter("aura_power", power)


# Luz do dia (day_night.gd): claridade do céu, cor dela e direção de onde vem (sol ou lua).
func set_light(daylight_v: float, tint: Vector3, dir: Vector3) -> void:
	for m in [material, water_material]:
		m.set_shader_parameter("daylight", daylight_v)
		m.set_shader_parameter("sky_tint", tint)
	material.set_shader_parameter("light_dir", dir)
	daylight = [daylight_v, tint]
	for k in model_nodes:
		for mi in model_nodes[k]:
			mi.material_override.set_shader_parameter("daylight", daylight_v)
			mi.material_override.set_shader_parameter("sky_tint", tint)


func get_block(x: int, y: int, z: int) -> int:
	if y < 0:
		return gen.BEDROCK
	var c := Vector2i(floori(x / float(C)), floori(z / float(C)))
	if y >= H or not in_world(c):
		return 0
	if not chunks.has(c):
		chunks[c] = gen.generate(c.x, c.y)
		_chunk_ready(c)   # gerado aqui, na thread principal (não pelo job): quem esperava por ele precisa saber
	return chunks[c][posmod(x, C) + posmod(z, C) * C + y * C * C]


# wake = false: o fluxo dos líquidos grava sem acordar de novo os vizinhos (ele mesmo acorda os que importam).
func set_block(x: int, y: int, z: int, id: int, wake := true) -> void:
	if y < 0 or y >= H:
		return
	get_block(x, y, z)  # garante que o chunk existe
	var c := Vector2i(floori(x / float(C)), floori(z / float(C)))
	if not in_world(c):
		return
	var lx := posmod(x, C)
	var lz := posmod(z, C)
	var reach := maxi(Blocks.light[id], Blocks.light[chunks[c][lx + lz * C + y * C * C]])   # tocha (nova ou tirada): a luz alcança os chunks em volta
	chunks[c][lx + lz * C + y * C * C] = id
	if y + 1 < H and Blocks.shape[chunks[c][lx + lz * C + (y + 1) * C * C]] == "plant" and not Blocks.solid[id]:
		chunks[c][lx + lz * C + (y + 1) * C * C] = 0  # planta sem chão some
	if Blocks.shape[id] != "cactus" and not Blocks.solid[id]:   # cortar o cacto derruba o pedaço de cima (ponytail: sem drop; corte de cima para baixo para aproveitar)
		var ay := y + 1
		while ay < H and Blocks.shape[chunks[c][lx + lz * C + ay * C * C]] == "cactus":
			chunks[c][lx + lz * C + ay * C * C] = 0
			ay += 1
	edited[c] = true
	if id == Blocks.sapling:
		saplings[Vector3i(x, y, z)] = randf_range(GROW_MIN, GROW_MAX)
	elif not saplings.is_empty():
		saplings.erase(Vector3i(x, y, z))
	if Blocks.spreads[id]:
		spread[Vector3i(x, y, z)] = randf_range(SPREAD_MIN, SPREAD_MAX)
	elif not spread.is_empty():
		spread.erase(Vector3i(x, y, z))
	if wake:
		liquid.wake(x, y, z)
	_rebuild(c)
	if lx == 0: _rebuild(c + Vector2i(-1, 0))
	if lx == C - 1: _rebuild(c + Vector2i(1, 0))
	if lz == 0: _rebuild(c + Vector2i(0, -1))
	if lz == C - 1: _rebuild(c + Vector2i(0, 1))
	if reach > 0:   # refaz também os vizinhos (e os de canto) que a luz alcança, não só os da borda
		for dz in [-1, 0, 1]:
			for dx in [-1, 0, 1]:
				var k := c + Vector2i(dx, dz)
				if (dx != 0 or dz != 0) and in_world(k) and _lit_side(lx, dx, reach) and _lit_side(lz, dz, reach):
					_rebuild(k)


# A grama do mal em p contamina um dos 26 vizinhos, sorteado: se é terra ou grama comum, está à mostra (ar ou planta ao lado) e o chunk dele ainda tem teto.
# Só a colocada/plantada e a que ela espalhou: a do bioma de nascença não anda (uma vila ao lado do mal não some).
func _spread_from(p: Vector3i) -> void:
	var q := p + Vector3i(randi_range(-1, 1), randi_range(-1, 1), randi_range(-1, 1))
	var cq := Vector2i(floori(q.x / float(C)), floori(q.z / float(C)))
	if not chunks.has(cq) or not chunks.has(Vector2i(floori(p.x / float(C)), floori(p.z / float(C)))):
		return
	var b := get_block(q.x, q.y, q.z)
	if b != Blocks.ids.dirt and b != Blocks.ids.grass:
		return
	var open := false
	for d in [Vector3i.UP, Vector3i.DOWN, Vector3i.LEFT, Vector3i.RIGHT, Vector3i.FORWARD, Vector3i.BACK]:
		var n := get_block(q.x + d.x, q.y + d.y, q.z + d.z)
		open = open or n == 0 or Blocks.soft[n] == 1
	var count := 0
	for k in spread:
		count += 1 if floori(k.x / float(C)) == cq.x and floori(k.z / float(C)) == cq.y else 0
	if open and count < SPREAD_CAP:
		set_block(q.x, q.y, q.z, get_block(p.x, p.y, p.z))


# A muda em p vira árvore se há grama embaixo e espaço livre em volta (2 blocos de cada lado, 12 de altura); senão tenta de novo em 1 min.
# A árvore sai de WorldGen.tree com uma semente da posição (a mesma muda dá a mesma árvore).
func grow_sapling(p: Vector3i) -> bool:
	var room := Blocks.grassy[get_block(p.x, p.y - 1, p.z)] == 1
	for dy in range(0, 13):
		for dz in range(-2, 3):
			for dx in range(-2, 3):
				var b := get_block(p.x + dx, p.y + dy, p.z + dz)
				room = room and (b == 0 or Blocks.shape[b] == "plant")   # (a própria muda é uma planta)
	if not room:
		saplings[p] = 60.0
		return false
	saplings.erase(p)
	set_block(p.x, p.y, p.z, 0)
	var side := PackedInt32Array()
	for d in WorldGen.DIRS4:
		side.append(surface_y(p.x + d.x, p.z + d.y, true) - 1)
	var h := absi(hash([world_seed, p.x, p.z]))
	for cz in range(floori((p.z - 6) / float(C)), floori((p.z + 6) / float(C)) + 1):
		for cx in range(floori((p.x - 6) / float(C)), floori((p.x + 6) / float(C)) + 1):
			var k := Vector2i(cx, cz)
			if in_world(k):
				get_block(cx * C, 0, cz * C)   # garante o chunk
				gen.tree(chunks[k], cx, cz, p.x, p.z, p.y - 1, side, h)
				edited[k] = true
				_rebuild(k)
	return true


# A luz de raio `reach` de um bloco na posição local l (0..15) chega ao chunk vizinho na direção d (−1, 0 ou 1)?
static func _lit_side(l: int, d: int, reach: int) -> bool:
	return d == 0 or (d < 0 and l < reach) or (d > 0 and l + reach >= C)


# Líquido (id do cheio: water, lava) que contém o ponto p, ou 0: o ponto tem de estar abaixo da superfície do bloco.
func liquid_at(p: Vector3) -> int:
	var x := floori(p.x)
	var y := floori(p.y)
	var z := floori(p.z)
	var b := get_block(x, y, z)
	if not Blocks.liquid[b]:
		return 0
	var above := get_block(x, y + 1, z)
	if p.y - y < Blocks.liquid_height(b) or (Blocks.liquid[above] and Blocks.liquid_kind[above] == Blocks.liquid_kind[b]):
		return Blocks.liquid_kind[b]
	return 0


# Começa o hardmode: liga na geração (chunks novos) e converte os já gerados (mesmo passe determinístico). Os chunks convertidos
# passam a contar como editados para o save guardá-los.
func start_hardmode() -> void:
	hardmode = true
	gen.hardmode = true
	for k in chunks.keys():
		gen.hardmode_pass(chunks[k], k.x, k.y)
		edited[k] = true
		_rebuild(k)


# Conteúdo do baú em p; na primeira vez sorteia o tesouro pela camada (Loot; determinístico pela seed e posição).
func chest_at(p: Vector3i) -> Dictionary:
	var k: int = TestWorld.chest_at_pos.get(p, -1) if test_world else -1
	if not chests.has(p):
		var rng := RandomNumberGenerator.new()
		rng.seed = hash([world_seed, p.x, p.y, p.z])
		chests[p] = TestWorld.stock(k) if k != -1 else Loot.chest("living" if gen and gen.living_chests.has(p) else "water" if gen and gen.in_sea(p.x, p.z) else Loot.layer_of(p.y), rng, gen.sky_chests.find(p) if gen else -1)   # ilhas: cada uma com o próximo item principal
	if k != -1:
		chests[p].title = TestWorld.chests[k].title   # o painel mostra o nome da categoria (não vai no save: sai da posição)
	return chests[p]


# Liga ou desliga o mundo de teste (antes de gerar chunks: a arena entra na geração).
func set_test(on: bool) -> void:
	test_world = on
	gen.test_world = on
	if on:
		TestWorld.build()


# Troca a seed e descarta tudo o que foi gerado (usado ao carregar um save).
func set_seed(s: int, test := false) -> void:
	world_seed = s
	gen = WorldGen.new(s)
	set_test(test)
	chunks.clear()
	edited.clear()
	chests.clear()
	npcs.clear()
	homes.clear()
	town_wait.clear()
	orbs_broken = 0
	evil_boss_down = false
	eoc_down = false
	meteor_due = false
	skeletron_down = false
	hardmode = false
	liquid = Liquid.new()
	map_img.fill(Color(0, 0, 0, 0))
	saplings.clear()
	spread.clear()


# Primeiro y livre acima do bloco sólido mais alto da coluna (ground: sem contar tronco e folhas). Ignora o céu (a partir de SKY_BASE, só há ilhas
# flutuantes): para achar o chão de uma ilha, passe top = H - 1.
func surface_y(x: int, z: int, ground := false, top := WorldGen.SKY_BASE - 1) -> int:
	for y in range(top, -1, -1):
		var b := get_block(x, y, z)
		if Blocks.solid[b] and not (ground and Blocks.clear[b]):
			return y + 1
	return 0


func _rebuild(k: Vector2i) -> void:
	versions[k] = versions.get(k, 0) + 1
	if meshes.has(k) and not k in urgent:
		urgent.append(k)


# Percorre voxels ao longo do raio (Amanatides & Woo).
# Retorna {"pos": bloco atingido, "normal": face atingida, "t": distância até a entrada no bloco} ou {} se não acertar.
func raycast(from: Vector3, dir: Vector3, max_dist: float, liquids := false) -> Dictionary:   # liquids: o líquido também é alvo (balde)
	var p := Vector3i(from.floor())
	var step := Vector3i(dir.sign())
	var t_delta := Vector3.INF
	var t_max := Vector3.INF
	for a in 3:
		if dir[a] != 0:
			t_delta[a] = absf(1.0 / dir[a])
			t_max[a] = (p[a] + 1 - from[a] if dir[a] > 0 else from[a] - p[a]) * t_delta[a]
	var normal := Vector3i.ZERO
	var t := 0.0
	while t <= max_dist:
		var b := get_block(p.x, p.y, p.z)
		if b != 0 and (not Blocks.soft[b] or (liquids and Blocks.liquid[b])):  # a mira pega também blocos não sólidos (tochas), mas atravessa plantas e líquidos
			return {"pos": p, "normal": normal, "t": t}
		var a := t_max.min_axis_index()
		t = t_max[a]
		p[a] += step[a]
		t_max[a] += t_delta[a]
		normal = Vector3i.ZERO
		normal[a] = -step[a]
	return {}


func in_world(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < WorldGen.SIZE_CHUNKS and c.y < WorldGen.SIZE_CHUNKS


func set_render_distance(rd: int) -> void:
	render_distance = clampi(rd, 2, 16)
	center = Vector2i(-999, -999)  # força recalcular a fila


func is_idle() -> bool:
	return pending.is_empty() and urgent.is_empty() and jobs.is_empty()


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed:
		if e.keycode == KEY_BRACKETRIGHT:
			set_render_distance(render_distance + 1)
		elif e.keycode == KEY_BRACKETLEFT:
			set_render_distance(render_distance - 1)


func _process(delta: float) -> void:
	liquid.step(self, delta)
	for p in saplings.keys():
		saplings[p] -= delta
		if saplings[p] <= 0.0:
			grow_sapling(p)
	for p in spread.keys():
		spread[p] -= delta
		if spread[p] <= 0.0:
			spread[p] = randf_range(SPREAD_MIN, SPREAD_MAX)
			_spread_from(p)
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var c := Vector2i(floori(cam.global_position.x / C), floori(cam.global_position.z / C))
	if c != center:
		_recenter(c, cam)
	for id in jobs.keys():
		if WorkerThreadPool.is_task_completed(id):
			WorkerThreadPool.wait_for_task_completion(id)
			_apply(jobs[id])
			jobs.erase(id)
	while jobs.size() < max_jobs:
		var r := _next_job()
		if r.is_empty():
			break
		jobs[WorkerThreadPool.add_task(_job.bind(r))] = r


# Próximo trabalho: refazer a mesh de um chunk editado, montar a de um chunk pronto (dados dele e dos vizinhos),
# ou gerar o chunk mais perto que falta. {} se não há nada a fazer agora.
func _next_job() -> Dictionary:
	if not urgent.is_empty():
		return _mesh_job(urgent.pop_front())
	while not meshable.is_empty():
		var k: Vector2i = meshable.pop_front()
		if pending.has(k):
			pending.erase(k)
			meshes[k] = null
			return _mesh_job(k)
	while not need_gen.is_empty():
		var c: Vector2i = need_gen.pop_back()
		if not chunks.has(c) and not generating.has(c):
			generating[c] = true
			return {"gen": c}
	return {}


# Um chunk ganhou dados (do job ou de get_block): ele e os vizinhos que já tinham tudo o mais podem virar mesh. (Sem isto, um chunk gerado por get_block enquanto estava na fila
# de geração ficava em `pending` sem nunca entrar em `meshable`: um buraco no mapa até o jogador mudar de chunk.)
func _chunk_ready(c: Vector2i) -> void:
	for o in [Vector2i.ZERO] + NB:
		var k: Vector2i = c + o
		if pending.has(k) and not meshable.has(k) and _has_data(k):
			meshable.append(k)


func _has_data(k: Vector2i) -> bool:
	for o in [Vector2i.ZERO] + NB:
		if in_world(k + o) and not chunks.has(k + o):
			return false
	return true


func _mesh_job(k: Vector2i) -> Dictionary:
	var r := {"k": k, "chunks": {}, "version": versions.get(k, 0)}
	for o in [Vector2i.ZERO] + NB + DIAG:
		if chunks.has(k + o):
			r.chunks[k + o] = chunks[k + o]
	return r


func _recenter(c: Vector2i, cam: Camera3D) -> void:
	center = c
	var r := render_distance
	for k in meshes.keys():
		if (k - c).length_squared() > (r + 1) * (r + 1):
			if meshes[k]:
				meshes[k].queue_free()
			meshes.erase(k)
			_free_models(k)
	for k in chunks.keys():   # o mundo é grande: chunks longe e sem edição saem da memória (get_block/a geração os refazem iguais)
		if not edited.has(k) and (k - c).length_squared() > (r + 4) * (r + 4):
			chunks.erase(k)
	pending.clear()
	for z in range(c.y - r, c.y + r + 1):
		for x in range(c.x - r, c.x + r + 1):
			var k := Vector2i(x, z)
			if in_world(k) and not meshes.has(k) and (k - c).length_squared() <= r * r:
				pending.append(k)
	pending.sort_custom(func(a, b): return (a - c).length_squared() > (b - c).length_squared())
	meshable.clear()
	need_gen.clear()
	var seen := {}
	for n in range(pending.size() - 1, -1, -1):   # do mais perto para o mais longe
		if _has_data(pending[n]):
			meshable.append(pending[n])
		for o in [Vector2i.ZERO] + NB:
			var g: Vector2i = pending[n] + o
			if in_world(g) and not chunks.has(g) and not seen.has(g):
				seen[g] = true
				need_gen.append(g)
	need_gen.reverse()
	cam.far = (r + 2) * C
	var env := get_world_3d().environment
	if env:
		env.fog_depth_end = r * C
		env.fog_depth_begin = r * C * 0.6


# Roda em thread: gera um chunk ("gen") ou monta os arrays da mesh de um chunk (opaca + água).
func _job(r: Dictionary) -> void:
	if r.has("gen"):
		r.data = gen.generate(r.gen.x, r.gen.y)
		return
	var k: Vector2i = r.k
	r.water = []
	r.models = []
	r.arrays = ChunkMesher.build(r.chunks[k], NB.map(func(o): return r.chunks.get(k + o, PackedByteArray())), Blocks.textures.size(), r.water,
		DIAG.map(func(o): return r.chunks.get(k + o, PackedByteArray())), r.models)


func _apply(r: Dictionary) -> void:
	if r.has("gen"):
		generating.erase(r.gen)
		if not chunks.has(r.gen):  # a thread principal pode ter gerado o mesmo chunk antes (get_block)
			chunks[r.gen] = r.data
		_chunk_ready(r.gen)
		return
	var k: Vector2i = r.k
	if not meshes.has(k) or r.version != versions.get(k, 0):
		return  # saiu do alcance, ou foi editado depois e outro job vai trazer a mesh certa
	if meshes[k]:
		meshes[k].queue_free()
		meshes[k] = null
	_free_models(k)
	_spawn_models(k, r.models)
	if r.arrays.is_empty() and r.water.is_empty():
		return
	var mesh := ArrayMesh.new()
	for s in [[r.arrays, material], [r.water, water_material]]:  # superfície 0 = opaca, 1 = água
		if not s[0].is_empty():
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, s[0])
			mesh.surface_set_material(mesh.get_surface_count() - 1, s[1])
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = Vector3(k.x * C, 0, k.y * C)
	add_child(mi)
	meshes[k] = mi


func _free_models(k: Vector2i) -> void:
	for mi in model_nodes.get(k, []):
		mi.queue_free()
	model_nodes.erase(k)


# Instâncias dos blocos com modelo voxel (scripts/voxel): a base no chão do bloco, centrado, olhando para -Z; cada uma com o próprio
# material para levar a luz do lugar (céu e tocha, do mesher) e a do dia.
func _spawn_models(k: Vector2i, list: Array) -> void:
	for e in list:
		var b: int = e[0]
		var mesh := VoxRecipes.block_mesh(Blocks.model[b], Blocks.model_size[b])
		if mesh == null:
			continue
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		var mat: ShaderMaterial = VoxMesh.material().duplicate()
		mat.set_shader_parameter("world_light", Vector2(e[2].x, e[2].y))
		mat.set_shader_parameter("daylight", daylight[0])
		mat.set_shader_parameter("sky_tint", daylight[1])
		mi.material_override = mat
		mi.position = Vector3(k.x * C + e[1].x + 0.5, e[1].y, k.y * C + e[1].z + 0.5)
		add_child(mi)
		if not model_nodes.has(k):
			model_nodes[k] = []
		model_nodes[k].append(mi)


func _exit_tree() -> void:
	for id in jobs:
		WorkerThreadPool.wait_for_task_completion(id)
