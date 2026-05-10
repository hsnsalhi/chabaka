# Chabaka — Options UX pour la saisie d'un mot

> Produit par l'agent `design`. Validation PO requise avant implémentation.
> L'agent principal traduit en widgets Flutter après validation.

---

## Contexte du problème

État actuel : chaque LetterCell est un TextField indépendant. L'utilisateur tape,
le focus reste sur la même cellule, et il doit re-tapper manuellement sur la case
suivante. Le clavier OS peut clignoter entre deux taps. Pour un mot de 5 lettres :
5 taps + 5 frappes, soit 10 gestes. Sur une grille de ~60 mots, c'est rédhibitoire.

---

## Option A — Auto-advance + clavier OS persistant

### Comportement de bout en bout

1. **Tap sur une LetterCell** : la cellule passe en état "sélectionné" (fond `#C84040`),
   toutes les cellules du mot actif passent en `#F2D5A0`. Le clavier OS s'ouvre (une
   seule fois, il reste ouvert jusqu'à désélection). La barre d'indice au-dessus du
   clavier affiche le texte de l'indice en grand.
2. **Frappe d'une lettre** : la lettre s'inscrit dans la cellule, le focus avance
   automatiquement vers la cellule suivante du mot (RTL : de droite vers gauche).
   La cellule précédente repasse en `#F2D5A0` (mot actif non sélectionné).
3. **Backspace** : efface la lettre de la cellule actuelle et recule d'une case.
   Si la cellule est déjà vide, recule et efface la précédente.
4. **Intersection (cellule appartenant à deux mots)** : un double-tap bascule la
   direction active H <-> V. La barre d'indice se met à jour en conséquence.
5. **Fin du mot** : quand la dernière case est remplie, un micro-feedback visuel
   (flash `#F2D5A0` -> `#EAE0C8`, 200ms) signale la complétion. Le focus passe au
   premier caractère vide du mot suivant (logique à définir par puzzle agent).
   Le clavier reste ouvert.
6. **Désélection** : tap en dehors de la grille, ou sur une ClueCell, ferme le
   clavier et retire la sélection.

### Mockup ASCII

```
┌─────────────────────────────────────────────┐
│  AppBar : "شبكة اليوم"   (Amiri Bold 24sp)  │  <- fond #8B1A1A
├─────────────────────────────────────────────┤
│                                             │
│  ┌───┬───┬───┬───┬───┬───┬───┐  RTL        │
│  │▓▓▓│   │   │ ب │   │   │▓▓▓│  <- rangée  │
│  ├───┼───┼───┼───┼───┼───┼───┤             │
│  │   │   │[ك]│ ت │ ا │ب  │   │  <- focus   │
│  ├───┼───┼───┼───┼───┼───┼───┤    sur [ك]  │
│  │   │▓▓▓│   │   │   │▓▓▓│   │             │
│  └───┴───┴───┴───┴───┴───┴───┘             │
│   cellules mot actif : fond #F2D5A0         │
│   [ك] sélectionnée : fond #C84040, texte    │
│       blanc, bordure 2pt #8B1A1A            │
│                                             │
├─────────────────────────────────────────────┤
│  ┌─────────────────────────────────────────┐│
│  │  [←] عاصمة المغرب  [↕ H/V]            ││  <- barre indice
│  │  Cairo SemiBold 18sp, fond #EAE0C8      ││     toujours visible
│  └─────────────────────────────────────────┘│     au-dessus clavier
├─────────────────────────────────────────────┤
│                                             │
│   ┌─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┐                │
│   │ض│ص│ث│ق│ف│غ│ع│ه│خ│ح│ج│                │
│   ├─┼─┼─┼─┼─┼─┼─┼─┼─┼─┼─┤                │
│   │ش│س│ي│ب│ل│ا│ت│ن│م│ك│د│                │  <- clavier OS natif
│   ├─┼─┼─┼─┼─┼─┼─┼─┼─┼─┼─┤                │     iOS / Android
│   │ظ│ط│ذ│د│ز│ر│و│ة│ى│⌫ │                │
│   └─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┘                │
└─────────────────────────────────────────────┘
```

