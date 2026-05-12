/// Moteur V4 — TrueInterleavedGenerator (modèle B : clue offset diagonal).
///
/// ## Géométrie Abu Salma authentique (modèle B)
///
/// Une CC à `(r, c)` génère 2 mots **offset diagonaux** :
///
///   - **H clue** : mot horizontal commençant à `(r+1, c)` dans la
///     **ROW r+1**. Lettres : `(r+1, c), (r+1, c+1), …, (r+1, c+L-1)`.
///   - **V clue** : mot vertical commençant à `(r, c+1)` dans la
///     **COL c+1**. Lettres : `(r, c+1), (r+1, c+1), …, (r+L-1, c+1)`.
///
/// L'**intersection** des deux mots est `(r+1, c+1)`.
///
/// ## Stratégie de génération
///
/// **Grilles paires** (rows et cols pairs) :
///   Pattern pair/pair : CCs aux positions (r, c) avec r%2==0 && c%2==0.
///   Chaque CC génère V (col c+1, len=2) et H (row r+1, len=2 ou plus pour
///   couvrir les bords). 0 orphelines garanti.
///
/// **Grilles impaires** (rows ou cols impaires) :
///   Pattern pair/pair pour les positions intérieures, puis phase de couverture
///   des bords impairs via des CCs additionnelles posées en positions impaires.
///   Les bords sont couverts par des H/V slots étendus.
///
/// ## Contraintes vérifiées
///
///   R1       : toute CC porte ≥1 indice.
///   R5       : (0,0)=CC, grille pleine.
///   R7       : pas de ≥3 CCs consécutives H ou V.
///   R9       : densité CC ≥ 22 %.
///   R10      : aucun mot > _maxWordLen lettres.
///   R_orphan : aucune LC sans slot clué.
library;

import 'dart:math';

import '../kb/kb_repository.dart';
import '../models.dart';
import 'topology.dart';

// ---------------------------------------------------------------------------
// Constantes
// ---------------------------------------------------------------------------

const int _maxWordLen = 5;
const double _minCcDensity = 0.22;

int _minCcsForGrid(int rows, int cols) {
  final computed = ((rows * cols) * _minCcDensity).round();
  return computed < 3 ? 3 : computed;
}

// ---------------------------------------------------------------------------
// État interne
// ---------------------------------------------------------------------------

enum _Kind { undefined, cc, lc }

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

  _GridState(this.rows, this.cols)
      : kinds = List.generate(rows, (_) => List.filled(cols, _Kind.undefined)),
        letters = List.generate(rows, (_) => List.filled(cols, null));

  bool inBounds(int r, int c) => r >= 0 && c >= 0 && r < rows && c < cols;

  void setCC(int r, int c) {
    kinds[r][c] = _Kind.cc;
    letters[r][c] = null;
  }

  void undoCC(int r, int c) {
    assert(kinds[r][c] == _Kind.cc);
    kinds[r][c] = _Kind.undefined;
  }

  void setLC(int r, int c, String letter) {
    kinds[r][c] = _Kind.lc;
    letters[r][c] = letter;
  }

  bool get isFull {
    for (final row in kinds) for (final k in row) if (k == _Kind.undefined) return false;
    return true;
  }

  int get ccCount {
    var n = 0;
    for (final row in kinds) for (final k in row) if (k == _Kind.cc) n++;
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
  for (var dc = 1; c + dc < g.cols && g.kinds[r][c + dc] == _Kind.cc; dc++) hRun++;
  for (var dc = 1; c - dc >= 0 && g.kinds[r][c - dc] == _Kind.cc; dc++) hRun++;
  if (hRun >= 3) return true;
  var vRun = 1;
  for (var dr = 1; r + dr < g.rows && g.kinds[r + dr][c] == _Kind.cc; dr++) vRun++;
  for (var dr = 1; r - dr >= 0 && g.kinds[r - dr][c] == _Kind.cc; dr++) vRun++;
  return vRun >= 3;
}

