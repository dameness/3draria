extends Node3D
# Jogador em 1ª pessoa com colisão AABB contra os voxels (VoxelBody).
# Teclas como no Terraria (wiki Controls): WASD anda, Espaço pula, 1-0 ou a roda escolhem o slot, Esc abre/fecha o inventário (a pausa é o botão
# Configurações dele), Tab/M/+/- são do minimapa (minimap.gd), Shift segurado = Auto Select (a ferramenta certa para o alvo, senão a tocha).
# Botão esquerdo usa o item da mão (picareta minera, espada golpeia, arco atira, bloco coloca, poção bebe); o direito interage (baú, NPC).
# H/Q bebem a poção de cura, J a de mana, B as de buff (wiki Controls).
# Só do jogo (não do Terraria): F liga/desliga o modo criativo (atravessa blocos, invulnerável; Espaço sobe, C desce), V troca 1ª/3ª pessoa,
# F5 salva (também salva ao fechar), F8 dá o kit de teste, F9 abre o painel do mundo de teste (só nele: hora, chefes, hardmode, viagem). Voar de verdade é com asas (acessório): segurar Espaço no ar.

const HALF := 0.3        # meia largura da caixa
const TALL := 1.8
const EYE := 1.62
const GRAVITY := 28.0
const JUMP := 9.0        # sobe ~1,4 bloco
const WALK := 6.6        # 11 tiles/s da wiki (1 bloco = 1,67 tile); não há corrida
const FLY := 13.5        # modo criativo (F): blocos/s
const WING_ACCEL := 45.0   # asas: quanto sobe a velocidade vertical por segundo enquanto voa
const GLIDE := 1.0 / 3.0   # planando (asas sem tempo de voo, Espaço apertado): gravidade e queda máxima em 1/3 (wiki Wings)
const FALL_MAX := 50.0
const GLIDE_FALL := 7.5    # 1/3 da queda máxima da wiki (37,5 tiles/s ≈ 22,5 blocos/s)
const LOOK := 0.003      # radianos por pixel do mouse, vezes Settings.mouse_sens
const CLICK_BUFFER := 0.12   # um clique durante o fim do golpe anterior vale para o próximo
const FAN := deg_to_rad(20.0)   # o golpe corpo a corpo testa a mira e mais dois raios a ±20°
const PAD := 0.25            # ...contra a caixa do inimigo alargada em tanto (dá folga ao mirar)
const REACH := 5.0
const HOOK_HANG := 1.4                 # gancho: a esta distância da âncora o jogador fica pendurado
const SMART_CONE := deg_to_rad(12.0)   # cursor inteligente: até onde da mira ele procura um bloco
const SWIM_UP := 4.5       # Espaço na água: sobe a esta velocidade
const SWIM_SINK := 3.0     # sem Espaço: afunda devagar
const SWIM_DEPTH := 1.0    # com mais líquido que isto acima dos pés (até a cintura) nada; com menos, vadeia: anda e pula como em terra
const HOP_DEPTH := 1.5     # perto da superfície, Espaço junto de uma margem dá um pulo inteiro para sair da água
const LAVA_DAMAGE := 50    # por golpe (há invencibilidade entre um e outro), sem tirar a armadura
const METEORITE_BURN := 4  # por golpe (há invencibilidade entre um e outro)
const MAX_HP := 100          # vida máxima inicial (max_hp sobe com Life Crystals)
const MAX_HP_CAP := 400      # 20 Life Crystals de 20 (wiki)
const MAX_MANA_CAP := 200    # 10 Mana Crystals de 20 além dos 20 iniciais (wiki Mana)
const SICKNESS := 60.0       # Doença da poção depois de uma cura (wiki)
const AIR_JUMP := 0.87       # Cloud in a Bottle: o pulo extra tem ~75% da altura do primeiro (0,87² da velocidade)
const IFRAMES := 0.67    # 40 frames de invencibilidade após levar dano, como no Terraria
const TILE := 0.6              # 1 tile do Terraria em blocos (a escala do jogo: jogador de 3 tiles = 1,8)
const FALL_SAFE := 25          # queda segura em tiles (≈ 15 blocos); acima, 10 de dano por tile a mais (wiki Fall damage); asas anulam
const BREATH := 23.3           # fôlego debaixo d'água: 200 de fôlego a 1 a cada 7 quadros (wiki Breath meter)
const BREATH_REFILL := 21.0    # fôlego por segundo ao respirar: 3 de 200 por quadro, cheio em ~1,1 s
const DROWN := 17.14           # vida por segundo sem fôlego: 2 a cada 7 quadros, direto (sem defesa; wiki Drowning)
const REGEN_DELAY := 5.0
const MINE_DECAY := 2.5        # sem golpear o bloco por este tempo, as rachaduras somem
const TPP_DISTANCE := 4.0      # câmera em 3ª pessoa: distância atrás da cabeça
const TPP_SHOULDER := 0.6      # e deslocada para a direita, para a mira não ficar sobre a cabeça
const TPP_MARGIN := 0.4        # a câmera para antes do bloco que está no caminho (a lente vê ~0,1 além do ponto)
const EPS := VoxelBody.EPS
const TEST_KIT := {"hermes_boots": 1, "shiny_red_balloon": 1, "band_of_regeneration": 1, "terra_blade": 1, "enchanted_sword": 1, "wooden_bow": 1, "wooden_arrow": 200, "iron_pickaxe": 1, "fledgling_wings": 1}  # F8, para playtest
const LO := Vector3(-HALF, 0, -HALF)
const HI := Vector3(HALF, TALL, HALF)

