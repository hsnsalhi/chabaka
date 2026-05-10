# Chabaka V1 MVP — Spec R4 (refonte wordlist + générateur)

> Produite le 2026-05-10 par `architect`. Complète `V1-MVP-spec.md` après dictée de **R4** (`docs/grid-rules.md`). À exécuter par `router` étape par étape.

## TL;DR

R4 force trois ruptures avec la V1 actuelle :

1. La **wordlist plate** (50 entrées, JSON) devient une **base de connaissances (KB)** large, thématique, embarquée → **SQLite + FTS5** indexé par longueur et par lettre×position.
2. Le **générateur greedy** ne peut PAS garantir R4 → réécriture en **topologie d'abord, remplissage par backtracking de slots** (chaque slot doit être un mot KB, intersections incluses).
3. **Sourcing offline** : pipeline Python batch (Wiktionary AR + Wikipedia AR titres + corpus libres) → SQLite embarqué dans `assets/kb/`.

V1 cible réaliste : **3 000 entrées**, taille bundle compressé **~5–10 MB**, génération 7×7 < 1 s sur iPhone récent.

---

## 1. Modèle de données — Knowledge Base

### 1.1 Choix du format : SQLite + FTS5

| Critère | JSON | SQLite + FTS5 | SQLite plain |
|---|---|---|---|
| Recherche `length=L AND letter[p]=X` | scan O(N) | index O(log N) | index O(log N) |
| Recherche par thème + longueur | scan | index composite | index composite |
| Mémoire RAM | tout chargé | mmap, paginé | mmap, paginé |
| Compression à l'embed | gzip externe | page-compress + ZSTD VFS | idem |
| Outillage Flutter | natif | `sqflite` + `sqlite3_flutter_libs` | idem |
| Recherche "définition contient X" | scan | **FTS5 natif** | LIKE lent |

**Décision : SQLite avec extension FTS5** pour les définitions ; tables relationnelles pour les index structurels (longueur, lettre×position).

Justifications :
- Une wordlist de 3 k–10 k entrées tient en RAM en JSON (~2–5 MB), mais le solver fait **des milliers** de requêtes "mots de longueur L, avec lettre X en position p, qui ne sont pas déjà placés" — un index B-tree sur `(length, letter_pos_0, letter_pos_1, …)` rend ça O(log N).
- FTS5 est fourni gratuitement par SQLite ; pas de dépendance externe.
- Format binaire compact, lisible dès l'install (pas de "premier lancement, je décompresse 30 MB").

### 1.2 Schema

```sql
-- Table principale : une entrée = un mot canonique + ses métadonnées.
CREATE TABLE entries (
  id            INTEGER PRIMARY KEY,
  word          TEXT NOT NULL,            -- forme canonique normalisée (R3)
  word_display  TEXT NOT NULL,            -- forme jolie pour l'affichage (avec ة, أ, etc.)
  length        INTEGER NOT NULL,
  category      TEXT NOT NULL,            -- enum : common, person, place, country, capital,
                                          --        history, science, art, idiom
  difficulty    INTEGER NOT NULL,         -- 1=facile, 2=moyen, 3=culturel pointu
  source        TEXT NOT NULL,            -- 'wiktionary', 'wikipedia', 'curated', etc.
  reviewed      INTEGER NOT NULL DEFAULT 0 -- 0=auto, 1=audité humain
);

-- Indices (plusieurs par entrée possibles).
CREATE TABLE clues (
  id        INTEGER PRIMARY KEY,
  entry_id  INTEGER NOT NULL REFERENCES entries(id) ON DELETE CASCADE,
  text      TEXT NOT NULL,                -- indice arabe court (≤ 40 chars idéalement)
  kind      TEXT NOT NULL,                -- 'synonym', 'definition', 'idiom', 'context'
  priority  INTEGER NOT NULL DEFAULT 0    -- ordre préféré
);

-- Index principal du solver : `(length, position, letter)` → entries.
-- Permet "tous les mots de longueur 5 dont la 3e lettre est ع".
CREATE TABLE letter_index (
  entry_id  INTEGER NOT NULL,
  length    INTEGER NOT NULL,
  position  INTEGER NOT NULL,             -- 0-based
  letter    TEXT NOT NULL,                -- 1 char arabe normalisé
  PRIMARY KEY (length, position, letter, entry_id)
);
CREATE INDEX idx_letter_lookup ON letter_index(length, position, letter);

-- FTS5 sur les indices pour recherche de duplicata éditorial.
CREATE VIRTUAL TABLE clues_fts USING fts5(text, content='clues', content_rowid='id');

-- Index secondaires utiles.
CREATE INDEX idx_entries_length ON entries(length);
CREATE INDEX idx_entries_cat_len ON entries(category, length);
```