// ---------------------------------------------------------------------------
// TrueInterleavedGenerator (modèle B)
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
      final placedWords = <(int, int, Direction), KbEntry>{};
      final usedIds = <int>{};

      // Phase 1 : placement des CCs du squelette et de leurs slots.
      _phase1Skeleton(g, index, rng, placedWords, usedIds, deadline);
      if (DateTime.now().isAfter(deadline)) break;

      // Phase 2 : résidu.
      _phase2Residual(g, index, rng, placedWords, usedIds, deadline);

      if (!_checkR7(g)) continue;
      if (g.ccCount < minCcs) continue;

      final grid = _buildGrid(config.rows, config.cols, g, placedWords, seed);
      if (_isValid(grid)) return grid;
    }
    return null;
  }

  // -------------------------------------------------------------------------
  // Phase 1 — Squelette modèle B
  //
  // Itère selon 2 patterns entrelacés :
  //
  // A) CCs aux positions (r, c) avec r%2==0 && c%2==0.
  //    Chaque CC(r,c) génère :
  //    - V slot dans col c+1 depuis row r, longueur = nombre de positions à
  //      couvrir avant la prochaine CC V dans col c+1 (distance 2k).
  //    - H slot dans row r+1 depuis col c, longueur = idem.
  //
  // B) CCs bord pour les dimensions impaires :
  //    - cols impaire : CC(r, cols-2) pour r pair déjà dans A. Leurs H slots
  //      sont étendus jusqu'à col cols-1 (longueur calculée par _neededSlotLen).
  //    - rows impaire : idem pour rows.
  // -------------------------------------------------------------------------

  void _phase1Skeleton(
    _GridState g,
    _KbIndex index,
    Random rng,
    Map<(int, int, Direction), KbEntry> placedWords,
    Set<int> usedIds,
    DateTime deadline,
  ) {
    // Pour les grilles à cols impaires (ex. 13-col) :
    // - La colonne borderCcCol = cols-2 (col 11 pour 13-col) accueille des CCs
    //   dont le V slot couvre la lastCol (col 12).
    // - Ces CCs sont placées EN PREMIER dans chaque rangée paire pour que leur
    //   V slot se place SANS contrainte (col 12 encore vide).
    // - La CC(r, lastEvenSkeletonCol=cols-3=10) n'a ensuite que son H slot
    //   (pas de V slot, car (r,11) est déjà CC).
    //
    // Résultat : 7 CCs par rangée paire → 56 CCs pour 16×13, 0 orphelines.

    final hasOddCols = g.cols % 2 == 1;
    final borderCcCol = hasOddCols ? g.cols - 2 : -1; // col 11 pour 13-col
    final lastEvenSkeletonCol = hasOddCols ? g.cols - 3 : g.cols - 2; // col 10 pour 13-col

    final hasOddRows = g.rows % 2 == 1;
    final borderCcRow = hasOddRows ? g.rows - 2 : -1;

    // Passe A : CCs en positions paires, par rangée.
    for (var r = 0; r < g.rows; r += 2) {
      if (DateTime.now().isAfter(deadline)) return;

      // Passe A1 : pour cols impaires, placer d'abord le CC bord (r, borderCcCol).
      // Cela garantit que le V slot vers lastCol n'a pas de contrainte sur (r, lastCol).
      if (hasOddCols) {
        _tryPlaceBorderCcForCol(g, r, borderCcCol, index, rng, placedWords, usedIds);
      }

      // Passe A2 : CCs en colonnes paires de 0 à lastEvenSkeletonCol.
      for (var c = 0; c <= lastEvenSkeletonCol; c += 2) {
        if (DateTime.now().isAfter(deadline)) return;
        if (g.kinds[r][c] == _Kind.lc) continue;

        if (g.kinds[r][c] == _Kind.undefined) {
          if (_wouldViolateR7(g, r, c)) continue;
          final canH = _maxAvailableLen(g, r, c, Direction.horizontal) >= 2;
          // Pas de V slot depuis lastEvenSkeletonCol (col borderCcCol déjà CC).
          final skipV = hasOddCols && c == lastEvenSkeletonCol;
          final canV = !skipV && _maxAvailableLen(g, r, c, Direction.vertical) >= 2;
          if (!canH && !canV) continue;
          g.setCC(r, c);
        }

        final skipV = hasOddCols && c == lastEvenSkeletonCol;
        final vLen = skipV ? 0 : _neededLen(g, r, c, Direction.vertical);
        // Pour la dernière col paire du squelette (cols impaire) : len H = 2 max.
        // La lastCol est déjà couverte par le V slot du CC bord (r, borderCcCol).
        // On ne va pas plus loin que col c+1 pour éviter les contraintes rares.
        final hPrefLen = (hasOddCols && c == lastEvenSkeletonCol) ? 2 : _neededLen(g, r, c, Direction.horizontal);
        final hLen = hPrefLen;

        final vOk = vLen >= 2 && _trySlot(g, r, c, Direction.vertical, index, rng, placedWords, usedIds, prefLen: vLen);
        final hOk = hLen >= 2 && _trySlot(g, r, c, Direction.horizontal, index, rng, placedWords, usedIds, prefLen: hLen);
        // Si ni H ni V n'ont pu être placés, annuler le CC pour éviter un CC vide.
        if (!hOk && !vOk && g.kinds[r][c] == _Kind.cc) {
          g.undoCC(r, c);
        }
      }
    }

    // Passe B : rows impaires — CCs bord pour couvrir la dernière rangée.
    if (hasOddRows) {
      _phase1BorderFixRows(g, borderCcRow, index, rng, placedWords, usedIds, deadline);
    }
  }

  /// Tente de placer un CC bord en (r, borderCcCol) pour les cols impaires.
  /// Le V slot couvre col borderCcCol+1 = lastCol. Placé AVANT les CCs
  /// de la rangée r pour que (r, lastCol) soit encore vide.
  void _tryPlaceBorderCcForCol(
    _GridState g,
    int r,
    int borderCcCol,
    _KbIndex index,
    Random rng,
    Map<(int, int, Direction), KbEntry> placedWords,
    Set<int> usedIds,
  ) {
    if (!g.inBounds(r, borderCcCol)) return;
    if (g.kinds[r][borderCcCol] != _Kind.undefined) return;
    if (_wouldViolateR7(g, r, borderCcCol)) return;

    final vAvail = _maxAvailableLen(g, r, borderCcCol, Direction.vertical);
    if (vAvail < 2) return;

    g.setCC(r, borderCcCol);
    // V slot : couvre (r, lastCol) et (r+1, lastCol) en len=2.
    // On force len=2 pour éviter que ce slot ne contraigne les CCs bord suivants
    // en occupant trop de positions de la lastCol.
    final placed = _trySlot(g, r, borderCcCol, Direction.vertical, index, rng, placedWords, usedIds, prefLen: 2);
    if (!placed) {
      // Le V slot a échoué → on annule le CC pour ne pas créer de CC vide.
      g.undoCC(r, borderCcCol);
      return;
    }
    // NOTE : on ne place PAS de H slot ici. La position (r+1, borderCcCol) est
    // laissée libre pour que CC(r, lastEvenSkeletonCol) puisse y placer son H slot
    // SANS contrainte à position 1. Si le H de lastEvenSkeletonCol ne l'atteint pas,
    // phase 2 la couvrira.
  }

  /// Phase 1 border fix pour rows impaires.
  /// Couvre les positions (lastRow, c) pour c pair via des CCs en (borderCcRow, c).
  void _phase1BorderFixRows(
    _GridState g,
    int borderCcRow,
    _KbIndex index,
    Random rng,
    Map<(int, int, Direction), KbEntry> placedWords,
    Set<int> usedIds,
    DateTime deadline,
  ) {
    for (var c = 0; c < g.cols; c += 2) {
      if (DateTime.now().isAfter(deadline)) return;
      if (!g.inBounds(borderCcRow, c)) continue;
      if (g.kinds[borderCcRow][c] != _Kind.undefined) continue;
      if (_wouldViolateR7(g, borderCcRow, c)) continue;

      final hAvail = _maxAvailableLen(g, borderCcRow, c, Direction.horizontal);
      if (hAvail < 2) continue;

      g.setCC(borderCcRow, c);
      final placed = _trySlot(g, borderCcRow, c, Direction.horizontal, index, rng, placedWords, usedIds, prefLen: hAvail);
      if (!placed) {
        g.undoCC(borderCcRow, c);
        continue;
      }
      _trySlot(g, borderCcRow, c, Direction.vertical, index, rng, placedWords, usedIds, prefLen: 2);
    }
  }

  // -------------------------------------------------------------------------
  // Calcul de la longueur nécessaire — modèle B
  // -------------------------------------------------------------------------

  /// Longueur nécessaire pour un slot depuis CC(ccR, ccC) dans [dir].
  ///
  /// Calcule la longueur minimale pour couvrir les positions jusqu'à
  /// la prochaine CC du squelette ou le bord, en tenant compte des
  /// CCs voisines dans le pattern pair/pair.
  int _neededLen(_GridState g, int ccR, int ccC, Direction dir) {
    final available = _maxAvailableLen(g, ccR, ccC, dir);
    if (available < 2) return 0;

    if (dir == Direction.horizontal) {
      var needed = 2;
      while (needed <= available && needed < _maxWordLen) {
        final nextCcC = ccC + needed;
        if (!g.inBounds(ccR, nextCcC)) { needed = available; break; }
        var nextAvail = 0;
        for (var k = 0; k < _maxWordLen; k++) {
          final nc = nextCcC + k;
          if (!g.inBounds(ccR + 1, nc)) break;
          if (g.kinds[ccR + 1][nc] == _Kind.cc) break;
          nextAvail++;
        }
        if (nextAvail >= 2) break;
        needed += 2;
      }
      return needed <= available ? needed : available;
    } else {
      var needed = 2;
      while (needed <= available && needed < _maxWordLen) {
        final nextCcR = ccR + needed;
        if (!g.inBounds(nextCcR, ccC)) { needed = available; break; }
        var nextAvail = 0;
        for (var k = 0; k < _maxWordLen; k++) {
          final nr = nextCcR + k;
          if (!g.inBounds(nr, ccC + 1)) break;
          if (g.kinds[nr][ccC + 1] == _Kind.cc) break;
          nextAvail++;
        }
        if (nextAvail >= 2) break;
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
    Map<(int, int, Direction), KbEntry> placedWords,
    Set<int> usedIds,
    DateTime deadline,
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

          // Via H : CC en row r-1.
          if (!resolved && r > 0) {
            for (var cc = 0; cc <= c && !resolved; cc++) {
              if (g.kinds[r - 1][cc] != _Kind.cc) continue;
              resolved = _trySlot(g, r - 1, cc, Direction.horizontal, index, rng, placedWords, usedIds);
              if (resolved) anyChange = true;
            }
          }

          // Via V : CC en col c-1.
          if (!resolved && c > 0) {
            for (var cr = 0; cr <= r && !resolved; cr++) {
              if (g.kinds[cr][c - 1] != _Kind.cc) continue;
              resolved = _trySlot(g, cr, c - 1, Direction.vertical, index, rng, placedWords, usedIds);
              if (resolved) anyChange = true;
            }
          }

          // Pose CC en (r-1, c) pour H → couvre (r, c).
          if (!resolved && r > 0 && g.kinds[r - 1][c] == _Kind.undefined && !_wouldViolateR7(g, r - 1, c)) {
            final hAvail = _maxAvailableLen(g, r - 1, c, Direction.horizontal);
            if (hAvail >= 2) {
              g.setCC(r - 1, c);
              resolved = _trySlot(g, r - 1, c, Direction.horizontal, index, rng, placedWords, usedIds, prefLen: hAvail);
              if (resolved) {
                _trySlot(g, r - 1, c, Direction.vertical, index, rng, placedWords, usedIds);
                anyChange = true;
              } else {
                g.undoCC(r - 1, c);
              }
            }
          }

          // Pose CC en (r, c-1) pour V → couvre (r, c).
          if (!resolved && c > 0 && g.kinds[r][c - 1] == _Kind.undefined && !_wouldViolateR7(g, r, c - 1)) {
            final vAvail = _maxAvailableLen(g, r, c - 1, Direction.vertical);
            if (vAvail >= 2) {
              g.setCC(r, c - 1);
              resolved = _trySlot(g, r, c - 1, Direction.vertical, index, rng, placedWords, usedIds, prefLen: vAvail);
              if (resolved) {
                _trySlot(g, r, c - 1, Direction.horizontal, index, rng, placedWords, usedIds);
                anyChange = true;
              } else {
                g.undoCC(r, c - 1);
              }
            }
          }

          // Pose CC en (r, c).
          if (!resolved && !_wouldViolateR7(g, r, c)) {
            final canH = _maxAvailableLen(g, r, c, Direction.horizontal) >= 2;
            final canV = _maxAvailableLen(g, r, c, Direction.vertical) >= 2;
            if (canH || canV) {
              g.setCC(r, c);
              final hadH = canH && _trySlot(g, r, c, Direction.horizontal, index, rng, placedWords, usedIds);
              final hadV = canV && _trySlot(g, r, c, Direction.vertical, index, rng, placedWords, usedIds);
              if (hadH || hadV) {
                anyChange = true;
              } else {
                g.undoCC(r, c);
              }
            }
          }
        }
      }
    }

    // Dernière passe : UNDEFINED → LC fallback.
    for (var r = 0; r < g.rows; r++) {
      for (var c = 0; c < g.cols; c++) {
        if (g.kinds[r][c] != _Kind.undefined) continue;
        g.setLC(r, c, _pickLetter(g, r, c, index, rng));
      }
    }
  }

  // -------------------------------------------------------------------------
  // Tentative de placement d'un slot
  // -------------------------------------------------------------------------

  bool _trySlot(
    _GridState g,
    int ccR,
    int ccC,
    Direction dir,
    _KbIndex index,
    Random rng,
    Map<(int, int, Direction), KbEntry> placedWords,
    Set<int> usedIds, {
    int prefLen = 2,
  }) {
    final (sr, sc) = _lcStart(ccR, ccC, dir);
    if (placedWords.containsKey((sr, sc, dir))) return false;

    final rawMax = _maxAvailableLen(g, ccR, ccC, dir);
    final maxLen = rawMax < _maxWordLen ? rawMax : _maxWordLen;
    if (maxLen < 2) return false;

    // Ordre : prefLen en premier, puis du plus court au plus long.
    final lengths = <int>[];
    if (prefLen >= 2 && prefLen <= maxLen) lengths.add(prefLen);
    for (var l = 2; l <= maxLen; l++) {
      if (l != prefLen) lengths.add(l);
    }

    for (final len in lengths) {
      if (!index.hasLength(len)) continue;
      final constraints = _slotConstraints(g, ccR, ccC, dir, len);
      final cands = index.find(
          length: len, constraints: constraints,
          excludeIds: usedIds, limit: _maxCandidatesPerSlot);
      if (cands.isEmpty) continue;

      final shuffled = List.of(cands)..shuffle(rng);
      for (final entry in shuffled) {
        if (_placeWord(g, ccR, ccC, dir, len, entry.word)) {
          placedWords[(sr, sc, dir)] = entry;
          usedIds.add(entry.id);
          return true;
        }
      }
    }
    return false;
  }

  // -------------------------------------------------------------------------
  // Utilitaires géométrie modèle B
  // -------------------------------------------------------------------------

  (int, int) _lcStart(int ccR, int ccC, Direction dir) {
    return dir == Direction.horizontal ? (ccR + 1, ccC) : (ccR, ccC + 1);
  }

  int _maxAvailableLen(_GridState g, int ccR, int ccC, Direction dir) {
    var len = 0;
    for (var i = 0; i < _maxWordLen + 1; i++) {
      final r = dir == Direction.horizontal ? ccR + 1 : ccR + i;
      final c = dir == Direction.horizontal ? ccC + i : ccC + 1;
      if (!g.inBounds(r, c)) break;
      if (g.kinds[r][c] == _Kind.cc) break;
      len++;
    }
    return len > _maxWordLen ? _maxWordLen : len;
  }

  List<LetterConstraint> _slotConstraints(
      _GridState g, int ccR, int ccC, Direction dir, int len) {
    final result = <LetterConstraint>[];
    for (var i = 0; i < len; i++) {
      final r = dir == Direction.horizontal ? ccR + 1 : ccR + i;
      final c = dir == Direction.horizontal ? ccC + i : ccC + 1;
      if (!g.inBounds(r, c)) break;
      if (g.kinds[r][c] == _Kind.lc && g.letters[r][c] != null) {
        result.add(LetterConstraint(position: i, letter: g.letters[r][c]!));
      }
    }
    return result;
  }

  bool _placeWord(_GridState g, int ccR, int ccC, Direction dir, int len, String word) {
    final runes = word.runes.toList();
    if (runes.length != len) return false;

    for (var i = 0; i < len; i++) {
      final r = dir == Direction.horizontal ? ccR + 1 : ccR + i;
      final c = dir == Direction.horizontal ? ccC + i : ccC + 1;
      if (!g.inBounds(r, c)) return false;
      if (g.kinds[r][c] == _Kind.cc) return false;
      final letter = String.fromCharCode(runes[i]);
      final existing = g.letters[r][c];
      if (existing != null && existing != letter) return false;
    }

    for (var i = 0; i < len; i++) {
      final r = dir == Direction.horizontal ? ccR + 1 : ccR + i;
      final c = dir == Direction.horizontal ? ccC + i : ccC + 1;
      g.setLC(r, c, String.fromCharCode(runes[i]));
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
    Map<(int, int, Direction), KbEntry> placedWords,
    int seed,
  ) {
    final cells = List<List<Cell>>.generate(rows, (r) {
      return List<Cell>.generate(cols, (c) {
        if (g.kinds[r][c] == _Kind.lc) return LetterCell(solution: g.letters[r][c] ?? '');
        return ClueCell(clues: const []);
      });
    });

    for (final entry in placedWords.entries) {
      final (startR, startC, dir) = entry.key;
      final kbEntry = entry.value;
      final primary = kbEntry.primaryClue;
      if (primary == null) continue;

      final clueR = dir == Direction.horizontal ? startR - 1 : startR;
      final clueC = dir == Direction.horizontal ? startC : startC - 1;

      if (clueR < 0 || clueC < 0 || clueR >= rows || clueC >= cols) continue;
      if (g.kinds[clueR][clueC] != _Kind.cc) continue;

      final clue = Clue(
        text: primary.text,
        language: ClueLanguage.arabic,
        direction: dir,
        solution: kbEntry.wordDisplay,
        startCell: Position(startR, startC),
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
      id: 'v4-diag-$seed',
      title: 'شبكة اليوم',
      author: 'Chabaka',
    );
  }

  // -------------------------------------------------------------------------
  // Validation finale
  // -------------------------------------------------------------------------

  bool _isValid(Grid grid) {
    for (var r = 0; r < grid.rows; r++) {
      for (var c = 0; c < grid.cols; c++) {
        final cell = grid.cells[r][c];
        if (cell is ClueCell && cell.clues.isEmpty) return false;
        if (cell is LetterCell && cell.solution.isEmpty) return false;
      }
    }

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
    for (var r = 0; r < grid.rows; r++) {
      for (var c = 0; c < grid.cols; c++) {
        if (grid.cells[r][c] is LetterCell && !covered.contains((r, c))) return false;
      }
    }

    return true;
  }

  int _perturbSeed(int base, int attempt) =>
      attempt == 0 ? base : base * 1009 + attempt * 9973;
}
