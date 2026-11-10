# Multijogador no browser — plano (M0–M7)

Objetivo do dono: jogar pelo browser com os amigos (10 ao mesmo tempo), num servidor (VPS), com mundo e personagens guardados
no servidor e sobrevivendo às atualizações do jogo. **Próximo passo prioritário do roadmap.**

Uma sessão = uma etapa M abaixo. Cada sessão lê **só** `CLAUDE.md` + este arquivo, faz a etapa, atualiza a seção
"Estado" no fim e apaga da etapa o que ficou pronto. Prompts prontos no fim.

## Como o código está hoje (nov/2026, medido)
- Nada de rede. ~12,6 mil linhas em `scripts/`, 81 testes em `tests/run.gd` (6,2 mil linhas).
- Um jogador só, por referência direta: `player.` / `entities.player` aparece 113× em `hud.gd`, 63× em `entities.gd`,
  15× em `enemy.gd`, e em `projectile.gd`, `item_drop.gd`, `timber.gd`, `minimap.gd`, `day_night.gd`.
  `game.tscn` liga `World`, `DayNight`, `Entities` e `Player` por `NodePath`.
- Pontos bons para a rede:
  - toda mudança de bloco passa por `world.set_block` (20 chamadas em 6 arquivos): um funil só;
  - `player.step(delta, wish, jump)` já é separado da leitura do teclado;
  - `entities.victim(e)` já escolhe alvo (habitante × jogador);
  - o save já guarda itens **por nome** (`Items.names`), então item novo não quebra personagem.
- Save (`save_game.gd`, v2): o `.wld` guarda **só os chunks editados**; o resto é refeito pela seed com o gerador **atual**.
- Geração: 120×120 = 14 400 chunks. Medido nesta máquina (1 thread): **10,7 ms/chunk → ~2,5 min o mundo inteiro**;
  zstd médio **962 B/chunk (máx. 2,4 KB) → ~14 MB o mundo inteiro**. Sem compressão seriam 472 MB.
- Em tempo de jogo o gerador ainda é consultado para: tipo de baú (`living_chests`, `sky_chests`, `in_dungeon`, `in_sea`),
  biomas dos spawns e do clima (`*_weight`, `evil`), `dungeon_entrance`, `tree` (muda), `hardmode_pass`.
- Blocos: 93 de 255 ids possíveis (chunk = 1 byte por bloco). Folga grande.
- Export: não há `export_presets.cfg` (está no `.gitignore`). `atlas.gd` lê os sprites com
  `ProjectSettings.globalize_path("res://assets/wiki/")`, que **não funciona em build exportado**.
  `assets/wiki/` e `assets/models/` ficam fora do git (gerados pelo `update.sh`).

## Mudança da geração × mundo dos amigos
**Hoje seria problema.** Trocou `world_gen.gd` → os chunks nunca editados nascem do gerador novo e os editados ficam do velho:
emendas no terreno, dungeon/Living Trees/ilhas mudam de lugar, baú fechado muda de tipo, casa e cama podem ficar soterradas.
Em rede seria pior: cada cliente geraria um terreno diferente do servidor.

**Solução (etapa M1): mundo assado, como no Terraria.** O mundo inteiro é gerado uma vez na criação e gravado (~14 MB).
Daí em diante o `.wld` é a verdade; o gerador só serve para mundos novos. O servidor manda os chunks prontos aos clientes,
que **nunca** rodam `world_gen.gd` (bom também para o browser, onde gerar é lento).

Consequência aceita: bioma/minério/estrutura novos **não aparecem no mundo antigo** (igual ao Terraria). Saídas:
1. mundo novo com os **mesmos personagens** (o `.plr` é separado do `.wld`; o servidor pode ter vários mundos);
2. quando valer a pena, um passe de retrofit determinístico só nos chunks nunca editados (o modelo é `hardmode_pass`).

O que **não** quebra mundo nem personagem: itens, receitas, inimigos, drops, números, blocos novos **no fim** de
`blocks.json`/`items.json` (regra que já existe). Reordenar esses arquivos corrompe todos os mundos.

