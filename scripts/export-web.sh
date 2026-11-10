#!/usr/bin/env bash
# Exporta o jogo para o browser em build/web/ (fora do git). Uso: scripts/export-web.sh && scripts/serve-web.py
# Baixa só os templates Web do Godot (do .tpz de 1,2 GB lê apenas ~20 MB, por Range), roda update.sh (sprites, modelos) e exporta.
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION=4.7.2.stable
T="${XDG_DATA_HOME:-$HOME/.local/share}/godot/export_templates/$VERSION"
if [ ! -f "$T/web_release.zip" ]; then
	mkdir -p "$T"
	T="$T" python3 -I - <<'PY'
import urllib.request, zipfile, io, os
U = "https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_export_templates.tpz"
class R(io.RawIOBase):
    def __init__(s):
        r = urllib.request.urlopen(urllib.request.Request(U, method="HEAD")); s.n = int(r.headers["Content-Length"]); s.u = r.geturl(); s.pos = 0
    def seekable(s): return True
    def readable(s): return True
    def tell(s): return s.pos
    def seek(s, o, w=0): s.pos = {0: o, 1: s.pos + o, 2: s.n + o}[w]; return s.pos
    def readinto(s, b):
        n = min(len(b), s.n - s.pos)
        if n <= 0: return 0
        d = urllib.request.urlopen(urllib.request.Request(s.u, headers={"Range": "bytes=%d-%d" % (s.pos, s.pos + n - 1)})).read()
        b[:len(d)] = d; s.pos += len(d); return len(d)
z = zipfile.ZipFile(io.BufferedReader(R(), 1 << 20))
for f in ["version.txt", "web_release.zip", "web_debug.zip"]:
    open(os.path.join(os.environ["T"], f), "wb").write(z.read("templates/" + f))
PY
fi
scripts/update.sh
rm -rf build/web && mkdir -p build/web
# assets/ tem .gdignore (o editor não importa sprites nem modelos); o export também o ignora. Aqui o tiramos e marcamos png/glb com o
# importador "keep" (vai como está, o jogo lê os bytes com FileAccess); no fim tudo volta ao que era, mesmo com erro.
touch build/.gdignore   # o editor não varre build/
mv assets/.gdignore build/.gdignore.assets
trap 'mv build/.gdignore.assets assets/.gdignore; find assets -name "*.import" -delete' EXIT
find assets \( -name "*.png" -o -name "*.glb" \) | while read -r f; do printf '[remap]\n\nimporter="keep"\n' > "$f.import"; done
.tools/godot --headless --import >/dev/null 2>&1
.tools/godot --headless --export-release Web build/web/index.html 2>&1 | grep -vE "^\s*$|Storing File" | tail -15
[ -f build/web/index.pck ] && echo "ok: build/web/ ($(du -sh build/web | cut -f1)). Servir: scripts/serve-web.py" || { echo "ERRO: export falhou"; exit 1; }
