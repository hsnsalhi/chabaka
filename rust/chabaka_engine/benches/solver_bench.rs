/// Benchmarks Criterion pour le solver Chabaka.
///
/// Exécution : cargo bench
/// Cibles attendues (spec §9) :
///   8×8  → P95 < 5 s
///   16×13 → P95 < 30 s (host macOS arm64)
use criterion::{criterion_group, criterion_main, Criterion};
use std::time::Duration;

use chabaka_engine::kb::KbCompact;
use chabaka_engine::models::{ConfigInput, KbEntryLite};
use chabaka_engine::normalizer::{normalize, NormalizerOptions};
use bitvec::prelude::*;
use std::collections::HashMap;

// ---------------------------------------------------------------------------
// KB synthétique large pour les benches (pas besoin de SQLite)
// ---------------------------------------------------------------------------

/// Génère une KB synthétique avec des mots arabes fictifs de toutes les longueurs.
/// Suffisamment grande pour que le solver ait des candidats réalistes.
fn make_bench_kb(target_per_length: usize) -> KbCompact {
    use chabaka_engine::kb::ALPHABET_SIZE;

    // Lettres arabes de base utilisées pour générer des "mots"
    let letters: Vec<char> = "ابتثجحخدذرزسشصضطظعغفقكلمنهوي".chars().collect();
    let n_letters = letters.len();
    let opts = NormalizerOptions::default();

    let mut entries = Vec::new();
    let mut id = 1u32;

    for length in 2usize..=8 {
        for i in 0..(target_per_length * 2) {
            // Générer un mot pseudo-aléatoire de cette longueur
            let chars: Vec<char> = (0..length)
                .map(|pos| letters[(i * 7 + pos * 13) % n_letters])
                .collect();
            // Dédupliquer (mot unique par ID)
            let word: String = chars.iter().collect();
            let normalized = normalize(&word, opts);
            let norm_chars: Vec<char> = normalized.chars().collect();
            if norm_chars.len() == length {
                entries.push(KbEntryLite { id, chars: norm_chars });
                id += 1;
            }
        }
        // Ajouter des mots avec des premières lettres variées (pour AC-3 efficace)
        for li in 0..n_letters.min(target_per_length) {
            let chars: Vec<char> = std::iter::once(letters[li])
                .chain((1..length).map(|pos| letters[(li * 3 + pos * 5) % n_letters]))
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

    // Construire les index
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
                if let Some(li) = chabaka_engine::kb::char_to_idx(ch) {
                    positions[pos][li].set(slot_idx, true);
                }
            }
        }
        letter_index.insert(length, positions);
    }

    KbCompact { entries, by_length, letter_index }
}

// ---------------------------------------------------------------------------
// Patrons de grille
// ---------------------------------------------------------------------------

/// Patron 8×8 (Pattern 0 de _patterns8x8 dans topology.dart)
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

/// Patron 16×13 (pattern de _patterns16x13 dans topology.dart)
fn pattern_16x13() -> Vec<u8> {
    // Miroir exact du const _patterns16x13[0] dans topology.dart
    // CellKind::clue=1, CellKind::letter=0, CellKind::blocker=2
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
// Benchmarks
// ---------------------------------------------------------------------------

fn bench_8x8(c: &mut Criterion) {
    let kb = make_bench_kb(200); // ~200 mots par longueur = ~1400 entrées total

    let config = ConfigInput {
        rows: 8,
        cols: 8,
        seed: 42,
        deadline_ms: 10_000, // 10s max pour le bench
        max_retries: 5,
        pattern_kinds: pattern_8x8(),
    };

    let mut group = c.benchmark_group("solver_8x8");
    group.measurement_time(Duration::from_secs(30));
    group.sample_size(10);

    group.bench_function("solve", |b| {
        b.iter(|| {
            let result = chabaka_engine::solver::solve(&config, &kb);
            criterion::black_box(result)
        });
    });

    group.finish();
}

fn bench_16x13(c: &mut Criterion) {
    let kb = make_bench_kb(500); // ~500 mots par longueur = ~3500 entrées

    let config = ConfigInput {
        rows: 16,
        cols: 13,
        seed: 42,
        deadline_ms: 60_000, // 60s max pour le bench
        max_retries: 3,
        pattern_kinds: pattern_16x13(),
    };

    let mut group = c.benchmark_group("solver_16x13");
    group.measurement_time(Duration::from_secs(120));
    group.sample_size(5);

    group.bench_function("solve", |b| {
        b.iter(|| {
            let result = chabaka_engine::solver::solve(&config, &kb);
            criterion::black_box(result)
        });
    });

    group.finish();
}

fn bench_kb_load_simulated(c: &mut Criterion) {
    // Bench de la construction KB (simulation du preload)
    c.bench_function("kb_build_1400_entries", |b| {
        b.iter(|| {
            let kb = make_bench_kb(200);
            criterion::black_box(kb.len())
        });
    });
}

criterion_group!(
    benches,
    bench_kb_load_simulated,
    bench_8x8,
    bench_16x13
);
criterion_main!(benches);
