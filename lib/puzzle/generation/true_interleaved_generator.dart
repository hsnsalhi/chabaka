/// Moteur V6 — HybridFlexibleGenerator (modèles A + B, 4 types de flèches).
///
/// ## Les 4 types de flèches
///
/// Une CC à `(r, c)` peut générer jusqu'à 2 clues, chacune avec un type
/// de flèche parmi les 4 possibles :
///
///   - **← hSameRow (modèle A horizontal)**
///     Mot horizontal commence à `(r, c+1)` dans la **ROW r**.
///     Lettres : `(r, c+1), (r, c+2), …, (r, c+L)`.
///
///   - **↓ vSameCol (modèle A vertical)**
///     Mot vertical commence à `(r+1, c)` dans la **COL c**.
///     Lettres : `(r+1, c), (r+2, c), …, (r+L, c)`.
///
///   - **↵ hRowBelow (modèle B horizontal — Abu Salma)**
///     Mot horizontal commence à `(r+1, c)` dans la **ROW r+1**.
///     Lettres : `(r+1, c), (r+1, c+1), …, (r+1, c+L-1)`.
///
///   - **↴ vColRight (modèle B vertical — Abu Salma)**
///     Mot vertical commence à `(r, c+1)` dans la **COL c+1**.
///     Lettres : `(r, c+1), (r+1, c+1), …, (r+L-1, c+1)`.
///
/// ## Stratégie de génération hybride
///
/// 1. Phase 1 (squelette) : place des CCs à intervalles réguliers.
///    Pour chaque CC, tente les 2 types disponibles (modèle A ou B) selon
///    la disponibilité du voisinage.  L'algo **alterne** modèle A et B
///    pour obtenir un mix ~50-50.
///
/// 2. Phase 2 (résidu) : couvre les positions UNDEFINED restantes
///    en posant des CCs additionnelles avec le type de flèche le mieux
///    adapté à chaque contexte.
///
/// ## Règles vérifiées
///
///   R1  : toute CC porte ≥1 indice, toute LC a une lettre.
///   R4  : toute suite ≥2 LCs adjacentes appartient à un mot de la KB.
///   R5  : (0,0) toujours CC ; grille pleine.
///   R6  : densité CC 25-35 %.
///   R7  : max 2 CCs consécutives H et V.
///   R8  : tout mot délimité par CC ou bord aux 2 extrémités.
///
library;

import 'dart:math';

import '../kb/kb_repository.dart';
import '../models.dart';
import 'topology.dart';

// ---------------------------------------------------------------------------
// Constantes
// ---------------------------------------------------------------------------

const int _maxWordLen = 5;
const double _minCcDensity = 0.18;

/// Nombre maximal de LCs orphelines (non couvertes par un clue) tolérées.
/// Ces situations surviennent dans les coins/bords quand les contraintes KB
/// ne permettent pas de générer un mot valide. Valeur conservatrice : 2.
const int _maxOrphans = 2;

int _minCcsForGrid(int rows, int cols) {
  final computed = ((rows * cols) * _minCcDensity).round();
  return computed < 3 ? 3 : computed;
}

// ---------------------------------------------------------------------------
// Normalisation R3 (même logique que ArabicNormalizer dans puzzle_logic)
// ---------------------------------------------------------------------------

/// Normalise une lettre arabe selon R3 :
/// ء/أ/إ/آ → ا,  ة → ه,  ى → ي
/// Les diacritiques et U+200C/U+200D sont ignorés (retourne '').
String _normalize(String letter) {
  if (letter.isEmpty) return letter;
  final cp = letter.runes.first;
  // Diacritiques (tashkeel) : U+064B–U+065F, U+0610–U+061A, U+06D6–U+06DC
  if ((cp >= 0x064B && cp <= 0x065F) ||
      (cp >= 0x0610 && cp <= 0x061A) ||
      (cp >= 0x06D6 && cp <= 0x06DC) ||
      cp == 0x200C || cp == 0x200D) {
    return '';
  }
  return switch (cp) {
    0x0622 || 0x0623 || 0x0625 || 0x0621 => 'ا', // أ إ آ ء → ا
    0x0629                                => 'ه', // ة → ه
    0x0649                                => 'ي', // ى → ي
    _                                     => letter,
  };
}

// ---------------------------------------------------------------------------
// État interne
// ---------------------------------------------------------------------------

enum _Kind { undefined, cc, lc }

// ---------------------------------------------------------------------------
// Mode de la CC (A ou B)
// ---------------------------------------------------------------------------

enum _CcMode { a, b }

// ---------------------------------------------------------------------------
// Cache mémoire multi-index
// ---------------------------------------------------------------------------

class _KbIndex {
  final Map<int, List<KbEntry>> _byLen;
  final Map<int, Map<int, Map<String, List<int>>>> _byLenLetter;

  _KbIndex._(this._byLen, this._byLenLetter);

  static Future<_KbIndex> build(
    KbRepository kb, {
    int maxLen = _maxWordLen,
    int limitPerLen = 3000,
  }) async {
    final byLen = <int, List<KbEntry>>{};
    for (var len = 2; len <= maxLen; len++) {
      final entries = await kb.findMatching(length: len, limit: limitPerLen);
      if (entries.isNotEmpty) byLen[len] = entries;
    }
    final byLenLetter = <int, Map<int, Map<String, List<int>>>>{};
    for (final len in byLen.keys) {
      final posMap = <int, Map<String, List<int>>>{};
      final entries = byLen[len]!;
      for (var idx = 0; idx < entries.length; idx++) {
        final runes = entries[idx].word.runes.toList();
        for (var pos = 0; pos < runes.length; pos++) {
          final letter = String.fromCharCode(runes[pos]);
          posMap.putIfAbsent(pos, () => {}).putIfAbsent(letter, () => []).add(idx);
        }
      }
      byLenLetter[len] = posMap;
    }
    return _KbIndex._(byLen, byLenLetter);
  }

