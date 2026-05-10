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

## (Règles suivantes en attente — PO à dicter)
