# Roadmap

Toda fase termina com `.tools/godot --headless -s tests/run.gd` passando e uma instrução de playtest para o dono.

## F0 Estrutura ✅
Pronto quando: `scripts/setup-godot.sh` é idempotente; `.tools/godot --headless --quit` sai com 0 e sem erros; `tests/run.gd` sai com 0 e com != 0 quando um check falha; o editor abre o projeto localmente.

## F1 Mundo ✅ (falta playtest)
Chunks 16x16 com altura fixa, blocos em PackedByteArray, mesh só de faces visíveis, atlas de texturas gerado por script, geração por ruído em camadas (superfície, subterrâneo, cavernas, submundo), mundo finito pequeno.
Pronto quando: testes verificam que um chunk sólido cercado só gera as faces do topo, winding correto, geração determinística por seed com as 4 camadas, atlas PNG gerado, e que a cena principal monta todos os chunks no alcance; no playtest local, câmera livre mostra o mundo a ≥ 60 fps com a distância de renderização padrão (6).

## F2 Jogador
Controle em 1ª pessoa, colisão, quebrar/colocar bloco, hotbar.
Pronto quando: testes verificam que o raycast de voxel acerta o bloco certo e que quebrar/colocar altera o chunk e refaz só a mesh afetada; no playtest, dá pra andar, pular sem atravessar blocos, quebrar, colocar e trocar o bloco pela hotbar.

## F3 Itens
Drops, inventário, bancadas e receitas por dados, poder de mineração por tier bloqueando minérios.
Pronto quando: testes carregam items/recipes/ores de `data/base/`, validam referências cruzadas, verificam empilhamento no inventário, craft só perto da bancada certa e minério recusado abaixo do tier; no playtest, minerar → coletar → craftar picareta melhor → minerar minério antes bloqueado.

## F4 Sobrevivência
Vida, dia/noite, 2-3 inimigos básicos, combate corpo a corpo e à distância, salvar/carregar.
Pronto quando: testes verificam dano/morte/respawn, ciclo dia/noite, que inimigos vêm de `enemies.json`, e que salvar→carregar reproduz mundo e inventário idênticos; no playtest, sobreviver a uma noite lutando com espada e arco, sair e voltar com tudo salvo.

## F5 Primeiro chefe + progressão completa de minérios pré-hardmode
Pronto quando: testes verificam a cadeia de tiers de minério pré-hardmode sem buracos e o invocador/drops do chefe por dados; no playtest, do cobre ao último tier pré-hardmode e o chefe derrotado.

## F6 Hardmode
Pronto quando: derrotar o chefe final pré-hardmode converte o mundo e libera minérios/inimigos novos, com teste da conversão.

## F7 Calamity
Pronto quando: `data/calamity/` carregada junto da base adiciona conteúdo sem mudar os sistemas genéricos além de poucos comportamentos novos, com teste de carregamento.