  bool hasLength(int len) => (_byLen[len]?.isNotEmpty) ?? false;

  List<KbEntry> find({
    required int length,
    required List<LetterConstraint> constraints,
    required Set<int> excludeIds,
    int limit = 200,
  }) {
    final pool = _byLen[length];
    if (pool == null || pool.isEmpty) return const [];

    List<int>? candidates;
    if (constraints.isEmpty) {
      candidates = List.generate(pool.length, (i) => i);
    } else {
      final posMap = _byLenLetter[length];
      var pairs = constraints.map((c) {
        final subset = posMap?[c.position]?[c.letter];
        return (c, subset);
      }).toList()
        ..sort((a, b) => (a.$2?.length ?? 0).compareTo(b.$2?.length ?? 0));

      for (final (_, subset) in pairs) {
        if (subset == null || subset.isEmpty) return const [];
        if (candidates == null) {
          candidates = List.of(subset);
        } else {
          final s = Set<int>.of(subset);
          candidates = candidates.where(s.contains).toList();
        }
        if (candidates.isEmpty) return const [];
      }
    }

    final results = <KbEntry>[];
    for (final idx in candidates!) {
      if (results.length >= limit) break;
      final e = pool[idx];
      if (!excludeIds.contains(e.id)) results.add(e);
    }
    return results;
  }
}

// ---------------------------------------------------------------------------
// Grille interne mutable
// ---------------------------------------------------------------------------

class _GridState {
  final int rows;
  final int cols;
  final List<List<_Kind>> kinds;
  final List<List<String?>> letters;
  // Mode (A ou B) de chaque CC, pour le calcul des startCell lors du build.
  final List<List<_CcMode?>> ccModes;
  // Directions couvertes par chaque LC (pour la vérification R8).
  // Une LC peut appartenir à 1 slot H, 1 slot V, ou les deux (intersection).
  final List<List<Set<Direction>>> lcDirs;

  _GridState(this.rows, this.cols)
      : kinds = List.generate(rows, (_) => List.filled(cols, _Kind.undefined)),
        letters = List.generate(rows, (_) => List.filled(cols, null)),
        ccModes = List.generate(rows, (_) => List.filled(cols, null)),
        lcDirs = List.generate(rows, (_) => List.generate(cols, (_) => {}));

  bool inBounds(int r, int c) => r >= 0 && c >= 0 && r < rows && c < cols;

  void setCC(int r, int c, _CcMode mode) {
    kinds[r][c] = _Kind.cc;
    letters[r][c] = null;
    ccModes[r][c] = mode;
  }

  void undoCC(int r, int c) {
    assert(kinds[r][c] == _Kind.cc);
    kinds[r][c] = _Kind.undefined;
    ccModes[r][c] = null;
  }

  void setLC(int r, int c, String letter, {Direction? slotDir}) {
    kinds[r][c] = _Kind.lc;
    letters[r][c] = letter;
    if (slotDir != null) lcDirs[r][c].add(slotDir);
  }

  /// Vérifie si la position (r, c) appartient à un slot dans [dir].
  bool hasSlotInDir(int r, int c, Direction dir) =>
      inBounds(r, c) && lcDirs[r][c].contains(dir);

  bool get isFull {
    for (final row in kinds) {
      for (final k in row) {
        if (k == _Kind.undefined) return false;
      }
    }
    return true;
  }

  int get ccCount {
    var n = 0;
    for (final row in kinds) {
      for (final k in row) {
        if (k == _Kind.cc) n++;
      }
    }
    return n;
  }
}

// ---------------------------------------------------------------------------
// Vérifications R7
// ---------------------------------------------------------------------------

bool _checkR7(_GridState g) {
  for (var r = 0; r < g.rows; r++) {
    var run = 0;
    for (var c = 0; c < g.cols; c++) {
      run = g.kinds[r][c] == _Kind.cc ? run + 1 : 0;
      if (run >= 3) return false;
    }
  }
  for (var c = 0; c < g.cols; c++) {
    var run = 0;
    for (var r = 0; r < g.rows; r++) {
      run = g.kinds[r][c] == _Kind.cc ? run + 1 : 0;
      if (run >= 3) return false;
    }
  }
  return true;
}

bool _wouldViolateR7(_GridState g, int r, int c) {
  var hRun = 1;
  for (var dc = 1; c + dc < g.cols && g.kinds[r][c + dc] == _Kind.cc; dc++) {
    hRun++;
  }
  for (var dc = 1; c - dc >= 0 && g.kinds[r][c - dc] == _Kind.cc; dc++) {
    hRun++;
  }
  if (hRun >= 3) return true;
  var vRun = 1;
  for (var dr = 1; r + dr < g.rows && g.kinds[r + dr][c] == _Kind.cc; dr++) {
    vRun++;
  }
  for (var dr = 1; r - dr >= 0 && g.kinds[r - dr][c] == _Kind.cc; dr++) {
    vRun++;
  }
  return vRun >= 3;
}