## Decisões de arquitetura (o mínimo que funciona; não reabrir sem motivo)
1. **Servidor dedicado** = o mesmo projeto, `--headless`, cena `server.tscn` (World sem malha + DayNight + Entities, sem Player/HUD).
2. **Transporte:** multiplayer de alto nível do Godot com `WebSocketMultiplayerPeer` (browser não tem UDP). Todos os `@rpc`
   num nó só, `scripts/net.gd`, mesmo caminho de nó nos dois lados. TLS fica no Caddy (`wss://`), não no Godot.
3. **Quem manda:**
   - servidor: blocos, líquidos, mudas, espalhamento, hora, inimigos e chefes, habitantes, itens no chão, baús, flags do mundo;
   - cliente: o próprio personagem (movimento, inventário, vida, o dano que causa). É jogo entre amigos: sem anti-trapaça.
4. **Um modo, não uma reescrita:** `net.mode` = `OFF` (um jogador, como hoje, todos os testes atuais valem) / `SERVER` / `CLIENT`.
   O modo é do **nó** (não `static`), porque os testes sobem servidor e clientes no mesmo processo.
5. **Funis** (o desvio de rede mora neles, não nos chamadores):
   - `world.set_block`: cliente aplica na hora e envia; servidor aplica e repassa aos outros. Lote por quadro.
   - `world.get_block` no cliente: chunk que ainda não chegou conta como parede (nunca gera).
   - `enemy.gd` com flag `puppet`: no cliente não pensa, interpola o estado recebido; `hurt()` vira pedido ao servidor.
   - `item_drop.gd`: quem pega é decidido pelo servidor (o primeiro pedido leva).
6. **Estado contínuo** (jogadores, inimigos): pacote compacto a 10–15 Hz só para quem está perto (raio de interesse).
   Eventos (bloco, golpe, drop, baú, chefe): RPC confiável.
7. **Baú:** um jogador por vez (como no Terraria), o servidor tranca. Sem trava haveria item duplicado.
8. **Personagem no servidor:** o cliente manda o dicionário do `.plr` a cada 60 s, ao mudar o inventário (com espera de 5 s)
   e ao sair; o servidor grava `players/<nome>.plr`. Login = senha do servidor (uma, dos amigos) + nome + senha do personagem
   (hash com sal no `.plr`). `ponytail:` aba fechada de repente perde até 60 s.
9. **Versão:** o build grava o hash do git; servidor recusa cliente de outra versão com "atualize a página".
10. **Hospedagem:** uma VPS (2 vCPU, 2–4 GB). Caddy serve o build Web (cabeçalhos COOP/COEP por causa das threads, `basicauth`
    porque os sprites da wiki são de uso pessoal) e faz proxy de `/ws` para o Godot. Precisa de um domínio (pode ser DuckDNS)
    para o TLS automático.

## Etapas

### M0 — Export Web de um jogador + medir (portão)
Feito (ver "Estado"). Falta só o **portão**: o dono abre `build/web/` no Chrome do PC dele e devolve o FPS (F10) com distância 6,
parado e andando. Abaixo de ~40 fps: parar e decidir (reduzir distância padrão no Web, ou cliente nativo com o mesmo servidor;
as etapas M1–M6 não mudam).

### M1 — Mundo assado + save em dicionários
- `SaveGame`: separar `player_out(player) -> Dictionary` / `player_in(player, data)` e `world_out` / `world_in` do acesso a
  arquivo (a rede reusa os dicionários). Save **v3**; ler v2 e converter.
- `world.packed`: `Vector2i -> bytes zstd` de **todos** os chunks. `get_block`: sem o chunk na memória, descomprime de
  `packed`; só gera se não houver (mundo de teste e testes continuam sem assar). Chunk editado que sai da memória volta
  comprimido para `packed`. O save grava `packed` + os carregados.
- Assar na criação do mundo (menu com barra de progresso, `WorkerThreadPool`); mundo v2 é assado com o gerador atual na
  primeira carga (é o que ele já mostraria hoje).
- Tirar do gerador o que é consultado em jogo e gravar no `.wld`: posições e tipo dos baús especiais, entrada do dungeon.
  Listar os outros usos (`grep "gen\." scripts/`) e decidir um a um: assar ou aceitar (biomas por raio/ângulo: aceitar e
  anotar "mudou o desenho dos biomas → mundo novo").
- `start_hardmode`: passar por todos os chunks de `packed` (medir o tempo; em thread se passar de 2 s).
- Teste: assar um mundo pequeno, trocar o gerador (outra seed) e conferir que os blocos carregados não mudam; ida e volta
  de `world_out`/`world_in` e `player_out`/`player_in`.

