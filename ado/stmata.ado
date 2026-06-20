*! stmata 0.3.0  Structural Topic Models in Stata (engine: topica-core, Rust)
*! stmata textvar [if] [in], k(#) [prevalence(fvvarlist) seed(#) iters(#) generate(name) replace]
program stmata, eclass
    version 15.0
    syntax varname [if] [in], K(integer) ///
        [ PREValence(varlist fv ts) SEED(integer 42) ITERs(integer 200) ///
          GENerate(name) replace ]

    if `k' < 2 {
        di as error "k() must be >= 2"
        exit 198
    }
    if "`generate'" == "" local generate theta

    // Sample: honors if/in and drops empty/missing text.
    marksample touse, strok

    // Expand factor/time-series prevalence into numeric design columns. fvrevar
    // gives one tempvar per fvexpand term (base/omitted included), so we drop the
    // base (`b.`) and omitted (`o.`) terms — the plugin adds its own intercept.
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
    local nprev : word count `prevvars'

    // Create the K topic-proportion variables the plugin writes into.
    forvalues t = 1/`k' {
        capture confirm new variable `generate'`t'
        if _rc & "`replace'" == "" {
            di as error "`generate'`t' already exists; use replace or a different generate()"
            exit 110
        }
        capture drop `generate'`t'
        quietly generate double `generate'`t' = .
    }

    // estimateEffect output matrices the plugin fills (k topics x nprev covariates).
    if `nprev' > 0 {
        matrix stmata_b  = J(`k', `nprev', .)
        matrix stmata_se = J(`k', `nprev', .)
    }

    // Varlist order the plugin expects: text (1), theta (2..K+1), prevalence (K+2..).
    plugin call stmataplugin `varlist' `generate'1-`generate'`k' `prevvars' ///
        if `touse', fit `k' `seed' `iters' `nprev'

    ereturn clear
    ereturn scalar k            = scalar(stmata_K)
    ereturn scalar n_terms      = scalar(stmata_V)
    ereturn scalar N_docs       = scalar(stmata_D)
    ereturn scalar bound        = scalar(stmata_bound)
    ereturn scalar iters        = scalar(stmata_iters)
    ereturn scalar coherence    = scalar(stmata_coh)
    ereturn scalar exclusivity  = scalar(stmata_excl)
    ereturn scalar n_prevalence = `nprev'
    ereturn local prevalence "`prevalence'"
    ereturn local generate   "`generate'"
    ereturn local textvar    "`varlist'"
    ereturn local cmd        "stmata"

    if `nprev' > 0 {
        local rn ""
        forvalues t = 1/`k' {
            local rn "`rn' topic`t'"
        }
        matrix rownames stmata_b  = `rn'
        matrix rownames stmata_se = `rn'
        capture matrix colnames stmata_b  = `collabels'
        capture matrix colnames stmata_se = `collabels'
        ereturn matrix effects_se = stmata_se
        ereturn matrix effects    = stmata_b
    }

    di ""
    di as txt "Structural Topic Model" ///
        _col(48) "Documents      = " as res %9.0fc e(N_docs)
    di as txt "Engine: topica-core (Rust)" ///
        _col(48) "Vocabulary     = " as res %9.0fc e(n_terms)
    di as txt _col(48) "Topics (K)     = " as res %9.0fc e(k)
    if `nprev' > 0 ///
        di as txt _col(48) "Prevalence     = " as res %9.0fc e(n_prevalence) as txt " term(s)"
    di as txt _col(48) "Final bound    = " as res %9.2f e(bound)
    di as txt "Mean semantic coherence  = " as res %9.2f e(coherence) ///
        _col(48) "Mean exclusivity = " as res %9.2f e(exclusivity)
    di as txt "Topic proportions written to " as res "`generate'1-`generate'`k'" ///
        as txt " (EM iters " as res %9.0f e(iters) as txt ")"

    if `nprev' > 0 {
        di ""
        di as txt "Covariate effects on topic proportions (method of composition)"
        tempname B SE
        matrix `B'  = e(effects)
        matrix `SE' = e(effects_se)
        local ci = 0
        foreach nm of local collabels {
            local ++ci
            di as txt "Term " as res "`nm'" as txt ":"
            di as txt "    topic {c |}       coef         se"
            di as txt "    {hline 6}{c +}{hline 24}"
            forvalues t = 1/`k' {
                di as txt "    " %5.0f `t' " {c |} " ///
                    as res %10.4f `B'[`t',`ci'] "  " %10.4f `SE'[`t',`ci']
            }
        }
    }
end

// --------------------------------------------------------------------------
// One-time plugin load. BARE top-level code (not inside a program): a plugin
// loaded inside a running program does not register for `plugin call` elsewhere.
// --------------------------------------------------------------------------
capture findfile stmata.plugin
if _rc {
    di as error "stmata: stmata.plugin not found on the adopath (or current dir)"
}
else {
    capture program stmataplugin, plugin using(`"`r(fn)'"')
}
