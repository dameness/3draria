# data/ — conteúdo do jogo

Cada pacote (`base/`, depois `calamity/`) tem os mesmos JSON. Os sistemas em `scripts/` só leem; conteúdo novo = editar JSON.
**Ids são a posição na lista** em `blocks.json` e `items.json`: só acrescente no fim (o save grava ids de bloco).

## textures.json — tudo que é desenhado
`nome: {wiki?, crop?, pattern?, colors?, top_colors?}`.
- `wiki`: arquivo da wiki (sem .png) baixado por `scripts/fetch-sprites.sh` em `assets/wiki/` (fora do git).
  Com `crop: [x, y]` recorta 16x16 para face de bloco; sem crop é ícone de item em tamanho original.
  `recolor: {"#de": "#para"}` troca cores do recorte (ex.: contorno preto da grama).
- Só PNG de verdade serve: a wiki às vezes serve GIF com nome `.png` (ex.: `Fallen_Star`, animada); o carregador confere a assinatura PNG e cai no procedural,
  e o `fetch-sprites.sh` nem grava. Procure outro arquivo (`Fallen_Star_(old)`) e ponha em `wiki`.
- Sem o arquivo (ou sem `wiki`), `scripts/atlas.gd` pinta `pattern` num tile 16x16 com RNG semeado pelo nome.
  Entrada só com `wiki` (ícone) não tem fallback próprio: o item-bloco usa a face lateral.
- Blocos (opacos): `noise` (pixels sorteados da paleta), `grass_side` (topo com top_colors), `stripes`, `rings`,
  `ore` (base + manchas de top_colors), `planks`, `bricks` (top_colors = argamassa), `liquid` (ondas suaves que
  emendam; paleta do escuro ao claro: água e lava).
- Ícones (fundo transparente): `bar`, `pickaxe`, `sword`, `bow`, `arrow`, `blob` (+ pupila se top_colors), `torch`, `star` (estrela; top_colors = faíscas).
- Plantas do mundo (fundo transparente, desenhadas em cruz): `tuft` (capim), `flower` (colors = pétala, miolo;
  top_colors = haste), `mushroom`.
- Padrão novo = um `match` em atlas.gd. Paleta curta (2-4 cores) mantém o estilo.
- Prévia ampliada (faces + ícones): `.tools/godot --headless -s tests/atlas_preview.gd` → `textures/preview.png`.

## blocks.json
`{name, tiles:{all|top|side|bottom}, icon?, station_as? (conta como outra estação), solid?=true, breakable?=true, power?=0 (picareta mínima), mine?=1 (dano por golpe = poder da picareta × mine; 100 quebra), drop?=name ("" = nada)}`.
`mine` segue a wiki (Pickaxe power): terra, areia, cinza e grama 2; pedra e minérios 1; pedra infernal 0,5; tocha 100 (1 golpe). A grama absorve o golpe que a quebraria e vira terra.
`axe: true` = só machado quebra (tronco); `hammer: true` = só martelo quebra (Shadow Orb, Crimson Heart: wiki "any hammer"); `Items.power_on(item, bloco)` escolhe o poder.
`icon`: textura do ícone do item-bloco (ex.: `dirt_item` → `Dirt_Block.png`).
`shape`: forma não cúbica e não sólida: `"torch"`, `"plant"` (dois quadros em cruz que balançam ao vento; a mira
atravessa e colocar bloco substitui; some se o chão sumir), `"liquid"` (água/lava: a mira atravessa; água = superfície
translúcida à parte, `"glow": true` = brilha sozinho, como a lava). Líquido flui (scripts/liquid.gd) e tem nível 1-8 por bloco:
`water`/`lava` são o nível 8 (cheio) e `water_1..7`/`lava_1..7` (`"liquid": "water", "level": n`) os níveis parciais; a altura da
superfície é proporcional ao nível. Líquido novo = uma entrada cheia + 7 níveis, no fim da lista.
`shape: "door"`: painel fino na borda do bloco, sem colisão (porta aberta; `door` é o cubo sólido: as duas contam como parede na moradia). `shape: "rope"`: fio fino não sólido; dentro dele Espaço sobe, C desce, sem tecla pendura (player.gd `on_rope`). Forma nova = um `match` em `chunk_mesher._shape`.
`light`: raio de luz em blocos (tocha = 10; lava não entra: só brilha nas próprias faces).
`grass: true`: é grama (a muda de árvore só pega em cima dela).
`clear: true`: a luz do céu passa (tronco e folhas: a copa só sombreia de leve).
Todo bloco sólido e quebrável vira item automaticamente (ícone = textura lateral). Plantas e líquidos são
`breakable: false`: não viram item.

