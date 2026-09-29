# Revisão pré-hardmode — mapa (etapa 1) e execução (etapa 2)

Foco: fechar a pré-hardmode antes de hardmode/Calamity. Cada item: **Hoje** (código) → **Wiki** (números) → **Plano** (passos pequenos) →
**Teste/print**. Um commit por item; marque ✅ ao concluir. Perguntas para o dono: no fim.

| # | Item | Status |
|---|------|--------|
| B1 | Minimapa "teleporta" (+ Tab/M) | ✅ |
| B2 | Verme (Eater of Worlds) bugado | ✅ |
| B3 | Brain: fase 1 não fica translúcida; barra e nº de Creepers | ✅ |
| B4 | Iluminação estranha (tochas cortam na borda do chunk; mão clara em caverna) | ✅ |
| 1 | Árvore cai inteira (madeira por bloco, acorn, muda) | ✅ |
| 2 | Binds do Terraria (Esc, Settings, botão esquerdo coloca, Shift; H/Q/J/B vêm com poções e mana) | ✅ |
| 3 | Ataque: use time, autoswing só onde a wiki diz, mira exata, tool speed | ✅ |
| 4 | Danos da wiki (variância, crítico, defesa, recuo) + martelos | ✅ |
| 5 | Voo: modo criativo (F) separado das asas (acessório) | ✅ |
| 6 | Loot: baús por camada, Life Crystal, poções e buffs | ✅ |
| 7 | Mana e magia | ✅ |
| 8 | NPCs (Guide, Merchant, Nurse) | ✅ |

Como mapeei: li o código (arquivo:função), baixei da wiki pela API (Controls, Damage, Defense, Tree, Axe power, Tool speed, Autoswing,
Use time, Minimap, Wings, Mana, Chest/Shadow Chest, Life/Mana Crystal, poções, Guide/Merchant/Nurse, Eater of Worlds, Brain of Cthulhu)
e pela tabela Cargo (`Items`: autoswing, use time, knockback, mana). **Reproduzi** os bugs (prints via xvfb + simulação com métrica);
os números abaixo são medidos, não suposição.

---------------------------------------------------------------------------------------------------------------------------------

## B1 — Cursor do minimapa "teleporta" ✅

**Hoje** (`minimap.gd:_process`): a imagem é redesenhada 2 linhas por quadro (80 linhas = 40 quadros ≈ 0,67 s). A origem (`origin`) é
recalculada quando `row == 0`, no começo do ciclo, mas a textura só é publicada (`tex.update`) no **fim** do ciclo. Durante os 40 quadros a
seta usa a origem **nova** sobre uma textura da origem **velha**: a seta salta para o centro no início do ciclo e o mapa salta no fim.
Erro = quanto o jogador andou no ciclo: 3 a 4 blocos andando (6-8 px), ~9 blocos voando (18 px). Além disso cada linha usa o `py` do
momento em que foi lida (faixas horizontais quando se sobe/desce) e nada é lembrado: o que sai da janela de 80x80 some.

**Wiki (Minimap):** modos retrato / sobreposição / oculto (Tab), mapa cheio (M), zoom (+/-); o mapa **guarda o explorado**
(mesmo se voltar a escurecer) e é salvo com o personagem; ícones do spawn, do local da última morte, NPCs e chefes.

**Plano**
1. Buffer do mundo inteiro (256x256, origem fixa em (0,0)): cada pixel é sempre a mesma coluna. Sem origem que muda = sem teleporte.
2. Retrato: recorte 80x80 (zoom 1x; +/- muda 40/80/160 blocos) centrado no jogador com deslocamento **em pixels inteiros**; a seta fica
   fixa no centro e só gira. Varredura de 2 linhas/quadro numa faixa em volta do jogador; a cor é a do topo da coluna (sem `py`).
3. Memória: o que já foi visto continua (mapa de exploração). Salvo no `.wld` (`map`, zstd) ("ponytail": a wiki salva por personagem).
4. Tab: retrato → sobreposição (translúcido sobre a tela) → oculto. M: mapa cheio (256x256 ampliado) com seta, spawn e local da morte.
5. `+`/`-` hoje mudam a distância de renderização (`world.gd:_unhandled_input`): passa para `[` e `]` e para o painel Settings.

**Teste/print:** `test_minimap`: o pixel sob a seta é a coluna do jogador em **todo** quadro de uma caminhada de 200 blocos; um bloco
marcador aparece a `(marcador − jogador) × escala` do centro (erro < 1 px) antes e depois de trocar de janela; explorado persiste.
Prints: `minimapa` (retrato), `minimapa_overlay`, `mapa_cheio`.

## B2 — Verme (Eater of Worlds) "meio bugado" ✅

**Hoje** (`enemy.gd:_process` linhas ~77-80): `Basis.looking_at(frente, Vector3.UP)`. Com a frente quase vertical (cabeça subindo ou
descendo até o jogador) a rolagem em torno do eixo é indefinida. **Medido** (simulação de 20 s, `worm_view`): o modelo de um segmento
gira **~155° num único quadro** duas vezes (placa das costas e anéis "piscam"). Outros defeitos vistos no código:
- Ao dividir (`hurt`, `o.follow = null`) o novo verme ganha cabeça com o modelo de **corpo** (sem boca) e o pedaço da frente termina sem
  ponta de rabo. A wiki converte: cabeça morta → o vizinho vira cabeça; corpo morto → um vira cabeça e o outro rabo; segmento sozinho morre.
- Voa em linha reta sem gravidade e sempre alcança o jogador (míssil teleguiado). O verme do Terraria **escava**.
- Números: cabeça 150 de vida (wiki 65); rabo 150 de vida e defesa 6 (wiki 220 e 8); 24 segmentos (wiki 67; vida total do jogo 3600
  contra ~10 050 da wiki).

**Wiki (Eater of Worlds):** cabeça 65 vida/22 dano/2 def; corpo 150/13/4; rabo 220/11/8; recuo 100% resistido; **no ar sofre gravidade e
acaba caindo, precisando escavar de novo**; se a cabeça está a mais de 62,5 tiles (~37 blocos) do jogador ela voa livre; foge para baixo
se o jogador morre ou sai do bioma; cospe Vile Spit (cabeça 1/390 → 1/90 por quadro conforme perde vida; corpo 1/900).

