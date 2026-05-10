# Chabaka KB Builder

Pipeline Python qui transforme un (ou plusieurs) CSV d'entrées arabes en un fichier SQLite + FTS5 embarqué dans l'app via `assets/kb/chabaka_kb.sqlite`.

## Quickstart

```bash
cd tools/kb-builder
python3 build_kb.py
```

Cela :

1. Lit `seed/chabaka_seed.csv` (200 entrées curées V1).
2. Applique la normalisation R3 (ا/أ/إ/آ → ا, ة → ه, ى → ي, retire diacritiques).
3. Valide R2 (caractères arabes uniquement) — rejette + log les violations.
4. Filtre les exclusions strictes (politique sensible / religion polémique / géopolitique — cf. `EXCLUSIONS`).
5. Dédoublonne par forme normalisée.
6. Construit `letter_index` (1 row par lettre × position).
7. Écrit `../../assets/kb/chabaka_kb.sqlite`.

## Schema

Conforme à `docs/V1-MVP-R4-spec.md` § 1.2 :

- `entries (id, word, word_display, length, category, difficulty, source, reviewed)`
- `clues (id, entry_id, text, kind, priority)`
- `letter_index (entry_id, length, position, letter)` — index principal du solver
- `clues_fts` — FTS5 virtuelle pour dedup éditorial

## Étendre la KB

Pour augmenter le volume :

1. Ajoute des entrées dans `seed/chabaka_seed.csv` (manuel) OU
2. Crée un nouveau CSV ingestible (ex `seed/wikipedia_capitals.csv`) et ajoute-le dans `INPUT_FILES` de `build_kb.py` OU
3. Branche un script qui parse Wiktionary AR XML / Wikipedia titles dump et produit un CSV au format attendu, puis l'ajoute à `INPUT_FILES`.

Format CSV :

```
word_display,category,clue_text,clue_kind,difficulty,source
كتاب,common,شيء يقرأ ويكتب فيه,definition,2,curated
المغرب,country,بلد في شمال إفريقيا,definition,2,curated
ابن خلدون,person,مؤرخ ومفكر مغربي,definition,2,curated
```

- `word_display` : forme avec hamza/ة/ى originale.
- `category` : `common|person|place|country|capital|history|science|art|idiom`.
- `clue_kind` : `synonym|definition|idiom|context`.
- Plusieurs lignes avec le même `word_display` → plusieurs clues pour la même entrée.

## Sources publiques (V2+)

Pour pousser vers 5 000 entrées, brancher :

- **Wiktionary AR** dump XML : `https://dumps.wikimedia.org/arwiktionary/latest/`
- **Wikipedia AR** titres : `https://dumps.wikimedia.org/arwiki/latest/arwiki-latest-all-titles-in-ns0.gz`
- **Wikidata** : labels arabe via `wbgetentities` ou dump JSON.

Chaque branchement doit produire un CSV au format ci-dessus, validable dans `build_kb.py`.
