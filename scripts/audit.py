#!/usr/bin/env python3
"""Compara data/base/*.json com o snapshot da wiki (data/ref/, veja `scripts/wiki.py dump`).
Uso: scripts/audit.py            # lista divergências; código de saída 1 se houver alguma fora de data/wiki_ok.json
O nome na wiki é o do jogo em title case (Items.title); se diferir, ponha `"wiki": "Nome"` na entrada.
Divergência deliberada: `"wiki_ok": ["campo", ...]` na própria entrada."""
import html, json, os, re, sys
import wiki

DATA = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "data", "base")


def load(name):
    with open(os.path.join(DATA, name + ".json")) as f:
        return json.load(f)


def key(s):
    return re.sub(r"[^a-z0-9]", "", html.unescape(str(s)).lower())


def nums(v):
    """Valores do modo normal de um campo da wiki (podem ser vários: variantes do mesmo NPC, ou bônus de expert)."""
    text = html.unescape(str(v))
    spans = re.findall(r'class="m-(?:normal|all)[^"]*">\s*(-?[\d.]+)', text)
    if spans:
        return [float(x) for x in spans]
    m = re.match(r"\s*(-?[\d.]+)", re.sub(r"<[^>]+>", " ", text))
    return [float(m.group(1))] if m else []


def by_name(rows, field):
    """Índice pelo nome; NPC com nota, 'Nome (Nota)', entra por 'Nome' e por 'Nota' (a wiki põe (Skeletron Head) na nota)."""
    out = {}
    for r in rows:
        text = re.sub(r"\s+", " ", wiki.normal(r[field]) if isinstance(r[field], str) and "[[" in r[field] else html.unescape(str(r[field]))).strip()
        for k in {key(text), key(re.sub(r"\(.*", "", text)), key(re.sub(r".*\(([^)]*)\).*", r"\1", text))}:
            out.setdefault(k, []).append(r)
    return out


def ing(name):
    """Ingrediente: a wiki diz 'Any Wood' / 'Any Stone Block' onde o jogo diz wood / stone."""
    return re.sub(r"^any|block$", "", key(name))


def check(kind, entry, rows, pairs, out):
    """pairs: (campo do jogo, valor do jogo, campo da wiki, tolerância). OK se alguma linha da wiki concordar."""
    if not rows:
        out.append(f"{kind} {entry['name']}: não achei na wiki (ponha \"wiki\": \"Nome\")")
        return
    for field, mine, wfield, tol in pairs:
        if mine is None or field in entry.get("wiki_ok", []):
            continue
        theirs = [t for r in rows for t in nums(r.get(wfield))]
        if theirs and not any(abs(t - mine) <= tol for t in theirs):
            out.append(f"{kind} {entry['name']}.{field}: jogo {mine}, wiki {sorted(set(theirs))[:8]}")


def main():
    out = []
    W_items, W_npcs = by_name(wiki.items(), "name"), by_name(wiki.local("npcs"), "name")
    for e in load("items"):
        rows = W_items.get(key(e.get("wiki") or e["name"]))
        if not ("damage" in e or "pick_power" in e or "rarity" in e):
            continue
        ut = e.get("use_time")
        check("item", e, rows, [("damage", e.get("damage"), "damage", 0), ("use_time", ut and ut * 60, "usetime", 1),
                                ("pick_power", e.get("pick_power"), "pick", 0), ("knockback", e.get("knockback"), "knockback", 0.05),
                                ("rarity", e.get("rarity"), "rare", 0)], out)
    for e in load("blocks"):   # raridade do bloco-item: a lava queima os de raridade 0 (sem linha na wiki, pula: os blocos comuns são todos 0)
        rows = W_items.get(key(e.get("wiki") or e["name"]))
        if rows and e.get("item", True) and e.get("breakable", True) and (e.get("solid", True) or e.get("shape")):
            check("bloco", e, rows, [("rarity", e.get("rarity", 0), "rare", 0)], out)
    for e in load("enemies"):
        check("inimigo", e, W_npcs.get(key(e.get("wiki") or e["name"])),
              [(f, e.get(f), f, 0) for f in ("life", "damage", "defense")], out)
    W_rec = by_name(wiki.recipes(), "result")
    for e in load("recipes"):
        rows = W_rec.get(key(e.get("wiki") or e["result"]), [])
        mine = {ing(k): v for k, v in e["needs"].items()}
        st = key(e.get("station", "by hand"))
        if not any({ing(k): v for k, v in r["needs"].items()} == mine and r["amount"] == e.get("count", 1) and
                   key(r["station"]).endswith(st) for r in rows):
            if "recipe" not in e.get("wiki_ok", []):
                out.append(f"receita {e['result']}: {e['needs']} x{e.get('count', 1)} @{e.get('station')}; wiki: " +
                           ("; ".join(f"{r['needs']} x{r['amount']} @{r['station']}" for r in rows) or "sem receita (ponha \"wiki\": \"Nome\")"))
    print("\n".join(out) or "tudo confere com a wiki")
    print(f"{len(out)} divergências", file=sys.stderr)
    sys.exit(1 if out else 0)


if __name__ == "__main__":
    main()
