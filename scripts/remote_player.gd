extends Node3D
# Outro jogador visto daqui (M2). Não pensa nem anda sozinho: o dono (o cliente dele, na M3) manda posição, pose, mão e armadura.
# É o contrato do "jogador visto de fora": só o que inimigos (enemy.gd), projéteis inimigos (projectile.gd), itens no chão
# (item_drop.gd), explosões e chefes (entities.gd) e o boneco (player_model.gd) leem. Entra em entities.remotes.

const HALF := 0.3   # caixa igual à do player.gd
const TALL := 1.8
const EYE := 1.62
const PlayerModel := preload("res://scripts/player_model.gd")

var entities: Node3D
var velocity := Vector3.ZERO
var pitch := 0.0           # olhar para cima/baixo (a cabeça do boneco)
var cooldown := 0.0        # golpe em andamento (o braço do boneco)
var on_floor := true
var swimming := false
var dead := 0.0            # > 0: morto esperando (não é alvo de item; ainda conta para inimigos, como o player.gd)
var ghost := false
var hp := 100.0
var max_hp := 100
var hand := -1             # item na mão
var inv := Inventory.new()   # equip (armadura que o boneco veste e que dá a defesa) e o que ele recolhe do chão
var flail_snap := 0.0
var hits: Array = []       # [dano, direção] que levou aqui. ponytail: na M4a vira o RPC `hurt` ao dono (a vida é dele)
var model: Node3D


func _ready() -> void:
	model = PlayerModel.new()
	model.player = self
	add_child(model)


func held() -> int:
	return hand


func eye() -> Vector3:
	return position + Vector3.UP * EYE


func defense() -> int:
	return inv.defense()


func flail_state() -> String:
	return ""


# O dono aplica a defesa, os quadros de invencibilidade e o empurrão; aqui só fica anotado.
func hurt(damage: int, dir: Vector3, _bounce := true) -> int:
	hits.append([damage, dir])
	return damage


func pickup(_pk: Dictionary) -> void:
	pass   # coração/estrela: a cura é do dono (M4a)
