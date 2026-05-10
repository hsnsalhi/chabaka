#!/usr/bin/env python3
"""Valide un patron passé en CLI ou stdin et émet le code Dart si OK."""
import sys
from generate_patterns import is_valid, emit_dart

# Patrons candidats hand-crafted (chacun sur 5 lignes pour 5×5).
# Format : 1 ligne par row, B/C/L sans espaces.
CANDIDATES_4 = [
    # P0 : BCCC / CLLL / CLLL / CLLL
    ["BCCC", "CLLL", "CLLL", "CLLL"],
    # P1 : BCCC / CLLL / CLLL / CLLB
    ["BCCC", "CLLL", "CLLL", "CLLB"],
    # P2 : BCCB / CLLC / CLLL / CLLL
    ["BCCB", "CLLC", "CLLL", "CLLL"],
    # P3 : BCCB / CLLL / CLLC / CLLL
    ["BCCB", "CLLL", "CLLC", "CLLL"],
    # P4 : BCCC / CLLL / CCLL / CLLL — interne ligne 2
    ["BCCC", "CLLL", "CCLL", "CLLL"],
    # P5 : BCBC / CLBL / CCLL / CLLL — patron éparse
    ["BCBC", "CLBL", "CCLL", "CLLL"],
]

CANDIDATES_5 = [
    # P0 : top-left corner B, header de C, body de L (canonical "tableau" layout)
    [
        "BCCCC",
        "CLLLL",
        "CLLLL",
        "CLLLL",
        "CLLLL",
    ],
    # P1 : double colonne header + B en bas-droite
    [
        "BCCCC",
        "CLLLL",
        "CCLLL",
        "CLLLL",
        "CLLLL",
    ],
    # P2 : B au coin haut-droit
    [
        "CCCCB",
        "LLLLC",
        "LLLLC",
        "LLLLC",
        "LLLLC",
    ],
    # P3 : B haut-gauche + bas-droit
    [
        "BCCCC",
        "CLLLL",
        "CLLLL",
        "CLLLL",
        "CLLLB",
    ],
    # P4 : header partiel, body sectionné
    [
        "BCCCC",
        "CLLLL",
        "CCLLL",
        "CLLLL",
        "CCLLL",
    ],
    # P5 : alternance rows-2
    [
        "BCCCC",
        "CLLLL",
        "CLLLL",
        "CCLLL",
        "CLLLL",
    ],
    # P6 : densité maxi
    [
        "BCCCC",
        "CLLLL",
        "CLLLC",
        "CLLLL",
        "CLLLB",
    ],
    # P7 : B en colonne droite + col 4 cluée par row 0
    [
        "BCCCC",
        "CLLLL",
        "CLLCB",
        "CLLLL",
        "CLLLL",
    ],
]

CANDIDATES_7 = [
    # 7×7 P0 : version étendue de P0
    [
        "BCCCCCC",
        "CLLLLLL",
        "CLLLLLL",
        "CLLLLLL",
        "CLLLLLL",
        "CLLLLLL",
        "CLLLLLL",
    ],
    # 7×7 P1 : avec C interne
    [
        "BCCCCCC",
        "CLLLLLL",
        "CLLCLLL",
        "CLLLLLL",
        "CCLLLLL",
        "CLLLLLL",
        "CLLLLLL",
    ],
    # 7×7 P2 : avec B interne
    [
        "BCCCCCC",
        "CLLLLLL",
        "CLBLLLL",
        "CCLLLLL",
        "CLLLLLL",
        "CLLLCLL",
        "CLLLLLL",
    ],
    # 7×7 P3 : autre layout
    [
        "BCCCCCC",
        "CLLLLLL",
        "CLLLCLL",
        "CLLLLLL",
        "CCLLLLL",
        "CLLLLLL",
        "CLLLLLL",
    ],
]

def main():
    print("=== Validation 4×4 ===", file=sys.stderr)
    valid_4 = []
    for i, c in enumerate(CANDIDATES_4):
        if all(len(row) == len(c[0]) for row in c) and is_valid(c):
            valid_4.append(c)
            print(f"  P{i} : VALID", file=sys.stderr)
        else:
            print(f"  P{i} : INVALID — {' / '.join(c)}", file=sys.stderr)

    print("=== Validation 5×5 ===", file=sys.stderr)
    valid_5 = []
    for i, c in enumerate(CANDIDATES_5):
        if all(len(row) == len(c[0]) for row in c) and is_valid(c):
            valid_5.append(c)
            print(f"  P{i} : VALID", file=sys.stderr)
        else:
            print(f"  P{i} : INVALID — {' / '.join(c)}", file=sys.stderr)

    print("=== Validation 7×7 ===", file=sys.stderr)
    valid_7 = []
    for i, c in enumerate(CANDIDATES_7):
        if all(len(row) == len(c[0]) for row in c) and is_valid(c):
            valid_7.append(c)
            print(f"  P{i} : VALID", file=sys.stderr)
        else:
            print(f"  P{i} : INVALID — {' / '.join(c)}", file=sys.stderr)

    if valid_4:
        print()
        print(emit_dart(valid_4, 4))
    if valid_5:
        print()
        print(emit_dart(valid_5, 5))
    if valid_7:
        print()
        print(emit_dart(valid_7, 7))

if __name__ == "__main__":
    main()
