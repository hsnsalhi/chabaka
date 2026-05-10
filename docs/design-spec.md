# Chabaka — Design Spec V1 MVP

> Produit par l'agent `design`. À implémenter par l'agent principal.

## Concept visuel

**"Papier de journal"** — évoquer la presse écrite marocaine (Al Ittihad Al Ichtiraki),
pas un jeu mobile générique. Typographie arabe soignée, palette chaleureuse et sobre.

---

## Palette de couleurs

### Mode clair (Light)

| Rôle | Token | Hex | Usage |
|---|---|---|---|
| Surface principale | `surface` | `#F5EDD8` | Fond de la grille (beige papier chaud) |
| Surface secondary | `surfaceVariant` | `#EAE0C8` | Fond des cellules-définition |
| On-surface | `onSurface` | `#1C1008` | Texte principal (encre sombre) |
| Accent primaire | `primary` | `#8B1A1A` | Rouge brique — Al Ittihad, highlights |
| On-primary | `onPrimary` | `#FFFFFF` | Texte sur accent |
| Outline | `outline` | `#6B5E4A` | Bordures des cellules |
| Outline variant | `outlineVariant` | `#C4B49A` | Bordures secondaires |
| Cell selected | `primaryContainer` | `#C84040` | Fond cellule sélectionnée |
| On cell selected | `onPrimaryContainer` | `#FFFFFF` | Lettre dans cellule sélectionnée |
| Cell active word | `secondaryContainer` | `#F2D5A0` | Fond cellule du mot actif (non sélectionnée) |
| Cell empty | `surface` | `#F5EDD8` | Cellule vide non sélectionnée |
| Cell correct | — | `#2E7D32` | Vert validation (feedback succès) |
| Cell error | — | `#C62828` | Rouge erreur |
| Background | `background` | `#ECDFC0` | Fond de l'écran hors grille |

### Mode sombre (Dark)

| Rôle | Token | Hex |
|---|---|---|
| Surface principale | `surface` | `#1E1A14` |
| Surface secondary | `surfaceVariant` | `#2C261C` |
| On-surface | `onSurface` | `#EDE0C4` |
| Accent primaire | `primary` | `#D4A04A` | Doré — lisible, chaleureux |
| On-primary | `onPrimary` | `#1C1008` |
| Outline | `outline` | `#7A6B55` |
| Outline variant | `outlineVariant` | `#3D3426` |
| Cell selected | `primaryContainer` | `#B8882A` |
| On cell selected | `onPrimaryContainer` | `#1C1008` |
| Cell active word | `secondaryContainer` | `#342B1A` |
| Background | `background` | `#141008` |

---

## Typographie

### Familles de polices

| Usage | Font | Weight | Taille |
|---|---|---|---|
| Titres / app bar | `Amiri` | Bold (700) | 24–28sp |
| Texte des indices (ClueCell) | `Cairo` | Regular (400) | 11–13sp (contrainte grille) |
| Lettres dans les cellules (LetterCell) | `Cairo` | SemiBold (600) | 22–26sp |
| Labels UI (boutons, feedback) | `Cairo` | Medium (500) | 14–16sp |

> Note taille indices : les ClueCells sont petites dans la grille (~60×60pt max).
> 11-13sp est un compromis — Cairo est lisible à cette taille.
> `lineHeight` 1.4 dans les ClueCells (texte compact), 1.0 pour les LetterCells (1 caractère).

### À déclarer dans pubspec.yaml

```yaml
fonts:
  - family: Cairo
    fonts:
      - asset: assets/fonts/Cairo-Regular.ttf
        weight: 400
      - asset: assets/fonts/Cairo-Medium.ttf
        weight: 500
      - asset: assets/fonts/Cairo-SemiBold.ttf
        weight: 600
      - asset: assets/fonts/Cairo-Bold.ttf
        weight: 700
  - family: Amiri
    fonts:
      - asset: assets/fonts/Amiri-Regular.ttf
        weight: 400
      - asset: assets/fonts/Amiri-Bold.ttf
        weight: 700
```

---

## États des cellules (LetterCell)

