*! fastm 0.7.0  Structural Topic Models in Stata (engine: topica-core, Rust)
*! fastm textvar [if] [in], k(#) [prevalence(fvvarlist) seed(#) iters(#) generate(name) replace]
program fastm, eclass
    version 15.0

    // Replay: bare `fastm` redisplays the last fit.
    if replay() {
        if "`e(cmd)'" != "fastm" {
            di as error "last estimates not found"
            exit 301
        }
        fastm_display
        exit
    }

    syntax varname [if] [in], K(integer) ///
        [ PREValence(varlist fv ts) SPline(string) CONTent(varname) ///
          noLOWercase STOPwords(string) MINdocfreq(integer 1) MAXdocpct(real 100) ///
          HELDout(real 0) NSTART(integer 1) ///
          SEED(integer 42) ITERs(integer 200) GENerate(name) SAVing(string) replace ]

    if `k' < 2 {
        di as error "k() must be >= 2"
        exit 198
    }
    confirm string variable `varlist'
    if `seed' < 0 {
        di as error "seed() must be a non-negative integer"
        exit 198
    }
    if `iters' < 1 {
        di as error "iters() must be positive"
        exit 198
    }
    if `nstart' < 1 {
        di as error "nstart() must be positive"
        exit 198
    }
    if `mindocfreq' < 1 {
        di as error "mindocfreq() must be positive"
        exit 198
    }
    if `maxdocpct' <= 0 | `maxdocpct' > 100 {
        di as error "maxdocpct() must be in (0,100]"
        exit 198
    }
    if `heldout' < 0 | `heldout' >= 100 {
        di as error "heldout() must be in [0,100)"
        exit 198
    }
    if "`generate'" == "" local generate theta
    local lower = ("`lowercase'" != "nolowercase")   // default on; nolowercase turns off

    // Resolve stopwords() to a file path the plugin loads. The plugin API has
    // no string-option channel, so transient file paths are passed by globals.
    local stopfile ""
    if "`stopwords'" != "" & "`stopwords'" != "none" {
        if "`stopwords'" == "english" {
            capture findfile fastm_english.stops
            if _rc {
                di as error "english stopword list (fastm_english.stops) not found on the adopath"
                exit 198
            }
            local stopfile "`r(fn)'"
        }
        else {
            capture confirm file `"`stopwords'"'
            if _rc {
                di as error `"stopwords(): use none, english, or an existing filename"'
                exit 198
            }
            local stopfile `"`stopwords'"'
        }
    }
    global fastm_stopfile `"`stopfile'"'

    // saving(filename[, replace]): the plugin writes beta+vocab to a temp CSV
    // named in a transient global; Stata then imports and saves it below.
    local sfile ""
    local srep ""
    global fastm_betafile ""
    if `"`saving'"' != "" {
        gettoken sfile srest : saving, parse(",")
        local sfile = trim(`"`sfile'"')
        local srest = trim(`"`srest'"')
        if `"`sfile'"' == "" {
            di as error "saving() requires a filename"
            exit 198
        }
        if `"`srest'"' != "" {
            if substr(`"`srest'"', 1, 1) != "," {
                di as error "saving() syntax is saving(filename[, replace])"
                exit 198
            }
            gettoken comma sopts : srest, parse(",")
            local sopts = strtrim(`"`sopts'"')
            if `"`sopts'"' == "replace" local srep replace
            else {
                di as error "saving() option must be replace"
                exit 198
            }
        }
        tempfile betacsv
        global fastm_betafile `"`betacsv'"'
    }

    marksample touse, strok

    // Expand factor/time-series prevalence into numeric design columns; drop the
    // base (`b.`)/omitted (`o.`) terms so they don't collide with the intercept.
    local prevvars ""
    local collabels ""
    if "`prevalence'" != "" {
        fvexpand `prevalence'
        local expnames `r(varlist)'
        fvrevar `prevalence'
        local revars `r(varlist)'
        local i 0
        foreach nm of local expnames {
            local ++i
            local tv : word `i' of `revars'
            if !strmatch("`nm'", "*b.*") & !strmatch("`nm'", "*o.*") {
                local prevvars  `prevvars'  `tv'
                local collabels `collabels' `nm'
            }
        }
        markout `touse' `prevvars'
    }

    // Fold content()'s missing rows into `touse' BEFORE the spline basis is built,
    // so knots land on the final estimation sample (stm does listwise deletion
    // before forming s()). The content block below re-derives its group codes on
    // this same narrowed sample. (Empty documents are dropped later by the engine
    // and cannot be excluded at this stage.)
    if "`content'" != "" {
        tempvar _cmiss
        quietly egen `_cmiss' = group(`content') if `touse'
        markout `touse' `_cmiss'
    }

    // spline(varlist [, df(#) degree(#)]): B-spline basis of a continuous
    // covariate (stm's s()). For each variable, df basis columns are added to
    // the prevalence design. Matches stm's design space (same quantile knots).
    if `"`spline'"' != "" {
        gettoken svars sopts : spline, parse(",")
        local svars = trim(`"`svars'"')
        local sdf 10
        local sdeg 3
        if `"`sopts'"' != "" {
            // Re-running syntax clobbers the standard locals (varlist/if/in), so
            // stash and restore the text variable around the suboption parse.
            local _txtvar `varlist'
            local 0 `"`sopts'"'
            syntax [, DF(integer 10) DEGree(integer 3)]
            local sdf `df'
            local sdeg `degree'
            local varlist `_txtvar'
        }
        if `sdf' < `sdeg' + 1 {
            di as error "spline(): df must be at least degree+1 (`=`sdeg'+1')"
            exit 198
        }
        foreach sv of local svars {
            confirm numeric variable `sv'
        }
        markout `touse' `svars'
        // The basis columns must be PERMANENT variables named exactly as their
        // e(b) coefficients (`<var>_s<j>`): predict xb/stdp and margins call
        // Stata's _predict, which evaluates x*b against dataset variables. As
        // tempvars they vanished on exit, so post-estimation broke with r(111).
        // They carry values only on e(sample) (missing elsewhere), like the fit.
        foreach sv of local svars {
            local sbv ""
            forvalues j = 1/`sdf' {
                local bsname `sv'_s`j'
                capture confirm new variable `bsname'
                if _rc {
                    if "`replace'" == "" {
                        di as error "`bsname' (spline basis) already exists; use replace or rename `sv'"
                        exit 110
                    }
                    quietly drop `bsname'
                }
                quietly generate double `bsname' = .
                local sbv `sbv' `bsname'
                local prevvars  `prevvars'  `bsname'
                local collabels `collabels' `bsname'
            }
            mata: fastm_bs("`sv'", "`touse'", "`sbv'", `sdf', `sdeg')
        }
    }

    // content(var): SAGE content covariate (a single categorical). Encode its
    // levels to 0-based group indices for the engine; passed as the last varlist
    // column (not part of the prevalence design). Content-level labels are kept
    // in globals because estat is a separate autoloaded program.
    local ng 0
    local cgrp ""
    capture macro drop fastm_clev_*
    if "`content'" != "" {
        tempvar cgrp
        egen `cgrp' = group(`content') if `touse'
        markout `touse' `cgrp'
        quietly summarize `cgrp', meanonly
        local ng = r(max)
        if `ng' < 2 {
            di as error "content() needs at least 2 groups"
            exit 198
        }
        // Record level names (group() codes by sorted value) for estat perspectives.
        capture confirm numeric variable `content'
        local cnum = (_rc == 0)
        levelsof `content' if `touse', local(_clevs)
        local _gi = 0
        foreach _lv of local _clevs {
            if `cnum' {
                local _lab : label (`content') `_lv'
                global fastm_clev_`_gi' `"`_lab'"'
            }
            else global fastm_clev_`_gi' `"`_lv'"'
            local ++_gi
        }
        quietly replace `cgrp' = `cgrp' - 1   // 0-based for the engine
    }

    local nprev : word count `prevvars'

    // Validate ALL target names first, then create -- so a conflict on topic t
    // does not leave topics 1..t-1 already written to the user's data.
    if "`replace'" == "" {
        forvalues t = 1/`k' {
            capture confirm new variable `generate'`t'
            if _rc {
                di as error "`generate'`t' already exists; use replace or a different generate()"
                exit 110
            }
        }
    }
    forvalues t = 1/`k' {
        capture drop `generate'`t'
        quietly generate double `generate'`t' = .
    }

    // Topic correlation matrix (filled by the plugin) -> e(topiccorr).
    matrix fastm_tc = J(`k', `k', .)

    // Multi-start diagnostics: one row per random start (bound / coherence /
    // exclusivity), filled by the plugin -> e(nstart_diag). Only the best-bound
    // start is kept, but reporting all lets the user judge the frontier.
    if `nstart' > 1 {
        matrix fastm_ns = J(`nstart', 3, .)
        matrix colnames fastm_ns = bound coherence exclusivity
    }

    // estimateEffect outputs: e(b) row (1 x k*nprev), e(V) (k*nprev square).
    if `nprev' > 0 {
        local pe = `k' * (`nprev' + 1)
        matrix fastm_eb = J(1, `pe', .)
        matrix fastm_eV = J(`pe', `pe', 0)
        matrix fastm_gamma = J(1 + `nprev', `k' - 1, .)
    }

    // Clear any stale labels/perspectives from a previous fit. The plugin
    // repopulates these globals for estat labels/perspectives.
    capture macro drop fastm_lbl_*
    capture macro drop fastm_persp_*

    // Varlist order the plugin expects: text (1), theta (2..K+1), prevalence,
    // then the content group var (last) when content() is used.
    plugin call fastmplugin `varlist' `generate'1-`generate'`k' `prevvars' `cgrp' ///
        if `touse', fit `k' `seed' `iters' `nprev' `mindocfreq' `maxdocpct' `lower' `heldout' `nstart' `ng'
    capture macro drop fastm_stopfile
    capture macro drop fastm_betafile

    // Tokenization and vocabulary trimming can remove documents that passed the
    // initial Stata marksample. The plugin writes theta only for retained
    // documents, so tighten e(sample) to the corpus actually fit.
    quietly replace `touse' = 0 if missing(`generate'1)

    // Post e(b)/e(V) so test/lincom/ereturn display work. Equation = topic#,
    // coefficient = prevalence term (matches the plugin's fill order: topic, term).
    if `nprev' > 0 {
        local bn ""
        forvalues t = 1/`k' {
            local bn `bn' topic`t':_cons
            foreach nm of local collabels {
                local bn `bn' topic`t':`nm'
            }
        }
        matrix colnames fastm_eb = `bn'
        matrix rownames fastm_eV = `bn'
        matrix colnames fastm_eV = `bn'
        ereturn post fastm_eb fastm_eV, esample(`touse')
        ereturn local marginsok "XB default"
        ereturn local marginsnotok "PR STDP SCores"
    }
    else {
        ereturn post, esample(`touse') properties(nob noV)
        ereturn local marginsnotok "_ALL"
    }
    ereturn scalar k            = scalar(fastm_K)
    ereturn scalar n_terms      = scalar(fastm_V)
    ereturn scalar N_docs       = scalar(fastm_D)
    ereturn scalar bound        = scalar(fastm_bound)
    ereturn scalar iters        = scalar(fastm_iters)
    ereturn scalar coherence    = scalar(fastm_coh)
    ereturn scalar exclusivity  = scalar(fastm_excl)
    ereturn scalar n_prevalence = `nprev'
    ereturn scalar n_content = `ng'
    ereturn scalar nstart = `nstart'
    if "`content'" != "" ereturn local content "`content'"
    if `heldout' > 0 ereturn scalar heldout_ll = scalar(fastm_heldout)
    ereturn local prev_terms "`collabels'"
    ereturn local prevalence "`prevalence'"
    ereturn local generate   "`generate'"
    ereturn local textvar    "`varlist'"
    ereturn local cmd        "fastm"
    ereturn local estat_cmd  "fastm_estat"
    ereturn local predict    "fastm_predict"

    // Persist postestimation display state with the estimates. The plugin can
    // only write Stata globals, but estat should survive estimates store/restore.
    foreach typ in prob frex lift score {
        forvalues t = 1/`k' {
            local _gname fastm_lbl_`typ'_`t'
            local _lbl `"${`_gname'}"'
            ereturn local lbl_`typ'_`t' `"`_lbl'"'
        }
    }
    if `ng' > 0 {
        forvalues g = 0/`=`ng'-1' {
            local _gname fastm_clev_`g'
            local _clev `"${`_gname'}"'
            ereturn local clev_`g' `"`_clev'"'
            forvalues t = 1/`k' {
                local _gname fastm_persp_`g'_`t'
                local _persp `"${`_gname'}"'
                ereturn local persp_`g'_`t' `"`_persp'"'
            }
        }
    }
    capture macro drop fastm_lbl_*
    capture macro drop fastm_persp_*
    capture macro drop fastm_clev_*

    local tn ""
    forvalues t = 1/`k' {
        local tn `tn' topic`t'
    }
    matrix rownames fastm_tc = `tn'
    matrix colnames fastm_tc = `tn'
    ereturn matrix topiccorr = fastm_tc

    // Multi-start diagnostics table -> e(nstart_diag); shown so the kept model is
    // not a silent choice.
    if `nstart' > 1 {
        local sn ""
        forvalues s = 1/`nstart' {
            local sn `sn' start`s'
        }
        matrix rownames fastm_ns = `sn'
        di ""
        di as txt "Multi-start diagnostics (kept the best bound):"
        matlist fastm_ns, border(rows) format(%10.3f)
        ereturn matrix nstart_diag = fastm_ns
    }

    if `nprev' > 0 {
        local gcols ""
        forvalues t = 1/`=`k'-1' {
            local gcols "`gcols' topic`t'"
        }
        matrix rownames fastm_gamma = _cons `collabels'
        matrix colnames fastm_gamma = `gcols'
        ereturn matrix gamma = fastm_gamma
    }

    // saving(): turn the plugin's beta+vocab CSV into a .dta (data preserved).
    if `"`sfile'"' != "" {
        preserve
        import delimited `"`betacsv'"', clear varnames(1) case(preserve)
        save `"`sfile'"', `srep'
        restore
        di as txt "beta + vocabulary written to " as res `"`sfile'"' ///
            as txt " (`=e(n_terms)' terms x `=e(k)' topics)"
    }

    fastm_display
