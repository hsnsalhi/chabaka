import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../puzzle/puzzle.dart';
import 'cell_visuals.dart';
import 'puzzle_providers.dart';
import 'puzzle_state.dart';

const double cellSize = 44;

/// Cellule pour saisir une lettre arabe.
class LetterCellWidget extends ConsumerStatefulWidget {
  final Position position;
  final LetterCell cell;
  final LetterCellVisual visual;

  const LetterCellWidget({
    super.key,
    required this.position,
    required this.cell,
    required this.visual,
  });

  @override
  ConsumerState<LetterCellWidget> createState() => _LetterCellWidgetState();
}

class _LetterCellWidgetState extends ConsumerState<LetterCellWidget> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.cell.userInput ?? '');
    _focusNode = FocusNode();
    _focusNode.addListener(_onFocusChanged);
  }

  @override
  void didUpdateWidget(covariant LetterCellWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = widget.cell.userInput ?? '';
    if (_controller.text != next) {
      _controller.value = TextEditingValue(
        text: next,
        selection: TextSelection.collapsed(offset: next.length),
      );
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    if (_focusNode.hasFocus) {
      ref.read(puzzleProvider.notifier).selectCell(widget.position);
      // Sélectionne le texte existant pour que la prochaine touche le
      // remplace (UX d'écrasement attendue par l'utilisateur sur une
      // cellule déjà remplie).
      final text = _controller.text;
      if (text.isNotEmpty) {
        _controller.selection = TextSelection(
          baseOffset: 0,
          extentOffset: text.length,
        );
      }
    }
  }

  void _handleChange(String value) {
    final controller = ref.read(puzzleProvider.notifier);
    if (value.isEmpty) {
      controller.setLetter(widget.position, null);
      return;
    }
    // Garder uniquement le dernier graphème saisi.
    final chars = value.runes.toList();
    final last = String.fromCharCode(chars.last);
    if (chars.length > 1) {
      _controller.value = TextEditingValue(
        text: last,
        selection: TextSelection.collapsed(offset: last.length),
      );
    }
    controller.typeLetter(widget.position, last);
  }

  @override
  Widget build(BuildContext context) {
    // Suivre la sélection globale : si elle pointe sur cette cellule
    // (via typeLetter qui avance la sélection), demander le focus pour
    // que le clavier OS reste ouvert et que la saisie continue.
    ref.listen<AsyncValue<PuzzleState>>(puzzleProvider, (prev, next) {
      final selected = next.valueOrNull?.selected;
      if (selected == widget.position && !_focusNode.hasFocus) {
        _focusNode.requestFocus();
      }
    });

    final scheme = Theme.of(context).colorScheme;
    final colors = LetterCellColors.from(widget.visual, scheme);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeInOut,
      width: cellSize,
      height: cellSize,
      decoration: BoxDecoration(
        color: colors.background,
        border: Border.all(color: colors.border, width: colors.borderWidth),
      ),
      child: Semantics(
        label: 'حقل لإدخال حرف',
        textField: true,
        child: TextField(
          controller: _controller,
          focusNode: _focusNode,
          textAlign: TextAlign.center,
          textAlignVertical: TextAlignVertical.center,
          maxLength: 1,
          showCursor: false,
          style: TextStyle(
            fontFamily: 'Cairo',
            fontWeight: FontWeight.w600,
            fontSize: 24,
            color: colors.text,
            height: 1.0,
          ),
          // Pas de fond ni de bordure propres au champ : la case (AnimatedContainer
          // parent) porte déjà couleur et bordure. Sans `filled: false`, le thème
          // global (inputDecorationTheme.filled) dessinait un ovale beige.
          decoration: const InputDecoration(
            counterText: '',
            filled: false,
            fillColor: Colors.transparent,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            isDense: true,
            contentPadding: EdgeInsets.zero,
          ),
          inputFormatters: [FilteringTextInputFormatter.deny(RegExp(r'\s'))],
          onChanged: _handleChange,
        ),
      ),
    );
  }
}

/// Bord de la CC par lequel sort la flèche d'un indice.
enum ArrowExit { left, right, bottom }

/// Bord de sortie selon le type de flèche (repère écran, grille RTL :
/// la colonne c+1 est à gauche de la CC, la colonne c-1 à droite).
ArrowExit arrowExitOf(ClueArrow a) => switch (a) {
  ClueArrow.hSameRow => ArrowExit.left,
  ClueArrow.vColRight => ArrowExit.left,
  ClueArrow.vColLeft => ArrowExit.right,
  ClueArrow.vSameCol => ArrowExit.bottom,
  ClueArrow.hRowBelow => ArrowExit.bottom,
};

