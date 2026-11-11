extends Node3D
# Outro jogador visto daqui (M2). Não pensa nem anda sozinho: o dono (o cliente dele, na M3) manda posição, pose, mão, vida e armadura.
# No cliente é o boneco de quem está perto (net.puppets); no servidor (M4a) é o alvo dos inimigos, sem modelo (`peer` = o dono).
# É o contrato do "jogador visto de fora": só o que inimigos (enemy.gd), projéteis inimigos (projectile.gd), itens no chão
# (item_drop.gd), explosões e chefes (entities.gd) e o boneco (player_model.gd) leem. Entra em entities.remotes.

const HALF := 0.3   # caixa igual à do player.gd
const TALL := 1.8
const EYE := 1.62
const IFRAMES := 0.67   # = player.gd
const PlayerModel := preload("res://scripts/player_model.gd")

var entities: Node3D
var velocity := Vector3.ZERO
var pitch := 0.0           # olhar para cima/baixo (a cabeça do boneco)
var cooldown := 0.0        # golpe em andamento (o braço do boneco)
var on_floor := true
var swimming := false
var dead := 0.0            # > 0: morto esperando (não é alvo de item; ainda conta para inimigos, como o player.gd)
var ghost := false
var sleeping := false      # deitado na cama (servidor: a hora só acelera com todos dormindo)
var hp := 100.0
var max_hp := 100
var mana := 20.0
var mana_max := 20         # (o mana_cap() do dono, que vem no estado)
var peer := 0              # servidor: o id de rede do dono (0 = teste sem rede)
var safe_until := 0        # servidor: ms até quando um golpe novo não é repassado (os quadros de invencibilidade do dono)
var hand := -1             # item na mão
var inv := Inventory.new()   # equip (armadura que o boneco veste e que dá a defesa) e o que ele recolhe do chão
var flail_snap := 0.0
var hits: Array = []       # [dano, direção] que levou aqui (no servidor também vai ao dono pelo RPC `hurt`: a vida é dele)
var model: Node3D


func _ready() -> void:
	if Fx.muted(self):
		return
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


func mana_cap() -> int:
	return mana_max


# O dono aplica a defesa, os quadros de invencibilidade e o empurrão; aqui fica anotado e, no servidor, vai a ele
# (no máximo um a cada IFRAMES: encostado num inimigo seriam 60 por segundo).
func hurt(damage: int, dir: Vector3, bounce := true) -> int:
	hits.append([damage, dir])
	if peer and dead <= 0.0 and Time.get_ticks_msec() >= safe_until:
		safe_until = Time.get_ticks_msec() + int(IFRAMES * 1000)
		entities.net.hurt.rpc_id(peer, damage, dir, bounce)
	return damage


func pickup(_pk: Dictionary) -> void:
	pass   # coração/estrela: a cura é do dono (M4a)
