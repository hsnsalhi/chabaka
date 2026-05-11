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
    }
  }

  void _handleChange(String value) {
    final controller = ref.read(puzzleProvider.notifier);
    if (value.isEmpty) {
      controller.setLetter(widget.position, null);
      return;
    }
    // Garder uniquement le DERNIER graphème saisi — autorise l'écrasement
    // d'une lettre existante (la cellule a alors temporairement 2 caractères
    // si l'user tape sur une case pleine, et on garde le nouveau).
    final chars = value.runes.toList();
    final last = String.fromCharCode(chars.last);
    if (chars.length > 1 || _controller.text != last) {
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
          // Pas de maxLength: on autorise temporairement 2 caractères pour
          // permettre à l'utilisateur d'écraser une lettre existante. Le
          // _handleChange garde le dernier graphème saisi.
          showCursor: false,
          style: TextStyle(
            fontFamily: 'Cairo',
            fontWeight: FontWeight.w600,
            fontSize: 24,
            color: colors.text,
            height: 1.0,
          ),
          decoration: const InputDecoration(
            border: InputBorder.none,
            isDense: true,
            contentPadding: EdgeInsets.zero,
          ),
          inputFormatters: [
            FilteringTextInputFormatter.deny(RegExp(r'\s')),
          ],
          onChanged: _handleChange,
        ),
      ),
    );
  }
}

/// Cellule contenant 1 ou 2 indices (avec flèche directionnelle).
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
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
      child: cell.clues.isEmpty ? null : _buildClues(context),
    );
  }

  Widget _buildClues(BuildContext context) {
    final clues = cell.clues;
    if (clues.length == 1) {
      return _ClueLine(clue: clues.first);
    }
    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(child: _ClueLine(clue: clues[0], compact: true)),
        Container(
          height: 0.5,
          color: Theme.of(context).colorScheme.outline,
        ),
        Expanded(child: _ClueLine(clue: clues[1], compact: true)),
      ],
    );
  }
}

class _ClueLine extends StatelessWidget {
  final Clue clue;
  final bool compact;

  const _ClueLine({required this.clue, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final arrow = clue.direction == Direction.horizontal ? '←' : '↓';
    final fontSize = compact ? 9.0 : 11.0;

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
      padding: const EdgeInsetsDirectional.symmetric(horizontal: 10, vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Text(
              clue.text,
              maxLines: compact ? 1 : 2,
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
          const SizedBox(width: 1),
          Text(
            arrow,
            textDirection: TextDirection.ltr,
            style: TextStyle(
              fontSize: fontSize + 2,
              fontWeight: FontWeight.w700,
              color: scheme.primary,
              height: 1.0,
            ),
          ),
        ],
      ),
    );
  }
}
