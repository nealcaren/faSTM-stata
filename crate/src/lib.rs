//! fastm — the Stata-facing plugin. The Stata ABI lives in `shim.c`; this file
//! is plain Rust and calls `topica_core` (a normal dependency, no FFI).
//!
//! Operations are dispatched on the first plugin argument:
//!   `plugin call fastm <text> <theta1..thetaK>, fit <K> <seed> <em_iters>`
//!   `plugin call fastm <var> [<out>]`            (no/other args -> M0 hello)

use std::ffi::{CStr, CString};
use std::os::raw::{c_char, c_double, c_int};
use std::panic::{catch_unwind, AssertUnwindSafe};

use rand::{Rng, SeedableRng};
use rand_chacha::ChaCha8Rng;
use std::path::Path;
use topica_core::corpus::{from_texts, load_stoplist, LoadOptions};
use topica_core::ctm::{fit_ctm, CtmModel, GammaPrior};
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
    fn rs_macro_use(name: *const c_char, buf: *mut c_char, len: c_int) -> c_int;
    fn rs_macro_save(name: *const c_char, text: *const c_char) -> c_int;
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
/// Save a Stata global macro (name without a leading underscore -> global).
fn macro_save(name: &str, text: &str) {
    if let (Ok(n), Ok(t)) = (CString::new(name), CString::new(text)) {
        unsafe { rs_macro_save(n.as_ptr(), t.as_ptr()) };
    }
}
/// Read a Stata global macro by name (empty if unset).
fn macro_use(name: &str) -> String {
    let cn = match CString::new(name) {
        Ok(c) => c,
        Err(_) => return String::new(),
    };
    let cap = 4096usize;
    let mut buf = vec![0u8; cap];
    unsafe { rs_macro_use(cn.as_ptr(), buf.as_mut_ptr() as *mut c_char, cap as c_int) };
    let end = buf.iter().position(|&b| b == 0).unwrap_or(0);
    String::from_utf8_lossy(&buf[..end]).into_owned()
}