@export var world: Node3D
@export var entities: Node3D
@export var clock: Node
var velocity := Vector3.ZERO
var knock := Vector3.ZERO     # empurrão horizontal de golpes, some aos poucos
var on_floor := false
var hit_wall := false         # o último passo bateu numa parede (usado para sair da água)
var depth := 0.0              # blocos de líquido acima dos pés
var swimming := false         # mais fundo que SWIM_DEPTH
var creative := false         # modo criativo (F): sem colisão, sem dano
var flight_left := 0.0        # segundos de voo que restam às asas; volta ao máximo no chão
var gliding := false          # planando com as asas (a animação usa)
var flapping := false         # batendo as asas agora (subindo)
var flap_timer := 0.0
var map_open := false         # mapa cheio (M) aberto: o jogador fica parado (minimap.gd liga e desliga)
var death := Vector3.INF      # onde morreu por último (o mapa marca)
var inv := Inventory.new()
var slot := 0                 # slot da hotbar na mão
var inventory_open := false
var menu_open := false        # Configurações (pausa): botão do inventário
var auto_prev := -1           # slot de antes do Auto Select (Shift); -1 = não trocou
var attack_held := false      # botão esquerdo apertado (eventos; quem repete é o autoswing do item)
var attack_buffer := 0.0      # clique ainda por atender (segundos que restam)
var third_person := false     # V alterna
var hook_state := ""          # gancho (E): "" sem gancho, "fly" a corrente indo, "pull" preso e puxando
var hook_at := Vector3.ZERO   # onde a corrente prende (o ponto da face do bloco)
var hook_time := 0.0          # segundos que faltam para a corrente chegar
var hook_from := Vector3.ZERO # de onde a corrente saiu
var hook_rope: MeshInstance3D
var smart_cursor := false     # Ctrl liga o cursor inteligente (find_target)
var message := ""             # aviso curto para o HUD
var message_until := 0
var hp := float(MAX_HP)
var max_hp := MAX_HP
var mana := 20.0
var max_mana := 20            # mana máxima de base (Mana Crystals); a Band of Starpower soma por cima (mana_cap)
var mana_use := 0.0           # segundos desde a última magia (usando mana a regeneração cai a 5%)
var buffs := {}               # nome (buffs.json) -> segundos que faltam
var recall_left := 0.0        # Magic Mirror / Recall Potion: segundos até o teleporte para casa
var air_jump_ready := false   # o pulo extra do Cloud in a Bottle ainda não foi usado neste voo
var jump_was := false         # Espaço estava apertado no passo anterior (o pulo extra pede um aperto novo)
var use_len := 0.25           # duração do uso em andamento (a animação da mão usa)
var iframes := 0.0
var since_hit := 99.0
var cooldown := 0.0
var spawn := Vector3.ZERO
var pitch := 0.0
var bob := 0.0                # fase do balanço da câmera ao andar
var shake := 0.0              # tremor da tela ao acertar ou ser acertado; some rápido
var swing_item := {}          # golpe em andamento: acerta no momento do impacto da animação
var swing_timer := 0.0
var target := {}              # resultado do raycast da mira
var mine_pos := Vector3i(-1, -1, -1)   # bloco que está sendo minerado e o dano acumulado nele (100 quebra)
var mine_damage := 0.0
var mine_idle := 0.0
var place_anim := 0.0         # a mão dá um empurrão ao colocar um bloco
var stride := 0.0             # distância andada desde a última nuvenzinha de poeira dos passos
var last_depth := 0.0
var bubble_timer := 0.0
var was_on_floor := false
var fall_speed := 0.0
var fall_top := 0.0           # altura de onde a queda atual começou (o último instante com velocidade vertical >= 0)
var last_pos := Vector3.ZERO  # posição do passo anterior (um salto grande = teletransporte: a queda recomeça)
var breath := BREATH          # segundos de fôlego que restam (só cai com a cabeça na água)
var drown_text := 0.0         # tempo até o próximo número de dano do afogamento
var crack: BlockCrack
var spelunker: Spelunker
@onready var cam: Camera3D = $Camera
var highlight: MeshInstance3D


func _ready() -> void:
	if SaveGame.world_path != "":
		SaveGame.load_world(world, self, clock, SaveGame.world_path)
		world.render_distance = Settings.render_distance
	if spawn == Vector3.ZERO:  # mundo novo: nasce no meio, na superfície
		var mid := WorldGen.SIZE_CHUNKS * WorldGen.CHUNK / 2
		spawn = Vector3(mid + 0.5, world.surface_y(mid, mid), mid + 0.5)
	position = spawn
	if SaveGame.player_path == "" or not SaveGame.load_player(self, SaveGame.player_path):
		inv.add(Items.ids.copper_pickaxe, 1)  # itens iniciais de personagem novo
		inv.add(Items.ids.copper_shortsword, 1)
		inv.add(Items.ids.copper_axe, 1)
	cam.position.y = EYE
	if world.test_world:   # mundo de teste: letreiros, habitantes e vitrine (F9 abre o painel de atalhos)
		entities.setup_test()
	if SaveGame.player_path != "":   # a aparência (cores) do personagem escolhido no menu
		get_node("Model").restyle(SaveGame.look(SaveGame.player_path))
	highlight = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3.ONE * 1.01
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0, 0, 0, 0.25)
	box.material = mat
	highlight.mesh = box
	highlight.top_level = true
	add_child(highlight)
	crack = BlockCrack.new()
	add_child(crack)
	hook_rope = MeshInstance3D.new()   # a corrente do gancho: um cilindro fino esticado entre a mão e a âncora
	var rope := CylinderMesh.new()
	rope.top_radius = 0.06
	rope.bottom_radius = 0.06
	rope.height = 1.0
	rope.radial_segments = 6
	rope.rings = 1
	var rope_mat := StandardMaterial3D.new()
	rope_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rope_mat.albedo_color = Color("#e6e9ef")
	rope.material = rope_mat
	hook_rope.mesh = rope
	hook_rope.top_level = true
	hook_rope.visible = false
	add_child(hook_rope)
	spelunker = Spelunker.new()   # os brilhos do Espeleólogo (só aparecem com o buff)
	spelunker.world = world
	spelunker.player = self
	spelunker.visible = false
	add_child(spelunker)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		SaveGame.save_all(world, self, clock)


func set_menu(open: bool) -> void:
	menu_open = open
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if open else Input.MOUSE_MODE_CAPTURED
	if is_inside_tree():
		get_tree().paused = open   # pausa de verdade: mundo, inimigos e relógio param (o HUD continua vivo)


func set_inventory(open: bool) -> void:
	inventory_open = open
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if open else Input.MOUSE_MODE_CAPTURED


func _unhandled_input(e: InputEvent) -> void:
	if menu_open or map_open:   # pausa: o HUD fecha; mapa cheio: o minimapa fecha
		return
	if e.is_action_pressed("ui_cancel"):   # Esc abre e fecha o inventário (o baú aberto e o item preso ao cursor voltam junto)
		set_inventory(not inventory_open)
	elif e is InputEventMouseMotion:
		if not inventory_open and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			look(e.relative)
	elif e is InputEventMouseButton:
		if e.button_index == MOUSE_BUTTON_LEFT:
			attack_held = e.pressed and not inventory_open
			if attack_held:
				attack_buffer = CLICK_BUFFER
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED   # clique com o mouse solto (voltou do Alt+Tab) recaptura
		elif e.pressed:
			if e.button_index == MOUSE_BUTTON_WHEEL_UP:
				slot = posmod(slot - 1, Inventory.HOTBAR)
			elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				slot = posmod(slot + 1, Inventory.HOTBAR)
			elif not inventory_open:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
				if e.button_index == MOUSE_BUTTON_RIGHT:
					interact()
	elif e is InputEventKey and e.pressed and not e.echo:
		if e.physical_keycode >= KEY_0 and e.physical_keycode <= KEY_9:
			slot = posmod(e.physical_keycode - KEY_1, Inventory.HOTBAR)  # 1..9 e 0 = décimo
		elif e.physical_keycode == KEY_H or e.physical_keycode == KEY_Q:
			quick_heal()
		elif e.physical_keycode == KEY_B:
			quick_buff()
		elif e.physical_keycode == KEY_J:
			quick_mana()
		elif e.physical_keycode == KEY_F:
			creative = not creative
		elif e.physical_keycode == KEY_V:
			third_person = not third_person
		elif e.physical_keycode == KEY_F9 and world.test_world:   # painel de atalhos do mundo de teste
			var hud: Node = get_parent().get_node("HUD")
			var show: bool = not (inventory_open and hud.test_open)
			set_inventory(show)
			hud.test_open = show
		elif e.physical_keycode == KEY_E and not inventory_open:   # gancho (wiki Controls: a tecla de gancho usa o primeiro gancho do inventário)
			use_hook()
		elif e.physical_keycode == KEY_CTRL and not inventory_open:   # (com o inventário aberto o Ctrl é o atalho da lixeira)
			smart_cursor = not smart_cursor
			say("Cursor inteligente: %s" % ("ligado" if smart_cursor else "desligado"))
		elif e.physical_keycode == KEY_F8:
			for n in TEST_KIT:
				inv.add(Items.ids[n], TEST_KIT[n])
			say("kit de teste")
		elif e.physical_keycode == KEY_F5:
			say("jogo salvo" if SaveGame.save_all(world, self, clock) == OK else "erro ao salvar")


