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

4. **Seeds (feito: Seed/Blowpipe, Grass/Corrupt/Crimson Seeds, espalhamento).** Falta:
   - Poison Dart (10 de dano, envenena, 100 por Stinger na bigorna; não há item Stinger nem debuff de veneno nos inimigos) e Blowgun (Hardmode).
   - Seeds só saem quando o **jogador** corta o capim/flor (golpe de arma ou ferramenta, à frente na altura dos pés; chance 1/2 é chute); a wiki solta também se outra coisa quebra a planta.
   - Grass Seeds e Crimson/Corrupt do outro mal só pelo Dryad (que não existe) ou Extractinator; hoje só o baú do mundo de teste as tem (o Olho solta as do mal do mundo). Jungle/Mushroom Grass Seeds e sementes em Mud (grama de selva do mal) esperam o bioma.
   - A grama comum não espalha; a do mal só espalha a colocada/plantada e o que ela contamina (a de nascença não anda), com teto de 64 por chunk (`SPREAD_CAP`) e sem espinhos da Corrupção; tire o teto quando houver Purification Powder/Dryad.

- Projétil 3D só onde o sprite é pixel art pequeno (`"solid": true` em projectiles.json: Enchanted e Rotted Fork); Terra Beam (crescente 297x520), laser e espinho seguem billboard.
- Efeitos de armadura da wiki ainda sem código (por isso sem texto na dica): Molten (+7% dano/velocidade/crítico corpo a corpo), Meteor (+9% dano mágico), Ninja (+3% crítico); bônus de conjunto de Molten/Ninja.