/// Read a (var, obs) string value into an owned String (str# or strL).
fn read_string(var: c_int, obs: c_int) -> String {
    let len = unsafe { rs_sdatalen(var, obs) };
    if len <= 0 {
        return String::new();
    }
    let cap = len as usize + 2;
    let mut buf = vec![0u8; cap];
    if unsafe { rs_var_is_strl(var) } != 0 {
        // SF_strldata returns the byte count, not a 0-success code; the
        // zero-initialized buffer NUL-terminates, so read up to the NUL/len below.
        unsafe { rs_strldata(var, obs, buf.as_mut_ptr() as *mut c_char, cap as c_int) };
    } else {
        // SF_sdata returns a Stata return code (0 = ok).
        let rc = unsafe { rs_sdata(var, obs, buf.as_mut_ptr() as *mut c_char) };
        if rc != 0 {
            return String::new();
        }
    }
    let end = buf[..cap]
        .iter()
        .position(|&b| b == 0)
        .unwrap_or(len as usize)
        .min(len as usize);
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
pub extern "C" fn fastm_entry(argc: c_int, argv: *const *const c_char) -> c_int {
    match catch_unwind(AssertUnwindSafe(|| {
        let a = args(argc, argv);
        match a.first().map(String::as_str) {
            Some("fit") => fit_op(&a),
            Some("searchk") => searchk_op(&a),
            _ => hello_op(),
        }
    })) {
        Ok(rc) => rc,
        Err(_) => {
            err("fastm: internal error (Rust panic)\n");
            198
        }
    }
}

/// Held-out document-completion diagnostics at one K. Splits each document's
/// tokens (deterministic by seed), fits on the train tokens, scores the held-out
/// tokens. `prevalence_full` is the design aligned to `corpus.docs` (kept rows are
/// selected internally). Returns (heldout_ll_per_token, n_test, bound, mean_coh,
/// mean_excl).
fn heldout_completion(
    corpus: &topica_core::corpus::Corpus,
    k: usize,
    em_iters: usize,
    prevalence_full: Option<&[Vec<f64>]>,
    heldout: f64,
    seed: u64,
) -> (f64, u64, f64, f64, f64) {
    let v = corpus.num_types();
    let mut split_rng = ChaCha8Rng::seed_from_u64(seed ^ 0x5EED_5EED_5EED_5EED);
    let mut train: Vec<Vec<u32>> = Vec::new();
    let mut test: Vec<Vec<u32>> = Vec::new();
    let mut keep: Vec<usize> = Vec::new();
    for (di, doc) in corpus.docs.iter().enumerate() {
        let mut tr = Vec::new();
        let mut te = Vec::new();
        for &w in doc {
            if split_rng.gen::<f64>() < heldout {
                te.push(w);
            } else {
                tr.push(w);
            }
        }
        if !tr.is_empty() {
            train.push(tr);
            test.push(te);
            keep.push(di);
        }
    }
    let dd = train.len();
    if dd < 2 {
        return (0.0, 0, 0.0, 0.0, 0.0);
    }
    let prev: Option<Vec<Vec<f64>>> =
        prevalence_full.map(|pf| keep.iter().map(|&di| pf[di].clone()).collect());
    let mut rng = ChaCha8Rng::seed_from_u64(seed);
    let model = fit_ctm(
        &train, k, v, em_iters, 1e-5, 0.0, prev.as_deref(), None, true, None,
        GammaPrior::Pooled, false, false, &mut rng,
    );
    let theta = model.doc_topics();
    let mut sum_lp = 0.0f64;
    let mut n_test = 0u64;
    for i in 0..dd {
        for &w in &test[i] {
            let mut p = 0.0f64;
            for t in 0..k {
                p += theta[i][t] * model.beta[t][w as usize];
            }
            sum_lp += p.max(1e-300).ln();
            n_test += 1;
        }
    }
    let ll = if n_test > 0 { sum_lp / n_test as f64 } else { 0.0 };
    let mm = 10usize.min(v);
    let coh = inspect::semantic_coherence(&model.beta, &train, mm);
    let excl = inspect::exclusivity(&model.beta, mm, 0.7);
    (
        ll,
        n_test,
        model.bound,
        coh.iter().sum::<f64>() / k as f64,
        excl.iter().sum::<f64>() / k as f64,
    )
}

/// M1: fit an STM (no covariates yet) and write topic proportions back.
/// Varlist: text var (1) followed by K theta vars (2..K+1).
/// Args: `fit <K> [seed=42] [em_iters=100]`.
fn fit_op(a: &[String]) -> c_int {
    let k: usize = a.get(1).and_then(|s| s.parse().ok()).unwrap_or(0);
    let seed: u64 = a.get(2).and_then(|s| s.parse().ok()).unwrap_or(42);
    let em_iters: usize = a.get(3).and_then(|s| s.parse().ok()).unwrap_or(100);
    let nprev: usize = a.get(4).and_then(|s| s.parse().ok()).unwrap_or(0);
    let mindf: u32 = a.get(5).and_then(|s| s.parse().ok()).unwrap_or(1);
    let maxdpct: f64 = a.get(6).and_then(|s| s.parse().ok()).unwrap_or(100.0);
    let lower: bool = a.get(7).and_then(|s| s.parse::<i32>().ok()).unwrap_or(1) != 0;
    let heldout: f64 = a
        .get(8)
        .and_then(|s| s.parse::<f64>().ok())
        .map(|x| (x / 100.0).clamp(0.0, 0.95))
        .unwrap_or(0.0);
    let nstart: usize = a.get(9).and_then(|s| s.parse().ok()).unwrap_or(1).max(1);
    let ncgroups: usize = a.get(10).and_then(|s| s.parse().ok()).unwrap_or(0);
    if k < 2 {
        err("fastm: k must be >= 2 (usage: fit <K> [seed] [em_iters] [nprev])\n");
        return 198;
    }

    let nvars = unsafe { rs_nvars() } as usize;
    if nvars < k + 1 + nprev {
        err(&format!(
            "fastm: varlist needs 1 text + {} theta + {} prevalence vars (got {})\n",
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

    let mut opts = LoadOptions {
        min_doc_freq: mindf,
        max_doc_fraction: (maxdpct / 100.0).clamp(0.0, 1.0),
        lowercase: lower,
        ..Default::default()
    };
    let stopfile = macro_use("fastm_stopfile");
    if !stopfile.is_empty() {
        match load_stoplist(Path::new(&stopfile)) {
            Ok(sw) => opts.stopwords = sw,
            Err(e) => {
                err(&format!(
                    "fastm: cannot read stopwords file '{}': {}\n",
                    stopfile, e
                ));
                return 198;
            }
        }
    }
    let corpus = match from_texts(&texts, Some(&names), None, &opts) {
        Ok(c) => c,
        Err(e) => {
            err(&format!("fastm: tokenize error: {}\n", e));
            return 198;
        }
    };
    let d = corpus.num_docs();
    let v = corpus.num_types();
    if d < 2 || v < 2 {
        err("fastm: too few documents/terms after tokenization\n");
        return 198;
    }
    if k > v {
        err(&format!(
            "fastm: k ({}) exceeds the vocabulary size ({}); reduce k() or relax preprocessing\n",
            k, v
        ));
        return 198;
    }
    say(&format!(
        "fastm: corpus = {} docs, {} terms, {} tokens; fitting K={} ...\n",
        d,
        v,
        corpus.total_tokens(),
        k
    ));
    say(&format!(
        "fastm: prep = lowercase {}, mindocfreq {}, maxdocpct {:.0}%, stopwords {}\n",
        if lower { "on" } else { "off" },
        mindf,
        maxdpct,
        if opts.stopwords.is_empty() { "none" } else { "yes" }
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
            "fastm: prevalence design = intercept + {} covariate(s)\n",
            nprev
        ));
        Some(x)
    } else {
        None
    };
    let want_effects = nprev > 0;

    // content(): SAGE content covariate (per-doc group index, num_groups). The
    // content variable is the last in the varlist (after text, theta, prevalence).
    let content_groups: Option<Vec<usize>> = if ncgroups >= 2 {
        let cvar = (2 + k + nprev) as c_int;
        let mut g = Vec::with_capacity(d);
        for name in &corpus.doc_names {
            let off: usize = name.parse().unwrap_or(usize::MAX);
            let obs = obs_of_offset.get(off).copied().unwrap_or(i1);
            let mut val: c_double = 0.0;
            unsafe { rs_vdata(cvar, obs, &mut val) };
            let gi = if val.is_finite() && val >= 0.0 { val as usize } else { 0 };
            g.push(gi.min(ncgroups - 1));
        }
        say(&format!(
            "fastm: content model (SAGE) with {} group(s)\n",
            ncgroups
        ));
        Some(g)
    } else {
        None
    };
    let content_arg = content_groups.as_ref().map(|g| (g.as_slice(), ncgroups));

    // nstart>1: random multi-start (stm selectModel), keep the best bound.
    // nstart==1 (default): deterministic spectral init.
    let model: CtmModel = if nstart <= 1 {
        let mut rng = ChaCha8Rng::seed_from_u64(seed);
        fit_ctm(
            &corpus.docs, k, v, em_iters, 1e-5, 0.0, prevalence.as_deref(), content_arg,
            true, None, GammaPrior::Pooled, want_effects, false, &mut rng,
        )
    } else {
        let mut best: Option<CtmModel> = None;
        for s in 0..nstart {
            let mut rng = ChaCha8Rng::seed_from_u64(seed.wrapping_add(s as u64));
            let m = fit_ctm(
                &corpus.docs, k, v, em_iters, 1e-5, 0.0, prevalence.as_deref(), content_arg,
                false, None, GammaPrior::Pooled, want_effects, false, &mut rng,
            );
            if best.as_ref().map_or(true, |b| m.bound > b.bound) {
                best = Some(m);
            }
        }
        say(&format!(
            "fastm: nstart={} random inits; kept the best bound\n",
            nstart
        ));
        best.unwrap()
    };
    let theta = model.doc_topics(); // d x k

    // heldout(): document-completion held-out log-likelihood for this fit (a
    // separate train/test split + fit; the reported model above uses all tokens).
    if heldout > 0.0 {
        let (hll, hn, _, _, _) =
            heldout_completion(&corpus, k, em_iters, prevalence.as_deref(), heldout, seed);
        if hn > 0 {
            save_scalar("fastm_heldout", hll);
            say(&format!(
                "fastm: held-out log-likelihood = {:.4} ({} test tokens)\n",
                hll, hn
            ));
        }
    }

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

    // Topic correlation matrix (stm topicCorr) -> e(topiccorr).
    let tc = model.topic_correlation();
    for a in 0..k {
        for b in 0..k {
            mat_store("fastm_tc", a + 1, b + 1, tc[a][b]);
        }
    }

    // FREX labels + coherence/exclusivity diagnostics (topica_core::inspect).
    let frex = inspect::frex_scores(&model.beta, &corpus.total_freqs, 0.5);
    let labels = inspect::top_words(&frex, 8usize.min(v));

    // estat labels: save prob/frex/lift/score top words per topic as globals.
    let nlab = 10usize.min(v);
    let join_words = |ids: &[usize]| {
        ids.iter()
            .map(|&w| corpus.id_to_word[w].as_str())
            .collect::<Vec<_>>()
            .join(" ")
    };
    let prob_top = inspect::top_words(&model.beta, nlab);
    let lift = inspect::lift_scores(&model.beta, &corpus.total_freqs);
    let lift_top = inspect::top_words(&lift, nlab);
    let score = inspect::score_scores(&model.beta);
    let score_top = inspect::top_words(&score, nlab);
    let frex_top = inspect::top_words(&frex, nlab);
    for t in 0..k {
        macro_save(&format!("fastm_lbl_prob_{}", t + 1), &join_words(&prob_top[t]));
        macro_save(&format!("fastm_lbl_frex_{}", t + 1), &join_words(&frex_top[t]));
        macro_save(&format!("fastm_lbl_lift_{}", t + 1), &join_words(&lift_top[t]));
        macro_save(&format!("fastm_lbl_score_{}", t + 1), &join_words(&score_top[t]));
    }

    // estat perspectives: for a content model, the words each level emphasizes in
    // each topic, ranked by the SAGE deviation (kappa_cov + kappa_interaction),
    // the same information stm's sageLabels() uses. Saved as globals per (level, topic).
    if let Some(ck) = &model.content_kappa {
        let g = model.num_groups;
        for t in 0..k {
            for lev in 0..g {
                let row = &ck.kappa_interaction[t * g + lev];
                let mut scored: Vec<(f64, usize)> = (0..v)
                    .map(|w| (ck.kappa_cov[lev][w] + row[w], w))
                    .collect();
                scored.sort_by(|a, b| b.0.partial_cmp(&a.0).unwrap_or(std::cmp::Ordering::Equal));
                let words = scored
                    .iter()
                    .take(nlab)
                    .map(|&(_, w)| corpus.id_to_word[w].as_str())
                    .collect::<Vec<_>>()
                    .join(" ");
                macro_save(&format!("fastm_persp_{}_{}", lev, t + 1), &words);
            }
        }
    }
    let mm = 10usize.min(v);
    let coh = inspect::semantic_coherence(&model.beta, &corpus.docs, mm);
    let excl = inspect::exclusivity(&model.beta, mm, 0.7);
    let mean_coh = coh.iter().sum::<f64>() / k as f64;
    let mean_excl = excl.iter().sum::<f64>() / k as f64;

    // saving(): write beta (topic-word probabilities) + vocab to a CSV the ado
    // turns into a dataset. Long form (V rows), so it scales to any vocabulary.
    let betafile = macro_use("fastm_betafile");
    if !betafile.is_empty() {
        use std::io::Write;
        match std::fs::File::create(&betafile) {
            Ok(f) => {
                let mut bw = std::io::BufWriter::new(f);
                let _ = write!(bw, "word");
                for t in 0..k {
                    let _ = write!(bw, ",topic{}", t + 1);
                }
                let _ = writeln!(bw);
                for vv in 0..v {
                    let _ = write!(bw, "{}", corpus.id_to_word[vv]);
                    for t in 0..k {
                        let _ = write!(bw, ",{:.10}", model.beta[t][vv]);
                    }
                    let _ = writeln!(bw);
                }
                say(&format!(
                    "fastm: beta+vocab ({} terms x {} topics) saved\n",
                    v, k
                ));
            }
            Err(e) => err(&format!("fastm: cannot write beta file: {}\n", e)),
        }
    }

    save_scalar("fastm_K", k as f64);
    save_scalar("fastm_V", v as f64);
    save_scalar("fastm_D", d as f64);
    save_scalar("fastm_bound", model.bound);
    save_scalar("fastm_iters", model.em_iters_run as f64);
    save_scalar("fastm_coh", mean_coh);
    save_scalar("fastm_excl", mean_excl);
    save_scalar("fastm_ncgroups", ncgroups as f64);

    say("fastm: top FREX words per topic [coherence / exclusivity] --\n");
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
    // method of composition (fills the Stata matrices fastm_b / fastm_se,
    // which the ado pre-creates as k x nprev).
    if want_effects {
        if let Some(xref) = prevalence.as_deref() {
            let mut eff_rng = ChaCha8Rng::seed_from_u64(seed ^ 0x9E37_79B9_7F4A_7C15);
            let nsims = 100usize;
            let pdim = nprev + 1; // intercept + covariates
            // Fill e(b) (1 x k*pdim) and block-diagonal e(V): full estimateEffect
            // regression per topic (intercept first, then covariates), so margins
            // and ereturn display treat it as a linear multi-equation model.
            for t in 0..k {
                let (coef, vcov) = effects::estimate_effect_topic(
                    &model.lambda, &model.nu, xref, t, nsims, &mut eff_rng,
                );
                for ci in 0..pdim {
                    let r = t * pdim + ci + 1; // 1-based
                    mat_store("fastm_eb", 1, r, coef[ci]);
                    for cj in 0..pdim {
                        let c = t * pdim + cj + 1;
                        mat_store("fastm_eV", r, c, vcov[ci * pdim + cj]);
                    }
                }
            }
            // Save the prevalence coefficients gamma (P x (K-1)) for predict.
            if let Some(g) = &model.gamma {
                for (pi, row) in g.iter().enumerate() {
                    for (ti, &val) in row.iter().enumerate() {
                        mat_store("fastm_gamma", pi + 1, ti + 1, val);
                    }
                }
            }
            say(&format!(
                "fastm: estimateEffect done ({} term(s), {} draws, method of composition)\n",
                nprev, nsims
            ));
        }
    }

    say(&format!(
        "fastm: done. bound={:.2}, iters={}, mean coherence={:.2}, mean exclusivity={:.2}\n",
        model.bound, model.em_iters_run, mean_coh, mean_excl
    ));
    0
}

/// searchk: fit at one K with held-out document completion, report diagnostics.
/// Varlist: text (1) then nprev prevalence vars (2..1+nprev); no theta vars.
/// Args: `searchk <K> <seed> <iters> <nprev> <heldoutpct> <mindf> <maxdpct> <lower>`.
/// Saves scalars fastm_sk_heldout / _bound / _coh / _excl for the ado to collect.
fn searchk_op(a: &[String]) -> c_int {
    let k: usize = a.get(1).and_then(|s| s.parse().ok()).unwrap_or(0);
    let seed: u64 = a.get(2).and_then(|s| s.parse().ok()).unwrap_or(42);
    let em_iters: usize = a.get(3).and_then(|s| s.parse().ok()).unwrap_or(100);
    let nprev: usize = a.get(4).and_then(|s| s.parse().ok()).unwrap_or(0);
    let heldout: f64 = a
        .get(5)
        .and_then(|s| s.parse::<f64>().ok())
        .map(|x| x / 100.0)
        .unwrap_or(0.5)
        .clamp(0.05, 0.95);
    let mindf: u32 = a.get(6).and_then(|s| s.parse().ok()).unwrap_or(1);
    let maxdpct: f64 = a.get(7).and_then(|s| s.parse().ok()).unwrap_or(100.0);
    let lower: bool = a.get(8).and_then(|s| s.parse::<i32>().ok()).unwrap_or(1) != 0;
    if k < 2 {
        err("fastm: k must be >= 2\n");
        return 198;
    }

    let nvars = unsafe { rs_nvars() } as usize;
    if nvars < 1 + nprev {
        err("fastm: searchk varlist needs the text var + prevalence vars\n");
        return 198;
    }

    let (i1, i2) = unsafe { (rs_in1(), rs_in2()) };
    let mut texts: Vec<String> = Vec::new();
    let mut names: Vec<String> = Vec::new();
    let mut obs_of_offset: Vec<c_int> = Vec::new();
    let mut off = 0usize;
    for obs in i1..=i2 {
        if unsafe { rs_ifobs(obs) } == 0 {
            continue;
        }
        texts.push(read_string(1, obs));
        names.push(off.to_string());
        obs_of_offset.push(obs);
        off += 1;
    }

    let mut opts = LoadOptions {
        min_doc_freq: mindf,
        max_doc_fraction: (maxdpct / 100.0).clamp(0.0, 1.0),
        lowercase: lower,
        ..Default::default()
    };
    let stopfile = macro_use("fastm_stopfile");
    if !stopfile.is_empty() {
        if let Ok(sw) = load_stoplist(Path::new(&stopfile)) {
            opts.stopwords = sw;
        }
    }
    let corpus = match from_texts(&texts, Some(&names), None, &opts) {
        Ok(c) => c,
        Err(e) => {
            err(&format!("fastm: tokenize error: {}\n", e));
            return 198;
        }
    };
    let v = corpus.num_types();
    if corpus.num_docs() < 2 || v < 2 {
        err("fastm: too few documents/terms after tokenization\n");
        return 198;
    }
    if k > v {
        err(&format!(
            "fastm: k ({}) exceeds the vocabulary size ({})\n",
            k, v
        ));
        return 198;
    }

    // Prevalence design aligned to corpus.docs (prevalence vars start at index 2);
    // the helper selects the kept rows after the held-out split.
    let prevalence: Option<Vec<Vec<f64>>> = if nprev > 0 {
        let mut x = Vec::with_capacity(corpus.num_docs());
        for name in &corpus.doc_names {
            let o: usize = name.parse().unwrap_or(usize::MAX);
            let obs = obs_of_offset.get(o).copied().unwrap_or(i1);
            let mut row = Vec::with_capacity(1 + nprev);
            row.push(1.0);
            for p in 0..nprev {
                let mut val: c_double = 0.0;
                unsafe { rs_vdata((2 + p) as c_int, obs, &mut val) };
                row.push(val);
            }
            x.push(row);
        }
        Some(x)
    } else {
        None
    };

    let (heldout_ll, n_test, bound, mean_coh, mean_excl) =
        heldout_completion(&corpus, k, em_iters, prevalence.as_deref(), heldout, seed);
    if n_test == 0 {
        err("fastm: too few documents/tokens after the held-out split\n");
        return 198;
    }
    save_scalar("fastm_sk_heldout", heldout_ll);
    save_scalar("fastm_sk_bound", bound);
    save_scalar("fastm_sk_coh", mean_coh);
    save_scalar("fastm_sk_excl", mean_excl);
    say(&format!(
        "fastm: searchk K={} done (held-out LL={:.4}, {} test tokens)\n",
        k, heldout_ll, n_test
    ));
    0
}

/// M0 smoke test: read var 1, mean it, write 2*x into var 2, save a scalar.
fn hello_op() -> c_int {
    let nobs = unsafe { rs_nobs() };
    let nvars = unsafe { rs_nvars() };
    say(&format!(
        "fastm: hello from Rust. obs={}, vars in varlist={}\n",
        nobs, nvars
    ));
    if nvars < 1 {
        err("fastm: pass at least one variable (the input)\n");
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
    save_scalar("fastm_mean", mean);
    say(&format!(
        "fastm: read {} non-missing obs, mean={:.6}, saved scalar fastm_mean\n",
        n, mean
    ));
    0
}
