# 3draria

Jogo voxel 3D (estilo Minecraft) com conteúdo e progressão do Terraria; depois, expansão inspirada no Calamity. Uso pessoal, sem distribuição.
O dono joga num PC Ubuntu modesto. A sessão remota não tem GPU/tela: valide só com execução headless e testes; o playtest é do dono.

## Princípios
- O código mais simples que funciona. YAGNI. Nenhuma abstração, camada ou dependência que o passo atual não exija.
- Scripts diretos, um por sistema. Nada de arquitetura corporativa.
- Conteúdo é dado, não código: blocos, itens, receitas, minérios e inimigos em arquivos de dados lidos por sistemas genéricos.
- Desempenho é requisito: 60 fps em GPU integrada, renderer Compatibility, distância de renderização configurável.
- Sem addons no MVP. Sem assets de terceiros: texturas 16x16 geradas por script (Image.save_png, paleta limitada).
- Respostas curtas; não repita código que não mudou.
- **Todo passo termina com teste headless passando + instrução objetiva de playtest para o dono.**

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

## Stack
Godot 4.7.2-stable (fixado em scripts/setup-godot.sh), GDScript, renderer Compatibility (gl_compatibility).

## Comandos
```sh
scripts/setup-godot.sh                        # baixa o Godot em .tools/godot (idempotente; roda sozinho no SessionStart remoto)
.tools/godot -e                               # abre o editor (local)
.tools/godot                                  # roda o jogo (local)
.tools/godot --headless --quit                # smoke test: projeto abre sem erros
.tools/godot --headless -s tests/run.gd       # testes; código de saída != 0 em falha
```
Testes: cada `test_*` retorna `true` no fim (erro de script aborta a função → retorna null → falha).
Não use `Logger` em GDScript para capturar erros: trava o Godot 4.7.2 em erro de script.

## Estrutura
```
project.godot        config (renderer Compatibility)
main.tscn            cena inicial
scripts/             setup-godot.sh e um .gd por sistema:
  blocks.gd          carrega blocks.json/textures.json (id = posição na lista, 0 = ar)
  atlas.gd           gera o atlas 16x16 procedural
  world_gen.gd       ruído em camadas → PackedByteArray por chunk (16x16x128)
  chunk_mesher.gd    faces visíveis → arrays de mesh (thread-safe)
  world.gd           chunks, distância de renderização, jobs no WorkerThreadPool
  fly_camera.gd      câmera livre (até a F2)   hud.gd  texto de fps/depuração
tests/run.gd         testes headless (asserts simples, sem framework) + integração da cena principal
data/base/           conteúdo do jogo base
data/calamity/       conteúdo da expansão (F7)
textures/            atlas.png gerado pelos testes, só para inspeção (ignorado pelo git)
docs/ROADMAP.md      fases e critérios de pronto
.tools/              binário do Godot (ignorado pelo git)
```

## Onde fica cada tipo de dado
Um arquivo JSON por tipo em `data/<pacote>/`: `blocks.json`, `textures.json` (paleta + padrão), e depois `items.json`, `recipes.json`, `ores.json`, `enemies.json`.
Não reordene `blocks.json`: o id do bloco é a posição (saves vão depender disso). Adicione no fim.
O Calamity é outra pasta com os mesmos arquivos + poucos comportamentos novos em script.

## Roadmap (detalhes em docs/ROADMAP.md)
F0 Estrutura · F1 Mundo · F2 Jogador · F3 Itens · F4 Sobrevivência · F5 Primeiro chefe · F6 Hardmode · F7 Calamity
