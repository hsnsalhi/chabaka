/// AC-3 — Arc Consistency Algorithm 3.
///
/// Propage les contraintes entre slots qui partagent des cases (intersections).
/// Réduit les domaines avant et pendant le backtracking (forward-checking
/// amélioré : propagation au-delà de profondeur 1).
///
/// Implémentation :
///   - File d'arcs (slot_i, slot_j, pos_in_i, pos_in_j) précalculée à l'init.
///   - Lors d'un placement, on réinsère les arcs pointant vers le slot placé.
///   - Propagation itérative jusqu'à convergence ou domaine vide.
///
/// Complexité : O(arcs × |domain| × letters) — en pratique rapide car les
/// bitsets permettent l'AND en un seul passage.

use std::collections::VecDeque;

use crate::kb::KbCompact;
use crate::models::Slot;
use crate::solver::domain::Domains;
use crate::solver::state::BacktrackState;

/// Un arc entre deux slots partageant une case.
#[derive(Debug, Clone, Copy)]
pub struct Arc {
    /// Slot source (son domaine sera propagé vers target).
    pub source: usize,
    /// Slot cible (son domaine sera restreint).
    pub target: usize,
    /// Position dans le mot source correspondant à la case partagée.
    pub pos_in_source: u8,
    /// Position dans le mot cible correspondant à la case partagée.
    pub pos_in_target: u8,
}

/// Toutes les intersections entre slots.
pub struct ArcGraph {
    /// Tous les arcs (bidirectionnels : (i→j) et (j→i) sont tous deux présents).
    pub arcs: Vec<Arc>,
    /// Pour chaque slot, les indices des arcs qui ont ce slot comme `target`.
    /// Utilisé pour re-propager quand un slot est modifié.
    pub arcs_into: Vec<Vec<usize>>,
}

impl ArcGraph {
    /// Construit le graphe d'arcs depuis la liste de slots et le patron de grille.
    ///
    /// Deux slots partagent une case si leurs positions se chevauchent.
    pub fn build(all_slots: &[Slot]) -> Self {
        let n = all_slots.len();
        let mut arcs = Vec::new();
        let mut arcs_into = vec![Vec::new(); n];

        for i in 0..n {
            let positions_i = all_slots[i].positions();
            for j in (i + 1)..n {
                // Slots orthogonaux peuvent partager une case
                if all_slots[i].direction == all_slots[j].direction {
                    continue; // Mêmes directions ne se croisent pas (dans notre modèle)
                }
                let positions_j = all_slots[j].positions();
                // Cherche une case commune
                for (pi, &(ri, ci)) in positions_i.iter().enumerate() {
                    for (pj, &(rj, cj)) in positions_j.iter().enumerate() {
                        if ri == rj && ci == cj {
                            // Arc i → j
                            let arc_ij = Arc {
                                source: i,
                                target: j,
                                pos_in_source: pi as u8,
                                pos_in_target: pj as u8,
                            };
                            let idx_ij = arcs.len();
                            arcs.push(arc_ij);
                            arcs_into[j].push(idx_ij);

                            // Arc j → i
                            let arc_ji = Arc {
                                source: j,
                                target: i,
                                pos_in_source: pj as u8,
                                pos_in_target: pi as u8,
                            };
                            let idx_ji = arcs.len();
                            arcs.push(arc_ji);
                            arcs_into[i].push(idx_ji);

                            break; // Un seul croisement par paire de slots
                        }
                    }
                }
            }
        }

        ArcGraph { arcs, arcs_into }
    }
}

/// Résultat d'une propagation AC-3.
pub enum Ac3Result {
    /// Propagation réussie, domaines mis à jour.
    Ok,
    /// Un domaine est devenu vide → backtrack requis.
    DomainEmpty { slot_idx: usize },
}

/// Lance AC-3 complet depuis une file initiale de tous les arcs.
/// Utilisé à l'init pour le pré-filtrage initial.
pub fn ac3_full(
    domains: &mut Domains,
    graph: &ArcGraph,
    kb: &KbCompact,
    all_slots: &[Slot],
    state: &BacktrackState,
) -> Ac3Result {
    let mut queue: VecDeque<usize> = (0..graph.arcs.len()).collect();
    propagate(domains, graph, kb, all_slots, state, &mut queue)
}

/// Lance AC-3 incrémental après le placement d'un slot.
/// Réinsère seulement les arcs pointant vers `placed_slot_idx`.
pub fn ac3_incremental(
    domains: &mut Domains,
    graph: &ArcGraph,
    kb: &KbCompact,
    all_slots: &[Slot],
    state: &BacktrackState,
    placed_slot_idx: usize,
) -> Ac3Result {
    // Les arcs entrants dans le slot placé propagent vers ses voisins
    let _arc_indices: Vec<usize> = graph.arcs_into[placed_slot_idx].clone();
    // On propage les arcs partant DU slot placé (source = placed_slot_idx)
    // car ses candidats ont été réduits à 1 (le mot placé).
    // Mais aussi les arcs entrant dans les voisins du slot placé.
    let mut queue: VecDeque<usize> = VecDeque::new();

    // Trouver les arcs dont la source est placed_slot_idx
    for (arc_idx, arc) in graph.arcs.iter().enumerate() {
        if arc.source == placed_slot_idx {
            queue.push_back(arc_idx);
        }
    }

    propagate(domains, graph, kb, all_slots, state, &mut queue)
}

