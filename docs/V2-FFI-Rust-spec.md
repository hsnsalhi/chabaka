# V2 — Réécriture du moteur de génération en Rust + dart:ffi

> Spec architect, 2026-05-11. PO : Hassane. Pas de code dans ce doc — uniquement
> spec exécutable par 3-4 agents en parallèle. Référence V1 : `docs/V1-MVP-R4-spec.md`.

---

## 1. Compréhension du besoin

Le moteur R4 actuel (Dart pur, MRV + forward checking + patrons tuilés) ne
converge pas pour la cible Abou Salma 16×13 (208 cellules, 61 ClueCells, ~50-60
slots ≥2) **dans un budget acceptable** : 12 min sans solution alors qu'on
dispose d'une KB de 4843 entrées indexées (table `letter_index` 27 792 lignes).
Le bottleneck mesuré est la combinaison de :
  - Cost d'un appel `kb.findMatching` (~quelques ms via `sqflite` Dart sur device),
    multiplié par O(slots × branches explorées).
  - Surcoût du runtime Dart sur opérations bit/hash dans la boucle backtrack.
  - Absence d'AC-3 (propagation au-delà du forward check de profondeur 1) → on
    explore des branches mort-nées.

**Objectif V2** : réécrire le solver en **Rust natif** appelé via `dart:ffi`,
viser ≤ 2 min sur iPhone 12+ (P95) et ≤ 4 min sur Android milieu de gamme,
**sans changer l'API publique** côté Flutter (drop-in remplacement de
`R4Generator.generate(TopologyConfig)`).

Tout le reste — Hive, riverpod, UI, KB SQLite — reste inchangé.

## 2. Questions au PO (déjà tranchées / hypothèses retenues)

Pas de question bloquante. Hypothèses prises :

- **H1** — On garde la KB SQLite existante telle quelle (schéma `entries`,
  `clues`, `letter_index`). Le Rust la lit en read-only via `rusqlite`.
  Justification : éviter de dupliquer la KB en format custom binaire et
  conserver `tools/kb-builder/build_kb.py` inchangé.
- **H2** — Le Rust expose une API **synchrone** côté C ABI ; le wrapper Dart
  l'exécute dans un `Isolate.run` (ou `compute()`) pour ne pas bloquer l'UI.
  Justification : le solver est CPU-bound non-cancellable côté algo ; pas
  besoin d'async réentrant. Simplification massive du FFI.
- **H3** — Cibles binaires V2 : `aarch64-apple-ios` (device), `aarch64-apple-ios-sim`
  (simulator M-series), `x86_64-apple-ios` (simulator legacy Intel, optionnel),
  `aarch64-linux-android`, `armv7-linux-androideabi`, `x86_64-linux-android`
  (emulator). Pour le dev macOS host (tests Dart desktop) : `aarch64-apple-darwin`.
  Pas de Windows / Linux desktop V2.
- **H4** — On porte `search_full_patterns.py` en Rust **en option différée** :
  le Rust solver consomme les patrons embarqués dans `topology.dart` (const
  `_patterns*`). Le portage SA est utile pour la suite (autres tailles, A/B
  testing patrons) mais n'est pas bloquant pour atteindre la cible perf.
  **Toutefois** la nouvelle contrainte R7 (cf. H7 ci-dessous) impose de
  **régénérer** les patrons existants — voir § 6-bis pour le plan.