### M2 — Vários jogadores, ainda sem rede (refatoração pura)
A etapa mais delicada: mexe em IA e spawn sem mudar o comportamento de um jogador. **Os 81 testes atuais passam sem editar.**
- `entities.players: Array` (um jogador: `[player]`) + `entities.nearest_player(pos)`; cada inimigo guarda o seu alvo.
  Trocar os usos de `entities.player` em `entities.gd`, `enemy.gd`, `projectile.gd`, `item_drop.gd`, `timber.gd`.
- Spawn e despawn por jogador (teto por jogador; some quem está longe de **todos**); chefe mira o mais perto;
  `victim()` passa a comparar com o jogador mais perto do inimigo.
- `world`: carregar/descartar chunks por uma lista de centros (hoje é a câmera); malha continua só para a câmera local.
- Definir o contrato do "jogador visto de fora" (o que `enemy.gd`, `projectile.gd`, `player_model.gd` leem: `position`,
  `velocity`, `hurt()`, `defense()`, `inv` da mão/armadura, `cooldown`, `pitch`, flail) e criar `remote_player.gd` com só isso.
- `hud.gd`, `minimap.gd`, `held_item.gd` continuam presos ao jogador local: não mexer.
- Testes novos: dois alvos → inimigo persegue o mais perto e troca; spawn em volta dos dois; drop vai a quem está perto.

### M3 — Rede base: entrar, ver o mundo, ver os outros, construir junto
- `scripts/net.gd` (todos os RPCs), `server.tscn` + `scripts/server.gd`, argumento `--server` e porta; no menu, "Multijogador"
  (endereço, nome). Login mínimo sem senha (as contas são da M5).
- Entrada: servidor manda versão, estado do mundo (`world_out` sem chunks) e os chunks do raio do cliente, comprimidos, do mais
  perto ao mais longe, **com vazão limitada** (o buffer padrão do `WebSocketMultiplayerPeer` é de 64 KB: aumentar e mandar
  N chunks por quadro). Novos chunks conforme o jogador anda.
- `set_block` nos dois sentidos pelo funil; relógio do servidor (o cliente só interpola).
- Jogadores: cada cliente manda posição/rotação/pose/item na mão/armadura a 15 Hz; os outros aparecem como `remote_player.gd`
  com o `player_model.gd`, interpolados, com o nome em cima.
- No servidor só rodam líquidos, mudas e espalhamento (`world.authority`); no cliente esses passos ficam desligados.
- Teste `tests/net.gd`: servidor + 2 clientes **no mesmo processo** (um `SceneMultiplayer` por ramo:
  `get_tree().set_multiplayer(api, caminho)`, WebSocket em 127.0.0.1): A quebra um bloco → B vê; B entra depois e recebe o
  chunk editado; A anda → B vê o boneco. Cuidado com os `static` compartilhados (`SaveGame.world_path`, `TestWorld`).
- Playtest do dono: `scripts/serve-web.py` + servidor local, duas abas.

### M4a — Inimigos, dano, itens no chão e projéteis
- Servidor roda `Entities` com os jogadores remotos da M2. Cliente não chama `try_spawn`.
- Inimigo: id de rede; nascer/sumir/morrer por evento; estado (posição, direção, modo de animação, vida) a 10 Hz para quem
  está perto; no cliente `enemy.gd` em `puppet`. Servidor **não** monta modelo 3D (só colisão e IA).
- Golpe do jogador: o cliente calcula como hoje contra os bonecos e manda `hit(id, dano, direção, recuo, crítico)`.
  Dano no jogador: o servidor manda `hurt` ao dono; a vida é do cliente (ele avisa quando morre).
- Projétil de jogador: o dono simula e acerta; os outros recebem só o evento de nascer (visual). Projétil de inimigo: servidor.
- Itens no chão: nascem no servidor; `pickup(id)` → o primeiro leva; drops de inimigo e de bloco pelo mesmo caminho.
- Textos de dano, partículas e som: locais, disparados pelos eventos.
- Teste: 2 clientes, um inimigo; A bate → vida cai nos dois; morre → drop único; inimigo troca de alvo.

