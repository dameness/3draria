# 3draria

Jogo voxel 3D com o conteúdo e a progressão do Terraria (Godot 4.7.2, GDScript). Uso pessoal.

## Rodar / atualizar
```sh
git pull                    # a branch que o Claude está usando
scripts/update.sh           # Godot + sprites da wiki (1ª vez ~2 min; depois nada) + cache de classes
.tools/godot                # jogar (ou .tools/godot -e para abrir o editor)
```
Rode `scripts/update.sh` **sempre depois de um `git pull`** (script novo precisa do cache de classes). Sem sprites o jogo
funciona igual (texturas procedurais); se a wiki responder 429, rode de novo mais tarde: continua de onde parou.
Testes: `.tools/godot --headless -s tests/run.gd`. Se um passo mudar a geração do mundo, crie um mundo novo.

Detalhes do projeto em `CLAUDE.md`; roteiro em `docs/ROADMAP.md`; visual em `docs/VISUAL.md`; GUI em `docs/UI.md`.
