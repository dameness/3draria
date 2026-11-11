extends Node3D
# Servidor dedicado (M3): .tools/godot --headless -- --server [porta] [arquivo.wld]
# World sem malha (não há câmera), DayNight, Entities (inimigos, itens no chão; M4a) e Net; sem jogador nem HUD (Fx.muted: sem efeitos nem modelos). Mundo padrão: user://worlds/servidor.wld (criado e assado na primeira vez).
# M5: salva o mundo a cada 5 min e ao encerrar, com uma cópia por dia (7 dias) do mundo e das contas em Net.root/backups/. Senha do servidor: variável DRARIA_PASSWORD.
# ponytail: a gravação (~14 MB) bloqueia o quadro por um instante, upgrade: thread.
const SAVE_EVERY := 300.0
const BACKUPS := 7
const KEEP := 14          # chunks em volta de cada jogador que ficam na memória a cada gravação (inimigos somem a 64 blocos; visão máx. 16 → esses voltam por get_block)

var path := ""
var timer := SAVE_EVERY
var stop_tick := 1.0
var quit_at := 0          # ms: encerrando (os clientes foram avisados e têm 2 s para mandar o personagem)
# Encerrar com calma: criar o arquivo Net.root/stop (o ExecStop do systemd faz isso e espera o processo sair). O Godot headless não entrega o SIGTERM ao script
# (o processo morre direto, testado), então o SIGTERM seco perde até 5 min do mundo (as contas já estão em disco).


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if "--server" in args:   # nos testes a cena é montada sem argumentos e o teste chama net.host
		var i := args.find("--server")
		var port: int = int(args[i + 1]) if args.size() > i + 1 and args[i + 1].is_valid_int() else $Net.PORT
		start(args[-1] if args[-1].ends_with(".wld") else SaveGame.worlds_dir + "servidor.wld", port)


# Carrega o mundo (já assado) e acha o nascimento.
func open(world_path: String) -> bool:
	path = world_path
	var net: Node = $Net
	net.key = path.get_file()
	SaveGame.load_world($World, net, $DayNight, path)
	if $World.test_world:   # o mundo de teste e o painel F9 são de um jogador só
		push_error("mundo de teste não abre no servidor: " + path)
		get_tree().quit(1)
		return false
	if net.spawn == Vector3.ZERO:
		var mid := WorldGen.SIZE_CHUNKS * WorldGen.CHUNK / 2
		net.spawn = Vector3(mid + 0.5, $World.surface_y(mid, mid), mid + 0.5)
	return true


func start(world_path: String, port: int) -> void:
	Engine.max_fps = 60
	DirAccess.make_dir_recursive_absolute($Net.root)   # (o arquivo `stop` vai aqui)
	if not FileAccess.file_exists(world_path):
		DirAccess.make_dir_recursive_absolute(world_path.get_base_dir())
		SaveGame._write(world_path, {"version": SaveGame.VERSION, "name": world_path.get_file().get_basename(), "seed": randi(), "size": WorldGen.SIZE_CHUNKS, "time": 60.0, "chunks": {}})
	if Baker.needs(world_path):
		print("assando o mundo (alguns minutos, só desta vez)...")
		var b := Baker.new(world_path)
		b.start()
		while not b.done():
			OS.delay_msec(1000)
			print("  %d%%" % int(b.progress() * 100))
		b.finish()
	if not open(world_path):
		return
	var net: Node = $Net
	net.password = OS.get_environment("DRARIA_PASSWORD")
	var err: Error = net.host(port)
	if err != OK:   # porta ocupada: sair com erro (o systemd reinicia) em vez de ficar de pé sem escutar
		push_error("não abriu a porta %d: %s" % [port, error_string(err)])
		get_tree().quit(1)
		return
	print("servidor na porta %d (%s), mundo %s, versão %s, %s" % [port, error_string(err), world_path, net.version, "com senha" if net.password != "" else "SEM senha (defina DRARIA_PASSWORD)"])


func _process(delta: float) -> void:
	timer -= delta
	stop_tick -= delta
	if stop_tick <= 0.0:
		stop_tick = 1.0
		if FileAccess.file_exists($Net.root + "stop") and path != "" and quit_at == 0:
			DirAccess.remove_absolute($Net.root + "stop")
			$Net.closing()
			quit_at = Time.get_ticks_msec() + 2000
	if quit_at != 0 and Time.get_ticks_msec() >= quit_at:
		quit_at = 0
		save()
		get_tree().quit()
	if timer <= 0.0:
		save()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:   # fechar a janela (servidor com tela, em teste)
		save()


# Grava o mundo (as contas já foram gravadas quando o cliente mandou). Atômico: .tmp + rename (SaveGame._write).
func save() -> void:
	timer = SAVE_EVERY
	if path == "":
		return
	_backup()
	var err := SaveGame._write(path, SaveGame.world_out($World, $Net, $DayNight, path.get_file().get_basename()))
	$World.trim($Entities.remotes.map(func(p): return $Net._chunk_of(p.position.x, p.position.z)), KEEP)   # (não há câmera para tirar da memória os chunks longe de todos)
	print("mundo salvo (%s)" % error_string(err))


# Uma cópia por dia do que estava no disco antes da primeira gravação do dia (mundo e contas); só as BACKUPS últimas ficam.
func _backup() -> void:
	var base: String = $Net.root + "backups/"
	var dir := base + Time.get_date_string_from_system() + "/"
	if DirAccess.dir_exists_absolute(dir):
		return
	DirAccess.make_dir_recursive_absolute(dir)
	if FileAccess.file_exists(path):
		DirAccess.copy_absolute(path, dir + path.get_file())
	var plr: String = $Net.root + "players/"
	for f in DirAccess.get_files_at(plr) if DirAccess.dir_exists_absolute(plr) else []:
		DirAccess.copy_absolute(plr + f, dir + f)
	var days := Array(DirAccess.get_directories_at(base))
	days.sort()
	for d in days.slice(0, maxi(0, days.size() - BACKUPS)):
		for f in DirAccess.get_files_at(base + d):
			DirAccess.remove_absolute(base + d + "/" + f)
		DirAccess.remove_absolute(base + d)
