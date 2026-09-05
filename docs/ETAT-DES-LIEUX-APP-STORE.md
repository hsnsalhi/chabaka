# Chabaka — état des lieux et chemin vers l'App Store

> Rédigé le 2026-09-05 après import du dépôt local dans `hsnsalhi/chabaka` (63 commits, 9 → 13 mai 2026).
> Audit réalisé sur un clone propre avec Flutter 3.47.2 stable et Rust stable. Le projet épingle Flutter 3.41.9 ; les écarts liés à la version sont signalés.

---

## 1. Le produit

**Chabaka (شبكة)** est une application mobile de **mots fléchés arabes (الكلمات المسهمة)**, inspirée des grilles d'**أبو سلمى / Abou Salma** publiées dans le journal marocain **الاتحاد الاشتراكي**.

Ce qui la distingue d'un jeu de mots croisés générique :

- Le format مسهمة : pas de case noire, les **cases-définition** (avec flèche) servent de bloqueurs. Une case-définition peut porter deux indices empilés. Quatre types de flèches (modèle « B » diagonal d'Abou Salma).
- **100 % hors ligne, sans compte, sans backend.** Les grilles sont **générées sur l'appareil** à partir d'une base de connaissances SQLite embarquée (~6 400 entrées mot + indice, 3,2 Mo) réparties en 20 catégories thématiques.
- Règles éditoriales strictes codées dans le générateur : R1 (toute case est utile), R4 (toute suite de lettres est un mot valide), R5 (pas de case noire), R7 (jamais plus de deux cases-définition consécutives), pas de lettre orpheline.
- Interface entièrement en **arabe, RTL natif**, polices Cairo et Amiri, trois thèmes (clair, sombre, sépia).

### Fonctionnalités présentes dans le code

| Domaine | Contenu | État |
|---|---|---|
| Grille du jour | 13×9, seedée par la date, cache Hive, pré-génération de la grille du lendemain | Implémenté |
| Partie rapide | 4 difficultés (taille, indices, chrono, multiplicateur), filtre par thèmes | Implémenté, scores non persistés |
| Saisie | Clavier arabe natif, avance automatique, bascule H/V, retour arrière intelligent, zoom | Implémenté |
| Score, streak, 12 succès | Calcul, persistance Hive, écran stats avec graphe 7 jours | Implémenté, bugs (voir §3) |
| Calendrier | Écran codé | Inaccessible (lien du menu pointe vers l'accueil) |
| Réglages | Thème, son, haptique, réinitialisation, à-propos | Implémenté |
| Audio | Service complet | Muet : aucun fichier dans `assets/sounds/` |
| Onboarding, splash | Implémentés | Sous-titre français sur le splash |
| Partage du résultat | Copie presse-papier | Stub en attendant `share_plus` |
| Variante bilingue fr→ar | Prévue dans le modèle de données | Non implémentée (hors V1, décision PO) |

### Architecture

```
lib/
├── main.dart              Hive + 5 services injectés via Riverpod, RTL global
├── app/router.dart        go_router : splash → onboarding → home → game → result, stats, settings, calendar
├── puzzle/                Moteur Dart pur (modèles, normalisation arabe, validateur, KB SQLite)
│   └── generation/        4 générateurs ; seul TrueInterleavedGenerator (V7) est câblé à l'UI
├── data/                  GameOptions, SettingsService, ScoreService, StreakService (Hive)
├── core/                  AchievementService, AudioService, HapticsService
└── ui/                    Écrans + thème (chabaka_theme / chabaka_colors / text_styles)

rust/chabaka_engine/       Solveur AC-3 + MRV (spec V2). Compile, 12 tests unitaires OK,
                           mais AUCUN appel FFI depuis Dart : moteur non branché.
tools/kb-builder/          Pipeline Python CSV → SQLite (seed 6 392 entrées, 88 chunks thématiques)
```

---

## 2. Verdict : l'app n'est pas publiable en l'état

Le dernier commit (« Phase D ») **ne compile pas**. `flutter analyze` remonte 23 erreurs :

- `ChabakaColors.indigo`, `indigoDark`, `indigoLight` sont utilisés à 16 endroits (`home_screen`, `settings_screen`, `stats_screen`, `calendar_screen`, `quick_setup_screen`) mais **n'existent pas** dans `lib/ui/theme/chabaka_colors.dart`. La palette a été renommée bordeaux/or en Phase A et les écrans de Phase C/D ont été écrits contre l'ancienne palette sans jamais être compilés.
- `CupertinoPageTransitionsBuilder` dans `chabaka_theme.dart:233` : erreur uniquement avec Flutter 3.47, où la classe a été déplacée dans la bibliothèque cupertino. Avec le Flutter 3.41.9 épinglé par le projet, cette ligne compile. Ajouter `import 'package:flutter/cupertino.dart'` pour être compatible avec les deux versions.

Résultats des vérifications sur clone propre :

| Vérification | Résultat |
|---|---|
| `flutter analyze` | 23 erreurs, 1 warning, 38 infos |
| `flutter test test/puzzle` | 135 réussis, 5 échoués (tous des tests de performance : grilles 12×12, 16×16, 12×16 et 16×13 non résolues en 40 s à 9 min ; 8×8 résolue en 68 ms) |
| `flutter test` complet | Impossible : les fichiers UI ne compilent pas |
| `cargo test` (moteur Rust) | 12 tests unitaires OK, test de performance 8×8 échoué (30 s sans solution) |

Signes que le build iOS n'a pas été refait depuis la Phase D :

- `ios/Podfile.lock` ne contient ni `audioplayers_darwin` ni `path_provider_foundation`, donc `pod install` n'a pas tourné après l'ajout de ces dépendances.
- Les fichiers de test UI (`test/ui/grid/test_*.dart`) ne suivent pas le suffixe `_test.dart` et **ne sont jamais exécutés** par `flutter test`. Ils importent en plus `grid_screen.dart`, écran obsolète non routé.

---

## 3. Défauts à corriger avant soumission

### Bloquants (l'app ne se lance pas ou trompe l'utilisateur)

1. **Compilation** : ajouter `indigo`, `indigoDark`, `indigoLight` à `ChabakaColors` ou, mieux, remplacer les 16 usages par les tokens bordeaux/or de la palette officielle.
2. **Chrono du mode quotidien jamais démarré** (`game_options.dart:156` renvoie `null` en daily, `game_screen.dart:76` ne lance donc rien) : `timeMs = 0` au résultat, ce qui débloque systématiquement les succès « speedster » et « perfect_score » dès la première grille.
3. **Déterminisme de la grille du jour cassé** : `puzzle_providers.dart:70` mélange un `randomStart` basé sur l'horloge dans la boucle de 100 seeds. Deux téléphones n'auront pas la même grille le même jour, ce qui vide de sens le partage de score et le calendrier.
4. **Temps de génération sur appareil** : la grille 13×9 est calculée en Dart au premier lancement. À mesurer sur un iPhone d'entrée de gamme avant soumission ; si > 5 s, prégénérer un lot de grilles à l'install ou embarquer des grilles précalculées.

### Importants (qualité perçue, risque de rejet)

5. **Icône et écran de lancement** : ce sont les fichiers **par défaut de Flutter** (icône 1024 px de 10,9 Ko, `LaunchImage.png` de 68 octets). Apple rejette les apps avec l'icône placeholder Flutter.
6. **Sons absents** : `assets/sounds/` ne contient qu'un `.gitkeep`. Soit ajouter `click`, `letter`, `complete`, `unlock` en mp3, soit retirer l'option « son » des réglages.
7. **Calendrier inaccessible** : `home_screen.dart:48` pointe vers `AppRoutes.home` au lieu de `AppRoutes.calendar`.
8. **Scores des parties rapides jamais enregistrés** : la box `scores_quick` est ouverte mais jamais écrite, donc l'écran stats les ignore.
9. **Texte français sur le splash** (`splash_screen.dart:186`, « Mots Fléchés Arabes ») dans une interface 100 % arabe.
10. **Orientation** : `Info.plist` autorise le paysage sur iPhone. Pour une grille, verrouiller en portrait évite des mises en page cassées visibles par le reviewer.

### Nettoyage (dette, pas bloquant)

- Supprimer le code mort : `lib/ui/placeholder/*`, `lib/ui/grid/grid_screen.dart`, `lib/ui/theme/app_theme.dart` et `colors.dart`, `generator.dart` + `wordlist.dart`, `interleaved_generator.dart`, `topology.dart` (garder si la V2 Rust reprend).
- Renommer les tests UI en `*_test.dart` et les reporter sur `GameScreen`.
- `validator.dart:90` indexe `solution[i]` par code unit alors que la longueur vient de `runes.length` : décalage possible après normalisation.
- Décider du sort de `rust/chabaka_engine` : non branché, et son test de performance échoue (8×8 non résolu en 30 s). Soit le brancher via `dart:ffi` selon `docs/V2-FFI-Rust-spec.md`, soit le retirer du dépôt pour ne pas embarquer une dette de build (NDK, xcframework).
- `.claude/scheduled_tasks.lock` ne devrait pas être versionné.

---

## 4. Configuration iOS à compléter

| Élément | État actuel | À faire |
|---|---|---|
| Bundle ID | `com.mainlyb.chabaka` | OK, à créer dans App Store Connect |
| Équipe de signature | Aucun `DEVELOPMENT_TEAM` dans le pbxproj | Sélectionner l'équipe dans Xcode (signing automatique) |
| Cible iOS minimale | pbxproj : 13.0, Podfile : 14.0 | Aligner sur 14.0 (CLAUDE.md) |
| Version | `1.0.0+1` dans pubspec | OK, incrémenter le build à chaque upload |
| Icône | Placeholder Flutter | Fournir une icône 1024×1024 (`flutter_launcher_icons`) |
| Launch screen | Placeholder Flutter | Storyboard aux couleurs crème/bordeaux |
| Chiffrement | `ITSAppUsesNonExemptEncryption` absent | Ajouter `false` dans Info.plist (aucun chiffrement propriétaire) |
| Privacy manifest | Aucun `PrivacyInfo.xcprivacy` côté app | Ajouter un manifeste vide (aucune donnée collectée) ; les plugins en fournissent un |
| Localisations | `ar`, `fr`, `en` déclarées | Garder `ar` seul tant que l'UI n'est pas localisée |
| Orientations | Portrait + paysage sur iPhone | Portrait seul recommandé |
| Podfile.lock | Obsolète | Régénéré automatiquement par `flutter build ios` |

Android, pour mémoire : la release est signée avec la **clé debug** (`build.gradle.kts:56`) ; un keystore de release est indispensable avant le Play Store.

---

## 5. Plan de publication App Store

### Étape 0 — Prérequis compte (à faire en parallèle, délais Apple)
- Inscription à l'**Apple Developer Program** (99 $/an), vérification d'identité parfois longue.
- Créer l'app dans **App Store Connect** avec le bundle ID `com.mainlyb.chabaka`.
- Héberger une **politique de confidentialité** (URL obligatoire même sans collecte ; une page GitHub Pages suffit).

### Étape 1 — Rendre le build vert (1 à 2 jours)
- Corriger les 23 erreurs de compilation (§3.1), le chrono daily (§3.2), le déterminisme (§3.3).
- Renommer et réparer les tests UI, `flutter analyze` et `flutter test` verts.
- Mettre en place une **CI GitHub Actions** : `flutter analyze` + `flutter test` sur chaque push, pour que ce genre de régression ne revienne pas.

### Étape 2 — Finition produit (2 à 4 jours)
- Icône, launch screen, sons, calendrier, scores rapides, texte du splash, portrait.
- Mesurer la génération sur appareil réel et décider : génération à la volée, prégénération à l'install, ou grilles embarquées.
- Test de bout en bout sur iPhone physique : première ouverture, grille complète, relance après fermeture, changement de thème.

### Étape 3 — Configuration iOS et TestFlight (1 jour)
- Signing automatique, cible 14.0, Info.plist (chiffrement, orientation, privacy manifest).
- `flutter build ipa` puis upload via Xcode ou Transporter.
- Distribuer à quelques testeurs TestFlight ; corriger les retours.

### Étape 4 — Fiche App Store et soumission (1 jour)
- Captures d'écran 6,7" et 6,5" (et 12,9" si iPad reste activé ; sinon retirer l'iPad de `TARGETED_DEVICE_FAMILY`).
- Nom, sous-titre, description et mots-clés en arabe (et français en secondaire).
- Classification d'âge 4+, catégorie Jeux / Mots, « Aucune donnée collectée » dans la section confidentialité.
- Mention d'inspiration Abou Salma / الاتحاد الاشتراكي : les grilles sont générées, pas copiées, mais éviter tout logo ou nom du journal dans les visuels de la fiche.

### Estimation
Avec un développeur à temps plein : **5 à 8 jours ouvrés** de travail avant le premier envoi TestFlight, puis la revue Apple (24 à 72 h en général).

---

## 6. Commandes de référence

```bash
# Sur le Mac (Flutter 3.41.9, Xcode 26.4.1, CocoaPods via rbenv)
flutter pub get
flutter analyze
flutter test
cd ios && pod install && cd ..
flutter build ipa --release        # génère build/ios/ipa/chabaka.ipa
open build/ios/archive/Runner.xcarchive   # ou upload via Transporter
```
