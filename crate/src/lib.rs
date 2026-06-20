//! stmata — the Stata-facing plugin. The Stata ABI lives in `shim.c`; this file
//! is plain Rust. At M1 it will call `topica_core` (a normal Rust dependency,
//! no FFI) to fit the model and hand results back through the SF_* wrappers.
//!
//! M0 (this version) is a toolchain/FFI smoke test: read a variable, compute its
//! mean, optionally write 2*x into a second variable, and save a Stata scalar.

use std::ffi::CString;
use std::os::raw::{c_char, c_double, c_int};
use std::panic::{catch_unwind, AssertUnwindSafe};

// Defined in shim.c (thin wrappers over the SF_* macros).
extern "C" {
    fn rs_display(s: *const c_char);
    fn rs_error(s: *const c_char);
    fn rs_nobs() -> c_int;
    fn rs_nvars() -> c_int;
    fn rs_in1() -> c_int;
    fn rs_in2() -> c_int;
    fn rs_vdata(i: c_int, j: c_int, d: *mut c_double) -> c_int;
    fn rs_vstore(i: c_int, j: c_int, v: c_double) -> c_int;
    fn rs_is_missing(v: c_double) -> c_int;
    fn rs_scal_save(name: *const c_char, v: c_double) -> c_int;
}

fn say(s: &str) {
    if let Ok(c) = CString::new(s) {
        unsafe { rs_display(c.as_ptr()) };
    }
}
fn err(s: &str) {
    if let Ok(c) = CString::new(s) {
        unsafe { rs_error(c.as_ptr()) };
    }
}

/// Entry called by shim.c's `stata_call`. Returns a Stata return code (0 = ok).
/// Panics are caught here so they never unwind across the C boundary.
#[no_mangle]
pub extern "C" fn stmata_entry(argc: c_int, argv: *const *const c_char) -> c_int {
    match catch_unwind(AssertUnwindSafe(|| run(argc, argv))) {
        Ok(rc) => rc,
        Err(_) => {
            err("stmata: internal error (Rust panic)\n");
            198
        }
    }
}

fn run(_argc: c_int, _argv: *const *const c_char) -> c_int {
    let nobs = unsafe { rs_nobs() };
    let nvars = unsafe { rs_nvars() };
    say(&format!(
        "stmata: hello from Rust. obs={}, vars in varlist={}\n",
        nobs, nvars
    ));

    if nvars < 1 {
        err("stmata: pass at least one variable (the input)\n");
        return 198; // invalid syntax
    }

    let (i1, i2) = unsafe { (rs_in1(), rs_in2()) };
    let mut sum = 0.0_f64;
    let mut n = 0_i64;
    for i in i1..=i2 {
        let mut v: c_double = 0.0;
        let rc = unsafe { rs_vdata(i, 1, &mut v as *mut c_double) };
        if rc != 0 {
            return rc;
        }
        if unsafe { rs_is_missing(v) } != 0 {
            continue;
        }
        sum += v;
        n += 1;
        // If a second variable is supplied, write 2*input into it (write round-trip).
        if nvars >= 2 {
            let rc = unsafe { rs_vstore(i, 2, v * 2.0) };
            if rc != 0 {
                return rc;
            }
        }
    }

    let mean = if n > 0 { sum / n as f64 } else { 0.0 };
    if let Ok(name) = CString::new("stmata_mean") {
        unsafe { rs_scal_save(name.as_ptr(), mean) };
    }
    say(&format!(
        "stmata: read {} non-missing obs, mean={:.6}, saved scalar stmata_mean\n",
        n, mean
    ));
    0
}
