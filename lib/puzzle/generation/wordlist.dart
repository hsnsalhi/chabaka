/// Chargement et accès à la wordlist arabe.

class WordEntry {
  final String word;       // mot arabe (non normalisé, tel que dans le JSON)
  final String clue;       // indice arabe
  final int length;        // longueur en caractères (précalculé dans JSON)

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

class Wordlist {
  final List<WordEntry> entries;

  const Wordlist(this.entries);

  factory Wordlist.fromJson(Map<String, dynamic> json) {
    final words = (json['words'] as List<dynamic>)
        .map((e) => WordEntry.fromJson(e as Map<String, dynamic>))
        .toList();
    return Wordlist(words);
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
