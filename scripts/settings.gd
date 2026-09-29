class_name Settings
# Opções do jogador (botão Configurações do inventário): valem para qualquer personagem e mundo e ficam em user://settings.cfg.
# O menu liga `path` e carrega; sem caminho (testes, rodar game.tscn direto) valem os padrões e nada é lido nem gravado.

const DISTANCE := Vector2i(2, 16)     # distância de renderização, em chunks
const SENS := Vector2(0.25, 3.0)      # multiplicador da sensibilidade do mouse

static var path := ""
static var render_distance := 6
static var volume := 1.0              # 0-1: multiplica todos os sons
static var mouse_sens := 1.0


static func load_file() -> void:
	var cfg := ConfigFile.new()
	if path == "" or cfg.load(path) != OK:
		return
	render_distance = clampi(cfg.get_value("game", "render_distance", render_distance), DISTANCE.x, DISTANCE.y)
	volume = clampf(cfg.get_value("game", "volume", volume), 0.0, 1.0)
	mouse_sens = clampf(cfg.get_value("game", "mouse_sens", mouse_sens), SENS.x, SENS.y)


static func save() -> void:
	if path == "":
		return
	var cfg := ConfigFile.new()
	cfg.set_value("game", "render_distance", render_distance)
	cfg.set_value("game", "volume", volume)
	cfg.set_value("game", "mouse_sens", mouse_sens)
	cfg.save(path)
