extends SceneTree
# Prévia das dicas dos itens (o balão do Terraria), sem abrir o jogo:
#   xvfb-run -a -s "-screen 0 1280x720x24" .tools/godot -s tests/tooltips.gd [-- item1 item2 ...]
# Salva textures/dicas.png (fora do git). Sem argumentos: armas, poções, armaduras e acessórios.

const DEFAULT := ["copper_pickaxe", "terra_blade", "wand_of_sparking", "musket", "tendon_bow", "wooden_arrow", "lesser_healing_potion", "ironskin_potion",
	"mana_potion", "life_crystal", "meteor_suit", "gold_helmet", "cloud_in_a_bottle", "hermes_boots", "iron_bar", "grappling_hook", "space_gun", "cobalt_pickaxe"]

var frames := 0


func _initialize() -> void:
	Blocks.load_pack()
	Items.load_pack()
	Crafting.load_pack()
	var names := Array(OS.get_cmdline_user_args())
	if names.is_empty():
		names = DEFAULT
	root.theme = Ui.theme()
	var bg := ColorRect.new()
	bg.color = Color("#5b7fae")
	bg.size = Vector2(1280, 720)
	root.add_child(bg)
	var flow := HFlowContainer.new()
	flow.position = Vector2(12, 12)
	flow.custom_minimum_size = Vector2(1000, 0)
	flow.size = flow.custom_minimum_size
	flow.add_theme_constant_override("h_separation", 12)
	flow.add_theme_constant_override("v_separation", 12)
	root.add_child(flow)
	for n in names:
		var panel := PanelContainer.new()
		var tip := RichTextLabel.new()
		tip.bbcode_enabled = true
		tip.fit_content = true
		tip.scroll_active = false
		tip.autowrap_mode = TextServer.AUTOWRAP_OFF
		tip.custom_minimum_size = Vector2(180, 0)
		tip.text = Ui.item_tip(Items.ids[n])
		panel.theme_type_variation = "TooltipPanel"
		panel.add_child(tip)
		flow.add_child(panel)


func _process(_delta: float) -> bool:
	frames += 1
	if frames == 4:
		root.get_texture().get_image().save_png("res://textures/dicas.png")
		quit()
	return false
