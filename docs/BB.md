# Modelos de inimigos/chefes em ossos (bb)

Dois caminhos para o mesmo `"model": "bb:nome"` do `enemies.json`; `EnemyModel.bb_path` escolhe:
1. **`assets/models/bb/nome.glb`** — feito à mão no Blockbench (só sessão local; fora do git). **Vence sempre; o update.sh nunca toca nesta pasta.**
2. **`assets/models/bbgen/nome.glb`** — gerado por script (`scripts/bb/models.gd` → `scripts/bb/build.gd`, o `update.sh` roda). Funciona na sessão remota, sem o Blockbench.
Sem nenhum dos dois vale o `"fallback"` procedural (os testes passam do mesmo jeito).

## Receita (`scripts/bb/models.gd`, uma função por modelo → `BbRig`)
- Osso = `rig.bone(nome, pai, pivô)` devolve um `VoxModel` para pintar (`box`, `ellipsoid`, `put`, `line`) em coordenadas globais, em células (x largura, y profundidade, frente = y menor, z altura).
  `rig.k` = texels por célula (1 texel = 1 pixel do sprite = 0,0375 bloco; chefe grande usa k=3); `rig.center` = ponto que vira a origem (pés para quem anda/voa; centro do corpo se o def tem `"look": true`).
- Clipes com os nomes que `enemy_model.gd` toca: `idle`, `move`, `attack`, `hurt`, `death` (+ `phase2`); `rig.sway` faz ciclo fechado (loop sem salto, o teste confere), `rig.shot` disparo único, `rig.std_hurt/std_death` padrão.
- Grupos `iris` (fase 1) e `mouth` (fase 2) = ossos com esses nomes (`set_phase`).
- Cor por vértice (sem textura), paleta do sprite da wiki: 1 tom de luz + 1 de sombra; o AO do mesher faz o resto.
- Conferir sem tela: `.tools/godot --headless -s tests/model_preview.gd -- enemy:nome enemy2:nome` (4 ângulos + `textures/enemy_anims.png` com um quadro por clipe).
- Modelo novo = uma função + uma linha em `all()` + `"model": "bb:nome"` no inimigo. Retocar à mão: abra no Blockbench, salve em `assets/models/bb/` com o mesmo nome.

## Feitos
Eye of Cthulhu (2 fases), Demon Eye, Servant of Cthulhu, Cave/Ice/Jungle Bat e Hellbat.
