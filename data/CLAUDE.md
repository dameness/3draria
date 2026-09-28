# data/ — conteúdo do jogo

Cada pacote (`base/`, depois `calamity/`) tem os mesmos JSON. Os sistemas em `scripts/` só leem; conteúdo novo = editar JSON.
**Ids são a posição na lista** em `blocks.json` e `items.json`: só acrescente no fim (o save grava ids de bloco).

## textures.json — tudo que é desenhado
`nome: {wiki?, crop?, pattern?, colors?, top_colors?}`.
- `wiki`: arquivo da wiki (sem .png) baixado por `scripts/fetch-sprites.sh` em `assets/wiki/` (fora do git).
  Com `crop: [x, y]` recorta 16x16 para face de bloco; sem crop é ícone de item em tamanho original.
- Sem o arquivo (ou sem `wiki`), `scripts/atlas.gd` pinta `pattern` num tile 16x16 com RNG semeado pelo nome.
  Entrada só com `wiki` (ícone) não tem fallback próprio: o item-bloco usa a face lateral.
- Blocos (opacos): `noise` (pixels sorteados da paleta), `grass_side` (topo com top_colors), `stripes`, `rings`,
  `ore` (base + manchas de top_colors), `planks`, `bricks` (top_colors = argamassa).
- Ícones (fundo transparente): `bar`, `pickaxe`, `sword`, `bow`, `arrow`, `blob` (+ pupila se top_colors), `torch`.
- Padrão novo = um `match` em atlas.gd. Paleta curta (2-4 cores) mantém o estilo.
- Prévia ampliada (faces + ícones): `.tools/godot --headless -s tests/atlas_preview.gd` → `textures/preview.png`.

## blocks.json
`{name, tiles:{all|top|side|bottom}, icon?, solid?=true, breakable?=true, power?=0 (picareta mínima), drop?=name ("" = nada)}`.
`icon`: textura do ícone do item-bloco (ex.: `dirt_item` → `Dirt_Block.png`).
Todo bloco sólido e quebrável vira item automaticamente (ícone = textura lateral).

## items.json (itens que não são bloco)
`{name, icon, stack?=9999, rarity?=0, pick_power?, use_time? (s), damage?, reach?, knockback?, ammo?, shoot_speed?, use_style?}`.
`sprite_angle`: para onde o sprite aponta em graus (0 = direita, 90 = cima; padrão 45, como as armas do Terraria;
flecha = −90). `shoot`/`projectile`: nome em projectiles.json. `effects`: {glow, trail, particles} (cores).
`use_style`: swing | thrust | shoot | hold (animação na mão; padrão deduzido: munição → shoot, arma/ferramenta → swing).
Uso pelo botão esquerdo: pick_power > 0 minera; com `ammo` atira; com `damage` golpeia.

## recipes.json
`{result, count?=1, needs:{item: n}, station?: bloco}`; a estação precisa estar a até 4 blocos do jogador.

## ores.json
`{block, min_y, max_y, veins (por chunk), size (blocos por veio)}`. Altura do mundo: 128 (submundo < 20, cavernas < 48).

## enemies.json
`{name, ai: hop|walk|fly, life, damage, defense, speed, size:[largura, altura], color, spawn: day|night|any,
drops:[{item, min, max, chance}]}`. IA nova = um `match` em `scripts/enemy.gd`.

## projectiles.json
`{name, sprite? (textura, billboard) | model_item? (ícone extrudado), size, gravity, life (s), pierce, glow?}`.
Dano/velocidade vêm da arma (feixe = dano da espada; flecha = arco + flecha).

## rarities.json
`raridade: cor` (valores do código do Terraria, −1 a 11). Pinta o feixe do item solto.

Números: conferir na wiki (links no CLAUDE.md da raiz) antes de criar conteúdo.
