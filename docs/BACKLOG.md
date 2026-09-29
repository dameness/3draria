# Backlog — o que falta (fonte única de pendências; leia este antes de qualquer outro doc)

**Estado:** `main` já tem tudo até aqui (menu no layout do Terraria, golpe diagonal, poção no cursor, projéteis com sprite da wiki, inimigos com sprite, Configurações em categorias, mundo de teste com "Reiniciar mundo").
Testes verdes (`tests/run.gd`, `tests/menu_flow.gd`). Não precisa de mundo novo. Histórico detalhado: `docs/REVISAO.md` (não precisa ler inteiro).

## Como trabalhar (curto)
- Uma sessão = um assunto abaixo. Ao terminar: testes, commit pequeno, push, prints (folha de contato, só do que mudou), "como testar/rebuildar/mundo novo".
- Números e sprites sempre da wiki (`scripts/wiki.py`, `curl` na API). Referências visuais do dono: `docs/referencias/` (menus do Terraria). Vídeos: ver `CLAUDE.md` (Reddit ok, YouTube só busca).
- Ao concluir um item, apague-o daqui (não arquive aqui; o histórico é o `git log`).

## Agora (nesta ordem)
1. **Personagem e armaduras** (2 passadas feitas: rosto aberto, ombreiras grandes, braços grossos; armadura com textura de placas pixeladas × cor do ícone). Falta o dono dizer o que ainda incomoda (proporção da cabeça, cores, volume). Molten, Meteor e Ninja com formato próprio já feitos.
2. **Inimigos:** revisão dos modelos além dos que já usam sprite (slimes, olhos, esqueleto, zumbi, chefes); nomes/comportamentos conferidos com a wiki.

- Projétil 3D só onde o sprite é pixel art pequeno (`"solid": true` em projectiles.json: Enchanted e Rotted Fork); Terra Beam (crescente 297x520), laser e espinho seguem billboard.
- Efeitos de armadura da wiki ainda sem código (por isso sem texto na dica): Molten (+7% dano/velocidade/crítico corpo a corpo), Meteor (+9% dano mágico), Ninja (+3% crítico); bônus de conjunto de Molten/Ninja.

## Depois
- Habitantes andando pela casa e voltando à noite; mais habitantes (Demolitionist, Arms Dealer…); parede de fundo.
- Ball O' Hurt (mangual), Starfury, Celestial Magnet, Sky Mill; mais asas no Hardmode.
- Editar personagem existente; Conquistas/Créditos/Configurações no título; escala da interface; tempo de jogo no save.
- Sons que faltam e música/ambiente (a wiki hospeda os áudios); autosave + backup do mundo.
- Biomas (neve, deserto, selva), luz que se espalha pelas tochas, eventos (Lua de Sangue, Goblin Army).
- Bot de progressão (joga até o Hardmode) e GitHub Action rodando os testes a cada push.
- Hardmode e Calamity (`docs/ROADMAP.md`) — só depois do básico bom.

## Em aberto com o dono
- Bug do verme/subsolo: causa raiz corrigida (chunk gerado na fila), mas o dono ainda não conseguiu verificar.
- Pedir playtest do que mudou desde o último: Configurações, cartões do menu, inimigos com sprite, "Reiniciar mundo" (F9).