**Plano**
1. Orientação sem flip: transporte paralelo (rotação de menor arco do `forward` anterior para o novo) + realinhar a rolagem ao "cima"
   do mundo devagar (só longe da vertical). Nunca `looking_at` com `UP`.
2. Divisão como a wiki: cabeça morta → vizinho vira cabeça (boca); corpo morto → cada lado vira cabeça ou rabo (troca o modelo/`def`);
   pedaço de 1 segmento morre e solta o loot.
3. Vida/defesa da cabeça, corpo e rabo iguais à wiki (`enemies.json`); manter 24 segmentos ("ponytail": wiki 67; é só dado).
4. Escavação: na cabeça, dentro de bloco sólido → guia até o jogador (giro limitado); no ar → gravidade e giro fraco (cai e volta a
   escavar); >37 blocos do jogador → voa livre. Corpo continua seguindo com distância fixa. (Opcional: Vile Spit reutilizando `eye_laser`.)

**Teste/print:** `test_worm`: nenhum segmento gira mais de 20° por quadro em 60 s com o jogador andando; a cabeça nova tem boca e a ponta
tem cone; a cabeça, sob o chão, sai, descreve arco balístico e volta a escavar. Print `verme_vivo` (simulado, câmera de perseguição).
**Feito:** `Enemy.orient` (menor arco + rolagem devolvida ao "cima" a 3 rad/s; o teste varre a frente rente à vertical: novo 2,9°/passo,
`looking_at` antigo 178°), `set_role`/`split_worm` (cabeça com boca, rabo com ponta, dano/defesa por papel, pedaço de 1 segmento morre),
`worm()` com escavação (dentro: giro ≤ 3 rad/s; fora: gravidade 14,85 blocos/s²; >37 blocos: voa livre), o verme nasce a 6 blocos sob a
superfície, cabeça 65 e rabo 220/def 8. Velocidade da cabeça **15 blocos/s** (wiki ≈ 22,5; abaixo por causa da mira em 3D — só dado em
`enemies.json`). Vile Spit e "foge se o jogador morre" ficam para depois.

## B3 — Brain of Cthulhu ✅

- **Fase 1 não parece translúcida** (`enemy.gd:set_ghost`): usa `MeshInstance3D.transparency`, que o renderer Compatibility ignora.
  **Medido** (esfera vermelha sobre fundo branco, xvfb): `transparency = 0.5` → (1, 0, 0) opaco; alpha no material → (1, 0.5, 0.5).
  Por isso o cérebro imune parece igual ao vulnerável. Correção: alpha no `albedo` dos materiais (modo ALPHA).
- **Barra de vida**: `boss_max` fica em 2450 (cérebro + Creepers) depois que os Creepers morrem: a barra começa a fase 2 em 51%.
  Recalcular `boss_max` ao mudar de fase.
- **Creepers:** wiki = **20** (Creeper 100 vida/20 dano/def 10); o jogo tem 12 (`creepers` em `enemies.json`). Total do grupo 3250.
- Fase 2 da wiki: vulnerável, teleporta rápido e investe (já existe). Ilusões só no Expert.

**Teste/print:** `test_brain`: `set_ghost(true)` deixa `albedo.a < 1` e `false` volta a 1; `boss_max` cai ao entrar na fase 2; 20 Creepers.
Prints `cerebro` (fase 1 translúcido) e `cerebro_fase2` (sólido).

## B4 — Iluminação estranha ✅

Reproduzido em `caverna` e `noite_tochas`: a luz da tocha **acaba numa linha reta na borda do chunk**. Causas:
1. `world.gd:set_block` só refaz o chunk vizinho se o bloco está **na borda** (`lx == 0` ou `15`), mas a tocha ilumina **10 blocos**
   (`blocks.json`: `light`): a malha do vizinho fica sem a tocha nova (é o caso de quem põe tochas cavando).
2. `chunk_mesher.gd:_lights` só considera os 4 vizinhos diretos: uma tocha no chunk **diagonal** não ilumina o canto.
3. A mão/personagem/inimigos usam luz de cena (sol + ambiente) que não sabe da profundidade: em caverna a picareta continua clara
   (`day_night.gd` só mexe em névoa e céu). A luz de face (`facing`) e o `shake` da câmera estão certos.

**Plano:** (a) `set_block` refaz todos os chunks ao alcance da luz quando o bloco novo/antigo emite luz (até 8 vizinhos); (b) `_mesh_job`
passa os 4 diagonais só como **fontes de luz** (o mesher usa os 8); (c) `day_night.gd` escurece sol/ambiente dos modelos pelo fator `cave`
(mínimo 0,35 para a mão continuar legível).
**Teste/print:** `test_lighting`: tocha a 3 blocos da borda ilumina as faces dos dois chunks (e do diagonal) com o mesmo valor; após
`set_block` os vizinhos entram em `urgent`. Prints `caverna` e `noite_tochas` de novo (sem a linha reta).

---------------------------------------------------------------------------------------------------------------------------------

## 1 — Árvore: quebrar a base derruba tudo ✅

**Ponto do dono:** base derruba tronco + copa; madeira por bloco do tronco; acorn/semente.
**Hoje:** `player.gd:break_target`: cada bloco de tronco (`wood`, `axe: true`, `mine 1,5`) leva 2 golpes com o machado de cobre e cada
um solta 1 madeira; as **folhas** (`mine 5`, sem drop) só quebram com **picareta** (machado dá "segure uma picareta") e a copa fica
**flutuando** depois que o tronco some. Não há acorn nem muda. Árvore = `world_gen.gd:_tree` (tronco 8-13, raízes, 0-2 galhos com tufo,
copa elipsoidal); tronco colocado pelo jogador usa o mesmo id `wood`.
**Wiki (Tree, Axe power):** cada tile de árvore tem 100 de vida; dano por golpe = ⌊poder do machado × 24⌋ (cobre 35% = 8 → 13 golpes;
ferro 45% = 10 → 10; chumbo 50% = 12 → 9); "tile destruído + tudo que está **acima** dele cai"; cortar o tile central mais baixo derruba a
árvore inteira; o que sobra não rebrota. Madeira: 1 por tile (galhos incluídos) e chance de virar 2 = (2·poder + 175)/525 (cobre
≈ 1,47 por tile); **1 acorn por tufo de folhas** (chance ~1/3); muda em grama (e areia/neve): cresce sozinha depois de um tempo, só com
espaço livre (9-20 de altura, 2 blocos de cada lado); sob o tronco o chão é indestrutível.
**Plano** (sem bloco novo: o tronco é o `wood` que já existe, então funciona em mundos antigos)
1. `World.fell_tree(p, axe_power)`: tronco = `wood` ligado para cima a partir de `p`; galhos = `wood` colado ao tronco (≤2 blocos, nunca
   outro tronco vertical); raízes se `p` é a base; folhas que ficam sem `wood` a ≤4 blocos (BFS por folhas) somem junto.
