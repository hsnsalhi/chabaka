#!/usr/bin/env python3
"""Cherche des patterns chabaka SANS cases absentes (R5 strict PO 2026-05-11).
Toute case est soit CC ('C') soit LC ('L'). (0,0) toujours CC.

Contraintes adoucies par rapport à search_scattered_patterns.py :
- R4 strict abandonné : les runs sans CC prédécesseur sont acceptés
  (correspondent aux mots "edge-starting" que le joueur déduit par
  intersection, comme dans les vraies grilles Abou Salma).
- Toute LC doit être dans AU MOINS un run ≥2 (sinon orpheline).
- Toute CC doit héberger au moins un slot (run ≥2 commençant après elle).

Score : minimiser CC, maximiser dispersion.
"""

from __future__ import annotations

import argparse
import random
import sys
from copy import deepcopy

# ---------------------------------------------------------------------------
# Runs detection (réutilisé de generate_patterns mais sans B)
# ---------------------------------------------------------------------------

def runs_horizontal(grid):
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

# ---------------------------------------------------------------------------
# Validation R5-strict : que C ou L, (0,0) = C
# ---------------------------------------------------------------------------

def is_valid(grid):
    rows = len(grid)
    cols = len(grid[0])

    # (0,0) doit être C
    if grid[0][0] != "C":
        return False

    # Toute case = C ou L (pas de '.')
    for row in grid:
        for c in row:
            if c not in ("C", "L"):
                return False

    # Toute L doit être dans un run ≥2 (H ou V).
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

    # Toute C doit héberger un slot (= run ≥2 commençant juste après).
    hosts_slot = [[False] * cols for _ in range(rows)]
    for r, c0, length in runs_horizontal(grid):
        if length >= 2 and c0 >= 1 and grid[r][c0 - 1] == "C":
            hosts_slot[r][c0 - 1] = True
    for r0, c, length in runs_vertical(grid):
        if length >= 2 and r0 >= 1 and grid[r0 - 1][c] == "C":
            hosts_slot[r0 - 1][c] = True
    for r in range(rows):
        for c in range(cols):
            if grid[r][c] == "C" and not hosts_slot[r][c]:
                return False

    return True

# ---------------------------------------------------------------------------
# Score
# ---------------------------------------------------------------------------

def cc_count(grid):
    return sum(1 for row in grid for c in row if c == "C")

def dispersion_score(grid):
    rows = len(grid)
    cols = len(grid[0])
    score = 0
    ccs = [(r, c) for r in range(rows) for c in range(cols) if grid[r][c] == "C"]
    for r, c in ccs:
        score -= sum(
            1 for r2, c2 in ccs
            if (r, c) != (r2, c2) and abs(r - r2) + abs(c - c2) <= 2
        )
    return score

def run_lengths(grid):
    lens = []
    for r, c0, length in runs_horizontal(grid):
        if length >= 2:
            lens.append(length)
    for r0, c, length in runs_vertical(grid):
        if length >= 2:
            lens.append(length)
    return lens

def edge_run_count(grid):
    """Compte les runs ≥2 SANS CC prédécesseur (= mots non-cluéd, déductibles
    uniquement par intersection). Idéal : 0 ou peu."""
    rows = len(grid)
    cols = len(grid[0])
    count = 0
    for r, c0, length in runs_horizontal(grid):
        if length >= 2:
            if c0 == 0 or grid[r][c0 - 1] != "C":
                count += 1
    for r0, c, length in runs_vertical(grid):
        if length >= 2:
            if r0 == 0 or grid[r0 - 1][c] != "C":
                count += 1
    return count

def composite_score(grid):
    cc = cc_count(grid)
    disp = dispersion_score(grid)
    lens = run_lengths(grid)
    # Penalise les slots longs ; valorise les slots courts (3-4).
    short_bonus = sum(1 for l in lens if 3 <= l <= 4)
    long_penalty = sum(max(0, l - 5) ** 2 for l in lens)
    edge = edge_run_count(grid)
    # Sweet spot : ~22 CCs, slots majoritairement 3-4 lettres, peu d'edge runs.
    return -1 * cc + 0.3 * disp + 0.5 * short_bonus - 3 * long_penalty - 5 * edge

