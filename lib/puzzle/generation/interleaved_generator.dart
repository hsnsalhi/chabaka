/// Moteur V2 — InterleavedGenerator.
///
/// Approche : pour les tailles connues (5×5, 8×8, 16×13), utilise des patrons
/// de cellules validés qui garantissent que chaque CC aura ≥1 indice.
/// Pour les autres tailles, génère un patron par tuilage adaptatif.
///
/// Algorithme de remplissage : MRV backtracking (Most-Restricted Variable).
/// À chaque étape, le slot avec le moins de candidats KB est traité en premier.
/// Forward-checking léger : si un slot a 0 candidats → backtrack immédiatement.
///
/// Garanties :
///   R1 : toute CC a ≥1 indice (vérifiée par la propriété des patrons).
///   R5 : (0,0) = CC, grille pleine, aucune LC sans lettre.
///   Edge slots : certains slots n'ont pas de CC prédécesseure (démarrent en
///     bord de grille). Leurs LCs sont couvertes par le slot perpendiculaire.
///     Ces slots sont remplis par le backtracking mais sans clue affiché.
///
/// Drop-in replacement de R4Generator (implémente R4GeneratorApi).
library;

import 'dart:math';

import '../kb/kb_repository.dart';
import '../models.dart';
import 'topology.dart'; // R4GeneratorApi, TopologyConfig, Slot, Direction

// ---------------------------------------------------------------------------
// Représentation interne du patron
// ---------------------------------------------------------------------------

enum _CK { cc, lc }

// ---------------------------------------------------------------------------
// Patrons pré-validés
//
// Propriétés garanties pour chaque patron (vérifiées par script offline) :
//   (a) (0,0) = CC.
//   (b) R7 assoupli : aucune suite ≥5 de CCs en H ou V.
//   (c) Toute CC est la prédécesseure d'au moins un slot → ≥1 indice garanti.
//   (d) Toute LC appartient à au moins un slot ≥2 (H ou V).
//   (e) Des "edge slots" existent (run LC sans CC prédécesseure) — leurs LCs
//       sont couvertes par le slot perpendiculaire qui a une CC.
// ---------------------------------------------------------------------------

/// 5×5 Patron A — CC=5, 12 slots, longueurs {2,3,4,5}.
/// R7 maxRun=2. Toutes CCs ont ≥1 indice. 6 edge slots.
const List<List<_CK>> _pat5x5A = [
  [_CK.cc, _CK.lc, _CK.lc, _CK.lc, _CK.lc],  // r0
  [_CK.lc, _CK.lc, _CK.lc, _CK.lc, _CK.cc],  // r1
  [_CK.lc, _CK.lc, _CK.cc, _CK.cc, _CK.lc],  // r2
  [_CK.lc, _CK.lc, _CK.lc, _CK.lc, _CK.lc],  // r3
  [_CK.cc, _CK.lc, _CK.lc, _CK.lc, _CK.lc],  // r4
];

/// 5×5 Patron B — CC=5, 12 slots, longueurs {2,3,4,5}.
/// R7 maxRun=1. Toutes CCs ont ≥1 indice. 5 edge slots.
const List<List<_CK>> _pat5x5B = [
  [_CK.cc, _CK.lc, _CK.lc, _CK.lc, _CK.lc],  // r0
  [_CK.lc, _CK.lc, _CK.cc, _CK.lc, _CK.lc],  // r1
  [_CK.lc, _CK.cc, _CK.lc, _CK.lc, _CK.lc],  // r2
  [_CK.lc, _CK.lc, _CK.lc, _CK.lc, _CK.lc],  // r3
  [_CK.lc, _CK.cc, _CK.lc, _CK.lc, _CK.lc],  // r4
];

