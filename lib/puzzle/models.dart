/// Data model Chabaka — مسهمة عربية
/// Dart pur (zéro import Flutter). Compatible Dart 3+.

// ---------------------------------------------------------------------------
// Enums
// ---------------------------------------------------------------------------

enum GridVariant { standard, bilingual }

enum ClueLanguage { arabic, french }

enum Direction { horizontal, vertical }

// ---------------------------------------------------------------------------
// Position
// ---------------------------------------------------------------------------

class Position {
  final int row;
  final int col;

  const Position(this.row, this.col);

  @override
  bool operator ==(Object other) =>
      other is Position && other.row == row && other.col == col;

  @override
  int get hashCode => Object.hash(row, col);

  @override
  String toString() => 'Position($row, $col)';

  Map<String, dynamic> toJson() => {'row': row, 'col': col};

  factory Position.fromJson(Map<String, dynamic> json) =>
      Position(json['row'] as int, json['col'] as int);
}

// ---------------------------------------------------------------------------
// Clue
// ---------------------------------------------------------------------------

class Clue {
  final String text;
  final ClueLanguage language;
  final Direction direction;
  final String solution; // mot complet (non normalisé)
  final Position startCell; // (row, col) de la première lettre

  const Clue({
    required this.text,
    required this.language,
    required this.direction,
    required this.solution,
    required this.startCell,
  });

  Map<String, dynamic> toJson() => {
        'text': text,
        'language': language.name,
        'direction': direction.name,
        'solution': solution,
        'startCell': startCell.toJson(),
      };

  factory Clue.fromJson(Map<String, dynamic> json) => Clue(
        text: json['text'] as String,
        language: ClueLanguage.values.byName(json['language'] as String),
        direction: Direction.values.byName(json['direction'] as String),
        solution: json['solution'] as String,
        startCell: Position.fromJson(json['startCell'] as Map<String, dynamic>),
      );
}

// ---------------------------------------------------------------------------
// Cells (sealed)
// ---------------------------------------------------------------------------

sealed class Cell {
  const Cell();

  Map<String, dynamic> toJson();

  factory Cell.fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String;
    return switch (type) {
      'clue' => ClueCell.fromJson(json),
      'letter' => LetterCell.fromJson(json),
      _ => throw ArgumentError('Unknown cell type: $type'),
    };
  }
}

class ClueCell extends Cell {
  final List<Clue> clues; // 1 ou 2 indices (cellule double)

  const ClueCell({required this.clues});

  @override
  Map<String, dynamic> toJson() => {
        'type': 'clue',
        'clues': clues.map((c) => c.toJson()).toList(),
      };

  factory ClueCell.fromJson(Map<String, dynamic> json) => ClueCell(
        clues: (json['clues'] as List<dynamic>)
            .map((c) => Clue.fromJson(c as Map<String, dynamic>))
            .toList(),
      );
}

class LetterCell extends Cell {
  final String solution; // 1 lettre arabe isolée
  String? userInput;     // mutation autorisée : saisie utilisateur

  LetterCell({required this.solution, this.userInput});

  @override
  Map<String, dynamic> toJson() => {
        'type': 'letter',
        'solution': solution,
        if (userInput != null) 'userInput': userInput,
      };

  factory LetterCell.fromJson(Map<String, dynamic> json) => LetterCell(
        solution: json['solution'] as String,
        userInput: json['userInput'] as String?,
      );
}

// ---------------------------------------------------------------------------
// Grid
// ---------------------------------------------------------------------------

class Grid {
  final int rows;
  final int cols;
  final List<List<Cell>> cells;
  final GridVariant variant;
  final String id;
  final String? title;
  final String? author;

  const Grid({
    required this.rows,
    required this.cols,
    required this.cells,
    required this.variant,
    required this.id,
    this.title,
    this.author,
  });

  /// Accès direct à une cellule.
  Cell cellAt(Position p) => cells[p.row][p.col];

  /// Toutes les LetterCell de la grille, avec leur position.
  Iterable<({Position pos, LetterCell cell})> get letterCells sync* {
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        final cell = cells[r][c];
        if (cell is LetterCell) {
          yield (pos: Position(r, c), cell: cell);
        }
      }
    }
  }

  /// Toutes les Clue de la grille (depuis les ClueCells).
  Iterable<Clue> get allClues sync* {
    for (final row in cells) {
      for (final cell in row) {
        if (cell is ClueCell) {
          yield* cell.clues;
        }
      }
    }
  }

  Map<String, dynamic> toJson() => {
        'rows': rows,
        'cols': cols,
        'cells': cells
            .map((row) => row.map((cell) => cell.toJson()).toList())
            .toList(),
        'variant': variant.name,
        'id': id,
        if (title != null) 'title': title,
        if (author != null) 'author': author,
      };

  factory Grid.fromJson(Map<String, dynamic> json) => Grid(
        rows: json['rows'] as int,
        cols: json['cols'] as int,
        cells: (json['cells'] as List<dynamic>)
            .map((row) => (row as List<dynamic>)
                .map((cell) => Cell.fromJson(cell as Map<String, dynamic>))
                .toList())
            .toList(),
        variant: GridVariant.values.byName(json['variant'] as String),
        id: json['id'] as String,
        title: json['title'] as String?,
        author: json['author'] as String?,
      );
}
