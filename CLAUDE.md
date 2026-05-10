# Chabaka — contexte projet

App Flutter (iOS + Android) de **mots fléchés en arabe** (الكلمات المسهمة), inspirée des grilles d'**أبو سلمى / Abou Salma** publiées dans le journal marocain **الاتحاد الاشتراكي / Al Ittihad Al Ichtiraki**.

## Stack

- **Flutter 3.41.9** (stable, arm64) → `~/development/flutter`
- **Material 3** + **RTL natif** (`Directionality(textDirection: TextDirection.rtl, ...)`)
- Cibles : iOS 14+, Android 7+ (API 24+), web pour tests rapides
- Tests : `flutter test` (unit/widget), chrome-devtools MCP (E2E web)
- iOS : Xcode 26.4.1, CocoaPods 1.16.2 via rbenv (Ruby 3.3.5)
- Android : SDK à `~/Library/Android/sdk`, JBR Java 21 bundlé avec Android Studio

## Format des grilles مسهمة (à modéliser)

Spec déduite de vrais exemples dans `references/` :

- Grille rectangulaire RTL, taille variable (~13×16 typique).
- **3 types de cellules** seulement :
  1. **Clue cell** : texte (1 ou 2 indices empilés) + flèche `→` (horizontal RTL) ou `↓` (vertical).
  2. **Letter cell** : 1 lettre arabe à remplir.
  3. Pas de case noire — les clue cells servent de bloqueurs.
- **Variante مزدوجة (bilingue)** : indices en français, réponses en arabe (outil pédagogique).

## Conventions arabe / RTL (essentielles, lire avant tout code visible par l'utilisateur)

**Polices** :
- Texte courant : `Cairo` ou `Tajawal` (modernes, lisibles à petite taille)
- Titres / accent : `Amiri` (traditionnelle, élégante)
- Académique : `Scheherazade New`
- Éviter : `Noto Naskh Arabic` (rend mal sur petits écrans)

**Tailles & espacement** :
- Texte minimum lisible : 18px (vs 14-16 pour latin)
- Cellules-définition : 20-22px (texte souvent long)
- `lineHeight` 1.5–1.6 (l'arabe a besoin de plus que le latin 1.2)

**RTL** :
- Toujours wrapper le tree avec `Directionality(textDirection: TextDirection.rtl)` ou `Localizations` arabe.
- Les flèches/icônes directionnelles : utiliser `Icon(...)` cross-locale ou les mirrorer manuellement avec `Transform.scale(scaleX: -1, ...)`.
- Les paddings : utiliser `EdgeInsetsDirectional` (`.start`/`.end`) plutôt que `.left`/`.right`.

**Lettres dans la grille** :
- Chaque case = **lettre isolée** (forme finale isolée, sans shaping). Utiliser `TextDirection.rtl` mais texte d'**1 caractère** = pas de jonction.
- Si shaping pose problème : injecter le caractère ZWNJ (`‌`) ne marche pas pour isoler — utiliser une font avec lookup `isol` forcé, ou simplement ne mettre qu'un caractère par cellule (ce qui suffit dans 99% des cas).

**Normalisation à la validation de l'input utilisateur** :
- `ا أ إ آ` → tous équivalents à `ا` par défaut (paramétrable produit)
- `ة ه` → équivalents (paramétrable)
- `ى ي` → équivalents (paramétrable)
- Diacritiques (تشكيل : ◌َ ◌ِ ◌ُ ◌ْ ◌ّ etc.) → toujours ignorés
- ZWNJ/ZWJ et espaces → toujours ignorés

## Structure du repo

```
chabaka/
├── lib/                          # code Dart Flutter
├── ios/                          # projet Xcode
├── android/                      # projet Gradle
├── test/                         # tests unit + widget
├── references/                   # vrais exemples de grilles + spec
│   ├── grille_72.jpg             # grille standard arabe
│   ├── grille_double_11.jpg      # grille bilingue fr→ar
│   └── README.md                 # spec format
├── .claude/agents/               # sous-agents spécialisés
└── CLAUDE.md                     # ce fichier (chargé auto par tous les agents)
```

## Organigramme & modèle d'orchestration

```
PO (utilisateur humain)
   │
   ▼
router (chef de projet) ◀──────── chaque agent revient ici
   │                              avec son résultat
   │
   ├──▶ architect (tech lead) — décompose besoin flou + propose un workflow
   │
   └──▶ spécialistes (séquentiels ou parallèles selon les dépendances) :
           ├── design     (UI/UX visuel)
           ├── apple      (iOS-only)
           ├── android    (Android-only)
           ├── puzzle     (moteur Dart pur — data model, validation)
           └── qa         (tests autonomes : flutter test + chrome-devtools MCP)

agent principal — code Flutter/Dart cross-platform de glue.
                  Le PO lui parle directement (router ne lui délègue PAS).
```

**Modèle workflow** : router pilote un pipeline étape par étape. Chaque agent
reçoit un brief qui inclut les outputs pertinents des étapes précédentes,
exécute, et rend son résultat à router. Router décide de la suite (étape
séquentielle, branche parallèle, ou adaptation du plan). Synthèse finale au PO.

Voir `.claude/agents/*.md` pour le détail de chaque rôle.

## Liens utiles

- Blog référence : http://chabaka84.blogspot.com (archive non-officielle)
- Journal d'origine : https://alittihad.info