Notes :
- `word` est **normalisé** (R3 : `ا/أ/إ/آ → ا`, `ة → ه`, `ى → ي`, diacritiques retirés). C'est ce que le solver matche.
- `word_display` garde la forme canonique avec hamza et ة pour la définition à l'écran.
- `length` est précalculé (= `runes(word).length`).
- `letter_index` est dérivé : 1 ligne par lettre × position, soit ~5 lignes par mot. Pour 10 k entrées de longueur moyenne 5 → ~50 k lignes, ~2 MB sans souci.

### 1.3 Requête type du solver

```sql
-- "Mots de longueur 5, avec ع en position 2, ل en position 4, non déjà placés."
SELECT e.id, e.word, e.word_display
FROM entries e
WHERE e.length = 5
  AND e.id IN (SELECT entry_id FROM letter_index WHERE length=5 AND position=2 AND letter='ع')
  AND e.id IN (SELECT entry_id FROM letter_index WHERE length=5 AND position=4 AND letter='ل')
  AND e.id NOT IN (:already_placed_ids)
LIMIT 50;
```

Un wrapper Dart (`KbRepository`) pré-compilera ces statements (cache `PreparedStatement`).

---

## 2. Sourcing offline — pipeline de constitution

### 2.1 Sources publiques exploitables

| Source | Type | Volume brut | Licence | Utilité |
|---|---|---|---|---|
| **Wiktionary AR** (dump XML) | dico | ~600 k entrées | CC BY-SA | vocabulaire courant + définitions |
| **Wikipedia AR** (titres + redirections) | encyclopédie | ~1 M titres | CC BY-SA | personnalités, lieux, œuvres |
| **Wikidata** | KG structuré | ~100 M items | CC0 | catégories (P31), labels AR, biographies |
| **OPUS / UN parallel corpus** | corpus | ~1 G mots | CC | extraction noms communs fréquents |
| **Lexique LMF arabe ouvert** (Open Multilingual Wordnet) | lexique | ~30 k synsets | libre | synonymes pour clues |
| Listes pays/capitales/villes (geonames AR) | structuré | ~10 k | CC BY | géographie en arabe |

V1 vise **les 4 premiers** ; les autres en V2.

### 2.2 Pipeline `tools/kb-builder/` (Python)

```
[dumps bruts]
   │
   ├─▶ extract.py        : XML/JSON → CSV plat (word, raw_def, source)
   ├─▶ normalize.py      : R3 normalisation + retire diacritiques
   ├─▶ filter_r2.py      : rejette caractères non arabes (utilise les mêmes
   │                       plages que `lib/puzzle/generation/wordlist.dart`)
   ├─▶ classify.py       : catégorie via heuristiques + Wikidata P31
   ├─▶ score_difficulty.py : 1/2/3 basé sur fréquence corpus + popularité Wikipedia
   ├─▶ extract_clues.py  : 1ère phrase Wiktionary → clue, dedup synonymes
   ├─▶ dedupe.py         : merge entrées même `word` normalisé
   ├─▶ audit_sample.py   : exporte un échantillon stratifié (200/cat) pour review humaine
   └─▶ build_sqlite.py   : génère `chabaka_kb.sqlite` avec schema § 1.2
                           VACUUM + page_size=4096 → fichier ~5–10 MB
```

Choix Python (vs Dart batch) : écosystème dump-parsing (mwparserfromhell, gensim, pandas) hors-pair. Le binaire produit est lu nativement par Flutter/sqflite.