- **H7 (NOUVEAU — PO 2026-05-11)** — **Règle R7 patterns** : dans tout pattern
  généré, **aucune séquence de plus de 2 ClueCells consécutives** n'est
  autorisée, ni horizontalement ni verticalement. Autrement dit : runs de `C`
  de longueur ≥ 3 interdits dans les deux axes. Justification PO : esthétique
  proche des vraies grilles Abou Salma (pas de « pavés » d'indices alignés),
  meilleure répartition visuelle des cellules de saisie. **Audit** : les
  patrons actuels (`_patterns16x13`, `_patterns8x8`) **violent** R7 (voir
  § 6-bis pour le détail). Ils doivent être régénérés.
- **H5** — Pas de `flutter_rust_bridge` (FRB) → **FFI manuel**. Justification
  détaillée § 5.1.
- **H6** — Le moteur Dart actuel **reste fonctionnel** comme fallback (feature
  flag `useRustEngine`, défaut true ; bascule auto sur Dart si la lib échoue
  à charger ou si l'init Rust retourne une erreur).

## 3. Décomposition fonctionnelle

| Id | Fonctionnalité                                                                    |
|----|-----------------------------------------------------------------------------------|
| F1 | Lib Rust `chabaka_engine` qui compile en `.dylib` / `.so` / `.dll` (test host)     |
| F2 | Backtracking MRV + forward checking + AC-3 en Rust, lecture KB SQLite             |
| F3 | API C ABI minimale exposée par la lib                                              |
| F4 | Bindings Dart `dart:ffi` + façade `RustR4Generator implements R4GeneratorApi`     |
| F5 | Pipeline build : cargo cross-compile + intégration iOS (xcframework) et Android   |
| F6 | Feature flag runtime + fallback automatique au moteur Dart                         |
| F7 | Tests parité Dart vs Rust (même seed → même grille) sur tailles 4×4 → 8×8          |
| F8 | Régénération patterns existants pour respecter R7 (max 2 CC adjacentes)            |
| F9 | (optionnel V2.1) Portage `search_full_patterns.py` en Rust avec R7 intégrée        |

## 4. Décomposition technique (modules)

### 4.1 Côté Rust (`rust/chabaka_engine/`)

```
rust/
└── chabaka_engine/
    ├── Cargo.toml              # crate-type = ["cdylib", "staticlib"]
    ├── src/
    │   ├── lib.rs              # exports #[no_mangle] extern "C" + panic = abort
    │   ├── ffi.rs              # ABI : structs C, allocators, error codes
    │   ├── models.rs           # Slot, Pattern, Constraint, KbEntryLite
    │   ├── kb.rs               # rusqlite wrapper read-only + cache LRU candidats
    │   ├── solver/
    │   │   ├── mod.rs          # entry point solve(pattern, kb, seed, deadline)
    │   │   ├── mrv.rs          # heuristique slot selection
    │   │   ├── ac3.rs          # arc consistency, domain pruning
    │   │   ├── domain.rs       # bitset domaines par slot (BitVec) — clé perf
    │   │   └── state.rs        # letters grid + placed map + undo stack
    │   ├── normalizer.rs       # mirroir R3 (idempotent avec Dart)
    │   └── patterns.rs         # (V2.1 différé) SA port de search_full_patterns
    ├── benches/                # criterion : 8×8, 16×13
    └── tests/                  # tests Rust pur (sans FFI)
```

**Responsabilités** :
  - `lib.rs` — surface FFI : `engine_create`, `engine_solve`, `engine_free`,
    `engine_last_error`. `panic = "abort"` en release (pas d'unwind across FFI).
  - `solver/domain.rs` — **clé perf** : domaine de chaque slot représenté en
    bitset (Vec<u64>) sur l'index des entrées KB filtrées par longueur. AC-3
    travaille dessus sans realloc. Coût mémoire : ~600 octets / slot pour 4843
    entrées max, donc < 100 KB pour 60 slots.
  - `kb.rs` — précharge en RAM les colonnes `(id, word, length, word_display)`
    + map `length → Vec<entry_index>` + tableau `letter_index_compact[length][position][letter] → bitset` au lieu de re-requêter SQL pendant le solve. Coût RAM
    estimé : 27 792 lignes × ~16 octets = ~500 KB ; acceptable. Les `clues` ne
    sont chargées qu'à la fin (lookup par ID des entrées sélectionnées).
  - AC-3 itère sur les arcs (slot_i, slot_j) qui partagent une cellule, propage
    la contrainte letter[pos_in_i] == letter[pos_in_j] sur les bitsets.

### 4.2 Côté Dart (`lib/puzzle/generation/rust/`)

```
lib/puzzle/generation/
├── generator.dart                # façade existante (reste l'unique API publique)
├── topology.dart                 # R4Generator Dart pur — DEVIENT le fallback
├── rust/
│   ├── bindings.dart             # bindings dart:ffi générés/écrits à la main
│   ├── rust_r4_generator.dart    # RustR4Generator : même signature que R4Generator
│   ├── rust_engine_lib.dart      # DynamicLibrary.open() + lookup symbols
│   └── kb_path_provider.dart     # résout le chemin du fichier SQLite copié au 1er run
└── engine_selector.dart          # choisit Rust ou Dart selon flag + dispo lib
```

**Responsabilités** :
  - `bindings.dart` — `final class ChabakaEngineBindings { ... }` avec types
    `Pointer<...>` et `@ffi.Native<...>` typedefs. Pas de génération auto
    (ffigen) en V2 ; surface FFI suffisamment petite pour écrire à la main et
    auditer.
  - `rust_r4_generator.dart` — implémente la même API que `R4Generator` (méthode
    `Future<Grid?> generate(TopologyConfig)`), serialize les inputs, invoque
    `engine_solve` dans un Isolate via `Isolate.run`, désérialise le Grid.
  - `engine_selector.dart` — singleton qui :
    1. Tente `DynamicLibrary.open(...)` (nom plateforme-spécifique).
    2. Si OK et `engine_create` retourne 0 → renvoie `RustR4Generator`.
    3. Sinon log + renvoie le `R4Generator` Dart existant (fallback).

### 4.3 Build / distribution

  - **iOS** :
    - Cargo cross-compile via `cargo lipo` ou commande manuelle pour produire un
      **xcframework** `ChabakaEngine.xcframework` (slices : ios-arm64, ios-arm64-simulator).
    - Le xcframework est posé dans `ios/Frameworks/` (gitignored, généré par
      script) et référencé par CocoaPods via une podspec locale ou directement
      par `xcconfig` (link_with `-framework ChabakaEngine`).
    - Script `tools/build-rust/build_ios.sh` : `cargo build --release --target ...`
      pour chaque slice, puis `xcodebuild -create-xcframework`.
  - **Android** :
    - Cargo cross-compile via `cargo-ndk` pour `arm64-v8a`, `armeabi-v7a`,
      `x86_64`. Output `.so` posés dans `android/app/src/main/jniLibs/<ABI>/libchabaka_engine.so`.
    - `System.loadLibrary("chabaka_engine")` côté Java pas nécessaire car
      `DynamicLibrary.open("libchabaka_engine.so")` côté Dart suffit
      (Flutter Android charge automatiquement depuis jniLibs).
    - Script `tools/build-rust/build_android.sh`.
  - **macOS host (dev/tests)** :
    - `cargo build --release` produit `target/release/libchabaka_engine.dylib`.
    - Le test harness Flutter Dart desktop (`flutter test`) résout le chemin via
      `kb_path_provider.dart` en mode host.
  - **CI** : matrix `{ios-device, ios-sim, android-arm64, android-armv7,
    android-x86_64, macos-host}` ; cache `~/.cargo` et `target/` par cible.

## 5. Choix techniques

### 5.1 `flutter_rust_bridge` (FRB) vs FFI manuel — **FFI manuel**

| Critère                        | FRB                                       | FFI manuel                                 |
|--------------------------------|-------------------------------------------|--------------------------------------------|
| Surface API à exposer          | ~5-6 fonctions                            | ~5-6 fonctions                             |
| Génération de code             | macros build.rs + dart codegen            | écrit à la main une fois                   |
| Async natif Rust → Dart        | oui (Future, Stream)                      | non — on utilise Isolate.run côté Dart     |
| Coût d'apprentissage           | élevé (DSL, macros, codegen v2)           | faible (typedef + Pointer<...>)            |
| Audit & lecture                | difficile (code généré opaque)            | direct                                     |
| Stabilité 2026                 | v2 stable mais traînée breaking changes   | dart:ffi stable Dart 3.x                   |
| Build pipeline                 | ajoute `flutter_rust_bridge_codegen`      | rien de plus que cargo + cp                |

→ **Décision : FFI manuel**. Le solver expose une surface minuscule (1 fonction
solve qui prend un blob d'input et renvoie un blob d'output). FRB serait
sur-architecturé pour ce besoin et alourdirait le pipeline CI.

### 5.2 `rusqlite` vs KB préchargée en mémoire côté Rust — **les deux**

- **Init** : ouverture `rusqlite::Connection` en read-only sur le fichier
  SQLite copié par Dart au 1er lancement. Dart **passe le chemin absolu** à
  `engine_create` (pas de duplication, pas de blob mémoire à transférer).
- **Avant solve** : `kb.rs` lit toute la KB **une fois** et construit les
  structures compactes (bitsets `letter_index`). La connexion SQLite est
  fermée. Aucune requête SQL pendant le backtracking.
- Pourquoi pas tout en mémoire dès le départ : (a) on évite de dupliquer 2 MB
  en RAM Dart + 2 MB en RAM Rust simultanément ; (b) la KB peut grossir
  (objectif V3 : 20 k entrées) — la lecture directe scale mieux.
- Pourquoi pas re-requêter SQL pendant le solve : un `findMatching` SQL coûte
  ~ms ; le solve fait 10 k+ appels. Tableaux compactés = O(1) per lookup.

### 5.3 Sync vs Async API FFI — **sync, Isolate côté Dart**

`engine_solve` est synchrone bloquante en Rust. Côté Dart, on l'appelle dans
`Isolate.run(() => bindings.solve(...))`. Avantages :
  - ABI minimaliste (pas de callbacks Rust → Dart sur main thread).
  - Pas de coordination de thread runtime Rust avec event loop Dart.
  - Annulation par timeout côté Dart : on passe `deadlineMs` au Rust qui
    check périodiquement ; au-delà, Rust retourne `kTimeout` proprement.
  - Pas d'annulation forcée mid-solve (acceptable : timeout 2 min ; si user
    cancel, on attend la fin du timeout naturel).

### 5.4 Données traversant la frontière FFI — sérialisation **MessagePack**

Plutôt que de définir 10 structs C avec arrays de strings (galère pour les
chaînes UTF-8 arabe + clues longs) :

- **Input** Dart → Rust : un blob MessagePack (ou JSON minifié — voir benchmark)
  contenant `{rows, cols, seed, deadlineMs, pattern: [...], kbPath: "..."}`.
- **Output** Rust → Dart : un blob MessagePack `{status, grid: {...}}` ou
  `{status: error, code, message}`.

Justification :
  - 1 seul allocator/freer côté Rust (alloc + free de pointeurs `*mut u8`).
  - Pas de problème de durée de vie de strings ni d'arrays nested.
  - Le coût de sérialisation est négligeable (< 1 ms sur grille 16×13).
  - Format Self-describing → audit facile via dump hex en cas de bug.
  - Alternative envisagée et écartée : `flatbuffers` (overkill ici), structs C
    plates (cauchemar pour les listes de clues de longueur variable).

→ **Choix** : MessagePack (crate `rmp-serde` côté Rust, `package:messagepack`
côté Dart). Fallback JSON acceptable si le package Dart pose souci.

### 5.5 Allocations mémoire FFI

Règle stricte : **celui qui alloue libère**.

- Rust alloue le buffer output → expose `engine_free_buffer(ptr, len)` que
  Dart appelle après lecture.
- Dart copie le blob output dans une `Uint8List` Dart-owned avant de free.
- Pas de pointeurs persistants Dart→Rust : tout le state Rust est porté par
  un `EngineHandle` opaque (created/destroyed par paire).

## 6. API FFI (signatures C ABI)

Signatures à implémenter côté Rust (`#[no_mangle] pub extern "C"`) et à
binder côté Dart. Tous les pointeurs sont non-owning sauf indication.

```c
// Opaque handle. Wraps Rust struct Engine { kb: KbCompact, rng_state, ... }.
typedef struct ChabakaEngine ChabakaEngine;

// Codes d'erreur (i32).
//   0  = OK
//   1  = NoSolution (timeout ou exhausted)
//   2  = InvalidInput (deserialization failed)
//   3  = KbOpenFailed
//   4  = InternalPanic (ne devrait jamais arriver — panic=abort)
//   5  = HandleInvalid
typedef int32_t ChabakaStatus;

// Crée un engine. kb_path_utf8 : zero-terminated path absolu vers le .sqlite.
// Renvoie NULL si init KB échoue (consultez engine_last_error()).
ChabakaEngine* engine_create(const char* kb_path_utf8);

// Détruit l'engine et libère toute mémoire owned.
void engine_destroy(ChabakaEngine* engine);

// Solve. input_msgpack : blob MessagePack alloué côté Dart (Rust ne free pas).
// out_ptr / out_len : Rust alloue, Dart doit appeler engine_free_buffer().
// out_ptr est NULL en cas d'erreur (consultez la valeur de retour).
ChabakaStatus engine_solve(
    ChabakaEngine* engine,
    const uint8_t* input_msgpack,
    uintptr_t      input_len,
    uint8_t**      out_ptr,
    uintptr_t*     out_len);

// Libère un buffer retourné par engine_solve.
void engine_free_buffer(uint8_t* ptr, uintptr_t len);

// Retourne un message d'erreur thread-local (ou NULL). Static buffer interne
// au crate ; ne pas free. Valide jusqu'au prochain appel FFI.
const char* engine_last_error();

// Version de la lib pour audit (ex: "0.1.0-2026-05-11"). Static.
const char* engine_version();
```

**Forme MessagePack — input** :
```
{
  rows: u16,
  cols: u16,
  seed: u64,
  deadline_ms: u32,
  max_retries: u8,
  pattern_kinds: [u8; rows*cols],   // 0=letter, 1=clue, 2=blocker
}
```

**Forme MessagePack — output succès** :
```
{
  status: 0,
  cells: [                          // row-major
    {kind: 0|1, letter?: str, kb_id?: u32, slot_dir?: u8, slot_len?: u8},
    ...
  ],
  placed: [                         // pour reconstruire les clues côté Dart
    {kb_id: u32, slot_row: u16, slot_col: u16, dir: u8, len: u8},
    ...
  ],
}
```

Côté Dart, `RustR4Generator._buildGrid()` consomme `placed[]`, requête les
`KbClue.text` via le `KbRepository` existant (Dart sqflite garde son rôle pour
les clues UI — le Rust ne renvoie que les IDs). Cela évite de dupliquer la
logique de chargement des indices dans Rust.

## 6-bis. Contrainte R7 sur les patterns (PO 2026-05-11)

### 6-bis.1 Énoncé

Dans tout pattern de grille مسهمة Chabaka, **aucune séquence ≥ 3 ClueCells
consécutives** n'est autorisée, ni horizontalement ni verticalement.
Formellement, pour tout `(r, c)` et toute direction `d ∈ {H, V}` :

> Si `pattern[r][c] = pattern[r±1][c] = pattern[r][c±1] = … = Clue` sur 3 cases
> alignées contiguës → pattern **invalide**.

Les paires de 2 CCs adjacentes restent autorisées (sinon trop restrictif sur les
grilles denses).

### 6-bis.2 Audit des patterns existants

Vérifié via script (2026-05-11) :

| Pattern              | Violations H | Violations V | Statut |
|----------------------|--------------|--------------|--------|
| `_patterns16x13[0]`  | 2 (run len=3 row 0)            | 0          | **INVALIDE R7** |
| `_patterns8x8[0]`    | 2 (run len=4 row 0, len=3 row 1) | 0        | **INVALIDE R7** |
| `_patterns8x8[1]`    | 0                            | 2 (run len=4 col 0, len=3 col 1) | **INVALIDE R7** |
| `_patterns4x4[*]`, `_patterns5x5[*]`, `_patterns7x7[*]` | à auditer | à auditer | tâche puzzle |
| Tuilage `_buildTiledPattern` (rows×cols ≥ 12×12) | 0 par construction (header row 0 = `BCCC…C` → exactement run len = cols-1, **INVALIDE** dès cols ≥ 4) | 0 | **INVALIDE R7** |

→ **Tous les patrons existants ≥ 8×8 sont à régénérer** ou à corriger
manuellement. Le tuilage automatique `_buildTiledPattern` doit être **désactivé**
(ou réécrit) car il génère par construction une row d'en-tête `CCCC…C`
incompatible avec R7.

### 6-bis.3 Implication sur la stratégie patrons

Deux options :

- **Option A (V2 minimale)** — Régénérer manuellement / via SA Python existant
  les patrons 8×8 et 16×13 en ajoutant R7 au validator `is_valid()` de
  `tools/kb-builder/search_full_patterns.py`. Le fichier `topology.dart` est mis
  à jour avec les nouveaux const. Pas de changement runtime Rust.
- **Option B (V2.1)** — Port complet du SA en Rust (étape 5) qui inclut R7
  nativement et peut générer à la volée.

→ **Décision** : Option A en V2 (rapide, déterministe, débloque tout le reste).
Option B reste en option V2.1.

### 6-bis.4 Modification de `is_valid()` dans le SA Python

Ajouter dans `tools/kb-builder/search_full_patterns.py` une nouvelle clause :

```
# R7 (PO 2026-05-11) : max 2 CC adjacentes en H et V.
for r in range(rows):
    run = 0
    for c in range(cols):
        run = run + 1 if grid[r][c] == "C" else 0
        if run >= 3: return False
for c in range(cols):
    run = 0
    for r in range(rows):
        run = run + 1 if grid[r][c] == "C" else 0
        if run >= 3: return False
```

Et **ajouter au scoring** (`composite_score`) une pénalité forte pour les paires
adjacentes au-delà d'un quota raisonnable, pour éviter de simplement remplacer
des triplets par beaucoup de doublets.

### 6-bis.5 Propagation au solver Rust

Le solver Rust **n'a pas à connaître R7** : la règle s'applique au pattern en
amont (validé à la génération par le SA Python ou par le futur SA Rust).
Le solver reçoit un pattern déjà conforme. Si jamais un pattern non conforme
arrivait (bug, pattern legacy), le Rust **ne refuserait pas** ; c'est un check
purement esthétique de génération, pas une contrainte de solvabilité.

**Cependant**, on ajoute un **assert debug-only** côté Dart juste avant
l'appel FFI : `assertNoTripleClueRun(pattern)` → throw si violation. Garde-fou
contre régression silencieuse.

## 7. Plan de migration (Dart existant reste fonctionnel à chaque étape)

Approche **strangler fig** : on greffe le moteur Rust derrière une façade, on
bascule via flag, on garde le Dart en fallback.

```
Étape 0 — pré-migration
  - Créer interface Dart abstraite `R4GeneratorApi` (méthode `generate`).
  - Faire implémenter cette interface par l'existant `R4Generator` (renommé
    `DartR4Generator`).
  - Pas de changement comportemental.

Étape 1 — squelette Rust + FFI bouchon
  - Crate `rust/chabaka_engine` qui compile et expose les 5 fonctions
    FFI ci-dessus, mais `engine_solve` renvoie kNoSolution immédiatement.
  - Build scripts iOS + Android OK, .dylib/.so livrés et chargés.
  - Bindings Dart écrits, `RustR4Generator` créé qui appelle FFI mais retourne
    null. Engine selector branche au flag (default OFF : Dart).
  - Tests : `flutter test` reste vert, `flutter build ios/android` OK.

Étape 2 — Rust solver minimal (sans AC-3)
  - Port du MRV + forward checking en Rust, lecture KB via rusqlite (preload).
  - Sérialisation MessagePack input/output OK.
  - Activable via flag --dart-define=USE_RUST=1.
  - Tests parité : sur grilles 4×4, 5×5, 7×7, Rust et Dart doivent donner
    des grilles **valides** (pas forcément identiques — RNG diffère).
  - Critère : Rust ≥ 5× plus rapide que Dart sur 8×8.

Étape 3 — AC-3 + bitset domains
  - Ajout AC-3 en Rust, domaines bitset, tests Rust internes (criterion bench).
  - Cible : 16×13 résolu en < 2 min P95 sur iPhone 12.

Étape 4 — Flag ON par défaut + fallback robuste
  - `engine_selector` retourne RustR4Generator par défaut, Dart fallback si
    `DynamicLibrary.open` jette ou `engine_create` retourne NULL.
  - Tests QA E2E : forcer fallback (suppr .so) → grille Dart toujours générée
    (peut être 4×4 max, ce qui est OK).

Étape 5 — clean
  - Le code Dart `topology.dart` est conservé comme fallback. Les patrons const
    `_patterns*` sont déplacés dans `lib/puzzle/generation/patterns.dart`
    partagés entre les deux moteurs.

Étape 6 (V2.1, optionnelle) — porter search_full_patterns.py
  - Module `rust/chabaka_engine/src/patterns.rs` reproduit le SA.
  - CLI `cargo run --bin pattern-search -- --rows 16 --cols 13` qui émet
    le Dart const pour `_patterns16x13`. Remplace tools/kb-builder/search_*.py.
```

## 8. Workflow proposé (router orchestre)

Étape 0 est triviale (1 refactor Dart) → router peut dispatcher directement à
agent principal. Les étapes 1-5 sont les **chantiers parallélisables** réels.

```
-1. [pas de dépendance] puzzle — **R7 patterns** :
    (a) ajoute R7 au validator `is_valid()` de
        `tools/kb-builder/search_full_patterns.py` (clause max 2 CC adjacentes),
    (b) régénère les patterns `_patterns8x8` (≥ 2 variants) et `_patterns16x13`
        via SA (`python3 search_full_patterns.py --rows 16 --cols 13 --seeds 50`),
    (c) audite + corrige `_patterns4x4`, `_patterns5x5`, `_patterns7x7`,
        `_patterns5x4`, `_patterns4x5` (modifs manuelles si triviaux),
    (d) désactive ou réécrit `_buildTiledPattern` (header row 0 actuellement
        non conforme R7),
    (e) ajoute un test Dart `test/puzzle/generation/r7_compliance_test.dart`
        qui itère tous les const `_patterns*` et vérifie max 2 CC adjacentes.
    Livrable : `topology.dart` avec patterns conformes R7 + test vert.
    **Note** : ce chantier est indépendant du Rust et débloque la suite —
    sans patterns conformes, le solver Rust travaillerait sur des patterns
    invalides.

0.  [dépend de -1] agent principal — extrait l'interface R4GeneratorApi
    et renomme l'existant DartR4Generator. PR < 100 lignes.
    Livrable : interface stable que les deux moteurs implémentent.

1a. [pas de dépendance] puzzle — porte la KB en structure compacte Rust
    (kb.rs + design des bitsets letter_index). Rend un doc d'API interne Rust
    (signatures fonctions kb.rs) sans implémentation finale.
    Livrable : `rust/chabaka_engine/src/kb.rs` design + types.

1b. [pas de dépendance] puzzle — porte le solver MRV + forward check + AC-3
    en Rust (solver/, models.rs, state.rs).
    Livrable : crate Rust + tests Rust + bench criterion qui valide < 2 min sur 16×13.

1c. [pas de dépendance] apple — script tools/build-rust/build_ios.sh qui produit
    le xcframework ; intégration podspec + lookup pod ; doc README sur la chaîne
    de toolchain Xcode (rustup target add aarch64-apple-ios + aarch64-apple-ios-sim).
    Livrable : `flutter build ios` réussit avec lib bouchon liée.

1d. [pas de dépendance] android — script tools/build-rust/build_android.sh
    avec cargo-ndk, jniLibs/ par ABI, doc README sur installation NDK.
    Livrable : `flutter build apk` réussit avec lib bouchon liée.

2.  [dépend de 1a + 1b + 1c + 1d] agent principal — bindings dart:ffi
    (lib/puzzle/generation/rust/bindings.dart), façade RustR4Generator,
    engine_selector, sérialisation MessagePack côté Dart.
    Livrable : moteur Rust appelable depuis Dart, --dart-define=USE_RUST=1
    fait passer les tests existants en mode Rust.

3a. [parallèle, dépend de 2] qa — tests parité Dart/Rust : seed → grille valide
    sur 4×4, 5×5, 7×7, 8×8 ; tests fallback (lib manquante → Dart).
    Livrable : suite test/generation/engine_parity_test.dart + CI verte.

3b. [parallèle, dépend de 2] qa — bench device réel : 16×13 sur iPhone via
    chrome-devtools MCP n'est pas applicable ; à la place script
    `tools/bench/bench_engine.dart` exécuté via `flutter test integration_test`
    qui mesure P50/P95 sur 20 seeds.
    Livrable : rapport bench, validation critère < 2 min P95.

4.  [dépend de 3a + 3b] agent principal — flip du défaut à RustR4Generator,
    doc utilisateur, mise à jour CLAUDE.md.

5.  [optionnel, parallèle de 1-4] puzzle — port SA `search_full_patterns.py`
    → `rust/chabaka_engine/src/bin/pattern_search.rs`.
    Livrable : CLI Rust qui reproduit les patrons existants (parité output
    pour seed donné), mais 10× plus rapide.
```

**Note router** : les étapes 1a / 1b sont du Rust pur, peuvent être confiées à
l'agent puzzle (moteur algo Dart pur s'étend à Rust pur — même périmètre
« logique de génération sans plateforme »). Les étapes 1c / 1d sont
spécifiques plateforme. L'étape 2 (FFI Dart) est cross-platform Flutter glue
donc principal. Les benches sont qa.

## 9. Critères d'acceptation

- [ ] `flutter test` vert sur toutes les plateformes hôte (macOS + linux CI).
- [ ] `flutter build ios` + `flutter build appbundle` réussissent avec la lib
      Rust liée.
- [ ] Sur grille 16×13 avec KB 4843 entrées, P95 ≤ **120 s** (cible 60-90 s)
      sur iPhone 12+ ; P95 ≤ **240 s** sur Pixel 5 / équivalent.
- [ ] Sur grille 8×8 avec patrons SA existants, P95 ≤ **5 s** sur même device.
- [ ] Fallback Dart automatique si :
        - `DynamicLibrary.open` jette,
        - `engine_create` retourne NULL,
        - `engine_solve` retourne `InternalPanic`.
      → tests QA forcent chaque scénario.
- [ ] Parité fonctionnelle : pour 20 seeds × 4 tailles {4×4, 5×5, 7×7, 8×8},
      Rust et Dart produisent tous deux une grille valide (toutes contraintes
      R5 strict respectées). Pas d'égalité bit-à-bit exigée.
- [ ] **R7 patterns** : tous les const `_patterns*` de `topology.dart` passent
      le test `r7_compliance_test.dart` (max 2 CC adjacentes en H et V).
- [ ] `tools/kb-builder/search_full_patterns.py` rejette tout candidat
      violant R7 (`is_valid()` retourne False).
- [ ] Taille .ipa : delta vs V1 ≤ **3 MB** (lib Rust release + xcframework
      slices arm64 device + arm64 simulator). À mesurer avec
      `flutter build ios --analyze-size`.
- [ ] Taille .aab : delta vs V1 ≤ **2 MB par ABI**. À mesurer avec
      `flutter build appbundle --analyze-size`.
- [ ] Pas de fuite mémoire FFI : test integration qui appelle `generate` 100×
      consécutivement → RSS stable à ± 5 MB.

## 10. Risques identifiés

| # | Risque | Mitigation |
|---|--------|------------|
| R1 | **Build cross-compile cassé en CI** : rustup target install échoue ou cargo-ndk introuvable. | Pin versions exactes dans `rust-toolchain.toml` + script d'install reproductible. Tester sur Mac M-series ET runner Linux. |
| R2 | **iOS App Store rejette le binaire** : bitcode (deprecated mais encore vérifié), symbols manquants, archi non whitelistée. | Build avec `-arch arm64` strict, pas de bitcode (off depuis Xcode 14), strip symbols release, valider via `xcrun altool --validate-app` avant TestFlight. |
| R3 | **Taille .ipa explose** : Rust std + rusqlite + rmp-serde + sqlite linké statiquement peut ajouter 3-5 MB par slice. | (a) `lto = "fat"`, `codegen-units = 1`, `panic = "abort"`, `strip = true` dans Cargo.toml release. (b) Si rusqlite trop gros, alternative : Dart passe les rows déjà extraites à Rust (Rust ne link pas sqlite). À évaluer au benchmark étape 1a. |
| R4 | **SIGBUS / crash FFI** sur device : alignement mémoire, lifetime de strings, ownership croisé. | Règle stricte « celui qui alloue libère ». Pas de mutex Rust → Dart. Test Address Sanitizer + tests integration sur device dès étape 2. |
| R5 | **`rusqlite` pose problème de linkage iOS** (libsqlite3 dynamique vs bundled). | Feature `rusqlite/bundled` pour linker sqlite-amalgamation côté Rust et éviter de dépendre de la libsqlite3 du device (versions Android variables). |
| R6 | **Performance ne tient pas la cible 16×13 < 2 min** malgré AC-3 + bitsets. | Plan B en gradient : (a) augmenter la sélectivité MRV (sonder plus loin), (b) restart aléatoire au bout de 30 s, (c) si toujours pas → revoir la stratégie patron (slots plus courts), (d) ultimately accepter 3 min. |
| R7 | **Isolate.run + FFI = pénible** : l'Isolate ne peut pas partager un `ChabakaEngine*` Dart-side car les pointeurs ne traversent pas. | L'engine est créé **dans** l'isolate à chaque solve (l'init Rust = 1 seul SQL preload ≈ 100 ms ; acceptable). Si trop lent : passer la KB précompilée en bytes via `SendPort`. |
| R8 | **Le portage de search_full_patterns.py est sous-estimé** : SA + scoring composite + dispersion = 200+ lignes. | Différé en V2.1 (étape 5 optionnelle). Le V2 n'en a pas besoin pour atteindre la cible perf. |
| R9 | **Divergence Dart/Rust normalisation arabe** : R3 implémentée 2× → bugs subtils. | Tests parité dédiés : 1 000 mots passés dans les deux normalizers, comparaison char-par-char. CI gate. |
| R10 | **Dart 3 ABI change** (rare mais possible) → bindings cassent. | Pin Flutter à version exacte dans `pubspec.yaml`, CI matrix valide. dart:ffi est très stable depuis Dart 2.12. |
| R11 | **R7 trop restrictif** : la combinaison R5 strict (toute CC doit héberger un slot) + R7 (max 2 CC adjacentes) pourrait rendre certaines tailles dénses infaisables (pas de pattern valide trouvé par le SA). | Augmenter `--seeds` et `--iters` dans le SA. Si vraiment infaisable sur 16×13 : assouplir R5 localement (autoriser quelques CC orphelines sans slot) ou réduire la cible CC count. À mesurer empiriquement par puzzle à l'étape -1. |

## 11. Hors scope V2 (V3+)

- Génération de grilles en streaming avec progrès partiels affichables à l'UI.
- Multi-thread Rust (rayon) : V2 reste single-thread, gain pas évident sur
  backtrack-sequence-with-undo.
- Persistance de l'EngineHandle entre solves (warm KB cache cross-Isolate).
- WASM build pour la version web (V3).

---

**Statut** : spec prête à dispatcher. Router doit traiter dans l'ordre :
**-1 (puzzle : R7 patterns, bloquant)** → 0 (principal trivial) →
1a/1b/1c/1d (parallèle, 1a+1b puzzle ; 1c apple ; 1d android) → 2 (principal) →
3a/3b (qa parallèles) → 4 (principal) → 5 (puzzle optionnel, V2.1 port SA Rust).

L'étape -1 (R7) peut être lancée **immédiatement et en parallèle** des autres
chantiers de fondation : elle ne touche que `tools/kb-builder/` (Python) et
`lib/puzzle/generation/topology.dart` (const Dart). Aucune interférence avec
le travail Rust ou Flutter glue.
