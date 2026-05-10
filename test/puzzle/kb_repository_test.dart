import 'package:flutter_test/flutter_test.dart';
import 'package:chabaka/puzzle/kb/kb_repository.dart';

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

List<KbEntry> _buildEntries() => [
      KbEntry(
        id: 1,
        word: 'علم',
        wordDisplay: 'علم',
        length: 3,
        category: KbCategory.common,
        clues: [KbClue(text: 'المعرفة', kind: KbClueKind.definition)],
      ),
      KbEntry(
        id: 2,
        word: 'عمل',
        wordDisplay: 'عمل',
        length: 3,
        category: KbCategory.common,
        clues: [KbClue(text: 'النشاط', kind: KbClueKind.definition)],
      ),
      KbEntry(
        id: 3,
        word: 'بحر',
        wordDisplay: 'بحر',
        length: 3,
        category: KbCategory.place,
        clues: [KbClue(text: 'ماء ملح', kind: KbClueKind.definition)],
      ),
      KbEntry(
        id: 4,
        word: 'كتاب',
        wordDisplay: 'كتاب',
        length: 4,
        category: KbCategory.common,
        clues: [KbClue(text: 'يُقرأ', kind: KbClueKind.definition)],
      ),
      KbEntry(
        id: 5,
        word: 'قمر',
        wordDisplay: 'قمر',
        length: 3,
        category: KbCategory.common,
        clues: [KbClue(text: 'يضيء الليل', kind: KbClueKind.definition)],
      ),
      KbEntry(
        id: 6,
        word: 'عصر',
        wordDisplay: 'عصر',
        length: 3,
        category: KbCategory.history,
        clues: [KbClue(text: 'حقبة زمنية', kind: KbClueKind.definition)],
      ),
    ];

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late InMemoryKbRepository repo;

  setUp(() {
    repo = InMemoryKbRepository(_buildEntries());
  });

  tearDown(() async {
    await repo.close();
  });

  group('InMemoryKbRepository — findMatching', () {
    test('filtre par longueur', () async {
      final results = await repo.findMatching(length: 3);
      expect(results.length, 5); // علم عمل بحر قمر عصر
      expect(results.every((e) => e.length == 3), isTrue);
    });

    test('aucun résultat pour longueur inconnue', () async {
      final results = await repo.findMatching(length: 10);
      expect(results, isEmpty);
    });

    test('contrainte lettre position 0', () async {
      final results = await repo.findMatching(
        length: 3,
        constraints: [LetterConstraint(position: 0, letter: 'ع')],
      );
      // علم + عمل + عصر commencent par ع
      expect(results.length, 3);
      expect(results.map((e) => e.word).toSet(),
          containsAll(['علم', 'عمل', 'عصر']));
    });

    test('contrainte lettre position intermédiaire', () async {
      final results = await repo.findMatching(
        length: 3,
        constraints: [LetterConstraint(position: 1, letter: 'ل')],
      );
      // علم : ع-ل-م ✓
      expect(results.length, 1);
      expect(results.first.word, 'علم');
    });

    test('deux contraintes combinées', () async {
      final results = await repo.findMatching(
        length: 3,
        constraints: [
          LetterConstraint(position: 0, letter: 'ع'),
          LetterConstraint(position: 2, letter: 'ل'),
        ],
      );
      // عمل : ع-م-ل ✓, علم : ع-ل-م ✗
      expect(results.length, 1);
      expect(results.first.word, 'عمل');
    });

    test('contrainte position hors-bornes → aucun résultat', () async {
      final results = await repo.findMatching(
        length: 3,
        constraints: [LetterConstraint(position: 10, letter: 'ع')],
      );
      expect(results, isEmpty);
    });

    test('exclusion par IDs', () async {
      final results = await repo.findMatching(
        length: 3,
        excludeIds: {1, 2}, // علم et عمل exclus
      );
      expect(results.none((e) => e.id == 1), isTrue);
      expect(results.none((e) => e.id == 2), isTrue);
      expect(results.length, 3); // بحر قمر عصر
    });

    test('limit respecté', () async {
      final results = await repo.findMatching(length: 3, limit: 2);
      expect(results.length, 2);
    });

    test('sans contraintes → tous les mots de la longueur', () async {
      final results = await repo.findMatching(length: 4);
      expect(results.length, 1);
      expect(results.first.word, 'كتاب');
    });
  });

  group('InMemoryKbRepository — countEntries', () {
    test('retourne le nombre total d\'entrées', () async {
      expect(await repo.countEntries(), 6);
    });
  });

  group('InMemoryKbRepository — close', () {
    test('close puis appel → StateError', () async {
      await repo.close();
      expect(
        () => repo.findMatching(length: 3),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('KbEntry — primaryClue', () {
    test('retourne l\'indice de priorité la plus basse', () {
      final entry = KbEntry(
        id: 99,
        word: 'test',
        wordDisplay: 'test',
        length: 4,
        category: KbCategory.common,
        clues: [
          KbClue(text: 'B', kind: KbClueKind.synonym, priority: 5),
          KbClue(text: 'A', kind: KbClueKind.definition, priority: 1),
          KbClue(text: 'C', kind: KbClueKind.context, priority: 3),
        ],
      );
      expect(entry.primaryClue?.text, 'A');
    });

    test('null si aucun indice', () {
      final entry = KbEntry(
        id: 100,
        word: 'test',
        wordDisplay: 'test',
        length: 4,
        category: KbCategory.common,
        clues: const [],
      );
      expect(entry.primaryClue, isNull);
    });
  });

  group('KbCategory', () {
    test('fromString reconnaît toutes les valeurs', () {
      for (final cat in KbCategory.values) {
        expect(KbCategory.fromString(cat.name), cat);
      }
    });

    test('fromString inconnu → common par défaut', () {
      expect(KbCategory.fromString('inconnu'), KbCategory.common);
    });
  });

  group('InMemoryKbRepository — perf', () {
    test('findMatching 5 000 entrées répond en < 5 ms', () async {
      // Construit un KB de 5 000 mots synthétiques de longueur 3 à 7.
      final entries = <KbEntry>[];
      const chars = 'علمبحرنوقشسكطابيدزوصفغحخجثذضظإأآة';
      for (var i = 0; i < 5000; i++) {
        final len = 3 + (i % 5);
        final word = List.generate(len, (j) => chars[(i + j) % chars.length]).join();
        entries.add(KbEntry(
          id: i + 1,
          word: word,
          wordDisplay: word,
          length: len,
          category: KbCategory.common,
          clues: [KbClue(text: 'indice $i', kind: KbClueKind.definition)],
        ));
      }
      final repo = InMemoryKbRepository(entries);

      final start = DateTime.now();
      await repo.findMatching(length: 3, limit: 50);
      final elapsed = DateTime.now().difference(start).inMilliseconds;

      expect(elapsed, lessThan(5),
          reason: 'findMatching doit répondre en < 5 ms même avec 5 000 entrées');
      await repo.close();
    });
  });

}

extension<T> on Iterable<T> {
  bool none(bool Function(T) test) => !any(test);
}