func look(rel: Vector2) -> void:
	var sens := LOOK * Settings.mouse_sens
	rotation.y -= rel.x * sens
	pitch = clampf(pitch - rel.y * sens, -1.55, 1.55)
	cam.rotation.x = pitch


func _physics_process(delta: float) -> void:
	var k := func(key): return 1.0 if Input.is_physical_key_pressed(key) and not map_open else 0.0   # com o mapa cheio aberto fica parado
	var wish := Vector3(k.call(KEY_D) - k.call(KEY_A), 0, k.call(KEY_S) - k.call(KEY_W)).rotated(Vector3.UP, rotation.y)
	if creative:
		wish.y = k.call(KEY_SPACE) - k.call(KEY_C)
	step(delta, wish.normalized(), k.call(KEY_SPACE) > 0.0)
	tick(delta)


# O bloco da mira. Com o cursor inteligente (Ctrl) e uma ferramenta na mão, se a mira não pega nada, procura o bloco mais perto da linha de visada
# num cone de 12° (dois anéis de 8 raios), como o Smart Cursor do Terraria escolhe o bloco perto do cursor.
func find_target(from: Vector3, dir: Vector3) -> Dictionary:
	var hit: Dictionary = world.raycast(from, dir, REACH)
	var id := held()
	if not hit.is_empty() or not smart_cursor or id == -1 or (Items.pick_power[id] == 0 and Items.axe_power[id] == 0 and Items.hammer_power[id] == 0):
		return hit
	var side := dir.cross(Vector3.UP if absf(dir.y) < 0.99 else Vector3.RIGHT).normalized()
	var up := side.cross(dir).normalized()
	for ring in [SMART_CONE / 2.0, SMART_CONE]:
		for k in 8:
			var a := k * TAU / 8.0
			var h: Dictionary = world.raycast(from, (dir + (side * cos(a) + up * sin(a)) * tan(ring)).normalized(), REACH)
			if not h.is_empty() and (hit.is_empty() or h.t < hit.t):
				hit = h
		if not hit.is_empty():
			return hit   # o anel de dentro tem prioridade
	return hit


func eye() -> Vector3:
	return global_position + Vector3.UP * EYE


func _process(delta: float) -> void:
	_update_camera(delta)
	target = find_target(eye(), -cam.global_basis.z)
	highlight.visible = not target.is_empty()
	if highlight.visible:
		highlight.global_position = Vector3(target.pos) + Vector3.ONE * 0.5
	if mine_damage > 0.0 and not target.is_empty() and target.pos == mine_pos:
		crack.show_at(mine_pos, mine_damage / 100.0)
	else:
		crack.visible = false
	_update_rope()
	var free := not (inventory_open or menu_open or map_open)   # mãos livres: sem painel na frente
	auto_pick(free and Input.is_physical_key_pressed(KEY_SHIFT))
	if not free:
		attack_held = false
		attack_buffer = 0.0
	elif attack_held and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		attack_held = false   # o soltar do botão se perdeu (ex.: foi solto sobre um painel)
	attack(delta)


# 1ª pessoa: câmera nos olhos e item na mão da câmera. 3ª pessoa: câmera atrás da cabeça e ao lado do ombro, mais perto se
# houver bloco no caminho (o raio vai dos olhos até o ponto da câmera, ombro incluído), e o corpo do jogador aparece.
func _update_camera(delta := 0.0) -> void:
	var offset := Vector3.ZERO
	if third_person:
		var want := Basis(Vector3.RIGHT, pitch) * Vector3(0, 0, TPP_DISTANCE) + Vector3(TPP_SHOULDER, 0, 0)   # em relação aos olhos
		var hit: Dictionary = world.raycast(eye(), (global_basis * want).normalized(), want.length() + TPP_MARGIN)
		var k := 1.0 if hit.is_empty() else clampf((hit.t - TPP_MARGIN) / want.length(), 0.0, 1.0)
		for i in 6:   # rede de segurança: encosta na parede lateral ou no teto sem a lente entrar em bloco
			if lens_clear(eye() + global_basis * (want * k)):
				break
			k *= 0.7
		offset = want * k
	cam.position = Vector3(0, EYE, 0) + offset
	var walk := clampf(Vector2(velocity.x, velocity.z).length() / WALK, 0.0, 1.4) if on_floor and not creative else 0.0
	bob += delta * (7.0 + walk * 3.0) * walk
	shake = maxf(shake - delta * 2.5, 0.0)
	if not third_person and delta > 0.0:   # em 1ª pessoa a câmera balança ao andar e treme nos golpes
		cam.position += Vector3(cos(bob * 0.5) * 0.02, absf(sin(bob)) * 0.035, 0) * walk
		cam.position += Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * shake * 0.05
	cam.get_node("Hand").visible = not third_person
	get_node("Model").visible = third_person


# A lente (um cubo de 0,3 em volta de p) não toca em bloco sólido.
func lens_clear(p: Vector3) -> bool:
	for dx in [-0.15, 0.15]:
		for dy in [-0.15, 0.15]:
			for dz in [-0.15, 0.15]:
				if Blocks.solid[world.get_block(floori(p.x + dx), floori(p.y + dy), floori(p.z + dz))]:
					return false
	return true


# Timers de vida: invencibilidade, cooldown de uso e regeneração lenta.
func tick(delta: float) -> void:
	iframes -= delta
	cooldown -= delta
	place_anim = maxf(place_anim - delta, 0.0)
	if not swing_item.is_empty():
		swing_timer -= delta
		if swing_timer <= 0.0:   # o impacto do golpe: a lâmina acerta o que está à frente e a picareta bate no bloco da mira
			var hits := 0
			if swing_item.get("damage", 0) > 0:
				hits = swing(swing_item, eye(), -cam.global_basis.z)
			if swing_item.has("pick_power") or swing_item.has("axe_power") or swing_item.has("hammer_power"):
				break_target()
			if hits > 0:
				shake = maxf(shake, 0.4)
			swing_item = {}
	if on_floor and world.get_block(floori(position.x), floori(position.y - 0.1), floori(position.z)) == Blocks.ids.meteorite:
		hurt(METEORITE_BURN, Vector3.ZERO)   # meteorito queima quem pisa (Burning do Terraria)
		Fx.sparks(entities, position + Vector3.UP * 0.2, Color("#ff9a3a"), 2, Vector3.UP)
	mine_idle += delta
	if mine_idle > MINE_DECAY:
		mine_damage = 0.0
		mine_pos = Vector3i(-1, -1, -1)
	for n in buffs.keys():
		buffs[n] -= delta
		if buffs[n] <= 0.0:
			buffs.erase(n)
	if recall_left > 0.0:
		recall_left -= delta
		if entities:
			Fx.sparks(entities, position + Vector3(0, 1.0, 0), Color("#a8e8f8"), 2, Vector3.UP)
		if recall_left <= 0.0:
			_teleport_home()
	_breathe(delta)
	var shine := buff_sum("shine") > 0.0   # Brilho: luz forte de 10 blocos (como uma tocha); Coruja: raio maior e fraco; juntas vale a mais forte
	var owl := buff_sum("owl") > 0.0
	if spelunker:
		spelunker.visible = buff_sum("spelunker") > 0.0
		spelunker.set_process(spelunker.visible)
	world.set_aura(position + Vector3.UP, 10.0 if shine else 15.0, 1.0 if shine else 0.55 if owl else 0.0)
	mana_use += delta
	# regeneração de mana da wiki: (máx/3 + 1) × (2 parado) × (mana/máx × 0,5 + 0,5) × (0,05 usando mana), ÷ 2 por segundo
	var still := 2.0 if Vector2(velocity.x, velocity.z).length() < 0.1 else 1.0
	var cap := mana_cap()
	var rate := (cap / 3.0 + 1.0) * still * (mana / cap * 0.5 + 0.5) * (0.05 if mana_use < 0.5 else 1.0)
	mana = minf(mana + rate / 2.0 * delta, cap)
	since_hit += delta
	if since_hit > REGEN_DELAY:
		hp = minf(hp + delta * (1.0 + inv.acc_sum("regen") + buff_sum("regen")), max_hp)  # ponytail: 1 de vida/s; a regeneração do Terraria é mais complexa