2. `break_target`: `wood` que é árvore (tem folhas ligadas acima) usa 100 de vida e dano ⌊poder × 24 / 100⌋ (o `wood` colocado continua
   `mine 1,5`); ao quebrar o bloco dispara `fell_tree`. Folhas cedem ao machado também.
3. Animação: a árvore vira um corpo que **tomba** sobre o eixo do lado oposto ao jogador (0→90° com aceleração, ~1,2 s), chuva de folhas
   (`Fx`), poeira e som; no fim solta as madeiras (uma pilha) e os acorns.
4. Drop: madeira por bloco com a fórmula da wiki; acorn ~1/3 por tufo. Item `acorn` + bloco `sapling` (planta); colocar em grama cria a muda;
   `world` guarda as mudas (tempo aleatório de 2-5 min) e cresce com o mesmo `_tree` (só com espaço livre). Vai no save do mundo.
**Teste/print:** `test_tree`: cortar a base derruba tronco+raízes+galhos+folhas (nada flutua, árvore vizinha intacta); meio do tronco
derruba só o de cima; 13 golpes com machado de cobre na base; média de madeira ≈ 1,47/tile em 2000 árvores; muda cresce. Prints
`arvore_cai` (meio da queda) e `arvore_toco`.
**Feito** (`timber.gd`, `world.gd:grow_sapling`, `WorldGen.tree`): dano ⌊poder × 0,24⌋ contra 100 por tile só em madeira **de árvore** (o topo da coluna
encosta em folhas; madeira colocada segue `mine 1,5`); ao quebrar, `Timber.fell` tira tronco+galhos+raízes (base) e as folhas que não ficam presas a
outra madeira (BFS: sem folha flutuando, árvore vizinha intacta), tomba o pedaço (malha do próprio mesher, 1,2 s, para longe do jogador),
solta madeira (1 por tile, 2 com chance (2·poder+175)/525) e acorn (1/2 por tufo — número meu, a wiki não dá). `acorn` coloca `sapling`
só em grama (bloco `grass: true`); a muda cresce em 2-5 min com 5x5x12 livres e sai com a semente da posição. Mudas vão no save do mundo.
Funciona em mundos antigos (o tronco é o `wood` de sempre).

## 2 — Binds do Terraria ✅

**Wiki (Controls, Desktop):** botão esquerdo = usar item (**inclusive colocar bloco**, com autoswing); direito = interagir (baú, porta,
NPC); **Esc = inventário** (e Save & Quit; só pausa com Autopause); **Tab = estilo do mapa**; M = mapa cheio; W/A/S/D e Espaço; 0-9 e
roda; **Shift esquerdo = Auto Select** (com Shift segurado escolhe a ferramenta certa para o alvo; senão uma fonte de luz); Ctrl esq. =
Smart Cursor; E = gancho; R = montaria; **H = cura rápida**, J = mana rápida, B = buffs; F1-F3 conjuntos; F10 FPS; F11 HUD; Alt+clique
favorita, **Ctrl+clique** joga no lixo, Shift+clique move para o baú; segurar o direito num item tira 1 por vez.
**Hoje:** `player.gd:_unhandled_input`: Tab e E abrem o inventário; Esc fecha o inventário e, sem nada aberto, **pausa**; botão direito
**coloca bloco** (`place_target`); Shift **corre** (1,4×); F voo, V 3ª pessoa, F5 salva, F8 kit. `hud.gd`: botão "Menu" abre a pausa.
**Plano**
1. Esc alterna o inventário (fecha painel/baú primeiro); a pausa vira o botão **Settings** do inventário (Continuar / distância de
   renderização / volume / sensibilidade / Salvar e sair). Tab e M: minimapa (item B1). E deixa de abrir o inventário.
2. Botão esquerdo coloca bloco quando o item da mão é bloco (repete a cada 0,25 s segurando, item 3); o direito só interage (baú, NPC).
3. Shift = Auto Select (com o botão esquerdo): troca temporariamente para o melhor machado/picareta da hotbar conforme o alvo, senão
   a tocha; solta e volta ao slot anterior. Sem corrida (a wiki: base = **11 tiles/s ≈ 6,6 blocos/s**; hoje 4,5 → sobe para 6,6).
4. H (e Q, pedido antigo) cura rápida (melhor poção); J mana rápida; B bebe as poções de buff; Ctrl+clique = lixo; F10/F11 escondem
   FPS/HUD. Tudo em constantes no topo de `player.gd` para trocar depois.
**Teste/print:** `test_binds` com `InputEventKey/MouseButton` sintéticos (Esc abre/fecha, Tab cicla, M, esquerdo coloca bloco e direito
não, Shift troca de slot e devolve, H usa a poção certa). Prints `inventario` com o botão Settings e o painel Settings.

