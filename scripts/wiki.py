#!/usr/bin/env python3
"""Consulta dados do Terraria na wiki (tabelas Cargo) para montar os JSON de data/.

Uso:
  scripts/wiki.py items "Copper Pickaxe" "Iron Broadsword"   # dano, use time (frames), knockback, pick, raridade...
  scripts/wiki.py recipes "Copper Pickaxe"                   # estação e ingredientes (versão desktop)
  scripts/wiki.py npcs "Eye of Cthulhu" "Zombie"             # vida, dano, defesa (modo normal), imagem
Saída: JSON. Frames → segundos: /60. Velocidade (px/tick) → blocos/s: *60/16.
"""
import html, json, re, subprocess, sys, urllib.parse

WIKI = "https://terraria.wiki.gg/index.php"


def cargo(table, fields, where):
    q = urllib.parse.urlencode({"title": "Special:CargoExport", "tables": table, "fields": fields,
                                "where": where, "format": "json", "limit": "500"})
    out = subprocess.run(["curl", "-sS", "--retry", "3", f"{WIKI}?{q}"], capture_output=True, text=True, check=True).stdout
    return json.loads(out)


def names_in(field, names):
    return field + " IN (" + ",".join('"' + n.replace('"', '') + '"' for n in names) + ")"


def normal(value):
    """Primeiro número de um campo formatado (modo normal); links [[X|Y]] viram Y."""
    if value is None or isinstance(value, (int, float)):
        return value
    text = re.sub(r"<[^>]+>", " ", html.unescape(str(value)))
    text = re.sub(r"\[\[(?:[^|\]]*\|)?([^\]]*)\]\]", r"\1", text).strip()
    m = re.match(r"\s*(-?[\d.]+)", text)
    return float(m.group(1)) if m and "." in m.group(1) else int(m.group(1)) if m else text


def main():
    kind, names = sys.argv[1], sys.argv[2:]
    if kind == "items":
        rows = cargo("Items", "name,damage,usetime,knockback,pick,axe,hammer,rare,velocity,defense,type", names_in("name", names))
    elif kind == "recipes":
        rows = []
        for r in cargo("Recipes", "result,amount,station,args,version", names_in("result", names)):
            if r["version"] and "desktop" not in r["version"]:
                continue
            ings = {a.split("¦")[0].split("#")[0]: int(a.split("¦")[1]) for a in r["args"].split("^")}
            rows.append({"result": r["result"], "amount": r["amount"], "station": r["station"], "needs": ings})
    elif kind == "npcs":
        rows = []
        where = " OR ".join('name LIKE "%[[' + n + '|%"' for n in names)
        for r in cargo("NPCs", "name,damage,life,defense,knockback,image,npcid", where):
            img = re.search(r"File:([^|\]]+)", html.unescape(r["image"] or ""))
            r = {k: normal(v) for k, v in r.items()}
            r["image"] = img.group(1).replace(" ", "_") if img else None
            if r["name"] in names:
                rows.append(r)
    else:
        sys.exit(__doc__)
    print(json.dumps(rows, indent=1, ensure_ascii=False))


if __name__ == "__main__":
    main()