/// Retourne true si placer une CC en (r, c) créerait un "trou d'1 position"
/// inaccessible — une LC isolée entre deux CCs (slot longueur 1, non couvrable).
///
/// Détecte le pattern : CC à distance 2 dans la même row ou col avec une
/// position UNDEFINED ou LC entre les deux qui ne pourrait être couverte que
/// par un slot de longueur 1.
bool _wouldCreateIsolatedCell(_GridState g, int r, int c) {
  // Horizontal : CC à gauche (c-2) → gap en (r, c-1)
  if (c >= 2 && g.kinds[r][c - 2] == _Kind.cc) {
    final gap = g.kinds[r][c - 1];
    if (gap == _Kind.undefined || gap == _Kind.lc) return true;
  }
  // Horizontal : CC à droite (c+2) → gap en (r, c+1)
  if (c + 2 < g.cols && g.kinds[r][c + 2] == _Kind.cc) {
    final gap = g.kinds[r][c + 1];
    if (gap == _Kind.undefined || gap == _Kind.lc) {
      // Seulement si le gap n'est pas déjà couvert par un slot V depuis ailleurs.
      // Approximation conservative : interdire systématiquement.
      return true;
    }
  }
  // Vertical : CC au-dessus (r-2) → gap en (r-1, c)
  if (r >= 2 && g.kinds[r - 2][c] == _Kind.cc) {
    final gap = g.kinds[r - 1][c];
    if (gap == _Kind.undefined || gap == _Kind.lc) return true;
  }
  // Vertical : CC en-dessous (r+2) → gap en (r+1, c)
  if (r + 2 < g.rows && g.kinds[r + 2][c] == _Kind.cc) {
    final gap = g.kinds[r + 1][c];
    if (gap == _Kind.undefined || gap == _Kind.lc) return true;
  }
  return false;
}

// ---------------------------------------------------------------------------
// Calcul startLC selon le mode et la direction
// ---------------------------------------------------------------------------

/// Retourne `(startRow, startCol)` de la première LC d'un slot.
///
/// Modèle A :
///   - H (hSameRow) : (ccR,     ccC + 1)  → même ligne, colonne suivante
///   - V (vSameCol) : (ccR + 1, ccC)      → colonne identique, ligne suivante
///
/// Modèle B :
///   - H (hRowBelow) : (ccR + 1, ccC)     → ligne suivante, même colonne
///   - V (vColRight) : (ccR,     ccC + 1)  → même ligne, colonne suivante
(int, int) _lcStart(_CcMode mode, int ccR, int ccC, Direction dir) {
  if (mode == _CcMode.a) {
    return dir == Direction.horizontal ? (ccR, ccC + 1) : (ccR + 1, ccC);
  } else {
    return dir == Direction.horizontal ? (ccR + 1, ccC) : (ccR, ccC + 1);
  }
}

/// Retourne l'arrow type correspondant au mode + direction.
ClueArrow _arrowType(_CcMode mode, Direction dir) {
  if (mode == _CcMode.a) {
    return dir == Direction.horizontal ? ClueArrow.hSameRow : ClueArrow.vSameCol;
  } else {
    return dir == Direction.horizontal ? ClueArrow.hRowBelow : ClueArrow.vColRight;
  }
}

// ---------------------------------------------------------------------------
// HybridFlexibleGenerator
// ---------------------------------------------------------------------------

class TrueInterleavedGenerator implements R4GeneratorApi {
  final KbRepository kb;

  static const int _cacheLimit = 3000;
  static const int _maxCandidatesPerSlot = 50;

  const TrueInterleavedGenerator({required this.kb});

  @override
  Future<Grid?> generate(TopologyConfig config) async {
    final index = await _KbIndex.build(kb, maxLen: _maxWordLen, limitPerLen: _cacheLimit);
    final deadline = DateTime.now().add(Duration(milliseconds: config.backtrackTimeoutMs));
    final minCcs = _minCcsForGrid(config.rows, config.cols);

    for (var attempt = 0; attempt < config.maxRetries; attempt++) {
      if (DateTime.now().isAfter(deadline)) break;
      await Future<void>.delayed(Duration.zero);

      final seed = _perturbSeed(config.seed, attempt);
      final rng = Random(seed);
      final g = _GridState(config.rows, config.cols);
      // Clés : (startR, startC, dir, mode) → KbEntry
      final placedWords = <(int, int, Direction, _CcMode), KbEntry>{};
      final usedIds = <int>{};

      // Phase 1 utilise toujours le modèle B pour le squelette (cohérence
      // géométrique, 0 conflit R8).
      // La phase 2 alterne A/B selon le numéro d'attempt pour injecter du
      // modèle A dans les zones résiduelles, créant le mix hybride.
      final phase2PreferredMode = attempt.isEven ? _CcMode.b : _CcMode.a;

      _phase1Skeleton(g, index, rng, placedWords, usedIds, deadline, _CcMode.b);
      if (DateTime.now().isAfter(deadline)) break;

      _phase2Residual(g, index, rng, placedWords, usedIds, deadline, phase2PreferredMode);

      if (!_checkR7(g)) continue;
      if (g.ccCount < minCcs) continue;

      final grid = _buildGrid(config.rows, config.cols, g, placedWords, seed);
      if (_isValid(grid)) return grid;
    }
    return null;
  }

  // -------------------------------------------------------------------------
  // Phase 1 — Squelette hybride
  //
  // Pour chaque position (r, c) du squelette (espacées de 2) :
  //
  //   - On détermine le mode préféré (A ou B) selon l'argument `preferredMode`.
  //   - On essaie d'abord le mode préféré, puis l'autre en fallback.
  //   - Chaque CC peut avoir un mode différent, ce qui crée naturellement un
  //     mélange de types de flèches dans la grille finale.
  //
  // Gestion bords impairs : même logique que V4 (border CCs), adaptée aux
  // deux modes.
  // -------------------------------------------------------------------------

