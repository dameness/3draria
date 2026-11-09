class_name Difficulty
# Dificuldade do personagem (data/base/difficulties.json; wiki Difficulty): só muda o que se perde ao morrer. `coins` = fração das moedas que cai,
# `drop_all` = cai tudo (Mediumcore/Hardcore), `ghost` = a morte é permanente (Hardcore). O personagem guarda a chave em .plr ("classic" é o padrão).

const DEFAULT := "classic"
static var defs := {}


static func load_pack(dir := "res://data/base") -> void:
	defs = Blocks.read(dir + "/difficulties.json")