func step(delta: float, wish: Vector3, jump: bool) -> void:
	var boots := 1.0 + inv.acc_sum("speed") + buff_sum("speed")
	var speed := WALK * boots
	if creative:
		velocity = Vector3.ZERO
		position += wish * FLY * boots * delta  # atravessa blocos
		fall_top = position.y
		last_pos = position
		return
	if hook_state != "" and _hook_step(delta, jump):   # preso ao gancho: ele manda no movimento (o resto do passo não roda)
		return
	depth = liquid_depth()
	var kind := liquid_kind_below()
	if velocity.y >= 0.0 or depth > 0.0 or position.distance_to(last_pos) > 4.0:   # sobe, está na água ou foi teletransportado: a queda recomeça daqui (wiki: zera com a velocidade vertical)
		fall_top = position.y
	swimming = depth > SWIM_DEPTH
	var slow := 0.55 if swimming else 0.75 if depth > 0.0 else 1.0
	velocity.x = wish.x * speed * slow + knock.x
	velocity.z = wish.z * speed * slow + knock.z
	knock = knock.move_toward(Vector3.ZERO, 20.0 * delta)
	if swimming:  # nadando: afunda devagar e Espaço sobe; junto de uma margem, perto da superfície, Espaço dá um pulo inteiro
		velocity.y = move_toward(velocity.y, SWIM_UP if jump else -SWIM_SINK, 30.0 * delta)
		if jump and depth < HOP_DEPTH and (hit_wall or on_floor):
			velocity.y = JUMP * (1.0 + inv.acc_sum("jump"))
	else:
		var wings := inv.wings()
		flapping = false
		gliding = false
		if not wings.is_empty():   # asas (wiki Wings): segurar Espaço no ar voa enquanto houver tempo de voo; depois plana; o chão recarrega
			if on_floor or depth > 0.0:
				flight_left = wings.time
			elif jump and flight_left > 0.0:
				flight_left = maxf(flight_left - delta, 0.0)
				velocity.y = move_toward(velocity.y, wings.lift, WING_ACCEL * delta)
				flapping = true
			elif jump and velocity.y < 0.0:
				gliding = true
		if not flapping:
			velocity.y = maxf(velocity.y - GRAVITY * (GLIDE if gliding else 1.0) * delta, -(GLIDE_FALL if gliding else FALL_MAX))
		if jump and on_floor:
			velocity.y = JUMP * (1.0 + inv.acc_sum("jump"))
		if on_floor or depth > 0.0:
			air_jump_ready = inv.has_acc("double_jump")
		elif jump and not jump_was and air_jump_ready:   # Cloud in a Bottle: um pulo a mais no ar, com um aperto novo
			air_jump_ready = false
			velocity.y = JUMP * AIR_JUMP * (1.0 + inv.acc_sum("jump"))
			if entities:
				Fx.puff(entities, position + Vector3(0, 0.2, 0), Color("#e8f0ff"), 8)
				Sfx.play(entities, "flap", position, -6.0, 1.3)
	jump_was = jump
	if depth > 0.0 and kind == Blocks.ids.lava:
		hurt(LAVA_DAMAGE, Vector3.ZERO)
	fall_speed = minf(velocity.y, fall_speed)
	var r := VoxelBody.move(world, position, HALF, TALL, velocity * delta)
	position = r[0]
	var hit: Vector3i = r[1]
	on_floor = hit.y < 0
	hit_wall = hit.x != 0 or hit.z != 0
	if hit.y != 0:
		velocity.y = 0.0
	if on_floor:
		_land()
	last_pos = position
	_effects(delta)


# Pousou: caiu mais que a queda segura (25 tiles) em terra firme e sem asas? 10 de dano por tile a mais, como o dano comum (defesa reduz, dá invencibilidade).
func _land() -> void:
	var tiles := int((fall_top - position.y) / TILE)   # a wiki mede em tiles inteiros
	fall_top = position.y
	if tiles > FALL_SAFE and depth == 0.0 and inv.wings().is_empty() and not inv.has_acc("no_fall") and not creative:
		var taken := hurt((tiles - FALL_SAFE) * 10, Vector3.ZERO, false)
		if taken > 0:
			say("queda de %d tiles" % tiles)


# Fôlego (wiki Breath meter/Drowning): com a cabeça na água gasta 1 s por segundo; a 0 afoga (17 de vida por segundo, direto); fora da água volta rápido.
func _breathe(delta: float) -> void:
	var under: bool = not creative and world.liquid_at(position + Vector3.UP * (EYE + 0.05)) == Blocks.ids.water
	if not under:
		breath = minf(breath + BREATH_REFILL * delta, BREATH)
		drown_text = 0.0
		return
	breath = maxf(breath - delta, 0.0)
	if breath > 0.0:
		return
	hp -= DROWN * delta
	since_hit = 0.0
	drown_text -= delta
	if drown_text <= 0.0 and entities:
		drown_text = 0.5
		entities.spawn_text(position + Vector3.UP * (TALL + 0.4), str(int(DROWN * 0.5)), Color("#ff5058"))
		Sfx.play(entities, "hurt", position + Vector3.UP, -4.0)
	if hp <= 0.0:
		die()


# Gancho (tecla E): o 1º item com "hook" do inventário. Solta a corrente na mira; se ela prende num bloco sólido dentro do alcance, chega depois de distância /
# velocidade de lançamento e puxa o jogador em linha reta até o bloco (fica pendurado a HOOK_HANG dele). E de novo ou Espaço solta; a âncora quebrada também.
func use_hook(aim := Vector3.ZERO) -> void:
	if hook_state != "":
		_hook_release()
		return
	var h := _hook_def()
	if h.is_empty():
		say("sem gancho")
		return
	var dir := aim if aim != Vector3.ZERO else -cam.global_basis.z
	var from := position + Vector3.UP * EYE
	var hit: Dictionary = world.raycast(from, dir, h.range)
	if hit.is_empty() or not Blocks.solid[world.get_block(hit.pos.x, hit.pos.y, hit.pos.z)]:
		say("nada ao alcance do gancho")
		return
	hook_from = from
	hook_at = from + dir * hit.t + dir * 0.02
	hook_state = "fly"
	hook_time = hit.t / h.launch
	Sfx.play(entities, "swing", position + Vector3.UP, -6.0, 1.6)


