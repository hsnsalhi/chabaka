import 'package:chabaka/ui/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('buildLightTheme produit un ThemeData M3 utilisable',
      (tester) async {
    final theme = buildLightTheme();
    expect(theme.useMaterial3, isTrue);
    expect(theme.brightness, Brightness.light);
    expect(theme.colorScheme.primary, const Color(0xFF8B1A1A));
  });

  testWidgets('buildDarkTheme produit un ThemeData M3 dark', (tester) async {
    final theme = buildDarkTheme();
    expect(theme.brightness, Brightness.dark);
    expect(theme.colorScheme.primary, const Color(0xFFD4A04A));
  });
}