/// 8×8 Patron A — R7-strict + chaque LC dans slot CLUÉ (PO 2026-05-12).
/// Manuellement corrigé : (1,2) CC→LC pour rattacher (1,1) à un H slot.
/// CC=19/64 (30%).
const List<List<_CK>> _pat8x8A = [
  [_CK.cc, _CK.lc, _CK.lc, _CK.cc, _CK.lc, _CK.lc, _CK.cc, _CK.cc],  // r0
  [_CK.cc, _CK.lc, _CK.lc, _CK.lc, _CK.cc, _CK.cc, _CK.lc, _CK.lc],  // r1
  [_CK.lc, _CK.cc, _CK.lc, _CK.lc, _CK.lc, _CK.cc, _CK.lc, _CK.lc],  // r2
  [_CK.lc, _CK.cc, _CK.lc, _CK.lc, _CK.lc, _CK.lc, _CK.cc, _CK.lc],  // r3
  [_CK.cc, _CK.lc, _CK.lc, _CK.cc, _CK.lc, _CK.lc, _CK.lc, _CK.cc],  // r4
  [_CK.cc, _CK.lc, _CK.lc, _CK.lc, _CK.cc, _CK.lc, _CK.lc, _CK.lc],  // r5
  [_CK.lc, _CK.lc, _CK.cc, _CK.lc, _CK.lc, _CK.lc, _CK.lc, _CK.lc],  // r6
  [_CK.lc, _CK.cc, _CK.lc, _CK.lc, _CK.lc, _CK.cc, _CK.lc, _CK.lc],  // r7
];

/// 8×8 Patron B — manuellement corrigé : (1,2) CC→LC. CC=17/64 (27%).
const List<List<_CK>> _pat8x8B = [
  [_CK.cc, _CK.lc, _CK.lc, _CK.lc, _CK.cc, _CK.cc, _CK.lc, _CK.lc],  // r0
  [_CK.lc, _CK.cc, _CK.lc, _CK.lc, _CK.lc, _CK.lc, _CK.cc, _CK.cc],  // r1
  [_CK.lc, _CK.lc, _CK.lc, _CK.cc, _CK.lc, _CK.lc, _CK.lc, _CK.lc],  // r2
  [_CK.lc, _CK.lc, _CK.cc, _CK.lc, _CK.lc, _CK.cc, _CK.lc, _CK.lc],  // r3
  [_CK.cc, _CK.lc, _CK.lc, _CK.lc, _CK.lc, _CK.lc, _CK.cc, _CK.lc],  // r4
  [_CK.lc, _CK.cc, _CK.lc, _CK.lc, _CK.lc, _CK.lc, _CK.lc, _CK.cc],  // r5
  [_CK.lc, _CK.cc, _CK.lc, _CK.lc, _CK.cc, _CK.lc, _CK.lc, _CK.lc],  // r6
  [_CK.cc, _CK.lc, _CK.lc, _CK.lc, _CK.cc, _CK.lc, _CK.lc, _CK.lc],  // r7
];

