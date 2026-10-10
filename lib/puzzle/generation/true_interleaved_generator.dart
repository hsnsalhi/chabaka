/// Moteur V7 — TrueInterleavedGenerator (règles strictes, grille 8×10).
///
/// ## Stratégie V7 : Plan-First avec passes itératives
///
/// On génère les slots (séquences + CC parents) de façon itérative H→V jusqu'à
/// convergence. À chaque passe, on crée les slots pour les séquences non encore
/// couvertes. La topologie (isCC) est dérivée des CC parents des slots.
///
/// ## Les 4 types de flèches
///
///   - **← hSameRow** (mode A-H) : CC(r,c) → mot H en (r, c+1..c+L)
///   - **↓ vSameCol** (mode A-V) : CC(r,c) → mot V en (r+1..r+L, c)
///   - **↲ hRowBelow** (mode B-H): CC(r,c) → mot H en (r+1, c..c+L-1)
///   - **↴ vColRight** (mode B-V): CC(r,c) → mot V en (r..r+L-1, c+1)
///
/// ## Règles strictes
///
///   R_noOrphan : 0 LC orpheline (toute séquence LC≥2 a 1 CC).
///   R_noDouble : pas de 2 CCs pointant vers la même séquence.
///   R_ccTarget : toute CC pointe vers une séquence LC≥2.
///   R7         : max 2 CCs consécutives H/V.
///   R1         : toute CC porte ≥1 clue ; toute LC a une lettre.
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

int _minCcsForGrid(int rows, int cols) {
  final computed = ((rows * cols) * _minCcDensity).round();
  return computed < 3 ? 3 : computed;
}

// ---------------------------------------------------------------------------
// Normalisation arabe
// ---------------------------------------------------------------------------

