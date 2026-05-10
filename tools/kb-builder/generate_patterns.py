#!/usr/bin/env python3
"""
Génère des patrons de grilles مسهمة strictement R4-conformes, avec 3 états :

  • C = ClueCell (porte 1+ indice → fait démarrer 1+ slot)
  • L = LetterCell (lettre à trouver, doit être dans 1+ slot ≥2)
  • B = Blocker visuel (case "noire" sans indice ni lettre — relaxation R1
    décidée par PO le 2026-05-10, miroir des vraies grilles Abou Salma)

Règles de validation :
  1. Tout run horizontal de ≥2 L consécutives doit avoir C immédiatement à
     gauche (jamais en col 0, jamais après un B).
  2. Tout run vertical de ≥2 L consécutives doit avoir C immédiatement
     au-dessus.
  3. Toute L doit appartenir à au moins un slot ≥2 (H ou V).
  4. Toute C doit héberger au moins un slot.
  5. Les B n'ont pas de contrainte propre — ils servent juste à briser des runs.

Usage :
    python3 generate_patterns.py [--n 5] [--max 20] [--max-blockers 4] [--out -]
"""

from __future__ import annotations

import argparse
import sys
from itertools import product

# ---------------------------------------------------------------------------
# Validation
# ---------------------------------------------------------------------------

def runs_horizontal(grid):
    """Yield (row, col_start, length) for each maximal H run of L cells."""
    rows = len(grid)
    cols = len(grid[0])
    for r in range(rows):
        c = 0
        while c < cols:
            if grid[r][c] == "L":
                start = c
                while c < cols and grid[r][c] == "L":
                    c += 1
                yield (r, start, c - start)
            else:
                c += 1

def runs_vertical(grid):
    rows = len(grid)
    cols = len(grid[0])
    for c in range(cols):
        r = 0
        while r < rows:
            if grid[r][c] == "L":
                start = r
                while r < rows and grid[r][c] == "L":
                    r += 1
                yield (start, c, r - start)
            else:
                r += 1

def is_valid(grid):
    rows = len(grid)
    cols = len(grid[0])

    # 1. Run H ≥2 doit avoir C juste à gauche (pas de col 0, pas après B).
    for r, c0, length in runs_horizontal(grid):
        if length < 2:
            continue
        if c0 == 0:
            return False
        # Prédécesseur doit être C (pas B)
        if grid[r][c0 - 1] != "C":
            return False

    # 2. Run V ≥2 doit avoir C juste au-dessus.
    for r0, c, length in runs_vertical(grid):
        if length < 2:
            continue
        if r0 == 0:
            return False
        if grid[r0 - 1][c] != "C":
            return False

    # 3. Toute L doit appartenir à au moins un slot ≥2.
    in_slot = [[False] * cols for _ in range(rows)]
    for r, c0, length in runs_horizontal(grid):
        if length >= 2:
            for i in range(length):
                in_slot[r][c0 + i] = True
    for r0, c, length in runs_vertical(grid):
        if length >= 2:
            for i in range(length):
                in_slot[r0 + i][c] = True
    for r in range(rows):
        for c in range(cols):
            if grid[r][c] == "L" and not in_slot[r][c]:
                return False

    # 4. Toute C doit héberger au moins un slot ≥2.
    hosts_slot = [[False] * cols for _ in range(rows)]
    for r, c0, length in runs_horizontal(grid):
        if length >= 2 and c0 >= 1:
            if grid[r][c0 - 1] == "C":
                hosts_slot[r][c0 - 1] = True
    for r0, c, length in runs_vertical(grid):
        if length >= 2 and r0 >= 1:
            if grid[r0 - 1][c] == "C":
                hosts_slot[r0 - 1][c] = True
    for r in range(rows):
        for c in range(cols):
            if grid[r][c] == "C" and not hosts_slot[r][c]:
                return False

    return True

# ---------------------------------------------------------------------------
# Génération par DFS avec pruning
# ---------------------------------------------------------------------------

def search(n, max_results=20, max_blockers=None):
    """Cherche jusqu'à max_results patrons n×n valides, distincts.

    Si [max_blockers] est défini, limite le nombre de B dans le patron pour
    favoriser les grilles plus "denses" (préférables côté UX).
    """
    found = []
    grid = [["?"] * n for _ in range(n)]

    def signature(g):
        return "".join("".join(row) for row in g)

    seen = set()

    def dfs(idx, n_blockers):
        if len(found) >= max_results:
            return
        if max_blockers is not None and n_blockers > max_blockers:
            return
        if idx == n * n:
            if is_valid(grid):
                sig = signature(grid)
                if sig not in seen:
                    seen.add(sig)
                    found.append([row[:] for row in grid])
            return

        r, c = idx // n, idx % n
        # Heuristique : essaie L > C > B (favorise grilles denses)
        for choice in ("L", "C", "B"):
            grid[r][c] = choice
            dfs(idx + 1, n_blockers + (1 if choice == "B" else 0))
            grid[r][c] = "?"

    dfs(0, 0)
    return found

# ---------------------------------------------------------------------------
# Sortie format Dart
# ---------------------------------------------------------------------------

def emit_dart(patterns, n):
    """Émet une liste de _Pattern Dart const utilisant l'enum CellKind."""
    lines = [f"const _patterns{n}x{n} = <_Pattern>["]
    for i, grid in enumerate(patterns):
        visual = " / ".join("".join(row).replace("L", ".") for row in grid)
        lines.append(f"  // Patron {i} : {visual}")
        lines.append(f"  _Pattern(rows: {n}, cols: {n}, kinds: [")
        for row in grid:
            tokens = []
            for ch in row:
                if ch == "C":
                    tokens.append("CellKind.clue")
                elif ch == "L":
                    tokens.append("CellKind.letter")
                else:  # B
                    tokens.append("CellKind.blocker")
            mask_row = ", ".join(tokens)
            lines.append(f"    {mask_row}, // {''.join(row)}")
        lines.append("  ]),")
    lines.append("];")
    return "\n".join(lines)

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--n", type=int, default=5)
    ap.add_argument("--max", type=int, default=12)
    ap.add_argument("--max-blockers", type=int, default=None,
                    help="limite le nb de B (favorise grilles denses)")
    ap.add_argument("--out", default="-")
    args = ap.parse_args()

    print(f"Recherche de patrons {args.n}×{args.n} valides (max {args.max})...",
          file=sys.stderr)
    patterns = search(args.n, args.max, max_blockers=args.max_blockers)
    print(f"  → {len(patterns)} trouvés", file=sys.stderr)

    if not patterns:
        print("  ÉCHEC : aucun patron valide", file=sys.stderr)
        return 1

    out = emit_dart(patterns, args.n)
    if args.out == "-":
        print(out)
    else:
        with open(args.out, "w", encoding="utf-8") as f:
            f.write(out)
        print(f"  écrit dans {args.out}", file=sys.stderr)
    return 0

if __name__ == "__main__":
    sys.exit(main())
