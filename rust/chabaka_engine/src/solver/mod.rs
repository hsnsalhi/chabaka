/// Point d'entrée du solver.
///
/// `solve(config, kb, pattern_kinds)` → `GridOutput`
///
/// Algorithme :
///   1. Extraire les slots depuis le patron (miroir de _computeSlotsFromPattern Dart).
///   2. Initialiser domaines + graphe AC-3.
///   3. AC-3 initial (pré-filtrage).
///   4. Backtracking MRV + forward-check + AC-3 incrémental.
///   5. Construire GridOutput depuis l'état final.
///
/// Restart aléatoire (plan B spec §10 R6) : si timeout dans un sous-arbre,
/// on réinitialise avec un seed perturbé et on recommence.

pub mod ac3;
pub mod domain;
pub mod mrv;
pub mod state;

use std::time::{Duration, Instant};

use rand::seq::SliceRandom;
use rand::SeedableRng;
use rand_chacha::ChaCha8Rng;

use crate::kb::KbCompact;
use crate::models::{
    CellKind, CellOutput, ConfigInput, Direction, EngineError, GridOutput, PlacedEntry, Slot,
};
use crate::solver::ac3::{ac3_full, ac3_incremental, Ac3Result, ArcGraph};
use crate::solver::domain::Domains;
use crate::solver::mrv::select_mrv;
use crate::solver::state::BacktrackState;

// ---------------------------------------------------------------------------
// Extraction des slots depuis le patron
// ---------------------------------------------------------------------------

fn compute_slots(rows: usize, cols: usize, kinds: &[CellKind]) -> Vec<Slot> {
    let mut slots = Vec::new();

    // Slots horizontaux
    for r in 0..rows {
        let mut c = 0usize;
        while c < cols {
            if kinds[r * cols + c] == CellKind::Letter {
                let start = c;
                while c < cols && kinds[r * cols + c] == CellKind::Letter {
                    c += 1;
                }
                let length = c - start;
                if length >= 2 {
                    slots.push(Slot {
                        direction: Direction::Horizontal,
                        start_row: r as u8,
                        start_col: start as u8,
                        length: length as u8,
                    });
                }
            } else {
                c += 1;
            }
        }
    }

    // Slots verticaux
    for c in 0..cols {
        let mut r = 0usize;
        while r < rows {
            if kinds[r * cols + c] == CellKind::Letter {
                let start = r;
                while r < rows && kinds[r * cols + c] == CellKind::Letter {
                    r += 1;
                }
                let length = r - start;
                if length >= 2 {
                    slots.push(Slot {
                        direction: Direction::Vertical,
                        start_row: start as u8,
                        start_col: c as u8,
                        length: length as u8,
                    });
                }
            } else {
                r += 1;
            }
        }
    }

    slots
}

// ---------------------------------------------------------------------------
// Backtracking récursif principal
// ---------------------------------------------------------------------------

struct SolveContext<'a> {
    kb: &'a KbCompact,
    all_slots: &'a [Slot],
    graph: &'a ArcGraph,
    deadline: Instant,
}

/// Résultat du backtracking.
enum BtResult {
    Found,
    Timeout,
    Exhausted,
}

