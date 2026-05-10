/// Générateur de grille مسهمة — stratégie en bandes + intersections.
///
/// Stratégie V1 :
///   Phase A — Placement en bandes horizontales : chaque mot horizontal
///     est posé sur une nouvelle ligne. La grille grandit verticalement.
///     Ceci garantit une grille rectangulaire sans trou (R1 satisfait).
///
///   Phase B — Enrichissement vertical : on tente d'ajouter des mots
///     verticaux qui intersectent les LetterCells existantes. Un mot
///     vertical n'est ajouté que s'il ne crée pas de cases null dans la
///     bounding box rectangulaire (contrainte R1).
///
///   R1 garantie par construction :
///     • Chaque ClueCell posée porte exactement 1 indice (ou 2 si double).
///     • Aucune ClueCell vide n'est créée.
///
///   R2 — Langue : délégué à Wordlist.validated().
///
/// Note : generate() retourne null si la wordlist ne contient pas assez
/// de mots pour atteindre [minWords]. Avec une wordlist ≥ minWords entrées
/// de longueur uniforme, le taux de succès est ≈100%.

import 'dart:math';
import '../models.dart';
import '../arabic_normalizer.dart';
import 'wordlist.dart';

class GeneratorConfig {
  final int rows;
  final int cols;
  final int minWords;
  final int maxWords;
  final int seed; // seed aléatoire (jours depuis epoch = déterministe par date)

  const GeneratorConfig({
    this.rows = 7,
    this.cols = 7,
    this.minWords = 6,
    this.maxWords = 20,
    required this.seed,
  });

  /// Seed basée sur la date (déterministe "grille du jour").
  factory GeneratorConfig.forDate(DateTime date) {
    final epoch = DateTime(2024, 1, 1);
    final days = date.difference(epoch).inDays;
    return GeneratorConfig(seed: days);
  }
}

class PuzzleGenerator {
  final Wordlist wordlist;
  final ArabicNormalizer normalizer;

  PuzzleGenerator({
    required this.wordlist,
    this.normalizer = const ArabicNormalizer(),
  });

