# Prompt para a próxima sessão: levas do visual Voxel

Copie o bloco abaixo numa sessão nova (uma leva por sessão).

```
Objetivo: continuar o visual "pixel art 3D do Terraria" (estilo Trove, 1 pixel do sprite = 1 voxel) convertendo UMA leva por sessão. A Leva 0 (infra + pilotos: corpo voxel, Molten, Living Loom, braço da 1ª pessoa) está pronta e aprovada pelo dono.

Leia antes de codar: CLAUDE.md, docs/VOXEL_STYLE.md, docs/LEVAS.md (inventário gerado dos JSON e regra de conteúdo futuro), a camada "Voxel" de docs/VISUAL.md, data/CLAUDE.md (seção models.json) e docs/BACKLOG.md. Código: scripts/voxel/ (vox_model.gd .vox + operações, vox_mesh.gd mesher, recipes.gd receitas, build.gd, levas.gd), shaders/voxel.gdshader, scripts/player_model.gd, scripts/held_item.gd, scripts/world.gd (_spawn_models), tests/model_preview.gd.

Ordem das levas (faça a que eu pedir; sem pedido, a 1): 1 estruturas (blocos com forma/estação/baú/porta/tocha...), 2 armaduras (um conjunto por vez; Molten é o modelo a seguir), 3 armas e ferramentas, 4 inimigos comuns, 5 chefes. Não converta mais que a leva da sessão.

Como se faz (já provado no piloto):
- Todo item/bloco/inimigo já tem modelo automático (sprite inflado). Só o que merece "destaque" ganha receita: entrada em data/base/models.json (wiki = sprite-base, emissive = cores que brilham, sparks) + função em recipes.gd + campo "model" no dado. Sprites-base novos vão em "wiki" (o fetch-sprites.sh baixa); veja a página da wiki por curl (Molten_armor, Living_Loom_(placed) são exemplos de imagem "vestido"/"colocado").
- Armadura: casca por peça (head/body/arm/leg) projetando uma região escolhida do sprite do conjunto vestido (recipes.shell + vein); cores emissivas pulsam no shader; fagulhas via fx.gd. Cuidado: o sprite vestido tem pixels duplicados 2x2; escolha as regiões à mão, sem o contorno escuro nas laterais (parâmetro `plain`).
- Bloco com modelo: "shape": "model", "size": [largura, altura] em tiles da wiki, "solid": false; a instância fica fora da malha do chunk (world.gd) e recebe a luz do lugar.
- Inimigos: hoje usam enemy_model.gd (eye/slime/humanoid ou sprite extrudado fino). Trocar por modelo voxel por receita, com articulações (encaixe 255,0,255 = pivô) e animação por código como o player_model; humanoides já usam o corpo voxel.
- Convenções: eixos do MagicaVoxel (x largura, y profundidade com frente = y pequeno, z altura); 1 voxel = 0,0375 bloco (VoxMesh.V; braço da 1ª pessoa 0,02); sem preto puro; 1 tom de luz e 1 de sombra; emissivo só onde o Terraria brilha; sem voxel flutuante imitando partícula; sem ligação só por quina. A saída do renderer NÃO converte sRGB: passe a paleta direto ao shader.

Verificação (sessão sem tela, obrigatória):
- .tools/godot --headless -s tests/model_preview.gd -- <alvos> gera textures/model_sheet.png (sprite + 4 ângulos; alvos: item, block:nome, body, armor:conjunto, sufixo @1.5 aproxima). Olhe e itere até silhueta e paleta baterem; mande o caminho/arquivo ao dono.
- Prints no jogo: xvfb-run ... tests/screenshot.gd -- <parte do nome> (adicione cenas em SHOTS; "late" espera mais quadros, "turn" gira o boneco). Confira de frente, lado e costas, de dia e à noite, e a 1ª pessoa quando mexer em item.
- tests/run.gd (um check por lógica nova), scripts/audit.py, scripts/voxel/levas.gd (docs/LEVAS.md tem teste de "em dia"), menu_flow.gd.

Lições do playtest do dono (valem para toda leva):
- "Terraria em 3D, nunca Minecraft"; modelo bom = silhueta e paleta do sprite. O dono aprovou Loom e Molten.
- Arma na mão: 3ª pessoa = o plano do sprite acompanha o golpe (de lado); 1ª pessoa = ROLL -90 em torno do eixo maior (espada com o sinal oposto, para o fio ir à frente), golpe para a frente em direção à mira (pose "swing" em held_item.gd), ferramenta segurada no meio do cabo (GRIP 0,3). Armas novas devem herdar isso sem ajuste; se uma não servir, campo no JSON, não exceção no código.
- Brilho moderado: halo de efeito fraco (Terra Blade estava forte demais); item na mão com ambient 0,85, corpo/armadura 0,6.
- Olhos do corpo ficam 1 voxel à frente do rosto (piscar não pode abrir buraco); peças que se encostam não podem deixar fresta (linha preta).
- Respostas curtas em português; ao fim: testes, prints, "como rebuildar" (git pull && scripts/update.sh && .tools/godot) e se precisa de mundo novo.

Entrega: commit pequeno + push no branch indicado, folha de prints, atualizar docs/LEVAS.md (rode levas.gd) e o BACKLOG (apague o que fechou), e um guia de playtest objetivo.
```