- Flails (Mace, Ball O' Hurt, The Meatball, Blue Moon, Sunfury): faltam a fase de segurar de novo para a bola cair no chão (50% do dano), o On Fire! do Sunfury (25%, sem debuff de fogo nos inimigos), a sinergia Blue Moon + Sunfury (arremessa os dois espelhados), a Chain Knife (flail lançado, 1/250 do Cave Bat) e a origem do Blue Moon (baú trancado da Dungeon; não há baú de dungeon, só no mundo de teste).
- **Botão direito em armas:** a wiki (tooltips) não lista nenhuma arma pré-Hardmode com ação no botão direito; só Hardmode (Sky Dragon's Fury, Flairon, Tome of Infinite Wisdom, Brand of the Inferno). Nada a fazer até lá.

- **Soltar itens (feito):** Q solta 1 do slot da mão (Alt+Q, a pilha; com o inventário aberto, o do slot sob o mouse); item no cursor + clique esquerdo fora dos painéis solta a pilha (poção no cursor continua bebendo). Sai à frente e só é puxado de volta depois de 1,5 s; favoritado não sai. Q deixou de ser cura rápida (só H). Falta: soltar de baú/equipamento/munição.
- **Lava queima itens (feito, wiki Lava):** item solto de raridade 0 (moedas incluídas; inclusive as que caem na morte) ou −1 queima ao boiar na lava; ficam os de raridade 1+ e os `lava_safe` (baldes, Chain, Obsidian). A Guide Voodoo Doll (branca) queima como os outros: o Guide morre (vivo, onde estiver) e, no submundo e sem chefe, nasce o Wall of Flesh (uma vez, mesmo com pilha). Usar a boneca perto da lava (botão esquerdo) continua valendo como atalho e não mata o Guide. Falta: na 1.4.4 cada boneca extra da pilha mata outro habitante; as raridades dos blocos comuns (Dirt etc.) são 0 por padrão e só os minérios/orbes têm `rarity` no blocks.json (o audit confere os que têm linha na wiki).

## Habitantes e exceções `wiki_ok`
- Habitantes: de dia andam até 6 blocos de casa e à noite voltam (abrem e fecham porta; sem busca de caminho, uma parede que os segura por 12 s os faz aparecer em casa), atiram no inimigo mais próximo (velocidade, cadência e alcance são chute, o dano é o da wiki), fogem se o inimigo chega a 3 blocos ou a vida cai abaixo de 50%, apanham do inimigo que encosta (defesa e 0,5 s de folga), regeneram (0,33/s; Guide 2/s), morrem e voltam depois de 2 min, de dia e com casa. Os inimigos comuns os perseguem quando estão mais perto que o jogador. Só atiram em quem veem (raycast), tiros inimigos (chefes) os ferem e a espera da morte vai no save. Falta: busca de caminho até a porta; explosão inimiga (não existe inimigo que exploda; se surgir, `explode` precisa ferir habitantes).
- Só o Ruby entre as gemas (para a Gold/Platinum Crown → Slime Crown); faltam Amethyst, Topaz, Sapphire, Emerald e Diamond.
- `wiki_ok` que restam: Old Man (dano; ele é o guarda da Dungeon) e a receita do Hellforge (a wiki não a tem: ele só vem de ruínas do Underworld e Hellstone Crate, que o jogo não tem).

## Divergências pré-Hardmode com a wiki (revisão de 29/09/2026; o que já foi corrigido está no `git log`)
Conferido contra a wiki: itens (dano, use time, poder, raridade), receitas, inimigos (vida/dano/defesa/recuo/moedas), drops de chefes, loot de baú, armaduras, regeneração, morte.
Tudo abaixo ainda diverge; em ordem de impacto na progressão:
1. **Bichos que ainda faltam:** Bone Serpent e os que só existem no Hardmode. Dark Caster, Tim e Fire Imp seguem a IA de conjurador da wiki (teleporta e solta 3 esferas), mas as esferas não revelam o mapa ao atravessar blocos. O Demon (foices) e o Meteor Head são só "voadores que batem"; Blood Crawler/Face Monster andam como zumbi (o de verdade anda em paredes).
2. **Spawn:** a wiki (NPC spawning) tem taxa por bioma/altura/hora e teto de 5; o jogo sorteia uniforme com teto 4 (dia) / 8 (noite). Estátuas e Slime Rain não existem.
3. **Morte:** falta a lápide; as moedas caem no lugar e a espera de 10 s é no ponto de nascimento (a wiki mantém você no lugar da morte, deixa pular a espera após 1,5 s sem inimigos por perto, e a espera Classic é de 10-20 s). Volta com a vida cheia (a wiki: metade, mínimo 100, e mantém a mana que tinha). Moedas no cursor não caem (a wiki as derruba). Ver também "Dificuldade do personagem" abaixo.
4. **Vila:** Guide, Merchant, Nurse, Demolitionist (chega com uma bomba) e Arms Dealer (com bala ou arma de bala); faltam Dryad, Clothier, Goblin Tinkerer/reforja, Wizard. Merchant sem Piggy Bank, Bug Net, Shuriken, Rope, Glowstick; Arms Dealer sem Minishark/Silver Bullet; Nurse cobra 1 de cobre por vida × o avanço do mundo, sem o ajuste de felicidade nem cobrança por debuff. O Olho de Cthulhu natural exige 4 habitantes, como na wiki.
5. **Baús:** faltam Guide to Plant Fiber Cordage, Step Stool, Poison Barb, Extractinator, Glowstick, Angel Statue, poções Gills/Hunter/Dangersense e os acessórios de pet; a Rope é um bloco de um só passo (a wiki a estende sozinha). Bomb, Dynamite, Grenade, Shuriken, Throwing Knife, Flare Gun, Umbrella, Climbing Claws, Shoe Spikes, Radar e Lava Charm já saem dos baús.
6. **Chefes:**
   - King Slime: faltam Slimy Saddle, Solidifier, Slime Staff (Slime Gun sem o debuff Slime; Slime Hook já cai); não nasce sozinho (1/300 de dia) nem pela Slime Rain.
   - Eye of Cthulhu: faltam Corrupt/Crimson Seeds e o altar (só cai se não houver); Binoculars aproxima a visão (zoom), não desloca o olhar.
   - Eater of Worlds: não foge quando o jogador sai do bioma; falta Eater's Bone; Worm Food/Rotten Chunk (Eater of Souls solta 33%) não existem, só as orbes o invocam.
   - Skeletron: Hand e Book of Skulls já caem; falta a máscara (vanity). **Decisão pendente:** ao amanhecer a wiki o enfurece (9999 de dano e defesa); o jogo faz ele ir embora.
   - Wall of Flesh: faltam Horrified/The Tongue (puxa o jogador para a boca), a arma e o emblema do Hardmode e o Demon Heart.
   - Queen Bee: sem enfurecimento fora da selva nem veneno; abelhas já perseguem o inimigo mais perto (30 blocos, vira 6 rad/s, vida 4 s, atravessa 2; falta quicar 3x, o 1 de dano extra 50% e o Hive Pack); faltam Hive Wand, Honeyed Goggles, Nectar, o Abeemination e Bee Keeper/Bee's Knees/Bee Gun sem os efeitos de abelha (só o dano e o disparo); Beenade, Honey Comb e Bottled Honey já caem. Máscaras/troféus de todos os chefes são vanity e não existem. Deerclops depende do que falta da neve.
7. **Biomas e eventos:** neve e deserto existem só como discos (neve/gelo com 6 inimigos; areia/areia endurecida/arenito com Vulture e Antlion Charger); selva com lama, grama de selva e a colmeia com a larva (Queen Bee), Hornet, Jungle Bat, Jungle Slime; faltam árvore boreal, Deerclops, baú de gelo, Ice Torch, tempestade; cacto, Antlion, pirâmide, Mummy (Hardmode); mogno, Man Eater, Snatcher, baú de hera, Life Fruit, oceano de verdade, cogumelo; Blood Moon, Goblin Army, Slime Rain; critters; pesca; Living Tree, Pirâmide, cavernas de aranha.
8. **Itens pré-Hardmode ausentes (amostra):** Trident, Anklet of the Wind, Zombie Arm, Bed (ponto de spawn), Piggy Bank, Rotten Chunk/Vertebra, Glowstick, plataformas e móveis de madeira.
Escala: 1 tile = 0,6 bloco e o mundo é uma ilha de 256x256 (o mundo pequeno da wiki é 4200x1200 tiles), então profundidades, quantidade de baús/orbes/cristais e raios de bioma não batem em número, só na ordem das camadas.

## Melhorias anotadas (sessão de Seeds, soltar itens e lava)
- **Dificuldade do personagem (wiki Difficulty, Death):** é escolhida na criação do personagem e só muda o que se perde ao morrer. Hoje o jogo só tem o **Classic** (o padrão): solta 50% das moedas e o resto fica; a wiki arredonda para cima *por slot* (40 moedas de cobre em 40 slots saem todas) e o jogo arredonda por tipo de moeda. Faltam:
  - **Mediumcore:** solta *todos* os itens (moedas e munição inclusive), mantém vida e mana máximas; volta ao spawn depois da espera.
  - **Hardcore:** solta tudo e o personagem morre para sempre (vira fantasma que só observa; o personagem é apagado; habitantes soltam lápide e formam Graveyard).
  - **Journey:** começa com equipamento extra e só joga em mundo Journey (poderes de criação; fora do escopo por enquanto).
  - Tela de criação de personagem com a escolha (hoje o menu não pergunta) e a dificuldade no `.plr`. O **modo do mundo** (Expert/Master: 75%/100% das moedas, inimigos pegam as moedas soltas, mais vida/dano) é outra coisa, do mundo.
  - Classic: as moedas soltas na morte **queimam** se caírem na lava (a wiki diz isso de toda moeda branca); hoje vale, e é a morte na lava que faz perder dinheiro de verdade.
- **Boneca do Guide (lava):** a wiki (1.4.4) mata um habitante extra por boneca a mais na pilha que queima; aqui a pilha toda queima e só o Guide morre. Usar a boneca perto da lava (botão esquerdo) é atalho antigo que *não* mata o Guide e não existe na wiki; pode sair quando o soltar for o caminho oficial.
- **Soltar itens:** só de slots do inventário e do cursor; faltam baú, equipamento/acessórios e slots de munição/moeda. Não há descarte automático (a wiki: só some se o mundo acumular itens demais; aqui somem em 5 min, `LIFETIME`).
- **Raridade dos blocos:** os itens de bloco têm raridade 0 por padrão e só minérios/orbes têm `rarity` no blocks.json; o audit só confere os que têm linha na wiki pelo nome do jogo (Dirt, Stone, Chair, Workbench etc. usam outro nome lá e ficam sem conferência; todos são brancos). Bloco novo com raridade acima de 0 *precisa* de `rarity`, senão queima na lava.
- **Lava × itens:** queima só o item solto; a wiki também destrói móveis, plataformas e a maioria das árvores colocados em contato com lava, e o item "à prova de lava" da wiki tem uns 15 nomes (só os que existem no jogo estão marcados `lava_safe`: baldes, Chain, Obsidian).

## Pedidos do dono anotados (ainda sem fazer)
- **Câmera de 3ª pessoa com olhar livre:** segurar **Alt** gira só a câmera em volta do personagem (perspectiva livre, como no PUBG) sem virar o corpo nem a mira; soltar volta a câmera atrás dele. Só na 3ª pessoa (V), com o inventário fechado. Cuidado: Alt já é favoritar (Alt+clique no inventário) e Alt+Q (soltar a pilha); ao soltar, a câmera volta suave. Em Linux o gerenciador de janelas pode pegar Alt+clique.
- **Expert Mode e Treasure Bags:** modo do *mundo* (escolhido na criação do mundo): inimigos com mais vida/dano e IA alterada, mais drops, chefes soltam **Treasure Bag** (o loot normal + itens só do Expert), slot de acessório extra no Master; moedas 2,5× e 75% das moedas perdidas na morte (ver "Dificuldade do personagem"). Precisa de `expert` no `.wld`, multiplicador de stats por modo em `enemies.json`/`enemy.gd`, e as bolsas como item consumível que abre ao usar. Fazer depois de conferir na wiki (Expert Mode, Treasure Bag) o que muda em cada chefe já existente.
- **Projétil da espada separado do golpe "true melee":** hoje o feixe (Enchanted Sword, Terra Blade, Rotted Fork, Light's Bane etc.) usa o mesmo dano, recuo e crítico do golpe da lâmina. No jogo são separados: o projétil tem dano/recuo próprios, não é "true melee" (não recebe o que só vale para o golpe, como a velocidade e os efeitos de ataque corpo a corpo) e acerta por conta própria. Criar campos próprios do projétil em items.json (dano, recuo, crítico do feixe) e conferir por arma na wiki.
- **Minecarts e geração de minas:** carrinho de mina e trilhos (Minecart Track, rampas, Booster Track, etc.), andar no carrinho (inércia, pulo, dano contra inimigos no Terraria), e minas geradas no mundo (corredores escorados com madeira e trilhos, no subsolo). Depende do item "Minecart Track", de um bloco de trilho não sólido e de novas regras de movimento no `player.gd`; a geração entra em `world_gen.gd` e exige mundo novo.

## Depois
- Sprites GIF animados da wiki (Angry Bones, Cursed Skull, Fallen Star): baixa prioridade, os inimigos vão ganhar modelo 3D próprio. Plano se voltar: `fetch-sprites` decodifica todos os quadros (stdlib, sem PIL) num PNG em faixa + `.anim` (quadros, ms); `Atlas.wiki_frames` corta; `enemy_model` monta uma malha por quadro (cache por sprite) e `animate()` alterna a visível.
- Mais habitantes (Dryad, Clothier, Goblin Tinkerer, Wizard); parede de fundo.
- Starfury, Celestial Magnet, Sky Mill; mais asas no Hardmode.
- Editar personagem existente; Conquistas/Créditos/Configurações no título; escala da interface; tempo de jogo no save.
- Sons que faltam e música/ambiente (a wiki hospeda os áudios); autosave + backup do mundo.
- Biomas (neve, deserto, selva), luz que se espalha pelas tochas, eventos (Lua de Sangue, Goblin Army).
- Bot de progressão (joga até o Hardmode) e GitHub Action rodando os testes a cada push.
- Hardmode e Calamity (`docs/ROADMAP.md`) — só depois do básico bom.

## Em aberto com o dono
- Bug do verme/subsolo: causa raiz corrigida (chunk gerado na fila), mas o dono ainda não conseguiu verificar.
- Pedir playtest (9ª parte: selva e colmeia, **mundo novo**: cave até a câmara, quebre a larva e lute com a Queen Bee; drops) e (8ª parte: deserto, **mundo novo**: Vulture de dia, Antlion Charger debaixo) e (7ª parte: bioma de neve — **mundo novo**; Ice Slime/Frozen Zombie na superfície de neve, Ice Bat/Undead Viking/Spiked Ice Slime/Snow Flinx debaixo) e (6ª parte: Wooden Boomerang, Book of Skulls, Skeletron Hand (drop do Skeletron), Mining Helmet no Merchant, 4 gold) e (5ª parte: Demolitionist chega com bomba no inventário e o Arms Dealer com bala; lojas deles) e (4ª parte: bombas e dinamite dos baús — mundo novo para achá-las; Nurse mais cara depois dos chefes) e (3ª parte: conjuradores — Dark Caster no dungeon, Fire Imp no submundo, Tim raro nas cavernas; caveiras teleguiadas do Skeletron abaixo de 75% da vida) e da revisão pré-Hardmode (2ª parte: espera de 10 s ao morrer, baús de superfície — **mundo novo**, Giant Worm/Devourer/Blood Crawler/Face Monster/Mother Slime/Undead Miner, Anvil no Merchant) e da 1ª: regeneração de vida (agora pela fórmula da wiki: parado e sem apanhar ~2/s aos 60 s), corações e estrelas dos inimigos, moedas que caem ao morrer, Eater of Worlds com 67 segmentos (**conferir o FPS**; o número é `worm.segments` em `enemies.json`), Skeletron alternando mãos e giro, bichos das cavernas/submundo/meteorito, tijolos do dungeon (agora pedem a Molten, 100%).
- Pedir playtest dos habitantes (mundo de teste ou uma casa sua): de dia passeiam perto de casa e param quando você chega perto; à noite voltam para dentro; zumbi/slime os persegue e eles atiram ou fogem; morto, o habitante volta de dia depois de 2 min (com casa). Sem mundo novo.
- Pedir playtest do que mudou antes: Configurações, cartões do menu, inimigos com sprite, "Reiniciar mundo" (F9).
