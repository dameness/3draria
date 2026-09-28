#!/usr/bin/env bash
# Baixa os sprites citados em "wiki" nos data/*/textures.json para assets/wiki/ (fora do git; uso pessoal).
# Idempotente: só baixa o que falta, então é só rodar de novo se algum falhar. Sem os sprites o jogo funciona
# igual, com as texturas procedurais.
# A wiki limita o ritmo (HTTP 429): baixa um arquivo por vez, com pausa, obedecendo o Retry-After; se ela insistir,
# para com um aviso de quanto esperar (o que já baixou fica).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/assets/wiki"
mkdir -p "$OUT"
python3 - "$ROOT" "$OUT" <<'PY'
import glob, json, os, sys, time, urllib.error, urllib.parse, urllib.request

root, out = sys.argv[1:3]
HOSTS = {"base": "terraria.wiki.gg", "calamity": "calamitymod.wiki.gg"}
UA = "3draria-sprites/1.0 (uso pessoal)"
PAUSE = 0.7     # segundos entre arquivos
GIVE_UP = 3     # falhas seguidas (já depois de esperar) antes de parar


def get(url):
    """Bytes da URL, ou None se não existe (404). Em 429/5xx espera (Retry-After, senão 5, 10, 20... s) e tenta de novo."""
    for attempt in range(6):
        try:
            with urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": UA}), timeout=60) as r:
                return r.read()
        except urllib.error.HTTPError as e:
            if e.code == 404:
                return None
            if e.code not in (429, 500, 502, 503, 504):
                raise
            wait = min(90, int(e.headers.get("Retry-After") or 5 * 2 ** attempt))
        except (urllib.error.URLError, TimeoutError):
            wait = 5
        print(f"  esperando {wait}s (tentativa {attempt + 1}/6)", flush=True)
        time.sleep(wait)
    raise RuntimeError("a wiki não respondeu")


def real_url(host, name):
    """Arquivo renomeado na wiki (redirect) não existe em /images/: pergunta a URL real à API."""
    q = urllib.parse.urlencode({"action": "query", "titles": f"File:{name}.png", "redirects": 1, "prop": "imageinfo",
                                "iiprop": "url", "format": "json", "formatversion": 2})
    data = get(f"https://{host}/api.php?{q}")
    try:
        return json.loads(data)["query"]["pages"][0]["imageinfo"][0]["url"]
    except (TypeError, KeyError, IndexError, ValueError):
        return None


todo = {}
for path in sorted(glob.glob(os.path.join(root, "data", "*", "textures.json"))):
    host = HOSTS.get(os.path.basename(os.path.dirname(path)), "terraria.wiki.gg")
    for spec in json.load(open(path)).values():
        name = spec.get("wiki")
        dest = os.path.join(out, str(name) + ".png")
        if name and not (os.path.exists(dest) and os.path.getsize(dest) > 0):
            todo[name] = host

failed = []
streak = 0
for name, host in todo.items():
    dest = os.path.join(out, name + ".png")
    try:
        data = get(f"https://{host}/images/{urllib.parse.quote(name)}.png")
        if data is None:
            url = real_url(host, name)
            data = get(url) if url else None
        if data is None:
            raise RuntimeError("não existe na wiki")
        with open(dest + ".tmp", "wb") as f:
            f.write(data)
        os.replace(dest + ".tmp", dest)
        streak = 0
    except Exception as e:
        print(f"falhou: {name} ({e})", flush=True)
        failed.append(name)
        streak += 1
        if streak >= GIVE_UP:
            print("A wiki está limitando o ritmo. Espere uns 10 minutos e rode de novo: o que já baixou fica.")
            break
    time.sleep(PAUSE)
print(f"sprites em {out} ({len(os.listdir(out))} arquivos)" + (f"; faltam {len(failed)}" if failed else ""))
sys.exit(1 if failed else 0)
PY