/// Coeur de l'algorithme AC-3.
fn propagate(
    domains: &mut Domains,
    graph: &ArcGraph,
    kb: &KbCompact,
    all_slots: &[Slot],
    state: &BacktrackState,
    queue: &mut VecDeque<usize>,
) -> Ac3Result {
    while let Some(arc_idx) = queue.pop_front() {
        let arc = graph.arcs[arc_idx];
        let source = arc.source;
        let target = arc.target;

        if state.is_placed(target) {
            continue; // Le slot cible est déjà placé — domaine figé
        }

        // Calculer les lettres valides à pos_in_target imposées par source
        // = union des lettres[pos_in_source] de tous les candidats actifs de source
        let source_letters = collect_letters_at_pos(domains, kb, all_slots, source, arc.pos_in_source);

        if source_letters.is_empty() {
            // Source a un domaine vide → dead end (ne devrait pas arriver si AC-3 correct)
            continue;
        }

        // Pour target, garder seulement les candidats dont lettre[pos_in_target] ∈ source_letters
        let changed = restrict_domain_by_letters(
            domains,
            kb,
            all_slots,
            target,
            arc.pos_in_target as usize,
            &source_letters,
        );

        if domains.slots[target].is_empty() {
            return Ac3Result::DomainEmpty { slot_idx: target };
        }

        if changed {
            // Le domaine de target a changé → re-propager ses arcs sortants
            for &arc_out_idx in &graph.arcs_into[target] {
                // arcs_into[target] = arcs avec target comme cible
                // On veut les arcs avec target comme SOURCE
                // → utiliser les arcs sortants
                queue.push_back(arc_out_idx);
            }
            // Trouver les arcs sortants de target
            for (ai, arc_a) in graph.arcs.iter().enumerate() {
                if arc_a.source == target && !queue.contains(&ai) {
                    queue.push_back(ai);
                }
            }
        }
    }

    Ac3Result::Ok
}

/// Collecte l'ensemble des chars présents à la position `pos` parmi tous les
/// candidats actifs du slot `slot_idx`.
fn collect_letters_at_pos(
    domains: &Domains,
    kb: &KbCompact,
    all_slots: &[Slot],
    slot_idx: usize,
    pos: u8,
) -> Vec<char> {
    let length = all_slots[slot_idx].length as usize;
    let indices = match kb.by_length.get(&length) {
        Some(v) => v,
        None => return vec![],
    };

    let active = &domains.slots[slot_idx];
    let mut letters = std::collections::HashSet::new();

    for (si, &entry_idx) in indices.iter().enumerate() {
        if si < active.bits.len() && active.bits[si] {
            let chars = &kb.entries[entry_idx].chars;
            if (pos as usize) < chars.len() {
                letters.insert(chars[pos as usize]);
            }
        }
    }

    letters.into_iter().collect()
}

/// Restreint le domaine de `target_slot_idx` en ne gardant que les candidats
/// dont la lettre à `pos` appartient à `valid_letters`.
/// Retourne true si le domaine a changé.
fn restrict_domain_by_letters(
    domains: &mut Domains,
    kb: &KbCompact,
    all_slots: &[Slot],
    target_slot_idx: usize,
    pos: usize,
    valid_letters: &[char],
) -> bool {
    let length = all_slots[target_slot_idx].length as usize;
    let indices = match kb.by_length.get(&length) {
        Some(v) => v,
        None => return false,
    };

    let valid_set: std::collections::HashSet<char> = valid_letters.iter().copied().collect();
    let mut changed = false;

    let n = indices.len();
    for si in 0..n {
        if si >= domains.slots[target_slot_idx].bits.len() {
            break;
        }
        if !domains.slots[target_slot_idx].bits[si] {
            continue; // déjà éliminé
        }
        let entry_idx = indices[si];
        let chars = &kb.entries[entry_idx].chars;
        let letter_ok = pos < chars.len() && valid_set.contains(&chars[pos]);
        if !letter_ok {
            domains.slots[target_slot_idx].bits.set(si, false);
            domains.slots[target_slot_idx].count = domains.slots[target_slot_idx].count.saturating_sub(1);
            changed = true;
        }
    }

    changed
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;
    use crate::models::Direction;

    fn h_slot(row: u8, col: u8, len: u8) -> Slot {
        Slot { direction: Direction::Horizontal, start_row: row, start_col: col, length: len }
    }

    fn v_slot(row: u8, col: u8, len: u8) -> Slot {
        Slot { direction: Direction::Vertical, start_row: row, start_col: col, length: len }
    }

    #[test]
    fn test_arc_build_crossing() {
        // H(0,0,3) et V(0,1,3) se croisent en (0,1)
        let slots = vec![h_slot(0, 0, 3), v_slot(0, 1, 3)];
        let graph = ArcGraph::build(&slots);
        // Il doit y avoir 2 arcs : 0→1 et 1→0
        assert_eq!(graph.arcs.len(), 2);
        let arc_01 = &graph.arcs[0];
        assert_eq!(arc_01.source, 0);
        assert_eq!(arc_01.target, 1);
        assert_eq!(arc_01.pos_in_source, 1); // col 1 = position 1 dans H(0,0,3)
        assert_eq!(arc_01.pos_in_target, 0); // row 0 = position 0 dans V(0,1,3)
    }

    #[test]
    fn test_arc_build_no_crossing() {
        // H(0,0,3) et H(1,0,3) : même direction, pas de croisement
        let slots = vec![h_slot(0, 0, 3), h_slot(1, 0, 3)];
        let graph = ArcGraph::build(&slots);
        assert_eq!(graph.arcs.len(), 0);
    }

    #[test]
    fn test_arc_build_vertical_only() {
        // V(0,0,3) et V(0,2,3) : même direction, pas de croisement
        let slots = vec![v_slot(0, 0, 3), v_slot(0, 2, 3)];
        let graph = ArcGraph::build(&slots);
        assert_eq!(graph.arcs.len(), 0);
    }
}