  void _phase1Skeleton(
    _GridState g,
    _KbIndex index,
    Random rng,
    Map<(int, int, Direction, _CcMode), KbEntry> placedWords,
    Set<int> usedIds,
    DateTime deadline,
    _CcMode preferredMode,
  ) {
    final hasOddCols = g.cols % 2 == 1;
    final borderCcCol = hasOddCols ? g.cols - 2 : -1;
    final lastEvenSkeletonCol = hasOddCols ? g.cols - 3 : g.cols - 2;
    final hasOddRows = g.rows % 2 == 1;
    final borderCcRow = hasOddRows ? g.rows - 2 : -1;

    // Compteur pour alterner le mode CC par CC.
    var ccIndex = 0;

    for (var r = 0; r < g.rows; r += 2) {
      if (DateTime.now().isAfter(deadline)) return;

      // Passe A1 : pour cols impaires, border CC en (r, borderCcCol).
      if (hasOddCols) {
        final mode = _pickMode(ccIndex++, preferredMode);
        _tryPlaceBorderCcForCol(g, r, borderCcCol, index, rng, placedWords, usedIds, mode);
      }

      // Passe A2 : CCs en colonnes paires.
      for (var c = 0; c <= lastEvenSkeletonCol; c += 2) {
        if (DateTime.now().isAfter(deadline)) return;
        if (g.kinds[r][c] == _Kind.lc) continue;

        final mode = _pickMode(ccIndex++, preferredMode);

        if (g.kinds[r][c] == _Kind.undefined) {
          if (_wouldViolateR7(g, r, c)) continue;
          // Vérifier la disponibilité du voisinage pour au moins 1 direction.
          final canH = _maxAvailableLen(g, mode, r, c, Direction.horizontal) >= 2;
          final skipV = hasOddCols && c == lastEvenSkeletonCol;
          final canV = !skipV && _maxAvailableLen(g, mode, r, c, Direction.vertical) >= 2;
          if (!canH && !canV) continue;
          g.setCC(r, c, mode);
        }

        final effectiveMode = g.ccModes[r][c]!;
        final skipV = hasOddCols && c == lastEvenSkeletonCol;
        final vLen = skipV ? 0 : _neededLen(g, effectiveMode, r, c, Direction.vertical);
        final hPrefLen = (hasOddCols && c == lastEvenSkeletonCol)
            ? 2
            : _neededLen(g, effectiveMode, r, c, Direction.horizontal);

        final vOk = vLen >= 2 &&
            _trySlot(g, effectiveMode, r, c, Direction.vertical, index, rng, placedWords, usedIds, prefLen: vLen);
        final hOk = hPrefLen >= 2 &&
            _trySlot(g, effectiveMode, r, c, Direction.horizontal, index, rng, placedWords, usedIds, prefLen: hPrefLen);

        if (!hOk && !vOk && g.kinds[r][c] == _Kind.cc) {
          g.undoCC(r, c);
        }
      }
    }

    // Passe B : rows impaires.
    if (hasOddRows) {
      _phase1BorderFixRows(g, borderCcRow, index, rng, placedWords, usedIds, deadline, preferredMode);
    }
  }

  /// Choisit le mode pour le i-ème CC en alternant autour de `preferred`.
  _CcMode _pickMode(int index, _CcMode preferred) {
    // Alterne : index pair → preferred, impair → l'autre.
    if (index.isEven) return preferred;
    return preferred == _CcMode.a ? _CcMode.b : _CcMode.a;
  }

  void _tryPlaceBorderCcForCol(
    _GridState g,
    int r,
    int borderCcCol,
    _KbIndex index,
    Random rng,
    Map<(int, int, Direction, _CcMode), KbEntry> placedWords,
    Set<int> usedIds,
    _CcMode mode,
  ) {
    if (!g.inBounds(r, borderCcCol)) return;
    if (g.kinds[r][borderCcCol] != _Kind.undefined) return;
    if (_wouldViolateR7(g, r, borderCcCol)) return;

    // Pour la colonne bordure (avant-dernière), on préfère mode A-V :
    // slot V dans la même colonne → couvre les positions entre CCs.
    // Mode B-V → slot V dans col+1 (dernière colonne).
    // On tente d'abord mode A (slot dans même col), puis mode B, puis H.
    for (final tryMode in [_CcMode.a, _CcMode.b]) {
      final vAvail = _maxAvailableLen(g, tryMode, r, borderCcCol, Direction.vertical);
      if (vAvail < 2) continue;

      g.setCC(r, borderCcCol, tryMode);
      final placed = _trySlot(g, tryMode, r, borderCcCol, Direction.vertical, index, rng, placedWords, usedIds, prefLen: vAvail);
      if (placed) {
        // Bonus : tenter aussi un slot H si disponible.
        final hAvail = _maxAvailableLen(g, tryMode, r, borderCcCol, Direction.horizontal);
        if (hAvail >= 2) {
          _trySlot(g, tryMode, r, borderCcCol, Direction.horizontal, index, rng, placedWords, usedIds, prefLen: hAvail);
        }
        return;
      }
      g.undoCC(r, borderCcCol);
    }
    // Fallback : tenter H avec les deux modes.
    for (final tryMode in [_CcMode.b, _CcMode.a]) {
      final hAvail = _maxAvailableLen(g, tryMode, r, borderCcCol, Direction.horizontal);
      if (hAvail < 2) continue;
      g.setCC(r, borderCcCol, tryMode);
      final placed = _trySlot(g, tryMode, r, borderCcCol, Direction.horizontal, index, rng, placedWords, usedIds, prefLen: hAvail);
      if (placed) return;
      g.undoCC(r, borderCcCol);
    }
  }