/// 16×13 Patron — transcrit de topology.dart _patterns16x13[0].
const List<List<_CK>> _pat16x13 = [
  [_CK.cc, _CK.cc, _CK.cc, _CK.lc, _CK.lc, _CK.cc, _CK.cc, _CK.cc, _CK.lc, _CK.lc, _CK.lc, _CK.cc, _CK.cc],
  [_CK.lc, _CK.lc, _CK.lc, _CK.lc, _CK.cc, _CK.lc, _CK.lc, _CK.lc, _CK.cc, _CK.cc, _CK.lc, _CK.lc, _CK.lc],
  [_CK.lc, _CK.lc, _CK.lc, _CK.cc, _CK.lc, _CK.lc, _CK.lc, _CK.lc, _CK.lc, _CK.cc, _CK.lc, _CK.lc, _CK.lc],
  [_CK.cc, _CK.lc, _CK.lc, _CK.cc, _CK.cc, _CK.lc, _CK.lc, _CK.lc, _CK.lc, _CK.lc, _CK.cc, _CK.lc, _CK.lc],
  [_CK.cc, _CK.lc, _CK.lc, _CK.lc, _CK.cc, _CK.lc, _CK.lc, _CK.lc, _CK.lc, _CK.cc, _CK.lc, _CK.lc, _CK.cc],
  [_CK.lc, _CK.cc, _CK.lc, _CK.lc, _CK.lc, _CK.cc, _CK.lc, _CK.lc, _CK.lc, _CK.cc, _CK.lc, _CK.lc, _CK.lc],
  [_CK.lc, _CK.cc, _CK.cc, _CK.lc, _CK.lc, _CK.lc, _CK.cc, _CK.cc, _CK.lc, _CK.lc, _CK.lc, _CK.cc, _CK.lc],
  [_CK.cc, _CK.lc, _CK.lc, _CK.cc, _CK.lc, _CK.lc, _CK.lc, _CK.lc, _CK.cc, _CK.lc, _CK.lc, _CK.lc, _CK.cc],
  [_CK.cc, _CK.lc, _CK.lc, _CK.cc, _CK.lc, _CK.lc, _CK.lc, _CK.cc, _CK.lc, _CK.lc, _CK.cc, _CK.lc, _CK.lc],
  [_CK.lc, _CK.cc, _CK.lc, _CK.lc, _CK.cc, _CK.lc, _CK.lc, _CK.lc, _CK.lc, _CK.cc, _CK.lc, _CK.lc, _CK.lc],
  [_CK.lc, _CK.cc, _CK.lc, _CK.lc, _CK.cc, _CK.lc, _CK.lc, _CK.cc, _CK.lc, _CK.lc, _CK.lc, _CK.cc, _CK.lc],
  [_CK.cc, _CK.lc, _CK.lc, _CK.cc, _CK.lc, _CK.lc, _CK.lc, _CK.cc, _CK.lc, _CK.lc, _CK.lc, _CK.lc, _CK.lc],
  [_CK.lc, _CK.cc, _CK.lc, _CK.lc, _CK.lc, _CK.cc, _CK.cc, _CK.lc, _CK.lc, _CK.cc, _CK.lc, _CK.lc, _CK.cc],
  [_CK.lc, _CK.lc, _CK.cc, _CK.lc, _CK.lc, _CK.lc, _CK.lc, _CK.lc, _CK.cc, _CK.lc, _CK.lc, _CK.lc, _CK.lc],
  [_CK.lc, _CK.cc, _CK.lc, _CK.lc, _CK.cc, _CK.lc, _CK.lc, _CK.cc, _CK.lc, _CK.lc, _CK.cc, _CK.lc, _CK.lc],
  [_CK.cc, _CK.lc, _CK.lc, _CK.lc, _CK.lc, _CK.cc, _CK.lc, _CK.lc, _CK.lc, _CK.lc, _CK.cc, _CK.lc, _CK.lc],
];

// ---------------------------------------------------------------------------
// Sélection du patron selon la taille
// ---------------------------------------------------------------------------

/// Retourne le patron adapté à la taille (rows, cols) et à l'attempt.
/// Null si la taille est inconnue → fallback sur tuilage adaptatif.
List<List<_CK>>? _selectPattern(int rows, int cols, int attempt) {
  if (rows == 5 && cols == 5) return attempt.isEven ? _pat5x5A : _pat5x5B;
  if (rows == 8 && cols == 8) return attempt.isEven ? _pat8x8A : _pat8x8B;
  if (rows == 16 && cols == 13) return _pat16x13;
  return null;
}

// ---------------------------------------------------------------------------
// Extraction des slots depuis un patron List<List<_CK>>
// ---------------------------------------------------------------------------