# Os números ({range, launch, pull}) do primeiro gancho do inventário, ou {}.
func _hook_def() -> Dictionary:
	for id in inv.item:
		if id != -1 and Items.defs[id].has("hook"):
			return Items.defs[id].hook
	return {}


func _hook_release() -> void:
	hook_state = ""
	if hook_rope:
		hook_rope.visible = false


# Um passo com o gancho. Retorna true se ele controlou o movimento deste passo (puxando ou pendurado).
func _hook_step(delta: float, jump: bool) -> bool:
	var anchor := Vector3i(hook_at.floor())
	if hook_state == "fly":
		hook_time -= delta
		if hook_time > 0.0:
			return false
		hook_state = "pull"
		hook_time = 0.0
		Sfx.play(entities, "place", hook_at, -4.0, 1.5)
	if not Blocks.solid[world.get_block(anchor.x, anchor.y, anchor.z)] or _hook_def().is_empty():
		_hook_release()   # a âncora foi quebrada (ou o gancho saiu do inventário)
		return false
	if jump and not jump_was:   # Espaço solta com um pulinho
		_hook_release()
		velocity = Vector3(velocity.x, JUMP * 0.7, velocity.z)
		jump_was = jump
		return false
	var to := hook_at - (position + Vector3.UP * 1.0)
	velocity = Vector3.ZERO if to.length() < HOOK_HANG else to.normalized() * _hook_def().pull
	knock = Vector3.ZERO
	var r := VoxelBody.move(world, position, HALF, TALL, velocity * delta)
	if to.length() >= HOOK_HANG and (r[0] - position).length() < velocity.length() * delta * 0.25:
		hook_time -= delta   # encostou em algo no caminho (hook_time conta o tempo preso): 0,4 s assim e solta
		if hook_time < -0.4:
			_hook_release()
			return false
	else:
		hook_time = 0.0
	position = r[0]
	on_floor = r[1].y < 0
	hit_wall = r[1].x != 0 or r[1].z != 0
	fall_top = position.y
	last_pos = position
	jump_was = jump
	return true


# A corrente entre a mão e a âncora (ou a ponta que está indo).
func _update_rope() -> void:
	if hook_state == "" or hook_rope == null:
		return
	var hand := position + Vector3(0, 1.25, 0)
	var end := hook_at
	if hook_state == "fly":
		var total := maxf(hook_at.distance_to(hook_from), 0.01)
		var sent := clampf(1.0 - hook_time * 25.8 / total, 0.0, 1.0)
		end = hook_from.lerp(hook_at, sent)
	var dir := end - hand
	if dir.length() < 0.05:
		hook_rope.visible = false
		return
	hook_rope.visible = true
	var up := dir.normalized()
	var basis := Basis(Vector3.RIGHT, PI) if up.dot(Vector3.UP) < -0.9999 else Basis(Quaternion(Vector3.UP, up))
	hook_rope.global_transform = Transform3D(basis * Basis.from_scale(Vector3(1, dir.length(), 1)), (hand + end) / 2.0)


# Partículas do movimento: poeira dos passos e do pouso (na cor do chão), respingo ao entrar ou sair da água e bolhas nadando.
func _effects(delta: float) -> void:
	if entities == null:
		return
	if on_floor and not was_on_floor and fall_speed < -7.0 and depth == 0.0:
		Fx.dust(entities, position + Vector3(0, 0.1, 0), _ground_color(), 10, Vector3.UP)
	if on_floor:
		fall_speed = 0.0
		var speed := Vector2(velocity.x, velocity.z).length()
		stride += speed * delta
		if stride > 1.5 and speed > 2.0 and depth == 0.0:
			stride = 0.0
			Fx.dust(entities, position + Vector3(0, 0.08, 0), _ground_color(), 2)
	was_on_floor = on_floor
	if flapping:   # bate as asas: sopro e penas a cada batida
		flap_timer -= delta
		if flap_timer <= 0.0:
			flap_timer = 0.17
			Fx.puff(entities, position + Vector3(0, 1.1, 0), Color("#e8f0ff"), 2)
			Sfx.play(entities, "flap", position + Vector3.UP, -8.0)
	if (depth > 0.3) != (last_depth > 0.3) and absf(velocity.y) > 2.0:
		Fx.splash(entities, position + Vector3(0, maxf(depth, 0.3), 0), 14)
	last_depth = depth
	if swimming:
		bubble_timer -= delta
		if bubble_timer <= 0.0:
			bubble_timer = 0.45
			Fx.bubbles(entities, position + Vector3(0, 1.5, 0))


func _ground_color() -> Color:
	return Blocks.color_of(world.get_block(floori(position.x), floori(position.y - 0.1), floori(position.z)))


# Blocos de líquido acima dos pés (0 = seco): sobe pelos blocos do mesmo líquido e conta até a superfície do último.
func liquid_depth() -> float:
	var x := floori(position.x)
	var z := floori(position.z)
	var y := floori(position.y + 0.05)
	var b: int = world.get_block(x, y, z)
	if not Blocks.liquid[b]:
		return 0.0
	while true:
		var above: int = world.get_block(x, y + 1, z)
		if not (Blocks.liquid[above] and Blocks.liquid_kind[above] == Blocks.liquid_kind[b]):
			break
		b = above
		y += 1
	return maxf(y + Blocks.liquid_height(b) - position.y, 0.0)


# Líquido (id do cheio: water, lava) nos pés, ou 0.
func liquid_kind_below() -> int:
	var b: int = world.get_block(floori(position.x), floori(position.y + 0.05), floori(position.z))
	return Blocks.liquid_kind[b] if Blocks.liquid[b] else 0


# Líquido (id do cheio) no meio do corpo, ou 0.
func liquid_at() -> int:
	return world.liquid_at(position + Vector3.UP * 0.6)


func overlaps_solid(p: Vector3) -> bool:
	return VoxelBody.overlaps(world, p, HALF, TALL)


func held() -> int:
	return inv.item[slot]


func say(text: String) -> void:
	message = text
	message_until = Time.get_ticks_msec() + 2000


# Dano como no Terraria (modo normal): dano − defesa/2 (armadura + bônus de conjunto), mínimo 1.
func hurt(damage: int, dir: Vector3, bounce := true) -> int:   # bounce = false: dano sem empurrão (queda)
	if iframes > 0 or creative:
		return 0
	var taken := maxi(1, damage - ceili(defense() / 2.0))
	hp -= taken
	if entities:
		entities.spawn_text(position + Vector3.UP * (TALL + 0.4), str(taken), Color("#ff5058"))
	iframes = IFRAMES
	since_hit = 0.0
	shake = 1.0
	if inv.has_acc("panic"):   # Panic Necklace: ao levar dano, 8 s com o dobro da velocidade
		add_buff("panic", 8.0)
	Sfx.play(entities, "hurt", position + Vector3.UP, 0.0)
	if bounce:
		knock = Vector3(dir.x, 0, dir.z).normalized() * 6.0
		velocity.y = 5.0
	if hp <= 0:
		die()
	return taken