### 2.3 Volumes cibles V1 (couverture par longueur)

Pour générer une grille N×N, il faut suffisamment de mots à chaque longueur de slot.

| Taille grille | Slots typiques | Longueurs requises | Mots min/longueur |
|---|---|---|---|
| 5×5 (V1 actuelle) | 6–10 slots | 2–5 | 80 |
| 7×7 (V1 cible) | 12–18 slots | 2–7 | 150 |
| 13×16 (Abou Salma) | 60–90 slots | 2–10 | 400+ |

**V1 réaliste : 3 000 entrées** réparties :
- 1 500 vocabulaire courant (Wiktionary fréquence haute)
- 600 personnalités (mondes arabe + intl)
- 400 géographie (pays, capitales, villes)
- 300 histoire / arts / sciences
- 200 idiomes / expressions

Cible par longueur : ≥ 200 mots pour chaque longueur 3..7, ≥ 80 pour 8..10.

V2/V3 : enrichissement progressif vers 10 000–20 000.

---

## 3. Algorithme R4 — topologie + slot-filling backtracking

### 3.1 Pourquoi le greedy actuel échoue

Le greedy place mot par mot et accepte les intersections. Quand un mot horizontal `ABCD` croise un mot vertical, il crée des **runs latérales accidentelles** (lettres adjacentes dans la perpendiculaire) qui peuvent former 2–3 lettres "lisibles" non valides. R4 les interdit.

### 3.2 Algorithme proposé : "Topology-First Slot-Filling"

```
PHASE A — Topologie (sans lettres)
  1. Décide les positions des ClueCells selon un patron (densité ≈ 25–30 %,
     évite ClueCells alignées créant des slots de longueur 1).
  2. Calcule les SLOTS H et V : maximal runs de LetterCells entre 2 ClueCells
     ou bord ↔ ClueCell. Tout slot de longueur 1 → invalide, retour à 1.
  3. Calcule les CONTRAINTES : pour chaque cellule lettre, liste des slots
     (1 H + 1 V généralement) qui passent dessus.

PHASE B — Filling (backtracking)
  4. Trie les slots par contrainte décroissante (plus longs et plus
     intersectés d'abord — heuristique "most constrained variable").
  5. Pour le slot courant :
     - Requête KB : mots de bonne longueur, compatibles avec lettres déjà
       fixées par d'autres slots déjà remplis → SQLite via letter_index.
     - Pour chaque candidat (ordre aléatoire seedé) :
       a. Vérifie que poser ce mot ne crée AUCUNE run accidentelle hors slot
          (par construction, si la topologie est correcte et qu'on remplit
          uniquement les slots définis, ça ne devrait pas arriver — mais on
          garde un check de sécurité).
       b. Récursion sur slot suivant.
       c. Sur échec → backtrack (essaie candidat suivant).
  6. Si tous les slots sont remplis → succès.

PHASE C — Indices
  7. Pour chaque slot, attribue une ClueCell adjacente (gauche en RTL pour H,
     haut pour V) qui n'a pas encore d'indice. Pioche `clues.text` du mot.
  8. R1 check : toute ClueCell doit avoir ≥ 1 indice. Sinon, fusion avec
     une ClueCell voisine ou retry.
```

Snippet illustratif (≤10 lignes) du cœur backtrack :

```dart
bool fill(int slotIdx, BacktrackState st) {
  if (slotIdx == slots.length) return true;
  final slot = order[slotIdx];
  final pattern = st.patternFor(slot); // ex: "ع_ا__"
  for (final entry in kb.findMatching(pattern, exclude: st.placed)) {
    st.place(slot, entry);
    if (fill(slotIdx + 1, st)) return true;
    st.unplace(slot, entry);
  }
  return false;
}
```

### 3.3 Performance attendue

- Slots typiques 7×7 : 12–18, longueur moyenne 4.
- Branching factor moyen avec KB 3 k mots et 2 lettres fixées : ~10–30 candidats.
- Profondeur 18, branching effectif après filtrage ~5 → exploration < 10⁵ nœuds dans la majorité des cas → **< 200 ms** sur iPhone récent.
- 13×16 : potentiellement plusieurs secondes, à benchmarker. Acceptable car généré 1× / jour.

