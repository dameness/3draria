# Contexto para continuar numa sessão nova

Repo `dameness/3draria`, branch **`claude/vigilant-babbage-nv53lx`** (commit e push nela; **não abra PR** sem o dono pedir; se o ambiente
sugerir outra branch, siga o dono). Jogo voxel 3D com o conteúdo e a progressão do Terraria (Godot 4.7.2, GDScript, renderer
Compatibility). Uso pessoal. O dono joga num PC Ubuntu modesto e testa localmente; a sessão remota **não tem GPU nem tela**: valide com
testes headless e com prints via Xvfb (e **olhe as imagens**). Respostas curtas, em português, com guia de teste no fim.

## Prompt pronto para colar numa sessão nova
```
Repo dameness/3draria, branch claude/vigilant-babbage-nv53lx (commit e push nela; NÃO abra PR). Jogo voxel 3D em Godot 4.7.2 com o conteúdo do Terraria; o dono testa local num
PC Ubuntu modesto e você não tem GPU: valide com testes headless (.tools/godot --headless -s tests/run.gd e tests/menu_flow.gd) e prints via xvfb (tests/screenshot.gd), e OLHE as imagens.
Leia CLAUDE.md, docs/HANDOFF.md, docs/REVISAO.md (o que foi feito item a item + "Depois"), docs/UI.md e data/CLAUDE.md; rode scripts/update.sh.
Regras do dono: Terraria em 3D (não copiar Minecraft), GUI e jogabilidade como as do Terraria, muita animação, bom desempenho; números sempre da wiki (curl na API ou scripts/wiki.py).
Commits PEQUENOS (uma mudança visível cada, com teste em tests/run.gd e, se visual, um print que você olhou), push depois de cada um; ao fim de cada commit diga em 2-3 linhas como
testar, como rebuildar (git pull && scripts/update.sh && .tools/godot) e se precisa de mundo novo. Respostas curtas, em português. Ponytail: o código mais simples que funciona.
Já feito: revisão pré-hardmode (REVISAO 1-8) e a sessão 3 (mundo de teste no menu, moedas/munição em qualquer slot, Fallen Star, câmera dentro da terra, Guia e moradia, queda e afogamento,
poções de luz, itens das orbes, ilhas flutuantes, mundo em ilha, gancho, cursor inteligente, sons).
Falta: o que está em "Depois" no REVISAO.md e, só depois, hardmode/Calamity (docs/ROADMAP.md). Peça ao dono o playtest do que ainda não foi testado (ver "Perguntas ao dono" no REVISAO).
```

## Revisão pré-hardmode (feita)
`docs/REVISAO.md` tem, item a item, o diagnóstico, a wiki e o que foi feito: minimapa, verme, Brain, iluminação, árvores, binds (Esc = inventário,
Configurações), ataque (autoswing/tool speed/mira), danos (variância/crítico/martelos), asas e modo criativo, loot/Life Crystal/poções/buffs, mana e magia,
NPCs (Guide, Merchant, Nurse). Mundo novo necessário. Pendências em "Depois" do REVISAO.

## Comandos
```sh
scripts/update.sh                              # após git pull: Godot + sprites + cache de classes (rodar --import após novo class_name)
.tools/godot --headless -s tests/run.gd        # testes (saída != 0 em falha; ~10 s)
xvfb-run -a -s "-screen 0 1280x720x24" .tools/godot -s tests/screenshot.gd -- spawn minera arco   # prints em textures/shot_*.png; sem argumentos = todos (~90 s)
xvfb-run -a -s "-screen 0 1280x720x24" .tools/godot -s tests/menu_flow.gd                        # menu → jogo → salvar → recarregar (+ prints textures/menu_*.png)
xvfb-run -a -s "-screen 0 1280x720x24" .tools/godot -s tests/character_preview.gd -- gold big walk item:iron_broadsword   # boneco: sets, big, walk, swing, seq (golpe em 5 quadros), item:nome, name:Fulano
scripts/wiki.py items|recipes|npcs "Nome"      # números oficiais (a wiki dá 429: o script já tenta de novo); páginas com curl na API (WebFetch é bloqueado)
```
Sempre ao fim de um passo: testes verdes, commit, push (na branch acima) e um guia curto de playtest **com "como rebuildar"**
(`git pull && scripts/update.sh && .tools/godot`) e se **precisa de mundo novo** (mudou `world_gen.gd`; até aqui **não precisa**: os ids novos
de líquido entram no fim de `blocks.json` e saves antigos continuam válidos).

