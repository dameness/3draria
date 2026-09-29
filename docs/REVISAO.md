# Revisão pré-hardmode (pontos do dono) — mapear e fazer, sempre com prints

Foco: fechar a pré-hardmode antes de hardmode/Calamity. Cada item: mapear (ler código + wiki), propor, implementar, teste + print.
Marque ✅ ao concluir. Perguntas que precisam do dono: liste no fim do passo.

## Prioridade (pós commit dos machados)
1. Árvore: quebrar a base derruba a árvore inteira (tronco + copa), como no Terraria; drop de madeira por bloco do tronco, e acorn/semente.
2. Voo: hoje é modo criativo (F). O Terraria não tem Ctrl/descer: sem asas cai pela gravidade. Decidir com o dono um modo criativo/debug (F) com descer numa tecla à parte, e as asas fiéis ao Terraria (sem descer manual). Hoje só C desce. Com asas (futuro): sem voo livre, planar/cair sozinho,
   sem dano de queda, tempo de voo limitado. Separar "modo criativo/debug" (F) de "asas" (item de acessório, ver `inv.acc_sum`).
3. Dano de armas/ferramentas = wiki (machado/picareta/espada: dano, use_time, knockback, escala de dano do Terraria; revisar `hurt`, defesa/2).
4. Cursor do minimapa "teleporta": `minimap.gd` atualiza a origem só a cada ciclo de 40 quadros; a seta usa a origem antiga → mover a seta
   pela posição atual do jogador e a textura por linhas com origem estável (ou rolar a imagem).
5. Binds do Terraria (conferir na wiki "Controls"): Esc abre/fecha inventário e Pause vira botão Settings; Tab alterna o mapa (minimapa/overlay);
   Shift segura para atirar/arremessar (flecha, glowstick); Q poção de cura, ... ; hotbar/criação como no Terraria (lista, martelo, guia).
6. Ataque: autoswing rápido demais e sem mirar exatamente onde aponto → use_time da wiki, golpe só ao clicar (ou auto só nas armas com autoswing),
   acerto pelo cone/raycast da mira.
7. Loot de cavernas/baús como no Terraria (tabelas por bioma/camada, Life Crystal, poções, acessórios, Shadow chests); equipáveis e consumíveis
   (poções, Life Crystal +20 vida, Mana Crystal) com os mesmos números.
8. Mana e itens mágicos (varinhas, Space Gun, Book of Skulls...); animações de melee que lançam projétil (Terra Blade) — testar; NPCs (Guide etc.).

## Bugs vistos no playtest desta sessão
- Verme do Crimson (na verdade o Eater of Worlds/Brain?) "meio bugado": conferir orientação/juntas dos segmentos (`enemy.gd` worm/`_process`
  olha para o de trás?), Brain: creepers e teletransporte. Reproduzir com tests/screenshot.gd (verme, cerebro).
- Um print de mineração com iluminação estranha: conferir luz da face/`shake`/tochas no shader (chunk.gdshader) e a cor do céu embaixo da terra.

## Depois
- Mobs e personagem muito básicos/infantis; tela de criação recarrega ao escolher cor e não edita personagem existente.
- Animações de arma em 3D pleno (hoje sprite extrudado).
- Mapa circular (oceano em volta, biomas no meio, baús embaixo), ilhas no céu, afogamento e dano de queda.
- Sons: `sfx.gd` (procedural) está ligado a minerar/quebrar/colocar/acertar/dano/chefe; falta pickup, moeda, bow, swing, splash e tecla M para mutar.
