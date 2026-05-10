# Règles de gestion — Chabaka (مسهمة)

> Spec dictée par le PO le 2026-05-10. À implémenter dans `lib/puzzle/generation/generator.dart` (agent `puzzle`).

## R1 — Toutes les cases doivent être "utiles"

Toute case de la grille doit être :
- soit une **ClueCell** porteuse d'au moins un indice (1 ou 2 synonymes/indices empilés) ;
- soit une **LetterCell** couverte par au moins un mot à trouver.

Conséquence : **interdiction des bloqueurs vides** (ClueCell avec `clues: []`).

## R2 — Langue

- Tous les mots et indices sont en **arabe**, langue correcte et propre.
- Pas de mots étrangers, transcrits, ou de jargon hors-langue.
- Les indices peuvent être : synonyme, définition courte, expression idiomatique — toujours en arabe standard.

---

## Implications immédiates pour le générateur (V1 actuelle)

- L'algo greedy actuel laisse des `ClueCell(clues: [])` quand il n'a pas trouvé d'indice à placer → **non conforme R1**, à corriger.
- La wordlist `assets/wordlist/wordlist_ar.json` doit être auditée pour conformité R2.
- Si une case ne peut pas être couverte par un mot ET qu'aucune définition ne vient s'y poser, la grille générée doit être **rejetée et reseed** (ou la taille de grille adaptée).

---

## R4 — Aucune suite de lettres sans sens

**Toute suite de ≥2 LetterCells contiguës horizontalement ou verticalement (entre deux ClueCells ou entre une ClueCell et le bord) doit former un mot valide de la base de connaissances.**

Conséquence directe : la grille n'est plus juste "des mots qu'on a placés", c'est "**toutes les suites lisibles** (H + V) **doivent être des mots valides**". Les "runs" résultant accidentellement d'intersections doivent eux aussi être des mots.

### Implications

- **Génération** : l'algo greedy actuel (placer un mot à la fois) ne garantit PAS R4. Refonte nécessaire.
  - Option : pré-planifier la topologie (positions ClueCells / LetterCells) puis remplir chaque "slot" avec un mot du dico, en respectant les intersections.
  - Option : hybride placement + validation post-hoc qui rejette toute grille où une run n'est pas dans le dico.
- **Base de connaissances** : doit être **très large et offline**, embarquée dans l'app.
  - Vocabulaire arabe usuel (verbes, noms communs, adjectifs).
  - **Personnalités célèbres** (historiques, contemporaines, monde arabe + monde).
  - **Géographie** : pays, capitales, villes (en arabe).
  - **Histoire**, philosophie, sciences, arts.
  - Format = paire (mot, définition/indice/contexte).

### Spec à produire (architect)

L'architect doit spécifier :
1. Modèle de données pour la base de connaissances (catégories, format JSON ou DB embarquée, taille cible).
2. Stratégie de sourcing offline (corpus public arabe, dictionnaires Wiktionary AR, listes Wikipedia, etc.) — pipeline de constitution.
3. Algorithme de génération qui garantit R4 (avec ordre de magnitude perfs).
4. Architecture d'embedding : asset bundle ? SQLite ? FTS ? Taille app acceptable ?
5. Critères de qualité : couverture par longueur de mot, équilibre des thématiques, exclusion (pas de termes politiques sensibles, etc.).

Pas de code dans cette spec — juste le "comment on s'y prend".

