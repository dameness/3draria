# Backlog — o que falta (fonte única de pendências; leia este antes de qualquer outro doc)

**Estado:** `main` já tem tudo até aqui (menu no layout do Terraria, golpe diagonal, poção no cursor, projéteis com sprite da wiki, inimigos com sprite, Configurações em categorias, mundo de teste com "Reiniciar mundo").
Testes verdes (`tests/run.gd`, `tests/menu_flow.gd`). Não precisa de mundo novo. Histórico detalhado: `docs/REVISAO.md` (não precisa ler inteiro).

## Como trabalhar (curto)
- Uma sessão = um assunto abaixo. Ao terminar: testes, commit pequeno, push, prints (folha de contato, só do que mudou), "como testar/rebuildar/mundo novo".
- Números e sprites sempre da wiki (`scripts/wiki.py`, `curl` na API). Referências visuais do dono: `docs/referencias/` (menus do Terraria). Vídeos: ver `CLAUDE.md` (Reddit ok, YouTube só busca).
- Ao concluir um item, apague-o daqui (não arquive aqui; o histórico é o `git log`).

## Agora (nesta ordem)
1. **Personagem e armaduras** (2 passadas feitas: rosto aberto, ombreiras grandes, braços grossos; armadura com textura de placas pixeladas × cor do ícone). Falta o dono dizer o que ainda incomoda (proporção da cabeça, cores, volume). Molten, Meteor e Ninja com formato próprio já feitos.
2. **Inimigos:** números de todos conferidos com a wiki (ok); nomes em title case (`Items.title`); The Hungry virou carne com boca; slimes em domo; Dark Caster de túnica azul.
   Falta o dono ver: Angry Bones/Cursed Skull (sprites da wiki são GIF: o carregador recusa), Skeletron (mãos), Wall of Flesh (plano demais) e o comportamento de cada IA.

- Projétil 3D só onde o sprite é pixel art pequeno (`"solid": true` em projectiles.json: Enchanted e Rotted Fork); Terra Beam (crescente 297x520), laser e espinho seguem billboard.
- Efeitos de armadura da wiki ainda sem código (por isso sem texto na dica): Molten (+7% dano/velocidade/crítico corpo a corpo), Meteor (+9% dano mágico), Ninja (+3% crítico); bônus de conjunto de Molten/Ninja.

## Divergências pré-Hardmode com a wiki (revisão de 29/09/2026; o que já foi corrigido está no `git log`)
Conferido contra a wiki: itens (dano, use time, poder, raridade), receitas, inimigos (vida/dano/defesa/recuo/moedas), drops de chefes, loot de baú, armaduras, regeneração, morte.
Tudo abaixo ainda diverge; em ordem de impacto na progressão:
1. **Bichos que ainda faltam:** Bone Serpent e os que só existem no Hardmode. Dark Caster, Tim e Fire Imp seguem a IA de conjurador da wiki (teleporta e solta 3 esferas), mas as esferas não revelam o mapa ao atravessar blocos. O Demon (foices) e o Meteor Head são só "voadores que batem"; Blood Crawler/Face Monster andam como zumbi (o de verdade anda em paredes).
2. **Spawn:** a wiki (NPC spawning) tem taxa por bioma/altura/hora e teto de 5; o jogo sorteia uniforme com teto 4 (dia) / 8 (noite). Estátuas e Slime Rain não existem.
3. **Morte:** falta a lápide; as moedas caem no lugar e a espera de 10 s é no ponto de nascimento (a wiki mantém você no lugar da morte e deixa pular a espera após 1,5 s sem inimigos por perto).
4. **Vila:** Guide, Merchant, Nurse, Demolitionist (chega com uma bomba) e Arms Dealer (com bala ou arma de bala); faltam Dryad, Clothier, Goblin Tinkerer/reforja, Wizard. Merchant sem Mining Helmet, Piggy Bank, Bug Net, Shuriken, Rope, Glowstick; Arms Dealer sem Minishark/Silver Bullet; Nurse cobra 1 de cobre por vida × o avanço do mundo, sem o ajuste de felicidade nem cobrança por debuff. O Olho de Cthulhu natural exige 4 habitantes, como na wiki.
5. **Baús:** o de superfície só tem Spear, Aglet e Wand of Sparking como principais (faltam Blowpipe, Wooden Boomerang, Climbing Claws, Umbrella, Radar...) e sem os secundários de granada/corda; faltam nos de caverna Mace, Shoe Spikes, Extractinator, Flare Gun, Lava Charm, Rope. (Bomb e Dynamite já saem dos baús; não há Demolitionist para vendê-las, nem bomba grudenta/quicante.)
6. **Chefes:**
   - King Slime: faltam Slimy Saddle, Solidifier, Slime Gun/Hook/Staff; a receita da Slime Crown na wiki é 20 Gel + Gold/Platinum Crown (jogo: 20 Gel + 5 barras de ouro); não nasce sozinho (1/300 de dia) nem pela Slime Rain.
   - Eye of Cthulhu: faltam Corrupt/Crimson Seeds, Binoculars e o altar (só cai se não houver).
   - Eater of Worlds: não foge quando o jogador sai do bioma; falta Eater's Bone; Worm Food/Rotten Chunk (Eater of Souls solta 33%) não existem, só as orbes o invocam.
   - Skeletron: faltam os drops Skeletron Hand/Book of Skulls/Mask. **Decisão pendente:** ao amanhecer a wiki o enfurece (9999 de dano e defesa); o jogo faz ele ir embora.
   - Wall of Flesh: faltam Horrified/The Tongue (puxa o jogador para a boca), a arma e o emblema do Hardmode e o Demon Heart.
   - Queen Bee e Deerclops dependem de selva e neve.
