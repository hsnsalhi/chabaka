#!/usr/bin/env python3
"""Cherche des patterns chabaka R1+R4 strict avec :
- minimum de ClueCells (CC) — meilleure densité de cellules à jouer
- dispersion aléatoire des CC (pas de symétrie évidente)
- positions absentes seulement où mathématiquement nécessaire

Stratégie : simulated annealing partant d'un pattern valide initial
(tuilage 4×4), puis swaps locaux qui préservent la validité.

Notation interne :
- 'C' = ClueCell
- 'L' = LetterCell
- '.' = position absente (off-grid)
"""

from __future__ import annotations

import argparse
import random
import sys
from copy import deepcopy

from generate_patterns import is_valid  # réutilise la validation R1+R4

# ---------------------------------------------------------------------------
# Patterns initiaux (= tuilage 4×4 que je veux dépasser)
# ---------------------------------------------------------------------------

def tiled_8x8() -> list[list[str]]:
    """Patron tuilé 8×8 (point de départ valide)."""
    grid = [['L'] * 8 for _ in range(8)]
    for r in range(8):
        for c in range(8):
            tr, tc = r % 4, c % 4
            if tr == 0 and tc == 0:
                grid[r][c] = '.'
            elif tr == 0 or tc == 0:
                grid[r][c] = 'C'
    return grid

def must_be_valid(grid: list[list[str]]) -> bool:
    # Réécriture en notation '.'=B pour réutiliser le validateur
    g = [[('B' if c == '.' else c) for c in row] for row in grid]
    return is_valid(g)

# ---------------------------------------------------------------------------
# Score
# ---------------------------------------------------------------------------

def cc_count(grid):
    return sum(1 for row in grid for c in row if c == 'C')

def absent_count(grid):
    return sum(1 for row in grid for c in row if c == '.')

def dispersion_score(grid):
    """Pénalise les CCs sur des lignes/cols entières. Plus c'est dispersé, plus haut."""
    rows = len(grid)
    cols = len(grid[0])
    # Pour chaque CC, compter ses voisins CC à distance Manhattan ≤ 2.
    score = 0
    cc_positions = [(r, c) for r in range(rows) for c in range(cols) if grid[r][c] == 'C']
    for r, c in cc_positions:
        neighbors = sum(
            1 for r2, c2 in cc_positions
            if (r, c) != (r2, c2) and abs(r - r2) + abs(c - c2) <= 2
        )
        score -= neighbors  # plus de voisins = moins dispersé
    return score

def runs_lengths(grid):
    """Retourne toutes les longueurs de run de L (H et V) ≥ 2."""
    from generate_patterns import runs_horizontal, runs_vertical
    g = [[('B' if c == '.' else c) for c in row] for row in grid]
    lens = []
    for r, c0, length in runs_horizontal(g):
        if length >= 2:
            lens.append(length)
    for r0, c, length in runs_vertical(g):
        if length >= 2:
            lens.append(length)
    return lens

def composite_score(grid):
    # Lower CC count = better. Higher dispersion = better.
    # Pénalise les slots trop longs (>5) car difficiles à interlocker.
    cc = cc_count(grid)
    abs_ = absent_count(grid)
    disp = dispersion_score(grid)
    lens = runs_lengths(grid)
    long_slot_penalty = sum(max(0, l - 5) ** 2 for l in lens)
    return -3 * cc - abs_ + 0.5 * disp - 2 * long_slot_penalty

# ---------------------------------------------------------------------------
# Simulated annealing
# ---------------------------------------------------------------------------

def random_neighbor(grid, rng):
    """Génère un voisin par swap aléatoire entre 2 positions."""
    new = deepcopy(grid)
    rows = len(new)
    cols = len(new[0])
    # Pick 2 random positions and swap their content.
    r1, c1 = rng.randint(0, rows - 1), rng.randint(0, cols - 1)
    r2, c2 = rng.randint(0, rows - 1), rng.randint(0, cols - 1)
    new[r1][c1], new[r2][c2] = new[r2][c2], new[r1][c1]
    return new

def random_flip(grid, rng):
    """Génère un voisin en changeant 1 position au hasard."""
    new = deepcopy(grid)
    rows = len(new)
    cols = len(new[0])
    r, c = rng.randint(0, rows - 1), rng.randint(0, cols - 1)
    choices = [x for x in ('C', 'L', '.') if x != new[r][c]]
    new[r][c] = rng.choice(choices)
    return new

def anneal(initial, rng, iterations=2000):
    current = initial
    best = deepcopy(current)
    best_score = composite_score(best)
    for i in range(iterations):
        neighbor = random_flip(current, rng) if rng.random() < 0.5 else random_neighbor(current, rng)
        if not must_be_valid(neighbor):
            continue
        score = composite_score(neighbor)
        if score > best_score:
            best = deepcopy(neighbor)
            best_score = score
            current = neighbor
        elif rng.random() < 0.1:  # exploration
            current = neighbor
    return best, best_score

# ---------------------------------------------------------------------------
# Sortie format Dart
# ---------------------------------------------------------------------------

def emit_dart(grid):
    rows = len(grid)
    cols = len(grid[0])
    cc = cc_count(grid)
    abs_ = absent_count(grid)
    visual = " / ".join("".join(row).replace("L", ".").replace(".", "_") for row in grid)
    lines = []
    lines.append(f"  // {rows}×{cols} pattern — CC={cc}, absent={abs_}, ratio CC/total={cc/(rows*cols):.0%}")
    lines.append(f"  // Visual: {visual}")
    lines.append(f"  _Pattern(rows: {rows}, cols: {cols}, kinds: [")
    for row in grid:
        tokens = []
        for ch in row:
            if ch == 'C':
                tokens.append('CellKind.clue')
            elif ch == 'L':
                tokens.append('CellKind.letter')
            else:
                tokens.append('CellKind.blocker')
        lines.append(f"    {', '.join(tokens)}, // {''.join(row)}")
    lines.append("  ]),")
    return "\n".join(lines)

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--seeds', type=int, default=20, help='nb de runs SA')
    ap.add_argument('--iters', type=int, default=3000, help='iterations par run')
    ap.add_argument('--top', type=int, default=5, help='nb de patterns à sortir')
    args = ap.parse_args()

    initial = tiled_8x8()
    assert must_be_valid(initial), "Le tiled initial doit être valide"

    best_patterns = []
    for seed in range(args.seeds):
        rng = random.Random(seed)
        pattern, score = anneal(initial, rng, args.iters)
        best_patterns.append((score, pattern))
        print(f"  seed={seed:2d} : CC={cc_count(pattern):2d} score={score:.2f}", file=sys.stderr)

    # Garde les top N par score
    best_patterns.sort(key=lambda x: -x[0])
    top = best_patterns[:args.top]

    print()
    print("// Patterns générés par tools/kb-builder/search_scattered_patterns.py")
    print()
    for score, pattern in top:
        print(emit_dart(pattern))

if __name__ == '__main__':
    sys.exit(main())
