#!/usr/bin/env bash
# Ver o jogo sem instalar nada: prints reais + clipes de jogo em previews/ (fora do git; o CI publica no branch "previews" e comenta no PR).
# Uso: scripts/preview.sh            → previews/folha.jpg (8 cenas), previews/cenas/*.jpg, previews/passeio.mp4, previews/noite.mp4
set -euo pipefail
cd "$(dirname "$0")/.."
CENAS="alto arvore_cai deserto_cacto mal neve luzes luz_na_mao gancho"   # nomes de tests/screenshot.gd (nenhum do mundo de teste)
rm -rf previews && mkdir -p previews/cenas
xvfb-run -a -s "-screen 0 1280x720x24" .tools/godot -s tests/screenshot.gd -- $CENAS 2>&1 | grep -E "salvo|SCRIPT ERROR" || true
i=0
for c in $CENAS; do
	i=$((i + 1))
	ffmpeg -loglevel error -y -i "textures/shot_$c.png" -q:v 3 "previews/cenas/$(printf %02d $i)_$c.jpg"
done
ffmpeg -loglevel error -y -pattern_type glob -i 'previews/cenas/*.jpg' -vf "scale=640:-1,tile=4x2" -frames:v 1 -q:v 3 previews/folha.jpg
for clip in passeio noite; do
	scripts/clip.sh "$clip"
	mv "textures/clip_$clip.mp4" "previews/$clip.mp4"
done
echo "pronto: previews/folha.jpg, previews/cenas/, previews/passeio.mp4, previews/noite.mp4"