7. **Biomas e eventos:** neve, deserto, selva, oceano de verdade, cogumelo; Blood Moon, Goblin Army, Slime Rain; critters; pesca; Living Tree, Pirâmide, cavernas de aranha.
8. **Itens pré-Hardmode ausentes (amostra):** Blowpipe, Wooden Boomerang, Trident, Flintlock Pistol, Anklet of the Wind, Zombie Arm, Bed (ponto de spawn), Piggy Bank, Rotten Chunk/Vertebra, Rope, Glowstick, plataformas e móveis de madeira. Slime Crown pela receita da wiki pede Gold Crown (5 barras + Ruby): faltam as gemas.
Escala: 1 tile = 0,6 bloco e o mundo é uma ilha de 256x256 (o mundo pequeno da wiki é 4200x1200 tiles), então profundidades, quantidade de baús/orbes/cristais e raios de bioma não batem em número, só na ordem das camadas.

## Depois
- Sprites GIF animados da wiki (Angry Bones, Cursed Skull, Fallen Star): baixa prioridade, os inimigos vão ganhar modelo 3D próprio. Plano se voltar: `fetch-sprites` decodifica todos os quadros (stdlib, sem PIL) num PNG em faixa + `.anim` (quadros, ms); `Atlas.wiki_frames` corta; `enemy_model` monta uma malha por quadro (cache por sprite) e `animate()` alterna a visível.
- Habitantes andando pela casa e voltando à noite; mais habitantes (Demolitionist, Arms Dealer…); parede de fundo.
- Ball O' Hurt (mangual), Starfury, Celestial Magnet, Sky Mill; mais asas no Hardmode.
- Editar personagem existente; Conquistas/Créditos/Configurações no título; escala da interface; tempo de jogo no save.
- Sons que faltam e música/ambiente (a wiki hospeda os áudios); autosave + backup do mundo.
- Biomas (neve, deserto, selva), luz que se espalha pelas tochas, eventos (Lua de Sangue, Goblin Army).
- Bot de progressão (joga até o Hardmode) e GitHub Action rodando os testes a cada push.
- Hardmode e Calamity (`docs/ROADMAP.md`) — só depois do básico bom.

## Em aberto com o dono
- Bug do verme/subsolo: causa raiz corrigida (chunk gerado na fila), mas o dono ainda não conseguiu verificar.
- Pedir playtest (5ª parte: Demolitionist chega com bomba no inventário e o Arms Dealer com bala; lojas deles) e (4ª parte: bombas e dinamite dos baús — mundo novo para achá-las; Nurse mais cara depois dos chefes) e (3ª parte: conjuradores — Dark Caster no dungeon, Fire Imp no submundo, Tim raro nas cavernas; caveiras teleguiadas do Skeletron abaixo de 75% da vida) e da revisão pré-Hardmode (2ª parte: espera de 10 s ao morrer, baús de superfície — **mundo novo**, Giant Worm/Devourer/Blood Crawler/Face Monster/Mother Slime/Undead Miner, Anvil no Merchant) e da 1ª: regeneração de vida (agora pela fórmula da wiki: parado e sem apanhar ~2/s aos 60 s), corações e estrelas dos inimigos, moedas que caem ao morrer, Eater of Worlds com 67 segmentos (**conferir o FPS**; o número é `worm.segments` em `enemies.json`), Skeletron alternando mãos e giro, bichos das cavernas/submundo/meteorito, tijolos do dungeon (agora pedem a Molten, 100%).
- Pedir playtest do que mudou antes: Configurações, cartões do menu, inimigos com sprite, "Reiniciar mundo" (F9).
