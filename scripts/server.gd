extends Node3D
# Servidor dedicado (M3): .tools/godot --headless -- --server [porta] [arquivo.wld]
# World sem malha (não há câmera), DayNight e Net; sem jogador nem HUD. Mundo padrão: user://worlds/servidor.wld (criado e assado na primeira vez).
# ponytail: M3 não salva o mundo (M5: a cada 5 min e ao encerrar) nem tira chunk da memória (só os que alguém editou/visitou ficam; teto = o mundo, 472 MB).


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if "--server" in args:   # nos testes a cena é montada sem argumentos e o teste chama net.host
		var i := args.find("--server")
		var port: int = int(args[i + 1]) if args.size() > i + 1 and args[i + 1].is_valid_int() else $Net.PORT
		var path: String = args[-1] if args[-1].ends_with(".wld") else SaveGame.worlds_dir + "servidor.wld"
		start(path, port)


func start(path: String, port: int) -> void:
	Engine.max_fps = 60
	if not FileAccess.file_exists(path):
		DirAccess.make_dir_recursive_absolute(path.get_base_dir())
		SaveGame._write(path, {"version": SaveGame.VERSION, "name": path.get_file().get_basename(), "seed": randi(), "size": WorldGen.SIZE_CHUNKS, "time": 60.0, "chunks": {}})
	if Baker.needs(path):
		print("assando o mundo (alguns minutos, só desta vez)...")
		var b := Baker.new(path)
		b.start()
		while not b.done():
			OS.delay_msec(1000)
			print("  %d%%" % int(b.progress() * 100))
		b.finish()
	var net: Node = $Net
	SaveGame.load_world($World, net, $DayNight, path)
	if net.spawn == Vector3.ZERO:
		var mid := WorldGen.SIZE_CHUNKS * WorldGen.CHUNK / 2
		net.spawn = Vector3(mid + 0.5, $World.surface_y(mid, mid), mid + 0.5)
	var err: Error = net.host(port)
	print("servidor na porta %d (%s), mundo %s, versão %s" % [port, error_string(err), path, net.version])