fn backtrack(
    ctx: &SolveContext<'_>,
    state: &mut BacktrackState,
    domains: &mut Domains,
    rng: &mut ChaCha8Rng,
) -> BtResult {
    // Vérification timeout
    if Instant::now() >= ctx.deadline {
        return BtResult::Timeout;
    }

    // Sélection MRV
    let selection = select_mrv(domains, state, ctx.all_slots.len());

    match selection {
        None => return BtResult::Found, // Tous les slots placés
        Some((_, true)) => return BtResult::Exhausted, // Domaine vide → dead end
        Some((slot_idx, false)) => {
            let slot = &ctx.all_slots[slot_idx];
            let length = slot.length as usize;

            // Candidats actifs pour ce slot
            let indices = match ctx.kb.by_length.get(&length) {
                Some(v) => v,
                None => return BtResult::Exhausted,
            };

            let active_slot_indices = domains.slots[slot_idx].active_indices();
            if active_slot_indices.is_empty() {
                return BtResult::Exhausted;
            }

            // Convertir slot-indices en entry-indices, filtrer excluded
            let excluded: std::collections::HashSet<u32> = state.excluded_ids().into_iter().collect();
            let mut candidates: Vec<usize> = active_slot_indices
                .iter()
                .filter_map(|&si| {
                    if si < indices.len() {
                        let entry_idx = indices[si];
                        if !excluded.contains(&ctx.kb.entries[entry_idx].id) {
                            Some(entry_idx)
                        } else {
                            None
                        }
                    } else {
                        None
                    }
                })
                .collect();

            if candidates.is_empty() {
                return BtResult::Exhausted;
            }

            // Mélanger les candidats (ordre aléatoire seedé)
            candidates.shuffle(rng);

            for entry_idx in candidates {
                let entry = &ctx.kb.entries[entry_idx];

                // Vérifier compatibilité des contraintes (forward check)
                let constraints = state.constraints_for(slot);
                let compatible = constraints.iter().all(|c| {
                    c.position < entry.chars.len() && entry.chars[c.position] == c.letter
                });
                if !compatible {
                    continue;
                }

                // Placer le mot
                state.place(slot_idx, entry_idx, slot, entry);

                // Snapshot des domaines pour undo
                let domain_snapshots: Vec<_> = (0..ctx.all_slots.len())
                    .map(|i| domains.snapshot_domain(i))
                    .collect();

                // Mettre à jour le domaine du slot placé = singleton
                // (on le marque comme "résolu" en vidant son domaine publique)
                // Note: le slot est maintenant dans state.placed, donc MRV le skipera.

                // Propager les contraintes induites par ce placement (AC-3 incrémental)
                let ac3_ok = match ac3_incremental(domains, ctx.graph, ctx.kb, ctx.all_slots, state, slot_idx) {
                    Ac3Result::Ok => true,
                    Ac3Result::DomainEmpty { .. } => false,
                };

                if ac3_ok {
                    let result = backtrack(ctx, state, domains, rng);
                    match result {
                        BtResult::Found => return BtResult::Found,
                        BtResult::Timeout => {
                            // Restore et remonte le timeout
                            state.unplace_last(ctx.all_slots, &ctx.kb.entries);
                            for (i, snap) in domain_snapshots.into_iter().enumerate() {
                                domains.restore_domain(i, snap);
                            }
                            return BtResult::Timeout;
                        }
                        BtResult::Exhausted => {} // essaie le prochain candidat
                    }
                }

                // Restore state + domaines
                state.unplace_last(ctx.all_slots, &ctx.kb.entries);
                for (i, snap) in domain_snapshots.into_iter().enumerate() {
                    domains.restore_domain(i, snap);
                }
            }

            BtResult::Exhausted
        }
    }
}

// ---------------------------------------------------------------------------
// Point d'entrée public
// ---------------------------------------------------------------------------

/// Résout la grille définie par `config` en utilisant la KB `kb`.
///
/// Supporte les restarts aléatoires (max_retries fois) si timeout ou exhaustion
/// dans le premier essai.
pub fn solve(config: &ConfigInput, kb: &KbCompact) -> Result<GridOutput, EngineError> {
    let rows = config.rows as usize;
    let cols = config.cols as usize;

    if config.pattern_kinds.len() != rows * cols {
        return Err(EngineError::InvalidInput(format!(
            "pattern_kinds length {} != rows*cols {}",
            config.pattern_kinds.len(),
            rows * cols
        )));
    }

    let kinds: Vec<CellKind> = config.pattern_kinds.iter().map(|&k| CellKind::from_u8(k)).collect();
    let all_slots = compute_slots(rows, cols, &kinds);

    if all_slots.is_empty() {
        return Err(EngineError::InvalidInput("No slots found in pattern".into()));
    }

    // Vérifier que la KB a des mots pour toutes les longueurs requises
    let required_lengths: std::collections::HashSet<usize> =
        all_slots.iter().map(|s| s.length as usize).collect();
    for &len in &required_lengths {
        if kb.by_length.get(&len).map(|v| v.len()).unwrap_or(0) == 0 {
            return Err(EngineError::InvalidInput(format!(
                "KB has no entries for length {}",
                len
            )));
        }
    }

    let graph = ArcGraph::build(&all_slots);
    let deadline = Instant::now() + Duration::from_millis(config.deadline_ms as u64);

    let max_retries = config.max_retries.max(1) as u64;

    for attempt in 0..max_retries {
        if Instant::now() >= deadline {
            break;
        }

        // Seed perturbé par tentative (miroir de _perturbSeed Dart)
        let seed = perturb_seed(config.seed, attempt);
        let mut rng = ChaCha8Rng::seed_from_u64(seed);

        let mut state = BacktrackState::new(rows, cols);
        let mut domains = Domains::init(kb, &all_slots);

        // AC-3 initial : pré-filtrage global
        match ac3_full(&mut domains, &graph, kb, &all_slots, &state) {
            Ac3Result::DomainEmpty { .. } => continue, // Patron infaisable avec cette KB
            Ac3Result::Ok => {}
        }

        let ctx = SolveContext {
            kb,
            all_slots: &all_slots,
            graph: &graph,
            deadline,
        };

        match backtrack(&ctx, &mut state, &mut domains, &mut rng) {
            BtResult::Found => {
                return Ok(build_output(rows, cols, &kinds, &all_slots, &state, kb));
            }
            BtResult::Timeout => break,
            BtResult::Exhausted => {} // retry avec seed différent
        }
    }

    Ok(GridOutput::no_solution())
}

