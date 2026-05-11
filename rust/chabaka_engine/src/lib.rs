// chabaka_engine — moteur de génération de grilles مسهمة en Rust.
// Surface C ABI selon spec V2-FFI-Rust-spec.md §6.
//
// Règle fondamentale : panic = "abort" en release (Cargo.toml),
// jamais d'unwind across FFI.

mod ffi_helpers;
pub mod kb;
pub mod models;
pub mod normalizer;
pub mod solver;

use std::ffi::CStr;
use std::os::raw::{c_char, c_int};

use crate::kb::KbCompact;
use crate::models::{ConfigInput, EngineError, GridOutput};

// ---------------------------------------------------------------------------
// Codes d'erreur (ChabakaStatus) — spec §6
// ---------------------------------------------------------------------------
pub const STATUS_OK: i32 = 0;
pub const STATUS_NO_SOLUTION: i32 = 1;
pub const STATUS_INVALID_INPUT: i32 = 2;
pub const STATUS_KB_OPEN_FAILED: i32 = 3;
pub const STATUS_INTERNAL_PANIC: i32 = 4;
pub const STATUS_HANDLE_INVALID: i32 = 5;

// ---------------------------------------------------------------------------
// Thread-local pour engine_last_error()
// ---------------------------------------------------------------------------

use std::cell::RefCell;

thread_local! {
    static LAST_ERROR: RefCell<Option<std::ffi::CString>> = RefCell::new(None);
}

fn set_last_error(msg: &str) {
    LAST_ERROR.with(|e| {
        *e.borrow_mut() = std::ffi::CString::new(msg).ok();
    });
}

// ---------------------------------------------------------------------------
// Opaque handle
// ---------------------------------------------------------------------------

/// Handle opaque exposé côté Dart. Wraps KbCompact chargé en RAM.
pub struct ChabakaEngine {
    kb: KbCompact,
}

// ---------------------------------------------------------------------------
// API FFI
// ---------------------------------------------------------------------------

/// Crée un engine. `kb_path_utf8` : chemin absolu (zero-terminated) vers le .sqlite.
///
/// Ouvre la DB SQLite, charge la KB en RAM, ferme la connexion.
/// Retourne NULL si l'init KB échoue (consulter `engine_last_error()`).
///
/// # Safety
/// `kb_path_utf8` doit être un pointeur valide vers une string C null-terminée UTF-8.
#[no_mangle]
pub extern "C" fn engine_create(kb_path_utf8: *const c_char) -> *mut ChabakaEngine {
    if kb_path_utf8.is_null() {
        set_last_error("kb_path_utf8 is NULL");
        return std::ptr::null_mut();
    }

    let path = match unsafe { CStr::from_ptr(kb_path_utf8) }.to_str() {
        Ok(s) => s,
        Err(e) => {
            set_last_error(&format!("kb_path_utf8 is not valid UTF-8: {}", e));
            return std::ptr::null_mut();
        }
    };

    match KbCompact::load(path) {
        Ok(kb) => {
            let engine = Box::new(ChabakaEngine { kb });
            Box::into_raw(engine)
        }
        Err(e) => {
            set_last_error(&e.to_string());
            std::ptr::null_mut()
        }
    }
}

/// Détruit l'engine et libère toute mémoire owned.
///
/// # Safety
/// `engine` doit être un pointeur valide créé par `engine_create`, ou NULL.
#[no_mangle]
pub extern "C" fn engine_destroy(engine: *mut ChabakaEngine) {
    if engine.is_null() {
        return;
    }
    // SAFETY: engine a été créé par engine_create (Box::into_raw)
    let _ = unsafe { Box::from_raw(engine) };
}

