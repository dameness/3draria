# 3draria

Jogo voxel 3D (estilo Minecraft) com conteúdo e progressão do Terraria; depois, expansão inspirada no Calamity. Uso pessoal, sem distribuição.
O dono joga num PC Ubuntu modesto. A sessão remota não tem GPU/tela: valide só com execução headless e testes; o playtest é do dono.

## Princípios
- O código mais simples que funciona. YAGNI. Nenhuma abstração, camada ou dependência que o passo atual não exija.
- Scripts diretos, um por sistema. Nada de arquitetura corporativa.
- Conteúdo é dado, não código: blocos, itens, receitas, minérios e inimigos em arquivos de dados lidos por sistemas genéricos.
- Desempenho é requisito: 60 fps em GPU integrada, renderer Compatibility, distância de renderização configurável.
- Sem addons no MVP. Visual: sprites do Terraria/Calamity baixados da wiki para `assets/wiki/` (fora do git, uso pessoal),
  com fallback procedural (atlas.gd) quando não houver sprite. Detalhes em docs/VISUAL.md.
- Respostas curtas; não repita código que não mudou.
- **Todo passo termina com teste headless passando + instrução objetiva de playtest para o dono.**

## Diretrizes do dono (playtest da v6; valem para todo passo novo)
- **Terraria em 3D, nunca Minecraft**: personagem, armaduras, inimigos, itens, blocos e GUI. Se parecer Minecraft, refaça.
- **GUI = a do Terraria, nos mesmos lugares e com a mesma interatividade** (spec em docs/UI.md): hotbar/inventário no canto
  superior esquerdo, criação à esquerda, equipamento à direita, vida no canto superior direito, item preso ao cursor,
  botão direito, lixeira, dicas com a cor da raridade. Tab abre o inventário. Jogabilidade também como a do Terraria.
- **Animação sempre**: câmera/mão, poses, inimigos, partículas e interface. Jogo parado é defeito.
- Desempenho está bom no PC do dono (Ubuntu modesto): manter e pedir o FPS de volta.
- **Ao fim de todo passo, diga como rebuildar**: `git pull && scripts/update.sh && .tools/godot` (update.sh = Godot + sprites +
  cache de classes; sem ele script novo dá "Identifier ... not declared"), e se **precisa de mundo novo** (mudou a geração).
- O dono lê o chat no app: respostas curtas em português, com o guia de teste no fim.

## Ponytail (skills em .claude/skills/, licença MIT em PONYTAIL-LICENSE)
- Antes de codar, pare no primeiro degrau que resolve: precisa existir? já existe no repo? stdlib/engine faz? dá pra ser uma linha? só então o mínimo.
- Entenda o problema primeiro: leia a tarefa e o fluxo real de ponta a ponta.
- Bug = causa raiz: corrija a função compartilhada uma vez, não cada chamador.
- Sem abstrações não pedidas, sem dependências evitáveis, sem boilerplate.
- Apagar > adicionar. Chato > esperto. Menos arquivos possível. Menor diff correto vence.
- Questione pedidos complexos: "precisa mesmo de X, ou Y resolve?"
- Atalho deliberado com teto conhecido leva comentário `ponytail:` com o teto e o caminho de upgrade.
- Não economize em: entender o problema, validação em fronteiras, perda de dados, segurança.
- Lógica não trivial deixa UM check executável (assert em tests/run.gd). One-liners triviais não precisam.

## Referência de conteúdo
- Terraria: https://terraria.wiki.gg (ex.: /wiki/Pickaxe_power, /wiki/Ores)
- Calamity: https://calamitymod.wiki.gg
Consulte antes de criar itens, receitas, minérios, inimigos e chefes; adapte os números, não copie texto.
Leia pela API com curl (WebFetch é bloqueado; curl passa): `curl -sS "https://terraria.wiki.gg/api.php?action=parse&page=Iron_Bar&prop=text&format=json&formatversion=2"`.

## Stack
Godot 4.7.2-stable (fixado em scripts/setup-godot.sh), GDScript, renderer Compatibility (gl_compatibility).

## Comandos
```sh
scripts/setup-godot.sh                        # baixa o Godot em .tools/godot (idempotente; roda sozinho no SessionStart remoto)
scripts/update.sh                             # após cada git pull: Godot + sprites + cache de classes (depois: .tools/godot)
scripts/fetch-sprites.sh                      # baixa os sprites da wiki em assets/wiki/ (idempotente, respeita o 429; opcional)
scripts/wiki.py items|recipes|npcs "Nome" ...  # números oficiais da wiki (tabelas Cargo) para montar data/
.tools/godot --headless --import              # após pull ou novo class_name: atualiza o cache de classes
.tools/godot -e                               # abre o editor (local)
.tools/godot                                  # roda o jogo (local)
.tools/godot --headless --quit                # smoke test: projeto abre sem erros
.tools/godot --headless -s tests/run.gd       # testes; código de saída != 0 em falha
xvfb-run -a -s "-screen 0 1280x720x24" .tools/godot -s tests/screenshot.gd   # prints reais (OpenGL por CPU) em textures/shot_*.png
xvfb-run -a -s "-screen 0 1280x720x24" .tools/godot -s tests/menu_flow.gd    # menu → personagem → mundo → salvar → recarregar (prints textures/menu_*.png)
```
Sessão remota: **sempre confira mudanças visuais com tests/screenshot.gd** e olhe as imagens (FPS ali é de CPU, não vale).
Testes: cada `test_*` retorna `true` no fim (erro de script aborta a função → retorna null → falha).
Não use `Logger` em GDScript para capturar erros: trava o Godot 4.7.2 em erro de script.