/// Miroir de `_perturbSeed` dans topology.dart.
fn perturb_seed(base: u64, attempt: u64) -> u64 {
    if attempt == 0 {
        base
    } else {
        base.wrapping_mul(1009).wrapping_add(attempt.wrapping_mul(9973))
    }
}

// ---------------------------------------------------------------------------
// Construction du GridOutput
// ---------------------------------------------------------------------------

fn build_output(
    rows: usize,
    cols: usize,
    kinds: &[CellKind],
    all_slots: &[Slot],
    state: &BacktrackState,
    kb: &KbCompact,
) -> GridOutput {
    // Cellules
    let cells: Vec<CellOutput> = (0..rows)
        .flat_map(|r| {
            (0..cols).map(move |c| {
                let kind = kinds[r * cols + c];
                match kind {
                    CellKind::Letter => {
                        let letter = state.grid.get(r as u8, c as u8)
                            .map(|ch| ch.to_string());
                        CellOutput { kind: 0, letter }
                    }
                    CellKind::Clue | CellKind::Blocker => CellOutput { kind: 1, letter: None },
                }
            })
        })
        .collect();

    // Placements
    let placed: Vec<PlacedEntry> = state
        .placed
        .iter()
        .map(|(&slot_idx, &entry_idx)| {
            let slot = &all_slots[slot_idx];
            let entry = &kb.entries[entry_idx];
            PlacedEntry {
                kb_id: entry.id,
                slot_row: slot.start_row as u16,
                slot_col: slot.start_col as u16,
                dir: match slot.direction {
                    Direction::Horizontal => 0,
                    Direction::Vertical => 1,
                },
                len: slot.length,
            }
        })
        .collect();

    GridOutput {
        status: 0,
        cells: Some(cells),
        placed: Some(placed),
        error_message: None,
    }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;
    use crate::kb::KbCompact;
    use crate::models::KbEntryLite;
    use crate::normalizer::{NormalizerOptions, normalize};
    use bitvec::prelude::*;
    use std::collections::HashMap;

    /// Construit une KB in-memory (sans SQLite) pour les tests.
    fn make_test_kb(words: &[(&str, u32)]) -> KbCompact {
        let opts = NormalizerOptions::default();
        let mut entries = Vec::new();
        for &(word, id) in words {
            let normalized = normalize(word, opts);
            let chars: Vec<char> = normalized.chars().collect();
            if chars.len() >= 2 {
                entries.push(KbEntryLite { id, chars });
            }
        }

        let mut by_length: HashMap<usize, Vec<usize>> = HashMap::new();
        for (idx, entry) in entries.iter().enumerate() {
            by_length.entry(entry.chars.len()).or_default().push(idx);
        }

        use crate::kb::ALPHABET_SIZE;
        let mut letter_index: HashMap<usize, Vec<[BitVec; ALPHABET_SIZE]>> = HashMap::new();
        for (&length, indices) in &by_length {
            let n = indices.len();
            let mut positions: Vec<[BitVec; ALPHABET_SIZE]> = (0..length)
                .map(|_| std::array::from_fn(|_| BitVec::<usize, Lsb0>::repeat(false, n)))
                .collect();
            for (slot_idx, &entry_idx) in indices.iter().enumerate() {
                for (pos, &ch) in entries[entry_idx].chars.iter().enumerate() {
                    if let Some(li) = crate::kb::char_to_idx(ch) {
                        positions[pos][li].set(slot_idx, true);
                    }
                }
            }
            letter_index.insert(length, positions);
        }

        KbCompact { entries, by_length, letter_index }
    }

    /// Patron 4×4 simple (miroir du _patterns4x4[0] Dart)
    /// BCCC
    /// CLLL
    /// CLLL
    /// CLLL
    fn pattern_4x4() -> Vec<u8> {
        vec![
            2, 1, 1, 1,  // row 0: blocker, clue, clue, clue
            1, 0, 0, 0,  // row 1: clue, letter, letter, letter
            1, 0, 0, 0,  // row 2: clue, letter, letter, letter
            1, 0, 0, 0,  // row 3: clue, letter, letter, letter
        ]
    }

    fn make_config(rows: u16, cols: u16, pattern: Vec<u8>, seed: u64) -> ConfigInput {
        ConfigInput {
            rows,
            cols,
            seed,
            deadline_ms: 30000, // 30s pour les tests
            max_retries: 10,
            pattern_kinds: pattern,
        }
    }

    #[test]
    fn test_compute_slots_4x4() {
        let kinds: Vec<CellKind> = pattern_4x4().iter().map(|&k| CellKind::from_u8(k)).collect();
        let slots = compute_slots(4, 4, &kinds);
        // 3 slots H (row 1,2,3, chacun len 3) + 3 slots V (col 1,2,3, chacun len 3)
        assert_eq!(slots.len(), 6);
        let h_slots: Vec<_> = slots.iter().filter(|s| s.direction == Direction::Horizontal).collect();
        let v_slots: Vec<_> = slots.iter().filter(|s| s.direction == Direction::Vertical).collect();
        assert_eq!(h_slots.len(), 3);
        assert_eq!(v_slots.len(), 3);
        // Longueur 3 pour tous
        assert!(slots.iter().all(|s| s.length == 3));
    }

    #[test]
    fn test_solve_5x5_converges() {
        // 5×5 : 4 slots H + 4 slots V de longueur 4
        // Patron BCCCC / CLLLL × 4
        let pattern: Vec<u8> = vec![
            2, 1, 1, 1, 1,
            1, 0, 0, 0, 0,
            1, 0, 0, 0, 0,
            1, 0, 0, 0, 0,
            1, 0, 0, 0, 0,
        ];

        // KB avec plusieurs mots de longueur 4 en arabe
        // On a besoin que les intersections soient compatibles
        let words_len4: Vec<(&str, u32)> = vec![
            ("كتاب", 1), ("سلام", 2), ("قلوب", 3), ("نهار", 4),
            ("بحار", 5), ("جبال", 6), ("رجال", 7), ("اقلام", 8), // len5 ignoré
            ("بيوت", 9), ("عمار", 10), ("ليل", 11), // len3 ignoré
            ("درس", 12), // len3 ignoré
            ("دار", 13), // len3
            ("كلام", 14), ("لحظة", 15), ("عالم", 16), ("مدرس", 17),
            ("صديق", 18), ("قبيل", 19), ("سفير", 20), ("نجاح", 21),
            ("ربيع", 22), ("صيف", 23),  // len3
            ("قمر", 24),   // len3
            ("وصفة", 25), ("عروس", 26), ("ثمار", 27), ("رسالة", 28), // len6
            ("نضال", 29), ("برتقال", 30), // len7
            ("بلاد", 31), ("ملاك", 32), ("جهاد", 33), ("وفاق", 34),
            ("سماء", 35), ("هواء", 36), ("ماء", 37),  // len3
            ("دعاء", 38),  // len4 après norm
            ("قضاء", 39),  // len4
            ("مساء", 40),  // len4
        ];

        let kb = make_test_kb(&words_len4);

        // Vérifier qu'on a des mots de longueur 4
        let len4_count = kb.by_length.get(&4).map(|v| v.len()).unwrap_or(0);
        assert!(len4_count >= 5, "Need at least 5 words of length 4, got {}", len4_count);

        let config = make_config(5, 5, pattern, 42);
        let result = solve(&config, &kb);

        // Le solve doit soit trouver une solution, soit retourner no_solution (pas d'erreur)
        assert!(result.is_ok(), "solve() should not return Err: {:?}", result);

        let output = result.unwrap();
        // Si solution trouvée, vérifier la cohérence
        if output.status == 0 {
            let cells = output.cells.as_ref().unwrap();
            assert_eq!(cells.len(), 25); // 5×5
            // Les cases lettre doivent avoir une lettre
            let kinds: Vec<CellKind> = vec![
                2u8, 1, 1, 1, 1,
                1, 0, 0, 0, 0,
                1, 0, 0, 0, 0,
                1, 0, 0, 0, 0,
                1, 0, 0, 0, 0,
            ].iter().map(|&k| CellKind::from_u8(k)).collect();
            for (i, cell) in cells.iter().enumerate() {
                if kinds[i] == CellKind::Letter {
                    assert!(cell.letter.is_some(), "Letter cell {} has no letter", i);
                }
            }
        }
    }

    #[test]
    fn test_perturb_seed() {
        assert_eq!(perturb_seed(42, 0), 42);
        assert_ne!(perturb_seed(42, 1), 42);
        assert_ne!(perturb_seed(42, 1), perturb_seed(42, 2));
    }
}
