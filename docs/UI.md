# GUI do Terraria — spec para o 3draria

Regra do dono: menus e GUI **nos mesmos lugares e com a mesma interatividade do Terraria** (PC, versão 1.4).
Referência: https://terraria.wiki.gg/wiki/Inventory. Medidas em pixels (slot 52, passo 58 = o print do dono, `docs/referencias/terraria_inventario.png`, 1834x1044; o HUD não escala: pensado para janela de 1080p).

## Onde fica cada coisa
- **Hotbar** (10 slots, teclas 1–0 e roda do mouse): canto superior esquerdo, x=20, y=20. É a primeira fileira do inventário:
  ao abrir, as outras 4 fileiras aparecem logo abaixo (5 x 10 = 50 slots). O slot escolhido fica destacado; o nome do item
  na cor da raridade aparece embaixo da hotbar por um instante.
- **Inventário**: Esc abre e fecha (Tab é o mapa; E fica livre, no Terraria é o gancho). O botão **Configurações** (embaixo do equipamento) pausa o
  jogo e abre distância de renderização, volume, sensibilidade do mouse, Continuar e Salvar e sair. À direita da grade: 4 slots de moedas e 4 de munição
  (a munição dos slots é usada antes da do inventário). **Lixeira**: 1 slot embaixo da grade, na última coluna (colocar outro
  item destrói o que estava lá). Botões de organizar/guardar ao lado (com baú).
- **Criação (crafting)**: coluna à esquerda, logo abaixo do inventário: lista vertical só do que dá para criar agora
  (estações a até 4 blocos + ingredientes no inventário); roda do mouse rola; o item do centro é clicado para criar; os
  ingredientes aparecem em fileira ao lado, com a quantidade; ícone de martelo alterna lista completa.
- **Equipamento**: coluna à direita (abaixo do minimapa), 3 colunas por fileira: tinta (dye), visual (vanity) e equipamento (verde, a da direita);
  3 fileiras de armadura (cabeça, corpo, pernas) e 5 de acessórios; o escudo da defesa (número dentro) fica à esquerda das últimas fileiras e
  Configurações embaixo. Armadura vestida aparece no corpo.
- **Vida**: canto superior direito, corações (20 de vida cada, começando na borda esquerda do minimapa) com "Vida: x/y" em cima; mana em estrelas ao lado (quando houver).
- **Minimapa**: canto superior direito, abaixo da vida, 300 px com moldura dourada e botões +/− no canto. **Buffs**: fileira logo abaixo da hotbar.
- **Dica (tooltip)**: ao passar o mouse, texto com contorno junto ao cursor: nome na cor da raridade, depois dano, velocidade,
  recuo, poder de picareta, defesa, etc. Sem painel de fundo.
- **Baú/NPC/loja** (quando houver): painel à esquerda, logo abaixo do inventário; a criação usa os itens do baú também.

## Interatividade
- **Botão esquerdo** num slot: pega a pilha inteira no **cursor** (o item segue o mouse); num slot vazio: solta; no mesmo item:
  junta (até o limite); em outro item: troca. Item no cursor fora do inventário: esquerdo usa, direito joga (ver Item no cursor); fechar o inventário devolve.
- **Botão direito**: pega 1 item da pilha (segurando, continua pegando); num armor/acessório: veste.
- **Shift+clique**: mover rápido (para baú/armadura); **Alt+clique**: favoritar (não cai nem vai para lixeira por atalho); **Ctrl+clique**: joga na lixeira.
- **Criar**: clicar no item central pega o resultado **no cursor** (segurando, repete até o limite da pilha).
- Colocar armadura do tipo certo no slot do equipamento veste; clicar na peça vestida devolve ao cursor.
- Esc abre e fecha o inventário. Roda do mouse escolhe a hotbar; 1–0 também (com o inventário aberto também). Shift segurado = Auto Select
  (a melhor ferramenta do inventário inteiro para o bloco da mira; sem alvo, Glowstick ou tocha), mostrada num slot extra à direita da hotbar.
- **Item no cursor** (wiki Inventory): vale como item na mão. Botão esquerdo fora dos painéis **usa** (joga 1 bomba, golpeia, coloca bloco, bebe poção) mirando no ponteiro; botão direito **joga a pilha** no chão (é assim que se joga a Guide Voodoo Doll na lava). F10 esconde o FPS, F11 o HUD.

## Estado no 3draria (atualize ao mexer)
Ver `scripts/hud.gd`, `scripts/minimap.gd` e `scripts/inventory.gd`. Feito: hotbar/inventário, criação, equipamento (3 armaduras + 5 acessórios com
bônus por dados: `"accessory": {speed, jump, regen, defense, wings: {time, lift}}`; asas = segurar Espaço no ar, planam depois, barra de voo sob a mira), moedas (slots que sobem 100→1 e giram; clicar leva a pilha para a mão e uma moeda do mesmo tipo volta; moeda em slot comum ou baú também conta para pagar), munição (4 slots, usados antes do inventário; a apanhada vai primeiro para eles; também vale em slot comum ou baú),
minimapa (mapa de exploração do mundo inteiro; Tab troca retrato/sobreposição/oculto, M mapa cheio, +/- zoom; salvo no mundo), lixeira (Ctrl+clique), Ordenar, Alt+clique favorita (★), Shift+clique (veste ou manda ao baú), Configurações (pausa; opções em `settings.gd`), baús (botão direito;
40 slots; tesouro sorteado na 1ª abertura; só quebra vazio). Animação: slots crescem/pulam, item voa até o slot, painéis deslizam, corações batem,
dicas com fade, cursor balança.
Mundo de teste: **F9** abre o painel de atalhos (modal: esconde o inventário; hora, vida/mana, hardmode, chefes, viagem) e um rodapé lista as teclas.
Criação: o botão do martelo alterna a lista completa. Ctrl (inventário fechado) liga o cursor inteligente: com ferramenta na mão e a mira no vazio, pega o bloco mais perto da linha de visada (mira dourada).
Pendente: vanity/dye (as colunas de tinta e visual já aparecem no equipamento, como no Terraria, mas os slots são só o desenho).

## Menu inicial (sessão 4, a partir das imagens do dono)
Título com o logo do Terraria (wiki, `logo` em textures.json) e lista "Um Jogador / Multijogador / Sair"; "Selecionar Personagem" e "Selecionar Mundo" com a placa azul no topo,
cartões (retrato, nome, plaquinhas PV/PM/Defesa ou Clássico/Mundo Pequeno/Salvo, linha Jogar + apagar) e os botões Voltar / Novo (+ Mundo de teste); "Novo" abre "Criar Personagem"/"Criar Mundo".
Configurações (pausa): "Menu de Configurações" com Geral / Vídeo / Controle à esquerda. Prints: tests/menu_flow.gd → textures/menu_*.png.