String _normalize(String letter) {
  if (letter.isEmpty) return letter;
  final cp = letter.runes.first;
  if ((cp >= 0x064B && cp <= 0x065F) ||
      (cp >= 0x0610 && cp <= 0x061A) ||
      (cp >= 0x06D6 && cp <= 0x06DC) ||
      cp == 0x200C ||
      cp == 0x200D) {
    return '';
  }
  // R9 (PO 2026-05-12) : la hamza ء (0x0621) reste DISTINCTE de l'alif ا.
  // Seules les 3 variantes d'alif diacritées sont mappées vers ا.
  return switch (cp) {
    0x0622 || 0x0623 || 0x0625 => 'ا',
    0x0629 => 'ه',
    0x0649 => 'ي',
    _ => letter,
  };
}

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
    Set<String>? categories,
    int? maxDifficulty,
  }) async {
    final byLen = <int, List<KbEntry>>{};
    for (var len = 2; len <= maxLen; len++) {
      final entries = await kb.findMatching(
        length: len,
        limit: limitPerLen,
        categories: categories,
        maxDifficulty: maxDifficulty,
      );
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
          posMap
              .putIfAbsent(pos, () => {})
              .putIfAbsent(letter, () => [])
              .add(idx);
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
      final pairs =
          constraints.map((c) {
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
// Slot et mode
// ---------------------------------------------------------------------------

class _Slot {
  final int startRow;
  final int startCol;
  final Direction dir;
  final int length;
  final int ccRow;
  final int ccCol;
  final _CcMode mode;

  const _Slot({
    required this.startRow,
    required this.startCol,
    required this.dir,
    required this.length,
    required this.ccRow,
    required this.ccCol,
    required this.mode,
  });

  ClueArrow get arrowType {
    if (mode == _CcMode.c) return ClueArrow.vColLeft;
    if (mode == _CcMode.a) {
      return dir == Direction.horizontal
          ? ClueArrow.hSameRow
          : ClueArrow.vSameCol;
    } else {
      return dir == Direction.horizontal
          ? ClueArrow.hRowBelow
          : ClueArrow.vColRight;
    }
  }
}

enum _CcMode { a, b, c }

/// Nombre maximal d'indices portés par une même CC (cellule triple possible).
const int _maxCluesPerCc = 3;

// ---------------------------------------------------------------------------
// Topologie
// ---------------------------------------------------------------------------

class _Topo {
  final int rows;
  final int cols;
  final List<List<bool>> isCC;

  _Topo(this.rows, this.cols)
    : isCC = List.generate(rows, (_) => List.filled(cols, false));

  bool inBounds(int r, int c) => r >= 0 && c >= 0 && r < rows && c < cols;

  List<(int, int, Direction, int)> allSequences() {
    final seqs = <(int, int, Direction, int)>[];
    for (var r = 0; r < rows; r++) {
      var c = 0;
      while (c < cols) {
        if (!isCC[r][c]) {
          final sc = c;
          while (c < cols && !isCC[r][c]) c++;
          final len = c - sc;
          if (len >= 2) seqs.add((r, sc, Direction.horizontal, len));
        } else {
          c++;
        }
      }
    }
    for (var c = 0; c < cols; c++) {
      var r = 0;
      while (r < rows) {
        if (!isCC[r][c]) {
          final sr = r;
          while (r < rows && !isCC[r][c]) r++;
          final len = r - sr;
          if (len >= 2) seqs.add((sr, c, Direction.vertical, len));
        } else {
          r++;
        }
      }
    }
    return seqs;
  }

  bool hasIsolatedLC({bool debug = false}) {
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        if (isCC[r][c]) continue;
        final lh = c == 0 || isCC[r][c - 1];
        final rh = c == cols - 1 || isCC[r][c + 1];
        final up = r == 0 || isCC[r - 1][c];
        final dn = r == rows - 1 || isCC[r + 1][c];
        if (lh && rh && up && dn) {
          if (debug) {
            // ignore: avoid_print
            print('  isolated LC: ($r,$c) lh=$lh rh=$rh up=$up dn=$dn');
          }
          return true;
        }
      }
    }
    return false;
  }

  bool checkR7() {
    for (var r = 0; r < rows; r++) {
      var run = 0;
      for (var c = 0; c < cols; c++) {
        run = isCC[r][c] ? run + 1 : 0;
        if (run >= 3) return false;
      }
    }
    for (var c = 0; c < cols; c++) {
      var run = 0;
      for (var r = 0; r < rows; r++) {
        run = isCC[r][c] ? run + 1 : 0;
        if (run >= 3) return false;
      }
    }
    return true;
  }

  int get ccCount {
    var n = 0;
    for (final row in isCC) for (final v in row) if (v) n++;
    return n;
  }
}

// ---------------------------------------------------------------------------
// Génération Plan-First itérative (V7.4)
//
// État : isCC (matrice), slots (liste), slotKeys (index rapide), ccUsage.
//
// Passe H : pour chaque séquence H non couverte, essayer de la couvrir.
// Passe V : pour chaque séquence V non couverte ou trop longue, la corriger.
// Itérer jusqu'à stabilité (≤ 5 itérations).
// ---------------------------------------------------------------------------

class _TopoAndSlots {
  final _Topo topo;
  final List<_Slot> slots;
  _TopoAndSlots(this.topo, this.slots);
}

/// Phase 1 : construction garantie de la topologie — approche "blocs alternés".
///
/// Stratégie : on découpe chaque ligne en séquences de longueur ∈ [2, maxLen].
/// Une séquence H peut être couverte par :
///   - A-H : CC à `(r, sc-1)` — CC sur la même ligne, juste avant.
///   - B-H : CC à `(r-1, sc)` — CC sur la ligne précédente, à la position de départ.
///
/// Pour éviter R7 (≥3 CCs consécutives en V), on n'impose PAS de CC en colonne 0
/// sur toutes les lignes. À la place :
///   - Lignes paires  : CC en première position de chaque segment (A-H naturel).
///   - Lignes impaires : la première séquence peut être couverte par B-H depuis
///     la CC en `(r-1, sc)` si elle existe, sinon on place un CC.
///
/// **Règle fondamentale** : jamais deux CC consécutives dans la même colonne
/// sur plus de 2 lignes → `canPlace()` vérifie hRun<3 ET vRun<3.
///
/// Après la génération H, une passe V insère des CCs pour couvrir les séquences
/// verticales non encore couvertes.
List<List<bool>> _buildTopology(int rows, int cols, Random rng) {
  final isCC = List.generate(rows, (_) => List.filled(cols, false));

  // ---- Helpers R7 ----
  int hRun(int r, int c) {
    var n = isCC[r][c] ? 1 : 0;
    for (var d = 1; c - d >= 0 && isCC[r][c - d]; d++) n++;
    for (var d = 1; c + d < cols && isCC[r][c + d]; d++) n++;
    return n;
  }

  int vRun(int r, int c) {
    var n = isCC[r][c] ? 1 : 0;
    for (var d = 1; r - d >= 0 && isCC[r - d][c]; d++) n++;
    for (var d = 1; r + d < rows && isCC[r + d][c]; d++) n++;
    return n;
  }

  bool canPlace(int r, int c) {
    if (r < 0 || c < 0 || r >= rows || c >= cols) return false;
    if (isCC[r][c]) return true;
    isCC[r][c] = true;
    final ok = hRun(r, c) < 3 && vRun(r, c) < 3;
    isCC[r][c] = false;
    return ok;
  }

  bool place(int r, int c) {
    if (!canPlace(r, c)) return false;
    isCC[r][c] = true;
    return true;
  }

  // ---- Étape 1 : génération ligne par ligne ----
  //
  // Pour chaque ligne r, on génère une suite de blocs [CC, seq_LC].
  // Contrainte V : on évite de placer un CC dans la même colonne que la ligne
  // précédente si cela créerait ≥3 CCs consécutives verticalement.
  //
  // Règle de couverture H :
  //   - A-H : isCC[r][c] vrai → couvre seq (r, c+1..c+len).
  //   - B-H : isCC[r-1][c] vrai → couvre seq (r+1, c..c+len-1).
  //
  // On assure qu'au moins l'une des deux est vraie pour chaque séquence H.
  for (var r = 0; r < rows; r++) {
    var c = 0;
    while (c < cols) {
      final remaining = cols - c;
      if (remaining < 2) break; // Pas assez de place pour une séquence.

      // Calculer la longueur du prochain segment LC.
      final maxSeg = remaining > _maxWordLen ? _maxWordLen : remaining;
      // seqLen ∈ [2, maxSeg] — mais si maxSeg == remaining on ne pose pas de CC
      // après (fin de ligne), donc on prend tout.
      final seqLen = 2 + (maxSeg > 2 ? rng.nextInt(maxSeg - 1) : 0);

      // Chercher ou poser une CC pour couvrir ce segment.
      // Option A-H : CC à (r, c-1).
      // Option B-H : CC à (r-1, c).
      // Si aucune n'est possible/existante → on essaie de placer A-H d'abord.
      final hasAH = c > 0 && isCC[r][c - 1];
      final hasBH = r > 0 && isCC[r - 1][c];

      if (!hasAH && !hasBH) {
        // Tenter A-H (CC à gauche sur la même ligne).
        if (c > 0 && place(r, c - 1)) {
          // OK : (r, c-1) est maintenant CC.
        } else if (r > 0 && place(r - 1, c)) {
          // OK : B-H via (r-1, c).
        } else if (c == 0) {
          // Première colonne : CC obligatoire en (r, 0) si possible.
          if (!place(r, 0)) {
            // Forcer — rare, cas limite.
            isCC[r][0] = true;
          }
        }
        // Sinon : séquence non couverte → sera traitée par la passe V ou
        // _assignSlots (cas rare en pratique).
      }

      c += seqLen;

      // Poser une CC séparatrice après la séquence (si place).
      if (c < cols && remaining - seqLen >= 2) {
        // La CC est en (r, c). On vérifie R7.
        if (!isCC[r][c]) {
          place(r, c);
          // Si canPlace échoue, on essaie une position décalée.
          if (!isCC[r][c] && c + 1 < cols) {
            place(r, c + 1);
          }
        }
        if (isCC[r][c]) c++;
      }
    }
  }

  // ---- Étape 2 : couverture des séquences H sans CC ----
  // Après la passe H, certaines séquences horizontales peuvent encore manquer
  // de CC (cas c=0 avec B-H impossible). On les couvre ici.
  for (var r = 0; r < rows; r++) {
    var c = 0;
    while (c < cols) {
      if (!isCC[r][c]) {
        final sc = c;
        while (c < cols && !isCC[r][c]) c++;
        final len = c - sc;
        if (len < 2) continue;
        // Vérifier couverture.
        final hasAH = sc > 0 && isCC[r][sc - 1];
        final hasBH = r > 0 && isCC[r - 1][sc];
        if (!hasAH && !hasBH) {
          // Tenter A-H.
          if (sc > 0 && place(r, sc - 1)) {
            // OK.
          } else if (r > 0 && place(r - 1, sc)) {
            // OK.
          }
          // Sinon : laisse pour _assignSlots.
        }
      } else {
        c++;
      }
    }
  }

  // ---- Étape 3 : couverture des séquences V sans CC ----
  // Pour chaque séquence V sans CC parent (A-V ou B-V), insérer une CC.
  for (var pass = 0; pass < 15; pass++) {
    var changed = false;

    for (var col = 0; col < cols; col++) {
      var r = 0;
      while (r < rows) {
        if (!isCC[r][col]) {
          final sr = r;
          while (r < rows && !isCC[r][col]) r++;
          final len = r - sr;
          if (len < 2) continue;

          final hasAV = sr > 0 && isCC[sr - 1][col];
          final hasBV = col > 0 && isCC[sr][col - 1];
          if (hasAV || hasBV) continue;

          changed = true;
          // Option A-V : CC à (sr-1, col).
          if (sr > 0 && place(sr - 1, col)) continue;
          // Option B-V : CC à (sr, col-1).
          if (col > 0 && place(sr, col - 1)) continue;
          // Forcer — rare.
          if (sr > 0)
            isCC[sr - 1][col] = true;
          else if (col > 0)
            isCC[sr][col - 1] = true;
        } else {
          r++;
        }
      }
    }

    // ---- Étape 4 : couper séquences longues ----
    // ic ∈ [sc+2, min(sc+maxLen, c-3)] pour garantir partie droite ≥ 2.
    for (var r = 0; r < rows; r++) {
      var c = 0;
      while (c < cols) {
        if (!isCC[r][c]) {
          final sc = c;
          while (c < cols && !isCC[r][c]) c++;
          if (c - sc > _maxWordLen) {
            changed = true;
            final icMax = (sc + _maxWordLen) < (c - 3)
                ? sc + _maxWordLen
                : c - 3;
            var cut = false;
            for (var ic = icMax; ic >= sc + 2 && !cut; ic--) {
              if (place(r, ic)) cut = true;
            }
            if (!cut && icMax >= sc + 2) isCC[r][icMax] = true;
          }
        } else {
          c++;
        }
      }
    }
    for (var col = 0; col < cols; col++) {
      var r = 0;
      while (r < rows) {
        if (!isCC[r][col]) {
          final sr = r;
          while (r < rows && !isCC[r][col]) r++;
          if (r - sr > _maxWordLen) {
            changed = true;
            final irMax = (sr + _maxWordLen) < (r - 3)
                ? sr + _maxWordLen
                : r - 3;
            var cut = false;
            for (var ir = irMax; ir >= sr + 2 && !cut; ir--) {
              if (place(ir, col)) cut = true;
            }
            if (!cut && irMax >= sr + 2) isCC[irMax][col] = true;
          }
        } else {
          r++;
        }
      }
    }

    if (!changed) break;
  }

  return isCC;
}

/// Phase 2 : association séquences ↔ CC avec suppression des CCs orphelines.
///
/// Algorithme itératif :
///   1. Énumérer toutes les séquences LC≥2.
///   2. Assigner chaque séquence à une CC candidate.
///   3. Identifier les CCs orphelines (sans slot).
///   4. Supprimer les CCs orphelines de `isCC` (→ LCs), ce qui peut étendre
///      des séquences existantes et créer de nouvelles séquences.
///   5. Vérifier que les séquences trop longues sont coupées (→ retenter si impossible).
///   6. Recommencer jusqu'à stabilité.
///
/// Retourne null si :
///   - Une séquence n'a aucune CC candidate (incouvrable structurellement).
///   - La suppression de CCs orphelines produit des séquences > _maxWordLen
///     non découpables.
///   - La grille n'a pas assez de CCs après nettoyage.
_TopoAndSlots? _assignSlots(int rows, int cols, List<List<bool>> isCC) {
  // Copie locale mutable de la matrice.
  final cc = List.generate(rows, (r) => List.of(isCC[r]));

  // Sous-fonctions.
  _Slot? _tryAssignSeq(
    int sr,
    int sc,
    Direction dir,
    int len,
    Map<(int, int), int> usage,
  ) {
    if (dir == Direction.horizontal) {
      if (sc > 0 &&
          cc[sr][sc - 1] &&
          (usage[(sr, sc - 1)] ?? 0) < _maxCluesPerCc) {
        return _Slot(
          startRow: sr,
          startCol: sc,
          dir: dir,
          length: len,
          ccRow: sr,
          ccCol: sc - 1,
          mode: _CcMode.a,
        );
      }
      if (sr > 0 &&
          cc[sr - 1][sc] &&
          (usage[(sr - 1, sc)] ?? 0) < _maxCluesPerCc) {
        return _Slot(
          startRow: sr,
          startCol: sc,
          dir: dir,
          length: len,
          ccRow: sr - 1,
          ccCol: sc,
          mode: _CcMode.b,
        );
      }
      if (sc > 0 && cc[sr][sc - 1]) {
        return _Slot(
          startRow: sr,
          startCol: sc,
          dir: dir,
          length: len,
          ccRow: sr,
          ccCol: sc - 1,
          mode: _CcMode.a,
        );
      }
      if (sr > 0 && cc[sr - 1][sc]) {
        return _Slot(
          startRow: sr,
          startCol: sc,
          dir: dir,
          length: len,
          ccRow: sr - 1,
          ccCol: sc,
          mode: _CcMode.b,
        );
      }
    } else {
      if (sr > 0 &&
          cc[sr - 1][sc] &&
          (usage[(sr - 1, sc)] ?? 0) < _maxCluesPerCc) {
        return _Slot(
          startRow: sr,
          startCol: sc,
          dir: dir,
          length: len,
          ccRow: sr - 1,
          ccCol: sc,
          mode: _CcMode.a,
        );
      }
      if (sc > 0 &&
          cc[sr][sc - 1] &&
          (usage[(sr, sc - 1)] ?? 0) < _maxCluesPerCc) {
        return _Slot(
          startRow: sr,
          startCol: sc,
          dir: dir,
          length: len,
          ccRow: sr,
          ccCol: sc - 1,
          mode: _CcMode.b,
        );
      }
      if (sc + 1 < cols &&
          cc[sr][sc + 1] &&
          (usage[(sr, sc + 1)] ?? 0) < _maxCluesPerCc) {
        return _Slot(
          startRow: sr,
          startCol: sc,
          dir: dir,
          length: len,
          ccRow: sr,
          ccCol: sc + 1,
          mode: _CcMode.c,
        );
      }
      if (sr > 0 && cc[sr - 1][sc]) {
        return _Slot(
          startRow: sr,
          startCol: sc,
          dir: dir,
          length: len,
          ccRow: sr - 1,
          ccCol: sc,
          mode: _CcMode.a,
        );
      }
      if (sc > 0 && cc[sr][sc - 1]) {
        return _Slot(
          startRow: sr,
          startCol: sc,
          dir: dir,
          length: len,
          ccRow: sr,
          ccCol: sc - 1,
          mode: _CcMode.b,
        );
      }
      if (sc + 1 < cols && cc[sr][sc + 1]) {
        return _Slot(
          startRow: sr,
          startCol: sc,
          dir: dir,
          length: len,
          ccRow: sr,
          ccCol: sc + 1,
          mode: _CcMode.c,
        );
      }
    }
    return null;
  }

  List<(int, int, Direction, int)> _enumSeqs() {
    final seqs = <(int, int, Direction, int)>[];
    for (var r = 0; r < rows; r++) {
      var c = 0;
      while (c < cols) {
        if (!cc[r][c]) {
          final sc = c;
          while (c < cols && !cc[r][c]) c++;
          final len = c - sc;
          if (len >= 2) seqs.add((r, sc, Direction.horizontal, len));
        } else {
          c++;
        }
      }
    }
    for (var col = 0; col < cols; col++) {
      var r = 0;
      while (r < rows) {
        if (!cc[r][col]) {
          final sr = r;
          while (r < rows && !cc[r][col]) r++;
          final len = r - sr;
          if (len >= 2) seqs.add((sr, col, Direction.vertical, len));
        } else {
          r++;
        }
      }
    }
    return seqs;
  }

  // Boucle principale.
  const maxIter = 10;
  for (var iter = 0; iter < maxIter; iter++) {
    final seqs = _enumSeqs();
    final slots = <_Slot>[];
    final slotKeys = <(int, int, Direction)>{};
    final usage = <(int, int), int>{};

    void addSlot(_Slot s) {
      if (slotKeys.contains((s.startRow, s.startCol, s.dir))) return;
      slots.add(s);
      slotKeys.add((s.startRow, s.startCol, s.dir));
      final key = (s.ccRow, s.ccCol);
      usage[key] = (usage[key] ?? 0) + 1;
    }

    // Assigner les séquences.
    for (final (sr, sc, dir, len) in seqs) {
      final slot = _tryAssignSeq(sr, sc, dir, len, usage);
      if (slot == null) return null;
      addSlot(slot);
    }

    // Vérifier R_noDouble (slots.length == seqs.length par construction addSlot).
    if (slots.length != seqs.length) return null;

    // Identifier les CCs orphelines.
    final coveredCcs = <(int, int)>{};
    for (final s in slots) coveredCcs.add((s.ccRow, s.ccCol));

    var orphans = <(int, int)>[];
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        if (cc[r][c] && !coveredCcs.contains((r, c))) {
          orphans.add((r, c));
        }
      }
    }

    if (orphans.isEmpty) {
      // Stable : pas d'orphelines. Construire la topologie finale.
      final topo = _Topo(rows, cols);
      for (var r = 0; r < rows; r++) {
        for (var c = 0; c < cols; c++) {
          topo.isCC[r][c] = cc[r][c];
        }
      }
      return _TopoAndSlots(topo, slots);
    }

    // Supprimer les CCs orphelines (→ LCs).
    for (final (r, c) in orphans) {
      cc[r][c] = false;
    }

    // Vérifier que la suppression n'a pas créé de séquences trop longues.
    // Si oui → topologie invalide → retenter.
    for (var r = 0; r < rows; r++) {
      var c = 0;
      while (c < cols) {
        if (!cc[r][c]) {
          final sc = c;
          while (c < cols && !cc[r][c]) c++;
          if (c - sc > _maxWordLen) return null;
        } else {
          c++;
        }
      }
    }
    for (var col = 0; col < cols; col++) {
      var r = 0;
      while (r < rows) {
        if (!cc[r][col]) {
          final sr = r;
          while (r < rows && !cc[r][col]) r++;
          if (r - sr > _maxWordLen) return null;
        } else {
          r++;
        }
      }
    }
    // Boucler pour ré-assigner avec la nouvelle topologie.
  }
  return null; // n'a pas convergé
}