end

// Display the stored results (estimation and replay). Reads e() only.
program fastm_display
    di ""
    di as txt "Structural Topic Model" ///
        _col(48) "Documents      = " as res %9.0fc e(N_docs)
    di as txt "Engine: topica-core (Rust)" ///
        _col(48) "Vocabulary     = " as res %9.0fc e(n_terms)
    di as txt _col(48) "Topics (K)     = " as res %9.0fc e(k)
    if e(n_prevalence) > 0 ///
        di as txt _col(48) "Prevalence     = " as res %9.0fc e(n_prevalence) as txt " term(s)"
    if e(n_content) > 0 ///
        di as txt _col(48) "Content groups = " as res %9.0fc e(n_content)
    di as txt _col(48) "Final bound    = " as res %9.2f e(bound)
    di as txt "Mean semantic coherence  = " as res %9.2f e(coherence) ///
        _col(48) "Mean exclusivity = " as res %9.2f e(exclusivity)
    di as txt "Topic proportions in " as res "`e(generate)'1-`e(generate)'`=e(k)'" ///
        as txt " (EM iters " as res %9.0f e(iters) as txt ")"

    if e(n_prevalence) > 0 {
        di ""
        di as txt "Covariate effects on topic proportions (method of composition)"
        ereturn display
    }