List<Slot> _slotsFromPat(List<List<_CK>> pat) {
  final rows = pat.length;
  final cols = pat[0].length;
  final slots = <Slot>[];

  // Horizontaux.
  for (var r = 0; r < rows; r++) {
    var c = 0;
    while (c < cols) {
      if (pat[r][c] == _CK.lc) {
        final s = c;
        while (c < cols && pat[r][c] == _CK.lc) { c++; }
        if (c - s >= 2) {
          slots.add(Slot(
            direction: Direction.horizontal,
            startRow: r,
            startCol: s,
            length: c - s,
          ));
        }
      } else {
        c++;
      }
    }
  }

  // Verticaux.
  for (var c = 0; c < cols; c++) {
    var r = 0;
    while (r < rows) {
      if (pat[r][c] == _CK.lc) {
        final s = r;
        while (r < rows && pat[r][c] == _CK.lc) { r++; }
        if (r - s >= 2) {
          slots.add(Slot(
            direction: Direction.vertical,
            startRow: s,
            startCol: c,
            length: r - s,
          ));
        }
      } else {
        r++;
      }
    }
  }

  return slots;
}

// ---------------------------------------------------------------------------
// Tuilage adaptatif (pour les tailles inconnues)
// ---------------------------------------------------------------------------

/// Génère les slots d'un patron par tuilage avec pas [step].
///
/// Pattern : row%step==0 OU col%step==0 → CC ; reste → LC.
/// Garantit R7 pour step≥3 (max 2 CCs consécutives avant les LCs).
///
/// [jitterRng] : si non null, déplace certaines CCs d'une case.
List<Slot> buildInterleavedSlots(
  int rows,
  int cols, {
  int stepOverride = 0,
  Random? jitterRng,
}) {
  final maxDim = rows > cols ? rows : cols;
  final step = stepOverride > 0
      ? stepOverride
      : (maxDim <= 6 ? 3 : (maxDim <= 12 ? 4 : 5));

  final kinds = List<List<_CK>>.generate(
    rows,
    (_) => List.filled(cols, _CK.lc),
  );
  for (var r = 0; r < rows; r++) {
    for (var c = 0; c < cols; c++) {
      if (r % step == 0 || c % step == 0) kinds[r][c] = _CK.cc;
    }
  }

  if (jitterRng != null) { _applyJitter(kinds, rows, cols, jitterRng); }

  return _slotsFromPat(kinds);
}

void _applyJitter(List<List<_CK>> kinds, int rows, int cols, Random rng) {
  for (var r = 1; r < rows; r++) {
    for (var c = 1; c < cols; c++) {
      if (kinds[r][c] != _CK.cc) continue;
      if (rng.nextInt(5) > 0) continue; // 20 % de chance
      final dirs = [(0, 1), (0, -1), (1, 0), (-1, 0)]..shuffle(rng);
      for (final (dr, dc) in dirs) {
        final nr = r + dr;
        final nc = c + dc;
        if (nr < 1 || nc < 1 || nr >= rows || nc >= cols) continue;
        if (kinds[nr][nc] == _CK.cc) continue;
        kinds[r][c] = _CK.lc;
        kinds[nr][nc] = _CK.cc;
        if (_isValidKinds(kinds, rows, cols)) { break; }
        kinds[r][c] = _CK.cc;
        kinds[nr][nc] = _CK.lc;
      }
    }
  }
}

bool _isValidKinds(List<List<_CK>> kinds, int rows, int cols) {
  for (var r = 0; r < rows; r++) {
    var run = 0;
    for (var c = 0; c < cols; c++) {
      run = kinds[r][c] == _CK.cc ? run + 1 : 0;
      if (run >= 3) { return false; }
    }
  }
  for (var c = 0; c < cols; c++) {
    var run = 0;
    for (var r = 0; r < rows; r++) {
      run = kinds[r][c] == _CK.cc ? run + 1 : 0;
      if (run >= 3) { return false; }
    }
  }
  return _slotsFromPat(kinds).every((s) => s.length >= 2);
}

// ---------------------------------------------------------------------------
// Cache mémoire locale — évite les round-trips SQLite pendant le backtracking
// ---------------------------------------------------------------------------

