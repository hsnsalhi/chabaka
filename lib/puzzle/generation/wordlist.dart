/// Chargement et accès à la wordlist arabe.
///
/// R2 — Langue : toute entrée contenant des caractères hors plages arabes
/// autorisées est rejetée au chargement avec un warning sur stderr.
///
/// Plages autorisées :
///   U+0600–U+06FF  Arabic
///   U+0750–U+077F  Arabic Supplement
///   U+08A0–U+08FF  Arabic Extended-A
///   U+0020          espace
///   U+200C          ZWNJ
///   U+060C          ، (virgule arabe)
///   U+061B          ؛ (point-virgule arabe)
///   U+061F          ؟ (point d'interrogation arabe)
///   U+003A          : (deux-points)

class WordEntry {
  final String word; // mot arabe (non normalisé, tel que dans le JSON)
  final String clue; // indice arabe
  final int length; // longueur en caractères (précalculé dans JSON)

  const WordEntry({
    required this.word,
    required this.clue,
    required this.length,
  });

  factory WordEntry.fromJson(Map<String, dynamic> json) => WordEntry(
        word: json['word'] as String,
        clue: json['clue'] as String,
        length: json['length'] as int,
      );

  @override
  String toString() => 'WordEntry($word, length=$length)';
}

/// Valide qu'une chaîne ne contient que des caractères arabes autorisés (R2).
/// Retourne null si valide, sinon la description du premier caractère invalide.
String? validateArabicText(String text) {
  for (final rune in text.runes) {
    if (_isAllowedRune(rune)) continue;
    return 'caractère non arabe U+${rune.toRadixString(16).toUpperCase().padLeft(4, '0')} '
        '"${String.fromCharCode(rune)}"';
  }
  return null;
}

bool _isAllowedRune(int rune) {
  // Espace ordinaire
  if (rune == 0x0020) return true;
  // ZWNJ
  if (rune == 0x200C) return true;
  // Ponctuation arabe usuelle
  if (rune == 0x060C) return true; // ،
  if (rune == 0x061B) return true; // ؛
  if (rune == 0x061F) return true; // ؟
  if (rune == 0x003A) return true; // :
  // Arabic block U+0600–U+06FF
  if (rune >= 0x0600 && rune <= 0x06FF) return true;
  // Arabic Supplement U+0750–U+077F
  if (rune >= 0x0750 && rune <= 0x077F) return true;
  // Arabic Extended-A U+08A0–U+08FF
  if (rune >= 0x08A0 && rune <= 0x08FF) return true;
  return false;
}

class Wordlist {
  final List<WordEntry> entries;

  const Wordlist(this.entries);

  /// Construit une Wordlist en filtrant les entrées non conformes R2.
  /// Les entrées invalides sont ignorées (warning sur stderr).
  factory Wordlist.fromJson(Map<String, dynamic> json) {
    final raw = (json['words'] as List<dynamic>)
        .map((e) => WordEntry.fromJson(e as Map<String, dynamic>))
        .toList();
    return Wordlist.validated(raw);
  }

  /// Construit depuis une liste brute en appliquant la validation R2.
  factory Wordlist.validated(List<WordEntry> raw) {
    final valid = <WordEntry>[];
    for (final entry in raw) {
      final wordError = validateArabicText(entry.word);
      if (wordError != null) {
        // ignore: avoid_print
        print('[Wordlist] R2 rejet "${entry.word}" : $wordError');
        continue;
      }
      final clueError = validateArabicText(entry.clue);
      if (clueError != null) {
        // ignore: avoid_print
        print('[Wordlist] R2 rejet indice de "${entry.word}" : $clueError');
        continue;
      }
      valid.add(entry);
    }
    return Wordlist(valid);
  }

  /// Mots d'une longueur exacte.
  List<WordEntry> ofLength(int len) =>
      entries.where((e) => e.length == len).toList();

  /// Mots dont la longueur est dans [min, max].
  List<WordEntry> inRange(int min, int max) =>
      entries.where((e) => e.length >= min && e.length <= max).toList();

  /// Cherche un mot dont la lettre à la position [pos] est [letter].
  List<WordEntry> withLetterAt(String letter, int pos) => entries
      .where((e) => pos < e.word.length && e.word[pos] == letter)
      .toList();
}
