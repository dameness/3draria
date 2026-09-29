class_name Buffs
# Buffs e debuffs (data/base/buffs.json): cada um soma um efeito nos atributos do jogador (defense, speed, regen, mining, arrow_damage,
# arrow_speed; player.buff_sum) enquanto durar. player.buffs guarda os segundos que restam de cada um; beber de novo renova o tempo (não soma).

static var defs := {}


static func load_pack(dir := "res://data/base") -> void:
	defs = Blocks.read(dir + "/buffs.json")


# "7:59" ou "45s" para o ícone do HUD.
static func time_text(seconds: float) -> String:
	var s := ceili(seconds)
	return "%d:%02d" % [s / 60, s % 60] if s >= 60 else "%ds" % s