**Feito:** `player.gd`: Esc abre/fecha o inventário (`set_inventory`; baú e item preso voltam junto), E e Tab não abrem mais; botão esquerdo
(`use_item`) coloca bloco (`place_block`, a cada 0,25 s segurando), direito só `interact()` (NPC, baú); sem corrida, `WALK` = 6,6 blocos/s
(voo livre F segue a 13,5 em `FLY`); **Auto Select** (`auto_pick`): com Shift a mão vai para o melhor machado (tronco) ou picareta (resto) da
hotbar para o bloco da mira, sem alvo para a tocha, e o slot de antes volta ao soltar. 1-0 e a roda valem com o inventário aberto.
`hud.gd`: o botão "Menu" virou **Configurações** (pausa de verdade) com distância de renderização (2-16), volume e sensibilidade do mouse
em controles deslizantes que aplicam na hora e gravam em `user://settings.cfg` (`settings.gd`, o menu liga o caminho; testes não gravam);
Ctrl+clique joga no lixo (`Inventory.quick_trash`, favorito não vai); F10 esconde o FPS, F11 o HUD; a mira "+" some com painel aberto.
**H/Q (cura), J (mana) e B (buffs) ficam para os itens 6 e 7**, quando existirem poções e mana (hoje não há nada para beber). Testes:
`test_binds` (eventos sintéticos, Auto Select, lixeira, sensibilidade, gravar/ler/limitar as opções) e, na integração, baú com botão
direito + Esc, painel Configurações com os controles, F10/F11. Prints: `inventario` (botão Configurações) e `config`.

## 3 — Ataque: use time, autoswing e mira ✅

**Ponto do dono:** rápido demais, sem mirar onde aponto → use time da wiki, só clicando, cone/raycast da mira.
**Hoje:** `player.gd:_process` chama `use_item()` a cada quadro enquanto o botão esquerdo está apertado e `cooldown <= 0`: **tudo repete**.
`swing` acerta por cone horizontal de ~75° (`dot > 0,25`) **ou** cone 3D de 60° (`dot > 0,5`): pega inimigo que não está na mira.
**Medido** (tabela Cargo × `items.json`, 49 itens; o Light's Bane não achei pelo nome): dano, use time (frames/60) e recuo **batem** com a
wiki; só o recuo do arco de madeira difere (2 → 0; o da flecha é 2 — na wiki soma-se arma + munição, hoje só a arma). `autoswing`: **só** picaretas, machados/martelos, Enchanted
Sword, Terra Blade e as espadas de cobalto/paládio; **não** têm: espadas curtas e largas de metal, Wooden Sword, arcos, Blood Butcherer,
Demon/Tendon Bow... (e blocos, tochas, baldes têm, com use time 15 = 0,25 s).
**Wiki (Use time/Tool speed):** use time = tempo do golpe; *tool speed* = intervalo entre golpes de ferramenta em blocos (cobre 15
quadros = 0,25 s, hoje 0,383; ferro 13, prata 11, platina 15, nightmare 15, molten 18, cobalto 13; machados 21/20/19/19/18/18/18/17).
**Plano**
1. `items.json`: `autoswing` (bool, da wiki) e `tool_speed` (quadros) em picaretas/machados; recuo do arco.
2. Entrada por evento (`attack_held`, `attack_pressed`): sem autoswing, um clique = um uso (com buffer de 0,12 s para não perder clique);
   com autoswing repete. Ferramentas usam `tool_speed` como ciclo ("ponytail": o inimigo leva o dano da picareta 50% mais rápido).
3. Mira: `melee_targets(eye, dir, reach)`: 3 raios em leque (centro, ±20°) contra a AABB do inimigo alargada em 0,25; acerta quem o
   raio cruza dentro do alcance, sem cone largo e sem acertar atrás. Flecha/feixe continuam saindo da mira.
4. Recuo de projétil = recuo da arma + recuo da munição.
**Teste/print:** `test_attack`: segurar o botão com espada larga dá 1 golpe; com picareta repete a cada `tool_speed`; inimigo a 40° da
mira não é acertado, na mira sim; 3 raios pegam 2 inimigos alinhados. Print `arco` de novo.

**Feito:** `items.json`: `autoswing: true` só nas picaretas, machados, Enchanted Sword, Terra Blade e espadas de cobalto/paládio (tabela Cargo da
wiki; blocos, tochas, mudas e baldes têm por padrão) e `tool_speed` (quadros da tabela Tool speed: cobre 15, estanho 14, ferro 13, chumbo 12, prata 11,
tungstênio 19, ouro 17, platina 15, Nightmare 15, Deathbringer 14, Molten 18, cobalto 13, paládio 12; machados 21/20/19/19/18/18/18/17); recuo do
arco de madeira 0 e da flecha 2. `Items.use_dur` (tool speed ou use time) é o ciclo do golpe e da animação; `Items.autoswing`. `player.gd`: o botão
esquerdo é evento (`attack_held`, `attack_buffer` de 0,12 s) e `attack()` usa o item uma vez por clique e repete só com autoswing; o golpe corpo a corpo
(`melee_targets`) usa 3 raios (mira e ±20°) contra a caixa do inimigo alargada em 0,25, dentro do alcance da arma: sem cone largo, nada atrás; recuo do
projétil = arma + munição. Como o Terraria, a picareta/machado também bate em inimigo no ritmo do tool speed (a wiki usa o use time para isso; dano
de ferramenta é baixo, sem ajuste). Testes: `test_attack` (autoswing/use_dur pela wiki, segurar dá 1 uso sem autoswing, 8 golpes em 2 s com a picareta de
cobre, buffer, mira/leque/fila/slime baixo, recuo 2 e 4) + o botão esquerdo de verdade na integração. Prints: `arco`, `minera`.

## 4 — Danos da wiki ✅

**Wiki (Damage, Defense):** dano final = base × modificador; **variância** ×[0,85; 1,15] arredondada; contra **inimigo**: subtrai
⌈defesa/2⌉ (mínimo 1) e **depois** o crítico ×2 (chance base 4%); contra o **jogador** (clássico): ⌊dano − defesa × 0,5⌋ (mínimo 1)
**depois** da variância; 40 quadros (0,67 s) de invencibilidade; munição soma ao dano da arma.
**Hoje:** `enemy.gd:hurt` e `player.gd:hurt` fazem `dmg − ⌈def/2⌉` **sem** variância nem crítico; números de dano sem cor de crítico.
`enemies.json`: vida/dano/defesa **batem** com a wiki, mas o recuo não: Zombie 50%, Demon Eye 20%, Hellbat 20%, Cursed Skull 80%,
Dark Caster 40%, Pixie 40%, Unicorn 70% (o jogo tem 0 ou 30%); EoW/Brain: ver B2/B3.
**Plano:** `Combat.roll(dmg)` (variância + crítico) usada pelo golpe, flecha, feixe e magia; defesa depois da variância e crítico depois
da defesa; número dourado maior no crítico; `kb_resist` da wiki; **martelos** (Wooden 25%, Copper 35%, Tin 38%, Iron 40%...; receitas
via `scripts/wiki.py`) porque a wiki manda quebrar **Shadow Orb / Crimson Heart com martelo** (hoje quebra com picareta) — `hammer_power`
em itens e `hammer` em blocos, e o Auto Select do item 2 já escolhe o martelo.
**Teste/print:** `test_damage`: 20 000 golpes: mínimo/máximo/média da variância; crítico ×2 depois da defesa; jogador `⌊d − def/2⌋`;
orbe só quebra com martelo. Print `inimigos` com números normais e um crítico.

**Feito:** `combat.gd` (`Combat.vary`, `Combat.is_crit`): o golpe corpo a corpo, a flecha/feixe (a cada inimigo acertado) e o dano que o jogador leva
(contato e laser) sorteiam a variância de ±15% **antes** da defesa; `Enemy.hurt(dmg, dir, kb, crit)` desconta ⌈def/2⌉ e o crítico (4%) dobra **depois**,
com +40% de recuo e número maior/mais alto/mais demorado (`spawn_text(..., crit)`). O jogador já levava ⌊dano − def × 0,5⌋ (mesmo resultado que
dano − ⌈def/2⌉ com dano inteiro), agora com variância. `kb_resist` de todas as criaturas conferido com a tabela NPCs da wiki (Zombie 50%, Demon Eye 20%,
Green Slime −20%, Cursed Skull 80%, Dark Caster 40%, Hellbat 20%, The Hungry −10%, Pixie 40%, Unicorn 70%, Old Man 50% e defesa 15).
**Martelos** (novos, no fim de items.json): Wooden 25%, Copper 35, Tin 38, Iron 40, Lead 43, Silver 45, Tungsten 50, Gold 55, Platinum 59, com dano, use
time, tool speed e receitas da wiki (`scripts/wiki.py`); bloco `hammer: true` na Shadow Orb e no Crimson Heart: a picareta agora avisa "precisa de um
martelo"; `Items.power_on` e o Auto Select escolhem o martelo. Sprites novos: rode `scripts/update.sh`. Testes: `test_damage` (20 000 sorteios: 85-115 e média
100; crítico 4%; (20−3)×2 = 34; recuo 3 e 4,2; tabela de recuos da wiki; jogador com 4 conjuntos de armadura; martelos e orbes) e as flechas/feixe agora
conferem a faixa da variância. Prints: `inimigos` (números normais e um crítico) e `martelo`.