  /// Génère une grille déterministe pour [config].
  /// Retourne null si impossible (wordlist trop petite, etc.)
  Grid? generate(GeneratorConfig config) {
    final rng = Random(config.seed);
    final shuffled = List<WordEntry>.from(wordlist.entries)..shuffle(rng);

    // --- Phase A : bandes horizontales ---
    // On sélectionne [minWords..maxWords] mots et on les pose chacun sur
    // une ligne séparée. Tous les mots de la même longueur → rectangle parfait.
    // Si longueurs variées, on prend des mots de longueur uniforme (mode strict)
    // ou on accepte la longueur maximale avec remplissage (mode souple V1).
    //
    // Pour V1 : mode uniforme — on prend des mots de même longueur.

    // Trouver la longueur la plus fréquente dans la wordlist.
    final wordLength = _mostFrequentLength(shuffled);
    if (wordLength == null) return null;

    // Filtrer les mots de cette longueur.
    final sameLength = shuffled
        .where((e) => normalizer.normalize(e.word).runes.length == wordLength)
        .toList();

    if (sameLength.length < config.minWords) return null;

    // Sélectionner [minWords..maxWords] mots distincts pour les bandes.
    final bandWords =
        sameLength.take(min(config.maxWords, sameLength.length)).toList();

    // Limiter au nombre de lignes disponibles dans config.rows.
    // La grille aura bandWords.length lignes de (1 + wordLength) colonnes.
    final nBands = min(bandWords.length, config.rows);
    if (nBands < config.minWords) return null;

    final gridCols = wordLength + 1; // 1 ClueCell + wordLength LetterCells
    final gridRows = nBands;

    if (gridCols > config.cols || gridRows > config.rows) return null;

    // Construire la grille.
    final cells = List.generate(
      gridRows,
      (row) {
        final entry = bandWords[row];
        final word = normalizer.normalize(entry.word);
        final letters = word.runes.map(String.fromCharCode).toList();
        final rowCells = <Cell>[];

        // Case 0 : ClueCell avec l'indice horizontal.
        rowCells.add(ClueCell(clues: [
          Clue(
            text: entry.clue,
            language: ClueLanguage.arabic,
            direction: Direction.horizontal,
            solution: entry.word,
            startCell: Position(row, 1), // les lettres commencent à col=1
          ),
        ]));

        // Cases 1..wordLength : LetterCells.
        for (final letter in letters) {
          rowCells.add(LetterCell(solution: letter));
        }

        return rowCells;
      },
    );

    // --- Phase B : enrichissement vertical (optionnel) ---
    // Pour chaque colonne de lettres (col 1..gridCols-1), on cherche un mot
    // vertical dont les lettres correspondraient aux LetterCells existantes.
    // Un mot vertical nécessite une ClueCell AVANT (row-1) pour chaque bande
    // couverte. On ne tente d'ajouter des mots verticaux que si la grille
    // reste rectangulaire et R1-conforme après ajout.
    //
    // Note : l'ajout de mots verticaux est purement optionnel en V1.
    // La grille horizontale-only est déjà R1-conforme.

    // Trouver les mots verticaux qui s'ajustent aux colonnes.
    final usedWords = Set<String>.from(bandWords.map((e) => e.word));
    final verticalCandidates = sameLength
        .where((e) => !usedWords.contains(e.word))
        .toList();

    // Pour chaque colonne de lettres (indices 1..gridCols-1),
    // tenter d'insérer un mot vertical dont la longueur = gridRows.
    // Cela nécessite que les lettres du mot vertical correspondent aux
    // LetterCells dans cette colonne (une lettre par ligne).
    for (var col = 1; col < gridCols; col++) {
      // Extraire les lettres actuelles de la colonne.
      final colLetters = <String>[];
      for (var row = 0; row < gridRows; row++) {
        final cell = cells[row][col];
        if (cell is LetterCell) {
          colLetters.add(cell.solution);
        } else {
          colLetters.add('?'); // ne devrait pas arriver
        }
      }

      // Chercher un mot vertical dont les lettres correspondent à colLetters.
      // Si le mot a exactement gridRows lettres → parfait.
      for (final candidate in verticalCandidates) {
        if (usedWords.contains(candidate.word)) continue;
        final normalizedWord = normalizer.normalize(candidate.word);
        final vLetters = normalizedWord.runes.map(String.fromCharCode).toList();
        if (vLetters.length != gridRows) continue;

        // Vérifier la correspondance lettre par lettre.
        var matches = true;
        for (var i = 0; i < gridRows; i++) {
          if (vLetters[i] != colLetters[i]) {
            matches = false;
            break;
          }
        }

        if (matches) {
          // Ajouter la ClueCell verticale : elle serait à (row=-1, col),
          // mais row=-1 n'existe pas dans la grille actuelle.
          // Pour ajouter une ligne en haut : agrandir la grille
          // (hors scope V1 — on skip l'ajout vertical dans cette version).
          //
          // Alternative : si la ClueCell[0][col] est déjà une ClueCell,
          // on peut y ajouter un 2e indice vertical... mais [0][col] est
          // une LetterCell. Impossible.
          //
          // Conclusion V1 : ajout vertical nécessite pré-planification.
          // Skip pour l'instant.
          usedWords.add(candidate.word); // marquer quand même pour stats
          break;
        }
      }
    }

    // --- Vérification R1 finale ---
    for (var r = 0; r < gridRows; r++) {
      for (var c = 0; c < gridCols; c++) {
        final cell = cells[r][c];
        if (cell is ClueCell && cell.clues.isEmpty) {
          return null; // ne devrait jamais arriver par construction
        }
      }
    }

    final gridId = 'day-${config.seed}';
    return Grid(
      rows: gridRows,
      cols: gridCols,
      cells: cells,
      variant: GridVariant.standard,
      id: gridId,
      title: 'شبكة اليوم',
      author: 'Chabaka',
    );
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Retourne la longueur de mot la plus fréquente dans la wordlist.
  int? _mostFrequentLength(List<WordEntry> entries) {
    if (entries.isEmpty) return null;
    final freq = <int, int>{};
    for (final e in entries) {
      final len = normalizer.normalize(e.word).runes.length;
      freq[len] = (freq[len] ?? 0) + 1;
    }
    return freq.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
  }
}
