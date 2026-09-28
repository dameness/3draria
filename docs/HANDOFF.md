# Contexto para continuar numa sessão nova

Repo `dameness/3draria`, branch **`claude/upbeat-ramanujan-ab3kfm`** (commit e push nela; **não abra PR** sem o dono pedir).
Jogo voxel 3D com o conteúdo e a progressão do Terraria (Godot 4.7.2, GDScript, renderer Compatibility). Uso pessoal.
O dono joga num PC Ubuntu modesto e testa localmente; a sessão remota **não tem GPU nem tela**: valide com testes
headless e com prints via Xvfb (e **olhe as imagens**). Respostas curtas, em português, com guia de teste no fim.

Leia antes: `CLAUDE.md` (princípios e **diretrizes do dono**), `data/CLAUDE.md`, `docs/ROADMAP.md`, `docs/VISUAL.md`, `docs/UI.md`.

## Comandos
```sh
scripts/update.sh                              # após git pull: Godot + sprites + cache de classes (rodar --import após novo class_name)
.tools/godot --headless -s tests/run.gd        # testes (saída != 0 em falha)
xvfb-run -a -s "-screen 0 1280x720x24" .tools/godot -s tests/screenshot.gd -- spawn inventario   # prints; sem argumentos = todos; nomes filtram
xvfb-run -a -s "-screen 0 1280x720x24" .tools/godot -s tests/menu_flow.gd                        # menu → jogo → salvar → recarregar
xvfb-run -a -s "-screen 0 1280x720x24" .tools/godot -s tests/character_preview.gd [-- copper iron]  # personagens/armaduras
scripts/wiki.py items|recipes|npcs "Nome"      # números oficiais (curl na API; a wiki dá 429: o script já tenta de novo)
```
Sempre ao fim de um passo: testes verdes, commit, push (na branch acima) e um guia curto de playtest **com "como rebuildar"**
(`git pull && scripts/update.sh && .tools/godot`) e se **precisa de mundo novo** (mudou a geração).

## Feito (tudo commitado e testado)
- **V6** céu procedural (sol, lua, estrelas, nuvens, montanhas; névoa escura em caverna, vermelha no submundo).
- **V7** mundo: relevo com serras/terraços, lagos com praia, árvores do Terraria, capim/flores/cogumelos, água e lava,
  oclusão ambiente por vértice; mesher 2× mais rápido; cada chunk gerado uma vez só; nado e dano de lava.
- **V8** GUI no layout do Terraria (Tab/E abre; hotbar = 1ª fileira do inventário, criação em coluna à esquerda, equipamento
  à direita, item preso ao cursor, lixeira, dicas por raridade), números de dano, tela azul/vermelha em água/lava.
- Personagem chibi arredondado com contorno e armaduras por peça (na paleta do ícone); **pausa de verdade** (Esc);
  golpe acerta no impacto da animação (arco na altura do corpo ou cone 3D); câmera balança/treme; tocha tremula.
- `fetch-sprites.sh` respeita o 429 da wiki; `scripts/update.sh`; docs/UI.md; prints em `docs/img/antes_depois_*.png`.

## Feedback do dono no playtest (v6/v7) — manter em mente sempre
- v6: quase sem animação; Tab não abria o inventário (corrigido); faltava jogabilidade estilo Terraria; armaduras/personagem
  pareciam Minecraft e feios (refeitos); **desempenho bom** (manter e pedir o FPS de volta).
- v7: pause não funcionava (agora pausa a árvore); "ainda sem animações"; "luta meio estranha" (ajustei acerto e arco; **peça
  detalhes**: acertar, recuo, velocidade, dano, IA?).
- Quer **crafting, menus e GUI nos mesmos lugares e com a mesma interatividade do Terraria** (docs/UI.md) e **muita animação**.

