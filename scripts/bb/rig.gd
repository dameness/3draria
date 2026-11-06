class_name BbRig
extends RefCounted
# Modelo de inimigo em ossos + animações, gerado por script (sem o Blockbench; ver docs/BB.md). Cada osso tem um VoxModel pintado em coordenadas
# GLOBAIS do modelo, em células (MagicaVoxel: x largura, y profundidade com a frente em y menor, z altura; pés em z = 0 ou `center` na origem).
# 1 célula = `k` texels (1 texel = 1 pixel do sprite = 0,0375 bloco). Os nomes dos ossos e dos clipes são os que enemy_model.gd espera
# (idle, move, attack, hurt, death, phase2; grupos iris e mouth). build.gd monta a cena e grava o .glb.

const LOOPED := ["idle", "move", "attack", "phase2"]

var k := 1
var center := Vector3.ZERO   # ponto (em células) que vira a origem do modelo
var bones := {}              # nome → {parent, pivot (células), vox}
var anims := {}              # nome → {length, tracks: {osso: {rot|pos|scl: [[t, Vector3]]}}}


# Cria o osso (pivô em células, no quadro global) e devolve o VoxModel onde pintar.
func bone(name: String, parent: String, pivot: Vector3) -> VoxModel:
	var m := VoxModel.new()
	bones[name] = {"parent": parent, "pivot": pivot, "vox": m}
	return m


func anim(name: String, length: float) -> void:
	anims[name] = {"length": length, "tracks": {}}


# kind: "rot" (graus, eixos do Godot: x lado, y cima, z trás), "pos" (células, deslocamento do repouso) ou "scl" (escala).
func track(a: String, b: String, kind: String, keys: Array) -> void:
	var t: Dictionary = anims[a].tracks
	if not t.has(b):
		t[b] = {}
	t[b][kind] = keys


# Ciclo fechado: base + amp × sen(2π (ciclos × t/T + fase)), 12 amostras (a última repete a primeira: o loop não salta).
func sway(a: String, b: String, kind: String, amp: Vector3, phase := 0.0, cycles := 1, base := Vector3.ZERO) -> void:
	var keys := []
	var T: float = anims[a].length
	for i in 13:
		keys.append([T * i / 12.0, base + amp * sin(TAU * (cycles * i / 12.0 + phase))])
	track(a, b, kind, keys)


# Disparo único: tempos em fração da duração, valores em [fração, Vector3].
func shot(a: String, b: String, kind: String, keys: Array) -> void:
	var T: float = anims[a].length
	var out := []
	for kv in keys:
		out.append([T * kv[0], kv[1]])
	track(a, b, kind, out)


# hurt (esmaga e treme) e death (gira, incha e some) padrão para o osso raiz.
func std_hurt(b: String, length := 0.25) -> void:
	anim("hurt", length)
	shot("hurt", b, "scl", [[0.0, Vector3.ONE], [0.3, Vector3(1.14, 0.86, 1.14)], [0.65, Vector3(0.95, 1.06, 0.95)], [1.0, Vector3.ONE]])
	shot("hurt", b, "rot", [[0.0, Vector3.ZERO], [0.3, Vector3(0, 0, -9)], [0.65, Vector3(0, 0, 6)], [1.0, Vector3.ZERO]])


func std_death(b: String, length := 0.6, spin := 360.0) -> void:
	anim("death", length)
	var s := []
	var r := []
	for i in 9:
		var f := i / 8.0
		s.append([f, Vector3.ONE * (1.0 + 0.2 * sin(f * PI) - f * f * 1.0)])
		r.append([f, Vector3(0, spin * f, 0)])
	shot("death", b, "scl", s)
	shot("death", b, "rot", r)
