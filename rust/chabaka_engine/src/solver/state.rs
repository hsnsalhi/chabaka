/// État du backtracking : grille de lettres + map slot→entry placée + undo stack.
///
/// Miroir de `_BacktrackState` dans topology.dart, mais optimisé :
///   - lettres stockées comme Option<char> (pas de String)
///   - undo stack explicite au lieu de récursion pure (itératif possible)
///   - positions partagées calculées à l'init (pas à chaque unplace)

use std::collections::HashMap;

use crate::models::{KbEntryLite, LetterConstraint, Slot};

// ---------------------------------------------------------------------------
// Grille de lettres
// ---------------------------------------------------------------------------

pub struct LetterGrid {
    pub rows: usize,
    pub cols: usize,
    cells: Vec<Option<char>>, // row-major, None = case vide
    /// Pour chaque case, combien de slots ont placé une lettre ici
    /// (nécessaire pour l'unplace correct).
    ref_count: Vec<u8>,
}

impl LetterGrid {
    pub fn new(rows: usize, cols: usize) -> Self {
        let n = rows * cols;
        LetterGrid {
            rows,
            cols,
            cells: vec![None; n],
            ref_count: vec![0; n],
        }
    }

    #[inline]
    fn idx(&self, row: u8, col: u8) -> usize {
        row as usize * self.cols + col as usize
    }

    pub fn get(&self, row: u8, col: u8) -> Option<char> {
        self.cells[self.idx(row, col)]
    }

    pub fn set(&mut self, row: u8, col: u8, ch: char) {
        let i = self.idx(row, col);
        self.cells[i] = Some(ch);
        self.ref_count[i] += 1;
    }

    /// Retire un slot de la case. La lettre n'est supprimée que si plus aucun
    /// autre slot placé ne l'occupe (ref_count tombe à 0).
    pub fn unset(&mut self, row: u8, col: u8) {
        let i = self.idx(row, col);
        if self.ref_count[i] > 0 {
            self.ref_count[i] -= 1;
        }
        if self.ref_count[i] == 0 {
            self.cells[i] = None;
        }
    }
}

// ---------------------------------------------------------------------------
// État backtracking
// ---------------------------------------------------------------------------

/// Un "placement" : slot_idx + entry_idx placés ensemble.
#[derive(Clone)]
pub struct Placement {
    pub slot_idx: usize,
    pub entry_idx: usize, // index dans kb.entries
}

pub struct BacktrackState {
    pub grid: LetterGrid,
    /// slot_idx → entry_idx placé dans ce slot.
    pub placed: HashMap<usize, usize>,
    /// Ensemble des kb_id déjà placés (pour éviter les doublons).
    pub placed_ids: std::collections::HashSet<u32>,
    /// Undo stack : liste des placements effectués dans l'ordre.
    /// (utilisé pour restaurer l'état lors du backtrack)
    undo_stack: Vec<Placement>,
}

impl BacktrackState {
    pub fn new(rows: usize, cols: usize) -> Self {
        BacktrackState {
            grid: LetterGrid::new(rows, cols),
            placed: HashMap::new(),
            placed_ids: std::collections::HashSet::new(),
            undo_stack: Vec::new(),
        }
    }

    /// Place un mot dans la grille.
    /// Précondition : le slot n'est pas encore occupé.
    pub fn place(
        &mut self,
        slot_idx: usize,
        entry_idx: usize,
        slot: &Slot,
        entry: &KbEntryLite,
    ) {
        for (i, &(row, col)) in slot.positions().iter().enumerate() {
            self.grid.set(row, col, entry.chars[i]);
        }
        self.placed.insert(slot_idx, entry_idx);
        self.placed_ids.insert(entry.id);
        self.undo_stack.push(Placement { slot_idx, entry_idx });
    }

    /// Retire le dernier placement (backtrack d'un niveau).
    pub fn unplace_last(&mut self, all_slots: &[Slot], kb_entries: &[KbEntryLite]) {
        if let Some(p) = self.undo_stack.pop() {
            let slot = &all_slots[p.slot_idx];
            let entry = &kb_entries[p.entry_idx];
            for &(row, col) in &slot.positions() {
                self.grid.unset(row, col);
            }
            self.placed.remove(&p.slot_idx);
            self.placed_ids.remove(&entry.id);
        }
    }