end


mata:

// R type-7 quantile of a sorted column vector at probability p.
real scalar fastm_q7(real colvector xs, real scalar p)
{
    real scalar n, h, lo
    n = rows(xs)
    h = (n - 1) * p + 1
    lo = floor(h)
    if (lo >= n) return(xs[n])
    return(xs[lo] + (h - lo) * (xs[lo + 1] - xs[lo]))
}

// i-th B-spline of order ord (degree ord-1) at t, Cox-de Boor recursion.
// Right-closed at the upper boundary so x==hi is included (as in R's bs()).
real scalar fastm_bbasis(real scalar i, real scalar ord, real scalar t,
                         real colvector knots, real scalar hi)
{
    real scalar a, b, d1, d2
    if (ord == 1) {
        if (knots[i] <= t & t < knots[i + 1]) return(1)
        if (t == hi & knots[i + 1] == hi & knots[i] < knots[i + 1]) return(1)
        return(0)
    }
    a = 0; b = 0
    d1 = knots[i + ord - 1] - knots[i]
    if (d1 > 0) a = (t - knots[i]) / d1 * fastm_bbasis(i, ord - 1, t, knots, hi)
    d2 = knots[i + ord] - knots[i + 1]
    if (d2 > 0) b = (knots[i + ord] - t) / d2 * fastm_bbasis(i + 1, ord - 1, t, knots, hi)
    return(a + b)
}