/// Cache mémoire construit une fois avant le backtracking.
/// Toutes les opérations sont synchrones (pas d'await).
class _LocalKbCache {
  /// words[len] = liste de toutes les KbEntry de longueur `len`.
  final Map<int, List<KbEntry>> _byLength;

  _LocalKbCache(this._byLength);

  /// Charge depuis la KB tous les mots pour les longueurs requises.
  static Future<_LocalKbCache> build(
    KbRepository kb,
    Set<int> lengths, {
    int limitPerLength = 2000,
  }) async {
    final map = <int, List<KbEntry>>{};
    for (final len in lengths) {
      map[len] = await kb.findMatching(length: len, limit: limitPerLength);
    }
    return _LocalKbCache(map);
  }

  /// Cherche les candidats compatibles — synchrone, scan mémoire.
  List<KbEntry> findMatching({
    required int length,
    List<LetterConstraint> constraints = const [],
    Set<int> excludeIds = const {},
    int limit = 200,
  }) {
    final pool = _byLength[length] ?? const [];
    final results = <KbEntry>[];
    for (final entry in pool) {
      if (results.length >= limit) break;
      if (excludeIds.contains(entry.id)) continue;
      if (!_matches(entry.word, constraints)) continue;
      results.add(entry);
    }
    return results;
  }

  bool _matches(String word, List<LetterConstraint> constraints) {
    if (constraints.isEmpty) return true;
    final runes = word.runes.toList();
    for (final c in constraints) {
      if (c.position < 0 || c.position >= runes.length) return false;
      if (String.fromCharCode(runes[c.position]) != c.letter) return false;
    }
    return true;
  }

  bool covers(int length) =>
      (_byLength[length]?.isNotEmpty) ?? false;
}

// ---------------------------------------------------------------------------
// Compteur mutable partagé pour limiter les itérations de backtracking
// ---------------------------------------------------------------------------

class _Counter {
  int value = 0;
}

// ---------------------------------------------------------------------------
// État du backtracking
// ---------------------------------------------------------------------------

class _BtState {
  final int rows;
  final int cols;
  final List<List<String?>> letters;
  final Map<Slot, KbEntry> placed;

  // Accélération : pour chaque LC (r,c), liste des slots qui la couvrent.
  final Map<(int, int), List<Slot>> _coveringSlots;

  _BtState(this.rows, this.cols, List<Slot> allSlots)
      : letters = List.generate(rows, (_) => List.filled(cols, null)),
        placed = {},
        _coveringSlots = _buildCovering(allSlots);

  static Map<(int, int), List<Slot>> _buildCovering(List<Slot> slots) {
    final map = <(int, int), List<Slot>>{};
    for (final slot in slots) {
      for (final pos in slot.positions) {
        map.putIfAbsent(pos, () => []).add(slot);
      }
    }
    return map;
  }

  List<LetterConstraint> constraintsFor(Slot slot) {
    final res = <LetterConstraint>[];
    for (var i = 0; i < slot.length; i++) {
      final (r, c) = slot.positions[i];
      final l = letters[r][c];
      if (l != null) { res.add(LetterConstraint(position: i, letter: l)); }
    }
    return res;
  }

  Set<int> get excludedIds => placed.values.map((e) => e.id).toSet();

  void place(Slot slot, KbEntry entry) {
    placed[slot] = entry;
    final runes = entry.word.runes.toList();
    for (var i = 0; i < slot.length && i < runes.length; i++) {
      final (r, c) = slot.positions[i];
      letters[r][c] ??= String.fromCharCode(runes[i]);
    }
  }

  void unplace(Slot slot) {
    placed.remove(slot);
    for (var i = 0; i < slot.length; i++) {
      final (r, c) = slot.positions[i];
      // La lettre reste si un autre slot placé couvre cette position.
      final stillCovered = _coveringSlots[(r, c)]?.any(
        (other) => other != slot && placed.containsKey(other),
      ) ?? false;
      if (!stillCovered) { letters[r][c] = null; }
    }
  }
}