## Feito (tudo commitado, testado e enviado)
- **V6–V8** (sessões anteriores): céu procedural, mundo (serras, lagos, árvores), GUI no layout do Terraria, personagem e armaduras por peça.
- **Bugs do playtest v8** (`158e957`): *água* agora flui (`liquid.gd`: níveis 1–8 em ids `water_1..7`/`lava_1..7`, cai e espalha conservando
  o volume, só reage a edições; malha com altura por nível e degraus); *jogador* vadeia até a cintura (anda/pula normal) e nada abaixo
  disso, e junto da margem Espaço dá um pulo inteiro (sai de poça de 1 bloco e de água funda); *boneco* com cabeça menor, ombros/mangas
  cobrindo o topo, braços com pivô no ombro (`PlayerModel`), golpe e braços balançando **para a frente** (o sinal antigo era invertido),
  item na mão com o plano do sprite no plano do golpe, aparência por nome (`SaveGame.look_for`); *inimigo fica vermelho* ao levar golpe
  (a sobreposição nunca era ligada: lógica de transição invertida); *"ver abaixo da terra"* = câmera de 3ª pessoa atravessando o chão
  (raio só para trás, sem o ombro): agora raio dos olhos até o ponto da câmera + rede de segurança `lens_clear`, com teste de 1500 ângulos
  (o código antigo falhava em 137 deles); `near` da câmera 0,02 → 0,05 (mais precisão de profundidade).
- **Prioridade 1 — menu** (`ddeab39`): `menu.gd` com o mundo real ao fundo (World + DayNight, distância 4, dia 9× mais rápido, câmera em
  órbita da planície de nascimento), logo 3DRARIA em 3 camadas, botões só texto que crescem no mouse, painel à direita (lista com nome/info/
  apagar, criar), personagem escolhido de pé à esquerda (muda ao passar o mouse na lista e ao digitar nome novo), Esc volta, entra do preto.
- **Prioridade 2** (`5899911`): `fx.gd` (partículas: poeira, lascas, faíscas, gotas, nuvem, respingo, bolhas) usadas ao minerar, ferir/matar,
  andar, pousar, entrar na água; **mineração como o Terraria** (wiki *Pickaxe power*: dano por golpe = poder × `mine` do bloco, 100 quebra;
  terra 2 golpes com cobre, pedra 3, grama 3; grama absorve um golpe; a picareta também fere inimigos; o golpe cai no impacto da animação)
  com **rachaduras em 4 estágios** (`block_crack.gd`, somem após 2,5 s sem golpear); **arco do golpe** (`trail.gd`) em 1ª e 3ª pessoa;
  **braço em 1ª pessoa** preso ao ombro (`held_item.gd`) com inércia ao girar, balanço ao andar e empurrão ao colocar bloco; **slime legível**
  (contorno escuro, miolo, olhos, sombra) e `blue_slime` (25 de vida, 7 de dano, defesa 2, da wiki); cor das gotas por inimigo (`blood`).

## Feedback do dono (manter em mente sempre)
- v6: quase sem animação; Tab não abria o inventário (corrigido); faltava jogabilidade estilo Terraria; armaduras/personagem pareciam
  Minecraft (refeitos); **desempenho bom** (manter e pedir o FPS de volta).
- v7: pause não funcionava (corrigido); "ainda sem animações"; "luta meio estranha" (ajustei acerto e arco; **peça detalhes**).
- v8 (último): água não se espalhava e não dava para sair pulando de 1 bloco; braços separados do corpo, cabeça grande, camiseta não cobria
  o topo; monstro não ficava vermelho; sem animação de quebrar bloco/árvore; dava para ver abaixo da terra em certos ângulos; iluminação boa;
  mobs "meio estranhos ainda, mas tudo bem"; GUI "um pouco estática, mas tudo bem"; **NPCs ainda não achou (não existem: roadmap)**; GUI de
  entrada estranha (refeita). Tudo isso já foi tratado exceto GUI estática e NPCs. **Peça um playtest** dessas correções, principalmente:
  água (cavar ao lado de um lago), sair da água, o boneco em 3ª pessoa (V), o menu, o FPS (as partículas e o fluxo são novos).