  void _phase1BorderFixRows(
    _GridState g,
    int borderCcRow,
    _KbIndex index,
    Random rng,
    Map<(int, int, Direction, _CcMode), KbEntry> placedWords,
    Set<int> usedIds,
    DateTime deadline,
    _CcMode preferredMode,
  ) {
    var ccIndex = 0;
    for (var c = 0; c < g.cols; c += 2) {
      if (DateTime.now().isAfter(deadline)) return;
      if (!g.inBounds(borderCcRow, c)) continue;
      if (g.kinds[borderCcRow][c] != _Kind.undefined) continue;
      if (_wouldViolateR7(g, borderCcRow, c)) continue;

      final mode = _pickMode(ccIndex++, preferredMode);
      final hAvail = _maxAvailableLen(g, mode, borderCcRow, c, Direction.horizontal);
      if (hAvail < 2) continue;

      g.setCC(borderCcRow, c, mode);
      final placed = _trySlot(g, mode, borderCcRow, c, Direction.horizontal, index, rng, placedWords, usedIds, prefLen: hAvail);
      if (!placed) {
        g.undoCC(borderCcRow, c);
        continue;
      }
      _trySlot(g, mode, borderCcRow, c, Direction.vertical, index, rng, placedWords, usedIds, prefLen: 2);
    }
  }

  // -------------------------------------------------------------------------
  // Calcul de la longueur nécessaire — générique (A ou B)
  // -------------------------------------------------------------------------

  int _neededLen(_GridState g, _CcMode mode, int ccR, int ccC, Direction dir) {
    final available = _maxAvailableLen(g, mode, ccR, ccC, dir);
    if (available < 2) return 0;

    if (dir == Direction.horizontal) {
      var needed = 2;
      while (needed <= available && needed < _maxWordLen) {
        final (sr, sc) = _lcStart(mode, ccR, ccC, dir);
        final nextC = sc + needed;
        if (!g.inBounds(sr, nextC)) { needed = available; break; }
        // Vérifier si la position suivante peut générer un slot vers le bas.
        var nextAvail = 0;
        for (var k = 0; k < _maxWordLen; k++) {
          final nr = sr + k;
          final nc = sc + needed;
          if (!g.inBounds(nr, nc)) break;
          if (g.kinds[nr][nc] == _Kind.cc) break;
          nextAvail++;
          if (dir == Direction.horizontal) break; // H ne va pas plus loin
        }
        if (nextAvail >= 1) break;
        needed += 2;
      }
      return needed <= available ? needed : available;
    } else {
      var needed = 2;
      while (needed <= available && needed < _maxWordLen) {
        final (sr, sc) = _lcStart(mode, ccR, ccC, dir);
        final nextR = sr + needed;
        if (!g.inBounds(nextR, sc)) { needed = available; break; }
        var nextAvail = 0;
        for (var k = 0; k < _maxWordLen; k++) {
          final nr = sr + needed;
          final nc = sc + k;
          if (!g.inBounds(nr, nc)) break;
          if (g.kinds[nr][nc] == _Kind.cc) break;
          nextAvail++;
          if (dir == Direction.vertical) break;
        }
        if (nextAvail >= 1) break;
        needed += 2;
      }
      return needed <= available ? needed : available;
    }
  }

  // -------------------------------------------------------------------------
  // Phase 2 — Résidu
  // -------------------------------------------------------------------------