## Estrutura
```
project.godot        config (renderer Compatibility)
menu.tscn            cena inicial: menu (personagem/mundo)   game.tscn  o jogo (roda direto sem save, p/ testes)
scripts/             setup-godot.sh e um .gd por sistema:
  blocks.gd          carrega blocks.json/textures.json (id = posição na lista, 0 = ar)
  atlas.gd           gera o atlas 16x16 procedural
  world_gen.gd       ruído em camadas → PackedByteArray por chunk (16x16x128)
  chunk_mesher.gd    faces visíveis → arrays de mesh com luz (céu pela altura da coluna + tochas); thread-safe
                     shaders/chunk.gdshader: atlas × luz (+ direção do sol, balanço das plantas, lava, tocha); o dia/noite muda só a luz do céu
                     shaders/water.gdshader: água translúcida com ondas   shaders/sky.gdshader: céu, sol, lua, estrelas, nuvens, montanhas
  world.gd           chunks, get/set_block, raycast, distância de renderização, jobs no WorkerThreadPool
  liquid.gd          fluxo de água e lava: níveis 1-8, cai e espalha, volume conservado; só reage a edições
  items.gd           itens (blocos viram itens + items.json), drops, poder de picareta
  inventory.gd       slots, empilhar, remover
  crafting.gd        receitas e estações por perto
  voxel_body.gd      colisão AABB contra voxels (jogador, inimigos, itens)
  player.gd          1ª pessoa, vida, usar item (minerar/golpear/atirar), colocar
  entities.gd        inimigos, itens soltos e flechas; spawn por horário
  enemy.gd  item_drop.gd  projectile.gd   um nó por entidade (IA genérica: hop/walk/fly/eye_of_cthulhu)
  enemy_model.gd     modelos 3D dos inimigos (eye/slime/humanoid; senão sprite extrudado)
  day_night.gd       ciclo 15+9 min
  save_game.gd       user://players/*.plr e user://worlds/*.wld (seed, hora, spawn, chunks editados)
  menu.gd            menu inicial com o mundo real ao fundo (câmera girando, dia passando) e o personagem escolhido de pé
                     no gramado: Um jogador → personagem → mundo; Esc no jogo = Continuar / Salvar e sair
  ui.gd              tema e peças da interface do Terraria (fonte com contorno, painéis azuis, coração, dicas por raridade)
  hud.gd             GUI no layout do Terraria (docs/UI.md): hotbar/inventário, criação, equipamento, vida, cursor, pausa
  item_model.gd      ícone 2D → malha 3D extrudada   held_item.gd  item na mão (1ª pessoa) + animação
  player_model.gd    boneco chibi arredondado com contorno (3ª pessoa, tecla V): poses, arma na mão, armadura por peça
scripts/update.sh    após cada git pull: Godot + sprites + cache de classes
tests/character_preview.gd  prévia dos personagens/armaduras (xvfb) → textures/personagens.png
tests/run.gd         testes headless (asserts simples, sem framework) + integração da cena principal
data/base/           conteúdo do jogo base
data/calamity/       conteúdo da expansão (F7)
textures/            atlas.png gerado pelos testes, só para inspeção (ignorado pelo git)
docs/ROADMAP.md      fases e critérios de pronto
docs/VISUAL.md       plano do visual Terraria → 3D
assets/wiki/         sprites baixados da wiki (fora do git)
.tools/              binário do Godot (ignorado pelo git)
```

## Documentação do projeto
Este arquivo: até 200 linhas. Cada pasta pode ter o próprio CLAUDE.md (até 50 linhas) com detalhes daquela seção,
ex.: `data/CLAUDE.md` (formato dos JSON e das texturas).

## Onde fica cada tipo de dado
Um arquivo JSON por tipo em `data/<pacote>/`: `blocks.json` (power = picareta mínima, drop), `textures.json` (paleta + padrão; também ícones),
`items.json` (itens que não são bloco; damage, use_time, reach, ammo, rarity), `recipes.json` (needs, station, count),
`ores.json` (faixa de y, veios), `enemies.json` (ai, life, damage, defense, spawn, drops), `rarities.json` (cor por raridade).
Não reordene `blocks.json` nem `items.json`: o id é a posição (saves vão depender disso). Adicione no fim.
O Calamity é outra pasta com os mesmos arquivos + poucos comportamentos novos em script.

## Roadmap (detalhes em docs/ROADMAP.md)
F0 Estrutura · F1 Mundo · F2 Jogador · F3 Itens · F4 Sobrevivência · F5 Primeiro chefe · F6 Hardmode · F7 Calamity
