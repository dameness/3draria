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

## Estrutura
```
project.godot        config (renderer Compatibility)
main.tscn            cena inicial
scripts/             scripts de shell (setup) e, a partir da F1, um .gd por sistema
tests/run.gd         testes headless (asserts simples, sem framework)
data/base/           conteúdo do jogo base (a partir da F1)
data/calamity/       conteúdo da expansão (F7)
textures/            PNGs gerados por script (não editar à mão)
docs/ROADMAP.md      fases e critérios de pronto
.tools/              binário do Godot (ignorado pelo git)
```

## Onde fica cada tipo de dado
Um arquivo JSON por tipo em `data/<pacote>/`: `blocks.json`, `items.json`, `recipes.json`, `ores.json`, `enemies.json`.
O Calamity é outra pasta com os mesmos arquivos + poucos comportamentos novos em script.

## Roadmap (detalhes em docs/ROADMAP.md)
F0 Estrutura · F1 Mundo · F2 Jogador · F3 Itens · F4 Sobrevivência · F5 Primeiro chefe · F6 Hardmode · F7 Calamity
