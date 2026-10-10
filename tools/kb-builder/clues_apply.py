#!/usr/bin/env python3
"""Applique des corrections d'indices au seed et aux fichiers enrich.

Usage : python3 clues_apply.py FIX.csv [FIX2.csv ...] [--check]
FIX.csv : file,line_no,new_clue
  - file : chemin relatif à tools/kb-builder (ex. seed/chabaka_seed.csv)
  - new_clue : nouvel indice (≤ 3 mots, arabe, sans le mot), ou __SUPPRIMER__
    pour retirer l'entrée entière.
--check : vérifie seulement, n'écrit rien.
"""
import csv, sys, argparse
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
from build_kb import normalize_r3, validate_arabic  # noqa: E402
ROOT = Path(__file__).resolve().parent
DELETE = "__SUPPRIMER__"

def main():
    ap = argparse.ArgumentParser(); ap.add_argument("fixes", nargs="+"); ap.add_argument("--check", action="store_true")
    a = ap.parse_args()
    files, errs, applied, deleted = {}, [], 0, 0
    def load(rel):
        if rel not in files:
            p = ROOT / rel
            if not p.is_file() or ".." in rel: return None
            with open(p, encoding="utf-8", newline="") as fh: files[rel] = list(csv.reader(fh))
        return files[rel]
    todel = set()
    for f in a.fixes:
        with open(f, encoding="utf-8", newline="") as fh:
            r = csv.reader(fh); head = next(r, None)
            if head is None or [c.strip() for c in head[:3]] != ["file", "line_no", "new_clue"]:
                errs.append(f"{f}: en-tête attendu file,line_no,new_clue"); continue
            for i, fx in enumerate(r, start=2):
                if not fx or not fx[0].strip(): continue
                if len(fx) < 3: errs.append(f"{f} L{i}: 3 colonnes attendues"); continue
                rel = fx[0].strip(); rows = load(rel)
                if rows is None: errs.append(f"{f} L{i}: fichier inconnu « {rel} »"); continue
                try: ln = int(fx[1])
                except ValueError: errs.append(f"{f} L{i}: line_no invalide « {fx[1]} »"); continue
                new = fx[2].strip()
                if not (2 <= ln <= len(rows)): errs.append(f"{f} L{i}: line_no {ln} hors de {rel}"); continue
                word = rows[ln - 1][0]
                if new == DELETE:
                    todel.add((rel, ln)); deleted += 1; continue
                if not new: errs.append(f"{f} L{i}: indice vide pour « {word} »"); continue
                if len(new.split()) > 3: errs.append(f"{f} L{i}: > 3 mots pour « {word} » : « {new} »"); continue
                bad = validate_arabic(new.replace("...", "").replace("…", ""))
                if bad: errs.append(f"{f} L{i}: « {new} » : {bad}"); continue
                nw = normalize_r3(word)
                if len(nw) >= 3 and nw in normalize_r3(new): errs.append(f"{f} L{i}: l'indice contient le mot « {word} » : « {new} »"); continue
                if not a.check: rows[ln - 1][2] = new
                applied += 1
    print(f"{applied} indices {'vérifiés' if a.check else 'appliqués'}, {deleted} suppressions, {len(errs)} erreurs")
    for e in errs[:100]: print("   ERREUR " + e)
    if errs: return 1
    if not a.check:
        for rel, rows in files.items():
            kept = [row for k, row in enumerate(rows, start=1) if (rel, k) not in todel]
            with open(ROOT / rel, "w", encoding="utf-8", newline="") as fh:
                csv.writer(fh, lineterminator="\n").writerows(kept)
    return 0

if __name__ == "__main__":
    sys.exit(main())
