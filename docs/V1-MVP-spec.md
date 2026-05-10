# Chabaka V1 MVP — Spec architect

> Produite le 2026-05-10 par "architect" (joué par agent principal car sous-agents pas encore actifs en session). À exécuter par `router` au prochain démarrage.

## Décisions PO (validées)

- **Scope** : MVP minimal — UNE grille du jour à résoudre, pas de bibliothèque, pas d'auth, sauvegarde locale uniquement.
- **Source des grilles** : génération automatique locale (pas de backend, pas de LLM runtime).
- **Variantes V1** : مسهمة عربية (arabe→arabe) seulement. Pas de bilingue dans la V1.
- **Plateformes V1** : iPhone + Android (pas de web pour la V1, mais on l'utilisera pour les tests E2E qa).

## Compréhension du besoin

App Flutter iOS+Android qui, au lancement, présente une grille مسهمة arabe générée localement (déterministe basée sur la date → "grille du jour"). L'utilisateur la résout au clavier arabe natif. Progression sauvegardée localement.

## Décomposition fonctionnelle V1

| Id | Fonctionnalité |
|---|---|
| F1 | Grille unique générée à l'ouverture, déterministe par date |
| F2 | Rendu RTL avec polices arabes lisibles (Cairo + Amiri) |
| F3 | Saisie 1 lettre arabe par cellule via clavier natif |
| F4 | Validation à la complétion + feedback succès/erreur |
| F5 | Persistance locale de la progression (reprise après fermeture) |
| F6 | Mode clair / sombre |

## Décomposition technique

| Module | Responsabilité |
|---|---|
| `lib/puzzle/` | Data model `Grid`, `Cell` (sealed: `ClueCell`, `LetterCell`), `Clue`, sérialisation JSON, normalisation arabe, validation |
| `lib/puzzle/generation/` | Algo génération greedy + backtracking, wordlist + dictionnaire d'indices (assets JSON) |
| `lib/puzzle/storage/` | Persistance progression via `hive` |
| `lib/ui/grid/` | Widget grille RTL, sélection cellule, highlight mot actif |
| `lib/ui/theme/` | Thème light/dark "papier de journal" |
| `ios/Runner/Info.plist` | `CFBundleLocalizations` += `ar`, `UIAppFonts` |
| `android/app/src/main/AndroidManifest.xml` | `supportsRtl="true"` (déjà présent), `values-ar/` |

## Choix d'architecture

- **State management** : **riverpod** (type-safe, modulaire). Écarté : `provider` (vieillit), `setState` brut (ne scale pas avec persistance).
- **Persistance** : **hive** (rapide, pas de SQL, sérialise objets). Écarté : `shared_preferences` (trop plat pour stocker un `Grid` avec userInput cellule par cellule).
- **Génération** : algo **greedy placement avec backtracking**, depuis wordlist JSON statique (~50 mots+indices initiaux à saisir manuellement, étendre par après). PAS de NLP runtime.
- **RTL** : `Directionality(textDirection: TextDirection.rtl)` à la racine, `EdgeInsetsDirectional` partout.
- **Polices** : Cairo (texte courant) + Amiri (titres), bundlées dans `pubspec.yaml`.
- Écarté de la V1 : backend, sync, génération LLM, bibliothèque, variante bilingue, auth.

## Workflow proposé (à exécuter par router)

```
Phase 1 — Fondation (paralléliser quand possible)
1.  puzzle    → data model + sérialisation JSON + normalisation arabe + validation     [pas de dépendance]
2.  design    → specs visuelles (palette light/dark, typo, états cellules, layout grille) [parallèle 1]
3.  apple     → locale ar Info.plist + polices Cairo/Amiri (UIAppFonts)                [parallèle 1+2]
3'. android   → locale ar Manifest + values-ar/ + polices via pubspec                  [parallèle 3]

Phase 2 — Logique de jeu
4.  puzzle    → wordlist + dictionnaire indices initiaux + algo génération             [dépend de 1]
5.  qa        → tests unitaires puzzle (data model, normalisation, validation, génération) [dépend de 1, 4]

Phase 3 — UI (à confier à l'agent principal — router NE délègue PAS au principal, il indique au PO)
6.  principal → theme Flutter d'après design + Directionality RTL                      [dépend de 2, 3, 3']
7.  principal → widget grille (3 types de cellules : ClueCell, LetterCell)             [dépend de 1, 6]
8.  principal → saisie clavier arabe + appel à validation à chaque saisie              [dépend de 7]
9.  principal → persistance progression via hive                                       [dépend de 1, 8]

Phase 4 — Tests
10. qa        → widget tests grille rendu + saisie                                     [dépend de 7, 8]
11. qa        → E2E web via chrome-devtools MCP : ouvrir l'app web, résoudre la grille [dépend de 8, 9]
```

## Critères d'acceptation V1

- [ ] L'app se lance et affiche une grille générée
- [ ] Saisie arabe possible cellule par cellule
- [ ] Détection complétion + feedback succès/erreur
- [ ] Mode sombre fonctionnel
- [ ] `flutter test` vert sur tous les modules
- [ ] Builds iOS (`flutter build ios`) et Android (`flutter build appbundle`) réussissent

## Risques & inconnues

- **Génération auto V1** : faisable mais les grilles seront "honnêtes", pas du niveau pro d'Abou Salma. Acceptable MVP. Si on veut du niveau pro dès V1, alternatives : pré-charger des grilles importées, ou plusieurs semaines sur l'algo.
- **Wordlist initiale** : ~50 mots+indices arabes à curer manuellement = ~3-4h de travail produit. Peut être délégué à `puzzle` qui génère un brouillon, le PO valide.
- **Clavier arabe natif** : l'utilisateur doit avoir activé le clavier arabe dans ses settings OS. À expliquer dans un onboarding minimal.
- **Tests E2E** : `qa` aura besoin de chrome-devtools MCP qui n'est actif qu'après restart Claude Code.

## Comment relancer le workflow après restart

Au prochain démarrage de Claude Code, l'utilisateur peut envoyer :

> `@router : exécute le workflow défini dans docs/V1-MVP-spec.md`

`router` lira ce fichier, validera le plan, et démarrera Phase 1. Il pourra adapter en cours selon les retours des spécialistes.
