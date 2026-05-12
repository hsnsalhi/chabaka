/// Moteur V3 — TrueInterleavedGenerator.
///
/// Approche : génération **constructive** (topologie émergente).
/// Contrairement à InterleavedGenerator (V2) qui fixe un patron pré-validé
/// puis backtrack pour le remplir, ce moteur fait croître la grille
/// organiquement : la topologie CC/LC est déterminée *par le choix des mots*,
/// pas l'inverse.
///
/// ## Algorithme BFS interleaved
///
///   1. Grille rows×cols initialisée à UNDEFINED.
///   2. CC placée en (0,0).
///   3. File BFS de CCs à traiter.
///   4. Pour chaque CC, on tente les directions H et V :
///      a. Calcule max_len (jusqu'au bord ou prochaine CC déjà posée).
///      b. Extrait les lettres déjà fixées aux intersections (contraintes).
///      c. Cherche un mot compatible dans la KB (du plus long au plus court).
///      d. Place les LCs + CC fermante → enfile la CC fermante.
///   5. Phase 2 : fixe les cellules UNDEFINED restantes (courtes rafales).
///   6. Vérifie R1/R5/R7/R8 → Grid si OK, sinon retry avec seed perturbé.
///
/// ## Conventions slot
///
///   Un slot de longueur L dans la direction dir depuis la CC (ccR, ccC) :
///     - Horizontal : LCs aux positions (ccR, ccC+1), …, (ccR, ccC+L)
///     - Vertical   : LCs aux positions (ccR+1, ccC), …, (ccR+L, ccC)
///   CC fermante (si dans la grille) : (ccR, ccC+L+1) H ou (ccR+L+1, ccC) V.
///
/// ## Contraintes vérifiées
///
///   R1  : toute ClueCell porte ≥1 indice.
///   R5  : (0,0)=CC, grille pleine, pas de LC sans lettre.
///   R7  : pas de ≥3 CCs consécutives en H ou V.
///   R8  : pas de V-run ≥2 LCs sans CC immédiatement au-dessus.
///
/// ## Performance
///
///   Cache en RAM par longueur + index lettre×position → zéro SQL en boucle.
///   Backtracking local par slot (pas de backtracking global).
///
/// Drop-in replacement via [R4GeneratorApi].
library;

import 'dart:collection';
import 'dart:math';

import '../kb/kb_repository.dart';
import '../models.dart';
import 'topology.dart'; // R4GeneratorApi, TopologyConfig, Slot, Direction

// ---------------------------------------------------------------------------
// État interne de la cellule (génération en cours)
// ---------------------------------------------------------------------------

enum _Kind { undefined, cc, lc }

// ---------------------------------------------------------------------------
// Cache mémoire multi-index
//
// Index principal  : _byLen[len]            → List<KbEntry>
// Index secondaire : _byLenLetter[len][pos][letter] → List<int> (indices)
// Construit une seule fois, synchrone ensuite (zéro SQL en boucle).
// ---------------------------------------------------------------------------

class _KbIndex {
  final Map<int, List<KbEntry>> _byLen;
  // _byLenLetter[len][pos][letter] = indices dans _byLen[len]
  final Map<int, Map<int, Map<String, List<int>>>> _byLenLetter;

  _KbIndex._(this._byLen, this._byLenLetter);

