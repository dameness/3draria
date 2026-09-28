# GUI do Terraria — spec para o 3draria

Regra do dono: menus e GUI **nos mesmos lugares e com a mesma interatividade do Terraria** (PC, versão 1.4).
Referência: https://terraria.wiki.gg/wiki/Inventory. Medidas em pixels com a interface a 100% (slot 52, passo 56).

## Onde fica cada coisa
- **Hotbar** (10 slots, teclas 1–0 e roda do mouse): canto superior esquerdo, x=20, y=20. É a primeira fileira do inventário:
  ao abrir, as outras 4 fileiras aparecem logo abaixo (5 x 10 = 50 slots). O slot escolhido fica destacado; o nome do item
  na cor da raridade aparece embaixo da hotbar por um instante.
- **Inventário**: Tab (e Esc/E fecham; Esc sem nada aberto = pausa). À direita da grade: 4 slots de moedas e 4 de munição
  (a munição dos slots é usada antes da do inventário). **Lixeira**: 1 slot no canto inferior direito da grade (colocar outro
  item destrói o que estava lá). Botões de organizar/guardar ao lado (com baú).
- **Criação (crafting)**: coluna à esquerda, logo abaixo do inventário: lista vertical só do que dá para criar agora
  (estações a até 4 blocos + ingredientes no inventário); roda do mouse rola; o item do centro é clicado para criar; os
  ingredientes aparecem em fileira ao lado, com a quantidade; ícone de martelo alterna lista completa.
- **Equipamento**: coluna à direita (abaixo do minimapa): defesa no topo (escudo + número), 3 slots de armadura (cabeça,
  corpo, pernas), depois 5 de acessórios; ao lado, as colunas de visual (vanity) e tinta (dye). Armadura vestida aparece no corpo.
- **Vida**: canto superior direito, corações (20 de vida cada) com "Vida: x/y" em cima; mana em estrelas ao lado (quando houver).
- **Minimapa**: canto superior direito, abaixo da vida. **Buffs**: fileira logo abaixo da hotbar.
- **Dica (tooltip)**: ao passar o mouse, texto com contorno junto ao cursor: nome na cor da raridade, depois dano, velocidade,
  recuo, poder de picareta, defesa, etc. Sem painel de fundo.
- **Baú/NPC/loja** (quando houver): painel à esquerda, logo abaixo do inventário; a criação usa os itens do baú também.

## Interatividade
- **Botão esquerdo** num slot: pega a pilha inteira no **cursor** (o item segue o mouse); num slot vazio: solta; no mesmo item:
  junta (até o limite); em outro item: troca. Item no cursor fora do inventário é jogado no chão; fechar o inventário devolve.
- **Botão direito**: pega 1 item da pilha (segurando, continua pegando); num armor/acessório: veste.
- **Shift+clique**: mover rápido (para baú/armadura); **Alt+clique**: favoritar (não cai nem vai para lixeira por atalho).
- **Criar**: clicar no item central pega o resultado **no cursor** (segurando, repete até o limite da pilha).
- Colocar armadura do tipo certo no slot do equipamento veste; clicar na peça vestida devolve ao cursor.
- Tab/E abrem e fecham; Esc fecha (ou pausa). Roda do mouse escolhe a hotbar; 1–0 também.

## Estado no 3draria (atualize ao mexer)
Ver `scripts/hud.gd` e `scripts/inventory.gd`. Pendente da spec: moedas, munição em slots, acessórios/vanity/dye, minimapa,
buffs, baús, favoritar, ordenar.
