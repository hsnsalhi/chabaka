/// Domaines de candidats par slot — représentés en bitset.
///
/// Clé perf (spec §4.1) : chaque slot a un domaine = BitVec de taille
/// `by_length[length].len()` (au plus 4843 bits ≈ 76 u64 = 608 octets/slot).
/// AC-3 travaille sur ces bitsets par AND sans realloc.

use bitvec::prelude::*;

use crate::kb::KbCompact;
use crate::models::{LetterConstraint, Slot};

/// Domaine d'un slot : indices dans `kb.by_length[length]` (slots-indices, pas entry_idx).
/// Un bit à 1 = ce candidat est encore possible.
pub struct SlotDomain {
    /// Bitset sur les slot-indices (position dans `kb.by_length[length]`).
    pub bits: BitVec<usize, Lsb0>,
    /// Taille de la population active (cache pour éviter bits.count_ones() à chaque fois).
    pub count: usize,
}

impl SlotDomain {
    /// Crée un domaine initial avec tous les candidats actifs pour cette longueur.
    pub fn full(kb: &KbCompact, length: usize) -> Self {
        let n = kb.by_length.get(&length).map(|v| v.len()).unwrap_or(0);
        let bits = BitVec::repeat(true, n);
        SlotDomain { bits, count: n }
    }

    /// Crée un domaine vide.
    pub fn empty(n: usize) -> Self {
        SlotDomain {
            bits: BitVec::repeat(false, n),
            count: 0,
        }
    }

    pub fn is_empty(&self) -> bool {
        self.count == 0
    }

    /// Recompute count (à appeler après modification directe de `bits`).
    pub fn recount(&mut self) {
        self.count = self.bits.count_ones();
    }

    /// Restreint le domaine en AND avec le bitset d'une contrainte lettre.
    /// Retourne `false` si le domaine devient vide (déclencheur de backtrack).
    pub fn intersect_with(&mut self, other: &BitVec<usize, Lsb0>) -> bool {
        // Taille : other peut être plus courte si généré depuis un kb partiel
        let min_len = self.bits.len().min(other.len());
        for i in 0..min_len {
            if self.bits[i] && !other[i] {
                self.bits.set(i, false);
            }
        }
        // Bits au-delà de `other` → zéro (aucune info → conservatif : keep)
        // En pratique les tailles sont égales (même kb.by_length[length].len()).
        self.recount();
        self.count > 0
    }

    /// Retire un seul slot-index du domaine (après exclusion d'un mot placé).
    pub fn remove_slot_idx(&mut self, slot_idx: usize) {
        if slot_idx < self.bits.len() && self.bits[slot_idx] {
            self.bits.set(slot_idx, false);
            self.count = self.count.saturating_sub(1);
        }
    }

    /// Collecte les slot-indices actifs.
    pub fn active_indices(&self) -> Vec<usize> {
        self.bits
            .iter()
            .enumerate()
            .filter_map(|(i, bit)| if *bit { Some(i) } else { None })
            .collect()
    }
}

/// Tous les domaines de la grille, indexés par numéro de slot.
pub struct Domains {
    /// domains[slot_idx] = domaine de ce slot.
    pub slots: Vec<SlotDomain>,
}

impl Domains {
    /// Initialise tous les domaines depuis la KB.
    /// Applique les contraintes lettre initiales (cases déjà fixées, si applicable).
    pub fn init(kb: &KbCompact, all_slots: &[Slot]) -> Self {
        let domains = all_slots
            .iter()
            .map(|slot| {
                let length = slot.length as usize;
                SlotDomain::full(kb, length)
            })
            .collect();
        Domains { slots: domains }
    }

    /// Applique une contrainte lettre au domaine d'un slot.
    /// Retourne false si le domaine devient vide.
    pub fn apply_letter_constraint(
        &mut self,
        slot_idx: usize,
        constraint: &LetterConstraint,
        kb: &KbCompact,
        all_slots: &[Slot],
    ) -> bool {
        let length = all_slots[slot_idx].length as usize;
        let position = constraint.position;

        let letter_bitset = kb
            .letter_index
            .get(&length)
            .and_then(|positions| {
                use crate::kb::char_to_idx;
                char_to_idx(constraint.letter).map(|li| &positions[position][li])
            });

        match letter_bitset {
            Some(bitset) => self.slots[slot_idx].intersect_with(bitset),
            None => {
                // Lettre inconnue ou position hors bornes → domaine vide
                self.slots[slot_idx].count = 0;
                false
            }
        }
    }

    /// Clone le domaine d'un slot (pour le undo stack).
    pub fn snapshot_domain(&self, slot_idx: usize) -> SlotDomain {
        let d = &self.slots[slot_idx];
        SlotDomain {
            bits: d.bits.clone(),
            count: d.count,
        }
    }

    /// Restore le domaine d'un slot depuis un snapshot.
    pub fn restore_domain(&mut self, slot_idx: usize, snapshot: SlotDomain) {
        self.slots[slot_idx] = snapshot;
    }
}

// ---------------------------------------------------------------------------
// char_to_idx est pub dans kb.rs — importé directement
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    fn make_domain(n: usize) -> SlotDomain {
        SlotDomain::full_from_count(n)
    }

    impl SlotDomain {
        fn full_from_count(n: usize) -> Self {
            SlotDomain {
                bits: BitVec::repeat(true, n),
                count: n,
            }
        }
    }

    #[test]
    fn test_domain_full() {
        let d = make_domain(5);
        assert_eq!(d.count, 5);
        assert!(!d.is_empty());
    }

    #[test]
    fn test_domain_intersect() {
        let mut d = make_domain(4);
        // Garder uniquement les indices 1 et 3
        let mask: BitVec<usize, Lsb0> = bitvec![usize, Lsb0; 0, 1, 0, 1];
        d.intersect_with(&mask);
        assert_eq!(d.count, 2);
        let active = d.active_indices();
        assert_eq!(active, vec![1, 3]);
    }

    #[test]
    fn test_domain_remove() {
        let mut d = make_domain(3);
        d.remove_slot_idx(1);
        assert_eq!(d.count, 2);
        let active = d.active_indices();
        assert!(!active.contains(&1));
    }

    #[test]
    fn test_domain_empty() {
        let d = SlotDomain::empty(5);
        assert!(d.is_empty());
    }
}
