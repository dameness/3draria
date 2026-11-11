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

### M2 — Vários jogadores, ainda sem rede
Feita (ver "Estado").

### M3 — Rede base: entrar, ver o mundo, ver os outros, construir junto
Feita (ver "Estado"). Falta o playtest do dono (duas abas).

### M4a — Inimigos, dano, itens no chão e projéteis
Feita (ver "Estado"). Falta o playtest do dono (duas abas).

### M4b — Chefes, eventos e estado do mundo
Feita (ver "Estado"). Falta o playtest do dono (duas abas).

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
- [x] M0 (falta o FPS do dono) · [x] M1 · [x] M2 · [x] M3 (falta o playtest) · [x] M4a (falta o playtest) · [x] M4b (falta o playtest) · [ ] M5 · [ ] M6
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
  - `ponytail:` o teste leva ~6 min (assar o mundo em wasm sobre CPU de software leva ~160 s); não entra no `tests/run.gd`.
- **M1 (feita):**
  - **Formato v3.** `.wld` = todos os chunks zstd em `chunks` (+ `baked`, `chest_kinds`, `dungeon_entrance`); `.plr` não mudou de formato.
    `SaveGame._read` aceita v2 e v3 (`OLDEST`); sempre grava v3. Dicionários sem arquivo: `player_out(player, old, world_key)` /
    `player_in(player, data, world_key)` / `world_out(world, player, clock, name)` / `world_in(...)`. A rede (M3) usa estes.
  - **`world.packed`** (`Vector2i -> zstd`). `world.unpack(c)` = packed ou, sem ele, o gerador (thread-safe: o job da fila leva os bytes).
    `world.edited` agora significa "sujo": `flush_edited()` recomprime em `packed` (no save e quando o chunk sai da memória em `_recenter`).
    Mundo sem assar (mundo de teste, testes) continua gerando sob demanda: não há flag a checar nos chamadores.
  - **`scripts/baker.gd`** (`Baker.new(path, area)` → `start()` → `done()`/`progress()` → `finish()`): gera os chunks que faltam em
    `WorkerThreadPool`, mantém os editados de um save v2, anota o tipo dos baús (`world.chest_kinds`, via `WorldGen.chest_kind`) e a
    `dungeon_entrance`, grava v3. O menu assa ao criar o mundo e ao jogar um mundo v2 (`menu.gd: bake_then`, barra de progresso).
    `Baker.needs(path)` é falso para o mundo de teste. **O servidor (M3) deve chamar o mesmo Baker** ao criar mundo, num laço com `OS.delay_msec`.
  - **Medido (nesta máquina, 4 núcleos que paralelizam mal):** assar o mundo todo = 119 s, arquivo 13,6 MB. `start_hardmode` sobre o packed = 2,3 s
    (bloqueia o quadro uma vez; `ponytail:` no código, virar job se incomodar no PC do dono).
  - **O que o gerador ainda decide em jogo (aceito, anotar "mudou o desenho → mundo novo")**: biomas do clima e dos spawns (`*_weight`, `evil`,
    `entities.gd`/`day_night.gd`), `gen.tree` (muda), `hardmode_pass`, `sky_islands`/`evil_center` do painel F9 (só mundo de teste). O `WorldGen.new(seed)`
    ainda roda ao carregar (só o plano da seed, sem gerar chunks).
  - **Baú colocado pelo jogador** em mundo assado sorteia pela altura (`Loot.layer_of`); antes, dentro do dungeon/mar, saía loot dessas tabelas.
  - Armadilha: `Baker` lê `Blocks`/`Loot` (precisam estar carregados) e classe nova pede `.tools/godot --headless --import`.
  - Sobrou: nada da M1. Mundo v2 existente **precisa assar uma vez** (o menu faz sozinho, ~2 min); sem isso ele joga como antes.