## 5 — Voo: modo criativo separado das asas ✅

**Wiki (Wings, Fledgling Wings):** asas são acessório; **segurar Espaço** dá voo enquanto houver *flight time* e depois **plana**
(gravidade e queda máx. 1/3); o tempo volta ao tocar o chão; **sem dano de queda**; Down+Espaço paira (só asas melhores); a única asa
pré-hardmode, Fledgling, voa **0,42 s**, 15 mph na horizontal e 22 na vertical (vêm de Skyware Chest, 2,5%). Não existe tecla de descer.
**Hoje:** `player.gd:step`: F liga voo livre (atravessa blocos, invulnerável), Espaço sobe e **C** desce; não há asas nem dano de queda.
**Plano:** (1) F vira **modo criativo/debug** (noclip, invulnerável, aviso fixo na tela; descer em tecla à parte — pergunta 1);
(2) `accessory.wings {time, speed, lift}` nos dados + `Fledgling Wings` (kit F8): segurar Espaço no ar gasta `time`, depois planeja;
`flight_left` recarrega no chão; `fall_immune` (o dano de queda em si fica para "Depois"); (3) HUD mostra a barra de voo.
**Teste/print:** `test_wings`: consome só segurando, recarrega no chão, planeio cai a 1/3, sem asas cai normal; modo criativo não
atravessa nada se desligado. Print `voo` (asas e planando).

**Feito:** `player.flying` virou `player.creative` (F): atravessa blocos, não leva dano, Espaço sobe e C desce, com o aviso fixo "MODO CRIATIVO" no topo da
tela (o rodapé diz "modo criativo (F)"). Asas de verdade: `Fledgling Wings` (item novo no fim de items.json, `accessory.wings {time: 0.42, lift: 9.7}` = 22 mph
da wiki ÷ 0,733 tiles/s por mph ÷ 1,67 tiles por bloco; sprite da wiki, entra no kit F8). `player.step`: com asas vestidas (`Inventory.wings()`), segurar Espaço no ar
sobe até `lift` (`WING_ACCEL`) gastando `flight_left` (voa mesmo logo depois de sair do chão); acabado o tempo, Espaço apertado com velocidade descendo **planeia**
(gravidade e queda máxima em 1/3: `GLIDE`, `GLIDE_FALL` = 7,5 blocos/s); o chão (ou a água) recarrega. Sem asas nada muda. A barra de voo (azul) aparece sob a
mira enquanto o tempo não está cheio. Animação: 2 asas espelhadas do sprite da wiki nas costas (translúcidas, fechadas em pé, batendo ao subir e abertas
planando), sopro/penas e som `flap` a cada batida. **Não há dano de queda no jogo** (fica em "Depois"), então "sem dano de queda" das asas ainda não muda nada.
Medido: pulo simples 1,52 blocos; segurando Espaço com as asas ~5,95 (26 quadros de batida); planeio a −7,5 blocos/s. Testes: `test_wings` (sem asas nada muda, 24-27
quadros de voo, sobe ~3-4 blocos a mais, planeio a 1/3, sem Espaço cai normal, tempo só gasta segurando, F liga/desliga o criativo, atravessa e não leva dano) e HUD
(aviso e barra) na integração. Prints: `asas` (3ª pessoa de costas, batendo) e `criativo`.

## 6 — Loot de cavernas/baús e consumíveis ✅

