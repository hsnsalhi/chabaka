#!/usr/bin/env python3
"""Applique des corrections d'indices aux CSV sources, ligne par ligne.

Entrée : un ou plusieurs fichiers JSONL dont chaque ligne vaut
  {"file": <chemin du CSV>, "line": <n° de ligne, en-tête = 1>, "word": ..., "old": ..., "new": ...}
Une correction n'est appliquée que si la ligne du CSV a bien ce word_display et cet indice
(`old`) : sinon elle est signalée et ignorée. Écrit un rapport sur la sortie standard.

    python3 tools/kb-builder/clues_fix_apply.py corrections1.jsonl [corrections2.jsonl …]
"""
import csv
import io
import json
import sys
from collections import defaultdict
from pathlib import Path


def main(paths):
    fixes = defaultdict(dict)
    for p in paths:
        for raw in Path(p).read_text(encoding="utf-8").splitlines():
            if not raw.strip():
                continue
            fx = json.loads(raw)
            fixes[fx["file"]][int(fx["line"])] = fx
    applied = skipped = 0
    for file, by_line in sorted(fixes.items()):
        path = Path(file)
        with open(path, encoding="utf-8", newline="") as fh:
            content = fh.read()
        # Fin de ligne d'origine conservée (certains CSV sont en CRLF).
        eol = "\r\n" if "\r\n" in content else "\n"
        lines = content.split(eol)
        header = next(csv.reader([lines[0]]))
        iw, it = header.index("word_display"), header.index("clue_text")
        for line, fx in sorted(by_line.items()):
            # Une ligne de CSV par ligne de fichier : seules les lignes corrigées
            # sont réécrites, le reste du fichier garde son format exact.
            row = next(csv.reader([lines[line - 1]])) if line - 1 < len(lines) else None
            if not row or row[iw].strip() != fx["word"] or row[it].strip() != fx["old"]:
                print(f"IGNORÉ {file}:{line} {fx['word']} « {fx['old']} » (ligne différente)")
                skipped += 1
                continue
            new = fx["new"].strip()
            if not new or new == fx["old"]:
                skipped += 1
                continue
            row[it] = new
            out = io.StringIO()
            csv.writer(out, lineterminator="").writerow(row)
            lines[line - 1] = out.getvalue()
            applied += 1
        with open(path, "w", encoding="utf-8", newline="") as fh:
            fh.write(eol.join(lines))
    print(f"{applied} corrections appliquées, {skipped} ignorées")


if __name__ == "__main__":
    main(sys.argv[1:])
