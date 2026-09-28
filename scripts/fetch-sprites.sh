#!/usr/bin/env bash
# Baixa os sprites citados em "wiki" nos data/*/textures.json para assets/wiki/ (fora do git; uso pessoal).
# Idempotente: só baixa o que falta. Sem rede, o jogo usa as texturas procedurais.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/assets/wiki"
mkdir -p "$OUT"
fail=0
while read -r host file url_name; do
	[ -s "$OUT/$file.png" ] && continue
	# Arquivos renomeados na wiki (redirect) não existem em /images/: pergunta a URL real à API.
	url="https://$host/images/$url_name.png"
	curl -fsSLI -o /dev/null "$url" 2>/dev/null || url=$(curl -fsSL "https://$host/api.php?action=query&titles=File:$url_name.png&redirects=1&prop=imageinfo&iiprop=url&format=json&formatversion=2" \
		| python3 -c 'import sys,json; print(json.load(sys.stdin)["query"]["pages"][0]["imageinfo"][0]["url"])' 2>/dev/null || echo "$url")
	if curl -fsSL -o "$OUT/$file.png.tmp" "$url"; then
		mv "$OUT/$file.png.tmp" "$OUT/$file.png"
	else
		rm -f "$OUT/$file.png.tmp"; echo "falhou: $file"; fail=1
	fi
done < <(python3 - "$ROOT" <<'PY'
import json, sys, glob, os, urllib.parse
hosts = {"base": "terraria.wiki.gg", "calamity": "calamitymod.wiki.gg"}
for path in sorted(glob.glob(os.path.join(sys.argv[1], "data", "*", "textures.json"))):
    host = hosts.get(os.path.basename(os.path.dirname(path)), "terraria.wiki.gg")
    for spec in json.load(open(path)).values():
        if "wiki" in spec:
            print(host, spec["wiki"], urllib.parse.quote(spec["wiki"]))
PY
)
echo "sprites em $OUT ($(ls "$OUT" | wc -l) arquivos)"
exit $fail
