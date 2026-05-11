/// Knowledge Base — lecture SQLite + indexation compacte en RAM.
///
/// Stratégie (spec §5.2) :
///   Init : ouvre la connexion SQLite read-only, charge TOUT en RAM,
///   ferme la connexion. Aucune requête SQL pendant le backtracking.
///
/// Index construit :
///   `letter_index[length][position][letter_codepoint_idx] → bitset d'IDs`
///   → O(1) lookup pour "quels mots de longueur L ont le char C à la position P"
///
/// Coût RAM : ~27 792 lignes × ~16 octets = ~500 KB (acceptable, spec §4.1).

use std::collections::HashMap;
use bitvec::prelude::*;
use rusqlite::{Connection, OpenFlags};

use crate::models::{KbEntryLite, LetterConstraint};
use crate::normalizer::{NormalizerOptions, normalize};

/// Alphabet arabe utilisé pour l'indexation.
/// On mappe chaque char arabe de base (après normalisation) vers un indice compact.
/// ا ب ت ث ج ح خ د ذ ر ز س ش ص ض ط ظ ع غ ف ق ك ل م ن ه و ي
/// = 28 lettres (0x0627..=0x064A, hors diacritiques)
/// Après normalisation : أ إ آ ٱ → ا (index 0), ة → ه (index 25), ى → ي (index 27)
const ARABIC_LETTERS: &[char] = &[
    'ا', 'ب', 'ت', 'ث', 'ج', 'ح', 'خ', 'د', 'ذ', 'ر',
    'ز', 'س', 'ش', 'ص', 'ض', 'ط', 'ظ', 'ع', 'غ', 'ف',
    'ق', 'ك', 'ل', 'م', 'ن', 'ه', 'و', 'ي',
];

pub const ALPHABET_SIZE: usize = ARABIC_LETTERS.len(); // 28

pub fn char_to_idx(c: char) -> Option<usize> {
    ARABIC_LETTERS.iter().position(|&a| a == c)
}

// ---------------------------------------------------------------------------
// Structure compacte KB
// ---------------------------------------------------------------------------

/// KB préchargée en RAM.
pub struct KbCompact {
    /// Toutes les entrées, indexées par leur position dans ce Vec (entry_idx).
    /// NB : entry_idx ≠ kb_id (l'id SQLite est stocké dans KbEntryLite.id).
    pub entries: Vec<KbEntryLite>,

    /// Map longueur → indices des entrées de cette longueur dans `entries`.
    pub by_length: HashMap<usize, Vec<usize>>,

    /// Index lettre : `letter_index[length][position][letter_idx]` → BitVec sur entry_idx.
    /// Clé outer = longueur (2..=max_len).
    /// Position = index dans le mot (0-based).
    /// letter_idx = index dans ARABIC_LETTERS.
    /// Valeur = bitset de taille `by_length[length].len()`, bit i = 1 si l'entrée
    /// à la position i dans `by_length[length]` a la lettre `letter_idx` à `position`.
    pub letter_index: HashMap<usize, Vec<[BitVec; ALPHABET_SIZE]>>,
}