### M4b — Chefes, eventos e estado do mundo
- Chefes (barra de vida para todos, alvo mais perto, invocação por RPC), Olho natural, meteorito, orbes, larva, hardmode.
- Flags do mundo (`eoc_down`, `hardmode`, `npcs`, `homes`...) num dicionário replicado na entrada e a cada mudança.
- Baús com trava; habitantes (conversa e loja locais; morte/volta no servidor); lápides; porta; carrinho (local, só a posição
  vai aos outros); cama: ponto de nascimento por personagem e **a hora só acelera com todos dormindo**.
- Árvore: quem corta roda `Timber.fell` (os outros veem os blocos sumirem; `ponytail:` sem a animação da queda para eles).
- Mundo de teste e painel F9 só em `OFF`.

### M5 — Contas e persistência
- Login: senha do servidor + nome + senha do personagem; criar personagem pelo menu contra o servidor.
- `.plr` no servidor (item 8 das decisões); cama por mundo já existe (`beds`); mapa explorado por jogador e por mundo
  (`map_img` hoje é do mundo): guardar comprimido no `.plr`, enviado a cada 5 min e ao sair.
- Servidor: salvar o mundo a cada 5 min e ao encerrar (SIGTERM), gravação atômica (já existe: `.tmp` + rename), 7 cópias
  diárias em `backups/`. Recusar versão diferente. Reconectar sem perder o personagem; mesmo nome duas vezes: recusa.
- Teste: entrar, mudar inventário e mundo, derrubar o servidor, subir de novo, entrar: tudo lá. Save v3 de antes de um
  item/bloco novo no fim dos JSON carrega igual.

### M6 — Publicar
- `scripts/deploy.sh usuario@host` (roda no PC do dono: a sessão remota não alcança a VPS): export Web, `rsync` do build e do
  projeto, reinício do serviço. `deploy/Caddyfile`, `deploy/3draria.service` (systemd, reinício automático, usuário sem root).
- `docs/DEPLOY.md`: criar a VPS, domínio, primeira instalação, atualizar, restaurar backup, criar mundo novo mantendo personagens.
- Segredos (senha do servidor, `basicauth`) só na VPS, nunca no git.
- Teste de carga: 10 clientes-robô headless andando e minerando por 5 min; medir tempo por quadro do servidor e banda.
  Alvo: servidor a 60 Hz (cair para 30 Hz se a CPU não der) e < 50 KB/s por jogador.

### M7 — Depois do primeiro jogo com os amigos
Lista aberta: atraso/interpolação, o que dessincronizar, conforto (chat, lista de jogadores, ponto no mapa de cada um, PvP não).
Só depois disto o roadmap de conteúdo (F6 Hardmode) volta, com a regra abaixo.

## Regra permanente depois da M3
Todo sistema novo declara quem manda (servidor ou cliente) e passa pelos funis; teste de rede em `tests/net.gd` quando
mudar o mundo ou outro jogador. Conteúdo em JSON não precisa de nada.

## Riscos
- **FPS no browser** (GDScript em WebAssembly; a malha dos chunks pesa): resolvido ou não na M0.
- **Safari** costuma dar problema com threads/WebGL2: combinar Chrome ou Firefox.
- **WebSocket é TCP:** perda de pacote vira engasgo, não salto. Para 10 amigos é aceitável; WebRTC só se incomodar.
- **CPU do servidor:** GDScript com inimigos em volta de 10 jogadores espalhados. Medido na M6; válvulas: teto de inimigos
  por jogador, IA a 30 Hz, raio de simulação menor que o de visão.
- **Dois caminhos (OFF e rede):** cada funil tem um `if`; mais que isso num sistema é sinal de desenho errado.

## Sessões, modelo e prompts
Nível do modelo: **A** = o mais forte disponível para código; **B** = intermediário, mais barato. Sessão nova para cada etapa
(contexto curto = menos tokens); não emendar duas etapas na mesma sessão.

| Sessão | Etapa | Nível | Depende de |
|---|---|---|---|
| 1 | M0 export Web | B | — (portão: FPS do dono) |
| 2 | M1 mundo assado | B | — (pode vir antes do retorno da M0) |
| 3 | M2 vários jogadores | A | M1 |
| 4 | M3 rede base | A | M2 |
| 5 | M4a inimigos e combate | A | M3 |
| 6 | M4b chefes e mundo | B | M4a |
| 7 | M5 contas e saves | B | M4b |
| 8 | M6 publicar | B | M5 + VPS e domínio do dono |