**Wiki (Chest, Gold/Shadow Chest, Life Crystal, poções):** cada baú tem **1 item principal** (sorteado) + itens comuns sorteados com
faixa de quantidade; Underground (Band of Regeneration, Magic Mirror, Cloud in a Bottle, Hermes Boots, Mace, Shoe Spikes — 1/6 cada;
comuns: Lesser Healing 3-5 50%, Regeneration 1-2 2/3, Recall 2-4, Torch 10-20, Silver Coin 50-89 50%, barras 5-14, flechas 25-49...);
Cavern/lava (Extractinator, Flare Gun; Healing 3-5, Spelunker, Featherfall..., Gold Coin 1-2, barra de meteorito 15-29 no fundo);
Shadow Chest (Sunfury, Flower of Fire, Flamelash, Dark Lance, Hellwing Bow; Restoration 15-20, barras de meteorito e ouro, Gold
Coin 2-4); Dungeon (Muramasa, Cobalt Shield, Aqua Scepter, Blue Moon, Magic Missile, Valor, Handgun + Shadow Key). **Life Crystal:**
+20 de vida máxima (até 400) e cura 20; aparece no subsolo e abaixo (não no submundo nem no dungeon); ~100 em mundo pequeno.
Lesser Healing 50 (Potion Sickness 60 s), Healing 100; Ironskin +8 de defesa por 8 min; Regeneration +2 vida/s; Swiftness +25%.
**Hoje:** `world.gd:chest_at` sorteia 8 itens fixos (3 acessórios a 12%, flechas, tochas, barras) sem camada; sem Life Crystal, sem
poções, sem buffs (a GUI reserva a fileira e não há sistema). `MAX_HP` é constante 100 e o HUD monta 5 corações.
**Plano**
1. Tabelas em `data/base/loot.json` (camada → principal + comuns) com os itens que existem e os que entram agora (poções, Cloud in a
   Bottle, Magic Mirror/Recall); `chest_at` sorteia por camada (altura do baú) e lê o dado.
2. `life_crystal` (bloco em forma de cristal que não balança, quebra com picareta, ~1 por 3 chunks nas cavernas) e item consumível
   (+20, até 400); `player.max_hp` variável (save), corações em duas fileiras de 10 no HUD.
3. **Buffs** (`buffs.json` + `player.buffs`): ícone e tempo sob a hotbar; Ironskin, Regeneration, Swiftness, Mining, Archery, Shine,
   Night Owl e o debuff Potion Sickness; poções: beber = usar o item (use time 17 quadros, 30 no cristal).
4. Loot dos orbes: 1ª quebra = Musket/The Undertaker + 100 balas; depois 20% de cada (Vilethorn, Ball O' Hurt, Band of Starpower / Crimson Rod,
   The Rotted Fork, Panic Necklace) — só o que existir no jogo.
**Precisa de mundo novo** (geração de cristais/baús).
**Teste/print:** `test_loot`: 1 principal exato por baú; frequências das faixas em 4000 baús; Life Crystal soma 20 e para em 400; Potion
Sickness bloqueia cura por 60 s; buff expira. Prints `bau` (loot) e `cristal` (na caverna).

**Feito:** `loot.json` + `loot.gd` (1 principal entre Band of Regeneration / Magic Mirror / Cloud in a Bottle / Hermes Boots, comuns por camada com conjuntos
exclusivos; subsolo, cavernas e "lava" por altura; baús agora nascem nas 3 camadas). **Life Crystal**: bloco `crystal` (cruz brilhante, mira acerta, 1 golpe), ~55 por mundo,
item +20 de vida máxima até 400 (`max_hp` no save; corações em 2 fileiras, minimapa desce). **Consumíveis**: Lesser Healing (50, Doença da poção 60 s), Ironskin,
Regeneration, Swiftness, Mining, Archery (`buffs.json`, `Buffs`, ícones com tempo ao lado da hotbar, clique direito cancela, salvos no personagem), Recall Potion, Magic Mirror
(teleporte para o spawn) e Cloud in a Bottle (pulo extra). Teclas H/Q cura, B buffs. **Orbes**: Musket / The Undertaker + 100 Musket Balls (1ª sempre, depois 20%);
Vilethorn/Crimson Rod/Band of Starpower entram com a magia (item 7); Ball O' Hurt, Rotted Fork, Panic Necklace e pets ficam de fora. Shiny Red Balloon e Fledgling Wings
são de ilhas no céu (Depois). Shine/Night Owl/Spelunker precisam de luz dinâmica (Depois). Testes: `test_consumables`, `test_life_crystal`, `test_loot`; prints `pocoes`,
`pocoes_inv`, `cristal`, `bau`. **Precisa de mundo novo** (cristais e baús por camada).

## 7 — Mana e magia ✅

**Wiki (Mana, Mana Crystal, magia):** mana inicial 20 (1 estrela = 20); **+20 por Mana Crystal** até 200 (feito de 5 Fallen Stars; a estrela
cai à noite e some ao amanhecer); regeneração/s = (máx/3 + 1 + bônus) × (2 parado) × (mana/máx·0,5 + 0,5) × (0,05 se usando mana) ÷ 2; com pouca
mana ainda se usa a arma com **60% de penalidade** de velocidade; Mana Potion 100 (Mana Sickness 5 s), Lesser 50.
Armas (Cargo): Wand of Sparking 14 dano/2 mana/use 26; Vilethorn 10/10/28; Space Gun 20/6/17 (autoswing); Book of Skulls 29/18/32
(autoswing); Aqua Scepter 27/7/16 (autoswing); Flower of Fire 48/12/16; Magic Missile 35/14/22.
**Hoje:** nada de mana; a barra de vida ocupa o canto e `use_item` só conhece minerar, bater, atirar, balde e invocar.
**Plano:** (1) `player.mana/max_mana` + regeneração da wiki + estrelas ao lado dos corações (a GUI reserva o lugar); (2) itens com
`mana` usam o projétil pelo mesmo `spawn_projectile` das espadas mágicas (Space Gun, Vilethorn, Wand of Sparking, Aqua Scepter,
Book of Skulls, Flower of Fire entram como dado + projétil em `projectiles.json`); (3) Fallen Star à noite (cai, brilha, some ao amanhecer)
→ receita do Mana Crystal; poções de mana; (4) `Meteor armor` zera o custo do Space Gun (dado).
**Teste/print:** `test_mana`: regeneração em 10 s bate a fórmula (parado e andando); uso sem mana leva ×1,6; cristal 20→200; poção.
Print `magia` (Space Gun) e `inventario` com as estrelas.