- **M2 (feita):**
  - `entities.player` continua sendo **o jogador local** (mensagens `say`, tremor, HUD, mundo de teste, painel F9). Os outros ficam em
    `entities.remotes`; `entities.players` (propriedade) = `[player] + remotes`; `entities.nearest_player(pos)` (null sem ninguém).
  - Inimigo: `enemy.chase` = jogador mais perto, revisto a cada quadro de física (sem `chase`, não pensa). Toda IA de chefe usa `chase`;
    o dano por contato e o tiro inimigo (`projectile.gd`, hostile) ferem **qualquer** jogador que encostam; a vitrine olha para o mais perto.
  - Entities: nascimento por jogador (`try_spawn` → `_spawn_near(who)`; teto = inimigos de quem ele é o mais perto), despawn longe de
    **todos**, `victim()` compara com o mais perto, explosão fere todos, estrela cadente/moradia/Velho/chegada de habitante olham todos os
    jogadores, Olho natural pede que **algum** tenha 200 de vida e 11 de defesa. `spawn_boss(n, near)` nasce em volta de quem invocou
    (`player.gd` passa `self`); verme nasce virado para o mais perto.
  - Item no chão vai para o jogador vivo mais perto (`item_drop._taker`); o remoto recolhe no próprio `inv`. `ponytail:` na M4a vira pedido ao servidor.
  - `world.centers` (Vector3 dos remotos, posto por entities a cada quadro): chunks perto deles não saem da memória; malha só da câmera.
    **Servidor (M3) não tem câmera**: hoje o descarte só roda em `_recenter` (câmera mudou de chunk); lá chamar o descarte sem câmera.
  - **`scripts/remote_player.gd` = contrato do jogador visto de fora:** `position`, `velocity`, `pitch`, `cooldown`, `on_floor`, `swimming`,
    `dead`, `ghost`, `hp`/`max_hp`, `hand` (`held()`), `inv` (equip → `defense()` e o boneco), `eye()`, `HALF`/`TALL`/`EYE`, `flail_state()` = "",
    `flail_snap`, `hurt()` (anota em `hits`; M4a = RPC ao dono), `pickup()` (nada; M4a). Monta um `player_model.gd` no `_ready`.
  - Ficou no jogador local de propósito (são coisas do mundo/da tela, resolver na M3/M4b): `toggle_door` do habitante (`entities.player.toggle_door`),
    `say`, `shake`, `_npc_spot` (usa `player.spawn` = nascimento do mundo), meteorito (perto do local), corações/estrelas (`drop_pickups` olha a vida
    do local), flail/bumerangue (projéteis do dono), timber (tremor). Com `player == null` (servidor) esses pontos quebram: a M3 precisa tratá-los.
  - Teste novo `test_players` em `tests/run.gd`. Os 81 testes antigos passam sem edição.
  - Armadilha: `test_debuffs` já era instável antes da M2 (~4%: um crítico do dardo mata o zumbi de 32 de vida); medido 7/200 antes e depois.
- **M3 (feita):**
  - **RPCs** (todos em `scripts/net.gd`, nó `Net`, primeiro filho da raiz de `game.tscn` e de `server.tscn`; cada cena prende o próprio
    `SceneMultiplayer` na sua raiz com `get_tree().set_multiplayer(api, raiz)`): `hello`/`refuse`/`welcome` (entrada), `chunks` (lotes de 6 por
    quadro, do mais perto ao mais longe, raio = distância de renderização do cliente + 1), `blocks` (os dois sentidos, lote por quadro),
    `state` (15 Hz, não confiável, leva também a distância de renderização) / `states` (15 Hz, raio de 192 blocos), `joined`/`left`, `equip`
    (só quando muda), `time_of_day` (1 Hz; não pode se chamar `clock`, que é a variável do relógio). Buffer do WebSocket = 4 MB por conexão.
  - **Funil:** `world.set_block` chama `world.net.block_changed` (só em rede). Cliente aplica na hora e manda; servidor aplica e repassa a quem
    **já tem aquele chunk** (os outros recebem o chunk já editado), menos ao autor. Conflito de dois editando o mesmo bloco no mesmo instante:
    `ponytail:` o autor fica com a versão dele (sem eco); se incomodar, ecoar ao autor.
  - **`world.authority`** (falso no cliente): `get_block` de chunk que não chegou = `BEDROCK` sem gerar nem guardar; `set_block` nele não faz nada;
    a fila de carga só pega chunks em `packed`; líquidos, mudas e espalhamento (`world._tick`) só com authority. `world.receive(c, zstd)` põe o
    chunk em `packed` e refaz as filas de malha.
  - **Entrada do cliente:** jogador e `Entities` ficam `PROCESS_MODE_DISABLED` até o `welcome` (`world_out` sem `chunks` e sem `map`, aplicado com
    `world_in`) e os 3x3 chunks em volta; então `player.home()` (antes disso a cama "sumiria": o chunk dela ainda é parede).
  - **Servidor:** `.tools/godot --headless -- --server [porta] [arquivo.wld]` (o `menu.gd` desvia para `server.tscn`). Cria e assa
    `user://worlds/servidor.wld` na primeira vez (Baker num laço). `Engine.max_fps = 60`. O nascimento é `net.spawn` (o `world_out/world_in`
    leem `player.spawn`; o Net faz o papel). DayNight roda lá (sem sol nem câmera) e manda a hora.
  - **Versão:** `scripts/update.sh` grava `version.json` (hash do git, fora do git; o export Web leva pelo filtro `*.json`); sem ele = "dev".
    Versão diferente → `refuse` com "atualize a página". Nome repetido também é recusado.
  - **Menu:** Selecionar Mundo → **Multijogador** → endereço (`ws://localhost:8070` padrão; sem `ws://` ele põe) → Entrar. O personagem é o
    escolhido e fica no PC/browser (o `.plr` só vai ao servidor na M5); o nome dele é o que os outros veem.
  - **Bonecos:** `remote_player.gd` filhos da raiz da cena, `Label3D` com o nome, interpolação exponencial (posição e yaw) em `net._process`;
    somem após 1 s sem estado (fora do raio). **No cliente eles NÃO entram em `entities.remotes`** de propósito: os inimigos ainda são locais
    (cada cliente tem os seus até a M4a) e um item no chão iria "para o boneco" e sumiria. A M4a decide como juntar.
  - Armadilha resolvida: `World._ready` recarregava `Blocks`/`Items`... a cada instância e zerava os dicionários enquanto o mesher de outro
    mundo os lia (servidor + clientes no mesmo processo). Agora carrega uma vez (`Blocks.ids.is_empty()`).
  - Armadilhas: `SceneTree` de teste só aceita cena depois do primeiro quadro (`await process_frame` em `tests/net.gd`); fechar o peer
    dentro do próprio RPC (`refuse`) dá erro no poll → `close.call_deferred()`.
  - **Sobrou (das etapas seguintes, já anotado lá):** servidor não salva o mundo (M5: a cada 5 min e ao encerrar) nem tira chunk da
    memória (`ponytail:` em `server.gd`); cada cliente ainda roda os próprios inimigos, meteorito, habitantes e o Olho (M4a/M4b); sono não
    acelera a hora em rede (M4b); cama/`beds` do personagem em rede usam a chave de mundo `""` (M5). Não verificado: duas abas no browser de
    verdade (é o playtest).