## Pendente da Tarefa 1 (visual), em ordem
1. **Menu com o mundo de verdade ao fundo** (`menu.gd`, `menu.tscn`): WorldEnvironment + `world.gd` (render distance 4) + `day_night.gd`
   (tempo acelerado) + Camera3D orbitando devagar a planície de nascimento (128,128; sem árvores num raio de 26) e o `PlayerModel`
   do personagem escolhido (com armadura, via um Dummy como em `tests/character_preview.gd`); logo grande com contorno;
   botões só texto (`Ui.menu_button`); telas de personagem/mundo em painel à direita com o avatar à esquerda (`cam.h_offset`).
   Manter `box`, `show_players`, `pick_player`, `play` (tests/menu_flow.gd usa).
2. **Partículas e animação** (`entities.gd` tem `spawn_text`; criar `spawn_dust`/faíscas com `CPUParticles3D`): poeira na
   cor do bloco ao minerar (média do tile do atlas), faíscas ao acertar, nuvem ao morrer, pegadas, respingo na água.
   Arco do golpe (crescente) para toda arma de swing em 1ª e 3ª pessoa (unificar o rastro de `held_item.gd` num componente
   com pontos em espaço global); braço em 1ª pessoa; inércia da mão ao girar; poses de 3ª pessoa já existem.
3. **Mineração com progresso** (dureza por bloco, rachaduras, tempo por poder de picareta) — hoje quebra na hora.
4. **Inimigos legíveis**: o slime (gel verde translúcido) some no gramado; contorno/núcleo mais escuro; idle dos olhos;
   zumbi com a pose nova. Rever IA/knockback se o dono descrever a "luta estranha".
5. **GUI restante** (docs/UI.md, "Pendente"): minimapa, buffs, moedas e slots de munição, acessórios/vanity/dye, baús,
   favoritar (Alt+clique), ordenar, Shift+clique, criação em lista/martelo.
6. Fechar: `docs/VISUAL.md` já descreve V6–V8; acrescente V8b/V9 e atualize prints.

## Tarefa 2 (passo 4 do roadmap, fecha a pré-hardmode) — nada feito ainda; sempre com os números da wiki
Corrupção e Carmesim (blocos, Shadow Orb/Crimson Heart, altares) com Eater of Worlds e Brain of Cthulhu; escamas → Nightmare
Pickaxe → pedra infernal (65) → equipamento Molten (Hellforge, obsidiana); King Slime; meteorito; Skeletron com a masmorra;
Wall of Flesh, que abre a F6 (hardmode). Conteúdo é **dado** (JSON em `data/base/`) lido por sistemas genéricos; IA nova = um
`match` em `enemy.gd`; novos blocos entram **no fim** de `blocks.json` (id = posição). Um subagente de pesquisa da wiki caiu por
limite de API: refaça a coleta (scripts/wiki.py + `curl` da API `action=parse&prop=wikitext`; WebFetch é bloqueado; respeite o 429).
Um commit por subpasso (bioma+EoW, BoC, Nightmare/Molten, King Slime+meteorito, Skeletron+masmorra, WoF), cada um com
testes e prints.

## Armadilhas e descobertas
- **Neste Godot, chamada de função GDScript disputa uma trava entre threads** (arrays, operadores e métodos nativos não):
  código de thread (`world_gen.gd`, `chunk_mesher.gd`) não chama função no laço quente. `WorkerThreadPool.add_task` sem
  prioridade alta usa só ~30% das threads. Sem GPU o FPS dos prints é de CPU e não vale.
- Mudou a geração (`world_gen.gd`)? Mundos salvos ficam com emendas: peça mundo novo. Save v2; `Inventory.SIZE` = 50.
- Novo `class_name`: rode `.tools/godot --headless --import` (senão "Identifier ... not declared"; `update.sh` faz).
- `ready` é nome reservado de Node; `PackedColorArray` não tem `filter`; `Slot` (botão com dica em BBCode) é classe interna do `hud.gd`.
- O classificador de comandos do ambiente às vezes falha de forma transitória: tente de novo / faça edições e volte.
- `textures/` e `assets/wiki/` ficam fora do git; `docs/img/` tem os prints de antes/depois.