Prompt (troque só `[Mx]`; para a M6 acrescente o domínio e o usuário da VPS, **nunca senhas**):
```
Repo dameness/3draria. Leia SÓ CLAUDE.md e docs/MULTIPLAYER.md (não leia BACKLOG, REVISAO nem HANDOFF; não leia hud.gd,
player.gd nem tests/run.gd inteiros: use grep e leia os trechos). Faça a etapa [Mx] do docs/MULTIPLAYER.md e só ela,
seguindo as "Decisões de arquitetura" sem reabri-las; se uma decisão se mostrar errada, pare e me explique antes de mudar.
Antes de codar, confira no código o que a etapa afirma (o plano é de nov/2026). Commits pequenos, cada um com teste;
`.tools/godot --headless -s tests/run.gd` verde no fim (e tests/net.gd a partir da M3). Push na branch da sessão, sem PR.
Ao terminar: apague da etapa o que ficou pronto, anote em "Estado" o que foi decidido, as armadilhas e o que sobrou,
e me responda curto em português com: o que mudou, como testar (passo a passo), como rebuildar e se precisa de mundo novo.
```
Extra por etapa, colado depois do prompt:
- **M0:** `Termine me pedindo o FPS (F10) no Chrome do meu PC, com distância 6, parado e andando.`
- **M2:** `É refatoração: nenhum teste existente pode ser editado para passar. Se um precisar mudar, pare e me diga qual e por quê.`
- **M3:** `Antes de codar, escreva em 15 linhas a lista de RPCs (nome, sentido, confiável ou não) e espere meu ok.`
- **M4a:** `Comece listando o que enemy.gd, projectile.gd e item_drop.gd leem e escrevem do jogador; isso define os RPCs.`
- **M6:** `Não tenho como te dar acesso à VPS: entregue scripts que eu rodo e um DEPLOY.md de copiar e colar.`

## Estado
- [x] M0 (falta o FPS do dono) · [ ] M1 · [ ] M2 · [ ] M3 · [ ] M4a · [ ] M4b · [ ] M5 · [ ] M6
- **M0 — decisões e armadilhas:**
  - `export_presets.cfg` agora é versionado (preset Web, threads ligadas). Export: `scripts/export-web.sh` (templates por Range
    do .tpz: ~20 MB em vez de 1,2 GB) → `build/web/` (63 MB: wasm 38 + pck 26; `build/` tem `.gdignore` e está no `.gitignore`).
  - **`assets/.gdignore` esconde sprites e modelos também do export.** O script tira o `.gdignore`, grava `.import` com
    `importer="keep"` (png/glb vão crus; `.vox/.json` entram pelo filtro) e restaura tudo no fim (trap). Não mexa nisso à mão.
  - `release` não aceita cena por argumento (`--scene`): o teste navega pelo menu real, por cliques (coordenadas em `tests/web.js`;
    mudou o layout do menu → ajustar lá).
  - Código: `atlas.gd` lê `res://` direto; `enemy_model.gd` usa `append_from_buffer` (o `append_from_file` não lê do .pck).
    `item_model.gd`/`voxel/` já usavam FileAccess/texturas em memória: nada a mudar.
  - Teclas (`player.gd`/`hud.gd`, só `OS.has_feature("web")`): `beforeunload` com confirmação durante o jogo (sai ao voltar ao menu);
    **Alt+Enter** = tela cheia, e em tela cheia o `navigator.keyboard.lock()` segura Ctrl+W; o **Esc do browser solta o ponteiro e o
    jogo nunca vê a tecla**: o evento `pointerlockchange` abre o inventário. F5 não recarrega (testado). `user://` sobrevive a
    recarregar (testado: personagem e mundo voltam na lista).
  - Testado em Chromium headless com WebGL por software (sem erros no console); **FPS dali não vale**.
  - Sobrou/não verificado: Tab, F9–F11 e Ctrl+W real (Playwright não os alcança); FPS no hardware do dono; Safari não tentado.
    Ícones das casas de Moedas/Munição variaram entre execuções nos prints do Web (vi cobre/flecha/ouro): olhar se persistir no PC do dono.
  - `ponytail:` o teste leva ~3 min (mundo novo gera em wasm sobre CPU de software); não entra no `tests/run.gd`.
