extends SceneTree
# Gera docs/LEVAS.md: o inventário de modelos voxel por leva, lido dos JSON (nada à mão). O teste (tests/run.gd) confere que o arquivo
# está em dia. Uso: .tools/godot --headless -s scripts/voxel/levas.gd
# Leva 0 = infra + pilotos; 1 estruturas; 2 armaduras; 3 armas; 4 inimigos; 5 chefes. Status: "receita" (entrada em models.json ou campo
# model) ou "auto" (sprite inflado, já no jogo); inimigos e chefes: bb / procedural / sem modelo. Itens de blocos com forma (torch, door...) contam como estrutura.

const PATH := "res://docs/LEVAS.md"
const SHAPES := ["model", "door", "torch", "rope", "track", "crystal"]
const BOSS_ORDER := ["king_slime", "eye_of_cthulhu", "eater_of_worlds", "brain_of_cthulhu", "queen_bee", "skeletron", "wall_of_flesh"]   # progressão da wiki
const FURNITURE := ["chest", "chair", "door", "workbench", "anvil", "furnace", "hellforge", "demon_altar"]


static func text() -> String:
	Blocks.load_pack()
	Items.load_pack()
	var specs := VoxRecipes.specs()
	var stations := {}
	for r in Blocks.read("res://data/base/recipes.json"):
		if r.has("station"):
			stations[r.station] = true
	var levas := {1: [], 2: [], 3: [], 4: [], 5: []}
	for n in Blocks.ids:
		var b: int = Blocks.ids[n]
		if n in FURNITURE or stations.has(n) or Blocks.shape[b] in SHAPES:
			levas[1].append([n, Blocks.model[b] != ""])
	for k in Items.sets:
		levas[2].append([k, Items.sets[k].model != ""])
	for d in Items.defs:
		if d.get("damage", 0) > 0 and not d.has("armor") and not d.has("pick_power") and not d.has("axe_power") and not d.has("hammer_power"):
			levas[3].append([d.name, d.has("model") or specs.has(d.name)])
	for e in Blocks.read("res://data/base/enemies.json"):
		if not (e.name.ends_with("_body") or e.name.ends_with("_tail")):   # segmentos de verme contam pela cabeça
			var m: String = e.get("model", "")
			levas[5 if e.get("boss", false) else 4].append([e.name, "bb" if m.begins_with("bb:") else ("procedural" if m != "" else "sem modelo")])
	var names := {1: "Estruturas", 2: "Armaduras (por conjunto)", 3: "Armas", 4: "Inimigos", 5: "Chefes"}
	var out := "# Levas do visual Voxel (gerado por `scripts/voxel/levas.gd` a partir dos JSON; não edite)\n\n"
	out += "Leva 0 (infra + pilotos): `scripts/voxel/`, corpo do personagem, Living Loom, conjunto Molten.\n"
	out += "Status: **receita** = tem modelo próprio (models.json / campo `model`); **auto** = sprite inflado, já vale no jogo.\n\n"
	for l in levas:
		var list: Array = levas[l]
		if l >= 4:
			out += foes(l, names[l], list)
			continue
		var done := list.filter(func(x): return x[1])
		out += "## Leva %d — %s (%d, %d com receita)\n" % [l, names[l], list.size(), done.size()]
		out += "- receita: %s\n" % (", ".join(done.map(func(x): return x[0])) if not done.is_empty() else "—")
		out += "- auto: %s\n\n" % ", ".join(list.filter(func(x): return not x[1]).map(func(x): return x[0]))
	out += "## Regra para conteúdo futuro\n"
	out += "- Todo item, bloco e estrutura novo nasce com modelo **automático** (o sprite da wiki inflado): não precisa fazer nada, já tem volume.\n"
	out += "- Só o que merece destaque ganha **receita**: entrada em `data/<pacote>/models.json` (sprite da wiki, cores emissivas) + função em `scripts/voxel/recipes.gd`,\n"
	out += "  e o campo `\"model\": \"nome\"` no item/bloco/conjunto. Critério de destaque: chefe, arma de raridade alta ou com efeito visual, estrutura grande (tamanho em tiles ≥ 2x2), conjunto de armadura com brilho.\n"
	out += "- Inimigo/chefe com rig e animação: Blockbench, só em sessão local (`\"model\": \"bb:nome\"` + `\"fallback\"` procedural no enemies.json; ver CLAUDE.md).\n"
	out += "- Retoque à mão: salve o `.vox` em `assets/models/` (prioridade sobre o gerado em `assets/models/gen/`). Ver `docs/VOXEL_STYLE.md`.\n"
	return out


# Leva 4/5: pelo campo "model" do JSON — bb (feito no Blockbench, só em sessão local), procedural (enemy_model.gd) ou sem modelo (sprite extrudado).
static func foes(l: int, title: String, list: Array) -> String:
	var kinds := ["bb", "procedural", "sem modelo"]
	var count := kinds.map(func(k): return "%d %s" % [list.filter(func(x): return x[1] == k).size(), k])
	var out := "## Leva %d — %s (%d: %s)\n" % [l, title, list.size(), ", ".join(count)]
	for k in kinds:
		out += "- %s: %s\n" % [k, ", ".join(list.filter(func(x): return x[1] == k).map(func(x): return x[0]))]
	if l == 5:
		var names := list.map(func(x): return x[0])
		var order := BOSS_ORDER.filter(func(n): return n in names)
		var rest := names.filter(func(n): return n not in order)
		out += "- ordem sugerida (progressão; as partes ficam com o chefe): %s; partes: %s\n" % [" → ".join(order), ", ".join(rest)]
	return out + "\n"


func _init() -> void:
	FileAccess.open(PATH, FileAccess.WRITE).store_string(text())
	print("docs/LEVAS.md atualizado")
	quit()
