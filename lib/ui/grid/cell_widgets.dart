import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../puzzle/puzzle.dart';
import 'cell_visuals.dart';
import 'puzzle_providers.dart';

const double cellSize = 64;

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
    // Garder uniquement le dernier graphème saisi.
    final chars = value.runes.toList();
    final last = String.fromCharCode(chars.last);
    if (chars.length > 1) {
      _controller.value = TextEditingValue(
        text: last,
        selection: TextSelection.collapsed(offset: last.length),
      );
    }
    controller.setLetter(widget.position, last);
  }

  @override
  Widget build(BuildContext context) {
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
          decoration: const InputDecoration(
            counterText: '',
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
/// Une ClueCell vide (sans indice) sert de bloqueur visuel.
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

    final isBlocker = cell.clues.isEmpty;
    final background = isBlocker
        ? scheme.outlineVariant
        : (inActiveWord
            ? Color.alphaBlend(
                scheme.outlineVariant.withValues(alpha: 0.4),
                scheme.surfaceContainerHighest,
              )
            : scheme.surfaceContainerHighest);

    return Container(
      width: cellSize,
      height: cellSize,
      decoration: BoxDecoration(
        color: background,
        border: Border.all(color: scheme.outline, width: 0.5),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
      child: isBlocker ? const SizedBox.shrink() : _buildClues(context),
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

    return Row(
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
    );
  }
}