**Feito:** `player.mana/max_mana` (20, +20 por Mana Crystal até 200; save), regeneração pela fórmula da wiki (parado ×2, fator mana/máx, ×0,05 usando mana, ÷2 por
segundo), estrelas azuis (uma por 20) à direita dos corações. Magia: item com `cost` (mana) e `shoot`: Wand of Sparking (14, 2 mana, use 26, crítico 14%), Space Gun (20, 6,
autoswing), Vilethorn (10, 10, perfura 2; 20% da Shadow Orb); sem mana ainda usa, ciclo ×1,6. Mana Potion (100) e Lesser (50), J bebe. Fallen Star cai à noite e some de
dia; Mana Crystal = 5 estrelas. Wand/Lesser Mana nos baús, Space Gun 8% nos baús fundos. Testes `test_mana`; print `magia`. Meteor armor zerando o custo do Space Gun fica para "Depois".

## 8 — NPCs ✅

**Wiki (Guide, Merchant, Nurse, Housing):** o **Guide** nasce com o mundo (Help: dicas; Crafting: mostra receitas do item dado), depois
se muda para a 1ª casa; o **Merchant** chega com > 50 de prata no inventário (loja: Copper Pickaxe 5 prata, Copper Axe 4, Torch 50
cobre, Lesser Healing 3 prata, Lesser Mana 1, flechas 5 cobre, Rope, Iron Anvil 50 prata...); a **Nurse** chega com vida máxima > 100 (cura
1 cobre por ponto). Casa válida: cômodo fechado com parede de fundo, luz, mesa e cadeira (o jogo não tem parede de fundo).
**Hoje:** só o Velho do dungeon (`ai: npc`, `entities.talk`); sem diálogo genérico, loja nem moradia.
**Plano** (mínimo, sem casa; moradia fica para "Depois"): (1) painel de diálogo (nome, fala, botões Help / Loja / Curar) reutilizando o
painel do baú; (2) **Guide** no spawn desde o começo com as falas da wiki e "Crafting" mostrando receitas do item do cursor; (3) Merchant
e Nurse chegam com as condições da wiki e ficam perto do spawn; a loja cobra dos slots de moeda; (4) animação: andam devagar de um lado
a outro, param e olham para o jogador ao falar. Moradia (casa válida) fica para "Depois".
**Teste/print:** `test_npc`: Merchant não chega com 49 de prata e chega com 51; compra tira moedas certas; Nurse cura o custo certo. Prints
`guia` (diálogo) e `loja`.

**Feito:** `guide`, `merchant`, `nurse` em enemies.json (ai npc, viram para o jogador). `Entities._town`: o Guide já existe, o Merchant chega com mais de 50 de prata, a Nurse com
vida máxima > 100 (salvos em `world.npcs`; voltam se sumirem). Botão direito abre o painel de conversa da HUD (`open_npc`): Guide com dicas, loja do Merchant (preços da wiki, `Inventory.pay`
com troco), Nurse cura o que falta por 1 cobre/ponto. Sem casa/moradia (fica em "Depois"). `test_npc` + integração; prints `guia`, `loja`.

---------------------------------------------------------------------------------------------------------------------------------

## Perguntas ao dono (respondi com o padrão marcado; diga se quer outro)

1. **Descer no modo criativo (F):** o Terraria não tem tecla de descer (Ctrl = Smart Cursor, C = Journey). Padrão: **Espaço sobe, C desce**
   (só no modo criativo). Prefere Ctrl?
2. **Shift:** na wiki é *Auto Select* (escolhe a ferramenta/tocha), não "atirar/arremessar". Padrão: **Auto Select**, e a corrida sai (a
   base sobe de 4,5 para 6,6 blocos/s = 11 tiles/s da wiki). Você queria outra coisa no Shift (ex.: arremessar glowstick)?
3. **Botão direito:** no Terraria só **interage** (baú, NPC); colocar bloco é o esquerdo. Padrão: **mover a colocação para o esquerdo**.
4. **Cura rápida:** a wiki manda **H** (o doc antigo dizia Q). Padrão: H e Q juntos; J mana, B buffs.
5. **Esc:** abre o inventário e a pausa vira o botão Settings. Padrão: assim; a tela pausa **só** dentro do Settings.
6. **E:** hoje abre o inventário; na wiki é gancho. Padrão: **E livre** (sem função até existir gancho).
7. **Mapa explorado:** a wiki salva no personagem; eu salvo no mundo (mais simples). Ok?
8. **Martelos:** a wiki exige martelo para Shadow Orb/Crimson Heart; hoje quebra com picareta. Padrão: **adicionar martelos** e exigir.
9. **Verme:** 24 segmentos (wiki 67) e escavando/caindo como o Terraria. Padrão: manter 24; quer 67 (~80 blocos de comprimento)?
10. **Vida/mana nos saves:** salvo `max_hp`/`max_mana` no `.plr` (save v2 continua legível). Personagens antigos ficam com 100/20.
11. **Mundo novo:** cristais, baús por camada e mudas mudam a geração — precisa criar mundo novo para ver tudo.

## Sessão 3 — mundo de teste e melhorias ✅ (tudo com teste em tests/run.gd; prints em textures/shot_*.png)