- **M4a (feita):**
  - **Servidor roda `Entities`** (em `server.tscn`; `entities.player == null`, `entities.net` = o Net). Cada jogador vira um `remote_player.gd`
    sem modelo (`peers[id].body`, em `entities.remotes`), atualizado pelo `state` (que agora leva também vida, vida máx., mana, mana máx. e
    o bit 8 = fantasma) e pelo `equip` (defesa). **Cliente não roda `_world_tick`** (`world.authority` falso: nascimento, despawn, meteorito,
    Velho, estrelas, habitantes, Olho natural); só a nuvem da Crimson Rod.
  - **`Fx.muted(nó)`** = a cena é servidor de rede com peer de verdade (por cena, não `static`): partículas, sons, modelo do inimigo, ícone do
    item, visual do projétil e boneco do jogador não são montados lá. `spawn_text` sai cedo sem `player`.
  - **Funis e RPCs** (todos em `net.gd`):
    - inimigo: `entities.spawn_enemy/remove_enemy` → `net.enemy_born/enemy_gone` (id de rede no servidor). `foe_states` 10 Hz não confiável
      (`[id, nome do def, posição, yaw, vida, bits 1 investida/2 fase 2/4 veneno/8 fogo]`, raio 96) cria/atualiza o boneco (`enemy.puppet`:
      não pensa, `_glide` interpola e tira a velocidade do deslocamento para animar; 1,5 s sem estado = sai). `foe_hurt` (raio 96) chama
      `enemy.show_hit` (número, som, sangue, vermelho) e `foe_gone(id, morreu)` chama `show_death`. Boneco: `hurt()` → `hit(id, dano, dir,
      recuo, crítico)`, `afflict()` → `curse(id, debuff, s)`. Segmento de verme que troca de papel: o nome do def muda → `enemy.become`.
    - dano no jogador: `RemotePlayer.hurt` no servidor → `hurt` ao dono (no máximo 1 a cada 0,67 s, os quadros de invencibilidade).
    - item no chão: `entities.spawn_drop` no cliente não cria nada no mundo: guarda o nó em `drops_out` e no fim do quadro manda `drop`
      (já com a velocidade/espera que quem chamou pôs). Servidor cria, dá id e anuncia `drop_new` **a todos** (quem entra recebe os que
      existem). Cópia no cliente cai igual; encostando, se `inv.fits(item)`, pede `grab(id)` uma vez; o servidor manda `give(item, n)` ao
      primeiro e apaga o item (`item_drop._exit_tree` com `queue_free` → `drop_gone` a todos). Não coube (`give` chegou com o inventário
      cheio): volta ao chão por `spawn_drop`. Lava e fim da vida: no servidor.
    - projétil: `entities.spawn_projectile` → `net.shot_fired`. Quem atira simula e acerta (cliente: os dele, nos bonecos via `hit`;
      servidor: inimigos e habitantes, nos alvos via `hurt`); os outros recebem `shot(nome, pos, vel)` e veem a cópia (`projectile.puppet`: só voa).
  - Corações/estrelas (`drop_pickups`) olham o jogador mais perto de quem morreu (por isso a vida/mana no estado). `entities.say()` é o
    funil das mensagens (`player.say` sem jogador = nada). Porta: `entities.toggle_door` (habitante no servidor; `player.toggle_door` chama).
  - Teste: `tests/net.gd` ganhou zumbi do servidor ferindo A, bonecos em A e B, golpe de A → vida cai nos três, troca de alvo, morte some
    nos três, drops iguais, dois `grab` juntos → um leva, B joga madeira → A vê → B recolhe, flecha de A em B, ferrão do servidor fere A.
  - Armadilha: lambda no `until` que captura um inimigo que morre dá "Lambda capture was freed": testar pelo id (`sn.foes`).
  - **Sobrou (`ponytail:`):** esfera de conjurador destruída pelo golpe some só para quem bateu; flail, bumerangue, bomba e sinalizador
    não aparecem voando para os outros (o efeito sim: blocos, golpes); itens no chão vão a todos (sem raio de interesse).
    (Mensagens, chefes, barra e habitantes: resolvidos na M4b.)
