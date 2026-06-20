//! stmata — the Stata-facing plugin. The Stata ABI lives in `shim.c`; this file
//! is plain Rust and calls `topica_core` (a normal dependency, no FFI).
//!
//! Operations are dispatched on the first plugin argument:
//!   `plugin call stmata <text> <theta1..thetaK>, fit <K> <seed> <em_iters>`
//!   `plugin call stmata <var> [<out>]`            (no/other args -> M0 hello)

use std::ffi::{CStr, CString};
use std::os::raw::{c_char, c_double, c_int};
use std::panic::{catch_unwind, AssertUnwindSafe};

use rand::SeedableRng;
use rand_chacha::ChaCha8Rng;
use topica_core::corpus::{from_texts, LoadOptions};
use topica_core::ctm::{fit_ctm, GammaPrior};
use topica_core::{effects, inspect};

// Defined in shim.c (thin wrappers over the SF_* macros).
extern "C" {
    fn rs_display(s: *const c_char);
    fn rs_error(s: *const c_char);
    fn rs_nobs() -> c_int;
    fn rs_nvars() -> c_int;
    fn rs_in1() -> c_int;
    fn rs_in2() -> c_int;
    fn rs_vdata(var: c_int, obs: c_int, d: *mut c_double) -> c_int;
    fn rs_vstore(var: c_int, obs: c_int, v: c_double) -> c_int;
    fn rs_is_missing(v: c_double) -> c_int;
    fn rs_ifobs(obs: c_int) -> c_int;
    fn rs_scal_save(name: *const c_char, v: c_double) -> c_int;
    fn rs_mat_store(name: *const c_char, r: c_int, c: c_int, v: c_double) -> c_int;
    fn rs_sdatalen(var: c_int, obs: c_int) -> c_int;
    fn rs_var_is_strl(var: c_int) -> c_int;
    fn rs_sdata(var: c_int, obs: c_int, buf: *mut c_char) -> c_int;
    fn rs_strldata(var: c_int, obs: c_int, buf: *mut c_char, len: c_int) -> c_int;
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
fn save_scalar(name: &str, v: f64) {
    if let Ok(c) = CString::new(name) {
        unsafe { rs_scal_save(c.as_ptr(), v) };
    }
}
fn mat_store(name: &str, r: usize, c: usize, v: f64) {
    if let Ok(cn) = CString::new(name) {
        unsafe { rs_mat_store(cn.as_ptr(), r as c_int, c as c_int, v) };
    }
}

/// Read a (var, obs) string value into an owned String (str# or strL).
fn read_string(var: c_int, obs: c_int) -> String {
    let len = unsafe { rs_sdatalen(var, obs) };
    if len <= 0 {
        return String::new();
    }
    let cap = len as usize + 2;
    let mut buf = vec![0u8; cap];
    let rc = unsafe {
        if rs_var_is_strl(var) != 0 {
            rs_strldata(var, obs, buf.as_mut_ptr() as *mut c_char, cap as c_int)
        } else {
            rs_sdata(var, obs, buf.as_mut_ptr() as *mut c_char)
        }
    };
    if rc != 0 {
        return String::new();
    }
    let end = buf.iter().position(|&b| b == 0).unwrap_or(buf.len());
    String::from_utf8_lossy(&buf[..end]).into_owned()
}

/// Collect the plugin's comma-args (`argv`) into owned Strings.
fn args(argc: c_int, argv: *const *const c_char) -> Vec<String> {
    let mut v = Vec::new();
    if argv.is_null() {
        return v;
    }
    for i in 0..argc as isize {
        let p = unsafe { *argv.offset(i) };
        if !p.is_null() {
            v.push(unsafe { CStr::from_ptr(p) }.to_string_lossy().into_owned());
        }
    }
    v
}

/// Entry called by shim.c's `stata_call`. Panics caught at the boundary.
#[no_mangle]
pub extern "C" fn stmata_entry(argc: c_int, argv: *const *const c_char) -> c_int {
    match catch_unwind(AssertUnwindSafe(|| {
        let a = args(argc, argv);
        match a.first().map(String::as_str) {
            Some("fit") => fit_op(&a),
            _ => hello_op(),
        }
    })) {
        Ok(rc) => rc,
        Err(_) => {
            err("stmata: internal error (Rust panic)\n");
            198
        }
    }
}

/// M1: fit an STM (no covariates yet) and write topic proportions back.
/// Varlist: text var (1) followed by K theta vars (2..K+1).
/// Args: `fit <K> [seed=42] [em_iters=100]`.
fn fit_op(a: &[String]) -> c_int {
    let k: usize = a.get(1).and_then(|s| s.parse().ok()).unwrap_or(0);
    let seed: u64 = a.get(2).and_then(|s| s.parse().ok()).unwrap_or(42);
    let em_iters: usize = a.get(3).and_then(|s| s.parse().ok()).unwrap_or(100);
    let nprev: usize = a.get(4).and_then(|s| s.parse().ok()).unwrap_or(0);
    if k < 2 {
        err("stmata: k must be >= 2 (usage: fit <K> [seed] [em_iters] [nprev])\n");
        return 198;
    }

    let nvars = unsafe { rs_nvars() } as usize;
    if nvars < k + 1 + nprev {
        err(&format!(
            "stmata: varlist needs 1 text + {} theta + {} prevalence vars (got {})\n",
            k, nprev, nvars
        ));
        return 198;
    }

    let (i1, i2) = unsafe { (rs_in1(), rs_in2()) };
    let mut texts: Vec<String> = Vec::new();
    let mut names: Vec<String> = Vec::new();
    let mut obs_of_offset: Vec<c_int> = Vec::new(); // offset -> Stata obs (honoring if/in)
    let mut off = 0usize;
    for obs in i1..=i2 {
        if unsafe { rs_ifobs(obs) } == 0 {
            continue;
        }
        texts.push(read_string(1, obs));
        names.push(off.to_string()); // 0-based offset within the selected sample
        obs_of_offset.push(obs);
        off += 1;
    }

    let opts = LoadOptions::default();
    let corpus = match from_texts(&texts, Some(&names), None, &opts) {
        Ok(c) => c,
        Err(e) => {
            err(&format!("stmata: tokenize error: {}\n", e));
            return 198;
        }
    };
    let d = corpus.num_docs();
    let v = corpus.num_types();
    if d < 2 || v < 2 {
        err("stmata: too few documents/terms after tokenization\n");
        return 198;
    }
    say(&format!(
        "stmata: corpus = {} docs, {} terms, {} tokens; fitting K={} ...\n",
        d,
        v,
        corpus.total_tokens(),
        k
    ));

    // Prevalence design matrix (intercept + covariates), aligned to corpus docs.
    let prevalence: Option<Vec<Vec<f64>>> = if nprev > 0 {
        let mut x = Vec::with_capacity(d);
        for name in &corpus.doc_names {
            let off: usize = name.parse().unwrap_or(usize::MAX);
            let obs = obs_of_offset.get(off).copied().unwrap_or(i1);
            let mut row = Vec::with_capacity(1 + nprev);
            row.push(1.0); // intercept
            for p in 0..nprev {
                let mut val: c_double = 0.0;
                unsafe { rs_vdata((2 + k + p) as c_int, obs, &mut val) };
                row.push(val);
            }
            x.push(row);
        }
        say(&format!(
            "stmata: prevalence design = intercept + {} covariate(s)\n",
            nprev
        ));
        Some(x)
    } else {
        None
    };
    let want_effects = nprev > 0;

    let mut rng = ChaCha8Rng::seed_from_u64(seed);
    let model = fit_ctm(
        &corpus.docs,
        k,
        v,
        em_iters,
        1e-5,
        0.0,
        prevalence.as_deref(), // prevalence covariates (#3a)
        None,                  // no content (later)
        true,                  // spectral init (STM default)
        None,
        GammaPrior::Pooled,
        want_effects, // keep_nu: needed for estimateEffect (#3b)
        false,        // diagonal
        &mut rng,
    );
    let theta = model.doc_topics(); // d x k

    // Write theta back: surviving corpus doc -> original obs via doc_names offset.
    for (di, name) in corpus.doc_names.iter().enumerate() {
        let off: usize = match name.parse() {
            Ok(x) => x,
            Err(_) => continue,
        };
        if off >= obs_of_offset.len() {
            continue;
        }
        let obs = obs_of_offset[off];
        for t in 0..k {
            unsafe { rs_vstore((2 + t) as c_int, obs, theta[di][t]) };
        }
    }

    // FREX labels + coherence/exclusivity diagnostics (topica_core::inspect).
    let frex = inspect::frex_scores(&model.beta, &corpus.total_freqs, 0.5);
    let labels = inspect::top_words(&frex, 8usize.min(v));
    let mm = 10usize.min(v);
    let coh = inspect::semantic_coherence(&model.beta, &corpus.docs, mm);
    let excl = inspect::exclusivity(&model.beta, mm, 0.7);
    let mean_coh = coh.iter().sum::<f64>() / k as f64;
    let mean_excl = excl.iter().sum::<f64>() / k as f64;

    save_scalar("stmata_K", k as f64);
    save_scalar("stmata_V", v as f64);
    save_scalar("stmata_D", d as f64);
    save_scalar("stmata_bound", model.bound);
    save_scalar("stmata_iters", model.em_iters_run as f64);
    save_scalar("stmata_coh", mean_coh);
    save_scalar("stmata_excl", mean_excl);

    say("stmata: top FREX words per topic [coherence / exclusivity] --\n");
    for t in 0..k {
        let words: Vec<&str> = labels[t]
            .iter()
            .map(|&w| corpus.id_to_word[w].as_str())
            .collect();
        say(&format!(
            "  topic {:>2} [coh {:>7.2}, excl {:>6.2}]: {}\n",
            t + 1,
            coh[t],
            excl[t],
            words.join(" ")
        ));
    }
    // estimateEffect: covariate effects on each topic's proportions, by the
    // method of composition (fills the Stata matrices stmata_b / stmata_se,
    // which the ado pre-creates as k x nprev).
    if want_effects {
        if let Some(xref) = prevalence.as_deref() {
            let mut eff_rng = ChaCha8Rng::seed_from_u64(seed ^ 0x9E37_79B9_7F4A_7C15);
            let nsims = 100usize;
            let pdim = nprev + 1; // intercept + covariates
            // Fill the e(b) row (1 x k*nprev) and the block-diagonal e(V).
            for t in 0..k {
                let (coef, vcov) = effects::estimate_effect_topic(
                    &model.lambda, &model.nu, xref, t, nsims, &mut eff_rng,
                );
                for ci in 1..=nprev {
                    let r = (t * nprev + (ci - 1) + 1) as c_int; // 1-based
                    mat_store("stmata_eb", 1, r as usize, coef[ci]);
                    for cj in 1..=nprev {
                        let c = (t * nprev + (cj - 1) + 1) as c_int;
                        mat_store("stmata_eV", r as usize, c as usize, vcov[ci * pdim + cj]);
                    }
                }
            }
            say(&format!(
                "stmata: estimateEffect done ({} term(s), {} draws, method of composition)\n",
                nprev, nsims
            ));
        }
    }

    say(&format!(
        "stmata: done. bound={:.2}, iters={}, mean coherence={:.2}, mean exclusivity={:.2}\n",
        model.bound, model.em_iters_run, mean_coh, mean_excl
    ));
    0
}

/// M0 smoke test: read var 1, mean it, write 2*x into var 2, save a scalar.
fn hello_op() -> c_int {
    let nobs = unsafe { rs_nobs() };
    let nvars = unsafe { rs_nvars() };
    say(&format!(
        "stmata: hello from Rust. obs={}, vars in varlist={}\n",
        nobs, nvars
    ));
    if nvars < 1 {
        err("stmata: pass at least one variable (the input)\n");
        return 198;
    }

    let (i1, i2) = unsafe { (rs_in1(), rs_in2()) };
    let mut sum = 0.0_f64;
    let mut n = 0_i64;
    for obs in i1..=i2 {
        let mut x: c_double = 0.0;
        let rc = unsafe { rs_vdata(1, obs, &mut x as *mut c_double) };
        if rc != 0 {
            return rc;
        }
        if unsafe { rs_is_missing(x) } != 0 {
            continue;
        }
        sum += x;
        n += 1;
        if nvars >= 2 {
            let wrc = unsafe { rs_vstore(2, obs, x * 2.0) };
            if wrc != 0 {
                return wrc;
            }
        }
    }
    let mean = if n > 0 { sum / n as f64 } else { 0.0 };
    save_scalar("stmata_mean", mean);
    say(&format!(
        "stmata: read {} non-missing obs, mean={:.6}, saved scalar stmata_mean\n",
        n, mean
    ));
    0
}