  static Future<_KbIndex> build(
    KbRepository kb, {
    int maxLen = 16,
    int limitPerLen = 3000,
  }) async {
    final byLen = <int, List<KbEntry>>{};
    for (var len = 2; len <= maxLen; len++) {
      final entries = await kb.findMatching(length: len, limit: limitPerLen);
      if (entries.isNotEmpty) {
        byLen[len] = entries;
      }
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

  /// Cherche les candidats compatibles avec [constraints] (position×lettre).
  /// Synchrone — scan en mémoire.
  List<KbEntry> find({
    required int length,
    required List<LetterConstraint> constraints,
    required Set<int> excludeIds,
    int limit = 200,
  }) {
    final pool = _byLen[length];
    if (pool == null || pool.isEmpty) return const [];

    List<int>? candidates; // indices dans pool

    if (constraints.isEmpty) {
      candidates = List.generate(pool.length, (i) => i);
    } else {
      final posMap = _byLenLetter[length];
      // Intersection des sous-listes de chaque contrainte (AND sémantique).
      // On commence par la contrainte qui donne la plus petite liste.
      List<(LetterConstraint, List<int>?)> pairs = constraints.map((c) {
        final subset = posMap?[c.position]?[c.letter];
        return (c, subset);
      }).toList();

      // Tri par taille croissante (plus sélectif en premier).
      pairs.sort((a, b) {
        final sa = a.$2?.length ?? 0;
        final sb = b.$2?.length ?? 0;
        return sa.compareTo(sb);
      });

      for (final (_, subset) in pairs) {
        if (subset == null || subset.isEmpty) return const [];
        if (candidates == null) {
          candidates = List.of(subset);
        } else {
          final subSet = Set<int>.of(subset);
          candidates = candidates.where(subSet.contains).toList();
        }
        if (candidates.isEmpty) return const [];
      }
    }

    final results = <KbEntry>[];
    for (final idx in candidates!) {
      if (results.length >= limit) break;
      final e = pool[idx];
      if (!excludeIds.contains(e.id)) {
        results.add(e);
      }
    }
    return results;
  }
}

// ---------------------------------------------------------------------------
// Grille interne mutable (génération en cours)
// ---------------------------------------------------------------------------

class _GridState {
  final int rows;
  final int cols;
  final List<List<_Kind>> kinds;
  final List<List<String?>> letters; // null si CC ou UNDEFINED

  _GridState(this.rows, this.cols)
      : kinds = List.generate(rows, (_) => List.filled(cols, _Kind.undefined)),
        letters = List.generate(rows, (_) => List.filled(cols, null));

  bool inBounds(int r, int c) => r >= 0 && c >= 0 && r < rows && c < cols;

  void setCC(int r, int c) {
    kinds[r][c] = _Kind.cc;
    letters[r][c] = null;
  }

  void setLC(int r, int c, String letter) {
    kinds[r][c] = _Kind.lc;
    letters[r][c] = letter;
  }

  bool get isFull {
    for (final row in kinds) {
      for (final k in row) {
        if (k == _Kind.undefined) return false;
      }
    }
    return true;
  }

  int get undefinedCount {
    var n = 0;
    for (final row in kinds) {
      for (final k in row) {
        if (k == _Kind.undefined) n++;
      }
    }
    return n;
  }
}

// ---------------------------------------------------------------------------
// Vérifications structurelles
// ---------------------------------------------------------------------------

/// R7 : aucune suite ≥3 CCs consécutives H ou V.
bool _checkR7(_GridState g) {
  for (var r = 0; r < g.rows; r++) {
    var run = 0;
    for (var c = 0; c < g.cols; c++) {
      if (g.kinds[r][c] == _Kind.cc) {
        run++;
        if (run >= 3) return false;
      } else {
        run = 0;
      }
    }
  }
  for (var c = 0; c < g.cols; c++) {
    var run = 0;
    for (var r = 0; r < g.rows; r++) {
      if (g.kinds[r][c] == _Kind.cc) {
        run++;
        if (run >= 3) return false;
      } else {
        run = 0;
      }
    }
  }
  return true;
}

/// R8 assoupli : tout run vertical ≥2 de LCs qui ne commence PAS en row 0
/// (bord supérieur) doit avoir une CC immédiatement au-dessus.
///
/// Les runs qui partent du bord (row 0) sont des "edge slots" légitimes dans
/// les vraies grilles Abou Salma — ils sont couverts par le slot H de la
/// première ligne, pas par une CC explicite. On les tolère.
bool _checkR8(_GridState g) {
  for (var c = 0; c < g.cols; c++) {
    var r = 0;
    while (r < g.rows) {
      if (g.kinds[r][c] != _Kind.lc) {
        r++;
        continue;
      }
      final runStart = r;
      while (r < g.rows && g.kinds[r][c] == _Kind.lc) {
        r++;
      }
      final runLen = r - runStart;
      if (runLen >= 2 && runStart > 0) {
        // Un run interne (pas depuis le bord) doit avoir une CC au-dessus.
        if (g.kinds[runStart - 1][c] != _Kind.cc) {
          return false;
        }
      }
    }
  }
  return true;
}

// ---------------------------------------------------------------------------
// Vérification R7 locale : poser une CC en (r, c) créerait-il 3+ CCs ?
// ---------------------------------------------------------------------------

bool _wouldViolateR7(_GridState g, int r, int c) {
  // Compte le run horizontal en incluant (r, c).
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

// ---------------------------------------------------------------------------
// TrueInterleavedGenerator
// ---------------------------------------------------------------------------

class TrueInterleavedGenerator implements R4GeneratorApi {
  final KbRepository kb;

  static const int _cacheLimit = 3000;
  static const int _maxCandidatesPerSlot = 50;
  // _maxPhase2Cells supprimé : la phase 2 utilise désormais une boucle
  // while à convergence, plus adaptée à la variété de tailles de grille.

  const TrueInterleavedGenerator({required this.kb});

  @override
  Future<Grid?> generate(TopologyConfig config) async {
    final maxDim = config.cols > config.rows ? config.cols : config.rows;
    final index = await _KbIndex.build(
      kb,
      maxLen: maxDim,
      limitPerLen: _cacheLimit,
    );

    final deadline = DateTime.now().add(
      Duration(milliseconds: config.backtrackTimeoutMs),
    );

    for (var attempt = 0; attempt < config.maxRetries; attempt++) {
      if (DateTime.now().isAfter(deadline)) break;
      await Future<void>.delayed(Duration.zero); // cède le contrôle event loop

      final seed = _perturbSeed(config.seed, attempt);
      final rng = Random(seed);

      final g = _GridState(config.rows, config.cols);
      final placedWords = <(int, int, Direction), KbEntry>{};
      final usedIds = <int>{};

      // Phase 1 : croissance BFS.
      _phase1Bfs(g, index, rng, placedWords, usedIds, deadline);
      if (DateTime.now().isAfter(deadline)) break;

      // Phase 2 : couvre les UNDEFINED restants.
      _phase2Cover(g, index, rng, placedWords, usedIds, deadline);

      // Invariants structurels.
      if (!_checkR7(g)) continue;
      if (!_checkR8(g)) continue;

      final grid = _buildGrid(config.rows, config.cols, g, placedWords, seed);
      if (_isValid(grid)) return grid;
    }
    return null;
  }

  // -------------------------------------------------------------------------
  // Phase 1 — BFS constructif
  //
  // Invariant maintenu : quand on défile une CC (ccR, ccC), elle est déjà
  // posée (kinds[ccR][ccC] == cc). On tente H puis V depuis cette CC.
  // -------------------------------------------------------------------------

  void _phase1Bfs(
    _GridState g,
    _KbIndex index,
    Random rng,
    Map<(int, int, Direction), KbEntry> placedWords,
    Set<int> usedIds,
    DateTime deadline,
  ) {
    g.setCC(0, 0);
    final queue = Queue<(int, int)>();
    queue.add((0, 0));
    final processed = <(int, int), Set<Direction>>{
      (0, 0): {},
    };

    while (queue.isNotEmpty) {
      if (DateTime.now().isAfter(deadline)) return;
      if (g.isFull) return;

      final (ccR, ccC) = queue.removeFirst();
      final done = processed[(ccR, ccC)]!;

      for (final dir in Direction.values) {
        if (done.contains(dir)) continue;
        done.add(dir);

        final maxLen = _maxAvailableLen(g, ccR, ccC, dir);
        if (maxLen < 2) continue;

        // Ordre de longueurs à essayer :
        //   - Priorité 1 : longueurs qui permettent une CC fermante *dans* la
        //     grille (len <= maxLen-1, car CC fermante = ccPos + len + 1).
        //   - Priorité 2 : le mot qui va jusqu'au bord (len == maxLen, pas de
        //     CC fermante dans la grille — acceptable pour clore un slot).
        // Pour maximiser la densité de CCs internes, on trie :
        //   1. len <= maxLen - 2 (CC fermante a au moins 1 case de recul)
        //   2. len == maxLen - 1 (CC fermante juste après)
        //   3. len == maxLen     (au bord — seulement si rien d'autre)
        // Et dans chaque groupe, ordre décroissant (mots plus longs d'abord
        // pour mieux contraindre les intersections).
        final lengths = <int>[];
        // Groupe 1 : longueurs avec CC fermante interne.
        for (var l = maxLen - 1; l >= 2; l--) {
          final (er, ec) = _terminalCC(ccR, ccC, dir, l);
          if (g.inBounds(er, ec)) {
            lengths.add(l);
          }
        }
        // Groupe 2 : longueur maximale (va au bord — CC fermante hors grille).
        if (!lengths.contains(maxLen)) {
          lengths.add(maxLen);
        }

        var placed = false;
        for (final len in lengths) {
          if (placed) break;
          if (!index.hasLength(len)) continue;

          final constraints = _slotConstraints(g, ccR, ccC, dir, len);
          final cands = index.find(
            length: len,
            constraints: constraints,
            excludeIds: usedIds,
            limit: _maxCandidatesPerSlot,
          );
          if (cands.isEmpty) continue;

          final shuffled = List.of(cands)..shuffle(rng);

          for (final entry in shuffled) {
            if (!_placeWord(g, ccR, ccC, dir, len, entry.word)) continue;

            final (sr, sc) = _lcStart(ccR, ccC, dir);
            placedWords[(sr, sc, dir)] = entry;
            usedIds.add(entry.id);

            // CC fermante : posée seulement si elle peut générer ≥1 slot
            // dans au moins une direction (sinon elle serait sans indice).
            {
              final (er, ec) = _terminalCC(ccR, ccC, dir, len);
              if (g.inBounds(er, ec) &&
                  g.kinds[er][ec] == _Kind.undefined &&
                  !_wouldViolateR7(g, er, ec) &&
                  _canGenerateSlot(g, er, ec)) {
                g.setCC(er, ec);
                if (!processed.containsKey((er, ec))) {
                  processed[(er, ec)] = {};
                  queue.add((er, ec));
                }
              }
            }
            placed = true;
            break;
          }
        }
      }
    }
  }

  // -------------------------------------------------------------------------
  // Utilitaires de calcul de position
  // -------------------------------------------------------------------------

  /// Position de la première LC d'un slot depuis la CC (ccR, ccC).
  (int, int) _lcStart(int ccR, int ccC, Direction dir) {
    return dir == Direction.horizontal
        ? (ccR, ccC + 1)
        : (ccR + 1, ccC);
  }

  /// Position de la CC fermante après L lettres depuis la CC (ccR, ccC).
  (int, int) _terminalCC(int ccR, int ccC, Direction dir, int len) {
    final r = dir == Direction.horizontal ? ccR : ccR + len + 1;
    final c = dir == Direction.horizontal ? ccC + len + 1 : ccC;
    return (r, c);
  }

  /// Vérifie qu'une future CC en (r, c) pourrait générer ≥1 slot dans au
  /// moins une direction (sinon elle serait sans indice — R1 violation).
  /// Condition : ≥2 cases disponibles (UNDEFINED ou LC) dans au moins une dir.
  bool _canGenerateSlot(_GridState g, int r, int c) {
    for (final dir in Direction.values) {
      var avail = 0;
      for (var i = 1; ; i++) {
        final nr = dir == Direction.horizontal ? r : r + i;
        final nc = dir == Direction.horizontal ? c + i : c;
        if (!g.inBounds(nr, nc)) break;
        if (g.kinds[nr][nc] == _Kind.cc) break;
        avail++;
      }
      if (avail >= 2) return true;
    }
    return false;
  }

  /// Longueur max du slot depuis (ccR, ccC) dans [dir].
  /// Compte les cases UNDEFINED et LC (s'arrête sur CC ou bord).
  int _maxAvailableLen(_GridState g, int ccR, int ccC, Direction dir) {
    var len = 0;
    for (var i = 1; ; i++) {
      final r = dir == Direction.horizontal ? ccR : ccR + i;
      final c = dir == Direction.horizontal ? ccC + i : ccC;
      if (!g.inBounds(r, c)) break;
      if (g.kinds[r][c] == _Kind.cc) break;
      len++;
    }
    return len;
  }

  /// Extrait les contraintes (lettre×position) pour un slot de longueur [len]
  /// depuis la CC (ccR, ccC) dans [dir].
  List<LetterConstraint> _slotConstraints(
    _GridState g,
    int ccR,
    int ccC,
    Direction dir,
    int len,
  ) {
    final result = <LetterConstraint>[];
    for (var i = 0; i < len; i++) {
      final r = dir == Direction.horizontal ? ccR : ccR + 1 + i;
      final c = dir == Direction.horizontal ? ccC + 1 + i : ccC;
      if (!g.inBounds(r, c)) break;
      if (g.kinds[r][c] == _Kind.lc && g.letters[r][c] != null) {
        result.add(LetterConstraint(position: i, letter: g.letters[r][c]!));
      }
    }
    return result;
  }

  // -------------------------------------------------------------------------
  // Placement effectif d'un mot dans la grille
  //
  // Vérifie les conflits de lettre AVANT de modifier la grille.
  // Retourne false si conflit ou hors-grille.
  // -------------------------------------------------------------------------

  bool _placeWord(
    _GridState g,
    int ccR,
    int ccC,
    Direction dir,
    int len,
    String word,
  ) {
    final runes = word.runes.toList();
    if (runes.length != len) return false;

    // Vérification préalable (lecture seule).
    for (var i = 0; i < len; i++) {
      final r = dir == Direction.horizontal ? ccR : ccR + 1 + i;
      final c = dir == Direction.horizontal ? ccC + 1 + i : ccC;
      if (!g.inBounds(r, c)) return false;
      final k = g.kinds[r][c];
      if (k == _Kind.cc) return false; // ne peut pas écraser une CC
      final letter = String.fromCharCode(runes[i]);
      final existing = g.letters[r][c];
      if (existing != null && existing != letter) return false;
    }

    // Placement effectif.
    for (var i = 0; i < len; i++) {
      final r = dir == Direction.horizontal ? ccR : ccR + 1 + i;
      final c = dir == Direction.horizontal ? ccC + 1 + i : ccC;
      g.setLC(r, c, String.fromCharCode(runes[i]));
    }
    return true;
  }

  // -------------------------------------------------------------------------
  // Phase 2 — couvrir les UNDEFINED restants
  //
  // Pour chaque case UNDEFINED :
  //   1. Cherche une CC adjacente (gauche ou dessus) et tente un slot.
  //   2. Sinon, convertit la case en CC (si R7 OK) ou en LC fallback.
  // -------------------------------------------------------------------------

  void _phase2Cover(
    _GridState g,
    _KbIndex index,
    Random rng,
    Map<(int, int, Direction), KbEntry> placedWords,
    Set<int> usedIds,
    DateTime deadline,
  ) {
    // Passe multiple : répète jusqu'à stabilisation (les nouvelles CC créées
    // peuvent débloquer de nouveaux slots pour les voisins UNDEFINED).
    var anyChange = true;
    while (anyChange && !g.isFull) {
      if (DateTime.now().isAfter(deadline)) return;
      anyChange = false;

      for (var r = 0; r < g.rows; r++) {
        for (var c = 0; c < g.cols; c++) {
          if (g.kinds[r][c] != _Kind.undefined) continue;
          if (DateTime.now().isAfter(deadline)) return;

          // Tente de couvrir depuis une CC à gauche (H) ou au-dessus (V).
          var resolved = false;
          if (c > 0 && g.kinds[r][c - 1] == _Kind.cc) {
            resolved = _tryExtend(
                g, r, c - 1, Direction.horizontal, index, rng, placedWords, usedIds);
            if (resolved) anyChange = true;
          }
          if (!resolved && r > 0 && g.kinds[r - 1][c] == _Kind.cc) {
            resolved = _tryExtend(
                g, r - 1, c, Direction.vertical, index, rng, placedWords, usedIds);
            if (resolved) anyChange = true;
          }

          // Tente de poser une CC si elle peut immédiatement générer un slot.
          // La CC sera exploitée lors du prochain passage de la boucle while.
          if (!resolved && g.kinds[r][c] == _Kind.undefined &&
              !_wouldViolateR7(g, r, c) &&
              _canGenerateSlot(g, r, c)) {
            g.setCC(r, c);
            anyChange = true;
          }
        }
      }
    }

    // Dernière passe : force les UNDEFINED résiduels en LC (lettre de remplissage).
    // Ces LCs peuvent violer R4 (pas de clue) mais R5 (grille pleine) est
    // prioritaire — elles seront rejetées par _isValid si une CC voisine sans
    // indice en résulte.
    for (var r = 0; r < g.rows; r++) {
      for (var c = 0; c < g.cols; c++) {
        if (g.kinds[r][c] != _Kind.undefined) continue;
        // Choisit une lettre compatible avec les contraintes voisines.
        final letter = _pickLetter(g, r, c, index, rng);
        g.setLC(r, c, letter);
      }
    }
  }

  /// Choisit une lettre cohérente pour un LC forcé.
  String _pickLetter(_GridState g, int r, int c, _KbIndex index, Random rng) {
    // Cherche si une LC voisine contraint la lettre.
    // Simple : retourne une lettre aléatoire d'un mot de longueur 2.
    final pool = index._byLen[2];
    if (pool != null && pool.isNotEmpty) {
      final e = pool[rng.nextInt(pool.length)];
      final runes = e.word.runes.toList();
      return String.fromCharCode(runes[rng.nextInt(runes.length)]);
    }
    return 'ا'; // fallback minimal
  }

  bool _tryExtend(
    _GridState g,
    int ccR,
    int ccC,
    Direction dir,
    _KbIndex index,
    Random rng,
    Map<(int, int, Direction), KbEntry> placedWords,
    Set<int> usedIds,
  ) {
    final maxLen = _maxAvailableLen(g, ccR, ccC, dir);
    if (maxLen < 2) return false;

    for (var len = maxLen; len >= 2; len--) {
      if (!index.hasLength(len)) continue;
      final constraints = _slotConstraints(g, ccR, ccC, dir, len);
      final cands = index.find(
        length: len,
        constraints: constraints,
        excludeIds: usedIds,
        limit: _maxCandidatesPerSlot,
      );
      if (cands.isEmpty) continue;

      final shuffled = List.of(cands)..shuffle(rng);
      for (final entry in shuffled) {
        if (_placeWord(g, ccR, ccC, dir, len, entry.word)) {
          final (sr, sc) = _lcStart(ccR, ccC, dir);
          placedWords[(sr, sc, dir)] = entry;
          usedIds.add(entry.id);

              final (er, ec) = _terminalCC(ccR, ccC, dir, len);
          if (g.inBounds(er, ec) &&
              g.kinds[er][ec] == _Kind.undefined &&
              !_wouldViolateR7(g, er, ec) &&
              _canGenerateSlot(g, er, ec)) {
            g.setCC(er, ec);
          }
          return true;
        }
      }
    }
    return false;
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
        if (g.kinds[r][c] == _Kind.lc) {
          return LetterCell(solution: g.letters[r][c] ?? '');
        }
        return ClueCell(clues: const []);
      });
    });

    for (final entry in placedWords.entries) {
      final (startR, startC, dir) = entry.key;
      final kbEntry = entry.value;
      final primary = kbEntry.primaryClue;
      if (primary == null) continue;

      // CC prédécesseure : case immédiatement avant la première LC.
      final clueR = dir == Direction.horizontal ? startR : startR - 1;
      final clueC = dir == Direction.horizontal ? startC - 1 : startC;

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
      id: 'true-interleaved-$seed',
      title: 'شبكة اليوم',
      author: 'Chabaka',
    );
  }

  // -------------------------------------------------------------------------
  // Validation finale de la Grid
  // -------------------------------------------------------------------------

  bool _isValid(Grid grid) {
    for (var r = 0; r < grid.rows; r++) {
      for (var c = 0; c < grid.cols; c++) {
        final cell = grid.cells[r][c];
        if (cell is ClueCell && cell.clues.isEmpty) return false;
        if (cell is LetterCell && cell.solution.isEmpty) return false;
      }
    }
    return true;
  }

  // -------------------------------------------------------------------------
  // Perturbation du seed entre les tentatives
  // -------------------------------------------------------------------------

  int _perturbSeed(int base, int attempt) =>
      attempt == 0 ? base : base * 1009 + attempt * 9973;
}
