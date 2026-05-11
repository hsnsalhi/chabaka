// chabaka_engine — stub FFI (V2 étape 1c)
// Surface C ABI selon spec V2-FFI-Rust-spec.md §6.
// Le puzzle agent implémentera le vrai solver dans les modules solver/, kb.rs, etc.
//
// Règle fondamentale : panic = "abort" (Cargo.toml release), jamais d'unwind across FFI.

use std::ffi::CStr;
use std::os::raw::{c_char, c_int};

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
// Opaque handle
// ---------------------------------------------------------------------------

/// Struct opaque. Le puzzle agent peuplera les champs kb/solver.
pub struct ChabakaEngine {
    _version: &'static str,
}

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
// API FFI
// ---------------------------------------------------------------------------

/// Crée un engine. `kb_path_utf8` : chemin absolu (zero-terminated) vers le .sqlite.
/// Renvoie NULL si init KB échoue.
#[no_mangle]
pub extern "C" fn engine_create(kb_path_utf8: *const c_char) -> *mut ChabakaEngine {
    if kb_path_utf8.is_null() {
        set_last_error("kb_path_utf8 is NULL");
        return std::ptr::null_mut();
    }

    // Stub : on ignore le chemin ; le puzzle agent ouvrira rusqlite ici.
    let _path = unsafe { CStr::from_ptr(kb_path_utf8) }.to_string_lossy();

    let engine = Box::new(ChabakaEngine {
        _version: env!("CARGO_PKG_VERSION"),
    });
    Box::into_raw(engine)
}

/// Détruit l'engine et libère toute mémoire owned.
#[no_mangle]
pub extern "C" fn engine_destroy(engine: *mut ChabakaEngine) {
    if engine.is_null() {
        return;
    }
    // SAFETY: engine a été créé par engine_create (Box::into_raw)
    let _ = unsafe { Box::from_raw(engine) };
}

/// Solve (stub : retourne immédiatement STATUS_NO_SOLUTION).
/// Le puzzle agent remplacera cette implémentation par le vrai solver.
///
/// # Safety
/// - `engine` doit être un pointeur valide créé par `engine_create`.
/// - `input_msgpack` doit être un buffer valide de longueur `input_len`.
/// - `out_ptr` et `out_len` doivent être des pointeurs non-NULL vers des slots écrits par Rust.
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

    // Stub : indique qu'il n'y a pas encore de solution (le solver est à implémenter).
    set_last_error("stub: solver not yet implemented — puzzle agent will fill this");
    STATUS_NO_SOLUTION
}

/// Libère un buffer retourné par `engine_solve`.
///
/// # Safety
/// `ptr` doit avoir été alloué par Rust via `engine_solve` (Vec::into_raw_parts).
#[no_mangle]
pub extern "C" fn engine_free_buffer(ptr: *mut u8, len: usize) {
    if ptr.is_null() || len == 0 {
        return;
    }
    // SAFETY: ce buffer a été alloué par Rust dans engine_solve
    let _ = unsafe { Vec::from_raw_parts(ptr, len, len) };
}

/// Retourne un message d'erreur thread-local (ou NULL). Buffer statique interne.
/// Valide jusqu'au prochain appel FFI.
#[no_mangle]
pub extern "C" fn engine_last_error() -> *const c_char {
    LAST_ERROR.with(|e| {
        e.borrow()
            .as_ref()
            .map(|s| s.as_ptr())
            .unwrap_or(std::ptr::null())
    })
}

/// Version de la lib pour audit. Static.
#[no_mangle]
pub extern "C" fn engine_version() -> *const c_char {
    // SAFETY: cette string est 'static et null-terminated
    static VERSION: &[u8] = b"0.1.0-stub-2026-05-11\0";
    VERSION.as_ptr() as *const c_char
}

/// Fonction de ping simple — utile pour valider que le FFI charge correctement
/// depuis Dart avant d'appeler des fonctions complexes.
#[no_mangle]
pub extern "C" fn engine_ping() -> c_int {
    42
}

// ---------------------------------------------------------------------------
// Tests unitaires Rust (pas d'integration FFI ici — voir tests/)
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
    fn test_create_destroy() {
        let path = CString::new("/tmp/fake.sqlite").unwrap();
        let handle = engine_create(path.as_ptr());
        assert!(!handle.is_null());
        engine_destroy(handle);
    }

    #[test]
    fn test_create_null_path() {
        let handle = engine_create(std::ptr::null());
        assert!(handle.is_null());
    }

    #[test]
    fn test_solve_stub_returns_no_solution() {
        let path = CString::new("/tmp/fake.sqlite").unwrap();
        let handle = engine_create(path.as_ptr());
        assert!(!handle.is_null());

        let input = b"\x80"; // msgpack empty map (stub accepté)
        let mut out_ptr: *mut u8 = std::ptr::null_mut();
        let mut out_len: usize = 0;

        let status = engine_solve(
            handle,
            input.as_ptr(),
            input.len(),
            &mut out_ptr,
            &mut out_len,
        );

        assert_eq!(status, STATUS_NO_SOLUTION);
        assert!(out_ptr.is_null());

        engine_destroy(handle);
    }

    #[test]
    fn test_version_not_null() {
        let v = engine_version();
        assert!(!v.is_null());
        let s = unsafe { CStr::from_ptr(v) }.to_str().unwrap();
        assert!(s.starts_with("0.1.0"));
    }
}