// ---------------------------------------------------------------------------
// InterleavedGenerator
// ---------------------------------------------------------------------------

class InterleavedGenerator implements R4GeneratorApi {
  final KbRepository kb;

  /// Nombre max de candidats chargés en mémoire par longueur.
  /// 2000 est suffisant pour la KB courante (~500 mots par longueur).
  static const int _cacheLimit = 2000;

  /// Nombre max de candidats tentés par slot pendant le backtracking.
  static const int _maxCandidatePool = 150;

  /// Nombre max d'itérations de backtracking (anti-boucle infinie).
  static const int _maxIterations = 500000;

  const InterleavedGenerator({required this.kb});

  @override
  Future<Grid?> generate(TopologyConfig config) async {
    for (var attempt = 0; attempt < config.maxRetries; attempt++) {
      if (attempt > 0) { await Future<void>.delayed(Duration.zero); }

      final seed = _ps(config.seed, attempt);
      final dl =
          DateTime.now().add(Duration(milliseconds: config.backtrackTimeoutMs));
      final rng = Random(seed);

      // ---- Patron pré-intégré (tailles connues) ----
      final prePat = _selectPattern(config.rows, config.cols, attempt);
      if (prePat != null) {
        final slots = _slotsFromPat(prePat);
        if (slots.isNotEmpty) {
          final cache = await _buildCache(slots);
          if (_cacheCoversAll(cache, slots)) {
            final state = _BtState(config.rows, config.cols, slots);
            if (_fillMRV(slots.toList(), state, rng, cache, dl)) {
              final grid = _buildGrid(
                config.rows, config.cols, slots, state, seed,
              );
              if (_isValid(grid)) { return grid; }
            }
          }
        }
      }

      // ---- Tuilage adaptatif (tailles inconnues ou fallback) ----
      final maxDim = config.rows > config.cols ? config.rows : config.cols;
      final steps = maxDim <= 6
          ? [3, 4]
          : (maxDim <= 12 ? [4, 5, 3] : [5, 4, 6]);

      for (final step in steps) {
        if (DateTime.now().isAfter(dl)) { break; }

        final slots = buildInterleavedSlots(
          config.rows,
          config.cols,
          stepOverride: step,
          jitterRng: attempt > 0 ? Random(seed ^ step) : null,
        );
        if (slots.isEmpty) { continue; }
        final cache = await _buildCache(slots);
        if (!_cacheCoversAll(cache, slots)) { continue; }

        final state = _BtState(config.rows, config.cols, slots);
        if (!_fillMRV(slots.toList(), state, rng, cache, dl)) { continue; }

        final grid = _buildGrid(
          config.rows, config.cols, slots, state, seed,
        );
        if (_isValid(grid)) { return grid; }
      }
    }
    return null;
  }

  // -------------------------------------------------------------------------
  // Cache local
  // -------------------------------------------------------------------------

  Future<_LocalKbCache> _buildCache(List<Slot> slots) async {
    final lengths = slots.map((s) => s.length).toSet();
    return _LocalKbCache.build(kb, lengths, limitPerLength: _cacheLimit);
  }

  bool _cacheCoversAll(_LocalKbCache cache, List<Slot> slots) {
    return slots.every((s) => cache.covers(s.length));
  }

  // -------------------------------------------------------------------------
  // MRV backtracking — synchrone (cache mémoire)
  // -------------------------------------------------------------------------

  bool _fillMRV(
    List<Slot> allSlots,
    _BtState state,
    Random rng,
    _LocalKbCache cache,
    DateTime deadline,
  ) {
    // Utilise une pile explicite (pas de récursion) pour éviter stack overflow
    // sur de grandes grilles avec beaucoup de backtracking.
    // Représentation : List<List<Slot>> restants à chaque niveau.
    // Mais l'approche récursive est plus lisible — on garde la récursion
    // avec un compteur d'itérations pour avorter proprement.
    final counter = _Counter();
    return _btStep(
      Set.of(allSlots),
      state,
      rng,
      cache,
      deadline,
      counter,
    );
  }

