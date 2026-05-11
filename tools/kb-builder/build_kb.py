#!/usr/bin/env python3
"""
Chabaka KB Builder — produit assets/kb/chabaka_kb.sqlite à partir de CSV curés.

Pipeline V1 :
  1. Lit chaque CSV de INPUT_FILES.
  2. Pour chaque ligne : normalise R3, valide R2, applique exclusions.
  3. Regroupe par mot normalisé (1 entry, N clues).
  4. Écrit SQLite avec schéma conforme à docs/V1-MVP-R4-spec.md § 1.2.

Usage :
    python3 build_kb.py            # build avec sortie par défaut
    python3 build_kb.py --out X    # override chemin de sortie

Aucune dépendance externe : utilise uniquement la stdlib Python.
"""

from __future__ import annotations

import argparse
import csv
import os
import re
import sqlite3
import sys
import unicodedata
from collections import defaultdict
from dataclasses import dataclass, field
from pathlib import Path
from typing import Iterable

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------

ROOT = Path(__file__).resolve().parent
PROJECT_ROOT = ROOT.parent.parent
DEFAULT_OUT = PROJECT_ROOT / "assets" / "kb" / "chabaka_kb.sqlite"

INPUT_FILES = [
    ROOT / "seed" / "chabaka_seed.csv",
]

VALID_CATEGORIES = {
    "common", "person", "place", "country", "capital",
    "history", "science", "art", "idiom",
    "verb", "adjective", "food", "sport", "job",
    "object", "home", "animal", "plant", "nature",
    "transport", "body", "emotion", "economy", "law",
}
VALID_CLUE_KINDS = {"synonym", "definition", "idiom", "context"}

# Exclusions strictes (PO 2026-05-10) : politique sensible, religion polémique,
# géopolitique. Liste à étendre selon audit éditorial.
EXCLUSIONS_NORMALIZED = {
    # Géopolitique sensible
    "الصحراء",       # Sahara (sujet politique Maroc-Algérie)
    "القدس",         # Jérusalem
    "فلسطين",        # Palestine (sensible international)
    # Religion polémique (V1 n'inclut pas de termes spécifiques sectaires)
    # Politique partisane (ajouter au besoin)
}

# ---------------------------------------------------------------------------
# Normalisation arabe (R3 — miroir de lib/puzzle/arabic_normalizer.dart)
# ---------------------------------------------------------------------------

_DIACRITICS = set("ًٌٍَُِّْٰٕٖٓٔٗ٘")
_ZERO_WIDTH = {"‌", "‍", " ", "﻿"}
_ALEF_VARIANTS = {"أ", "إ", "آ", "ٱ"}

def normalize_r3(text: str) -> str:
    """Applique la normalisation R3 (sans diacritiques, ا/أ/إ/آ → ا,
    ة → ه, ى → ي, supprime ZWNJ/ZWJ)."""
    out = []
    for ch in text:
        if ch in _DIACRITICS:
            continue
        if ch in _ZERO_WIDTH:
            continue
        if ch.isspace():
            continue
        if ch in _ALEF_VARIANTS:
            ch = "ا"
        elif ch == "ة":
            ch = "ه"
        elif ch == "ى":
            ch = "ي"
        out.append(ch)
    return "".join(out)

# ---------------------------------------------------------------------------
# Validation R2 (langue arabe propre)
# ---------------------------------------------------------------------------

def is_arabic_rune(c: str) -> bool:
    if c == " " or c == "‌":
        return True
    if c in {"،", "؛", "؟", ":"}:
        return True
    cp = ord(c)
    if 0x0600 <= cp <= 0x06FF:  # Arabic block
        return True
    if 0x0750 <= cp <= 0x077F:  # Arabic Supplement
        return True
    if 0x08A0 <= cp <= 0x08FF:  # Arabic Extended-A
        return True
    return False

def validate_arabic(text: str) -> str | None:
    """Retourne None si valide, sinon la description du 1er char invalide."""
    for ch in text:
        if not is_arabic_rune(ch):
            return f"caractère non arabe U+{ord(ch):04X} '{ch}'"
    return None

# ---------------------------------------------------------------------------
# Modèle interne
# ---------------------------------------------------------------------------