### 3.4 Plans B

- **Échec backtracking** : retry avec **seed perturbé** (déjà en place pour R1, garder).
- **Échec persistant** : **réduire** la taille de grille (5×5 < 7×7) pour la "grille du jour" plutôt que de présenter rien.
- **Topologie infaisable** : la phase A doit valider qu'aucun slot de longueur 1 ne reste avant phase B. Si la KB ne couvre pas une longueur (ex: longueur 9), filtrer ces topologies en phase A.

---

## 4. Architecture d'embedding

### 4.1 Cible de taille

| Composant | V1 cible | Notes |
|---|---|---|
| `chabaka_kb.sqlite` (compressé) | 5–10 MB | 3 k entrées + index + FTS5 |
| Polices Cairo + Amiri (subset arabe) | ~500 KB | already in V1 |
| Code Flutter | ~15 MB | baseline Flutter |
| **App total iOS** | **< 30 MB** | OK App Store sans warning |
| **App total Android (appbundle)** | **< 25 MB** | split par ABI |

L'**App Store autorise > 200 MB**, mais 30 MB est le seuil psychologique "j'installe sans réfléchir". On reste large.

### 4.2 Compression

- SQLite `VACUUM` + `PRAGMA page_size = 4096` : -30 % vs build naïf.
- L'AAB Android compresse les assets en ZIP-deflate par défaut → SQLite passe de 8 MB brut à ~3 MB en bundle (texte arabe se compresse très bien).
- iOS : `.app` est zippé pour transmission App Store, même gain.
- **Pas besoin de gzip/Brotli/ZSTD custom** pour V1. À reconsidérer en V2 si on dépasse 50 MB.

### 4.3 Chargement runtime

