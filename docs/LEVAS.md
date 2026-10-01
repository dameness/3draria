# Levas do visual Voxel (gerado por `scripts/voxel/levas.gd` a partir dos JSON; não edite)

Leva 0 (infra + pilotos): `scripts/voxel/`, corpo do personagem, Living Loom, conjunto Molten.
Status: **receita** = tem modelo próprio (models.json / campo `model`); **auto** = sprite inflado, já vale no jogo.

## Leva 1 — Estruturas (16, 10 com receita)
- receita: workbench, furnace, anvil, demon_altar, lead_anvil, chest, hellforge, life_crystal, bee_larva, living_loom
- auto: torch, chair, door, door_open, rope, minecart_track

## Leva 2 — Armaduras (por conjunto) (12, 1 com receita)
- receita: molten
- auto: copper, tin, iron, lead, silver, tungsten, gold, platinum, meteor, ninja, wood

## Leva 3 — Armas (69, 0 com receita)
- receita: —
- auto: wooden_sword, copper_shortsword, wooden_bow, wooden_arrow, enchanted_sword, terra_blade, copper_broadsword, copper_bow, tin_broadsword, tin_bow, iron_broadsword, iron_bow, lead_broadsword, lead_bow, silver_broadsword, silver_bow, tungsten_broadsword, tungsten_bow, gold_broadsword, gold_bow, platinum_broadsword, platinum_bow, lights_bane, demon_bow, unholy_arrow, blood_butcherer, tendon_bow, cobalt_sword, palladium_sword, musket_ball, musket, the_undertaker, wand_of_sparking, space_gun, vilethorn, the_rotted_fork, crimson_rod, tin_shortsword, iron_shortsword, lead_shortsword, silver_shortsword, tungsten_shortsword, gold_shortsword, platinum_shortsword, spear, bone_sword, bomb, dynamite, flintlock_pistol, book_of_skulls, wooden_boomerang, bee_keeper, the_bees_knees, bee_gun, mace, ball_o'_hurt, the_meatball, blue_moon, sunfury, grenade, shuriken, throwing_knife, flare_gun, flare, umbrella, slime_gun, beenade, seed, blowpipe

## Leva 4 — Inimigos (49, 0 com receita)
- receita: —
- auto: green_slime, blue_slime, zombie, demon_eye, servant_of_cthulhu, eater_of_souls, crimera, angry_bones, cursed_skull, dark_caster, old_man, voodoo_demon, hellbat, the_hungry, pixie, unicorn, guide, merchant, nurse, red_slime, yellow_slime, black_slime, lava_slime, cave_bat, skeleton, meteor_head, demon, mother_slime, undead_miner, blood_crawler, face_monster, giant_worm, devourer, tim, fire_imp, demolitionist, arms_dealer, ice_slime, frozen_zombie, ice_bat, undead_viking, spiked_ice_slime, snow_flinx, vulture, antlion_charger, hornet, jungle_bat, jungle_slime, bee

## Leva 5 — Chefes (9, 0 com receita)
- receita: —
- auto: eye_of_cthulhu, eater_of_worlds, creeper, brain_of_cthulhu, king_slime, skeletron, skeletron_hand, wall_of_flesh, queen_bee

## Regra para conteúdo futuro
- Todo item, bloco e estrutura novo nasce com modelo **automático** (o sprite da wiki inflado): não precisa fazer nada, já tem volume.
- Só o que merece destaque ganha **receita**: entrada em `data/<pacote>/models.json` (sprite da wiki, cores emissivas) + função em `scripts/voxel/recipes.gd`,
  e o campo `"model": "nome"` no item/bloco/conjunto. Critério de destaque: chefe, arma de raridade alta ou com efeito visual, estrutura grande (tamanho em tiles ≥ 2x2), conjunto de armadura com brilho.
- Retoque à mão: salve o `.vox` em `assets/models/` (prioridade sobre o gerado em `assets/models/gen/`). Ver `docs/VOXEL_STYLE.md`.