/// Résout la grille.
///
/// - `input_msgpack` : blob MessagePack alloué côté Dart (Rust ne free pas).
/// - `out_ptr` / `out_len` : Rust alloue, Dart doit appeler `engine_free_buffer()`.
/// - `out_ptr` est NULL en cas d'erreur non-récupérable.
///
/// Retour :
///   0 = OK (grille dans out_ptr)
///   1 = NoSolution (timeout ou exhausté)
///   2 = InvalidInput
///   3 = KbOpenFailed (ne devrait pas arriver ici)
///   5 = HandleInvalid
///
/// # Safety
/// - `engine` doit être un pointeur valide créé par `engine_create`.
/// - `input_msgpack` doit être un buffer valide de longueur `input_len`.
/// - `out_ptr` et `out_len` doivent être des pointeurs non-NULL.
#[no_mangle]
pub extern "C" fn engine_solve(
    engine: *mut ChabakaEngine,
    input_msgpack: *const u8,
    input_len: usize,
    out_ptr: *mut *mut u8,
    out_len: *mut usize,
) -> i32 {
    if engine.is_null() {
        set_last_error("engine handle is NULL");
        return STATUS_HANDLE_INVALID;
    }
    if input_msgpack.is_null() || input_len == 0 {
        set_last_error("input_msgpack is NULL or empty");
        return STATUS_INVALID_INPUT;
    }
    if out_ptr.is_null() || out_len.is_null() {
        set_last_error("out_ptr or out_len is NULL");
        return STATUS_INVALID_INPUT;
    }

    // SAFETY: pointeurs validés ci-dessus
    unsafe {
        *out_ptr = std::ptr::null_mut();
        *out_len = 0;
    }

    // Désérialiser l'input MessagePack
    let input_slice = unsafe { std::slice::from_raw_parts(input_msgpack, input_len) };
    let config: ConfigInput = match rmp_serde::from_slice(input_slice) {
        Ok(c) => c,
        Err(e) => {
            set_last_error(&format!("MessagePack deserialization failed: {}", e));
            return STATUS_INVALID_INPUT;
        }
    };

    // Accéder à la KB via le handle
    let engine_ref = unsafe { &*engine };

    // Lancer le solver
    let output = match solver::solve(&config, &engine_ref.kb) {
        Ok(o) => o,
        Err(EngineError::InvalidInput(msg)) => {
            set_last_error(&msg);
            return STATUS_INVALID_INPUT;
        }
        Err(EngineError::KbOpenFailed(msg)) => {
            set_last_error(&msg);
            return STATUS_KB_OPEN_FAILED;
        }
        Err(EngineError::NoSolution) => GridOutput::no_solution(),
        Err(EngineError::Internal(msg)) => {
            set_last_error(&msg);
            return STATUS_INTERNAL_PANIC;
        }
    };

    // Sérialiser l'output en MessagePack
    let output_bytes = match rmp_serde::to_vec_named(&output) {
        Ok(b) => b,
        Err(e) => {
            set_last_error(&format!("MessagePack serialization failed: {}", e));
            return STATUS_INTERNAL_PANIC;
        }
    };

    let status = output.status as i32;

    // Transférer ownership du buffer à Dart
    let len = output_bytes.len();
    let ptr = {
        let mut v = output_bytes;
        v.shrink_to_fit();
        let ptr = v.as_mut_ptr();
        std::mem::forget(v);
        ptr
    };

    unsafe {
        *out_ptr = ptr;
        *out_len = len;
    }

    status
}

/// Libère un buffer retourné par `engine_solve`.
///
/// # Safety
/// `ptr` doit avoir été alloué par Rust via `engine_solve`.
/// `len` doit correspondre exactement à la longueur retournée.
#[no_mangle]
pub extern "C" fn engine_free_buffer(ptr: *mut u8, len: usize) {
    if ptr.is_null() || len == 0 {
        return;
    }
    // SAFETY: ce buffer a été alloué par Rust dans engine_solve
    let _ = unsafe { Vec::from_raw_parts(ptr, len, len) };
}

/// Retourne un message d'erreur thread-local (ou NULL).
/// Buffer valide jusqu'au prochain appel FFI.
#[no_mangle]
pub extern "C" fn engine_last_error() -> *const c_char {
    LAST_ERROR.with(|e| {
        e.borrow()
            .as_ref()
            .map(|s| s.as_ptr())
            .unwrap_or(std::ptr::null())
    })
}

/// Version de la lib pour audit.
#[no_mangle]
pub extern "C" fn engine_version() -> *const c_char {
    static VERSION: &[u8] = b"0.1.0-2026-05-11\0";
    VERSION.as_ptr() as *const c_char
}

/// Ping de sanité — retourne 42 si le FFI charge correctement.
#[no_mangle]
pub extern "C" fn engine_ping() -> c_int {
    42
}

// ---------------------------------------------------------------------------
// Tests unitaires
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;
    use std::ffi::CString;

    #[test]
    fn test_ping() {
        assert_eq!(engine_ping(), 42);
    }

    #[test]
    fn test_create_null_path() {
        let handle = engine_create(std::ptr::null());
        assert!(handle.is_null());
        // engine_last_error doit retourner un message
        let err = engine_last_error();
        assert!(!err.is_null());
    }

    #[test]
    fn test_create_invalid_path() {
        let path = CString::new("/nonexistent/path/fake.sqlite").unwrap();
        let handle = engine_create(path.as_ptr());
        assert!(handle.is_null());
        let err = engine_last_error();
        assert!(!err.is_null());
    }

    #[test]
    fn test_destroy_null() {
        // Ne doit pas crasher
        engine_destroy(std::ptr::null_mut());
    }

    #[test]
    fn test_version_format() {
        let v = engine_version();
        assert!(!v.is_null());
        let s = unsafe { CStr::from_ptr(v) }.to_str().unwrap();
        assert!(s.starts_with("0.1.0-"));
    }

    #[test]
    fn test_free_buffer_null() {
        // Ne doit pas crasher
        engine_free_buffer(std::ptr::null_mut(), 0);
    }

    #[test]
    fn test_solve_with_null_engine() {
        let input = b"\x80"; // msgpack empty map
        let mut out_ptr: *mut u8 = std::ptr::null_mut();
        let mut out_len: usize = 0;
        let status = engine_solve(
            std::ptr::null_mut(),
            input.as_ptr(),
            input.len(),
            &mut out_ptr,
            &mut out_len,
        );
        assert_eq!(status, STATUS_HANDLE_INVALID);
    }
}
