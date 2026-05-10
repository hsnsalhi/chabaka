import 'package:flutter_test/flutter_test.dart';
import 'package:chabaka/puzzle/arabic_normalizer.dart';

void main() {
  const normalizer = ArabicNormalizer();

  group('ArabicNormalizer — alef variants', () {
    test('أ → ا', () => expect(normalizer.normalize('أ'), 'ا'));
    test('إ → ا', () => expect(normalizer.normalize('إ'), 'ا'));
    test('آ → ا', () => expect(normalizer.normalize('آ'), 'ا'));
    test('ا → ا (unchanged)', () => expect(normalizer.normalize('ا'), 'ا'));
  });

  group('ArabicNormalizer — ta marbuta', () {
    test('ة → ه', () => expect(normalizer.normalize('ة'), 'ه'));
    test('حياة → حياه', () => expect(normalizer.normalize('حياة'), 'حياه'));
  });

  group('ArabicNormalizer — yaa variants', () {
    test('ى → ي', () => expect(normalizer.normalize('ى'), 'ي'));
    test('مصطفى → مصطفي', () => expect(normalizer.normalize('مصطفى'), 'مصطفي'));
  });

  group('ArabicNormalizer — diacritics stripped', () {
    test('remove fatha', () => expect(normalizer.normalize('كَ'), 'ك'));
    test('remove shadda', () => expect(normalizer.normalize('كّ'), 'ك'));
    test('remove full tashkeel', () =>
        expect(normalizer.normalize('مَرْحَباً'), 'مرحبا'));
  });

  group('ArabicNormalizer — zero width chars', () {
    test('ZWNJ removed', () =>
        expect(normalizer.normalize('ك‌ل'), 'كل'));
  });

  group('ArabicNormalizer — matchesLetter', () {
    test('exact match', () =>
        expect(normalizer.matchesLetter('ك', 'ك'), isTrue));
    test('alef variant matches', () =>
        expect(normalizer.matchesLetter('أ', 'ا'), isTrue));
    test('ta marbuta matches ha', () =>
        expect(normalizer.matchesLetter('ة', 'ه'), isTrue));
    test('diacritised matches base', () =>
        expect(normalizer.matchesLetter('كَ', 'ك'), isTrue));
    test('wrong letter no match', () =>
        expect(normalizer.matchesLetter('ب', 'ك'), isFalse));
    test('empty user input no match', () =>
        expect(normalizer.matchesLetter('', 'ك'), isFalse));
  });

  group('ArabicNormalizer — disabled options', () {
    const strict = ArabicNormalizer(
      normalizeAlef: false,
      normalizeTaMarbuta: false,
      normalizeYaa: false,
    );
    test('alef not normalized when disabled', () =>
        expect(strict.normalize('أ'), 'أ'));
    test('ta marbuta not normalized when disabled', () =>
        expect(strict.normalize('ة'), 'ة'));
  });
}