- Regras: Terraria em 3D, nunca Minecraft; GUI e jogabilidade como as do Terraria; muita animação; desempenho bom; conteúdo é dado (JSON).

## Falta
Ver "Depois" e "Perguntas ao dono" no fim de docs/REVISAO.md (o que era daqui já foi feito).

## Armadilhas e descobertas
- **Godot: `rotation.x` positivo balança braço/perna para a FRENTE** no modelo (olha para -Z); vários sinais estavam invertidos. Pivô de
  braço = ombro. Item na mão: plano do sprite = plano do golpe (base `Basis(b.cross(RIGHT), b, RIGHT)` em `_show_held`).
- `material_overlay` funciona no Compatibility; o problema do "clarão" era lógica (só detectava a transição de desligar).
- Chamada de função GDScript disputa uma trava entre threads: código de thread (`world_gen.gd`, `chunk_mesher.gd`) não chama função no laço
  quente. `WorkerThreadPool.add_task` sem prioridade alta usa só ~30% das threads. Sem GPU o FPS dos prints é de CPU e não vale.
- Líquidos: `Blocks.liquid_kind/level/level_ids`; o fluxo grava com `world.set_block(..., false)` e acorda vizinhos; teste com
  `world.liquid.settle(world)`; ~1 ms por geração num lago 18×18×3. Chunk não gerado conta como parede.
- Mudou a geração (`world_gen.gd`)? Mundos salvos ficam com emendas: peça mundo novo. Save v2; `Inventory.SIZE` = 50.
- Novo `class_name`: rode `.tools/godot --headless --import` (senão "Identifier ... not declared"; `update.sh` faz).
- GDScript: `var a := x * p[2]` com `p` sem tipo não infere (use `var a: float = ...`); `ready` é nome reservado de Node; `Slot` é classe interna do `hud.gd`.
- Edições por script Python: confira a indentação (tabs) e use `assert old in s`; um `replace` que não casa passa em silêncio.
- Prints rodam a ~8 quadros/s: partículas (0,5–0,9 s) e arco (0,17 s) precisam ser disparados 1–4 quadros antes do print (ver `tests/screenshot.gd`).
- O classificador de comandos do ambiente às vezes falha de forma transitória: tente de novo.
- `textures/` e `assets/wiki/` ficam fora do git; `docs/img/` tem os prints de antes/depois (V6–V8).


## Atualização (sessão pré-hardmode)
Feito e testado (commits na branch `claude/vigilant-babbage-nv53lx`; a "claude" pura não pôde ser criada: conflita com `claude/...`): GUI completa (minimapa,
moedas, munição, acessórios, baús, favoritar, ordenar, animações), Corrupção/Carmesim + Eater of Worlds + Brain, Nightmare/Deathbringer/Molten,
obsidiana, King Slime, meteorito, Skeletron + dungeon + Velho, Wall of Flesh + hardmode (cobalto/paládio, Hallow), machados, baldes, olhos piscam,
cores na criação de personagem, sons procedurais. **Precisa de mundo novo** (mudou a geração). Próximo: docs/REVISAO.md.

## Atualização (sessão 3)
Tudo commitado e testado na branch (ver REVISAO "Sessão 3"). **Precisa de mundo novo** (mudou a geração: ilha com oceano, ilhas flutuantes, blocos novos no fim de blocks.json: cloud, sunplate, chair,
door, door_open). Para testar tudo sem grindar: menu → Mundo de teste (F9 painel). Armadilhas novas: `Object._set` é nome reservado em GDScript (por isso `WorldGen._write`); fora da árvore
(testes) `global_position`/`cam` não existem: as funções que os testes chamam usam `position` e recebem a direção como parâmetro (`cast(d, aim)`, `use_hook(aim)`, `find_target`);
`add_child` de uma cena dentro do `_init` do teste não roda `_ready` (a cena de integração troca de fase em `integration()`); `pkill -f godot` mata o próprio shell da ferramenta.

