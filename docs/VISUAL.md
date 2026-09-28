# Visual Terraria em 3D — estrutura

Objetivo: cada item tem **o mesmo ícone do Terraria** e, na mão, uma **versão 3D derivada desse sprite** com os
**mesmos efeitos** (ex.: Terra Blade brilha verde, deixa rastro e dispara o Terra Beam). Inspiração: a colaboração
Palworld × Terraria (armas do Terraria reinterpretadas em 3D com brilho e partículas).

## Regra de assets (aprovada pelo dono)
- **Ícones = os do Terraria/Calamity, exatos.** O 3D *evolui* a partir deles: parte do sprite, mas pode ganhar forma,
  materiais e efeitos próprios; itens novos do dono podem ter visual original (sem sprite da wiki).
- Os sprites são do Terraria (© Re-Logic). Uso pessoal, sem distribuição: **não vão para o git**.
- `scripts/fetch-sprites.sh` baixa da wiki (terraria.wiki.gg / calamitymod.wiki.gg) para `assets/wiki/` (ignorado
  pelo git), igual ao binário do Godot. Idempotente; roda no setup local e no SessionStart remoto.
- Sem o sprite baixado, o jogo usa o ícone procedural atual (fallback) — testes headless continuam passando offline.

## Camadas (cada uma é dado + um sistema genérico)
1. **Sprites 2D (ícones e blocos)**
   - Em `textures.json`: `"wiki": "Terra_Blade"` → `assets/wiki/Terra_Blade.png` (ícone em tamanho original).
   - Face de bloco: `"wiki": "Dirt_Block_(placed)", "crop": [16, 16]` (48x48 = 3x3 tiles; centro = face;
     grama usa `[16, 0]`, o tile de cima, para a lateral; o topo verde é procedural com as cores do sprite).
   - Blocos continuam num atlas 16x16; ícones de item são texturas próprias (32x32, 46x54…).
2. **Item 3D na mão (extrusão do sprite = ponto de partida)**
   - Campo `model` no item sobrepõe a extrusão quando o item "evoluir" (malha procedural própria ou .glb feito à mão).
   - Cada pixel opaco vira um voxel fino → malha gerada uma vez e guardada em cache. Funciona para *todo* item sem
     modelagem manual; mantém a silhueta exata do Terraria.
   - "Mais realista": bordas chanfradas, espessura variável (lâmina fina, cabo grosso — pelo alfa/cor), material com
     brilho metálico por paleta e emissão nas cores claras.
   - Visão em 1ª pessoa (viewmodel) + animação de golpe por tipo de uso (`swing`, `thrust`, `shoot`, `hold`).
3. **Efeitos por dados** (`effects` no item; poucos tipos genéricos, combináveis)
   - `glow`: cor de emissão + luz pontual. `trail`: rastro do golpe (cor, largura). `particles`: faíscas/poeira.
   - `shoot`: projétil de `projectiles.json` (sprite da wiki, velocidade, dano, penetração, IA: reto, bumerangue,
     teleguiado…). Ex.: Terra Blade → `{"shoot": "terra_beam", "glow": "#7dff5a", "trail": "#7dff5a"}`.
   - Comportamento único (poucos casos) = função nomeada em `scripts/`, referenciada pelo dado.
4. **Personagem e equipamento** (junto com a câmera 3ª pessoa)
   - Modelo em blocos (estilo voxel) com encaixes: cabeça/corpo/pernas/mão/costas (asas).
   - Armadura: extrusão do sprite do item de armadura + cores da peça; acessórios e asas com efeitos por dados.
5. **Inimigos e chefes**
   - Sprite da wiki extrudado como "papel 3D" ou billboard animado (frames do sprite sheet) — decidir no playtest.

## Ordem proposta
- V1 ✅: fetch-sprites + ícones e blocos exatos + fallback (tests/atlas_preview.gd → textures/preview.png).
- V2 ✅: item extrudado na mão (scripts/item_model.gd + held_item.gd) com swing/thrust/shoot/hold.
  Ver sem GPU: `.tools/godot --headless -s tests/model_preview.gd -- item1 item2` → textures/item_models.png.
- V3 ✅: `effects` (glow/trail/particles) + `projectiles.json`; Enchanted Sword e Terra Blade disparam feixes;
  flechas voam como o ícone extrudado. F8 no jogo dá um kit de teste.
- V4 ✅: tecla V (1ª/3ª pessoa por cima do ombro, câmera desvia de blocos), corpo em blocos animado,
  arma na mão, armaduras dos 8 metais com defesa e bônus de conjunto; cascas coloridas pelo sprite da peça.
- V5: inimigos e chefes em 3D (extrusão como base; modelo próprio nos chefes; humanoides usam o corpo da V4).

## Limites conhecidos
- Blocos do Terraria têm bordas que mudam com os vizinhos (tile framing); em voxel usamos só o tile central.
- Sprites grandes (> 64 px) e animados precisam de recorte de frame no JSON (`frame: [x, y, w, h]`).
- Desempenho: malhas extrudadas são pequenas (≤ 64x64 voxels, com faces internas removidas); uma por item em cache.
