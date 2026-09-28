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
- V5 ✅: inimigos em 3D por `model` (scripts/enemy_model.gd): eye (veias, íris, tentáculos; fase 2 = boca com
  dentes), slime (gelatina translúcida que estica), humanoid (corpo da V4); sem modelo, sprite extrudado.

## Revisão gráfica V6–V9 (o que mudou e por quê)
Motivo: o jogo parecia Minecraft (gramado uniforme, árvores em bolha, céu chapado, HUD padrão do Godot). Prints
de antes/depois em `docs/img/antes_depois_*.png` (esquerda = antes). Meta mantida: 60 fps em GPU integrada (renderer
Compatibility, sem sombras em tempo real, uma malha por chunk com 2 superfícies).
- **V6 céu** (`shaders/sky.gdshader`, `day_night.gd`): gradiente, brilho de pôr do sol, sol, lua com crateras, estrelas,
  2 camadas de nuvens e 3 de montanhas ao horizonte; a névoa usa a cor do horizonte (sem emenda) e escurece em
  caverna / fica vermelha no submundo. Sol e lua giram e a direção da luz muda o tom das faces dos blocos.
- **V7 mundo**: relevo com serras e terraços, planície no nascimento, lagos com praia, árvores do Terraria (tronco alto,
  raízes, galhos com tufos, copa no topo; grade sorteada, iguais entre chunks), capim/flores/cogumelos que balançam,
  água (superfície translúcida com ondas) e lava (brilha), oclusão ambiente por vértice, variação de tom por bloco,
  copa que sombreia de leve. Mesher reescrito (37 → 17 ms/chunk) e chunks gerados uma vez só.
- **V8 interface** (`ui.gd`, `hud.gd`, docs/UI.md): tema Terraria, corações, hotbar + inventário 5x10 no canto superior
  esquerdo, criação em coluna, equipamento à direita, item preso ao cursor, lixeira, dicas com a cor da raridade,
  números de dano flutuantes, tela azul na água / vermelha na lava, flash de dano, pausa de verdade.
- **Personagem e armaduras** (`player_model.gd`): boneco arredondado com contorno e sombreado toon (o traço do sprite),
  cabeça grande, olhos, cabelo espetado; armaduras por peça na paleta do ícone; respira, pisca, anda, pula, nada, golpeia.
- **Combate e movimento**: golpe acerta no impacto da animação (arco na altura do corpo ou cone 3D), câmera balança
  ao andar e treme nos golpes, tochas tremulam.
- **Pendente** (docs/HANDOFF.md): menu com o mundo ao fundo, partículas, arco do golpe, braço em 1ª pessoa, rachaduras
  ao minerar, inimigos mais legíveis (o slime some no gramado).

## Desempenho: o que aprendemos
- Neste Godot, chamadas de função GDScript disputam uma trava entre threads (arrays, operadores e métodos nativos
  não): código que roda em thread (`world_gen.gd`, `chunk_mesher.gd`) não chama função no laço quente.
- `WorkerThreadPool.add_task` sem prioridade alta usa só ~30% das threads.

## Limites conhecidos
- Blocos do Terraria têm bordas que mudam com os vizinhos (tile framing); em voxel usamos só o tile central.
- Sprites grandes (> 64 px) e animados precisam de recorte de frame no JSON (`frame: [x, y, w, h]`).
- Desempenho: malhas extrudadas são pequenas (≤ 64x64 voxels, com faces internas removidas); uma por item em cache.
