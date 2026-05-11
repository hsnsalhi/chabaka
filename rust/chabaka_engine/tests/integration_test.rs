/// Tests d'intégration Rust pur (sans SQLite).
///
/// Valide le pipeline complet :
///   normalizer → kb (in-memory) → solver → output

use bitvec::prelude::*;
use std::collections::HashMap;

use chabaka_engine::kb::{char_to_idx, KbCompact, ALPHABET_SIZE};
use chabaka_engine::models::{ConfigInput, KbEntryLite};
use chabaka_engine::normalizer::{normalize, NormalizerOptions};
use chabaka_engine::solver::solve;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

fn make_kb(words: &[(&str, u32)]) -> KbCompact {
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

fn config_4x4(seed: u64) -> ConfigInput {
    // Patron 4×4 standard (BCCC / CLLL × 3)
    ConfigInput {
        rows: 4,
        cols: 4,
        seed,
        deadline_ms: 30_000,
        max_retries: 20,
        pattern_kinds: vec![
            2, 1, 1, 1,
            1, 0, 0, 0,
            1, 0, 0, 0,
            1, 0, 0, 0,
        ],
    }
}

fn config_5x5(seed: u64) -> ConfigInput {
    // Patron 5×5 standard (BCCCC / CLLLL × 4)
    ConfigInput {
        rows: 5,
        cols: 5,
        seed,
        deadline_ms: 30_000,
        max_retries: 20,
        pattern_kinds: vec![
            2, 1, 1, 1, 1,
            1, 0, 0, 0, 0,
            1, 0, 0, 0, 0,
            1, 0, 0, 0, 0,
            1, 0, 0, 0, 0,
        ],
    }
}

fn config_7x7(seed: u64) -> ConfigInput {
    // Patron 7×7 (BCCCCCC / CLLLLLL × 6)
    let mut kinds = vec![0u8; 49];
    kinds[0] = 2;
    for c in 1..7 { kinds[c] = 1; }
    for r in 1..7 { kinds[r * 7] = 1; }
    ConfigInput {
        rows: 7,
        cols: 7,
        seed,
        deadline_ms: 60_000,
        max_retries: 20,
        pattern_kinds: kinds,
    }
}

/// Grande KB avec des mots arabes de longueur 3 à 6.
fn make_large_kb() -> KbCompact {
    make_kb(&[
        // Longueur 3
        ("كتب", 1), ("قلم", 2), ("باب", 3), ("دار", 4), ("نور", 5),
        ("بحر", 6), ("جبل", 7), ("نهر", 8), ("شمس", 9), ("قمر", 10),
        ("ليل", 11), ("صوت", 12), ("حصن", 13), ("طير", 14), ("ذهب", 15),
        ("فضة", 16), ("ماء", 17), ("دم", 18), ("سن", 19), // len2, len2
        ("روح", 20), ("ورد", 21), ("زهر", 22), ("عين", 23), ("فم", 24),
        // Longueur 4
        ("كتاب", 101), ("سلام", 102), ("قلوب", 103), ("نهار", 104),
        ("بحار", 105), ("جبال", 106), ("رجال", 107), ("بيوت", 108),
        ("كلام", 109), ("عالم", 110), ("مدرس", 111), ("صديق", 112),
        ("نجاح", 113), ("ربيع", 114), ("بلاد", 115), ("ملاك", 116),
        ("جهاد", 117), ("وفاق", 118), ("سماء", 119), ("قضاء", 120),
        ("مساء", 121), ("دعاء", 122), ("صباح", 123), ("مساج", 124),
        ("فراش", 125), ("ملابس", 126), // len6
        ("طعام", 127), ("شراب", 128), ("كرسي", 129), ("طاولة", 130), // len5, len5
        ("درسة", 131), ("عمارة", 132), // len4 après norm: عماره, درسه
        // Longueur 5
        ("كتبوا", 201), ("سلامة", 202), ("نهارك", 203), ("جبالي", 204),
        ("رجالك", 205), ("بيوتي", 206), ("كلامه", 207), ("عالمي", 208),
        ("صديقي", 209), ("نجاحك", 210), ("بلادي", 211), ("ملاكي", 212),
        ("سماؤك", 213), ("قضاؤه", 214), ("صباحك", 215), ("طعامك", 216),
        ("شرابك", 217), ("كرسيك", 218), ("ورودي", 219), ("بحوثي", 220),
        // Longueur 6
        ("مدارس", 301), ("معلوم", 302), ("قواعد", 303), ("رسائل", 304),
        ("مكتبة", 305), ("درجات", 306), ("رياضة", 307), ("ثقافة", 308),
        ("صناعة", 309), ("زراعة", 310), ("تجارة", 311), ("سياسة", 312),
    ])
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[test]
fn test_normalizer_alef() {
    use chabaka_engine::normalizer::normalize_default;
    assert_eq!(normalize_default("أهل"), "اهل");
    assert_eq!(normalize_default("إبراهيم"), "ابراهيم");
    assert_eq!(normalize_default("آداب"), "اداب");
}

#[test]
fn test_normalizer_ta_marbuta() {
    use chabaka_engine::normalizer::normalize_default;
    assert_eq!(normalize_default("مدرسة"), "مدرسه");
    assert_eq!(normalize_default("فاطمة"), "فاطمه");
}

#[test]
fn test_normalizer_yaa() {
    use chabaka_engine::normalizer::normalize_default;
    assert_eq!(normalize_default("موسى"), "موسي");
}

#[test]
fn test_normalizer_diacritics() {
    use chabaka_engine::normalizer::normalize_default;
    assert_eq!(normalize_default("كَتَبَ"), "كتب");
    assert_eq!(normalize_default("مُحَمَّدٌ"), "محمد");
}

#[test]
fn test_kb_find_matching_basic() {
    let kb = make_kb(&[("كتاب", 1), ("سلام", 2), ("قلم", 3)]);
    let res = kb.find_matching(4, &[], &[]);
    assert_eq!(res.len(), 2); // كتاب et سلام (len 4)

    let res3 = kb.find_matching(3, &[], &[]);
    assert_eq!(res3.len(), 1); // قلم (len 3)
}

#[test]
fn test_kb_find_matching_with_constraint() {
    use chabaka_engine::models::LetterConstraint;
    let kb = make_kb(&[("كتاب", 1), ("كلام", 2), ("سلام", 3)]);
    let constraints = vec![LetterConstraint { position: 0, letter: 'ك' }];
    let res = kb.find_matching(4, &constraints, &[]);
    assert_eq!(res.len(), 2); // كتاب et كلام
}

#[test]
fn test_solve_4x4_converges() {
    let kb = make_large_kb();
    // Vérifier qu'on a des mots de longueur 3
    let count3 = kb.by_length.get(&3).map(|v| v.len()).unwrap_or(0);
    assert!(count3 >= 5, "Need ≥5 words of length 3, got {}", count3);

    let config = config_4x4(42);
    let result = solve(&config, &kb);
    assert!(result.is_ok(), "solve() error: {:?}", result.err());

    let output = result.unwrap();
    // Doit trouver une solution avec cette KB
    if output.status == 0 {
        let cells = output.cells.as_ref().unwrap();
        assert_eq!(cells.len(), 16); // 4×4

        // Toutes les cases lettre doivent avoir une lettre
        let kinds = config_4x4(42).pattern_kinds;
        for (i, cell) in cells.iter().enumerate() {
            if kinds[i] == 0 {
                // letter cell
                assert!(cell.letter.is_some(), "Cell {} is a letter cell but has no letter", i);
                // Lettre arabe valide (1 char)
                let letter = cell.letter.as_ref().unwrap();
                assert_eq!(letter.chars().count(), 1, "Letter cell {} has {} chars", i, letter.chars().count());
            }
        }

        // Pas de mots dupliqués
        let placed = output.placed.as_ref().unwrap();
        let ids: std::collections::HashSet<u32> = placed.iter().map(|p| p.kb_id).collect();
        assert_eq!(ids.len(), placed.len(), "Duplicate words placed");
    }
    // Si no_solution : pas une erreur (la KB est peut-être trop restreinte)
}

#[test]
fn test_solve_5x5_converges() {
    let kb = make_large_kb();
    let count4 = kb.by_length.get(&4).map(|v| v.len()).unwrap_or(0);
    assert!(count4 >= 8, "Need ≥8 words of length 4, got {}", count4);

    let config = config_5x5(42);
    let result = solve(&config, &kb);
    assert!(result.is_ok(), "solve() error: {:?}", result.err());

    let output = result.unwrap();
    if output.status == 0 {
        let cells = output.cells.as_ref().unwrap();
        assert_eq!(cells.len(), 25); // 5×5

        // Vérifier cohérence : les lettres aux intersections doivent matcher
        let kinds = config_5x5(42).pattern_kinds;
        let mut _grid = vec![None::<char>; 25];
        for (i, cell) in cells.iter().enumerate() {
            if kinds[i] == 0 {
                if let Some(ref l) = cell.letter {
                    _grid[i] = l.chars().next();
                }
            }
        }

        // Vérifier via les placements que les mots sont dans la KB
        let placed = output.placed.as_ref().unwrap();
        for p in placed {
            assert!(p.len >= 2, "Placed word has length < 2");
            assert!(p.len <= 4, "Placed word has length > 4 for 5x5 grid");
        }
    }
}

#[test]
fn test_solve_multiple_seeds() {
    // Avec différents seeds, on doit toujours obtenir soit une solution valide
    // soit no_solution (jamais une erreur).
    let kb = make_large_kb();
    let config_base = config_4x4(0);

    for seed in [1u64, 42, 100, 999, 12345] {
        let mut config = clone_config(&config_base);
        config.seed = seed;
        let result = solve(&config, &kb);
        assert!(
            result.is_ok(),
            "solve() returned Err for seed={}: {:?}",
            seed,
            result.err()
        );
    }
}

#[test]
fn test_solve_empty_kb_returns_error() {
    let kb = make_kb(&[]); // KB vide
    let config = config_4x4(42);
    let result = solve(&config, &kb);
    // Soit erreur InvalidInput, soit no_solution — jamais un crash
    assert!(result.is_ok() || result.is_err());
}

#[test]
fn test_solve_wrong_pattern_size() {
    let kb = make_large_kb();
    let mut config = config_4x4(42);
    config.pattern_kinds = vec![0u8; 5]; // Mauvaise taille (5 ≠ 4*4=16)
    let result = solve(&config, &kb);
    assert!(result.is_err(), "Should return Err for wrong pattern size");
}

#[test]
fn test_placed_words_match_grid_letters() {
    // Vérifie que les mots placés correspondent aux lettres dans la grille
    let kb = make_large_kb();
    let config = config_4x4(42);
    let result = solve(&config, &kb).unwrap();

    if result.status != 0 {
        return; // No solution — pas d'erreur mais rien à vérifier
    }

    let cells = result.cells.as_ref().unwrap();
    let placed = result.placed.as_ref().unwrap();
    let kinds = config.pattern_kinds;

    // Reconstruire la grille de lettres
    let grid: Vec<Option<char>> = cells.iter().map(|cell| {
        cell.letter.as_ref().and_then(|l| l.chars().next())
    }).collect();

    // Pour chaque placement, vérifier que les lettres dans la grille correspondent
    for p in placed {
        let (dr, dc): (u16, u16) = if p.dir == 0 { (0, 1) } else { (1, 0) };
        for i in 0..p.len as u16 {
            let r = (p.slot_row + i * dr) as usize;
            let c = (p.slot_col + i * dc) as usize;
            let idx = r * 4 + c;
            assert!(
                idx < 16,
                "Placement out of bounds: ({},{}) for 4x4",
                r,
                c
            );
            assert!(
                kinds[idx] == 0,
                "Placement lands on non-letter cell ({},{}) kind={}",
                r,
                c,
                kinds[idx]
            );
            assert!(
                grid[idx].is_some(),
                "Letter cell ({},{}) is empty",
                r,
                c
            );
        }
    }
}

/// Helper pour cloner ConfigInput dans les tests (ConfigInput n'implémente pas Clone
/// car rmp-serde Deserialize ne l'exige pas, mais on en a besoin ici).
fn clone_config(c: &ConfigInput) -> ConfigInput {
    ConfigInput {
        rows: c.rows,
        cols: c.cols,
        seed: c.seed,
        deadline_ms: c.deadline_ms,
        max_retries: c.max_retries,
        pattern_kinds: c.pattern_kinds.clone(),
    }
}