| État | Fond | Bordure | Texte | Bordure épaisseur |
|---|---|---|---|---|
| Vide | `#F5EDD8` | `#6B5E4A` | — | 0.5pt |
| Saisie (en cours) | `#F5EDD8` | `#8B1A1A` | `#1C1008` | 1.5pt |
| Mot actif non sélectionné | `#F2D5A0` | `#6B5E4A` | `#1C1008` | 0.5pt |
| Sélectionné (focus) | `#C84040` | `#8B1A1A` | `#FFFFFF` | 2pt |
| Correct (feedback) | `#E8F5E9` | `#2E7D32` | `#2E7D32` | 1.5pt |
| Erreur (feedback) | `#FFEBEE` | `#C62828` | `#C62828` | 1.5pt |

**Mode sombre** : remplacer les hex light par leurs équivalents dark (cf palette).

---

## États des cellules (ClueCell)

| État | Fond | Texte | Séparateur (double) |
|---|---|---|---|
| Normal | `#EAE0C8` | `#1C1008` | `#6B5E4A` 0.5pt |
| Mot actif | `#D4C8A8` | `#1C1008` | `#6B5E4A` 0.5pt |

Flèche directionnelle : `#8B1A1A` (accent), taille 10pt.

---

## Layout grille

```
┌──────────────────────────────────────────────┐
│  AppBar : "شبكة اليوم"  (Amiri Bold, 24sp)   │
│  RTL, fond #8B1A1A, icône menu à gauche (en  │
│  RTL = côté "fin")                            │
├──────────────────────────────────────────────┤
│                                              │
│  ┌──┬──┬──┬──┬──┐   Grille scrollable        │
│  │▓▓│  │  │  │▓▓│   (InteractiveViewer ou    │
│  ├──┼──┼──┼──┼──┤    SingleChildScrollView)  │
│  │  │  │▓▓│  │  │                            │
│  └──┴──┴──┴──┴──┘                            │
│                                              │
│  Cellules : taille min 44×44pt (accessibilité)│
│  ClueCells : ~52×52pt (texte + flèche)       │
│  Grille centrée horizontalement              │
│                                              │
├──────────────────────────────────────────────┤
│  BottomSheet feedback : "أحسنت !" / "خطأ"    │
│  (apparaît à complétion)                     │
└──────────────────────────────────────────────┘
```

### Taille cellule recommandée

- **LetterCell** : 44×44pt (exactement la taille tactile minimum)
- **ClueCell** : variable selon contenu, min 44×44pt, peut s'étirer verticalement
- La grille typique 13×16 fera ~572×704pt → nécessite scroll vertical sur iPhone SE

---

## Animations / Feedback

| Événement | Animation | Durée |
|---|---|---|
| Sélection cellule | Scale 1.0→1.05→1.0 + changement couleur | 150ms |
| Validation mot correct | Flash vert (vert → normal) sur les cellules | 300ms |
| Mot incorrect (à complétion) | Shake horizontal (translation ±4pt × 3) | 400ms |
| Grille résolue | Confetti ou vague de vert sur toutes les cellules | 800ms |
| Transition états | `AnimatedContainer` curve `easeInOut` | 200ms |

---

## Accessibilité

- Contraste minimum : WCAG AA (4.5:1) sur tous les états
  - `#8B1A1A` sur `#F5EDD8` → ratio ~6.2:1 ✓
  - `#FFFFFF` sur `#C84040` → ratio ~4.8:1 ✓
  - `#1C1008` sur `#F2D5A0` → ratio ~8.1:1 ✓
- Taille tactile : toutes cellules ≥44×44pt
- Sémantique : `Semantics(label: '...')` sur ClueCells et LetterCells (VoiceOver/TalkBack)
- Police Cairo lisible à 11sp (vérifiée visuellement sur grille مسهمة réelle)

---

## Écran "Grille résolue"

Modal bottom sheet (ou plein écran overlay) :

```
┌─────────────────────────────┐
│                             │
│    ✓  أحسنت !               │
│    (Amiri Bold 32sp, vert)  │
│                             │
│  أنهيت شبكة اليوم بنجاح     │
│  (Cairo Regular 16sp)       │
│                             │
│  [مشاركة النتيجة]  [حسناً]  │
│                             │
└─────────────────────────────┘
```

---

## Écran "Grille incomplète / erreurs"

Bottom sheet léger :

```
┌─────────────────────────────┐
│  ✗  توجد أخطاء              │
│  (Cairo Medium 16sp, rouge) │
│  [مراجعة]                   │
└─────────────────────────────┘
```
