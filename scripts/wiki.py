#!/usr/bin/env python3
"""Consulta dados do Terraria na wiki (tabelas Cargo) para montar os JSON de data/.
As consultas leem o snapshot data/ref/*.json (sem rede); `dump` o refaz baixando as tabelas inteiras.

Uso:
  scripts/wiki.py dump                                       # baixa Items, Recipes e NPCs para data/ref/ (a cada versão nova da wiki)
  scripts/wiki.py items "Copper Pickaxe" "Iron Broadsword"   # dano, use time (frames), knockback, pick, raridade...
  scripts/wiki.py recipes "Copper Pickaxe"                   # estação e ingredientes (versão desktop)
  scripts/wiki.py npcs "Eye of Cthulhu" "Zombie"             # vida, dano, defesa (modo normal), imagem
Saída: JSON. Frames → segundos: /60. Velocidade (px/tick) → blocos/s: *60/16.
"""
import html, json, os, re, subprocess, sys, urllib.parse

WIKI = "https://terraria.wiki.gg/index.php"
REF = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "data", "ref")
TABLES = {"items": ("Items", "name,damage,usetime,knockback,pick,axe,hammer,rare,velocity,defense,type"),
          "recipes": ("Recipes", "result,amount,station,args,version"),
          "npcs": ("NPCs", "name,damage,life,defense,knockback,image,npcid")}


def cargo(table, fields, offset=0):
    q = urllib.parse.urlencode({"title": "Special:CargoExport", "tables": table, "fields": fields,
                                "format": "json", "limit": "5000", "offset": offset})
    # A wiki responde 429 se for rápido demais: --retry-all-errors espera (Retry-After) e tenta de novo.
    out = subprocess.run(["curl", "-sS", "--retry", "6", "--retry-delay", "4", "--retry-all-errors", f"{WIKI}?{q}"],
                         capture_output=True, text=True, check=True).stdout
    return json.loads(out)


def dump():
    os.makedirs(REF, exist_ok=True)
    for key, (table, fields) in TABLES.items():
        rows = []
        while True:
            page = cargo(table, fields, len(rows))
            rows += page
            if len(page) < 5000:
                break
        with open(os.path.join(REF, key + ".json"), "w") as f:
            json.dump(rows, f, ensure_ascii=False, separators=(",", ":"))
        print(key, len(rows), file=sys.stderr)


def local(key):
    path = os.path.join(REF, key + ".json")
    if not os.path.exists(path):
        sys.exit("sem data/ref/" + key + ".json: rode `scripts/wiki.py dump`")
    with open(path) as f:
        return json.load(f)


def normal(value):
    """Primeiro número de um campo formatado (modo normal); links [[X|Y]] viram Y."""
    if value is None or isinstance(value, (int, float)):
        return value
    text = re.sub(r"<[^>]+>", " ", html.unescape(str(value)))
    text = re.sub(r"\[\[(?:[^|\]]*\|)?([^\]]*)\]\]", r"\1", text).strip()
    m = re.match(r"\s*(-?[\d.]+)", text)
    return float(m.group(1)) if m and "." in m.group(1) else int(m.group(1)) if m else text


def items():
    return local("items")


def recipes():
    rows = []
    for r in local("recipes"):
        if r["version"] and "desktop" not in r["version"]:
            continue
        ings = {a.split("¦")[0].split("#")[0]: int(a.split("¦")[1]) for a in r["args"].split("^")}
        rows.append({"result": r["result"], "amount": r["amount"], "station": r["station"], "needs": ings})
    return rows


def npcs():
    rows = []
    for r in local("npcs"):
        img = re.search(r"File:([^|\]]+)", html.unescape(r["image"] or ""))
        r = {k: normal(v) for k, v in r.items()}
        r["image"] = img.group(1).replace(" ", "_") if img else None
        rows.append(r)
    return rows


def main():
    kind, names = sys.argv[1], sys.argv[2:]
    if kind == "dump":
        return dump()
    if kind not in ("items", "recipes", "npcs"):
        sys.exit(__doc__)
    key = "result" if kind == "recipes" else "name"
    rows = [r for r in globals()[kind]() if r[key] in names]
    print(json.dumps(rows, indent=1, ensure_ascii=False))


if __name__ == "__main__":
    main()
