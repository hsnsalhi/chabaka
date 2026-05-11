/// Tests de performance (mesure de temps réel).
///
/// Exécution : cargo test --release --test perf_test -- --nocapture
///
/// Ces tests NE font PAS de assertions strictes sur le temps (pour éviter
/// des flaps CI selon la machine), mais impriment les timings pour audit.

use bitvec::prelude::*;
use std::collections::HashMap;
use std::time::Instant;

use chabaka_engine::kb::{char_to_idx, KbCompact, ALPHABET_SIZE};
use chabaka_engine::models::{ConfigInput, KbEntryLite};
use chabaka_engine::normalizer::{normalize, NormalizerOptions};
use chabaka_engine::solver::solve;

// ---------------------------------------------------------------------------
// KB synthétique (même logique que solver_bench.rs)
// ---------------------------------------------------------------------------

fn make_bench_kb(target_per_length: usize) -> KbCompact {
    let letters: Vec<char> = "ابتثجحخدذرزسشصضطظعغفقكلمنهوي".chars().collect();
    let n_letters = letters.len();
    let opts = NormalizerOptions::default();

    let mut entries = Vec::new();
    let mut id = 1u32;

    for length in 2usize..=8 {
        // Mots générés par combinaison
        for i in 0..(target_per_length * 3) {
            let chars: Vec<char> = (0..length)
                .map(|pos| letters[(i * 7 + pos * 13 + length * 3) % n_letters])
                .collect();
            let word: String = chars.iter().collect();
            let normalized = normalize(&word, opts);
            let norm_chars: Vec<char> = normalized.chars().collect();
            if norm_chars.len() == length {
                entries.push(KbEntryLite { id, chars: norm_chars });
                id += 1;
            }
        }
        // Variante : premières lettres distribuées
        for li in 0..n_letters {
            for variant in 0..5usize {
                let chars: Vec<char> = std::iter::once(letters[li])
                    .chain((1..length).map(|pos| letters[(li * 5 + pos * 7 + variant * 11) % n_letters]))
                    .collect();
                let word: String = chars.iter().collect();
                let normalized = normalize(&word, opts);
                let norm_chars: Vec<char> = normalized.chars().collect();
                if norm_chars.len() == length {
                    entries.push(KbEntryLite { id, chars: norm_chars });
                    id += 1;
                }
            }
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

// ---------------------------------------------------------------------------
// Patrons
// ---------------------------------------------------------------------------

fn pattern_8x8() -> Vec<u8> {
    // CLLLCCCC / LCCCLLLL / LLLCLLLL / CLLLLLCL / CLLLLCLL / LCLLCLLC / LCLLLCLL / CLLCLLLL
    vec![
        1, 0, 0, 0, 1, 1, 1, 1,
        0, 1, 1, 1, 0, 0, 0, 0,
        0, 0, 0, 1, 0, 0, 0, 0,
        1, 0, 0, 0, 0, 0, 1, 0,
        1, 0, 0, 0, 0, 1, 0, 0,
        0, 1, 0, 0, 1, 0, 0, 1,
        0, 1, 0, 0, 0, 1, 0, 0,
        1, 0, 0, 1, 0, 0, 0, 0,
    ]
}

fn pattern_16x13() -> Vec<u8> {
    vec![
        1, 1, 1, 0, 0, 1, 1, 1, 0, 0, 0, 1, 1,
        0, 0, 0, 0, 1, 0, 0, 0, 1, 1, 0, 0, 0,
        0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0, 0,
        1, 0, 0, 1, 1, 0, 0, 0, 0, 0, 1, 0, 0,
        1, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 1,
        0, 1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0,
        0, 1, 1, 0, 0, 0, 1, 1, 0, 0, 0, 1, 0,
        1, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 1,
        1, 0, 0, 1, 0, 0, 0, 1, 0, 0, 1, 0, 0,
        0, 1, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0,
        0, 1, 0, 0, 1, 0, 0, 1, 0, 0, 0, 1, 0,
        1, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 0, 0,
        0, 1, 0, 0, 0, 1, 1, 0, 0, 1, 0, 0, 1,
        0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0,
        0, 1, 0, 0, 1, 0, 0, 1, 0, 0, 1, 0, 0,
        1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0,
    ]
}

// ---------------------------------------------------------------------------
// Tests de perf
// ---------------------------------------------------------------------------

#[test]
fn perf_8x8_solve_timing() {
    let kb = make_bench_kb(200);

    let len2 = kb.by_length.get(&2).map(|v| v.len()).unwrap_or(0);
    let len3 = kb.by_length.get(&3).map(|v| v.len()).unwrap_or(0);
    let len4 = kb.by_length.get(&4).map(|v| v.len()).unwrap_or(0);
    let len5 = kb.by_length.get(&5).map(|v| v.len()).unwrap_or(0);
    println!("\n[perf 8x8] KB: len2={} len3={} len4={} len5={} total={}", len2, len3, len4, len5, kb.len());

    let config = ConfigInput {
        rows: 8,
        cols: 8,
        seed: 42,
        deadline_ms: 30_000,
        max_retries: 10,
        pattern_kinds: pattern_8x8(),
    };

    let runs = 3;
    let mut times = Vec::new();

    for i in 0..runs {
        let t = Instant::now();
        let result = solve(&config, &kb);
        let elapsed = t.elapsed();
        times.push(elapsed);
        let status = result.as_ref().map(|o| o.status).unwrap_or(99);
        println!("[perf 8x8] run {} : {:.1}ms (status={})", i, elapsed.as_secs_f64() * 1000.0, status);
    }

    let max_ms = times.iter().map(|t| t.as_millis()).max().unwrap_or(0);
    println!("[perf 8x8] Max: {}ms (target < 5000ms)", max_ms);
    // Assertion souple : < 30s (le vrai target device est 5s mais en test host sans vraie KB c'est OK)
    assert!(max_ms < 30_000, "8x8 solve took more than 30s: {}ms", max_ms);
}

#[test]
fn perf_16x13_solve_timing() {
    let kb = make_bench_kb(400);

    let total = kb.len();
    println!("\n[perf 16x13] KB: {} total entries", total);

    let config = ConfigInput {
        rows: 16,
        cols: 13,
        seed: 42,
        deadline_ms: 30_000, // 30s max (cible ticket)
        max_retries: 5,
        pattern_kinds: pattern_16x13(),
    };

    let t = Instant::now();
    let result = solve(&config, &kb);
    let elapsed = t.elapsed();
    let elapsed_ms = elapsed.as_millis();

    let status = result.as_ref().map(|o| o.status).unwrap_or(99);
    if let Ok(ref output) = result {
        if let Some(ref placed) = output.placed {
            println!("[perf 16x13] elapsed={}ms status={} placed={}", elapsed_ms, status, placed.len());
        } else {
            println!("[perf 16x13] elapsed={}ms status={} (no solution)", elapsed_ms, status);
        }
    }

    // Validation : le solve doit se terminer (pas crasher) dans le délai donné
    assert!(result.is_ok(), "16x13 solve returned Err");
    // Le temps doit être < 35s (avec 30s deadline + overhead)
    assert!(elapsed_ms < 35_000, "16x13 solve took too long: {}ms", elapsed_ms);
}