/// Ordre d'affichage des indices dans une CC : d'abord ceux dont la flèche
/// sort par un côté (gauche puis droite), en dernier ceux qui sortent par le
/// bas, pour que chaque flèche soit au plus près de son mot. Tri stable.
List<Clue> orderedClues(ClueCell cell) {
  int rank(Clue c) => switch (arrowExitOf(c.arrowType)) {
    ArrowExit.left => 0,
    ArrowExit.right => 1,
    ArrowExit.bottom => 2,
  };
  final indexed = cell.clues.asMap().entries.toList()
    ..sort((a, b) {
      final d = rank(a.value) - rank(b.value);
      return d != 0 ? d : a.key - b.key;
    });
  return [for (final e in indexed) e.value];
}

/// Marge intérieure verticale d'une CC (doit rester cohérente avec
/// [ArrowOverlayPainter] qui calcule la hauteur de chaque ligne d'indice).
const double clueCellPadding = 2;

/// Cellule contenant 1 à 3 indices. Les flèches ne sont pas dessinées ici
/// mais par [ArrowOverlayPainter], en surcouche de la grille, sur le bord
/// de sortie de chaque mot (elles débordent sur la première case du mot).
/// R5 PO 2026-05-11 : ClueCell présent dans le data model garantit ≥1 indice
/// (les positions absentes sont désormais null dans Grid.cells et gérées
/// par GridBoard, pas ici).
class ClueCellWidget extends StatelessWidget {
  final ClueCell cell;
  final bool inActiveWord;

  const ClueCellWidget({
    super.key,
    required this.cell,
    this.inActiveWord = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final background = inActiveWord
        ? Color.alphaBlend(
            scheme.outlineVariant.withValues(alpha: 0.4),
            scheme.surfaceContainerHighest,
          )
        : scheme.surfaceContainerHighest;

    return Container(
      width: cellSize,
      height: cellSize,
      decoration: BoxDecoration(
        color: background,
        border: Border.all(color: scheme.outline, width: 0.5),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: 3,
        vertical: clueCellPadding,
      ),
      child: cell.clues.isEmpty ? null : _buildClues(context),
    );
  }

  Widget _buildClues(BuildContext context) {
    final clues = orderedClues(cell);
    if (clues.length == 1) {
      return _ClueLine(clue: clues.first, lines: 1);
    }
    final divider = Container(
      height: 0.5,
      color: Theme.of(context).colorScheme.outline,
    );
    return Column(
      children: [
        for (var i = 0; i < clues.length; i++) ...[
          if (i > 0) divider,
          Expanded(
            child: _ClueLine(clue: clues[i], lines: clues.length),
          ),
        ],
      ],
    );
  }
}

class _ClueLine extends StatelessWidget {
  final Clue clue;

  /// Nombre total de lignes dans la CC (1, 2 ou 3) : règle la taille du texte.
  final int lines;

  const _ClueLine({required this.clue, required this.lines});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fontSize = switch (lines) {
      1 => 11.0,
      2 => 9.0,
      _ => 7.5,
    };

    // Long-press révèle l'indice complet quand il est tronqué par ellipsis.
    return Tooltip(
      message: clue.text,
      triggerMode: TooltipTriggerMode.longPress,
      showDuration: const Duration(seconds: 4),
      preferBelow: false,
      textStyle: const TextStyle(
        fontFamily: 'Cairo',
        fontSize: 14,
        color: Colors.white,
        height: 1.4,
      ),
      decoration: BoxDecoration(
        color: scheme.inverseSurface.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(6),
      ),
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: 10,
        vertical: 6,
      ),
      child: Center(
        child: Text(
          clue.text,
          maxLines: lines == 1 ? 2 : 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'Cairo',
            fontWeight: FontWeight.w400,
            fontSize: fontSize,
            color: scheme.onSurface,
            height: 1.15,
          ),
        ),
      ),
    );
  }
}

/// Dessine, par-dessus toute la grille, la flèche de chaque indice sur le
/// bord de sa CC, alignée sur la ligne de l'indice, en débordant légèrement
/// sur la première case du mot. Peindre en surcouche évite que la flèche
/// soit recouverte par le fond de la case voisine.
class ArrowOverlayPainter extends CustomPainter {
  final Grid grid;
  final Color color;
  final bool rtl;

