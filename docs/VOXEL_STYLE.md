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

## Fluxo
`models.json` (sprite da wiki + cores) → receita em `scripts/voxel/recipes.gd` → `assets/models/gen/*.vox` (update.sh) → jogo.
Retoque: copie o `.vox` para `assets/models/` e edite; ele vence o gerado e o update nunca o toca. Conferir sem tela: `tests/model_preview.gd`.