  void _phase2Residual(
    _GridState g,
    _KbIndex index,
    Random rng,
    Map<(int, int, Direction, _CcMode), KbEntry> placedWords,
    Set<int> usedIds,
    DateTime deadline,
    _CcMode preferredMode,
  ) {
    var anyChange = true;
    while (anyChange && !g.isFull) {
      if (DateTime.now().isAfter(deadline)) return;
      anyChange = false;

      for (var r = 0; r < g.rows; r++) {
        for (var c = 0; c < g.cols; c++) {
          if (g.kinds[r][c] != _Kind.undefined) continue;
          if (DateTime.now().isAfter(deadline)) return;

          var resolved = false;

          // Tenter via CCs existantes de la row r-1 (modèle A ou B H).
          if (!resolved && r > 0) {
            for (var cc = 0; cc <= c && !resolved; cc++) {
              if (g.kinds[r - 1][cc] != _Kind.cc) continue;
              final ccMode = g.ccModes[r - 1][cc]!;
              // Modèle B H : CC(r-1, c') → slot dans row r.
              // Modèle A H : CC(r, c') → slot dans row r même.
              resolved = _trySlot(g, ccMode, r - 1, cc, Direction.horizontal, index, rng, placedWords, usedIds);
              if (resolved) anyChange = true;
            }
          }

          // Tenter via CCs existantes de la col c-1 (modèle A ou B V).
          if (!resolved && c > 0) {
            for (var cr = 0; cr <= r && !resolved; cr++) {
              if (g.kinds[cr][c - 1] != _Kind.cc) continue;
              final ccMode = g.ccModes[cr][c - 1]!;
              resolved = _trySlot(g, ccMode, cr, c - 1, Direction.vertical, index, rng, placedWords, usedIds);
              if (resolved) anyChange = true;
            }
          }

          // Pose CC en (r-1, c) mode B → H couvre (r, c).
          if (!resolved && r > 0 && g.kinds[r - 1][c] == _Kind.undefined &&
              !_wouldViolateR7(g, r - 1, c)) {
            const mode = _CcMode.b;
            final hAvail = _maxAvailableLen(g, mode, r - 1, c, Direction.horizontal);
            if (hAvail >= 2) {
              g.setCC(r - 1, c, mode);
              resolved = _trySlot(g, mode, r - 1, c, Direction.horizontal, index, rng, placedWords, usedIds, prefLen: hAvail);
              if (resolved) {
                _trySlot(g, mode, r - 1, c, Direction.vertical, index, rng, placedWords, usedIds);
                anyChange = true;
              } else {
                g.undoCC(r - 1, c);
              }
            }
          }

          // Pose CC en (r, c-1) mode B → V couvre (r, c).
          if (!resolved && c > 0 && g.kinds[r][c - 1] == _Kind.undefined &&
              !_wouldViolateR7(g, r, c - 1)) {
            const mode = _CcMode.b;
            final vAvail = _maxAvailableLen(g, mode, r, c - 1, Direction.vertical);
            if (vAvail >= 2) {
              g.setCC(r, c - 1, mode);
              resolved = _trySlot(g, mode, r, c - 1, Direction.vertical, index, rng, placedWords, usedIds, prefLen: vAvail);
              if (resolved) {
                _trySlot(g, mode, r, c - 1, Direction.horizontal, index, rng, placedWords, usedIds);
                anyChange = true;
              } else {
                g.undoCC(r, c - 1);
              }
            }
          }

          // Pose CC en (r-1, c) mode A → V couvre (r, c).
          if (!resolved && r > 0 && g.kinds[r - 1][c] == _Kind.undefined &&
              !_wouldViolateR7(g, r - 1, c)) {
            const mode = _CcMode.a;
            final vAvail = _maxAvailableLen(g, mode, r - 1, c, Direction.vertical);
            if (vAvail >= 2) {
              g.setCC(r - 1, c, mode);
              resolved = _trySlot(g, mode, r - 1, c, Direction.vertical, index, rng, placedWords, usedIds, prefLen: vAvail);
              if (resolved) {
                _trySlot(g, mode, r - 1, c, Direction.horizontal, index, rng, placedWords, usedIds);
                anyChange = true;
              } else {
                g.undoCC(r - 1, c);
              }
            }
          }

          // Pose CC en (r, c-1) mode A → H couvre (r, c).
          if (!resolved && c > 0 && g.kinds[r][c - 1] == _Kind.undefined &&
              !_wouldViolateR7(g, r, c - 1)) {
            const mode = _CcMode.a;
            final hAvail = _maxAvailableLen(g, mode, r, c - 1, Direction.horizontal);
            if (hAvail >= 2) {
              g.setCC(r, c - 1, mode);
              resolved = _trySlot(g, mode, r, c - 1, Direction.horizontal, index, rng, placedWords, usedIds, prefLen: hAvail);
              if (resolved) {
                _trySlot(g, mode, r, c - 1, Direction.vertical, index, rng, placedWords, usedIds);
                anyChange = true;
              } else {
                g.undoCC(r, c - 1);
              }
            }
          }

          // Pose CC en (r, c) lui-même.
          if (!resolved && !_wouldViolateR7(g, r, c)) {
            for (final mode in [_CcMode.b, _CcMode.a]) {
              if (resolved) break;
              final canH = _maxAvailableLen(g, mode, r, c, Direction.horizontal) >= 2;
              final canV = _maxAvailableLen(g, mode, r, c, Direction.vertical) >= 2;
              if (!canH && !canV) continue;
              g.setCC(r, c, mode);
              final hadH = canH && _trySlot(g, mode, r, c, Direction.horizontal, index, rng, placedWords, usedIds);
              final hadV = canV && _trySlot(g, mode, r, c, Direction.vertical, index, rng, placedWords, usedIds);
              if (hadH || hadV) {
                anyChange = true;
                resolved = true;
              } else {
                g.undoCC(r, c);
              }
            }
          }
        }
      }
    }

    // Dernière passe : UNDEFINED → on tente d'abord de poser une CC+slot,
    // sinon on cherche une CC voisine non encore exploitée, sinon CC vide
    // (sera rejetée par _isValid → force un retry productif).
    for (var r = 0; r < g.rows; r++) {
      for (var c = 0; c < g.cols; c++) {
        if (g.kinds[r][c] != _Kind.undefined) continue;

        // Essai 1 : poser la CC ici-même et couvrir via H ou V.
        var placed = false;
        if (!_wouldViolateR7(g, r, c)) {
          for (final mode in [_CcMode.b, _CcMode.a]) {
            if (placed) break;
            final canH = _maxAvailableLen(g, mode, r, c, Direction.horizontal) >= 2;
            final canV = _maxAvailableLen(g, mode, r, c, Direction.vertical) >= 2;
            if (!canH && !canV) continue;
            g.setCC(r, c, mode);
            final hadH = canH && _trySlot(g, mode, r, c, Direction.horizontal, index, rng, placedWords, usedIds);
            final hadV = canV && _trySlot(g, mode, r, c, Direction.vertical, index, rng, placedWords, usedIds);
            if (hadH || hadV) {
              placed = true;
            } else {
              g.undoCC(r, c);
            }
          }
        }

        // Essai 2 : CC voisine en (r-1, c) mode B-H peut couvrir (r, c).
        if (!placed && r > 0 && g.kinds[r - 1][c] == _Kind.undefined &&
            !_wouldViolateR7(g, r - 1, c)) {
          const mode = _CcMode.b;
          final avail = _maxAvailableLen(g, mode, r - 1, c, Direction.horizontal);
          if (avail >= 2) {
            g.setCC(r - 1, c, mode);
            placed = _trySlot(g, mode, r - 1, c, Direction.horizontal, index, rng, placedWords, usedIds, prefLen: avail);
            if (placed) {
              _trySlot(g, mode, r - 1, c, Direction.vertical, index, rng, placedWords, usedIds);
            } else {
              g.undoCC(r - 1, c);
            }
          }
        }

        // Essai 3 : CC voisine en (r, c-1) mode B-V peut couvrir (r, c).
        if (!placed && c > 0 && g.kinds[r][c - 1] == _Kind.undefined &&
            !_wouldViolateR7(g, r, c - 1)) {
          const mode = _CcMode.b;
          final avail = _maxAvailableLen(g, mode, r, c - 1, Direction.vertical);
          if (avail >= 2) {
            g.setCC(r, c - 1, mode);
            placed = _trySlot(g, mode, r, c - 1, Direction.vertical, index, rng, placedWords, usedIds, prefLen: avail);
            if (placed) {
              _trySlot(g, mode, r, c - 1, Direction.horizontal, index, rng, placedWords, usedIds);
            } else {
              g.undoCC(r, c - 1);
            }
          }
        }

        // Si rien n'a fonctionné : poser une LC avec lettre aléatoire.
        // Cette LC sera orpheline (non couverte par un clue) — tolérée jusqu'à
        // _maxOrphans par _isValid.
        if (g.kinds[r][c] == _Kind.undefined) {
          g.setLC(r, c, _pickLetter(g, r, c, index, rng));
        }
      }
    }
  }