# ---------------------------------------------------------------------------
# Initial pattern : tous C dans row 0, puis L partout (forcément valide ? non)
# ---------------------------------------------------------------------------

def initial_pattern(n=8):
    """Patron initial : row 0 = C * n, rows 1+ = L * n. (0,0) = C ✓."""
    grid = [["C"] * n] + [["L"] * n for _ in range(n - 1)]
    # Check validity. Si invalide, on essaie d'autres init.
    return grid

# ---------------------------------------------------------------------------
# Simulated annealing
# ---------------------------------------------------------------------------

def random_flip(grid, rng):
    """Voisin : change 1 cellule C↔L (sauf (0,0) qui reste C)."""
    new = deepcopy(grid)
    rows = len(new)
    cols = len(new[0])
    while True:
        r, c = rng.randint(0, rows - 1), rng.randint(0, cols - 1)
        if (r, c) == (0, 0):
            continue
        new[r][c] = "L" if new[r][c] == "C" else "C"
        return new

def anneal(initial, rng, iterations=10000):
    current = initial
    best = deepcopy(current)
    best_valid = is_valid(best)
    best_score = composite_score(best) if best_valid else -10**6

    for i in range(iterations):
        candidate = random_flip(current, rng)
        if not is_valid(candidate):
            continue
        score = composite_score(candidate)
        if score > best_score:
            best = deepcopy(candidate)
            best_score = score
            best_valid = True
            current = candidate
        elif rng.random() < 0.05:  # exploration légère
            current = candidate

    return best, best_score, best_valid

# ---------------------------------------------------------------------------
# Sortie format Dart
# ---------------------------------------------------------------------------

def emit_dart(grid):
    rows = len(grid)
    cols = len(grid[0])
    cc = cc_count(grid)
    visual = " / ".join("".join(row).replace("L", "_") for row in grid)
    lines = []
    lines.append(f"  // {rows}×{cols} R5-strict (no absent) — CC={cc}, ratio={cc/(rows*cols):.0%}")
    lines.append(f"  // Visual: {visual}")
    lines.append(f"  _Pattern(rows: {rows}, cols: {cols}, kinds: [")
    for row in grid:
        tokens = []
        for ch in row:
            tokens.append("CellKind.clue" if ch == "C" else "CellKind.letter")
        lines.append(f"    {', '.join(tokens)}, // {''.join(row)}")
    lines.append("  ]),")
    return "\n".join(lines)

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--n', type=int, default=8)
    ap.add_argument('--seeds', type=int, default=20)
    ap.add_argument('--iters', type=int, default=10000)
    ap.add_argument('--top', type=int, default=5)
    args = ap.parse_args()

    initial = initial_pattern(args.n)
    if not is_valid(initial):
        # On essaie de partir d'un meilleur initial : alternance plus dense.
        n = args.n
        initial = [["L"] * n for _ in range(n)]
        initial[0][0] = "C"
        for c in range(2, n, 2):
            initial[0][c] = "C"
        for r in range(2, n, 2):
            initial[r][0] = "C"
        print(f"  initial valide ? {is_valid(initial)}", file=sys.stderr)

    found = []
    for seed in range(args.seeds):
        rng = random.Random(seed)
        pattern, score, valid = anneal(initial, rng, args.iters)
        if valid:
            found.append((score, pattern))
            cc = cc_count(pattern)
            print(f"  seed={seed:2d} valid : CC={cc} score={score:.2f}", file=sys.stderr)
        else:
            print(f"  seed={seed:2d} INVALID", file=sys.stderr)

    if not found:
        print("ÉCHEC : aucun pattern valide trouvé", file=sys.stderr)
        return 1

    found.sort(key=lambda x: -x[0])
    print()
    for score, pattern in found[:args.top]:
        print(emit_dart(pattern))
    return 0

if __name__ == '__main__':
    sys.exit(main())
