#!/usr/bin/env python3
"""Choisit la prochaine grille de la banque (docs/facebook/grids/) pour la page.

Règles (ligne éditoriale §6) : jamais une grille déjà publiée, au plus un mot de
4 lettres ou plus déjà vu dans les 30 dernières grilles publiées (les mots de
2-3 lettres, très fréquents, ne comptent pas), aucun mot de
docs/facebook/exclusions.txt, aucun indice de plus de 28 caractères.

  pick_grid.py --kind small|big            → affiche le chemin JSON choisi
  pick_grid.py --kind small --mark PATH    → marque PATH comme publiée (état)
"""
import argparse
import json
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
BANK = ROOT / "docs" / "facebook" / "grids"
STATE = ROOT / "docs" / "facebook" / "state.json"
EXCL = ROOT / "docs" / "facebook" / "exclusions.txt"
MAX_CLUE = 28
WINDOW = 30


def load_state():
    if STATE.exists():
        return json.loads(STATE.read_text(encoding="utf-8"))
    return {"published": [], "next_number": 1}


def words_of(path):
    g = json.loads(path.read_text(encoding="utf-8"))
    words, clues = set(), []
    for row in g["cells"]:
        for cell in row:
            for cl in cell.get("clues", []) or []:
                words.add(cl["solution"])
                clues.append(cl["text"])
    return words, clues


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--kind", choices=["small", "big"], required=True)
    p.add_argument("--mark")
    a = p.parse_args()
    state = load_state()

    if a.mark:
        rel = str(pathlib.Path(a.mark).resolve().relative_to(ROOT))
        words, _ = words_of(ROOT / rel)
        state["published"].append({"file": rel, "number": state["next_number"], "words": sorted(words)})
        state["next_number"] += 1
        STATE.write_text(json.dumps(state, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(f"marquée : {rel} (numéro {state['next_number'] - 1})")
        return

    excluded = {l.strip() for l in EXCL.read_text(encoding="utf-8").splitlines() if l.strip() and not l.startswith("#")} if EXCL.exists() else set()
    used_files = {e["file"] for e in state["published"]}
    recent = set()
    for e in state["published"][-WINDOW:]:
        recent.update(w for w in e["words"] if len(w) >= 4)

    prefix = "grid_10x7_" if a.kind == "small" else "grid_13x9_"
    for path in sorted(BANK.glob(prefix + "*.json")):
        rel = str(path.relative_to(ROOT))
        if rel in used_files:
            continue
        words, clues = words_of(path)
        if words & excluded or len(words & recent) > 1:
            continue
        if any(len(c) > MAX_CLUE for c in clues):
            continue
        print(rel)
        return
    sys.exit(f"aucune grille {a.kind} disponible dans la banque : en régénérer")


if __name__ == "__main__":
    main()