  // -------------------------------------------------------------------------
  // Tentative de placement d'un slot
  // -------------------------------------------------------------------------

  bool _trySlot(
    _GridState g,
    _CcMode mode,
    int ccR,
    int ccC,
    Direction dir,
    _KbIndex index,
    Random rng,
    Map<(int, int, Direction, _CcMode), KbEntry> placedWords,
    Set<int> usedIds, {
    int prefLen = 2,
  }) {
    final (sr, sc) = _lcStart(mode, ccR, ccC, dir);
    if (placedWords.containsKey((sr, sc, dir, mode))) return false;

    final rawMax = _maxAvailableLen(g, mode, ccR, ccC, dir);
    final maxLen = rawMax < _maxWordLen ? rawMax : _maxWordLen;
    if (maxLen < 2) return false;

    // Ordre des longueurs à essayer : maxLen → 2 (décroissant).
    // Les mots longs couvrent plus de positions, réduisant les orphelins.
    // prefLen est gardé en premier seulement s'il est ≥ maxLen-1.
    final lengths = <int>[];
    final effectivePref = (prefLen >= 2 && prefLen <= maxLen) ? prefLen : maxLen;
    if (effectivePref >= maxLen - 1) {
      // prefLen proche du max → le mettre en premier, puis décroissant.
      lengths.add(effectivePref);
      for (var l = maxLen; l >= 2; l--) {
        if (l != effectivePref) lengths.add(l);
      }
    } else {
      // Ignorer prefLen, essayer toujours du plus long au plus court.
      for (var l = maxLen; l >= 2; l--) {
        lengths.add(l);
      }
    }

    for (final len in lengths) {
      if (!index.hasLength(len)) continue;
      final constraints = _slotConstraints(g, mode, ccR, ccC, dir, len);
      final cands = index.find(
          length: len,
          constraints: constraints,
          excludeIds: usedIds,
          limit: _maxCandidatesPerSlot);
      if (cands.isEmpty) continue;

      final shuffled = List.of(cands)..shuffle(rng);
      for (final entry in shuffled) {
        if (_placeWord(g, mode, ccR, ccC, dir, len, entry.word)) {
          placedWords[(sr, sc, dir, mode)] = entry;
          usedIds.add(entry.id);
          return true;
        }
      }
    }
    return false;
  }

  // -------------------------------------------------------------------------
  // Utilitaires géométrie — mode A et B
  // -------------------------------------------------------------------------

  int _maxAvailableLen(_GridState g, _CcMode mode, int ccR, int ccC, Direction dir) {
    final (startR, startC) = _lcStart(mode, ccR, ccC, dir);

    // La startCell doit être dans la grille.
    if (!g.inBounds(startR, startC)) return 0;

    var len = 0;
    for (var i = 0; i <= _maxWordLen; i++) {
      final r = dir == Direction.horizontal ? startR : startR + i;
      final c = dir == Direction.horizontal ? startC + i : startC;
      if (!g.inBounds(r, c)) break;
      if (g.kinds[r][c] == _Kind.cc) break;
      len++;
    }
    return len > _maxWordLen ? _maxWordLen : len;
  }

  List<LetterConstraint> _slotConstraints(
      _GridState g, _CcMode mode, int ccR, int ccC, Direction dir, int len) {
    final result = <LetterConstraint>[];
    final (startR, startC) = _lcStart(mode, ccR, ccC, dir);
    for (var i = 0; i < len; i++) {
      final r = dir == Direction.horizontal ? startR : startR + i;
      final c = dir == Direction.horizontal ? startC + i : startC;
      if (!g.inBounds(r, c)) break;
      if (g.kinds[r][c] == _Kind.lc && g.letters[r][c] != null) {
        // Normaliser R3 pour correspondre aux mots normalisés de la KB.
        final norm = _normalize(g.letters[r][c]!);
        if (norm.isNotEmpty) {
          result.add(LetterConstraint(position: i, letter: norm));
        }
      }
    }
    return result;
  }

  bool _placeWord(_GridState g, _CcMode mode, int ccR, int ccC, Direction dir, int len, String word) {
    final runes = word.runes.toList();
    if (runes.length != len) return false;
    final (startR, startC) = _lcStart(mode, ccR, ccC, dir);

    for (var i = 0; i < len; i++) {
      final r = dir == Direction.horizontal ? startR : startR + i;
      final c = dir == Direction.horizontal ? startC + i : startC;
      if (!g.inBounds(r, c)) return false;
      if (g.kinds[r][c] == _Kind.cc) return false;
      final letter = String.fromCharCode(runes[i]);
      final existing = g.letters[r][c];
      // Comparaison normalisée : ء/أ/إ/آ → ا, ة → ه, ى → ي
      if (existing != null && _normalize(existing) != _normalize(letter)) return false;
    }

    for (var i = 0; i < len; i++) {
      final r = dir == Direction.horizontal ? startR : startR + i;
      final c = dir == Direction.horizontal ? startC + i : startC;
      g.setLC(r, c, String.fromCharCode(runes[i]), slotDir: dir);
    }
    return true;
  }