  bool _btStep(
    Set<Slot> remaining,
    _BtState state,
    Random rng,
    _LocalKbCache cache,
    DateTime deadline,
    _Counter counter,
  ) {
    if (remaining.isEmpty) { return true; }
    if (DateTime.now().isAfter(deadline)) { return false; }
    if (counter.value++ > _maxIterations) { return false; }

    // MRV : slot avec le moins de candidats en premier.
    Slot? bestSlot;
    List<KbEntry>? bestCands;
    var bestCount = _maxCandidatePool + 1;

    final excl = state.excludedIds;
    for (final slot in remaining) {
      final cands = cache.findMatching(
        length: slot.length,
        constraints: state.constraintsFor(slot),
        excludeIds: excl,
        limit: _maxCandidatePool,
      );
      if (cands.isEmpty) { return false; } // forward check
      if (cands.length < bestCount) {
        bestSlot = slot;
        bestCands = cands;
        bestCount = cands.length;
        if (bestCount == 1) { break; }
      }
    }

    if (bestSlot == null) { return false; }

    final shuffled = List.of(bestCands!)..shuffle(rng);
    final nextRemaining = Set.of(remaining)..remove(bestSlot);

    for (final entry in shuffled) {
      state.place(bestSlot, entry);
      if (_btStep(nextRemaining, state, rng, cache, deadline, counter)) {
        return true;
      }
      state.unplace(bestSlot);
    }

    return false;
  }

  // -------------------------------------------------------------------------
  // Construction de la Grid
  // -------------------------------------------------------------------------

  Grid _buildGrid(
    int rows,
    int cols,
    List<Slot> slots,
    _BtState state,
    int seed,
  ) {
    // Ensemble des positions LC.
    final isLc = <(int, int)>{};
    for (final slot in slots) {
      for (final pos in slot.positions) { isLc.add(pos); }
    }

    // Construction initiale : CC vide ou LC avec lettre.
    final cells = List<List<Cell>>.generate(rows, (r) {
      return List<Cell>.generate(cols, (c) {
        if (isLc.contains((r, c))) {
          return LetterCell(solution: state.letters[r][c] ?? '');
        }
        return ClueCell(clues: const []);
      });
    });

    // Attache les indices aux ClueCells prédécesseures.
    for (final entry in state.placed.entries) {
      final slot = entry.key;
      final kbEntry = entry.value;
      final primary = kbEntry.primaryClue;
      if (primary == null) { continue; }

      final (clueR, clueC) = slot.clueCellPos;
      if (clueR < 0 || clueC < 0 || clueR >= rows || clueC >= cols) { continue; }
      if (isLc.contains((clueR, clueC))) { continue; }

      final clue = Clue(
        text: primary.text,
        language: ClueLanguage.arabic,
        direction: slot.direction,
        solution: kbEntry.wordDisplay,
        startCell: Position(slot.startRow, slot.startCol),
      );
      final existing = cells[clueR][clueC];
      if (existing is ClueCell) {
        cells[clueR][clueC] = ClueCell(clues: [...existing.clues, clue]);
      }
    }

    return Grid(
      rows: rows,
      cols: cols,
      cells: cells,
      variant: GridVariant.standard,
      id: 'interleaved-$seed',
      title: 'شبكة اليوم',
      author: 'Chabaka',
    );
  }

  bool _isValid(Grid grid) {
    for (var r = 0; r < grid.rows; r++) {
      for (var c = 0; c < grid.cols; c++) {
        final cell = grid.cells[r][c];
        if (cell is ClueCell && cell.clues.isEmpty) { return false; }
        if (cell is LetterCell && cell.solution.isEmpty) { return false; }
      }
    }
    return true;
  }

  int _ps(int base, int attempt) =>
      attempt == 0 ? base : base * 1009 + attempt * 9973;
}