impl KbCompact {
    /// Charge la KB depuis un fichier SQLite (schéma Chabaka standard).
    ///
    /// Schéma attendu :
    ///   entries(id, word, word_display, length, ...)
    ///   letter_index(entry_id, position, letter)  ← optionnel, recalculé si absent
    pub fn load(sqlite_path: &str) -> Result<Self, crate::models::EngineError> {
        let conn = Connection::open_with_flags(
            sqlite_path,
            OpenFlags::SQLITE_OPEN_READ_ONLY | OpenFlags::SQLITE_OPEN_NO_MUTEX,
        )
        .map_err(|e| crate::models::EngineError::KbOpenFailed(e.to_string()))?;

        let opts = NormalizerOptions::default();

        // Charger toutes les entrées
        let mut stmt = conn
            .prepare("SELECT id, word, length FROM entries ORDER BY id")
            .map_err(|e| crate::models::EngineError::KbOpenFailed(e.to_string()))?;

        let mut entries: Vec<KbEntryLite> = Vec::new();

        let rows = stmt
            .query_map([], |row| {
                let id: i64 = row.get(0)?;
                let word: String = row.get(1)?;
                Ok((id as u32, word))
            })
            .map_err(|e| crate::models::EngineError::KbOpenFailed(e.to_string()))?;

        for row in rows {
            let (id, word) = row.map_err(|e| crate::models::EngineError::KbOpenFailed(e.to_string()))?;
            // Normaliser le mot (au cas où la KB ne serait pas pré-normalisée)
            let normalized = normalize(&word, opts);
            let chars: Vec<char> = normalized.chars().collect();
            if chars.is_empty() || chars.len() < 2 {
                continue; // On ignore les entrées trop courtes
            }
            entries.push(KbEntryLite { id, chars });
        }

        drop(stmt);
        drop(conn); // Connexion fermée ici — plus aucune requête SQL après

        // Construire les index
        let mut by_length: HashMap<usize, Vec<usize>> = HashMap::new();
        for (entry_idx, entry) in entries.iter().enumerate() {
            by_length.entry(entry.chars.len()).or_default().push(entry_idx);
        }

        // Construire letter_index
        let mut letter_index: HashMap<usize, Vec<[BitVec; ALPHABET_SIZE]>> = HashMap::new();

        for (&length, indices) in &by_length {
            let n = indices.len();
            // Pour chaque position, pour chaque lettre, un bitset de taille n
            // Initialiser : position_count = length, chaque = [BitVec::repeat(false, n); ALPHABET_SIZE]
            let mut positions: Vec<[BitVec; ALPHABET_SIZE]> = (0..length)
                .map(|_| {
                    // Pas de Copy pour BitVec, on construit manuellement
                    std::array::from_fn(|_| BitVec::<usize, Lsb0>::repeat(false, n))
                })
                .collect();

            for (slot_idx, &entry_idx) in indices.iter().enumerate() {
                let chars = &entries[entry_idx].chars;
                for (pos, &ch) in chars.iter().enumerate() {
                    if let Some(letter_idx) = char_to_idx(ch) {
                        positions[pos][letter_idx].set(slot_idx, true);
                    }
                    // Si le char n'est pas dans ARABIC_LETTERS (ponctuation, etc.),
                    // on l'ignore — il ne matche jamais de contrainte.
                }
            }

            letter_index.insert(length, positions);
        }

        Ok(KbCompact {
            entries,
            by_length,
            letter_index,
        })
    }

    /// Nombre total d'entrées.
    pub fn len(&self) -> usize {
        self.entries.len()
    }

    pub fn is_empty(&self) -> bool {
        self.entries.is_empty()
    }

    /// Trouve les entrées compatibles avec un slot de longueur `length` et les
    /// contraintes `constraints` (lettres déjà fixées par d'autres slots).
    ///
    /// Retourne les indices dans `entries` (pas les kb_id).
    /// Exclut les entrées dont le kb_id est dans `exclude_ids`.
    ///
    /// Algorithme :
    ///   1. Part du bitset complet de la longueur (tous les indices actifs).
    ///   2. Pour chaque contrainte, AND avec le bitset de la lettre à la position donnée.
    ///   3. Collecte les entry_idx restants, filtre excluded, retourne.
    pub fn find_matching(
        &self,
        length: usize,
        constraints: &[LetterConstraint],
        exclude_ids: &[u32],
    ) -> Vec<usize> {
        let indices = match self.by_length.get(&length) {
            Some(v) => v,
            None => return vec![],
        };

        let n = indices.len();
        if n == 0 {
            return vec![];
        }

        // Bitset initial : tous les slots actifs
        let mut active: BitVec<usize, Lsb0> = BitVec::repeat(true, n);

        // Pour chaque contrainte, AND avec le bitset de la lettre à cette position
        if let Some(positions) = self.letter_index.get(&length) {
            for constraint in constraints {
                if constraint.position >= length {
                    // Contrainte hors bornes → aucun candidat possible
                    return vec![];
                }
                if let Some(letter_idx) = char_to_idx(constraint.letter) {
                    let letter_bitset = &positions[constraint.position][letter_idx];
                    // active &= letter_bitset
                    for (i, mut bit) in active.iter_mut().enumerate() {
                        if i < letter_bitset.len() {
                            *bit &= letter_bitset[i];
                        } else {
                            *bit = false;
                        }
                    }
                } else {
                    // Lettre inconnue (hors alphabet arabe de base) → aucun candidat
                    return vec![];
                }
            }
        }

        // Collecter les entry_idx actifs, filtrer les excluded
        let exclude_set: std::collections::HashSet<u32> = exclude_ids.iter().copied().collect();

        active
            .iter()
            .enumerate()
            .filter_map(|(slot_idx, bit)| {
                if *bit {
                    let entry_idx = indices[slot_idx];
                    let entry = &self.entries[entry_idx];
                    if exclude_set.contains(&entry.id) {
                        None
                    } else {
                        Some(entry_idx)
                    }
                } else {
                    None
                }
            })
            .collect()
    }

