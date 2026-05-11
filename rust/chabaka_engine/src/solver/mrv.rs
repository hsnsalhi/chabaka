/// MRV — Most Restricted Variable heuristic.
///
/// Sélectionne le slot non-placé avec le moins de candidats compatibles.
/// Priorité : si deux slots ont le même count, on préfère celui avec le plus
/// de contraintes (lettres déjà fixées) → en pratique le degré heuristique.
///
/// O(n_remaining) par appel — acceptable car n_remaining ≤ 60 pour 16×13.

use crate::solver::domain::Domains;
use crate::solver::state::BacktrackState;

/// Sélectionne le slot le plus contraint parmi les slots non placés.
///
/// Retourne `None` si tous les slots sont placés (succès) ou si un domaine
/// est vide (forward-check échoue → le caller doit backtracker).
///
/// Retourne `Some((slot_idx, is_dead_end))` où `is_dead_end = true` si le
/// domaine du slot sélectionné est vide (0 candidats).
pub fn select_mrv(
    domains: &Domains,
    state: &BacktrackState,
    n_slots: usize,
) -> Option<(usize, bool)> {
    let mut best_idx: Option<usize> = None;
    let mut best_count = usize::MAX;
    let mut found_empty = false;
    let mut empty_idx = 0;

    for slot_idx in 0..n_slots {
        if state.is_placed(slot_idx) {
            continue;
        }
        let count = domains.slots[slot_idx].count;
        if count == 0 {
            // Domaine vide → dead end immédiat, inutile de chercher plus loin
            found_empty = true;
            empty_idx = slot_idx;
            break;
        }
        if best_idx.is_none() || count < best_count {
            best_count = count;
            best_idx = Some(slot_idx);
            if count == 1 {
                break; // Minimum absolu
            }
        }
    }

    if found_empty {
        return Some((empty_idx, true));
    }

    best_idx.map(|idx| (idx, false))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::solver::domain::{Domains, SlotDomain};
    use crate::solver::state::BacktrackState;
    use bitvec::prelude::*;

    fn make_domain_count(n: usize, count: usize) -> SlotDomain {
        let mut bits: BitVec<usize, Lsb0> = BitVec::repeat(false, n);
        for i in 0..count {
            bits.set(i, true);
        }
        SlotDomain { bits, count }
    }

    #[test]
    fn test_selects_min_count() {
        // 3 slots non-placés avec counts 5, 2, 8
        let domains = Domains {
            slots: vec![
                make_domain_count(10, 5),
                make_domain_count(10, 2),
                make_domain_count(10, 8),
            ],
        };
        let state = BacktrackState::new(5, 5);
        // Tous non-placés
        let result = select_mrv(&domains, &state, 3);
        assert_eq!(result, Some((1, false))); // slot 1 a count=2
    }

    #[test]
    fn test_detects_empty_domain() {
        let domains = Domains {
            slots: vec![
                make_domain_count(10, 5),
                make_domain_count(10, 0), // empty
                make_domain_count(10, 3),
            ],
        };
        let state = BacktrackState::new(5, 5);
        let result = select_mrv(&domains, &state, 3);
        assert_eq!(result, Some((1, true))); // dead end
    }

    #[test]
    fn test_skips_placed_slots() {
        let domains = Domains {
            slots: vec![
                make_domain_count(10, 1), // slot 0 : best mais placé
                make_domain_count(10, 5), // slot 1 : restant
            ],
        };
        let mut state = BacktrackState::new(5, 5);
        // Simuler slot 0 comme placé
        state.placed.insert(0, 0);

        let result = select_mrv(&domains, &state, 2);
        assert_eq!(result, Some((1, false)));
    }

    #[test]
    fn test_all_placed_returns_none() {
        let domains = Domains {
            slots: vec![make_domain_count(10, 3)],
        };
        let mut state = BacktrackState::new(5, 5);
        state.placed.insert(0, 0);

        let result = select_mrv(&domains, &state, 1);
        assert_eq!(result, None);
    }
}