# Morreu: volta ao spawn com a vida cheia (o mapa marca onde foi).
func die() -> void:
	hp = max_hp
	death = position
	position = spawn
	velocity = Vector3.ZERO
	knock = Vector3.ZERO
	breath = BREATH
	fall_top = position.y
	say("você morreu")


# Mana máxima de verdade: a de base mais o que os acessórios dão (Band of Starpower +40).
func mana_cap() -> int:
	return max_mana + int(inv.acc_sum("max_mana"))


func defense() -> int:
	return inv.defense() + int(buff_sum("defense"))


# Soma do efeito `stat` dos buffs ativos (buffs.json).
func buff_sum(stat: String) -> float:
	var t := 0.0
	for n in buffs:
		t += Buffs.defs[n].get(stat, 0.0)
	return t


func has_buff(name: String) -> bool:
	return buffs.has(name)


# Beber de novo renova o tempo; não soma.
func add_buff(name: String, seconds: float) -> void:
	buffs[name] = maxf(buffs.get(name, 0.0), seconds)


# Tempo de um uso: o do item; a picareta com o buff de Mineração usa ⌊tool speed × (1 − bônus)⌋ quadros (wiki Tool speed; o bônus vale só para picaretas, até 70%).
func use_time(id: int) -> float:
	var t := Items.use_dur(id)
	if Items.pick_power[id] > 0 and has_buff("mining"):
		t = floorf(t * 60.0 * (1.0 - minf(buff_sum("mining"), 0.7))) / 60.0
	return t


# Poção ou espelho do slot i faz o efeito e, sendo consumível, gasta um. false = não deu (Doença da poção).
func consume(i: int) -> bool:
	var id: int = inv.item[i]
	var d: Dictionary = Items.defs[id]
	if d.has("heal"):
		if has_buff("potion_sickness"):
			say("Doença da poção: espere para beber outra de cura")
			return false
		hp = minf(hp + d.heal, max_hp)
		if entities:
			entities.spawn_text(position + Vector3.UP * (TALL + 0.4), "+%d" % d.heal, Color("#5aff6a"))
		add_buff("potion_sickness", SICKNESS)
	if d.has("life"):   # Life Crystal: +20 de vida máxima (e de vida), até 400
		if max_hp >= MAX_HP_CAP:
			say("a vida máxima já é %d" % MAX_HP_CAP)
			return false
		max_hp = mini(max_hp + int(d.life), MAX_HP_CAP)
		hp = minf(hp + d.life, max_hp)
		if entities:
			Fx.puff(entities, position + Vector3(0, 1.0, 0), Color("#ff6a8a"), 12)
		say("vida máxima: %d" % max_hp)
	if d.has("mana_max"):   # Mana Crystal: +20 de mana máxima, até 200
		if max_mana >= MAX_MANA_CAP:
			say("a mana máxima já é %d" % MAX_MANA_CAP)
			return false
		max_mana = mini(max_mana + int(d.mana_max), MAX_MANA_CAP)
		mana = minf(mana + d.mana_max, mana_cap())
		say("mana máxima: %d" % max_mana)
	if d.has("mana"):
		mana = minf(mana + d.mana, mana_cap())
	if d.has("buff"):
		add_buff(d.buff, d.buff_time)
	if d.has("recall"):
		recall_left = d.recall
		say("indo para casa...")
	if d.get("consumable", false):
		Sfx.play(entities, "drink", position + Vector3.UP, -4.0)
		inv.take_one(i)
	return true


# H/Q (wiki Controls): bebe a poção de cura que cobre o que falta com o menor desperdício; se nenhuma cobre, a maior.
func quick_heal() -> void:
	var missing := max_hp - hp
	var best := -1
	for i in Inventory.SIZE:
		var id: int = inv.item[i]
		if id == -1 or not Items.defs[id].has("heal"):
			continue
		var h: int = Items.defs[id].heal
		var b: int = Items.defs[inv.item[best]].heal if best != -1 else 0
		if best == -1 or (h >= missing and (b < missing or h < b)) or (h < missing and b < missing and h > b):
			best = i
	if best == -1:
		say("sem poção de cura")
	else:
		consume(best)


# J: bebe uma poção de mana (a menor que completa o que falta, senão a maior).
func quick_mana() -> void:
	var best := -1
	for i in Inventory.SIZE:
		var id: int = inv.item[i]
		if id == -1 or not Items.defs[id].has("mana"):
			continue
		if best == -1 or (Items.defs[id].mana >= mana_cap() - mana and Items.defs[id].mana < Items.defs[inv.item[best]].mana):
			best = i
	if best == -1:
		say("sem poção de mana")
	else:
		consume(best)


# Magia (wiki Mana): gasta `cost`; sem mana suficiente ainda dá para usar, com 60% de penalidade de velocidade (o ciclo ×1,6).
func cast(d: Dictionary, aim := Vector3.ZERO) -> void:   # aim: a direção (os testes passam; em jogo é a da câmera)
	var cost: float = 0.0 if inv.free_cast(Items.ids[d.name]) else float(d.cost)   # conjunto Meteor: Space Gun sem mana
	if mana >= cost:
		mana -= cost
	else:
		mana = 0.0
		cooldown *= 1.6
		use_len = cooldown
	mana_use = 0.0
	var forward := aim if aim != Vector3.ZERO else -cam.global_basis.z
	var from := position + Vector3.UP * EYE
	if d.has("cloud"):   # Crimson Rod: uma nuvem no ponto da mira (para antes de um bloco) que chove sangue; uma por vez
		var hit: Dictionary = world.raycast(from, forward, d.cloud)
		var at: Vector3 = from + forward * d.cloud if hit.is_empty() else Vector3(hit.pos) + Vector3.ONE * 0.5 + Vector3(hit.normal) * 0.8
		at.y += 2.5
		while Blocks.solid[world.get_block(floori(at.x), floori(at.y), floori(at.z))] and at.y > from.y - 3.0:
			at.y -= 0.5
		entities.spawn_cloud(at, d.damage)
	else:
		entities.spawn_projectile(d.shoot, from + forward * 0.6, forward, d.shoot_speed, d.damage, d.get("knockback", 0.0), d.get("crit", Combat.CRIT))
	Sfx.play(entities, "bow", position + Vector3.UP, -8.0, 1.6)


# B: bebe uma poção de cada buff que não está ativo.
func quick_buff() -> void:
	var drank := 0
	for i in Inventory.SIZE:
		var id: int = inv.item[i]
		if id != -1 and Items.defs[id].has("buff") and not has_buff(Items.defs[id].buff):
			drank += int(consume(i))
	if drank == 0:
		say("sem poção de buff nova")


# Teleporte para casa (o spawn): as partículas saem de onde estava e chegam onde volta.
func _teleport_home() -> void:
	if entities:
		Fx.puff(entities, position + Vector3(0, 1.0, 0), Color("#a8e8f8"), 16)
		Sfx.play(entities, "coin", position, -4.0, 0.7)
	position = spawn
	velocity = Vector3.ZERO
	knock = Vector3.ZERO
	if entities:
		Fx.puff(entities, position + Vector3(0, 1.0, 0), Color("#a8e8f8"), 16)