## items.json (itens que não são bloco)
`{name, icon, stack?=9999, rarity?=0, pick_power?, axe_power?, hammer_power?, use_time? (s), tool_speed? (quadros de 1/60 s), autoswing? (bool), damage?, reach?, knockback?, ammo?, shoot_speed?, use_style?, places? (bloco que o item coloca)}`.
`ammo`: classe de munição (ex.: "arrow"); itens com `ammo_class` igual servem. `summon`: chefe invocado.
`sprite_angle`: para onde o sprite aponta em graus (0 = direita, 90 = cima; padrão 45, como as armas do Terraria;
flecha = −90). `shoot`/`projectile`: nome em projectiles.json. `effects`: {glow, trail, particles} (cores).
`use_style`: swing | thrust | shoot | hold (animação na mão; padrão deduzido: munição → shoot, arma/ferramenta → swing).
Uso pelo botão esquerdo: pick_power > 0 minera; com `ammo` atira; com `damage` golpeia; `places` coloca. Um clique = um uso; segurar repete só com
`autoswing` (padrão true para quem coloca bloco e para baldes; picaretas, machados e as espadas da wiki marcam no dado). `use_time` é o use time da wiki
(dica e ciclo das armas); `tool_speed` é o intervalo entre golpes no bloco (picareta/machado) e vira o ciclo da ferramenta (`Items.use_dur`).
Recuo de flecha soma ao da arma (`knockback` na munição).
`tip`: texto do item no balão, traduzido da linha "Tooltip" da wiki (`\n` separa linhas); `crit`: chance de crítico da arma (padrão 0.04). O resto do balão (dano, crítico, velocidade, recuo, "Consumível", "Material" = entra em alguma receita) sai dos campos em `ui.gd item_tip`; só escreva `tip` se o efeito existir no jogo.

Acessório: `accessory: {speed?, jump?, regen?, defense?, max_mana?, panic?, no_fall?, double_jump?, wall_slide? (desliza e pula da parede), lava? (s de imunidade), radar? (raio; vale também no inventário), bees? (Honey Comb), wings?: {time (s de voo), lift (blocos/s)}}` (bônus somam; só um par de asas vale).
Na mão: `slowfall` (Umbrella: queda máxima 3 blocos/s, sem dano) e `zoom` (Binoculars). `throw: <projétil>` joga o item consumível (bomba, granada, shuriken...); `cost: 0` = magia sem mana (Slime Gun).
Armadura: `armor: head|body|legs`, `defense`, `set`. `armor_sets.json`: `{conjunto: {pieces: [...], defense: bônus, free_cost?: [armas sem custo de mana com o conjunto completo]}}`.
Flail: `flail: <projétil>` (projectiles.json: `flail: true`, `color`, `size`, `length` em blocos, `life`); `shoot_speed` = velocity da wiki. Segurar gira (60% dano, 35% recuo), soltar arremessa e volta; um no ar por vez.
Magia: `cost` (mana) + `shoot` (projétil); `cloud: alcance` faz a arma soltar uma nuvem que chove (`blood_drop`) em vez de um projétil (Crimson Rod).
Gancho: `hook: {range, launch, pull}` (blocos, blocos/s); a tecla E usa o primeiro gancho do inventário. Poção/buff: `buff` + `buff_time` (s), nomes em `buffs.json` (efeitos `defense speed regen mining arrow_damage arrow_speed shine owl spelunker`).
`pickup: {heal?, mana?}`: coração/estrela, consumidos ao pegar (não entram no inventário).
Item novo entra no FIM de `items.json` e de `blocks.json` (o mundo de teste o põe sozinho no baú da categoria: `TestWorld.category`).