    /// Vérifie qu'il existe au moins un candidat pour ce slot (forward check rapide).
    pub fn has_any_candidate(
        &self,
        length: usize,
        constraints: &[LetterConstraint],
        exclude_ids: &[u32],
    ) -> bool {
        let indices = match self.by_length.get(&length) {
            Some(v) => v,
            None => return false,
        };
        let n = indices.len();
        if n == 0 {
            return false;
        }

        let mut active: BitVec<usize, Lsb0> = BitVec::repeat(true, n);

        if let Some(positions) = self.letter_index.get(&length) {
            for constraint in constraints {
                if constraint.position >= length {
                    return false;
                }
                if let Some(letter_idx) = char_to_idx(constraint.letter) {
                    let letter_bitset = &positions[constraint.position][letter_idx];
                    for (i, mut bit) in active.iter_mut().enumerate() {
                        if i < letter_bitset.len() {
                            *bit &= letter_bitset[i];
                        } else {
                            *bit = false;
                        }
                    }
                } else {
                    return false;
                }
            }
        }

        let exclude_set: std::collections::HashSet<u32> = exclude_ids.iter().copied().collect();

        active.iter().enumerate().any(|(slot_idx, bit)| {
            if *bit {
                let entry_idx = indices[slot_idx];
                !exclude_set.contains(&self.entries[entry_idx].id)
            } else {
                false
            }
        })
    }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;
    use crate::models::KbEntryLite;

    /// Crée une KB en mémoire sans SQLite pour les tests unitaires.
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

        let mut letter_index: HashMap<usize, Vec<[BitVec; ALPHABET_SIZE]>> = HashMap::new();
        for (&length, indices) in &by_length {
            let n = indices.len();
            let mut positions: Vec<[BitVec; ALPHABET_SIZE]> = (0..length)
                .map(|_| std::array::from_fn(|_| BitVec::<usize, Lsb0>::repeat(false, n)))
                .collect();
            for (slot_idx, &entry_idx) in indices.iter().enumerate() {
                for (pos, &ch) in entries[entry_idx].chars.iter().enumerate() {
                    if let Some(li) = char_to_idx(ch) {
                        positions[pos][li].set(slot_idx, true);
                    }
                }
            }
            letter_index.insert(length, positions);
        }

        KbCompact { entries, by_length, letter_index }
    }

    #[test]
    fn test_find_by_length() {
        let kb = make_test_kb(&[("كتاب", 1), ("باب", 2), ("قلم", 3), ("سلام", 4)]);
        // "كتاب" et "سلام" ont longueur 4
        let res = kb.find_matching(4, &[], &[]);
        assert_eq!(res.len(), 2);
        // "باب" et "قلم" ont longueur 3
        let res = kb.find_matching(3, &[], &[]);
        assert_eq!(res.len(), 2);
    }

    #[test]
    fn test_find_with_constraint() {
        // "كتاب" commence par ك, "سلام" commence par س
        let kb = make_test_kb(&[("كتاب", 1), ("سلام", 2), ("كلام", 3)]);
        let constraints = vec![LetterConstraint { position: 0, letter: 'ك' }];
        let res = kb.find_matching(4, &constraints, &[]);
        // Doit retourner كتاب (id=1) et كلام (id=3)
        assert_eq!(res.len(), 2);
        for idx in &res {
            assert_eq!(kb.entries[*idx].chars[0], 'ك');
        }
    }

    #[test]
    fn test_exclude_ids() {
        let kb = make_test_kb(&[("كتاب", 1), ("كلام", 2)]);
        let res = kb.find_matching(4, &[], &[1]);
        assert_eq!(res.len(), 1);
        assert_eq!(kb.entries[res[0]].id, 2);
    }

    #[test]
    fn test_constraint_unknown_letter() {
        let kb = make_test_kb(&[("كتاب", 1)]);
        // '@' n'est pas dans ARABIC_LETTERS → aucun candidat
        let constraints = vec![LetterConstraint { position: 0, letter: '@' }];
        let res = kb.find_matching(4, &constraints, &[]);
        assert!(res.is_empty());
    }

    #[test]
    fn test_has_any_candidate() {
        let kb = make_test_kb(&[("كتاب", 1), ("سلام", 2)]);
        let constraints = vec![LetterConstraint { position: 0, letter: 'ك' }];
        assert!(kb.has_any_candidate(4, &constraints, &[]));
        assert!(!kb.has_any_candidate(4, &constraints, &[1]));
    }

    #[test]
    fn test_alef_normalization_in_kb() {
        // أكل normalisé → اكل : doit matcher avec contrainte ا en pos 0
        let kb = make_test_kb(&[("أكل", 1)]);
        let constraints = vec![LetterConstraint { position: 0, letter: 'ا' }];
        let res = kb.find_matching(3, &constraints, &[]);
        assert_eq!(res.len(), 1);
    }
}
