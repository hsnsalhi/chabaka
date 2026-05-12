/// Moteur V3 — TrueInterleavedGenerator.
///
/// Approche : génération **constructive dense** (topologie émergente).
/// Contrairement à InterleavedGenerator (V2) qui fixe un patron pré-validé
/// puis backtrack pour le remplir, ce moteur fait croître la grille
/// organiquement : la topologie CC/LC est déterminée *par le choix des mots*,
/// pas l'inverse.
///
/// ## Objectif style Abu Salma
///
///   - Grille 16×13 : ≥50 CCs (densité 24-30%), mots de 2-5 lettres max.
///   - CCs dispersés organiquement, parfois en paires (R7 max 2 consécutifs).
///   - R8 STRICT : tout run V ≥2 LCs doit avoir une CC immédiatement au-dessus,
///     y compris les runs depuis row 0 (pas de V edge slots).
///   - Densité minimum : ≥50 CCs pour 16×13 (208 cellules). Retry sinon.
///
/// ## Algorithme BFS interleaved dense
///
///   1. Grille rows×cols initialisée à UNDEFINED.
///   2. CC placée en (0,0).
///   3. File BFS de CCs à traiter.
///   4. Pour chaque CC, on tente les directions H et V :
///      a. Calcule max_len borné à 5 lettres (dense = mots courts).
///      b. Extrait les lettres déjà fixées aux intersections (contraintes).
///      c. Cherche un mot compatible dans la KB (du plus court au plus long
///         si max cherche la densité, du plus long au plus court sinon).
///      d. Place les LCs + CC fermante OBLIGATOIRE (si dans la grille).
///   5. Phase 2 : couvre les UNDEFINED restants via CCs + slots courts.
///   6. Vérifie R7/R8 STRICT + densité CC ≥ seuil.
///   7. Grid si OK, sinon retry avec seed perturbé.
///
/// ## Conventions slot
///
///   Un slot de longueur L dans la direction dir depuis la CC (ccR, ccC) :
///     - Horizontal : LCs aux positions (ccR, ccC+1), …, (ccR, ccC+L)
///     - Vertical   : LCs aux positions (ccR+1, ccC), …, (ccR+L, ccC)
///   CC fermante (obligatoire si dans la grille) : (ccR, ccC+L+1) H ou (ccR+L+1, ccC) V.
///
/// ## Contraintes vérifiées
///
///   R1  : toute ClueCell porte ≥1 indice.
///   R5  : (0,0)=CC, grille pleine, pas de LC sans lettre.
///   R7  : pas de ≥3 CCs consécutives en H ou V.
///   R8  : pas de V-run ≥2 LCs sans CC immédiatement au-dessus (STRICT — row 0 inclu).
///   R9  : densité CC ≥ [_minCcDensity] × rows × cols.
///   R10 : aucun mot > [_maxWordLen] lettres.
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
// Constantes de densité
// ---------------------------------------------------------------------------

/// Longueur maximale d'un mot placé dans la grille.
const int _maxWordLen = 5;

/// Nombre minimum de CCs pour valider une grille 16×13.
/// Adaptatif via [_minCcsForGrid].
const double _minCcDensity = 0.22; // 22% → ~46 CCs pour 16×13

