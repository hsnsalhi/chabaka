#!/usr/bin/env python3
"""Contrôle d'un CSV d'enrichissement avant intégration dans la KB.

Usage : python3 check_csv.py seed/enrich/len4_common.csv [--length 4]

Vérifie, ligne par ligne :
  - en-tête exact : word_display,category,clue_text,clue_kind,difficulty,source
  - 6 colonnes, catégorie et kind valides, difficulté 1..3
  - mot : caractères arabes uniquement (après normalisation R3), longueur
    normalisée == --length si fourni, entre 2 et 13 sinon
  - mot absent de la KB existante (assets/kb/chabaka_kb.sqlite, forme normalisée)
  - pas de doublon normalisé à l'intérieur du fichier
  - indice : non vide, ≤ 6 mots, ne contient pas le mot lui-même, caractères
    arabes (ponctuation arabe tolérée)
Code de sortie 0 si aucune erreur. Affiche un résumé par longueur.
"""
import csv, sqlite3, sys, argparse
from collections import Counter
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from build_kb import normalize_r3, validate_arabic, VALID_CATEGORIES, VALID_CLUE_KINDS, EXCLUSIONS_NORMALIZED  # noqa: E402

ROOT = Path(__file__).resolve().parent
KB = ROOT.parent.parent / "assets" / "kb" / "chabaka_kb.sqlite"
HEADER = ["word_display", "category", "clue_text", "clue_kind", "difficulty", "source"]


def existing_words() -> set[str]:
    if not KB.exists():
        return set()
    con = sqlite3.connect(KB)
    return {w for (w,) in con.execute("select word from entries")}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("files", nargs="+")
    ap.add_argument("--length", type=int, default=None)
    ap.add_argument("--quiet", action="store_true")
    a = ap.parse_args()
    known = existing_words()
    total_err = 0
    for f in a.files:
        errs: list[str] = []
        seen: dict[str, int] = {}
        kept = Counter()
        with open(f, encoding="utf-8", newline="") as fh:
            rows = list(csv.reader(fh))
        if not rows or [c.strip() for c in rows[0]] != HEADER:
            errs.append("L1: en-tête attendu : " + ",".join(HEADER))
            rows = rows[1:] if rows else []
        else:
            rows = rows[1:]
        for i, row in enumerate(rows, start=2):
            if not row or all(not c.strip() for c in row):
                continue
            if len(row) != 6:
                errs.append(f"L{i}: {len(row)} colonnes au lieu de 6 (virgule dans un champ ? utiliser des guillemets)")
                continue
            word, cat, clue, kind, diff, src = [c.strip() for c in row]
            norm = normalize_r3(word)
            bad = validate_arabic(word)
            if bad:
                errs.append(f"L{i}: mot « {word} » : {bad}"); continue
            if not norm:
                errs.append(f"L{i}: mot vide"); continue
            n = len(norm)
            if a.length is not None and n != a.length:
                errs.append(f"L{i}: « {word} » fait {n} lettres normalisées, attendu {a.length}"); continue
            if not (2 <= n <= 13):
                errs.append(f"L{i}: « {word} » fait {n} lettres (hors 2..13)"); continue
            if norm in EXCLUSIONS_NORMALIZED:
                errs.append(f"L{i}: « {word} » est dans la liste d'exclusion"); continue
            if norm in known:
                errs.append(f"L{i}: « {word} » existe déjà dans la KB"); continue
            if norm in seen:
                errs.append(f"L{i}: « {word} » doublon de la ligne {seen[norm]}"); continue
            if cat not in VALID_CATEGORIES:
                errs.append(f"L{i}: catégorie invalide « {cat} »"); continue
            if kind not in VALID_CLUE_KINDS:
                errs.append(f"L{i}: clue_kind invalide « {kind} »"); continue
            if diff not in ("1", "2", "3"):
                errs.append(f"L{i}: difficulty « {diff} » hors 1..3"); continue
            if not clue:
                errs.append(f"L{i}: indice vide"); continue
            badc = validate_arabic(clue.replace("...", "").replace("…", ""))
            if badc:
                errs.append(f"L{i}: indice « {clue} » : {badc}"); continue
            if len(clue.split()) > 6:
                errs.append(f"L{i}: indice trop long (> 6 mots) : « {clue} »"); continue
            if norm in normalize_r3(clue) and n >= 3:
                errs.append(f"L{i}: l'indice contient le mot lui-même : « {clue} »"); continue
            seen[norm] = i
            kept[n] += 1
        print(f"== {f} : {sum(kept.values())} entrées valides, {len(errs)} erreurs")
        for n in sorted(kept):
            print(f"   longueur {n} : {kept[n]}")
        if not a.quiet:
            for e in errs[:200]:
                print("   ERREUR " + e)
            if len(errs) > 200:
                print(f"   ... {len(errs) - 200} autres erreurs")
        total_err += len(errs)
    return 1 if total_err else 0


if __name__ == "__main__":
    sys.exit(main())
