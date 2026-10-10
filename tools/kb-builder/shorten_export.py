#!/usr/bin/env python3
"""Exporte les indices trop longs du seed en lots à raccourcir.

Usage : python3 shorten_export.py OUT_DIR [--max-words 2] [--chunk 450]
Produit OUT_DIR/chunk_NN.csv avec : line_no,word_display,category,clue_text
(line_no = numéro de ligne dans seed/chabaka_seed.csv, 1 = en-tête).
"""
import csv, sys, argparse
from pathlib import Path
ROOT = Path(__file__).resolve().parent
SEED = ROOT / "seed" / "chabaka_seed.csv"

def main():
    ap = argparse.ArgumentParser(); ap.add_argument("out"); ap.add_argument("--max-words", type=int, default=2); ap.add_argument("--chunk", type=int, default=450)
    a = ap.parse_args(); out = Path(a.out); out.mkdir(parents=True, exist_ok=True)
    rows = []
    with open(SEED, encoding="utf-8", newline="") as fh:
        r = csv.reader(fh); next(r)
        for i, row in enumerate(r, start=2):
            if len(row) < 3: continue
            if len(row[2].split()) > a.max_words:
                rows.append((i, row[0], row[1], row[2]))
    # Regroupe par catégorie pour que chaque agent travaille un vocabulaire cohérent.
    rows.sort(key=lambda t: (t[2], t[0]))
    for n, k in enumerate(range(0, len(rows), a.chunk), start=1):
        with open(out / f"chunk_{n:02d}.csv", "w", encoding="utf-8", newline="") as fh:
            w = csv.writer(fh); w.writerow(["line_no", "word_display", "category", "clue_text"]); w.writerows(rows[k:k + a.chunk])
    print(f"{len(rows)} indices > {a.max_words} mots, {n} lots dans {out}")

if __name__ == "__main__":
    main()
