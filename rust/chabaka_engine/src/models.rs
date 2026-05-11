/// Data model Rust pour le solver Chabaka.
///
/// Miroir des types Dart (topology.dart, kb_repository.dart) mais optimisés
/// pour le backtracking : indices entiers, pas de String inutiles dans la
/// boucle chaude.

use serde::{Deserialize, Serialize};

// ---------------------------------------------------------------------------
// Input MessagePack (Dart → Rust)
// ---------------------------------------------------------------------------

/// Input sérialisé en MessagePack envoyé par Dart via FFI.
///
/// `pattern_kinds` : tableau row-major de longueur `rows * cols`.
/// Valeurs : 0 = letter, 1 = clue, 2 = blocker.
#[derive(Debug, Deserialize)]
pub struct ConfigInput {
    pub rows: u16,
    pub cols: u16,
    pub seed: u64,
    pub deadline_ms: u32,
    pub max_retries: u8,
    pub pattern_kinds: Vec<u8>,
}

// ---------------------------------------------------------------------------
// Output MessagePack (Rust → Dart)
// ---------------------------------------------------------------------------

#[derive(Debug, Serialize)]
pub struct GridOutput {
    pub status: u8, // 0 = OK, 1 = NoSolution, 2+ = erreur
    #[serde(skip_serializing_if = "Option::is_none")]
    pub cells: Option<Vec<CellOutput>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub placed: Option<Vec<PlacedEntry>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error_message: Option<String>,
}

impl GridOutput {
    pub fn no_solution() -> Self {
        GridOutput {
            status: 1,
            cells: None,
            placed: None,
            error_message: Some("no solution found".into()),
        }
    }

    pub fn error(msg: impl Into<String>) -> Self {
        GridOutput {
            status: 2,
            cells: None,
            placed: None,
            error_message: Some(msg.into()),
        }
    }
}

/// Une cellule dans la grille résultat.
#[derive(Debug, Serialize)]
pub struct CellOutput {
    pub kind: u8, // 0 = letter, 1 = clue
    #[serde(skip_serializing_if = "Option::is_none")]
    pub letter: Option<String>, // si kind=0 : lettre arabe isolée
}

/// Un mot placé dans la grille (pour reconstruire les clues côté Dart).
#[derive(Debug, Serialize)]
pub struct PlacedEntry {
    pub kb_id: u32,
    pub slot_row: u16,
    pub slot_col: u16,
    /// 0 = horizontal, 1 = vertical
    pub dir: u8,
    pub len: u8,
}

// ---------------------------------------------------------------------------
// Représentation interne du solver
// ---------------------------------------------------------------------------

/// Direction d'un slot.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum Direction {
    Horizontal,
    Vertical,
}

/// Un slot = séquence de cases lettre à remplir.
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub struct Slot {
    pub direction: Direction,
    pub start_row: u8,
    pub start_col: u8,
    pub length: u8,
}

impl Slot {
    /// Positions (row, col) de chaque case du slot, dans l'ordre.
    pub fn positions(&self) -> Vec<(u8, u8)> {
        (0..self.length)
            .map(|i| match self.direction {
                Direction::Horizontal => (self.start_row, self.start_col + i),
                Direction::Vertical => (self.start_row + i, self.start_col),
            })
            .collect()
    }
}

/// Type de cellule dans le patron d'entrée.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CellKind {
    Letter,
    Clue,
    Blocker,
}

impl CellKind {
    pub fn from_u8(v: u8) -> Self {
        match v {
            0 => CellKind::Letter,
            1 => CellKind::Clue,
            _ => CellKind::Blocker,
        }
    }
}

/// Contrainte lettre×position pour le lookup KB.
#[derive(Debug, Clone)]
pub struct LetterConstraint {
    /// Index 0-based dans le mot.
    pub position: usize,
    /// Lettre arabe normalisée (codepoint Unicode).
    pub letter: char,
}

/// Entrée KB allégée — uniquement ce dont le solver a besoin.
#[derive(Debug, Clone)]
pub struct KbEntryLite {
    pub id: u32,
    /// Mot normalisé (sans diacritiques, ا/أ/إ/آ→ا, ة→ه, ى→ي).
    /// Stocké comme Vec<char> pour O(1) access par position.
    pub chars: Vec<char>,
}

// ---------------------------------------------------------------------------
// Codes d'erreur (miroir de la surface C ABI)
// ---------------------------------------------------------------------------

#[derive(Debug, thiserror::Error)]
pub enum EngineError {
    #[error("KB open failed: {0}")]
    KbOpenFailed(String),
    #[error("Invalid input: {0}")]
    InvalidInput(String),
    #[error("No solution found (timeout or exhausted)")]
    NoSolution,
    #[error("Internal error: {0}")]
    Internal(String),
}
