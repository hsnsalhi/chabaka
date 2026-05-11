# Synthèse session nocturne 2026-05-10 → 2026-05-11

> Pour le PO à son réveil. Le user a dit "vise 300x500, t'as toute la nuit,
> prends les décisions toi-même".

## Ce qui marche maintenant

L'app Chabaka V1 tourne sur simulateur iOS avec une **vraie chabaka 8×8**
(structure Abou Salma) :

- **24 indices** culturels variés (sciences, géographie, anatomie, histoire, idiomes…)
- **R1 + R4 strict** respectés : aucun run accidentel de lettres sans clue
- **Bloqueurs visuels** (cases gris foncé) comme dans les vraies grilles d'Abou Salma
- **Auto-advance** : on tape une lettre → la sélection avance à la case suivante du mot actif
- **Direction toggle** : re-tap sur une intersection bascule H↔V
- **Backspace retreat** : recule + efface si la case actuelle est vide
- **Clue bar** persistante en haut : indice du mot actif en gros + flèche directionnelle + progress dots
- **Cache Hive** : 1er launch = ~3s, ensuite = instantané
- **Pré-cache** : la grille du lendemain est générée en background pendant que vous jouez

## Limites V1 actuelles

- **Taille max device** : 8×8 par défaut (UX < 5s). Le moteur supporte 12×16 et 16×16
  (testés OK en ~15-30s) mais c'est trop long pour un lancement sur device en debug.
- **20×20+** : timeout (algo et/ou KB pas encore prêts pour cette taille).
- **KB** : 1229 entrées V1. Spec PO = 5000 entrées (task #13 toujours pending).

## Architecture / décisions techniques de la nuit

### 1. Algorithme MRV (Most-Restricted Variable)
- `lib/puzzle/generation/topology.dart` : refonte de `_fillMRV` qui choisit
  dynamiquement le slot avec le moins de candidats à chaque pas. Élimine
  l'explosion exponentielle du backtracking.
- Gains mesurés : 4×4 5s→200ms, 8×8 timeout→0.5s, 12×16 timeout→15s.

### 2. Tuilage automatique pour grandes grilles
- `_buildTiledPattern(rows, cols)` : assemble des sous-régions 4×4
  indépendantes pour toute grille `rows%4==0 && cols%4==0`. Les tuiles
  ne partagent aucune cellule donc se résolvent presque indépendamment.

### 3. Knowledge Base enrichie
- `tools/kb-builder/seed/chabaka_seed.csv` : 264 → 1229 entrées (+965)
- `assets/kb/chabaka_kb.sqlite` : 136 KB → 536 KB
- Distribution : len-3 (111→361), len-4 (64→291), len-5 (38→239), len-6 (19→109), len-7 (19→85)
- Catégories : vocab common dominant, personnalités (priorité monde arabe), géo
  (villes/pays/capitales), sciences, arts, histoire — exclusions politiques strictes respectées.

### 4. UX Option A (validée par l'agent design)
- One TextField per cell mais navigation auto via Riverpod state + ref.listen
- Le clavier OS reste ouvert entre les cellules d'un même mot
- Direction active stockée dans `PuzzleState.activeDirection`
- Clue bar avec progress dots (un cercle par lettre du mot, plein si rempli, contour rouge si sélectionnée)

### 5. Pré-cache lendemain
- `_warmupTomorrowCache` lancé en `Future.microtask` après chargement de la grille du jour
- Hive box `grid_cache`, key = `day-{seed}`
- Best-effort : pas de log si échoue, l'app fonctionne pareil

## Tests

- **102 tests "principaux"** (puzzle engine + R4 generator + smoke patterns)
- **12 widget tests** ajoutés par l'agent qa : loading screen, clue bar, auto-advance, direction toggle, backspace retreat
- Tous verts en `flutter test`. Analyzer clean (4 warnings pré-existants de "dangling library doc comment" — inoffensifs).

## Commits de la nuit (récents → anciens)

```
310f78d  UX polish : pré-cache la grille du lendemain en background
f669002  UX polish : progress dots dans la clue bar (+ widget tests qa)
10ea15c  UX option A : auto-advance + clue bar + direction toggle
5512ba3  Push performance + scale : 8×8 tuilé V1, KB 1229 entrées, MRV + cache
2631a9b  Étend la wordlist de 264 à 1229 entrées (+965 mots arabes)
cf8e228  R4 strict : pattern validation + 3 patrons 4×4 + cellSize 64pt
```

## Ce qui reste pending (tasks)

- **#5** PO : suite des règles R5+ (à dicter)
- **#6** PO : valider option UX A (✅ implémentée — à valider visuellement)
- **#8** Phase 4 qa (E2E + non-régression supplémentaires)
- **#13** PO/éditorial : pousser KB vers 5000 entrées (puzzle agent v2 a stallé à mi-chemin)

## Pour pousser à 12×16 (Abou Salma typical) sur device

Si tu veux activer 12×16 en production, deux options :

**a)** Changer la default dans `lib/ui/grid/puzzle_providers.dart` ligne
  `TopologyConfig.forDate(today, rows: 8, cols: 8)` → `rows: 12, cols: 16`.
  Premier launch = 30-90s d'attente. Avec le pré-cache, les jours suivants
  instantanés. Risque : utilisateur impatient ferme l'app.

**b)** Pré-générer 7 jours de grilles à l'install (job d'onboarding qui
  affiche un screen "préparation des 7 prochaines chabakas..."). Plus
  propre côté UX mais demande dev supplémentaire.

Je recommande (a) avec un message d'attente plus rassurant pour le premier
launch + une option "passer à 8×8 si trop lent" en settings.

## Pour aller à 5000 entrées KB

L'agent puzzle v2 a stallé à 556/1200 entrées (timeout watchdog 600s).
Solutions :

1. **Re-lancer l'agent en plusieurs chunks** plus petits (~200 entrées chacun)
2. **Édition manuelle** du CSV par le PO (long mais plus fiable)
3. **Brancher un pipeline Wiktionary AR** (cf. README de `tools/kb-builder/` —
   demande dev Python ~1 jour)