_TopoAndSlots? _buildTopoAndSlots(int rows, int cols, Random rng) {
  final isCC = _buildTopology(rows, cols, rng);
  return _assignSlots(rows, cols, isCC);
}

// ---------------------------------------------------------------------------
// Validation stricte V7
// ---------------------------------------------------------------------------

String? validateStrict(Grid grid) {
  for (var r = 0; r < grid.rows; r++) {
    for (var c = 0; c < grid.cols; c++) {
      final cell = grid.cells[r][c];
      if (cell is ClueCell && cell.clues.isEmpty)
        return 'R1 violé : CC vide en ($r,$c)';
      if (cell is LetterCell && cell.solution.isEmpty)
        return 'R1 violé : LC vide en ($r,$c)';
    }
  }

  final allSeqs = _findAllLcSequences(grid);
  final seqIndex = <(int, int, Direction), int>{};
  for (var i = 0; i < allSeqs.length; i++) {
    final s = allSeqs[i];
    seqIndex[(s.$1, s.$2, s.$3)] = i;
  }
  final seqCount = List.filled(allSeqs.length, 0);

  for (var r = 0; r < grid.rows; r++) {
    for (var c = 0; c < grid.cols; c++) {
      final cell = grid.cells[r][c];
      if (cell is! ClueCell) continue;
      for (final clue in cell.clues) {
        final key = (clue.startCell.row, clue.startCell.col, clue.direction);
        final idx = seqIndex[key];
        if (idx == null) {
          return 'R_ccTarget violé : CC($r,$c) → '
              '(${clue.startCell.row},${clue.startCell.col}) ${clue.direction.name} '
              'n\'est pas une séquence LC≥2';
        }
        seqCount[idx]++;
      }
    }
  }

  for (var i = 0; i < allSeqs.length; i++) {
    final (sr, sc, dir, len) = allSeqs[i];
    if (seqCount[i] == 0) {
      return 'R_noOrphan violé : séquence ${dir.name} ($sr,$sc) len=$len sans CC';
    }
    if (seqCount[i] > 1) {
      return 'R_noDouble violé : séquence ${dir.name} ($sr,$sc) len=$len a ${seqCount[i]} CCs';
    }
  }

  final covered = <(int, int)>{};
  for (final clue in grid.allClues) {
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

  for (var r = 0; r < grid.rows; r++) {
    for (var c = 0; c < grid.cols; c++) {
      if (grid.cells[r][c] is LetterCell && !covered.contains((r, c))) {
        return 'R_noOrphan violé : LC($r,$c) orpheline';
      }
    }
  }

  return null;
}

List<(int, int, Direction, int)> _findAllLcSequences(Grid grid) {
  final seqs = <(int, int, Direction, int)>[];

  for (var r = 0; r < grid.rows; r++) {
    var c = 0;
    while (c < grid.cols) {
      if (grid.cells[r][c] is LetterCell) {
        final sc = c;
        while (c < grid.cols && grid.cells[r][c] is LetterCell) c++;
        final len = c - sc;
        if (len >= 2) seqs.add((r, sc, Direction.horizontal, len));
      } else {
        c++;
      }
    }
  }

  for (var c = 0; c < grid.cols; c++) {
    var r = 0;
    while (r < grid.rows) {
      if (grid.cells[r][c] is LetterCell) {
        final sr = r;
        while (r < grid.rows && grid.cells[r][c] is LetterCell) r++;
        final len = r - sr;
        if (len >= 2) seqs.add((sr, c, Direction.vertical, len));
      } else {
        r++;
      }
    }
  }

  return seqs;
}

// ---------------------------------------------------------------------------
// TrueInterleavedGenerator V7
// ---------------------------------------------------------------------------

class TrueInterleavedGenerator implements R4GeneratorApi {
  final KbRepository kb;

  static const int _cacheLimit = 3000;
  static const int _maxCandidatesPerSlot = 80;

  const TrueInterleavedGenerator({required this.kb});

  @override
  Future<Grid?> generate(TopologyConfig config) async {
    final index = await _KbIndex.build(
      kb,
      maxLen: _maxWordLen,
      limitPerLen: _cacheLimit,
      categories: config.categories,
      maxDifficulty: config.maxDifficulty,
    );
    final deadline = DateTime.now().add(
      Duration(milliseconds: config.backtrackTimeoutMs),
    );
    final minCcs = _minCcsForGrid(config.rows, config.cols);

    for (var attempt = 0; attempt < config.maxRetries; attempt++) {
      if (DateTime.now().isAfter(deadline)) break;
      await Future<void>.delayed(Duration.zero);

      final seed = _perturbSeed(config.seed, attempt);
      final rng = Random(seed);

      // Phase A : plan-first topologie + slots.
      final result = _buildTopoAndSlots(config.rows, config.cols, rng);
      if (result == null) continue;

      final topo = result.topo;
      final slots = result.slots;

      if (!topo.checkR7()) continue;
      if (topo.hasIsolatedLC()) continue;
      if (topo.ccCount < minCcs) continue;

      // Vérifier les longueurs dans la KB.
      final lengths = slots.map((s) => s.length).toSet();
      var hasAllLengths = true;
      for (final len in lengths) {
        if (!index.hasLength(len)) {
          hasAllLengths = false;
          break;
        }
      }
      if (!hasAllLengths) continue;

      // Phase B : remplir les slots avec des mots.
      final letters = List<List<String?>>.generate(
        config.rows,
        (_) => List.filled(config.cols, null),
      );
      final placedWords = <_Slot, KbEntry>{};
      final usedIds = <int>{};

      final sortedSlots = List.of(slots)
        ..sort((a, b) => b.length.compareTo(a.length));

      final success = _fillSlots(
        sortedSlots,
        letters,
        placedWords,
        usedIds,
        index,
        rng,
        deadline,
      );
      if (!success) continue;

      // Phase C : construire la Grid.
      final grid = _buildGrid(
        config.rows,
        config.cols,
        topo,
        slots,
        placedWords,
        seed,
      );
      if (_isValidStrict(grid)) return grid;
    }
    return null;
  }

  bool _fillSlots(
    List<_Slot> slots,
    List<List<String?>> letters,
    Map<_Slot, KbEntry> placedWords,
    Set<int> usedIds,
    _KbIndex index,
    Random rng,
    DateTime deadline,
  ) {
    if (slots.isEmpty) return true;
    if (DateTime.now().isAfter(deadline)) return false;

    _Slot? bestSlot;
    List<KbEntry>? bestCands;
    var bestCount = 999999;

    for (final slot in slots) {
      if (placedWords.containsKey(slot)) continue;
      final constraints = _constraintsFor(slot, letters);
      final cands = index.find(
        length: slot.length,
        constraints: constraints,
        excludeIds: usedIds,
        limit: _maxCandidatesPerSlot,
      );
      if (cands.isEmpty) return false;
      if (cands.length < bestCount) {
        bestSlot = slot;
        bestCands = cands;
        bestCount = cands.length;
        if (bestCount == 1) break;
      }
    }

    if (bestSlot == null) return true;

    final shuffled = List.of(bestCands!)..shuffle(rng);
    final remaining = slots
        .where((s) => s != bestSlot && !placedWords.containsKey(s))
        .toList();

    for (final entry in shuffled) {
      if (DateTime.now().isAfter(deadline)) return false;
      if (_placeWord(bestSlot, entry.word, letters)) {
        placedWords[bestSlot] = entry;
        usedIds.add(entry.id);

        if (_fillSlots(
          remaining,
          letters,
          placedWords,
          usedIds,
          index,
          rng,
          deadline,
        )) {
          return true;
        }

        _unplaceWord(bestSlot, letters, placedWords);
        placedWords.remove(bestSlot);
        usedIds.remove(entry.id);
      }
    }

    return false;
  }

  List<LetterConstraint> _constraintsFor(
    _Slot slot,
    List<List<String?>> letters,
  ) {
    final result = <LetterConstraint>[];
    for (var i = 0; i < slot.length; i++) {
      final r = slot.dir == Direction.horizontal
          ? slot.startRow
          : slot.startRow + i;
      final c = slot.dir == Direction.horizontal
          ? slot.startCol + i
          : slot.startCol;
      final existing = letters[r][c];
      if (existing != null) {
        final norm = _normalize(existing);
        if (norm.isNotEmpty)
          result.add(LetterConstraint(position: i, letter: norm));
      }
    }
    return result;
  }

  bool _placeWord(_Slot slot, String word, List<List<String?>> letters) {
    final runes = word.runes.toList();
    if (runes.length != slot.length) return false;

    for (var i = 0; i < slot.length; i++) {
      final r = slot.dir == Direction.horizontal
          ? slot.startRow
          : slot.startRow + i;
      final c = slot.dir == Direction.horizontal
          ? slot.startCol + i
          : slot.startCol;
      final letter = String.fromCharCode(runes[i]);
      final existing = letters[r][c];
      if (existing != null && _normalize(existing) != _normalize(letter))
        return false;
    }

    for (var i = 0; i < slot.length; i++) {
      final r = slot.dir == Direction.horizontal
          ? slot.startRow
          : slot.startRow + i;
      final c = slot.dir == Direction.horizontal
          ? slot.startCol + i
          : slot.startCol;
      letters[r][c] = String.fromCharCode(runes[i]);
    }
    return true;
  }

  void _unplaceWord(
    _Slot slot,
    List<List<String?>> letters,
    Map<_Slot, KbEntry> placed,
  ) {
    for (var i = 0; i < slot.length; i++) {
      final r = slot.dir == Direction.horizontal
          ? slot.startRow
          : slot.startRow + i;
      final c = slot.dir == Direction.horizontal
          ? slot.startCol + i
          : slot.startCol;
      var shared = false;
      for (final other in placed.keys) {
        if (other == slot) continue;
        for (var j = 0; j < other.length; j++) {
          final or2 = other.dir == Direction.horizontal
              ? other.startRow
              : other.startRow + j;
          final oc = other.dir == Direction.horizontal
              ? other.startCol + j
              : other.startCol;
          if (or2 == r && oc == c) {
            shared = true;
            break;
          }
        }
        if (shared) break;
      }
      if (!shared) letters[r][c] = null;
    }
  }

  Grid _buildGrid(
    int rows,
    int cols,
    _Topo topo,
    List<_Slot> slots,
    Map<_Slot, KbEntry> placedWords,
    int seed,
  ) {
    final cells = List<List<Cell>>.generate(rows, (r) {
      return List<Cell>.generate(cols, (c) {
        if (topo.isCC[r][c]) return ClueCell(clues: const []);
        return LetterCell(solution: '');
      });
    });

    for (final entry in placedWords.entries) {
      final slot = entry.key;
      final kbEntry = entry.value;
      final runes = kbEntry.word.runes.toList();
      for (var i = 0; i < slot.length; i++) {
        final r = slot.dir == Direction.horizontal
            ? slot.startRow
            : slot.startRow + i;
        final c = slot.dir == Direction.horizontal
            ? slot.startCol + i
            : slot.startCol;
        cells[r][c] = LetterCell(solution: String.fromCharCode(runes[i]));
      }
    }

    for (final entry in placedWords.entries) {
      final slot = entry.key;
      final kbEntry = entry.value;
      final primary = kbEntry.primaryClue;
      if (primary == null) continue;

      final clue = Clue(
        text: primary.text,
        language: ClueLanguage.arabic,
        direction: slot.dir,
        // R3+R9 : utiliser word normalisé (sans shadda/diacritiques) pour
        // que la longueur match exactement le nombre de cellules LCs.
        // wordDisplay garde shadda mais peut être 5 runes pour 4 cellules.
        solution: kbEntry.word,
        startCell: Position(slot.startRow, slot.startCol),
        arrowType: slot.arrowType,
      );

      final existing = cells[slot.ccRow][slot.ccCol];
      if (existing is ClueCell) {
        cells[slot.ccRow][slot.ccCol] = ClueCell(
          clues: [...existing.clues, clue],
        );
      }
    }

    return Grid(
      rows: rows,
      cols: cols,
      cells: cells,
      variant: GridVariant.standard,
      id: 'v7-strict-$seed',
      title: 'شبكة اليوم',
      author: 'Chabaka',
    );
  }

  bool _isValidStrict(Grid grid) => validateStrict(grid) == null;

  Future<Grid> generateRaw(TopologyConfig config) async {
    final index = await _KbIndex.build(
      kb,
      maxLen: _maxWordLen,
      limitPerLen: _cacheLimit,
      categories: config.categories,
      maxDifficulty: config.maxDifficulty,
    );
    final deadline = DateTime.now().add(
      Duration(milliseconds: config.backtrackTimeoutMs),
    );
    final rng = Random(config.seed);
    final result = _buildTopoAndSlots(config.rows, config.cols, rng);
    final topo = result?.topo ?? _Topo(config.rows, config.cols);
    final slots = result?.slots ?? [];
    final sortedSlots = List.of(slots)
      ..sort((a, b) => b.length.compareTo(a.length));
    final letters = List<List<String?>>.generate(
      config.rows,
      (_) => List.filled(config.cols, null),
    );
    final placedWords = <_Slot, KbEntry>{};
    final usedIds = <int>{};
    _fillSlots(
      sortedSlots,
      letters,
      placedWords,
      usedIds,
      index,
      rng,
      deadline,
    );
    return _buildGrid(
      config.rows,
      config.cols,
      topo,
      slots,
      placedWords,
      config.seed,
    );
  }

  int _perturbSeed(int base, int attempt) =>
      attempt == 0 ? base : base * 1009 + attempt * 9973;
}