// B-spline basis matching R splines::bs(x, df, degree, intercept=FALSE):
// quantile interior knots, min/max boundary knots, drop the first column.
// Writes the df basis columns into the tempvars listed in tvars over touse.
void fastm_bs(string scalar xvar, string scalar touse, string scalar tvars,
              real scalar df, real scalar degree)
{
    real colvector x, xs, iknots, knots, yv
    real matrix B, Bout
    string rowvector tv
    real scalar ord, nik, lo, hi, n, i, j, nb

    st_view(x = ., ., xvar, touse)
    n = rows(x)
    ord = degree + 1
    nik = df - ord + 1                         // interior knots (intercept=FALSE)
    xs = sort(x, 1)
    lo = xs[1]; hi = xs[n]
    iknots = J(0, 1, .)
    if (nik > 0) {
        iknots = J(nik, 1, .)
        for (i = 1; i <= nik; i++) iknots[i] = fastm_q7(xs, i / (nik + 1))
    }
    knots = J(ord, 1, lo) \ iknots \ J(ord, 1, hi)
    nb = rows(knots) - ord                     // number of basis functions
    B = J(n, nb, 0)
    for (i = 1; i <= n; i++) {
        for (j = 1; j <= nb; j++) B[i, j] = fastm_bbasis(j, ord, x[i], knots, hi)
    }
    Bout = B[, (2 :: nb)]                       // drop first column (intercept=FALSE)
    tv = tokens(tvars)
    for (j = 1; j <= cols(Bout); j++) {
        st_view(yv = ., ., tv[j], touse)
        yv[., .] = Bout[, j]
    }
}
end

// Plugin load: BARE top-level code. A plugin loaded inside a running program
// does not persist, so it must be declared here (auto-load runs this too). Dev
// build first (fastm.plugin), else the per-OS plugin shipped with the package.
// This block is intentionally duplicated in searchk.ado so either command can
// be autoloaded independently and still declare the plugin at top level.
// Pass the bare filename to using() and let Stata resolve it on the adopath:
// findfile can return a ~-prefixed path (e.g. PLUS = ~/ado/plus) that
// program ... , plugin using() cannot open (r(601)).
capture findfile fastm.plugin
if !_rc local _fpl fastm.plugin
else {
    if "`c(os)'" == "Windows"      local _fpl fastm-windows-x86_64.plugin
    else if strpos("`c(machine_type)'", "Mac") local _fpl fastm-macos.plugin
    else                            local _fpl fastm-linux-x86_64.plugin
}
capture program fastmplugin, plugin using("`_fpl'")
