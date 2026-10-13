import 'package:chabaka/puzzle/arabic_normalizer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Défaut (PO 2026-10-13) : strict, chaque lettre garde sa fonction.
  const normalizer = ArabicNormalizer();

  group('ArabicNormalizer strict — alef variants distinctes', () {
    test('أ reste أ', () => expect(normalizer.normalize('أ'), 'أ'));
    test('إ reste إ', () => expect(normalizer.normalize('إ'), 'إ'));
    test('آ reste آ', () => expect(normalizer.normalize('آ'), 'آ'));
    test('ا reste ا', () => expect(normalizer.normalize('ا'), 'ا'));
    test('ٱ (wasla) → ا', () => expect(normalizer.normalize('ٱ'), 'ا'));
  });

  group('ArabicNormalizer strict — ة et ى distinctes', () {
    test('ة reste ة', () => expect(normalizer.normalize('حياة'), 'حياة'));
    test('ى reste ى', () => expect(normalizer.normalize('مصطفى'), 'مصطفى'));
  });

  group('ArabicNormalizer — diacritics stripped', () {
    test('remove fatha', () => expect(normalizer.normalize('كَ'), 'ك'));
    test('remove shadda', () => expect(normalizer.normalize('كّ'), 'ك'));
    test(
      'remove full tashkeel',
      () => expect(normalizer.normalize('مَرْحَباً'), 'مرحبا'),
    );
  });

  group('ArabicNormalizer — zero width chars', () {
    test('ZWNJ removed', () => expect(normalizer.normalize('ك‌ل'), 'كل'));
  });

  group('ArabicNormalizer strict — matchesLetter', () {
    test(
      'exact match',
      () => expect(normalizer.matchesLetter('ك', 'ك'), isTrue),
    );
    test(
      'أ ne vaut pas ا',
      () => expect(normalizer.matchesLetter('أ', 'ا'), isFalse),
    );
    test(
      'إ ne vaut pas أ',
      () => expect(normalizer.matchesLetter('إ', 'أ'), isFalse),
    );
    test(
      'ة ne vaut pas ه',
      () => expect(normalizer.matchesLetter('ة', 'ه'), isFalse),
    );
    test(
      'ى ne vaut pas ي',
      () => expect(normalizer.matchesLetter('ى', 'ي'), isFalse),
    );
    test(
      'diacritised matches base',
      () => expect(normalizer.matchesLetter('كَ', 'ك'), isTrue),
    );
    test(
      'wrong letter no match',
      () => expect(normalizer.matchesLetter('ب', 'ك'), isFalse),
    );
    test(
      'empty user input no match',
      () => expect(normalizer.matchesLetter('', 'ك'), isFalse),
    );
  });

  group('ArabicNormalizer — équivalences optionnelles', () {
    const loose = ArabicNormalizer(
      normalizeAlef: true,
      normalizeTaMarbuta: true,
      normalizeYaa: true,
    );
    test('أ → ا quand activé', () => expect(loose.normalize('أ'), 'ا'));
    test('ة → ه quand activé', () => expect(loose.normalize('ة'), 'ه'));
    test('ى → ي quand activé', () => expect(loose.normalize('ى'), 'ي'));
  });
}