# Botão esquerdo (wiki Autoswing): cada clique usa o item uma vez (o clique durante o fim do golpe anterior espera até CLICK_BUFFER);
# segurando, só repete o que tem autoswing (ferramentas, blocos, espadas marcadas), no ritmo do use time / tool speed.
func attack(delta: float) -> void:
	attack_buffer = maxf(attack_buffer - delta, 0.0)
	var id := held()
	if cooldown <= 0.0 and (attack_buffer > 0.0 or (attack_held and id != -1 and Items.autoswing(id))):
		attack_buffer = 0.0
		use_item()


# Usa o item da mão: picareta minera, arma com munição atira, arma golpeia, bloco coloca.
func use_item() -> void:
	var id := held()
	if id == -1:
		return
	var d: Dictionary = Items.defs[id]
	cooldown = use_time(id)
	use_len = cooldown
	if d.has("summon"):
		summon(d)
		return
	if d.has("heal") or d.has("buff") or d.has("recall") or d.has("life") or d.has("mana") or d.has("mana_max"):
		consume(slot)
		return
	if d.has("cost"):
		cast(d)
		return
	if d.has("ammo"):
		shoot(d, eye(), -cam.global_basis.z)
	elif d.has("bucket"):
		use_bucket(d)
	elif Items.places[id] != -1:
		place_block()
	elif d.get("damage", 0) > 0 or Items.pick_power[id] > 0 or Items.axe_power[id] > 0:   # a lâmina (ou a picareta) só acerta quando o arco chega à frente (~1/3 do golpe)
		swing_item = d
		swing_timer = cooldown * (0.42 if d.get("use_style") == "thrust" else 0.3)
		Sfx.play(entities, "swing", position + Vector3.UP, -10.0, 1.15 if d.get("use_style") == "thrust" else 0.9)


# Balde: vazio pega o líquido da mira (um bloco); cheio derrama um bloco cheio no ar junto do alvo. O líquido depois flui sozinho (liquid.gd).
func use_bucket(d: Dictionary) -> void:
	if d.bucket == "empty":
		var look := Basis(Vector3.UP, rotation.y) * Basis(Vector3.RIGHT, pitch) * Vector3.FORWARD   # a mira, sem depender da câmera na árvore
		var hit: Dictionary = world.raycast(position + Vector3.UP * EYE, look, REACH, true)
		if hit.is_empty() or not Blocks.liquid[world.get_block(hit.pos.x, hit.pos.y, hit.pos.z)]:
			return
		var kind := Blocks.liquid_kind[world.get_block(hit.pos.x, hit.pos.y, hit.pos.z)]
		world.set_block(hit.pos.x, hit.pos.y, hit.pos.z, 0)
		inv.item[slot] = Items.ids["water_bucket" if kind == Blocks.ids.water else "lava_bucket"]
		inv.version += 1
		Fx.splash(entities, Vector3(hit.pos) + Vector3(0.5, 0.8, 0.5), 8)
		return
	if target.is_empty():
		return
	var p: Vector3i = target.pos + target.normal
	var there: int = world.get_block(p.x, p.y, p.z)
	if there == 0 or Blocks.soft[there]:
		world.set_block(p.x, p.y, p.z, Blocks.ids[d.bucket])
		inv.item[slot] = Items.ids.empty_bucket
		inv.version += 1
		Fx.splash(entities, Vector3(p) + Vector3(0.5, 0.8, 0.5), 8)


# Inimigos que um golpe corpo a corpo alcança: 3 raios (a mira e ±FAN na horizontal) contra a caixa de cada um (alargada em PAD), até `reach`
# do olho. Só vale o que está na mira: sem cone largo e sem acertar quem está atrás; quem os raios atravessam em fila leva junto.
func melee_targets(eye: Vector3, forward: Vector3, reach: float) -> Array:
	var rays := [forward, forward.rotated(Vector3.UP, FAN), forward.rotated(Vector3.UP, -FAN)]
	var found := []
	for e in entities.enemies:
		var w: float = e.half + PAD
		var box := AABB(e.position + Vector3(-w, -PAD, -w), Vector3(2.0 * w, e.tall + 2.0 * PAD, 2.0 * w))
		if box.has_point(eye):   # encostado: vale se olha para ele
			if forward.dot(box.get_center() - eye) > 0.0:
				found.append(e)
			continue
		for r in rays:
			var at = box.intersects_ray(eye, r)
			if at != null and eye.distance_to(at) <= reach:
				found.append(e)
				break
	return found


# O golpe acerta o que melee_targets acha. O feixe das espadas mágicas (Terra Blade) sai junto, na direção da mira.
func swing(d: Dictionary, eye: Vector3, forward: Vector3) -> int:
	var hits := melee_targets(eye, forward, d.reach)
	for e in hits:
		e.hurt(Combat.vary(d.damage, entities.rng), forward, d.knockback, Combat.is_crit(entities.rng))
	if d.has("shoot"):
		entities.spawn_projectile(d.shoot, eye + forward * 0.8, forward, d.shoot_speed, d.damage, d.knockback)
	return hits.size()


# Invocador de chefe (ex.: Suspicious Looking Eye): só à noite e com um chefe por vez.
# Há lava a até r blocos dos pés?
func _lava_near(r: int) -> bool:
	var p := Vector3i(position.floor())
	for y in range(p.y - r, p.y + r + 1):
		for z in range(p.z - r, p.z + r + 1):
			for x in range(p.x - r, p.x + r + 1):
				if Blocks.liquid_kind[world.get_block(x, y, z)] == Blocks.ids.lava and Blocks.liquid[world.get_block(x, y, z)]:
					return true
	return false


func summon(d: Dictionary) -> void:
	if d.get("underworld", false) and not (position.y < WorldGen.UNDERWORLD_TOP and _lava_near(3)):
		say("jogue a boneca na lava, no submundo")
	elif d.get("night", false) and not clock.is_night():
		say("nada acontece... (só à noite)")
	elif entities.boss:
		say("já há um chefe")
	else:
		var b: Node3D = entities.spawn_boss(d.summon)
		inv.take_one(slot)
		say("%s despertou!" % b.def.name.replace("_", " "))


func shoot(d: Dictionary, eye: Vector3, forward: Vector3) -> void:
	var ammo := inv.take_ammo(d.ammo)
	if ammo == -1:
		say("sem munição (%s)" % d.ammo)
		return
	var dmg: int = d.damage + Items.defs[ammo].get("damage", 0)
	var kb: float = d.knockback + Items.defs[ammo].get("knockback", 0.0)   # wiki Knockback: arma + munição
	var speed: float = d.shoot_speed
	if d.ammo == "arrow":   # Arquearia: +10% de dano e +20% de velocidade nas flechas
		dmg = roundi(dmg * (1.0 + buff_sum("arrow_damage")))
		speed *= 1.0 + buff_sum("arrow_speed")
	entities.spawn_projectile(Items.defs[ammo].projectile, eye, forward, speed, dmg, kb)
	Sfx.play(entities, "bow", position + Vector3.UP, -8.0, 1.0 if d.ammo == "arrow" else 2.2)   # a flecha estala, a bala é um estampido agudo