**Barre d'indice** (entre grille et clavier, fond `#EAE0C8`, hauteur min 52pt) :
- Icone direction active : fleche `→` ou `↓` en `#8B1A1A`, 20pt.
- Texte de l'indice : `Cairo` SemiBold 18sp, `#1C1008`, lineHeight 1.5.
- Bouton `[H/V]` (44×44pt min) a droite : bascule direction sur intersection,
  désactivé (opacity 0.38) si la cellule n'est pas une intersection.

**Indicateur de progression du mot** (sous le texte de l'indice, optionnel) :
- Série de pastilles `● ● ○ ○ ○` (remplies/vides), 8pt, couleur `#8B1A1A`.

### Trade-offs

| Dimension | Evaluation |
|---|---|
| Effort Flutter | Moyen — FocusNode chain à gérer, intercepter le TextInputAction.next, gérer le backspace via RawKeyboardListener. Pas de widget custom complet. |
| Familiarité | Tres haute — exactement le comportement NYT Crossword, Apple News+ Crossword. Le clavier arabe iOS natif est maitrisé par le public cible. |
| Clavier OS | Reste ouvert sans clignotement si le focus passe d'un TextField a l'autre dans le meme formulaire. A valider sur iOS (comportement parfois capricieux entre deux TextFields). |
| Public 40+ | Bien : ils connaissent le clavier arabe iOS. La barre d'indice en grand compense le mini-texte actuel des ClueCells. |
| RTL | Auto-advance va de droite vers gauche (premier index = cellule la plus a droite). Backspace recule vers la droite. |

---

## Option B — Clavier arabe in-app (custom keyboard)

### Comportement de bout en bout

1. **Premier lancement** : le clavier OS ne s'ouvre jamais. Un clavier custom 28
   touches est affiché en permanence en bas de l'ecran (aucun appel a `showKeyboard`).
2. **Tap sur une LetterCell** : focus visuel identique a l'Option A. Le clavier
   custom reste fixe, aucun reflow de l'ecran.
3. **Frappe sur une touche du clavier custom** : lettre inscrite + auto-advance
   (meme logique que A).
4. **Touche [⌫]** : efface + recule (meme logique que A).
5. **Touche [✓]** : valide manuellement le mot actif (optionnel — pour les
   utilisateurs qui veulent confirmer avant de passer au suivant).
6. **Switch direction** : bouton `H / V` intégré directement dans la rangee de
   touches de controle du clavier custom (toujours visible, pas a chercher).
7. **Fin de mot** : meme micro-feedback qu'en A. Focus passe au mot suivant.

### Mockup ASCII

```
┌─────────────────────────────────────────────┐
│  AppBar : "شبكة اليوم"                      │  <- fond #8B1A1A
├─────────────────────────────────────────────┤
│                                             │
│  ┌───┬───┬───┬───┬───┬───┬───┐  RTL        │
│  │▓▓▓│   │   │ ب │   │   │▓▓▓│             │
│  ├───┼───┼───┼───┼───┼───┼───┤             │
│  │   │   │[ك]│ ت │ ا │ب  │   │  <- focus   │
│  ├───┼───┼───┼───┼───┼───┼───┤             │
│  │   │▓▓▓│   │   │   │▓▓▓│   │             │
│  └───┴───┴───┴───┴───┴───┴───┘             │
│                                             │
│  ┌─────────────────────────────────────────┐│
│  │ → عاصمة المغرب              ● ● ○ ○ ○  ││ <- indice + progression
│  │ Cairo SemiBold 18sp                     ││
│  └─────────────────────────────────────────┘│
├─────────────────────────────────────────────┤
│                                             │
│  ┌─────────────────────────────────────────┐│
│  │ ض  ص  ث  ق  ف  غ  ع  ه  خ  ح  ج      ││
│  │ ش  س  ي  ب  ل  ا  ت  ن  م  ك  د      ││  <- clavier custom
│  │ ظ  ط  ذ  ر  ز  و  ة  ى  ⌫            ││     28 lettres arabes
│  ├─────────────────────────────────────────┤│
│  │     [H→]   [V↓]        [  ✓ تأكيد  ]   ││ <- barre de controle
│  └─────────────────────────────────────────┘│
└─────────────────────────────────────────────┘
```

**Specs du clavier custom** :
- Fond : `#EAE0C8` (mode clair) / `#2C261C` (mode sombre).
- Touche standard : 36×44pt min, border-radius 6pt, fond `#F5EDD8`, texte `Cairo`
  Regular 20sp `#1C1008`.
- Touche pressed : fond `#D4C8A8`, transition 80ms `easeIn`.
- Touche [⌫] : largeur 48pt, icone SF Symbol `delete.left` (iOS) / `backspace` (MD).
- Barre de controle : hauteur 52pt, fond `#D4C8A8`, boutons `[H→]` et `[V↓]`
  avec le bouton actif en fond `#8B1A1A` texte `#FFFFFF`.
- Bouton `[✓ تأكيد]` : fond `#8B1A1A`, texte `#FFFFFF`, Cairo Medium 15sp, border-radius 8pt.
- Hauteur totale clavier custom : ~220pt.

### Trade-offs

| Dimension | Evaluation |
|---|---|
| Effort Flutter | Lourd — widget custom complet (touches, gestion backspace, feedback haptique, accessibilite TalkBack/VoiceOver pour 28 touches). ~2-3 jours dev. |
| Familiarité | Moyenne-haute — proche de Wordle (clavier visuel permanent). Moins familier que le clavier OS pour les 40+. |
| Clavier OS | Jamais invoque, zero clignotement, zero reflow. Experience tres stable. |
| Public 40+ | Risque : ils peuvent etre destabilises de ne pas voir "leur" clavier arabe habituel. Gain : toutes les lettres sont visibles, pas besoin de chercher. |
| RTL | La disposition 28 touches doit suivre la convention du clavier arabe AZERTY-ar (ض ص ث... standard Moyen-Orient + Maghreb). |
| Normalisation | Avec `arabic_normalizer.dart`, on n'a besoin que de 28 touches de base — pas de long-press pour variantes (ا, أ, إ, آ sont tous acceptes comme ا). Simplifie enormement le clavier custom. |

---

## Option C — Saisie au mot via modal bottom sheet

### Comportement de bout en bout

1. **Tap sur une ClueCell** (ou sur n'importe quelle LetterCell du mot) : une
   modale bottom sheet s'anime vers le haut (spring, 300ms). La grille reste visible
   en arriere-plan, assombrie (`Colors.black54`).
2. **Contenu de la modale** : titre de l'indice en grand (Amiri Bold 22sp), sous-
   titre direction + longueur (ex. "افقي — 5 حروف"), un champ texte unique pre-
   focalisé (clavier OS s'ouvre).
3. **Pendant la frappe** : les lettres s'affichent au fur et a mesure dans les
   cellules de la grille en arriere-plan (transparence 70%), synchrone avec la
   saisie. La modale affiche aussi les lettres en grand sous l'indice (style "révèle").
4. **Longueur atteinte** : vibration courte (haptic feedback), le bouton `[تأكيد]`
   s'active automatiquement (primary `#8B1A1A`).
5. **Validation** : tap `[تأكيد]` ou appui sur la touche Retour du clavier OS.
   La modale se ferme, les lettres s'inscrivent definitvement dans la grille,
   feedback flash vert ou shake rouge selon correction.
6. **Correction** : le champ texte est modifiable librement avant validation.
   Backspace efface la derniere lettre saisie.
7. **Annulation** : swipe down sur la modale, ou tap sur l'arriere-plan.

### Mockup ASCII

```
┌─────────────────────────────────────────────┐
│  AppBar : "شبكة اليوم"                      │
├─────────────────────────────────────────────┤
│                                             │
│  ┌───┬───┬───┬───┬───┬───┬───┐  RTL        │
│  │▓▓▓│   │   │ب  │   │   │▓▓▓│   <- grille │
│  ├───┼───┼───┼───┼───┼───┼───┤      en     │
│  │   │   │ك  │ت  │ا  │ب  │   │   arriere-  │
│  ├───┼───┼───┼───┼───┼───┼───┤   plan semi-│
│  │   │▓▓▓│   │   │   │▓▓▓│   │   transparent
│  └───┴───┴───┴───┴───┴───┴───┘             │
│  ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ (overlay)   │
├═════════════════════════════════════════════╡
│  ╔═════════════════════════════════════════╗│
│  ║  ────  (drag handle)                   ║│
│  ║                                        ║│
│  ║  → أفقي • 5 حروف                      ║│  <- Amiri Bold 22sp
│  ║  عاصمة المغرب                          ║│     #1C1008
│  ║                                        ║│
│  ║  ┌───┬───┬───┬───┬───┐                ║│
│  ║  │ ط │ ا │ ب │ ر │   │  <- preview   ║│  <- Cairo SemiBold
│  ║  └───┴───┴───┴───┴───┘    lettres      ║│     28sp, cellules
│  ║                            en cours    ║│     44×44pt
│  ║  ┌─────────────────────────────────┐  ║│
│  ║  │     طابر|  (curseur)            │  ║│  <- TextField unique
│  ║  └─────────────────────────────────┘  ║│     Cairo 22sp
│  ║                                        ║│
│  ║  [ إلغاء ]          [ تأكيد ▶ ]       ║│  <- boutons
│  ╚═════════════════════════════════════════╝│
├─────────────────────────────────────────────┤
│  [ clavier OS natif arabe ]                 │
└─────────────────────────────────────────────┘
```

**Specs de la modale** :
- Fond : `#F5EDD8` (mode clair), border-radius top 16pt.
- Drag handle : 32×4pt, `#C4B49A`, centré, margin-top 8pt.
- Indice : `Amiri` Bold 22sp, `#1C1008`, lineHeight 1.6, padding 16pt.
- Sous-titre direction/longueur : `Cairo` Regular 14sp, `#6B5E4A`.
- Preview cellules : serie de 44×44pt avec fond `#F2D5A0`, bordure `#8B1A1A` 1.5pt,
  lettre `Cairo` SemiBold 26sp. Cellule active du curseur : fond `#C84040`.
- TextField : fond transparent, texte `Cairo` 22sp mais masqué visuellement
  (opacity 0) — l'affichage se fait via les cellules de preview. Clavier OS reste
  standard.
- Bouton `[تأكيد]` : desactivé (opacity 0.38) tant que longueur incorrecte,
  actif en `#8B1A1A`.
- Bouton `[إلغاء]` : texte only, `#6B5E4A`.

### Trade-offs

| Dimension | Evaluation |
|---|---|
| Effort Flutter | Moyen — ModalBottomSheet + DraggableScrollableSheet, un seul TextField, synchronisation texte -> grille en temps réel. Moins de FocusNode gymnastics que A. |
| Familiarité | Faible-Moyenne — pattern peu courant dans les mots fléchés. Plus proche d'un formulaire que d'un jeu. |
| Clavier OS | Un seul TextField donc zero probleme de focus. Clavier s'ouvre une fois, reste ouvert pendant toute la saisie du mot. |
| Public 40+ | Avantage majeur : l'indice est affiché en GRAND et lisible. L'interface est simple (un champ, deux boutons). |
| RTL | Le champ texte accepte du RTL. La preview des cellules s'affiche de droite a gauche. |
| Inconvénient principal | La grille est cachee pendant la saisie — l'utilisateur ne peut pas exploiter les lettres d'intersection déjà remplies pour s'aider (cross-checking). C'est une vraie perte ergonomique pour un mots fléchés. |

---

## Recommandation finale : Option A avec emprunt a B

### Choix : Option A (auto-advance + clavier OS) + barre d'indice persistante

**Pourquoi pas B (clavier custom)** : effort lourd, risque de destabiliser
les utilisateurs 40+ qui ont leurs habitudes avec le clavier arabe iOS/Android.
Le gain principal de B (zero clignotement) est atteignable en A en maintenant
un seul TextField avec FocusNode rebond — le clavier OS ne se ferme pas entre
deux cellules d'un meme mot si on gère le focus correctement.

**Pourquoi pas C (modal)** : le cross-checking (utiliser les lettres
d'intersection déjà connues pour deviner le mot courant) est fondamental dans
les mots fléchés. La modal masque la grille et casse ce mechansime.

**Ce qui rend A superieur pour Chabaka** :
- Comportement appris (NYT, Apple News+ Crossword) = zero onboarding.
- Barre d'indice persistante résout le problème de lisibilite de 11sp actuel.
- Le clavier arabe natif iOS est bien connu du public cible 40+ (ils l'utilisent
  tous les jours sur WhatsApp).
- Normalisation existante (`arabic_normalizer.dart`) fait que l'utilisateur peut
  taper `ا` sans chercher `أ` — ça réduit le besoin du long-press natif.
- Effort d'implémentation moyen, pas lourd.

**Emprunt a B** : intégrer le bouton `[H→] / [V↓]` comme composant flottant
au-dessus de la barre d'indice (pas besoin d'un clavier custom entier). Il suffit
d'un FAB secondaire ou d'un chip discret dans la barre d'indice.

### Layout final recommandé (Option A affinée)

```
┌─────────────────────────────────────────────┐
│  AppBar : "شبكة اليوم"     [menu]           │  fond #8B1A1A
├─────────────────────────────────────────────┤
│                                             │
│  [grille scrollable, RTL]                   │
│  cellules mot actif : #F2D5A0               │
│  cellule focus : #C84040 + bordure #8B1A1A  │
│                                             │
├─────────────────────────────────────────────┤
│  ┌─────────────────────────────────────────┐│
│  │ [→]  عاصمة المغرب         [↕]  ● ● ○ ○ ││  <- barre indice
│  │      Cairo SemiBold 18sp               ││     fond #EAE0C8
│  └─────────────────────────────────────────┘│     hauteur 52pt min
├─────────────────────────────────────────────┤
│  [ clavier OS arabe natif — iOS/Android ]   │
└─────────────────────────────────────────────┘
```

### Specs de la barre d'indice (a transmettre a l'agent principal)

| Element | Valeur |
|---|---|
| Fond | `#EAE0C8` (clair) / `#2C261C` (sombre) |
| Hauteur min | 52pt (taille tactile) |
| Padding horizontal | 16pt (`EdgeInsetsDirectional`) |
| Icone direction | Fleche `→` ou `↓`, couleur `#8B1A1A`, taille 20pt |
| Texte indice | `Cairo` SemiBold 600, 18sp, `#1C1008`, lineHeight 1.5, max 2 lignes puis ellipsis |
| Bouton H/V | 44×44pt min, fond `#D4C8A8` (inactif) / `#8B1A1A` (actif), texte `Cairo` Medium 13sp, border-radius 8pt ; désactivé si cellule non-intersection (opacity 0.38) |
| Pastilles progression | Série de 8pt, espacement 4pt, remplies = `#8B1A1A`, vides = `#C4B49A` |
| Séparateur | Ligne 0.5pt `#C4B49A` en haut de la barre |
| Mode sombre | Fond `#2C261C`, texte `#EDE0C4`, accent `#D4A04A`, pastilles remplies `#D4A04A` |

### Comportements clés a implémenter (pour l'agent principal)

- **Auto-advance** : apres chaque input d'1 caractere, passer le focus au prochain
  index valide du mot actif (sens RTL = index décroissant en X si horizontal).
  Ignorer les cellules deja correctement remplies (sauter par-dessus) ou ne pas
  sauter (parametre produit a décider avec PO).
- **Backspace sur cellule vide** : reculer et effacer la cellule precedente.
- **Double-tap sur intersection** : toggler direction H <-> V, mettre a jour la
  barre d'indice.
- **Focus unique** : un seul TextField visible actif a la fois. Le clavier OS
  ne doit pas se rouvrir/fermer entre les cellules d'un meme mot — maintenir
  le focus dans un widget unique (TextField masqué de coordination) si nécessaire,
  et dessiner la grille par-dessus (pattern "invisible input sink").
- **Fermeture clavier** : tap sur ClueCell, tap sur zone hors grille, ou tap
  sur la cellule deja selectionnee.
- **Accessibilite** : `Semantics(label: "حرف رقم X من كلمة : [texte indice]")`
  sur chaque LetterCell du mot actif. Barre d'indice : `Semantics(liveRegion: true)`
  pour que VoiceOver annonce le changement d'indice.