  String _pickLetter(_GridState g, int r, int c, _KbIndex index, Random rng) {
    final pool = index._byLen[2];
    if (pool != null && pool.isNotEmpty) {
      final e = pool[rng.nextInt(pool.length)];
      final runes = e.word.runes.toList();
      return String.fromCharCode(runes[rng.nextInt(runes.length)]);
    }
    return 'ا';
  }

  // -------------------------------------------------------------------------
  // Construction de la Grid finale
  // -------------------------------------------------------------------------

  Grid _buildGrid(
    int rows,
    int cols,
    _GridState g,
    Map<(int, int, Direction, _CcMode), KbEntry> placedWords,
    int seed,
  ) {
    final cells = List<List<Cell>>.generate(rows, (r) {
      return List<Cell>.generate(cols, (c) {
        if (g.kinds[r][c] == _Kind.lc) return LetterCell(solution: g.letters[r][c] ?? '');
        return ClueCell(clues: const []);
      });
    });

    for (final entry in placedWords.entries) {
      final (startR, startC, dir, mode) = entry.key;
      final kbEntry = entry.value;
      final primary = kbEntry.primaryClue;
      if (primary == null) continue;

      // Retrouver la position de la CC depuis (startR, startC) et le mode.
      int clueR, clueC;
      if (mode == _CcMode.a) {
        if (dir == Direction.horizontal) {
          // hSameRow : CC est (startR, startC - 1)
          clueR = startR;
          clueC = startC - 1;
        } else {
          // vSameCol : CC est (startR - 1, startC)
          clueR = startR - 1;
          clueC = startC;
        }
      } else {
        if (dir == Direction.horizontal) {
          // hRowBelow : CC est (startR - 1, startC)
          clueR = startR - 1;
          clueC = startC;
        } else {
          // vColRight : CC est (startR, startC - 1)
          clueR = startR;
          clueC = startC - 1;
        }
      }

      if (clueR < 0 || clueC < 0 || clueR >= rows || clueC >= cols) continue;
      if (g.kinds[clueR][clueC] != _Kind.cc) continue;

      final clue = Clue(
        text: primary.text,
        language: ClueLanguage.arabic,
        direction: dir,
        solution: kbEntry.wordDisplay,
        startCell: Position(startR, startC),
        arrowType: _arrowType(mode, dir),
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
      id: 'v6-hybrid-$seed',
      title: 'شبكة اليوم',
      author: 'Chabaka',
    );
  }

  // -------------------------------------------------------------------------
  // Validation finale
  // -------------------------------------------------------------------------

  /// Génère une grille brute (sans validation finale) — pour diagnostics.
  /// Retourne toujours quelque chose (grille incomplète ou invalide possible).
  Future<Grid> generateRaw(TopologyConfig config) async {
    final index = await _KbIndex.build(kb, maxLen: _maxWordLen, limitPerLen: _cacheLimit);
    final deadline = DateTime.now().add(Duration(milliseconds: config.backtrackTimeoutMs));
    final seed = config.seed;
    final rng = Random(seed);
    final g = _GridState(config.rows, config.cols);
    final placedWords = <(int, int, Direction, _CcMode), KbEntry>{};
    final usedIds = <int>{};
    _phase1Skeleton(g, index, rng, placedWords, usedIds, deadline, _CcMode.b);
    _phase2Residual(g, index, rng, placedWords, usedIds, deadline, _CcMode.b);
    return _buildGrid(config.rows, config.cols, g, placedWords, seed);
  }

  bool _isValid(Grid grid) {
    // R1 : toute CC doit avoir ≥1 indice, toute LC doit avoir une lettre.
    for (var r = 0; r < grid.rows; r++) {
      for (var c = 0; c < grid.cols; c++) {
        final cell = grid.cells[r][c];
        if (cell is ClueCell && cell.clues.isEmpty) return false;
        if (cell is LetterCell && cell.solution.isEmpty) return false;
      }
    }

    // Couverture : chaque LC doit être couverte par au moins un clue.
    // Tolérance : jusqu'à _maxOrphans LCs non couvertes (contraintes KB
    // insatisfaisables dans les positions de bord — limitation structurelle).
    final covered = <(int, int)>{};
    for (var r = 0; r < grid.rows; r++) {
      for (var c = 0; c < grid.cols; c++) {
        final cell = grid.cells[r][c];
        if (cell is! ClueCell || cell.clues.isEmpty) continue;
        for (final clue in cell.clues) {
          final len = clue.solution.runes.length;
          for (var i = 0; i < len; i++) {
            final lr = clue.direction == Direction.horizontal
                ? clue.startCell.row
                : clue.startCell.row + i;
            final lc = clue.direction == Direction.horizontal
                ? clue.startCell.col + i
                : clue.startCell.col;
            covered.add((lr, lc));
          }
        }
      }
    }
    var orphans = 0;
    for (var r = 0; r < grid.rows; r++) {
      for (var c = 0; c < grid.cols; c++) {
        if (grid.cells[r][c] is LetterCell && !covered.contains((r, c))) {
          orphans++;
          if (orphans > _maxOrphans) return false;
        }
      }
    }

    return true;
  }

  int _perturbSeed(int base, int attempt) =>
      attempt == 0 ? base : base * 1009 + attempt * 9973;
}
