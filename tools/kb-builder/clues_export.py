#!/usr/bin/env python3
"""Exporte tous les indices (seed + enrich) en lots pour relecture.

Usage : python3 clues_export.py OUT_DIR [--chunk 1000] [--category CAT ...]
Produit OUT_DIR/chunk_NN.csv avec : file,line_no,word_display,category,clue_text
(file = chemin relatif à tools/kb-builder, line_no = numéro de ligne, 1 = en-tête).
"""
import csv, argparse
from pathlib import Path
ROOT = Path(__file__).resolve().parent
FILES = [ROOT / "seed" / "chabaka_seed.csv"] + sorted((ROOT / "seed" / "enrich").glob("*.csv"))

def main():
    ap = argparse.ArgumentParser(); ap.add_argument("out"); ap.add_argument("--chunk", type=int, default=1000)
    ap.add_argument("--category", nargs="*")
    a = ap.parse_args(); out = Path(a.out); out.mkdir(parents=True, exist_ok=True)
    rows = []
    for f in FILES:
        rel = str(f.relative_to(ROOT))
        with open(f, encoding="utf-8", newline="") as fh:
            r = csv.reader(fh); next(r)
            for i, row in enumerate(r, start=2):
                if len(row) < 3: continue
                if a.category and row[1] not in a.category: continue
                rows.append((rel, i, row[0], row[1], row[2]))
    rows.sort(key=lambda t: (t[3], t[0], t[1]))
    n = 0
    for n, k in enumerate(range(0, len(rows), a.chunk), start=1):
        with open(out / f"chunk_{n:02d}.csv", "w", encoding="utf-8", newline="") as fh:
            w = csv.writer(fh); w.writerow(["file", "line_no", "word_display", "category", "clue_text"]); w.writerows(rows[k:k + a.chunk])
    print(f"{len(rows)} indices, {n} lots dans {out}")

if __name__ == "__main__":
    main()
