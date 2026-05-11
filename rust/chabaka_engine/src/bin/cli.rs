/// CLI de test pour le moteur Chabaka.
///
/// Usage :
///   chabaka_cli --kb <path> --rows 8 --cols 8 --seed 42 --timeout 30000
///
/// Utile pour tester le solver sans passer par Dart/FFI.

use std::time::Instant;

// Dans un bin/ du même crate, on importe directement les modules du crate root.
use chabaka_engine::kb::KbCompact;
use chabaka_engine::models::{CellOutput, ConfigInput};
use chabaka_engine::solver::solve;

fn main() {
    let args: Vec<String> = std::env::args().collect();

    if args.iter().any(|a| a == "--help" || a == "-h") {
        eprintln!(
            "Usage: chabaka_cli --kb <sqlite_path> [--rows N] [--cols N] [--seed N] [--timeout ms]"
        );
        return;
    }

    let kb_path = match get_arg(&args, "--kb") {
        Some(p) => p,
        None => {
            eprintln!("Usage: chabaka_cli --kb <sqlite_path> [--rows N] [--cols N] [--seed N] [--timeout ms]");
            std::process::exit(1);
        }
    };

    let rows: usize = get_arg(&args, "--rows")
        .and_then(|s| s.parse().ok())
        .unwrap_or(8);
    let cols: usize = get_arg(&args, "--cols")
        .and_then(|s| s.parse().ok())
        .unwrap_or(8);
    let seed: u64 = get_arg(&args, "--seed")
        .and_then(|s| s.parse().ok())
        .unwrap_or(42);
    let timeout_ms: u32 = get_arg(&args, "--timeout")
        .and_then(|s| s.parse().ok())
        .unwrap_or(30000);

    println!("Loading KB from: {}", kb_path);
    let t0 = Instant::now();
    let kb = match KbCompact::load(&kb_path) {
        Ok(kb) => kb,
        Err(e) => {
            eprintln!("KB load error: {}", e);
            std::process::exit(1);
        }
    };
    println!(
        "KB loaded: {} entries in {:.1}ms",
        kb.len(),
        t0.elapsed().as_secs_f64() * 1000.0
    );

    // Construire un patron selon les dimensions
    let pattern_kinds = make_pattern(rows, cols);

    let config = ConfigInput {
        rows: rows as u16,
        cols: cols as u16,
        seed,
        deadline_ms: timeout_ms,
        max_retries: 10,
        pattern_kinds,
    };

    println!(
        "Solving {}x{} grid (seed={}, timeout={}ms)...",
        rows, cols, seed, timeout_ms
    );
    let t1 = Instant::now();
    let result = solve(&config, &kb);
    let elapsed = t1.elapsed();

    match result {
        Ok(output) if output.status == 0 => {
            println!("SOLVED in {:.1}ms", elapsed.as_secs_f64() * 1000.0);
            if let Some(placed) = &output.placed {
                println!("Words placed: {}", placed.len());
            }
            if let Some(cells) = &output.cells {
                print_grid(rows, cols, cells);
            }
        }
        Ok(output) => {
            println!(
                "NO SOLUTION in {:.1}ms (status={}): {:?}",
                elapsed.as_secs_f64() * 1000.0,
                output.status,
                output.error_message
            );
            std::process::exit(1);
        }
        Err(e) => {
            eprintln!("Error: {}", e);
            std::process::exit(1);
        }
    }
}

fn get_arg(args: &[String], flag: &str) -> Option<String> {
    args.windows(2)
        .find(|w| w[0] == flag)
        .map(|w| w[1].clone())
}

/// Génère un patron "L-grid" standard : top-row = clues, left-col = clues.
fn make_pattern(rows: usize, cols: usize) -> Vec<u8> {
    let mut kinds = vec![0u8; rows * cols];
    kinds[0] = 2; // (0,0) = blocker
    for c in 1..cols {
        kinds[c] = 1; // Ligne 0 = clues
    }
    for r in 1..rows {
        kinds[r * cols] = 1; // Col 0 = clues
    }
    kinds
}

fn print_grid(rows: usize, cols: usize, cells: &[CellOutput]) {
    println!("\nGrille ({} × {}) :", rows, cols);
    for r in 0..rows {
        let row: String = (0..cols)
            .map(|c| {
                let cell = &cells[r * cols + c];
                match (cell.kind, &cell.letter) {
                    (0, Some(l)) => format!("[{}]", l),
                    (0, None) => "[?]".to_string(),
                    (1, _) => " # ".to_string(),
                    _ => " . ".to_string(),
                }
            })
            .collect();
        println!("{}", row);
    }
}