- **Mundo de teste** (`test_world.gd`, botão "Mundo de teste" na tela de mundos; flag `test` no .wld, seed 1337): arena plana de 89 x 74 no nascimento, gerada dentro de
  `WorldGen.generate` (o `.wld` só guarda a flag). Um baú por categoria **saído de `Items.names`** (Armas, Ferramentas, Armaduras, Acessórios, Poções e consumíveis, Blocos e minérios,
  Moedas e munição, Materiais e barras, Chefes e invocadores; passa de 40 slots = mais um baú "n/m"), todos os blocos de `Blocks.ids` em fileiras com o nome em cima (líquido afundado
  no gramado; só os níveis parciais de líquido ficam de fora), tochas de 9 em 9, Guide/Merchant/Nurse/Velho parados perto, vitrine com um de cada inimigo que não é chefe (parados,
  ainda levam golpe), duas casas de demonstração (uma válida, uma sem cadeira). **F9** abre o painel (hora, relógio parado, vida/mana máximas, +10 de ouro, criativo, hardmode
  liga/desliga, os 6 chefes, vitrine, limpar inimigos, meteorito, reabastecer baús, viagem: nascimento/submundo/dungeon/bioma do mal/Hallow/ilha no céu); a mira mostra o nome do bloco
  no rodapé (F10). Testes: `test_testworld` (todo item em exatamente um baú, todo bloco na fileira, gramado plano e limpo, `chest_at`, save, cena com F9 e atalhos) + fase 4 da integração
  + `menu_flow` (o botão abre o mundo). Prints `teste_*`. Desligar o hardmode só volta os spawns/geração: o terreno já convertido fica.
- **Moedas e munição em qualquer slot**: slots de moeda clicáveis (`click_coin`: leva a pilha à mão / guarda moeda do mesmo tipo, 100 sobem de tipo); `coin_value`/`pay` contam também as
  moedas em slots comuns (pagar recolhe tudo para os slots de moeda: `ponytail:`); munição apanhada vai primeiro aos slots de munição (`add`), `total`/`remove` contam esses slots; Shift+clique
  do baú usa `take_stack` (= apanhar do chão). Teste `test_coins_ammo` (inclui save).
- **Fallen Star**: o `Fallen_Star.png` da wiki é um GIF; agora `Fallen_Star_(old)` (PNG estático) + estrela procedural (`star` em atlas.gd) de reserva; `wiki_image` confere a assinatura PNG
  (GIF/truncado/vazio → procedural) e o `fetch-sprites.sh` não grava o que não é PNG. Prints `estrela`, `estrela_chao`.
- **"Subsolo bugado" do verme**: reproduzido como voo criativo com a câmera dentro do bloco (dava para ver o mundo através da terra, faces de trás não existem). Agora a tela escurece
  (`hud.dark`, atrás do minimapa). Se o dono ainda vir isso **fora do criativo**, pedir posição/ângulo. Prints `dentro_terra*`.
- **Guia**: dicas do momento (`_guide_tips`, na ordem do jogo) e modo **Criação** (espaço para o item + lista de `Crafting.uses_of`). **Moradia** (`housing.gd`): cômodo fechado por blocos e portas
  (busca em 3D, 12–400 blocos de ar) com tocha, bancada e cadeira; botão direito na cadeira diz o que falta; Guide/Merchant/Nurse se mudam sozinhos (`Entities._homes`, `world.homes` no save),
  voltam ao nascimento se a casa for desfeita. Blocos `chair`, `door` (sólida) e `door_open` (painel fino; botão direito abre/fecha os 2 blocos), receitas da wiki (4 e 6 de madeira).
- **Queda e afogamento** (wiki Fall damage / Breath meter / Drowning): 25 tiles (15 blocos) seguros, 10 de dano por tile a mais (a defesa reduz; asas, água, Lucky Horseshoe e teletransporte
  anulam; o pulo do Cloud in a Bottle recomeça a queda); fôlego 23,3 s, depois 17 de vida por segundo direto; bolhas na tela.
- **Poções de luz**: Shine (aura de 10 blocos), Night Owl (aura fraca de 15) via `aura` no shader dos blocos, Spelunker (`spelunker.gd`); 10 min; entram nos baús.
- **Itens das orbes**: Space Gun sem mana com o conjunto Meteor (`free_cost` em armor_sets.json), Band of Starpower (+40 de mana máx.), Panic Necklace, The Rotted Fork (estocada + onda),
  Crimson Rod (nuvem que chove sangue: 30 de mana, uma por vez, 5 min; a gota cai sobre o inimigo debaixo dela). Ball O' Hurt e os pets ficam de fora.
- **Ilhas flutuantes** (mundo novo): 3 por mundo, acima de `SKY_BASE` (110), casa de sunplate com Skyware Chest (Shiny Red Balloon, Lucky Horseshoe na ordem; Fledgling Wings em 1/4 dos
  baús — a wiki dá 1/40, subi porque são só 3 ilhas —, 50–100 nuvens + o loot comum de superfície). O céu não escurece a terra (`_light` e `surface_y` ignoram y ≥ SKY_BASE).
- **Mundo em ilha** (mundo novo): terra até 104 blocos do centro, costa de 18 e oceano de 14 de fundo em volta; a borda do mundo é uma parede para o jogador; nada nasce no fundo do mar.
- **Criação com o martelo** (ícone alterna a lista completa), **Ctrl = cursor inteligente** (mira dourada), **gancho na tecla E** (Grappling Hook: alcance 18,75 tiles, lançamento 11,5 px/quadro,
  puxão 11 px/quadro; Chain 15 por barra de ferro e Hook 4% dos Angry Bones para criá-lo), **sons** ligados (pickup, coin, swing, bow, splash, baú).
- **Boneco mais adulto** (cabeça 0,78 → 0,68, olhos menores, ombros mais largos); a tela de criação de personagem não recarrega mais ao escolher cor.

**Perguntas ao dono (padrão marcado):** (1) Fledgling Wings em 1/4 dos baús de ilha em vez de 1/40: ok? (2) o "Mundo de teste" tem seed fixa 1337 (Corrupção ou Carmesim depende dela): quer uma segunda seed?
(3) desligar hardmode não desfaz o terreno: precisa de "restaurar"? (4) o que exatamente estava "bugado" no verme (posição/ângulo se ainda acontecer fora do criativo)?

## Depois

- Ball O' Hurt (mangual), Starfury e Celestial Magnet (Skyware), Sky Mill; mais asas no hardmode.
- Animações de arma em 3D pleno (hoje sprite extrudado: é o visual "Terraria em 3D"; modelos de primitivas seriam outra estética).
- Editar personagem existente na tela de criação; mobs mais "adultos" além do boneco (slimes/olhos são de outro estilo).
- Casa: habitantes andando pelo cômodo e voltando para casa à noite; mais habitantes (Demolitionist etc.); parede de fundo (o jogo não tem).
- Hardmode/Calamity (docs/ROADMAP.md).