    /// Contraintes sur un slot non encore placé (lettres déjà fixées par d'autres slots).
    pub fn constraints_for(&self, slot: &Slot) -> Vec<LetterConstraint> {
        let mut result = Vec::new();
        for (i, &(row, col)) in slot.positions().iter().enumerate() {
            if let Some(ch) = self.grid.get(row, col) {
                result.push(LetterConstraint { position: i, letter: ch });
            }
        }
        result
    }

    /// Ids déjà placés (pour exclusion dans find_matching).
    pub fn excluded_ids(&self) -> Vec<u32> {
        self.placed_ids.iter().copied().collect()
    }

    pub fn is_placed(&self, slot_idx: usize) -> bool {
        self.placed.contains_key(&slot_idx)
    }

    pub fn placement_count(&self) -> usize {
        self.placed.len()
    }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;
    use crate::models::{Direction, Slot, KbEntryLite};

    fn make_slot(dir: Direction, row: u8, col: u8, len: u8) -> Slot {
        Slot { direction: dir, start_row: row, start_col: col, length: len }
    }

    fn make_entry(id: u32, word: &str) -> KbEntryLite {
        KbEntryLite { id, chars: word.chars().collect() }
    }

    #[test]
    fn test_place_and_constraints() {
        let mut state = BacktrackState::new(4, 4);
        let slot_h = make_slot(Direction::Horizontal, 1, 1, 3); // (1,1)(1,2)(1,3)
        let entry = make_entry(1, "كتب"); // ك ت ب
        let _slots = vec![slot_h.clone()];
        let _entries = vec![entry.clone()];

        state.place(0, 0, &slot_h, &entry);

        // La grille doit avoir les lettres aux bonnes positions
        assert_eq!(state.grid.get(1, 1), Some('ك'));
        assert_eq!(state.grid.get(1, 2), Some('ت'));
        assert_eq!(state.grid.get(1, 3), Some('ب'));

        // Un slot vertical croisant en (1,2) doit avoir contrainte ت à position 0
        let slot_v = make_slot(Direction::Vertical, 1, 2, 3); // (1,2)(2,2)(3,2)
        let constraints = state.constraints_for(&slot_v);
        assert_eq!(constraints.len(), 1);
        assert_eq!(constraints[0].position, 0);
        assert_eq!(constraints[0].letter, 'ت');
    }

    #[test]
    fn test_place_and_unplace() {
        let mut state = BacktrackState::new(4, 4);
        let slot = make_slot(Direction::Horizontal, 1, 1, 3);
        let entry = make_entry(1, "كتب");
        let slots = vec![slot.clone()];
        let entries = vec![entry.clone()];

        state.place(0, 0, &slot, &entry);
        assert!(state.placed_ids.contains(&1));

        state.unplace_last(&slots, &entries);
        assert!(!state.placed_ids.contains(&1));
        assert_eq!(state.grid.get(1, 1), None);
        assert_eq!(state.grid.get(1, 2), None);
    }

    #[test]
    fn test_shared_cell_ref_count() {
        // Deux slots partagent une case : (1,2)
        // H : (1,1)...(1,3), V : (0,2)...(2,2)
        let mut state = BacktrackState::new(4, 4);
        let slot_h = make_slot(Direction::Horizontal, 1, 1, 3);
        let slot_v = make_slot(Direction::Vertical, 0, 2, 3);
        let entry_h = make_entry(1, "كتب"); // ت à (1,2)
        let entry_v = make_entry(2, "بتر"); // ت à (1,2) aussi
        let slots = vec![slot_h.clone(), slot_v.clone()];
        let entries_vec = vec![entry_h.clone(), entry_v.clone()];

        state.place(0, 0, &slot_h, &entry_h);
        state.place(1, 1, &slot_v, &entry_v);

        // (1,2) est occupé par les deux
        assert_eq!(state.grid.get(1, 2), Some('ت'));

        // Unplace le slot vertical
        state.unplace_last(&slots, &entries_vec);
        // (1,2) doit encore avoir la lettre du slot H
        assert_eq!(state.grid.get(1, 2), Some('ت'));

        // Unplace le slot horizontal
        state.unplace_last(&slots, &entries_vec);
        // Maintenant (1,2) est vide
        assert_eq!(state.grid.get(1, 2), None);
    }
}