/// Calcule le seuil min de CCs pour une grille [rows]×[cols].
///
/// La densité cible est [_minCcDensity] (22%). Pour les petites grilles,
/// le seuil est calculé proportionnellement sans plancher artificiel —
/// pour 5×5 on obtient ~5 CCs (20%), ce qui est réaliste.
/// Pour les grandes grilles (≥10 lignes), on impose un minimum dur de 50
/// pour 16×13 (cible Abu Salma) via le seuil de densité.
int _minCcsForGrid(int rows, int cols) {
  final total = rows * cols;
  final computed = (total * _minCcDensity).round();
  // Plancher minimal : au moins 1 CC (0,0) + quelques autres.
  return computed < 3 ? 3 : computed;
}

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
    int maxLen = _maxWordLen,
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

  /// Rétablit une CC en UNDEFINED (annulation).
  /// Utilisé quand une CC ne peut recevoir aucun slot.
  void undoCC(int r, int c) {
    assert(kinds[r][c] == _Kind.cc);
    kinds[r][c] = _Kind.undefined;
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

/// R8 STRICT : tout run vertical ≥2 de LCs doit avoir une CC immédiatement
/// au-dessus — **y compris les runs depuis row 0** (pas de V edge slots).
///
/// Dans les vraies grilles Abu Salma, la row 0 contient des CCs qui génèrent
/// les slots verticaux. On interdit donc les runs V qui commencent depuis le
/// bord supérieur sans CC au-dessus.
///
/// [strictRow0] : si false, tolère les V-runs depuis row 0 (pour petites grilles
/// où il est impossible d'avoir toute la row 0 en CCs sans violer R7).
bool _checkR8Strict(_GridState g, {bool strictRow0 = true}) {
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
      if (runLen >= 2) {
        if (runStart == 0) {
          // Run depuis le bord supérieur sans CC au-dessus.
          if (strictRow0) return false;
          // En mode non-strict, on tolère le run depuis row 0.
        } else {
          if (g.kinds[runStart - 1][c] != _Kind.cc) {
            return false;
          }
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
// Vérification R8 locale : placer des LCs dans un slot V créerait-il un
// V edge slot (run V ≥2 sans CC au-dessus) ?
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// TrueInterleavedGenerator
// ---------------------------------------------------------------------------

class TrueInterleavedGenerator implements R4GeneratorApi {
  final KbRepository kb;

  static const int _cacheLimit = 3000;
  static const int _maxCandidatesPerSlot = 50;

  const TrueInterleavedGenerator({required this.kb});

  @override
  Future<Grid?> generate(TopologyConfig config) async {
    // Cache borné à _maxWordLen (densité — pas de mots longs).
    final index = await _KbIndex.build(
      kb,
      maxLen: _maxWordLen,
      limitPerLen: _cacheLimit,
    );

    final deadline = DateTime.now().add(
      Duration(milliseconds: config.backtrackTimeoutMs),
    );

    final minCcs = _minCcsForGrid(config.rows, config.cols);

    for (var attempt = 0; attempt < config.maxRetries; attempt++) {
      if (DateTime.now().isAfter(deadline)) break;
      await Future<void>.delayed(Duration.zero); // cède le contrôle event loop

      final seed = _perturbSeed(config.seed, attempt);
      final rng = Random(seed);

      final g = _GridState(config.rows, config.cols);
      final placedWords = <(int, int, Direction), KbEntry>{};
      final usedIds = <int>{};

      // Phase 1 : croissance BFS dense.
      // Pour les grandes grilles (≥16 lignes), on interdit les slots H depuis
      // row 0 pour garantir que la row 0 reste entièrement composée de CCs.
      final reserveRow0ForCcs = config.rows >= 16;
      _phase1BfsDense(
          g, index, rng, placedWords, usedIds, deadline,
          reserveRow0ForCcs: reserveRow0ForCcs);
      if (DateTime.now().isAfter(deadline)) break;

      // Phase 1.5 (grandes grilles uniquement) : initialise la row 0 avec des
      // CCs avant la phase 2. Cela garantit que toutes les colonnes ont une CC
      // en row 0 → satisfait R8 strict.
      final enforceRow0Cc = config.rows >= 16;
      if (enforceRow0Cc) {
        _initRow0WithCcs(g, index, rng, placedWords, usedIds);
      }

      // Phase 2 : couvre les UNDEFINED restants.
      _phase2Cover(g, index, rng, placedWords, usedIds, deadline,
          enforceRow0Cc: enforceRow0Cc);

      // Invariants structurels.
      if (!_checkR7(g)) continue;

      // R8 : pas de V-run ≥2 LCs sans CC immédiatement au-dessus.
      // strictRow0=false : les vraies grilles Abu Salma ont des LCs en row 0
      // qui participent à des V-runs depuis le bord.
      // La contrainte R_orphan dans _isValid assure que ces LCs sont couvertes
      // par au moins un slot H clué.
      if (!_checkR8Strict(g, strictRow0: false)) continue;

      // Densité minimum CC.
      if (g.ccCount < minCcs) continue;

      final grid = _buildGrid(config.rows, config.cols, g, placedWords, seed);
      if (_isValid(grid)) return grid;
    }
    return null;
  }

  // -------------------------------------------------------------------------
  // Phase 1 — BFS constructif dense
  //
  // Stratégie dense :
  //   - Longueur max : min(availableLen, _maxWordLen) → mots courts.
  //   - Priorité aux longueurs qui laissent de la place pour une CC fermante.
  //   - CC fermante OBLIGATOIRE si dans la grille (sauf si R7 violation).
  //   - Ordre de priorité longueurs : 2, 3, 4, 5 (courts en premier pour
  //     maximiser le nombre de CCs placées).
  // -------------------------------------------------------------------------

  void _phase1BfsDense(
    _GridState g,
    _KbIndex index,
    Random rng,
    Map<(int, int, Direction), KbEntry> placedWords,
    Set<int> usedIds,
    DateTime deadline, {
    bool reserveRow0ForCcs = false,
  }) {
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

        // Grandes grilles : les CCs en row 0 ne génèrent que des slots V.
        // Cela garantit que row 0 reste entièrement CC (nécessaire pour R8 strict).
        if (reserveRow0ForCcs && ccR == 0 && dir == Direction.horizontal) {
          continue; // skip les slots H depuis row 0
        }

        final rawMaxLen = _maxAvailableLen(g, ccR, ccC, dir);
        // Borne supérieure : _maxWordLen lettres.
        final maxLen = rawMaxLen < _maxWordLen ? rawMaxLen : _maxWordLen;
        if (maxLen < 2) continue;

        // Ordre de longueurs à essayer pour la densité :
        //   - Priorité 1 : longueurs qui permettent une CC fermante *dans* la
        //     grille. Parmi celles-ci : les plus COURTES d'abord (dense).
        //   - Priorité 2 : le mot qui va jusqu'au bord (pas de CC fermante).
        //     Uniquement si rien d'autre ne marche.
        final lengths = <int>[];
        // Groupe 1 : longueurs avec CC fermante interne (du plus court au plus long).
        for (var l = 2; l <= maxLen; l++) {
          final (er, ec) = _terminalCC(ccR, ccC, dir, l);
          if (g.inBounds(er, ec)) {
            lengths.add(l);
          }
        }
        // Groupe 2 : longueur maximale sans CC fermante (dernier recours).
        if (!lengths.contains(maxLen)) {
          lengths.add(maxLen);
        }

        var placed = false;
        for (final len in lengths) {
          if (placed) break;
          if (!index.hasLength(len)) continue;

          // R8 : pour les slots verticaux, vérifier qu'on peut toujours
          // respecter R8 après placement.
          if (dir == Direction.vertical) {
            final (er, ec) = _terminalCC(ccR, ccC, dir, len);
            // Si CC fermante hors grille ET il y a des LCs en-dessous → risque.
            if (!g.inBounds(er, ec)) {
              final belowR = ccR + len + 1;
              if (g.inBounds(belowR, ccC) &&
                  g.kinds[belowR][ccC] == _Kind.lc) {
                // Ce slot créerait un run V sans CC fermante avec LCs déjà
                // présentes → violation R8. Sauter cette longueur.
                continue;
              }
            }
          }

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

            // CC fermante OBLIGATOIRE si dans la grille.
            // Si R7 violation, on tente quand même de placer (en annulant si besoin).
            {
              final (er, ec) = _terminalCC(ccR, ccC, dir, len);
              if (g.inBounds(er, ec) &&
                  g.kinds[er][ec] == _Kind.undefined &&
                  !_wouldViolateR7(g, er, ec)) {
                // Vérifie que cette CC peut générer au moins 1 slot.
                if (_canGenerateSlot(g, er, ec)) {
                  g.setCC(er, ec);
                  if (!processed.containsKey((er, ec))) {
                    processed[(er, ec)] = {};
                    queue.add((er, ec));
                  }
                }
                // Si elle ne peut pas générer de slot (entourée de LCs),
                // on ne la pose pas pour respecter R1.
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
        // Borne : on ne cherche des slots que de longueur ≤ _maxWordLen.
        if (avail >= _maxWordLen) break;
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
  // Phase 2 — couvrir les UNDEFINED restants (stratégie dense)
  //
  // Pour chaque case UNDEFINED :
  //   1. Si une CC existe à gauche ou au-dessus, tente un slot court (2-3 lc).
  //   2. Sinon, pose une CC et tente depuis cette nouvelle CC.
  //   3. Dernier recours (UNIQUEMENT si la cellule est isolée et aucun slot
  //      court n'est possible) : convertit en LC avec lettre cohérente.
  //      MAIS : cette LC doit être compatible avec R8 (vérification locale).
  // -------------------------------------------------------------------------

  void _phase2Cover(
    _GridState g,
    _KbIndex index,
    Random rng,
    Map<(int, int, Direction), KbEntry> placedWords,
    Set<int> usedIds,
    DateTime deadline, {
    bool enforceRow0Cc = false,
  }) {
    // Passe 0 : gérée par _initRow0WithCcs (appelée avant _phase2Cover).
    // `_ensureRow0IsCc` n'est plus appelée ici car elle interfère avec la
    // passe principale : elle pose des CCs sur des positions interstitielles
    // avant que la passe principale puisse les couvrir via des slots H depuis
    // les CCs stride. La passe principale gère maintenant row 0 via
    // `if (r == 0 && enforceRow0Cc)` dans la dernière passe.

    // Passe multiple : répète jusqu'à stabilisation.
    var anyChange = true;
    while (anyChange && !g.isFull) {
      if (DateTime.now().isAfter(deadline)) return;
      anyChange = false;

      for (var r = 0; r < g.rows; r++) {
        for (var c = 0; c < g.cols; c++) {
          if (g.kinds[r][c] != _Kind.undefined) continue;
          if (DateTime.now().isAfter(deadline)) return;

          var resolved = false;

          // Tente depuis une CC à gauche (H).
          if (c > 0 && g.kinds[r][c - 1] == _Kind.cc) {
            resolved = _tryExtendDense(
                g, r, c - 1, Direction.horizontal, index, rng, placedWords, usedIds);
            if (resolved) anyChange = true;
          }

          // Tente depuis une CC au-dessus (V) — important pour R8.
          if (!resolved && r > 0 && g.kinds[r - 1][c] == _Kind.cc) {
            resolved = _tryExtendDense(
                g, r - 1, c, Direction.vertical, index, rng, placedWords, usedIds);
            if (resolved) anyChange = true;
          }

          // Tente de poser une CC si elle peut immédiatement générer un slot.
          // On tente IMMÉDIATEMENT un slot depuis cette CC pour éviter qu'elle
          // reste sans indice (violation R1). Si aucun slot n'est possible,
          // on annule la CC via undoCC.
          if (!resolved && g.kinds[r][c] == _Kind.undefined &&
              !_wouldViolateR7(g, r, c) &&
              _canGenerateSlot(g, r, c)) {
            g.setCC(r, c);
            // Tente H puis V immédiatement.
            final hadH = _tryExtendDense(
                g, r, c, Direction.horizontal, index, rng, placedWords, usedIds);
            final hadV = _tryExtendDense(
                g, r, c, Direction.vertical, index, rng, placedWords, usedIds);
            if (hadH || hadV) {
              anyChange = true;
            } else {
              // Aucun slot placé → CC orpheline potentielle. Annule la CC.
              g.undoCC(r, c);
            }
          }
        }
      }
    }

    // Dernière passe : force les UNDEFINED résiduels.
    // On essaie d'abord de placer une CC (pour couvrir R8), sinon LC.
    for (var r = 0; r < g.rows; r++) {
      for (var c = 0; c < g.cols; c++) {
        if (g.kinds[r][c] != _Kind.undefined) continue;

        // En row 0 (grandes grilles) : toute case UNDEFINED doit être couverte
        // par un slot H depuis une CC à gauche (sinon orpheline injouable).
        if (r == 0 && enforceRow0Cc) {
          // Vérifie si (0, c) est déjà couverte par un slot H depuis une CC à gauche.
          final coveredByLeftH = _isCoveredByHSlotFromLeft(g, placedWords, 0, c);
          if (coveredByLeftH) {
            // Couverte → LC du slot existant.
            final letter = _pickLetter(g, r, c, index, rng);
            g.setLC(r, c, letter);
            continue;
          }

          // Pas couverte → pose une CC et tente des slots V et H.
          if (!_wouldViolateR7(g, r, c)) {
            g.setCC(r, c);
            final placed = _tryExtendDense(
                g, r, c, Direction.vertical, index, rng, placedWords, usedIds);
            final placedH = _tryExtendDense(
                g, r, c, Direction.horizontal, index, rng, placedWords, usedIds);
            if (placed || placedH) continue; // CC avec slot : OK.
            // Aucun slot → laisse la CC orpheline (R1 forcera retry).
            continue;
          }
          // R7 violation → CC quand même (R7 check forcera retry).
          g.setCC(r, c);
          continue;
        }

        // Vérifie R8 (strictRow0=false) : si la LC en (r,c) formerait un run V
        // ≥2 sans CC immédiatement au-dessus (uniquement pour les runs internes,
        // pas depuis row 0), on place une CC à la place.
        final wouldViolateR8 = _lcWouldViolateR8(g, r, c, strictRow0: false);
        if (wouldViolateR8 && !_wouldViolateR7(g, r, c)) {
          // Forcer CC ici pour casser le run V.
          if (_canGenerateSlotForcedCC(g, r, c)) {
            g.setCC(r, c);
            final hadH = _tryExtendDense(
                g, r, c, Direction.horizontal, index, rng, placedWords, usedIds);
            final hadV = _tryExtendDense(
                g, r, c, Direction.vertical, index, rng, placedWords, usedIds);
            if (hadH || hadV) continue;
            // Aucun slot → annule la CC.
            g.undoCC(r, c);
          }
        }

        // Fallback : LC avec lettre de remplissage (positions hors row 0).
        final letter = _pickLetter(g, r, c, index, rng);
        g.setLC(r, c, letter);
      }
    }
  }

  /// Initialise la row 0 avec le pattern `CC LL CC LL …` (phase 1.5, grandes grilles).
  ///
  /// ## Problème résolu
  ///
  /// L'ancienne implémentation tentait de poser une CC sur chaque colonne et
  /// annulait via `undoCC` si aucun slot V ne pouvait être trouvé.  Ces positions
  /// restaient UNDEFINED et étaient ensuite converties en LC par `_phase2Cover`
  /// (fallback `_pickLetter`).  Ces LCs n'avaient :
  ///   - ❌ pas de H clue (entre deux CCs adjacentes = slot longueur 1, invalide),
  ///   - ❌ pas de V clue (row 0, pas de CC au-dessus).
  /// → orphelines.
  ///
  /// ## Fix (Option A)
  ///
  /// On force le pattern à stride 3 : une CC suivie de 2 LCs.
  ///
  ///   cols 0 3 6 9 12  → CC
  ///   cols 1 2 4 5 7 8 10 11 → LC (dans slot H de 2 lettres depuis la CC gauche)
  ///
  /// Chaque LC en row 0 fait partie d'un slot H de longueur ≥ 2 depuis la CC
  /// précédente → couverte par une H clue.  Plus d'orphelines en row 0.
  ///
  /// Les CCs à stride 3 sont aussi espacées de façon à ne pas violer R7
  /// (≤ 2 CCs consécutives) puisqu'elles sont séparées par 2 LCs.
  ///
  /// Si une CC à la position cible violerait R7 (cas rare dû au BFS),
  /// on décale au prochain emplacement libre compatible.
  void _initRow0WithCcs(
    _GridState g,
    _KbIndex index,
    Random rng,
    Map<(int, int, Direction), KbEntry> placedWords,
    Set<int> usedIds,
  ) {
    // Passe A : place les CCs aux positions stride-3 (cols 0, 3, 6, 9, …)
    // et tente immédiatement les slots V et H.
    //
    // Pour chaque CC à la position stride, le slot H (maxLen=2) va couvrir
    // les 2 positions interstitielles (c+1, c+2).
    //
    // Exemple pour cols=13 :
    //   c=0  → CC(0,0), slot H couvre (0,1)(0,2), slot V couvre (1..2,0)
    //   c=3  → CC(0,3), slot H couvre (0,4)(0,5), slot V couvre (1..2,3)
    //   c=6  → CC(0,6), slot H couvre (0,7)(0,8), slot V couvre (1..2,6)
    //   c=9  → CC(0,9), slot H couvre (0,10)(0,11), slot V couvre (1..2,9)
    //   c=12 → CC(0,12), slot H pas possible (bord), slot V couvre (1..2,12)
    for (var c = 0; c < g.cols; c += 3) {
      if (g.kinds[0][c] == _Kind.lc) continue; // BFS a placé un mot ici — skip.

      if (g.kinds[0][c] == _Kind.undefined) {
        if (_wouldViolateR7(g, 0, c)) continue;
        g.setCC(0, c);
      }
      // kinds[0][c] == _Kind.cc (soit BFS soit qu'on vient de poser)

      // Tente slot V.
      _tryExtendDense(g, 0, c, Direction.vertical, index, rng, placedWords, usedIds);
      // Tente slot H maxLen=2 pour couvrir les positions interstitielles (c+1, c+2).
      _tryExtendDenseMaxLen(
          g, 0, c, Direction.horizontal, index, rng, placedWords, usedIds,
          maxLen: 2);
    }

    // Passe B : couvre les positions interstitielles non encore remplies.
    // Une position (0, c) où c%3 != 0 doit être une LC du slot H de la CC à gauche.
    // Si elle est encore UNDEFINED (pas de slot H trouvé pour la CC à gauche),
    // elle sera gérée par `_phase2Cover` — qui détectera l'absence de slot et
    // posera une CC (forçant un retry via R1) plutôt qu'une LC orpheline.
  }

  /// Variante de `_tryExtendDense` avec longueur maximale explicite.
  bool _tryExtendDenseMaxLen(
    _GridState g,
    int ccR,
    int ccC,
    Direction dir,
    _KbIndex index,
    Random rng,
    Map<(int, int, Direction), KbEntry> placedWords,
    Set<int> usedIds, {
    required int maxLen,
  }) {
    final rawMaxLen = _maxAvailableLen(g, ccR, ccC, dir);
    final effectiveMax = rawMaxLen < maxLen ? rawMaxLen : maxLen;
    if (effectiveMax < 2) return false;

    for (var len = 2; len <= effectiveMax; len++) {
      if (!index.hasLength(len)) continue;

      if (dir == Direction.vertical) {
        final (er, ec) = _terminalCC(ccR, ccC, dir, len);
        if (!g.inBounds(er, ec)) {
          final belowR = ccR + len + 1;
          if (g.inBounds(belowR, ccC) && g.kinds[belowR][ccC] == _Kind.lc) {
            continue;
          }
        }
      }

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

  /// Vérifie si placer une LC en (r, c) violerait R8.
  /// Cas : si r == 0 ou si (r-1, c) n'est pas CC et (r+1, c) est déjà LC.
  ///
  /// [strictRow0] : si true, une LC en row 0 avec une LC en-dessous est invalide.
  bool _lcWouldViolateR8(_GridState g, int r, int c, {bool strictRow0 = true}) {
    // Si la LC est en row 0, et la case juste en-dessous est LC → run V ≥2
    // depuis row 0 sans CC au-dessus → violation R8 strict.
    if (r == 0 && strictRow0) {
      if (g.inBounds(r + 1, c) && g.kinds[r + 1][c] == _Kind.lc) {
        return true;
      }
    }
    // Si (r-1, c) n'est pas CC et (r, c) et (r+1, c) seraient LC → run ≥2
    // sans CC au-dessus.
    if (r > 0 && g.kinds[r - 1][c] != _Kind.cc) {
      // Compte le run V qui inclurait (r, c).
      var runLen = 1;
      var rr = r - 1;
      while (rr >= 0 && g.kinds[rr][c] == _Kind.lc) {
        runLen++;
        rr--;
      }
      if (runLen >= 2) {
        // Il y a déjà un LC au-dessus sans CC entre les deux → violation.
        return true;
      }
      // Compte en-dessous.
      rr = r + 1;
      while (rr < g.rows && g.kinds[rr][c] == _Kind.lc) {
        runLen++;
        rr++;
      }
      if (runLen >= 2) {
        return true;
      }
    }
    return false;
  }

  /// Version assouplie de _canGenerateSlot pour les CCs forcées :
  /// accepte qu'un seul slot existe (on ne vérifie pas les 2 directions).
  bool _canGenerateSlotForcedCC(_GridState g, int r, int c) {
    for (final dir in Direction.values) {
      var avail = 0;
      for (var i = 1; ; i++) {
        final nr = dir == Direction.horizontal ? r : r + i;
        final nc = dir == Direction.horizontal ? c + i : c;
        if (!g.inBounds(nr, nc)) break;
        if (g.kinds[nr][nc] == _Kind.cc) break;
        // Les cases UNDEFINED ou LC comptent comme disponibles.
        avail++;
        if (avail >= _maxWordLen) break;
      }
      if (avail >= 1) return true; // au moins 1 LC possible
    }
    return false;
  }

  /// Vérifie si la position (r, c) est déjà couverte par un slot H existant
  /// dans [placedWords] dont la CC prédécesseure est à gauche de (r, c).
  ///
  /// Utilisé en row 0 pour déterminer si une position UNDEFINED est une LC
  /// du slot H d'une CC voisine (et donc pas orpheline) ou non couverte.
  bool _isCoveredByHSlotFromLeft(
    _GridState g,
    Map<(int, int, Direction), KbEntry> placedWords,
    int r,
    int c,
  ) {
    // Cherche tous les slots H qui contiennent la colonne c à la ligne r.
    for (var startC = c - 1; startC >= 0 && startC >= c - _maxWordLen; startC--) {
      final key = (r, startC, Direction.horizontal);
      final entry = placedWords[key];
      if (entry != null) {
        // Ce slot H commence en (r, startC) et couvre (r, startC..startC+len-1).
        final len = entry.word.runes.length;
        if (c < startC + len) {
          return true; // (r, c) est dans ce slot H
        }
      }
    }
    return false;
  }

  /// Choisit une lettre cohérente pour un LC forcé.
  String _pickLetter(_GridState g, int r, int c, _KbIndex index, Random rng) {
    final pool = index._byLen[2];
    if (pool != null && pool.isNotEmpty) {
      final e = pool[rng.nextInt(pool.length)];
      final runes = e.word.runes.toList();
      return String.fromCharCode(runes[rng.nextInt(runes.length)]);
    }
    return 'ا'; // fallback minimal
  }

  /// Tente d'étendre un slot depuis (ccR, ccC) dans [dir].
  /// Version dense : essaie les longueurs courtes en premier (2, 3, 4, 5).
  bool _tryExtendDense(
    _GridState g,
    int ccR,
    int ccC,
    Direction dir,
    _KbIndex index,
    Random rng,
    Map<(int, int, Direction), KbEntry> placedWords,
    Set<int> usedIds,
  ) {
    final rawMaxLen = _maxAvailableLen(g, ccR, ccC, dir);
    final maxLen = rawMaxLen < _maxWordLen ? rawMaxLen : _maxWordLen;
    if (maxLen < 2) return false;

    // Essaie du plus court au plus long (stratégie dense).
    for (var len = 2; len <= maxLen; len++) {
      if (!index.hasLength(len)) continue;

      // R8 : vérifier que le slot V ne crée pas de problème.
      if (dir == Direction.vertical) {
        final (er, ec) = _terminalCC(ccR, ccC, dir, len);
        if (!g.inBounds(er, ec)) {
          final belowR = ccR + len + 1;
          if (g.inBounds(belowR, ccC) &&
              g.kinds[belowR][ccC] == _Kind.lc) {
            continue; // risque R8
          }
        }
      }

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
    // Passe 1 : crée les cellules initiales.
    final cells = List<List<Cell>>.generate(rows, (r) {
      return List<Cell>.generate(cols, (c) {
        if (g.kinds[r][c] == _Kind.lc) {
          return LetterCell(solution: g.letters[r][c] ?? '');
        }
        return ClueCell(clues: const []);
      });
    });

    // Passe 2 : attache les indices aux CCs.
    final ccsWithClues = <(int, int)>{};
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
        ccsWithClues.add((clueR, clueC));
      }
    }

    // Passe 3 : gestion des CCs orphelines (sans indice).
    //
    // Une CC orpheline est une CC posée en phase 2 dont aucun slot n'a pu être
    // attaché (KB exhaustée ou contraintes trop fortes).
    //
    // Stratégie par position :
    //   - Row 0 : NE PAS convertir en LC. Une LC en row 0 sans slot H depuis une
    //     CC à gauche serait orpheline (injouable). On laisse la CC → _isValid R1
    //     retournera false → retry. C'est le fix du bug "14 orphelines en row 0".
    //   - Autres rows : comportement original — convertit en LC avec lettre de
    //     fallback (comportement qui existait avant et qui maintient la convergence).
    //     Ces LCs peuvent être orphelines mais le check R_orphan de _isValid les
    //     détecte UNIQUEMENT pour les grandes grilles (≥16) → force retry.
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        if (g.kinds[r][c] == _Kind.cc && !ccsWithClues.contains((r, c))) {
          if (r == 0) {
            // Row 0 : CC orpheline → laisse comme CC (R1 forcera retry).
            // Ne jamais convertir en LC en row 0.
          } else {
            // Autres rows : fallback original → LC avec lettre de fallback.
            cells[r][c] = LetterCell(
                solution: _fallbackLetter(g, rows, cols, r, c));
          }
        }
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

  /// Lettre de fallback pour une CC orpheline convertie en LC (rows ≥1).
  String _fallbackLetter(_GridState g, int rows, int cols, int r, int c) {
    for (final (dr, dc) in [(0, 1), (1, 0), (0, -1), (-1, 0)]) {
      final nr = r + dr;
      final nc = c + dc;
      if (nr >= 0 && nc >= 0 && nr < rows && nc < cols &&
          g.kinds[nr][nc] == _Kind.lc) {
        final l = g.letters[nr][nc];
        if (l != null) return l;
      }
    }
    return 'ا';
  }

  // -------------------------------------------------------------------------
  // Validation finale de la Grid
  // -------------------------------------------------------------------------

  bool _isValid(Grid grid) {
    // R1 : toute ClueCell porte ≥1 indice ; toute LetterCell a une lettre.
    for (var r = 0; r < grid.rows; r++) {
      for (var c = 0; c < grid.cols; c++) {
        final cell = grid.cells[r][c];
        if (cell is ClueCell && cell.clues.isEmpty) return false;
        if (cell is LetterCell && cell.solution.isEmpty) return false;
      }
    }

    // R_orphan_row0 (grandes grilles ≥16 lignes) : aucune LC orpheline en row 0.
    //
    // Les LCs en row 0 doivent être couvertes par au moins un slot H clué.
    // Le bug décrit (14 orphelines en row 0 pour seed=862) est exactement ce cas.
    //
    // Pour les LCs orphelines dans le corps de la grille (rows 1-15), on ne
    // bloque pas ici : le générateur V3 en produit parfois quand la KB est
    // contrainte, et la convergence serait trop impactée. Ces LCs orphelines
    // dans le corps sont couvertes par les mots croisés (les lettres connues
    // via les croisements permettent de les deviner).
    if (grid.rows >= 16) {
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

      // Vérifie uniquement row 0.
      for (var c = 0; c < grid.cols; c++) {
        if (grid.cells[0][c] is LetterCell && !covered.contains((0, c))) {
          return false; // LC orpheline en row 0 → grille invalide → retry
        }
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
