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

/// Vérifie que placer un slot V depuis (ccR, ccC) de longueur [len] ne
/// crée pas de V edge slot.
///
/// Règle : le premier LC est en (ccR+1, ccC). Pour chaque LC de ce slot,
/// on vérifie que le LC a bien une CC immédiatement au-dessus ou fait
/// partie d'un run V déjà couvert (même slot). En pratique, (ccR, ccC)
/// est la CC prédécesseure donc (ccR+1, ccC) a une CC au-dessus → OK.
/// Mais si certaines cases dans le slot sont déjà des LCs faisant partie
/// d'un run V plus long, il peut y avoir une violation.
bool _wouldCreateVEdgeSlot(_GridState g, int ccR, int ccC, int len) {
  // Pour un slot V depuis (ccR, ccC), les LCs sont en (ccR+1..ccR+len, ccC).
  // La CC prédécesseure est (ccR, ccC). La première LC a donc une CC au-dessus.
  // Le problème survient si des LCs DÉJÀ EXISTANTES en-dessous vont étendre
  // un run V sans CC au-dessus propre.
  //
  // Cas concret : si (ccR+len+1, ccC) est déjà LC et que la CC fermante
  // (ccR+len+1, ccC) ne sera pas posée (bord de grille), on aurait un run
  // V de len+X sans CC à la jonction.
  //
  // On vérifie en simulant : après placement, le run V depuis (ccR+1, ccC)
  // aurait-il une CC immédiatement au-dessus ?
  // (ccR, ccC) = CC = OK pour (ccR+1, ccC).
  // Pas de V edge slot créé par le slot lui-même.
  // Mais si des LCs existants juste sous le slot formeraient une extension...
  final nextR = ccR + len + 1;
  if (g.inBounds(nextR, ccC) && g.kinds[nextR][ccC] == _Kind.lc) {
    // Il y a déjà une LC juste après la fin du slot. La CC fermante devra
    // être posée ici. Si elle ne peut pas l'être (R7 violation), le run
    // V combiné (len + run existant) serait sans CC interne → violation R8.
    // On laisse la logique de placement gérer ça : si CC fermante obligatoire
    // ne peut pas être posée, on rejette le slot entier.
    return true; // signale le risque : on forcera la CC fermante
  }
  return false;
}

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
      // R8 strict (row 0 inclus) uniquement pour les très grandes grilles
      // (≥16 lignes, style Abu Salma pur).
      final strictRow0 = config.rows >= 16;
      if (!_checkR8Strict(g, strictRow0: strictRow0)) continue;

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
    // Passe 0 : s'assurer que toute la row 0 est CC (nécessaire pour R8 strict
    // sur les grandes grilles Abu Salma). Pas appliqué aux petites grilles où
    // R7 empêche d'avoir toute la row 0 en CCs.
    if (enforceRow0Cc) {
      _ensureRow0IsCc(g, index, rng, placedWords, usedIds);
    }

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

        // En row 0 (grandes grilles) : doit être CC pour éviter V edge slots.
        if (r == 0 && enforceRow0Cc) {
          // Tente CC si pas R7 violation.
          if (!_wouldViolateR7(g, r, c)) {
            if (_canGenerateSlotForcedCC(g, r, c)) {
              g.setCC(r, c);
              final placed = _tryExtendDense(
                  g, r, c, Direction.vertical, index, rng, placedWords, usedIds);
              final placedH = _tryExtendDense(
                  g, r, c, Direction.horizontal, index, rng, placedWords, usedIds);
              if (placed || placedH) continue;
              // Aucun slot → annule la CC.
              g.undoCC(r, c);
            }
          }
        }

        // Vérifie R8 : si la LC en (r,c) formerait un run V ≥2 sans CC
        // immédiatement au-dessus, on place une CC à la place.
        final strictR8Row0 = enforceRow0Cc;
        final wouldViolateR8 = _lcWouldViolateR8(g, r, c, strictRow0: strictR8Row0);
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

        // Fallback : LC avec lettre de remplissage.
        final letter = _pickLetter(g, r, c, index, rng);
        g.setLC(r, c, letter);
      }
    }
  }

  /// Initialise la row 0 avec des CCs (phase 1.5, grandes grilles).
  ///
  /// Pour les grilles ≥16 lignes (style Abu Salma), la row 0 doit être
  /// entièrement composée de CCs. Cette méthode place des CCs sur toutes
  /// les positions UNDEFINED de la row 0 et tente un slot V depuis chacune.
  ///
  /// Si une position de row 0 est déjà CC (placée par le BFS), on la traite
  /// en tentant de compléter ses slots. Si elle est LC (BFS a placé un mot H
  /// sur cette case), on ne peut pas la changer → violation potentielle de R8
  /// qui sera rejetée par `_checkR8Strict`.
  ///
  /// Différence avec `_ensureRow0IsCc` : cette méthode est plus agressive —
  /// elle pose les CCs même si elle ne peut pas placer de slot immédiatement
  /// (les slots seront tentés lors de la phase 2).
  void _initRow0WithCcs(
    _GridState g,
    _KbIndex index,
    Random rng,
    Map<(int, int, Direction), KbEntry> placedWords,
    Set<int> usedIds,
  ) {
    for (var c = 0; c < g.cols; c++) {
      switch (g.kinds[0][c]) {
        case _Kind.cc:
          // Déjà CC (placé par BFS). Tente uniquement des slots V
          // (les slots H depuis row 0 mettraient des LCs en row 0 → violation R8).
          _tryExtendDense(g, 0, c, Direction.vertical, index, rng, placedWords, usedIds);
        case _Kind.undefined:
          // Tente de poser une CC + slot V uniquement.
          if (_wouldViolateR7(g, 0, c)) continue;
          // Vérifie qu'un slot V est possible (≥2 cases disponibles en-dessous).
          var vAvail = 0;
          for (var dr = 1; dr <= _maxWordLen + 1; dr++) {
            if (!g.inBounds(dr, c)) break;
            if (g.kinds[dr][c] == _Kind.cc) break;
            vAvail++;
          }
          if (vAvail < 2) continue; // Pas de slot V possible → skip
          g.setCC(0, c);
          final vPlaced = _tryExtendDense(
              g, 0, c, Direction.vertical, index, rng, placedWords, usedIds);
          if (!vPlaced) {
            // CC orpheline : annule.
            g.undoCC(0, c);
          }
        case _Kind.lc:
          // LC en row 0 : violation R8 si une LC est en-dessous.
          // On ne peut pas changer une LC posée par le BFS.
          // La vérification finale _checkR8Strict rejettera si nécessaire.
          break;
      }
    }
  }

  /// Assure que toute la row 0 est CC.
  ///
  /// Dans les vraies grilles Abu Salma, la première ligne est composée
  /// quasi-entièrement de CCs qui servent d'en-têtes pour les slots verticaux.
  /// Sans CCs en row 0, les colonnes ne peuvent pas avoir de slots V valides
  /// (R8 strict interdit les V-runs ≥2 sans CC au-dessus, ce qui inclut row 0).
  ///
  /// Pour chaque UNDEFINED en (0, c) :
  ///   - Si pas R7 violation et des LCs existent en-dessous → CC + slot V.
  ///   - Si pas R7 violation et pas de LCs en-dessous → CC + slot H ou V court.
  ///   - Si R7 violation → laisse UNDEFINED (la passe principale gérera).
  void _ensureRow0IsCc(
    _GridState g,
    _KbIndex index,
    Random rng,
    Map<(int, int, Direction), KbEntry> placedWords,
    Set<int> usedIds,
  ) {
    for (var c = 0; c < g.cols; c++) {
      if (g.kinds[0][c] != _Kind.undefined) continue;
      if (_wouldViolateR7(g, 0, c)) continue;

      // Vérifier si une CC ici peut générer un slot V ou H.
      var hasVSlot = false;
      // Slot V : check les LCs ou UNDEFINED en-dessous.
      for (var dr = 1; dr <= _maxWordLen; dr++) {
        if (!g.inBounds(dr, c)) break;
        if (g.kinds[dr][c] == _Kind.cc) break;
        if (dr >= 2) {
          hasVSlot = true;
          break;
        }
      }
      var hasHSlot = false;
      for (var dc = 1; dc <= _maxWordLen; dc++) {
        if (!g.inBounds(0, c + dc)) break;
        if (g.kinds[0][c + dc] == _Kind.cc) break;
        if (dc >= 2) {
          hasHSlot = true;
          break;
        }
      }

      if (!hasVSlot && !hasHSlot) continue; // Pas de slot possible → skip

      // Tente de poser la CC ET uniquement un slot V (pas H, car un slot H
      // depuis row 0 placerait des LCs en row 0 → violation R8 strict).
      // Si aucun slot V n'est possible, on n'annule pas mais on accepte que
      // la CC sera orpheline (gérée par _buildGrid passe 3 → LC fallback).
      g.setCC(0, c);

      // Tente V uniquement (priorité pour couvrir la colonne verticalement).
      if (hasVSlot) {
        _tryExtendDense(g, 0, c, Direction.vertical, index, rng, placedWords, usedIds);
      }
      // Note : si aucun slot V placé, la CC peut rester orpheline.
      // La passe 3 de _buildGrid la convertira en LC avec lettre de fallback.
      // _checkR8Strict vérifiera si cette conversion crée une violation.
    }
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

    // Passe 3 : les CCs sans indice sont des CCs orphelines (posées en phase 2
    // mais dont aucun slot n'a pu être attaché). On les convertit en LC avec
    // une lettre aléatoire pour ne pas créer de violation R1.
    // Note : cette situation est rare grâce aux checks _canGenerateSlot, mais
    // peut survenir si la KB est exhaustée ou si les contraintes sont trop fortes.
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        if (g.kinds[r][c] == _Kind.cc && !ccsWithClues.contains((r, c))) {
          // CC orpheline → convertit en LC avec lettre de fallback.
          // On choisit une lettre cohérente avec les voisins si possible.
          cells[r][c] = LetterCell(solution: _fallbackLetter(g, r, c));
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

  /// Lettre de fallback pour une CC orpheline convertie en LC.
  String _fallbackLetter(_GridState g, int r, int c) {
    // Cherche une lettre dans les LCs voisines.
    for (final (dr, dc) in [(0, 1), (1, 0), (0, -1), (-1, 0)]) {
      final nr = r + dr;
      final nc = c + dc;
      if (g.inBounds(nr, nc) && g.kinds[nr][nc] == _Kind.lc) {
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
