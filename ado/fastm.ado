*! fastm 0.5.2  Structural Topic Models in Stata (engine: topica-core, Rust)
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
          noLOWercase STOPwords(string) MINdocfreq(integer 1) MAXdocpct(real 100) STEM ///
          HELDout(real 0) NSTART(integer 1) ///
          SEED(integer 42) ITERs(integer 200) GENerate(name) SAVing(string) replace ]

    if `k' < 2 {
        di as error "k() must be >= 2"
        exit 198
    }
    if "`generate'" == "" local generate theta
    if "`stem'" != "" {
        di as error "stem is not yet supported (the engine has no stemmer); stem upstream for now"
        exit 198
    }
    local lower = ("`lowercase'" != "nolowercase")   // default on; nolowercase turns off

    // Resolve stopwords() to a file path the plugin loads (via the global below).
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

    // saving(filename[, replace]): the plugin writes beta+vocab to a temp CSV here.
    local sfile ""
    local srep ""
    global fastm_betafile ""
    if `"`saving'"' != "" {
        gettoken sfile srest : saving, parse(",")
        local sfile = trim(`"`sfile'"')
        if strpos(`"`srest'"', "replace") local srep replace
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
        foreach sv of local svars {
            local sbv ""
            forvalues j = 1/`sdf' {
                tempvar bs`sv'`j'
                quietly generate double `bs`sv'`j'' = .
                local sbv `sbv' `bs`sv'`j''
                local prevvars  `prevvars'  `bs`sv'`j''
                local collabels `collabels' `sv'_s`j'
            }
            mata: fastm_bs("`sv'", "`touse'", "`sbv'", `sdf', `sdeg')
        }
    }

    // content(var): SAGE content covariate (a single categorical). Encode its
    // levels to 0-based group indices for the engine; passed as the last varlist
    // column (not part of the prevalence design).
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

    forvalues t = 1/`k' {
        capture confirm new variable `generate'`t'
        if _rc & "`replace'" == "" {
            di as error "`generate'`t' already exists; use replace or a different generate()"
            exit 110
        }
        capture drop `generate'`t'
        quietly generate double `generate'`t' = .
    }

    // Topic correlation matrix (filled by the plugin) -> e(topiccorr).
    matrix fastm_tc = J(`k', `k', .)

    // estimateEffect outputs: e(b) row (1 x k*nprev), e(V) (k*nprev square).
    if `nprev' > 0 {
        local pe = `k' * (`nprev' + 1)
        matrix fastm_eb = J(1, `pe', .)
        matrix fastm_eV = J(`pe', `pe', 0)
        matrix fastm_gamma = J(1 + `nprev', `k' - 1, .)
    }

    // Clear any stale labels/perspectives from a previous fit (plugin repopulates).
    capture macro drop fastm_lbl_*
    capture macro drop fastm_persp_*

    // Varlist order the plugin expects: text (1), theta (2..K+1), prevalence,
    // then the content group var (last) when content() is used.
    plugin call fastmplugin `varlist' `generate'1-`generate'`k' `prevvars' `cgrp' ///
        if `touse', fit `k' `seed' `iters' `nprev' `mindocfreq' `maxdocpct' `lower' `heldout' `nstart' `ng'

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
    }
    else {
        ereturn clear
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

    local tn ""
    forvalues t = 1/`k' {
        local tn `tn' topic`t'
    }
    matrix rownames fastm_tc = `tn'
    matrix colnames fastm_tc = `tn'
    ereturn matrix topiccorr = fastm_tc

    if `nprev' > 0 {
        local gcols ""
        forvalues t = 1/`=`k'-1' {
            local gcols "`gcols' topic`t'"
        }
        matrix rownames fastm_gamma = _cons `collabels'
        matrix colnames fastm_gamma = `gcols'
        ereturn matrix gamma = fastm_gamma
        ereturn local predict "fastm_predict"
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
