#!/usr/bin/env python3
"""Applique des indices raccourcis au seed.

Usage : python3 shorten_apply.py FIX.csv [FIX2.csv ...] [--check]
FIX.csv : line_no,new_clue  (line_no = numéro de ligne dans seed/chabaka_seed.csv)
Règles : nouvel indice non vide, ≤ 3 mots, caractères arabes, ne contient pas le mot.
--check : vérifie seulement, n'écrit rien. Sans --check : réécrit le seed en place.
"""
import csv, sys, argparse
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
from build_kb import normalize_r3, validate_arabic  # noqa: E402
ROOT = Path(__file__).resolve().parent
SEED = ROOT / "seed" / "chabaka_seed.csv"

def main():
    ap = argparse.ArgumentParser(); ap.add_argument("fixes", nargs="+"); ap.add_argument("--check", action="store_true")
    a = ap.parse_args()
    with open(SEED, encoding="utf-8", newline="") as fh:
        rows = list(csv.reader(fh))
    errs, applied = [], 0
    for f in a.fixes:
        with open(f, encoding="utf-8", newline="") as fh:
            r = csv.reader(fh); head = next(r, None)
            if head is None or [c.strip() for c in head[:2]] != ["line_no", "new_clue"]:
                errs.append(f"{f}: en-tête attendu line_no,new_clue"); continue
            for i, fx in enumerate(r, start=2):
                if not fx or not fx[0].strip(): continue
                if len(fx) < 2: errs.append(f"{f} L{i}: 2 colonnes attendues"); continue
                try: ln = int(fx[0])
                except ValueError: errs.append(f"{f} L{i}: line_no invalide « {fx[0]} »"); continue
                new = fx[1].strip()
                if not (2 <= ln <= len(rows)): errs.append(f"{f} L{i}: line_no {ln} hors du seed"); continue
                word = rows[ln - 1][0]
                if not new: errs.append(f"{f} L{i}: indice vide pour « {word} »"); continue
                if len(new.split()) > 3: errs.append(f"{f} L{i}: > 3 mots pour « {word} » : « {new} »"); continue
                bad = validate_arabic(new.replace("...", "").replace("…", ""))
                if bad: errs.append(f"{f} L{i}: « {new} » : {bad}"); continue
                nw = normalize_r3(word)
                if len(nw) >= 3 and nw in normalize_r3(new): errs.append(f"{f} L{i}: l'indice contient le mot « {word} » : « {new} »"); continue
                if not a.check:
                    rows[ln - 1][2] = new
                applied += 1
    print(f"{applied} indices {'vérifiés' if a.check else 'appliqués'}, {len(errs)} erreurs")
    for e in errs[:100]: print("   ERREUR " + e)
    if errs: return 1
    if not a.check:
        with open(SEED, "w", encoding="utf-8", newline="") as fh:
            csv.writer(fh, lineterminator="\n").writerows(rows)
    return 0

if __name__ == "__main__":
    sys.exit(main())
