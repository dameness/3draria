# Estilo Voxel (Trove com o detalhe do Terraria)

1 pixel do sprite do Terraria = 1 voxel. Um modelo é um `.vox` (MagicaVoxel: você abre e retoca; Goxel também serve) gerado por uma receita curta.

## Escala
- **1 voxel = 0,0375 bloco** (`VoxMesh.V`): 1 tile do Terraria (16 px) = 0,6 bloco. Personagem = 48 voxels (1,8 bloco): cabeça 11 + cabelo, tronco 13,
  pernas 20, braços 5x5 (proporção das articulações do `player_model.gd`; `VoxRecipes.PIV`).
- Item na mão: o maior lado vira o comprimento de antes (`HeldItem.LENGTH` etc.); só a espessura é nova.
- Bloco com modelo: `"size": [largura, altura]` em tiles da wiki; o modelo inteiro cabe nessa largura (Living Loom 3x3 tiles = 1,8 bloco) e é só visual
  (a seleção e a colisão são as da célula do bloco; `solid: false`, como móvel do Terraria).
- Limites de tamanho: item ≤ 64x64x8 voxels, armadura = casca de 1 voxel sobre o corpo (13x13x13 cabeça), estrutura ≤ 64x64x16, inimigo comum ≤ 64³,
  chefe ≤ 128³ (o `.vox` aceita até 256 por lado). Malha: só faces expostas, então custo = superfície, não volume.

## Regras (Trove)
- Formas blocadas: cantos cortados no máximo 1 voxel; nada de curva fingida com voxel solto.
- Sem ligação só por quina (dois voxels que se tocam só na aresta/vértice somem da vista de lado): sempre uma face em comum.
- Sem voxel flutuante imitando partícula: fagulha, brasa e poeira são `fx.gd`, não modelo.
- Cor: a paleta do sprite da wiki + **1 tom de luz e 1 de sombra** por cor (o AO do mesher escurece os cantos; não pinte sombra à mão).
  Sem preto puro (vira `0c0c0c`). Uma cor por região: nada de ruído.
- Emissivo só onde o Terraria brilha (lava, olhos, cristais): liste as cores em `emissive` no `models.json` (vão no `.json` ao lado do `.vox`);
  elas ignoram a luz, pulsam em onda (`shaders/voxel.gdshader`) e as fagulhas saem dos topos delas (`"sparks"`).
- Voxel `255,0,255` = ponto de encaixe (pivô: ombro, quadril, pescoço, empunhadura); não vira malha.
- Eixos do MagicaVoxel: x largura, y profundidade (frente = y pequeno), z altura. O jogo gira para a frente olhar para -Z.

## Padrão das estruturas (aprovado pelo dono na leva 1; vale para toda estrutura nova, Living Loom e similares)
Receita `prop` (ou `loom`) + campos do `models.json`; nada de código novo por estrutura:
- Sprite da wiki **de frente** extrudado (`depth`), nunca a malha chapada: dê volume com `profile` (domo da tampa, tampo que sobressai, chifre fino, cintura estreita) ou `round` (gema/altar).
- **`"sides": true`**: as laterais repetem a textura da frente (`side_texture`), em vez de lajes lisas. `plain` pinta o miolo do contorno escuro. Exceção: peça com afinamento forte (bigorna).
- Emissivo recuado (`recess`) onde há boca/fogo; vão no meio (`legs`) onde há pernas.
- Bloco: `"shape": "model"`, **sólido** (colide como bloco inteiro) e o mesher não o usa para esconder faces vizinhas (`Blocks.cull`: o modelo é menor que a célula, senão abre buraco no chão/parede).
- Largura = pixels do sprite × 1 voxel (0,0375): ~1,1 a 1,2 bloco; altar/larva reduzidos para 2,5 tiles. Não giram (frente = -Z). Fino demais ou de perfil (porta, cadeira, tocha, corda, trilho) fica no automático.
- Conferir: `tests/model_preview.gd -- block:nome` (4 ângulos) e `tests/screenshot.gd -- estacoes`.

## Padrão das armaduras (leva 2)
- Conjunto = casca por peça (head 13³, body, arm, leg) no quadro do corpo; **rosto aberto** nos de placa (o rosto e os olhos aparecem; o cabelo some), `closed` só no Meteor, capuz de pano no Ninja.
- Metais/madeira/Meteor/Ninja: receita `armor_plate`, uma só para todos (calota com nariz, peitoral com gola/cós/costura, ombreira grande, manga até o cotovelo, joelheira, bota); só a paleta (ícones) e poucas opções mudam. Conjunto novo = uma linha em `models.json` + `"model"` em `armor_sets.json`.
- Brilho/projeção do sprite vestido (`armor_set`) só para conjuntos com detalhe emissivo que o ícone não dá (Molten).

## Padrão das armas e ferramentas (leva 3)
- Todo item já tem modelo automático; a espessura vem da categoria (`VoxRecipes.auto_cap`): lâmina, arco e ferramenta finos (cap 2), arma de fogo/varinha/livro cheios (2 a 4), cabeça de flail redonda (3 a 6). Regra nova = uma linha ali, não um campo por item.
- Receita `weapon` (models.json) só para destaque: brilho (`emissive`, moderado), `cap` próprio ou `round: true` (bomba, granada: esfera). A pose na mão não muda (ver PROMPT_LEVAS).

## Padrão dos inimigos de sprite (leva 4)
- Todo inimigo sem `model` em código (sprite da wiki) vira voxel sozinho (`VoxRecipes.creature`): sprite inflado, o maior lado = `size` do def, sempre virado para o jogador. Receita só para destaque: `wings` (morcegos: asas em V, meia-imagem esquerda/direita que bate em `EnemyModel.animate`), `emissive`, `cap`.
- Slimes, olhos, vermes, caveiras e o Wall of Flesh continuam nos modelos de código; humanoides usam o corpo voxel. Ver `tests/model_preview.gd -- enemy:nome`.

## Fluxo
`models.json` (sprite da wiki + cores) → receita em `scripts/voxel/recipes.gd` → `assets/models/gen/*.vox` (update.sh) → jogo.
Retoque: copie o `.vox` para `assets/models/` e edite; ele vence o gerado e o update nunca o toca. Conferir sem tela: `tests/model_preview.gd`.
