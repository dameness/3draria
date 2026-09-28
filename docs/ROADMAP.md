# Roadmap

Toda fase termina com `.tools/godot --headless -s tests/run.gd` passando e uma instrução de playtest para o dono.

## F0 Estrutura ✅
Pronto quando: `scripts/setup-godot.sh` é idempotente; `.tools/godot --headless --quit` sai com 0 e sem erros; `tests/run.gd` sai com 0 e com != 0 quando um check falha; o editor abre o projeto localmente.

## F1 Mundo ✅ (falta playtest)
Chunks 16x16 com altura fixa, blocos em PackedByteArray, mesh só de faces visíveis, atlas de texturas gerado por script, geração por ruído em camadas (superfície, subterrâneo, cavernas, submundo), mundo finito pequeno.
Pronto quando: testes verificam que um chunk sólido cercado só gera as faces do topo, winding correto, geração determinística por seed com as 4 camadas, atlas PNG gerado, e que a cena principal monta todos os chunks no alcance; no playtest local, câmera livre mostra o mundo a ≥ 60 fps com a distância de renderização padrão (6).

## F2 Jogador ✅ (falta playtest)
Controle em 1ª pessoa, colisão, quebrar/colocar bloco, hotbar.
Pronto quando: testes verificam que o raycast de voxel acerta o bloco e a face certos, colisão (cair e parar no chão, pulo de ~1,4 bloco, parede bloqueia), e que quebrar pela mira altera o chunk e refaz a mesh (e a do vizinho na borda); no playtest, dá pra andar, pular sem atravessar blocos, quebrar, colocar e trocar o bloco pela hotbar.

## F3 Itens ✅ (falta playtest)
Drops, inventário, bancadas e receitas por dados, poder de mineração por tier bloqueando minérios.
Drops vão direto para o inventário (itens soltos no chão ficam para a F4). Números conferidos na wiki: picaretas 35/40/55,
barras 3/3/4 minérios, picaretas 8/10/10 barras. Pendente: fornalha pede 3 tochas (tocha = gel + madeira, entra na F4 com slimes).
Pronto quando: testes carregam items/recipes/ores de `data/base/`, validam referências cruzadas, verificam empilhamento no inventário, craft só perto da bancada certa e minério recusado abaixo do tier; no playtest, minerar → coletar → craftar picareta melhor → minerar minério antes bloqueado.

## Depois do protótipo (anotado, ordem a definir; sempre conferindo a wiki)
- Mundo mais profundo e maior (ALTURA/SIZE_CHUNKS em world_gen.gd; conferir memória e tempo de geração).
- Câmera em 1ª e 3ª pessoa com troca por tecla; modelo do jogador mostrando armadura, arma e acessórios equipados.
- Iluminação por blocos (tochas, cavernas escuras).
- Asas, ganchos, acessórios e slots de equipamento; reforja com modificadores (Goblin Tinkerer).
- NPCs de vila (casas válidas, lojas, diálogos).
- Biomas do Terraria (corrupção/carmesim, selva, neve, deserto, oceano, cogumelo, masmorra) com blocos, inimigos e drops próprios.

## F4 Sobrevivência ✅ (falta playtest)
Vida, dia/noite, 2-3 inimigos básicos, combate corpo a corpo e à distância, salvar/carregar.
Itens soltos no chão (miniatura girando + feixe na cor da raridade), tochas/gel, fornalha com tochas.
Pronto quando: testes verificam dano/defesa/morte/respawn, invencibilidade, IA de slime/zumbi/olho, espada e flecha, coleta de itens, ciclo dia/noite, e que salvar→carregar reproduz mundo e inventário; no playtest, sobreviver a uma noite lutando com espada e arco, sair e voltar com tudo salvo.
Pendente (fora do protótipo): dano de queda, regeneração fiel, knockback resist, inimigos com modelo.

## V1–V3 Visual Terraria (ver docs/VISUAL.md) — V1 ✅
V1 ícones/blocos exatos da wiki (baixados, fora do git) com fallback procedural; V2 item 3D extrudado na mão;
V3 efeitos e projéteis por dados. Pronto quando: testes verificam fallback sem rede, extrusão (faces só nas bordas)
e que `effects`/`shoot` vêm do JSON; no playtest, Terra Blade com o ícone do jogo, brilho verde e o feixe.

## F5 Primeiro chefe + progressão completa de minérios pré-hardmode
Tiers da wiki: minérios comuns com qualquer picareta; meteorito 50; demonita/carmesim e obsidiana 55; pedra infernal 65.
Pronto quando: testes verificam a cadeia de tiers de minério pré-hardmode sem buracos e o invocador/drops do chefe por dados; no playtest, do cobre ao último tier pré-hardmode e o chefe derrotado.

## F6 Hardmode
Pronto quando: derrotar o chefe final pré-hardmode converte o mundo e libera minérios/inimigos novos, com teste da conversão.

## F7 Calamity
Pronto quando: `data/calamity/` carregada junto da base adiciona conteúdo sem mudar os sistemas genéricos além de poucos comportamentos novos, com teste de carregamento.