  const ArrowOverlayPainter({
    required this.grid,
    required this.color,
    required this.rtl,
  });

  // Géométrie des flèches (en px, pour cellSize = 44).
  static const double _inset = 5; // départ à l'intérieur de la CC
  static const double _overflow = 8; // débordement sur la case voisine
  static const double _head = 3.2; // demi-largeur de la pointe
  static const double _stroke = 1.6;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = _stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    for (var r = 0; r < grid.rows; r++) {
      for (var c = 0; c < grid.cols; c++) {
        final cell = grid.cells[r][c];
        if (cell is! ClueCell || cell.clues.isEmpty) continue;
        final rect = _cellRect(r, c);
        final clues = orderedClues(cell);
        final lineH = (cellSize - 2 * clueCellPadding) / clues.length;
        for (var i = 0; i < clues.length; i++) {
          final y = rect.top + clueCellPadding + (i + 0.5) * lineH;
          _drawArrow(canvas, paint, fill, rect, y, clues[i].arrowType);
        }
      }
    }
  }

  Rect _cellRect(int r, int c) {
    final visualCol = rtl ? grid.cols - 1 - c : c;
    return Rect.fromLTWH(
      visualCol * cellSize,
      r * cellSize,
      cellSize,
      cellSize,
    );
  }

  /// Côté « vers la colonne suivante » (c+1) : gauche en RTL, droite en LTR.
  double _mx(Rect rect, double xRtl) =>
      rtl ? xRtl : rect.left + rect.right - xRtl;

  void _drawArrow(
    Canvas canvas,
    Paint paint,
    Paint fill,
    Rect rect,
    double y,
    ClueArrow type,
  ) {
    // Points calculés en repère RTL puis miroités si LTR.
    final l = rect.left, rgt = rect.right, b = rect.bottom;
    final List<Offset> pts;
    final _Head head;
    switch (type) {
      case ClueArrow.hSameRow:
        // Sort à gauche, pointe à gauche.
        pts = [Offset(l + _inset, y), Offset(l - _overflow, y)];
        head = _Head.towardNext;
      case ClueArrow.vColRight:
        // Sort à gauche, tourne vers le bas.
        pts = [
          Offset(l + _inset, y),
          Offset(l - _overflow, y),
          Offset(l - _overflow, y + _overflow),
        ];
        head = _Head.down;
      case ClueArrow.vColLeft:
        // Sort à droite, tourne vers le bas.
        pts = [
          Offset(rgt - _inset, y),
          Offset(rgt + _overflow, y),
          Offset(rgt + _overflow, y + _overflow),
        ];
        head = _Head.down;
      case ClueArrow.vSameCol:
        // Sort par le bas au centre, pointe vers le bas.
        final x = rect.center.dx;
        pts = [Offset(x, b - _inset), Offset(x, b + _overflow)];
        head = _Head.down;
      case ClueArrow.hRowBelow:
        // Sort par le bas côté « colonne suivante », tourne vers la gauche.
        final x = l + cellSize * 0.28;
        pts = [
          Offset(x, b - _inset),
          Offset(x, b + _overflow),
          Offset(x - _overflow, b + _overflow),
        ];
        head = _Head.towardNext;
    }
    final mirrored = [for (final p in pts) Offset(_mx(rect, p.dx), p.dy)];
    final path = Path()..moveTo(mirrored.first.dx, mirrored.first.dy);
    for (final p in mirrored.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(path, paint);

    final tip = mirrored.last;
    final Path headPath;
    if (head == _Head.down) {
      headPath = Path()
        ..moveTo(tip.dx, tip.dy + _head)
        ..lineTo(tip.dx - _head, tip.dy - _head * 0.6)
        ..lineTo(tip.dx + _head, tip.dy - _head * 0.6)
        ..close();
    } else {
      final dir = rtl ? -1.0 : 1.0; // vers la colonne suivante
      headPath = Path()
        ..moveTo(tip.dx + dir * _head, tip.dy)
        ..lineTo(tip.dx - dir * _head * 0.6, tip.dy - _head)
        ..lineTo(tip.dx - dir * _head * 0.6, tip.dy + _head)
        ..close();
    }
    canvas.drawPath(headPath, fill);
  }

  @override
  bool shouldRepaint(ArrowOverlayPainter old) =>
      old.grid != grid || old.color != color || old.rtl != rtl;
}

enum _Head { down, towardNext }