## recipes.json
`{result, count?=1, needs:{item: n}, station?: bloco}`; a estação precisa estar a até 4 blocos do jogador.

## ores.json
`{block, group?, in?=["stone","dirt"], min_y, max_y, veins (por chunk), size}`. Mesmo `group` = alternativos
(cobre/estanho...): a seed escolhe um por mundo. Altura do mundo: 128 (submundo < 20, cavernas < 48).

## enemies.json
`{name, ai: hop|walk|fly|eye_of_cthulhu, model?: eye|slime|humanoid (senão sprite extrudado), iris?, colors?,
life, damage, defense, speed, size:[largura, altura], color, blood? (cor das gotas ao levar golpe; padrão = color), sprite?,
spawn: day|night|any|none, kb_resist? (resistência a recuo da tabela NPCs da wiki; negativo = recua mais), boss?, minion?, phase2?:{below, damage, defense, sprite}, drops:[{item, min, max, chance}]}`.
`biome?` (nome ou lista): onde nasce (sem ele: superfície comum): `underground` (terra, ≥ 8 blocos abaixo da superfície) `cavern` (rocha, y < 48) `underworld` `dungeon` `corruption` `crimson` `hallow` `meteorite` (perto de uma cratera) `snow` (superfície da neve) `ice` (debaixo dela) `desert` `desert_cave` `jungle` `jungle_cave`. `worm` + `group` (verme; `part: true` nos def de corpo/rabo, que não nascem sozinhos; `noclip`). `final_drops`: só o último segmento/parte do grupo. `pick`: em `drops`, só um item de cada grupo cai. `ai: caster` + `shoot: {projectile, damage, speed, count}`: conjurador (teleporta e atira esferas; `rare`: chance de valer o sorteio do spawn). `heart`: chance de soltar Heart (senão 1/12 ou 1/24; estrela 13/24; só inimigos que soltam moedas). Moedas: valor da wiki em cobre ±40%.
Escala: 1 tile do Terraria ≈ 0,6 bloco (jogador de 3 tiles = 1,8). IA nova = um `match` em `scripts/enemy.gd`.
Chefes atravessam blocos e vão embora ao amanhecer; itens com `summon` os invocam (só à noite).

## projectiles.json
`{name, sprite? (textura, billboard) | model_item? (ícone extrudado), size, gravity, life (s), pierce, glow?}`.
Extras: `fuse`+`radius` (bomba; `contact` explode ao tocar inimigo, `keep_blocks` não quebra blocos, `bees` solta abelhas), `spin` (gira deitado), `stick` (gruda no bloco até o fim da vida: sinalizador).
Dano/velocidade vêm da arma (feixe = dano da espada; flecha = arco + flecha).

## loot.json
`{camada: {main: [itens, um por baú], common: [{items, min, max, chance}]}}`, camadas `surface` `underground` `cavern` `lava` `sky` (Skyware Chest das ilhas, pela altura; as ilhas dão o item principal na ordem).
Um principal pode pesar menos: `{"item", "weight"}` (os outros pesam 1). `bundle: {item: {item, min, max}}` põe outro item junto (Flare Gun + Flares).

## rarities.json
`raridade: cor` (valores do código do Terraria, −1 a 11). Pinta o feixe do item solto.

Números: conferir na wiki (links no CLAUDE.md da raiz) antes de criar conteúdo.