@dataclass
class RawRow:
    word_display: str
    category: str
    clue_text: str
    clue_kind: str
    difficulty: int
    source: str
    line_no: int
    file: str

@dataclass
class KbEntry:
    word: str             # normalisé R3
    word_display: str     # forme originale
    length: int
    category: str
    difficulty: int
    source: str
    reviewed: int
    clues: list[tuple[str, str, int]] = field(default_factory=list)
    # tuples (text, kind, priority)

# ---------------------------------------------------------------------------
# Lecture CSV
# ---------------------------------------------------------------------------

def read_csv(path: Path) -> Iterable[RawRow]:
    with path.open(newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for i, row in enumerate(reader, start=2):  # ligne 1 = header
            yield RawRow(
                word_display=row["word_display"].strip(),
                category=row["category"].strip(),
                clue_text=row["clue_text"].strip(),
                clue_kind=row["clue_kind"].strip(),
                difficulty=int(row.get("difficulty", "2") or 2),
                source=row.get("source", "curated").strip() or "curated",
                line_no=i,
                file=str(path.name),
            )

# ---------------------------------------------------------------------------
# Validation + filtrage
# ---------------------------------------------------------------------------

def process_rows(rows: Iterable[RawRow]) -> tuple[dict[str, KbEntry], list[str]]:
    entries: dict[str, KbEntry] = {}
    warnings: list[str] = []

    for row in rows:
        loc = f"{row.file}:{row.line_no}"

        # Validation R2 sur word_display + clue
        err = validate_arabic(row.word_display)
        if err:
            warnings.append(f"{loc} R2 rejet word: {err}")
            continue
        err = validate_arabic(row.clue_text)
        if err:
            warnings.append(f"{loc} R2 rejet clue: {err}")
            continue

        # Validation catégorie + kind
        if row.category not in VALID_CATEGORIES:
            warnings.append(f"{loc} catégorie inconnue: {row.category}")
            continue
        if row.clue_kind not in VALID_CLUE_KINDS:
            warnings.append(f"{loc} clue_kind inconnu: {row.clue_kind}")
            continue
        if row.difficulty not in (1, 2, 3):
            warnings.append(f"{loc} difficulty hors [1,3]: {row.difficulty}")
            continue

        # Normalisation
        normalized = normalize_r3(row.word_display)
        if not normalized:
            warnings.append(f"{loc} mot vide après normalisation")
            continue

        # Exclusions
        if normalized in EXCLUSIONS_NORMALIZED:
            warnings.append(f"{loc} EXCLU (PO strict): {row.word_display}")
            continue

        # Longueur
        length = len(normalized)
        if length < 2:
            warnings.append(f"{loc} mot trop court (len={length}): {row.word_display}")
            continue

        # Aggrégation par mot normalisé
        if normalized in entries:
            existing = entries[normalized]
            # Vérifier cohérence catégorie (warning si différente, garde la 1re)
            if existing.category != row.category:
                warnings.append(
                    f"{loc} catégorie différente pour '{row.word_display}' "
                    f"({existing.category} vs {row.category}) — garde {existing.category}"
                )
            # Ajoute clue (priorité = ordre d'arrivée)
            existing.clues.append(
                (row.clue_text, row.clue_kind, len(existing.clues))
            )
        else:
            entries[normalized] = KbEntry(
                word=normalized,
                word_display=row.word_display,
                length=length,
                category=row.category,
                difficulty=row.difficulty,
                source=row.source,
                reviewed=1 if row.source == "curated" else 0,
                clues=[(row.clue_text, row.clue_kind, 0)],
            )

    return entries, warnings

# ---------------------------------------------------------------------------
# Écriture SQLite
# ---------------------------------------------------------------------------

SCHEMA = """
PRAGMA foreign_keys = ON;

CREATE TABLE entries (
  id            INTEGER PRIMARY KEY,
  word          TEXT NOT NULL,
  word_display  TEXT NOT NULL,
  length        INTEGER NOT NULL,
  category      TEXT NOT NULL,
  difficulty    INTEGER NOT NULL,
  source        TEXT NOT NULL,
  reviewed      INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE clues (
  id        INTEGER PRIMARY KEY,
  entry_id  INTEGER NOT NULL REFERENCES entries(id) ON DELETE CASCADE,
  text      TEXT NOT NULL,
  kind      TEXT NOT NULL,
  priority  INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE letter_index (
  entry_id  INTEGER NOT NULL,
  length    INTEGER NOT NULL,
  position  INTEGER NOT NULL,
  letter    TEXT NOT NULL,
  PRIMARY KEY (length, position, letter, entry_id)
);
CREATE INDEX idx_letter_lookup ON letter_index(length, position, letter);

CREATE INDEX idx_entries_length ON entries(length);
CREATE INDEX idx_entries_cat_len ON entries(category, length);

CREATE VIRTUAL TABLE clues_fts USING fts5(text, content='clues', content_rowid='id');

CREATE TRIGGER clues_fts_insert AFTER INSERT ON clues BEGIN
  INSERT INTO clues_fts(rowid, text) VALUES (new.id, new.text);
END;
"""

def write_sqlite(entries: dict[str, KbEntry], out_path: Path) -> None:
    out_path.parent.mkdir(parents=True, exist_ok=True)
    if out_path.exists():
        out_path.unlink()

    conn = sqlite3.connect(str(out_path))
    try:
        conn.executescript(SCHEMA)

        # Insère entries
        for next_id, entry in enumerate(sorted(entries.values(), key=lambda e: e.word), start=1):
            conn.execute(
                "INSERT INTO entries(id, word, word_display, length, category, difficulty, source, reviewed) "
                "VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
                (next_id, entry.word, entry.word_display, entry.length,
                 entry.category, entry.difficulty, entry.source, entry.reviewed),
            )
            # Insère clues
            for text, kind, priority in entry.clues:
                conn.execute(
                    "INSERT INTO clues(entry_id, text, kind, priority) VALUES (?, ?, ?, ?)",
                    (next_id, text, kind, priority),
                )
            # Insère letter_index
            for pos, ch in enumerate(entry.word):
                conn.execute(
                    "INSERT INTO letter_index(entry_id, length, position, letter) VALUES (?, ?, ?, ?)",
                    (next_id, entry.length, pos, ch),
                )

        conn.commit()
        conn.execute("VACUUM")
        conn.execute("ANALYZE")
    finally:
        conn.close()

# ---------------------------------------------------------------------------
# Stats
# ---------------------------------------------------------------------------

def report(entries: dict[str, KbEntry], warnings: list[str]) -> None:
    print(f"Entrées : {len(entries)}")
    by_cat: dict[str, int] = defaultdict(int)
    by_len: dict[int, int] = defaultdict(int)
    total_clues = 0
    for e in entries.values():
        by_cat[e.category] += 1
        by_len[e.length] += 1
        total_clues += len(e.clues)
    print(f"Total clues : {total_clues}")
    print("Par catégorie :")
    for cat, n in sorted(by_cat.items()):
        print(f"  {cat:10s} : {n}")
    print("Par longueur :")
    for length in sorted(by_len):
        print(f"  len={length} : {by_len[length]}")
    if warnings:
        print(f"\n{len(warnings)} warnings :")
        for w in warnings[:20]:
            print(f"  {w}")
        if len(warnings) > 20:
            print(f"  ... ({len(warnings) - 20} autres)")

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> int:
    ap = argparse.ArgumentParser(description="Chabaka KB Builder")
    ap.add_argument("--out", default=str(DEFAULT_OUT), help="chemin SQLite de sortie")
    args = ap.parse_args()

    rows: list[RawRow] = []
    for path in INPUT_FILES:
        if not path.exists():
            print(f"[KB] WARNING : fichier absent {path}", file=sys.stderr)
            continue
        rows.extend(read_csv(path))
        print(f"[KB] {len(rows)} lignes après {path.name}")

    entries, warnings = process_rows(rows)
    if not entries:
        print("[KB] ERREUR : aucune entrée valide", file=sys.stderr)
        return 1

    out_path = Path(args.out).resolve()
    write_sqlite(entries, out_path)
    size_kb = out_path.stat().st_size // 1024
    print(f"\n[KB] Écrit : {out_path} ({size_kb} KB)")
    report(entries, warnings)
    return 0

if __name__ == "__main__":
    sys.exit(main())
