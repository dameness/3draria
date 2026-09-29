# Contexto para continuar numa sessão nova

**O que falta está em `docs/BACKLOG.md`** (curto). Este arquivo tem o prompt pronto, os comandos e as armadilhas.

## Prompt pronto para colar numa sessão nova
```
Repo dameness/3draria (jogo voxel 3D em Godot 4.7.2 com o conteúdo do Terraria; o dono testa local num PC Ubuntu modesto; você não tem GPU: valide com
testes headless e prints via xvfb, e OLHE as imagens). Leia SÓ CLAUDE.md e docs/BACKLOG.md e faça o item [N] do backlog; não leia REVISAO.md nem HANDOFF.md inteiros.
Commits pequenos (teste em tests/run.gd + print se for visual), push na branch da sessão (sem PR). Números da wiki. Respostas curtas em português, com "como testar / rebuildar / mundo novo".
Prints só do que mudou, em folha de contato. Ao terminar, apague o item do backlog.
```

## Comandos
```sh
scripts/update.sh                              # após git pull: Godot + sprites + cache de classes (rodar --import após novo class_name)
.tools/godot --headless -s tests/run.gd        # testes (saída != 0 em falha; ~10 s)
xvfb-run -a -s "-screen 0 1280x720x24" .tools/godot -s tests/screenshot.gd -- spawn minera arco   # prints em textures/shot_*.png; sem argumentos = todos (~90 s)
xvfb-run -a -s "-screen 0 1280x720x24" .tools/godot -s tests/menu_flow.gd                        # menu → jogo → salvar → recarregar (+ prints textures/menu_*.png)
xvfb-run -a -s "-screen 0 1280x720x24" .tools/godot -s tests/character_preview.gd -- gold big walk item:iron_broadsword   # boneco: sets, big, walk, swing, seq (golpe em 5 quadros), item:nome, name:Fulano
scripts/wiki.py items|recipes|npcs "Nome"      # números oficiais (a wiki dá 429: o script já tenta de novo); páginas com curl na API (WebFetch é bloqueado)
```
Sempre ao fim de um passo: testes verdes, commit, push (na branch acima) e um guia curto de playtest **com "como rebuildar"**
(`git pull && scripts/update.sh && .tools/godot`) e se **precisa de mundo novo** (mudou `world_gen.gd`; até aqui **não precisa**: os ids novos
de líquido entram no fim de `blocks.json` e saves antigos continuam válidos).

## Armadilhas e descobertas
- **Godot: `rotation.x` positivo balança braço/perna para a FRENTE** no modelo (olha para -Z); vários sinais estavam invertidos. Pivô de
  braço = ombro. Item na mão: plano do sprite = plano do golpe (base `Basis(b.cross(RIGHT), b, RIGHT)` em `_show_held`).
- `material_overlay` funciona no Compatibility; o problema do "clarão" era lógica (só detectava a transição de desligar).
- Chamada de função GDScript disputa uma trava entre threads: código de thread (`world_gen.gd`, `chunk_mesher.gd`) não chama função no laço
  quente. `WorkerThreadPool.add_task` sem prioridade alta usa só ~30% das threads. Sem GPU o FPS dos prints é de CPU e não vale.
- Líquidos: `Blocks.liquid_kind/level/level_ids`; o fluxo grava com `world.set_block(..., false)` e acorda vizinhos; teste com
  `world.liquid.settle(world)`; ~1 ms por geração num lago 18×18×3. Chunk não gerado conta como parede.
- Mudou a geração (`world_gen.gd`)? Mundos salvos ficam com emendas: peça mundo novo. Save v2; `Inventory.SIZE` = 50.
- Novo `class_name`: rode `.tools/godot --headless --import` (senão "Identifier ... not declared"; `update.sh` faz).
- GDScript: `var a := x * p[2]` com `p` sem tipo não infere (use `var a: float = ...`); `ready` é nome reservado de Node; `Slot` é classe interna do `hud.gd`.
- Edições por script Python: confira a indentação (tabs) e use `assert old in s`; um `replace` que não casa passa em silêncio.
- Prints rodam a ~8 quadros/s: partículas (0,5–0,9 s) e arco (0,17 s) precisam ser disparados 1–4 quadros antes do print (ver `tests/screenshot.gd`).
- O classificador de comandos do ambiente às vezes falha de forma transitória: tente de novo.
- `textures/` e `assets/wiki/` ficam fora do git; `docs/img/` tem os prints de antes/depois (V6–V8).
- Sessão 4: o classificador de comandos falha às vezes (repita uma vez); o script de print deixa projétil congelado de uma cena na seguinte (já limpo em `_setup`);
  uploads de imagem grandes dão 500 às vezes (mande JPEG menor); `git push` dá 503 às vezes (tente de novo com espera); edições por Python: `assert old in s` sempre.
