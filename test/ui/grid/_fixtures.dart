/// Fixtures partagées pour les widget tests de GridScreen / ClueBar / etc.
///
/// Grille 4×4 :
///
///   [CC_H] [L:ك] [L:ت] [L:ب]    ← mot H "كتب" (clue:"قراءة←")  row 0
///   [L:م]  [L:ر] [L:س] [CC_V]   ← CC_V = clue V "مدرس↓"        row 1
///   [L:ل]  [L:ا] [L:ب] [L:س]    ←                              row 2
///   [CC_b] [L:ئ] [L:ر] [L:ة]    ← CC_b = bloqueur vide         row 3
///
/// Mot H : "كتب"  start=(0,1)  clue-cell=(0,0)
/// Mot V : "مل"   start=(1,0)  via CC_V=(1,3)  ← ATTENTION: on simplifie :
///   Mot V : "مل" start=(1,0) col 0  (ClueCell en (1,3) pointe col 0)
///   Dans cette fixture on positionne la ClueCell verticale en (1,3) pointant
///   vers le mot V "مل" qui commence en (1,0).  Seul le mot H a son CC en
///   colonne adjacente (col 0 pour une grille RTL).
///
/// --- Grille simplifiée retenue pour les tests ---
///
/// 3 colonnes, 4 lignes :
///
///   row 0 : [CC_H:"قراءة"] [L:ك] [L:ت]
///   row 1 : [CC_V:"عالم"] [L:ر] [L:س]
///   row 2 : [L:م]         [L:ا] [L:ب]
///   row 3 : [blocker]     [L:ئ] [L:ر]
///
///   Mot H : solution="كت" start=(0,1)   clue-cell=(0,0)  text="قراءة"
///   Mot V : solution="رئ" start=(1,1)   clue-cell=(1,0)  text="عالم"
///
/// Intersection : Position(1,1) "ر" appartient à H ET à V (si on étend H).
/// Pour simplifier l'intersection test on utilise une autre fixture (voir
/// fixtureIntersection).

library;

import 'package:chabaka/puzzle/puzzle.dart';

/// Grille 3×3 simple avec 1 mot horizontal "كتب" et 1 mot vertical "كرم".
///
///   row 0 : [CC_H]  [L:ك]  [L:ت]  <- mot H "كت" start=(0,1)
///   row 1 : [CC_V]  [L:ر]  [L:س]  <- mot V "كر" start=(0,1)... non
///
/// Grille 3×3 retenue :
///
///   (0,0)=CC_H  (0,1)=L:ك  (0,2)=L:ت
///   (1,0)=L:ب   (1,1)=L:ر  (1,2)=L:س
///   (2,0)=CC_V  (2,1)=L:ا  (2,2)=L:ب
///
///   Mot H "كت"  : start=(0,1), CC=(0,0), text="قراءة"
///   Mot V "بر"  : start=(1,0), CC=(2,0) ne peut pas pointer vers (1,0)
///                 si CC est en (2,0) et direction=V → non standard.
///
/// On va faire simple : une grille 3×3 avec UN seul mot horizontal et c'est
/// tout. Tests intersection dans fixtureIntersection séparé.

/// Grille principale : 3×3, 1 mot H "كتب" (3 lettres), 1 mot V "بر" (2 l.).
///
///   (0,0)=ClueCell[H:"كتب"] (0,1)=L:ك  (0,2)=L:ت
///   (1,0)=L:ب               (1,1)=L:ر  (1,2)=L:س
///   (2,0)=ClueCell[V:"بر"]  (2,1)=L:ا  (2,2)=L:ب
///
/// Mot H "كت" start=(0,1) : NON — on veut 3 lettres. Ajustons cols à 4.
///
/// --- FIXTURE FINALE ---
///
/// Grille 3 lignes × 4 colonnes :
///   (0,0)=CC[H:"كتب"]  (0,1)=L:ك  (0,2)=L:ت  (0,3)=L:ب
///   (1,0)=CC[V:"كرم"]  (1,1)=L:ر  (1,2)=L:م  (1,3)=blocker
///   (2,0)=blocker       (2,1)=L:ا  (2,2)=L:ل  (2,3)=L:م
///
///   Mot H : solution="كتب" start=(0,1) CC=(0,0) text="قراءة وكتابة"
///   Mot V : solution="كر"  start=(0,1) CC=(1,0) text="عالم"
///      → (0,1) appartient à H ET à V  ← intersection parfaite

Grid buildFixtureGrid() {
  // Mot H "كتب" : startCell = (0,1), CC en (0,0)
  // Mot V "كر"  : startCell = (0,1), CC en (1,0)
  // => Position(0,1) est à l'intersection H ∩ V
  const clueH = Clue(
    text: 'قراءة وكتابة',
    language: ClueLanguage.arabic,
    direction: Direction.horizontal,
    solution: 'كتب',
    startCell: Position(0, 1),
  );

  const clueV = Clue(
    text: 'عالم',
    language: ClueLanguage.arabic,
    direction: Direction.vertical,
    solution: 'كر',
    startCell: Position(0, 1),
  );

  return Grid(
    rows: 3,
    cols: 4,
    id: 'fixture-001',
    variant: GridVariant.standard,
    cells: [
      // row 0
      [
        ClueCell(clues: [clueH]),   // (0,0) CC pour mot H
        LetterCell(solution: 'ك'), // (0,1) intersection H ∩ V
        LetterCell(solution: 'ت'), // (0,2)
        LetterCell(solution: 'ب'), // (0,3)
      ],
      // row 1
      [
        ClueCell(clues: [clueV]),   // (1,0) CC pour mot V
        LetterCell(solution: 'ر'), // (1,1)
        LetterCell(solution: 'م'), // (1,2)
        ClueCell(clues: []),        // (1,3) bloqueur
      ],
      // row 2
      [
        ClueCell(clues: []),        // (2,0) bloqueur
        LetterCell(solution: 'ا'), // (2,1)
        LetterCell(solution: 'ل'), // (2,2)
        LetterCell(solution: 'م'), // (2,3)
      ],
    ],
  );
}

/// Retourne la validation initiale (grille vide).
GridValidationResult buildEmptyValidation(Grid grid) {
  const validator = GridValidator();
  return validator.validateGrid(grid);
}
