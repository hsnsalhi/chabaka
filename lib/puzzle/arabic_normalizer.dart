/// Normalisation de l'input arabe utilisateur.
///
/// Règle PO (2026-10-13) : chaque lettre garde sa propre fonction. Par défaut
/// ا, أ, إ et آ sont quatre lettres différentes, ة n'est pas ه, ى n'est pas ي.
/// Les équivalences restent disponibles en option (désactivées par défaut).
///   • Diacritiques (تشكيل) → toujours supprimés
///   • ZWNJ / ZWJ / espaces → toujours supprimés
///   • ٱ (alif wasla) → ا

class ArabicNormalizer {
  final bool normalizeAlef; // ا أ إ آ → ا  (défaut : false)
  final bool normalizeTaMarbuta; // ة → ه        (défaut : false)
  final bool normalizeYaa; // ى → ي        (défaut : false)

  const ArabicNormalizer({
    this.normalizeAlef = false,
    this.normalizeTaMarbuta = false,
    this.normalizeYaa = false,
  });

  static const _diacritics = {
    'ً', // fathatan
    'ٌ', // dammatan
    'ٍ', // kasratan
    'َ', // fatha
    'ُ', // damma
    'ِ', // kasra
    'ّ', // shadda
    'ْ', // sukun
    'ٓ', // maddah above
    'ٔ', // hamza above
    'ٕ', // hamza below
    'ٖ', // subscript alef
    'ٗ', // inverted damma
    '٘', // mark noon ghunna
    'ٰ', // superscript alef
  };

  static const _zeroWidthChars = {
    '‌', // ZWNJ
    '‍', // ZWJ
    ' ', // NBSP
    '﻿', // BOM
  };

  /// Normalise un mot ou une lettre.
  String normalize(String input) {
    final buffer = StringBuffer();

    for (final char in input.characters) {
      // Supprimer diacritiques
      if (_diacritics.contains(char)) continue;

      // Supprimer zero-width + espaces
      if (_zeroWidthChars.contains(char) || char.trim().isEmpty) continue;

      var ch = char;
      if (ch == 'ٱ') ch = 'ا';

      if (normalizeAlef) {
        // أ إ آ ٱ → ا
        if (const {'أ', 'إ', 'آ', 'ٱ'}.contains(ch)) {
          ch = 'ا'; // ا
        }
      }

      if (normalizeTaMarbuta) {
        // ة → ه
        if (ch == 'ة') ch = 'ه'; // ه
      }

      if (normalizeYaa) {
        // ى → ي
        if (ch == 'ى') ch = 'ي'; // ي
      }

      buffer.write(ch);
    }

    return buffer.toString();
  }

  /// Normalise lettre par lettre pour la validation cellule.
  bool matchesLetter(String userInput, String solution) {
    final normUser = normalize(userInput.trim());
    final normSol = normalize(solution.trim());
    if (normUser.isEmpty || normSol.isEmpty) return false;
    return normUser == normSol;
  }
}

// Extension utilitaire sur String pour accès aux graphèmes.
extension on String {
  Iterable<String> get characters sync* {
    final runes = this.runes.toList();
    var i = 0;
    while (i < runes.length) {
      yield String.fromCharCode(runes[i]);
      i++;
    }
  }
}