- **M4b (feita):**
  - **Pedidos ao servidor** (`entities._relay` → RPC `ask(o quê, args)`): `summon` (item invocador; o jogador confere noite/chefe e gasta o
    item antes, o servidor recusa com "já há um chefe"), `orb`, `larva`, `old_man` (o Velho à noite). Funis em `entities.summon/orb_broken/
    larva_broken/curse_old_man`; o chefe nasce em volta de quem pediu (o `body` dele) e mira o mais perto (já era assim).
  - **Barra do chefe para todos:** bit 16 no `foe_states` = é o `entities.boss`; `boss_max` vai nas flags. `boss_life()` soma os bonecos do grupo.
  - **Flags do mundo** (`net._flags()`: orbes, chefes caídos, `meteor_due`, `hardmode`, `npcs`, `homes`, `boss_max`) vão a todos quando mudam
    (comparadas em `str` a 15 Hz) e de novo quando alguém entra. **Hardmode no cliente:** `world.start_hardmode()` refeito sobre os chunks que já
    chegaram (o passe é determinístico; os RPCs confiáveis são ordenados, então chunk velho enviado antes da flag também é convertido).
  - **Avisos:** `entities.say` no servidor → `notice` a todos (chefe despertou, habitante chegou/morreu, meteorito, Olho...).
  - **Baú com trava** (decisão 7): `chest_ask` → o servidor tranca e manda `chest_ok` (o cliente abre o painel por `player.open_chest`); fechar o
    inventário (`hud._set_open(false)`) manda `chest_put` e destranca; os outros recebem `chest_set` (o "não quebra baú cheio" deles fica certo).
    Ocupado: `notice` "<nome> está com o baú aberto". Quem cai com o baú aberto: destranca, o conteúdo fica o de antes.
  - **`world.set_block` apaga o conteúdo do baú/texto da lápide** quando o bloco sai (antes era o `player.break_target`): vale em todos os lados.
  - **Lápide:** `tomb(pos, texto)` cliente → servidor → os outros; quem entra recebe `tombs` no welcome.
  - **Habitantes:** nascem, mudam de casa, morrem e voltam no servidor; conversa e loja locais (o boneco tem o `def`). Para chegarem, o cliente
    manda `bag(item, munição, moedas)` (no máximo 1/s, quando o inventário muda) e o servidor põe no `inv` do `body`.
  - **Sono:** bit 16 no `state`; o servidor acelera a hora só com **todos** dormindo e sem chefe, e manda a hora na hora. O cliente não mexe
    em `clock.speed` (`world.authority`).
  - **Árvore, porta, carrinho:** já funcionavam pelos funis (blocos e drops); nada novo (a queda animada é só de quem cortou).
  - **Mundo de teste/F9 só em OFF:** o servidor recusa abrir mundo de teste; o welcome não leva a flag `test`.
  - **Pausa:** o botão Configurações não pausa a árvore em rede (`get_tree().paused` só sem `world.net`).
  - Teste: `tests/net.gd` ganhou chefe invocado por A (servidor, barra e mensagem em B, segundo recusado), flags e hardmode nos dois, orbe,
    lápide, Arms Dealer pela bala de A, baú com trava (B recusado, A guarda gel, B vê), sono (só A não acelera; os dois aceleram).
  - **Sobrou (`ponytail:`):** a bola de fogo do meteorito não aparece para os clientes (só a cratera e o aviso); o Velho e o "Volte à noite"
    não foram testados em rede (o caminho é o mesmo `ask`); cama/`beds` em rede continuam na chave de mundo `""` (M5).