# Um golpe da picareta no bloco da mira, como no Terraria: cada golpe soma ao bloco (poder da picareta × dureza dele) e ele racha
# até 100, quando quebra e o drop cai como item solto. A grama absorve o golpe que a quebraria: vira terra, ainda rachada.
# Bloco que a picareta não alcança (poder abaixo do mínimo) só avisa.
func break_target() -> void:
	if target.is_empty():
		return
	var p: Vector3i = target.pos
	var b: int = world.get_block(p.x, p.y, p.z)
	var power := Items.power_on(held(), b) if held() != -1 else 0   # tronco: só o machado; orbe e coração: só o martelo; o resto, a picareta
	if not Blocks.breakable[b]:
		return
	if power == 0:
		say("precisa de um machado" if Blocks.axe[b] == 1 else "precisa de um martelo" if Blocks.hammer[b] == 1 else "segure uma picareta")
		return
	if b == Blocks.ids.chest and Array(world.chest_at(p).item).any(func(id): return id != -1):
		say("esvazie o baú primeiro")
		return
	if Blocks.guard[b] > power and not world.skeletron_down:
		say("os tijolos do dungeon resistem (poder %d, ou derrote o Skeletron)" % Blocks.guard[b])
		return
	if power < Blocks.power[b]:
		say("%s precisa de picareta com poder %d (a sua: %d)" % [Blocks.ids.keys()[b].replace("_", " "), Blocks.power[b], power])
		return
	if p != mine_pos:
		mine_pos = p
		mine_damage = 0.0
	mine_idle = 0.0
	var normal := Vector3(target.normal)
	var face := Vector3(p) + Vector3.ONE * 0.5 + normal * 0.5
	var color := Blocks.color_of(b)
	var hard := Blocks.mine[b] <= 1.0   # pedra e minério soltam faíscas
	var tree: bool = b == Blocks.ids.wood and Timber.is_tree(world, p)   # árvore: 100 de vida por tile e ⌊poder × 24%⌋ por golpe (wiki Axe power)
	var damage: float = floori(power * Timber.HIT) if tree else power * Blocks.mine[b]
	if b == Blocks.ids.grass and mine_damage + damage >= 100.0:
		world.set_block(p.x, p.y, p.z, Blocks.ids.dirt)
		Fx.dust(entities, face, color, 6, normal)
		return
	mine_damage += damage
	if mine_damage < 100.0:
		Fx.dust(entities, face, color, 7, normal)
		Sfx.play(entities, "stone" if Blocks.mine[b] <= 1.0 else "dig", face)
		if hard:
			Fx.sparks(entities, face, Color("#ffe27a"), 2, normal)
		if tree:
			Timber.rustle(entities, world, p)
		shake = maxf(shake, 0.15)
		return
	if tree:   # o tile quebrou: cai ele e tudo o que está em cima (na base, a árvore inteira)
		Timber.fell(entities, p, power, position)
		mine_damage = 0.0
		mine_pos = Vector3i(-1, -1, -1)
		shake = maxf(shake, 0.3)
		return
	world.set_block(p.x, p.y, p.z, 0)
	world.chests.erase(p)
	if b == Blocks.ids.shadow_orb or b == Blocks.ids.crimson_heart:
		entities.orb_broken(b, Vector3(p) + Vector3(0.5, 0.2, 0.5))
	mine_damage = 0.0
	mine_pos = Vector3i(-1, -1, -1)
	if Items.drop[b] != -1:
		entities.spawn_drop(Items.drop[b], 1, Vector3(p) + Vector3(0.5, 0.2, 0.5))
	Fx.chips(entities, Vector3(p) + Vector3.ONE * 0.5, color, 12)
	Sfx.play(entities, "break", Vector3(p) + Vector3.ONE * 0.5)
	if hard:
		Fx.sparks(entities, face, Color("#ffe27a"), 5, normal)
	shake = maxf(shake, 0.3)


# Botão direito: interage com o que está na mira (NPC, baú), como no Terraria; colocar bloco é o botão esquerdo (use_item).
func interact() -> void:
	var npc: Node3D = entities.npc_aimed(REACH)
	if npc:
		entities.talk(npc)
	elif target.is_empty():
		return
	elif world.get_block(target.pos.x, target.pos.y, target.pos.z) == Blocks.ids.chest:
		set_inventory(true)   # o baú abre o inventário com o painel do baú
		Sfx.play(entities, "place", Vector3(target.pos) + Vector3.ONE * 0.5, -6.0, 1.6)
		get_parent().get_node("HUD").open_chest(world.chest_at(target.pos))
	elif world.get_block(target.pos.x, target.pos.y, target.pos.z) in [Blocks.door_closed, Blocks.door_open]:
		toggle_door(target.pos)
	elif world.get_block(target.pos.x, target.pos.y, target.pos.z) == Blocks.ids.chair:
		say(Housing.report(world, target.pos))   # a cadeira diz se a casa vale


# Abre ou fecha a porta em p (e a que está em cima ou embaixo, para o vão de 2 blocos). A aberta não tem colisão; as duas são parede na moradia.
func toggle_door(p: Vector3i) -> void:
	var to: int = Blocks.door_open if world.get_block(p.x, p.y, p.z) == Blocks.door_closed else Blocks.door_closed
	for dy in [0, 1, -1]:
		var q := p + Vector3i(0, dy, 0)
		if dy == 0 or world.get_block(q.x, q.y, q.z) in [Blocks.door_closed, Blocks.door_open]:
			world.set_block(q.x, q.y, q.z, to)
	Sfx.play(entities, "place", Vector3(p) + Vector3.ONE * 0.5, -4.0, 0.8 if to == Blocks.door_open else 1.1)


func place_block() -> void:
	if target.is_empty() or held() == -1 or Items.places[held()] == -1:
		return
	if Items.places[held()] == Blocks.sapling and not (target.normal == Vector3i.UP and Blocks.grassy[world.get_block(target.pos.x, target.pos.y, target.pos.z)] == 1):
		say("a muda só pega em cima da grama")
		return
	var p: Vector3i = target.pos + target.normal
	var lo := Vector3i((position + LO).floor())
	var hi := Vector3i((position + HI - Vector3.ONE * EPS).floor())
	var inside := p.x >= lo.x and p.x <= hi.x and p.y >= lo.y and p.y <= hi.y and p.z >= lo.z and p.z <= hi.z
	var there: int = world.get_block(p.x, p.y, p.z)
	if not inside and (there == 0 or Blocks.soft[there]):  # ar, planta ou líquido: o bloco novo substitui
		Sfx.play(entities, "place", Vector3(p) + Vector3.ONE * 0.5)
		world.set_block(p.x, p.y, p.z, Items.places[held()])
		inv.take_one(slot)
		place_anim = 0.18


# Auto Select (Shift): segurado, a mão vai para a melhor ferramenta da hotbar para o bloco da mira (machado no tronco, picareta no resto)
# ou, sem bloco na mira, para uma tocha; ao soltar volta ao slot de antes. Sem ferramenta adequada não troca.
func auto_pick(hold: bool) -> void:
	if not hold:
		if auto_prev != -1:
			slot = auto_prev
			auto_prev = -1
		return
	var b: int = world.get_block(target.pos.x, target.pos.y, target.pos.z) if not target.is_empty() else 0
	var best := -1
	var best_score := 0
	for i in Inventory.HOTBAR:
		var id: int = inv.item[i]
		if id == -1:
			continue
		var score := 0
		if b == 0:
			score = 1 if Items.places[id] == Blocks.ids.torch else 0
		elif Blocks.breakable[b]:
			score = Items.power_on(id, b)
		if score > best_score:   # empate: fica o primeiro slot
			best = i
			best_score = score
	if best != -1 and best != slot:
		if auto_prev == -1:
			auto_prev = slot
		slot = best
