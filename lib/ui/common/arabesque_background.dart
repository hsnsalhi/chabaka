import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Fond décoratif subtil à motif géométrique islamique (étoile à 8 branches).
/// Opacity par défaut : 6% — invisible mais présent pour texture.
///
/// Usage :
/// ```dart
/// Stack(children: [
///   const ArabesqueBackground(),
///   child,
/// ])
/// ```
class ArabesqueBackground extends StatelessWidget {
  final Color? color;
  final double opacity;

  const ArabesqueBackground({super.key, this.color, this.opacity = 0.06});

  @override
  Widget build(BuildContext context) {
    final effectiveColor = color ?? Theme.of(context).colorScheme.onSurface;
    return Positioned.fill(
      child: IgnorePointer(
        child: RepaintBoundary(
          child: CustomPaint(
            painter: _ArabesquePainter(
              color: effectiveColor.withValues(alpha: opacity),
            ),
          ),
        ),
      ),
    );
  }
}

class _ArabesquePainter extends CustomPainter {
  final Color color;

  const _ArabesquePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..isAntiAlias = true;

    const cellSize = 72.0; // espacement de la grille décorative
    final cols = (size.width / cellSize).ceil() + 2;
    final rows = (size.height / cellSize).ceil() + 2;

    for (var row = -1; row <= rows; row++) {
      for (var col = -1; col <= cols; col++) {
        final cx = col * cellSize + (row.isOdd ? cellSize / 2 : 0);
        final cy = row * cellSize;
        _drawStar8(canvas, paint, Offset(cx, cy), cellSize * 0.38);
        _drawSquare(
          canvas,
          paint,
          Offset(cx, cy),
          cellSize * 0.22,
          math.pi / 4,
        );
      }
    }
  }

  /// Étoile à 8 branches (motif islamique de base).
  void _drawStar8(Canvas canvas, Paint paint, Offset center, double r) {
    final path = Path();
    const n = 8;
    const innerRatio = 0.42;

    for (var i = 0; i < n; i++) {
      final outerAngle = (i * 2 * math.pi / n) - math.pi / 2;
      final innerAngle = outerAngle + math.pi / n;
      final outer = Offset(
        center.dx + r * math.cos(outerAngle),
        center.dy + r * math.sin(outerAngle),
      );
      final inner = Offset(
        center.dx + r * innerRatio * math.cos(innerAngle),
        center.dy + r * innerRatio * math.sin(innerAngle),
      );
      if (i == 0) {
        path.moveTo(outer.dx, outer.dy);
      } else {
        path.lineTo(outer.dx, outer.dy);
      }
      path.lineTo(inner.dx, inner.dy);
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  /// Carré tourné pour compléter le motif.
  void _drawSquare(
    Canvas canvas,
    Paint paint,
    Offset center,
    double half,
    double angle,
  ) {
    final path = Path();
    for (var i = 0; i < 4; i++) {
      final a = angle + i * math.pi / 2;
      final p = Offset(
        center.dx + half * math.sqrt(2) * math.cos(a + math.pi / 4),
        center.dy + half * math.sqrt(2) * math.sin(a + math.pi / 4),
      );
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_ArabesquePainter old) => old.color != color;
}
