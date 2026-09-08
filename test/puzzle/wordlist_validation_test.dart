/// Tests R2 — Validation de la langue arabe dans la Wordlist.
///
/// Vérifie que :
///   • Les entrées purement arabes sont acceptées.
///   • Les entrées contenant des caractères latins sont rejetées.
///   • Les entrées mixtes (arabe + latin) sont rejetées.
///   • Les chaînes vides sont rejetées (longueur 0 → pas de rune autorisée
///     mais la chaîne est vide, validateArabicText retourne null car la
///     boucle ne s'exécute pas — acceptable : une entrée vide sera rejetée
///     pour d'autres raisons comme length=0).
///   • Les ponctuation arabes usuelles et espaces sont acceptés.
///   • Les chiffres arabes-indiens (٠–٩) sont acceptés (dans le bloc Arabic).
///   • Les chiffres latins (0–9) sont rejetés.
///   • Les emojis sont rejetés.

import 'package:flutter_test/flutter_test.dart';
import 'package:chabaka/puzzle/generation/wordlist.dart';

void main() {
  group('validateArabicText', () {
    // --- Cas valides ---

    test('mot arabe simple → valide', () {
      expect(validateArabicText('كتاب'), isNull);
    });

    test('mot arabe avec hamza → valide', () {
      expect(validateArabicText('أسرة'), isNull);
    });

    test('phrase arabe avec espace → valide', () {
      expect(validateArabicText('ضد الظلام'), isNull);
    });

    test('phrase arabe avec virgule arabe → valide', () {
      expect(validateArabicText('كبير، قديم'), isNull);
    });

    test('phrase arabe avec point-virgule arabe → valide', () {
      expect(validateArabicText('كبير؛ قديم'), isNull);
    });

    test('phrase arabe avec point d\'interrogation arabe → valide', () {
      expect(validateArabicText('ما هو؟'), isNull);
    });

    test('phrase arabe avec deux-points → valide', () {
      expect(validateArabicText('تعريف: الماء'), isNull);
    });

    test('chiffres arabes-indiens → valides (bloc Arabic U+0660–U+0669)', () {
      expect(validateArabicText('٣ أيام'), isNull);
    });

    test('mot avec tashkeel (diacritiques arabes) → valide', () {
      // Les diacritiques sont dans le bloc Arabic U+0600–U+06FF
      expect(validateArabicText('كَتَبَ'), isNull);
    });

    test('ZWNJ seul → valide', () {
      // U+200C est explicitement autorisé
      expect(validateArabicText('‌'), isNull);
    });

    // --- Cas invalides ---

    test('lettre latine seule → invalide', () {
      expect(validateArabicText('a'), isNotNull);
    });

    test('mot latin seul → invalide', () {
      expect(validateArabicText('livre'), isNotNull);
    });

    test('mot arabe + lettre latine → invalide', () {
      expect(validateArabicText('كتابa'), isNotNull);
    });

    test('mot arabe + chiffre latin → invalide', () {
      expect(validateArabicText('كتاب3'), isNotNull);
    });

    test('chiffre latin seul → invalide', () {
      expect(validateArabicText('5'), isNotNull);
    });

    test('emoji → invalide', () {
      expect(validateArabicText('كتاب😀'), isNotNull);
    });

    test('texte latin seul → invalide', () {
      expect(validateArabicText('bonjour'), isNotNull);
    });

    test('texte mixte arabe-français → invalide', () {
      expect(validateArabicText('كتاب livre'), isNotNull);
    });

    test('ponctuation latine (point) → invalide', () {
      expect(validateArabicText('كتاب.'), isNotNull);
    });

    test('ponctuation latine (virgule) → invalide', () {
      // La virgule latine (U+002C) est différente de la virgule arabe (U+060C)
      expect(validateArabicText('كتاب,'), isNotNull);
    });

    test('le message d\'erreur cite le caractère invalide', () {
      final error = validateArabicText('كتابA');
      expect(error, isNotNull);
      expect(error, contains('U+0041')); // 'A' = U+0041
    });
  });

  group('Wordlist.validated — filtrage R2', () {
    test('toutes les entrées arabes valides sont acceptées', () {
      final entries = [
        WordEntry(word: 'كتاب', clue: 'ما يُقرأ', length: 4),
        WordEntry(word: 'نور', clue: 'ضد الظلام', length: 3),
        WordEntry(word: 'بحر', clue: 'ماء ملح', length: 3),
      ];
      final wl = Wordlist.validated(entries);
      expect(wl.entries.length, 3);
    });

    test('les entrées avec mot latin sont rejetées', () {
      final entries = [
        WordEntry(word: 'livre', clue: 'كتاب', length: 5),
        WordEntry(word: 'كتاب', clue: 'ما يُقرأ', length: 4),
      ];
      final wl = Wordlist.validated(entries);
      // 'livre' rejeté, 'كتاب' conservé
      expect(wl.entries.length, 1);
      expect(wl.entries.first.word, 'كتاب');
    });

    test('les entrées avec indice latin sont rejetées', () {
      final entries = [
        WordEntry(word: 'كتاب', clue: 'un livre', length: 4),
        WordEntry(word: 'نور', clue: 'ضد الظلام', length: 3),
      ];
      final wl = Wordlist.validated(entries);
      // L'entrée 'كتاب' rejetée (indice latin), 'نور' conservée
      expect(wl.entries.length, 1);
      expect(wl.entries.first.word, 'نور');
    });

    test('les entrées mixtes arabe-latin sont rejetées', () {
      final entries = [
        WordEntry(word: 'كتابbook', clue: 'وعاء المعرفة', length: 8),
        WordEntry(word: 'علم', clue: 'المعرفة', length: 3),
      ];
      final wl = Wordlist.validated(entries);
      expect(wl.entries.length, 1);
      expect(wl.entries.first.word, 'علم');
    });

    test('les entrées avec chiffres latins sont rejetées', () {
      final entries = [
        WordEntry(word: 'ثلاثة3', clue: 'العدد 3', length: 6),
        WordEntry(word: 'أربعة', clue: 'العدد ٤', length: 5),
      ];
      final wl = Wordlist.validated(entries);
      // 'ثلاثة3' rejeté (chiffre latin), 'أربعة' conservé
      expect(wl.entries.length, 1);
      expect(wl.entries.first.word, 'أربعة');
    });

    test('liste entièrement invalide → Wordlist vide', () {
      final entries = [
        WordEntry(word: 'hello', clue: 'greeting', length: 5),
        WordEntry(word: 'world', clue: 'terre', length: 5),
      ];
      final wl = Wordlist.validated(entries);
      expect(wl.entries, isEmpty);
    });

    test('liste vide → Wordlist vide', () {
      final wl = Wordlist.validated([]);
      expect(wl.entries, isEmpty);
    });

    test('ponctuation arabe dans indice → accepté', () {
      final entries = [
        WordEntry(word: 'ماء', clue: 'سائل، أساس الحياة', length: 3),
      ];
      final wl = Wordlist.validated(entries);
      expect(wl.entries.length, 1);
    });

    test('chiffres arabes-indiens dans indice → acceptés', () {
      final entries = [WordEntry(word: 'ثلاثة', clue: 'العدد ٣', length: 5)];
      final wl = Wordlist.validated(entries);
      expect(wl.entries.length, 1);
    });

    test('Wordlist.fromJson applique aussi la validation R2', () {
      final json = {
        'words': [
          {'word': 'كتاب', 'clue': 'ما يُقرأ', 'length': 4},
          {'word': 'livre', 'clue': 'كتاب', 'length': 5}, // invalide
          {'word': 'نور', 'clue': 'ضد الظلام', 'length': 3},
        ],
      };
      final wl = Wordlist.fromJson(json);
      expect(wl.entries.length, 2);
      expect(
        wl.entries.map((e) => e.word).toList(),
        containsAll(['كتاب', 'نور']),
      );
    });
  });
}