- `sqflite` + `sqflite_common_ffi` (web/test). Le fichier est copié de `assets/kb/` vers `getApplicationSupportDirectory()` au premier lancement (sqflite n'ouvre pas directement les assets).
- Mode read-only (`OpenMode.readOnly`) → SQLite peut mmap.
- Statements préparés mis en cache dans `KbRepository`.

---

## 5. Critères de qualité éditoriale

### 5.1 Couverture cible

| Catégorie | % cible V1 | Mots min |
|---|---|---|
| Vocabulaire courant | 50 % | 1 500 |
| Personnalités | 20 % | 600 |
| Géographie | 13 % | 400 |
| Histoire/arts/sciences | 10 % | 300 |
| Idiomes | 7 % | 200 |

### 5.2 Exclusions (à valider PO)

- **Politique sensible contemporaine** : noms d'acteurs politiques vivants polarisants → exclure.
- **Religion controversée** : termes théologiques OK (références culturelles : أنبياء, مساجد), polémique → exclure.
- **Vulgaire / argot / familier** : exclure.
- **Termes étrangers translitérés** (R2 stricte) : exclure.

### 5.3 Pipeline d'audit

1. **Auto** : R2 (caractères), R3 (normalisation), longueur dans [2, 12], indice non vide, pas de duplicata FTS.
2. **Échantillonnage humain** : `audit_sample.py` exporte 200 entrées stratifiées par catégorie/difficulté/longueur → CSV pour review PO.
3. **Marquage** : `entries.reviewed = 1` après pass humain.
4. **V1 release** : > 80 % d'entrées `reviewed=1` minimum, 100 % du top 500 fréquence.

---

## 6. Workflow (router orchestre)

| # | Agent | Tâche | Effort | Dépend de | Livrable |
|---|---|---|---|---|---|
| 1 | architect | (cette spec) | — | — | `docs/V1-MVP-R4-spec.md` |
| 2 | puzzle | Définit le contrat `KbRepository` (interface Dart abstraite, méthodes solver) | S | 1 | `lib/puzzle/kb/kb_repository.dart` (abstract) |
| 3 | puzzle | Implémente la nouvelle topologie + backtracking (algo § 3.2), branché sur `KbRepository` | L | 2 | `lib/puzzle/generation/topology.dart` + refonte `generator.dart` |
| 4a | principal | Crée `tools/kb-builder/` Python : extract, normalize, filter_r2, dedupe, build_sqlite | M | 1 | scripts + README |
| 4b | principal | Catégorisation + scoring difficulté (Wikidata/heuristiques) | M | 4a | `classify.py`, `score_difficulty.py` |
| 4c | principal | Audit sample + premier lot review PO (200 entrées) | M | 4b | CSV review + go/no-go PO |
| 5 | principal | Run le pipeline → produit `assets/kb/chabaka_kb.sqlite` (3 k entrées) | S | 4c | binaire SQLite + checksum |
| 6 | principal | Implémente `KbRepositorySqflite` (lecture, requêtes solver, copie asset → app dir) | M | 2, 5 | `lib/puzzle/kb/kb_repository_sqflite.dart` |
| 7 | qa | Tests unitaires `KbRepository` (requêtes, perf < 5 ms) + tests générateur R4 (toutes runs valides) | M | 3, 6 | `test/puzzle/kb_test.dart`, `test/puzzle/generator_r4_test.dart` |
| 8 | qa | Bench génération 7×7 sur device réel (CI iOS sim + Android emu acceptable V1) | S | 7 | rapport perf |
| 9 | apple | Vérif taille bundle iOS, ajout `assets/kb/*.sqlite` au xcassets si besoin | S | 5 | build iOS OK |
| 10 | android | Vérif taille appbundle, split ABI | S | 5 | build appbundle OK |
| 11 | qa | Audit éditorial assisté : script qui détecte runs validées par R4 mais "bizarres" (très rares) | S | 7 | rapport |

Légende effort : **S** = ≤ 0.5 j, **M** = 1–2 j, **L** = 3–5 j.

**Effort total estimé : 14–20 jours-homme** (si un seul dev), parallélisable sur 5–7 jours réels avec router (étapes 4a-c et 2-3 en parallèle, 9-10 en parallèle).

### Critères d'acceptation par étape

- **2** : interface compile, méthodes documentées.
- **3** : sur 100 seeds, ≥ 95 % de grilles 7×7 valides R1+R2+R4 en < 1 s.
- **4a-c** : pipeline reproductible (`make build-kb`), CSV review livrable au PO.
- **5** : SQLite < 10 MB, 3 000 entrées, 100 % R2 OK, 100 % R3 OK.
- **6** : `findMatching(pattern)` < 5 ms en moyenne sur 1 000 calls.
- **7** : tests R4 exhaustifs (toute run produite est dans la KB).
- **8** : génération 7×7 < 1 s p95 sur iPhone récent.
- **9-10** : builds release OK, taille app < 30 MB iOS / 25 MB Android.

### Risques

- **Sourcing licence** : Wiktionary/Wikipedia CC BY-SA → on doit créditer dans l'app (écran "À propos / Sources"). À ajouter au scope UI.
- **Qualité indices auto** : la 1ère phrase Wiktionary fait souvent un mauvais indice → review humaine indispensable, peut révéler que 3 k est trop ambitieux.
- **Backtracking pathologique** : sur grilles denses, l'algo peut exploser en temps. Mitigation : timeout dur 2 s + fallback taille réduite.
- **Géographie politique** : "Sahara", "Jérusalem" — exclure ou laisser ? À trancher PO.
- **Compatibilité sqflite web** : tests unitaires utilisent `sqflite_common_ffi` ; CI doit l'installer.

### Décisions PO requises (bloquantes ou semi-bloquantes)

1. **Volume V1** : 3 000 entrées OK ? ou viser plus haut (5 k) quitte à retarder ?
2. **Exclusions** : politique sensible / religion polémique / géopolitique (Sahara, Palestine) — règle stricte ou laisser au cas par cas ?
3. **Crédit licences** : ok pour ajouter un écran "Sources" mentionnant Wikipedia/Wiktionary CC BY-SA ?
4. **Difficulté** : V1 = un seul niveau ("moyen") ou différencier easy/medium/hard dès V1 ?
5. **Personnalités** : monde arabe prioritaire, ou équilibre 50/50 arabe/international ?
