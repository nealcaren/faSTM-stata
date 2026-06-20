*! stmata 0.5.0  Structural Topic Models in Stata (engine: topica-core, Rust)
*! stmata textvar [if] [in], k(#) [prevalence(fvvarlist) seed(#) iters(#) generate(name) replace]
program stmata, eclass
    version 15.0

    // Replay: bare `stmata` redisplays the last fit.
    if replay() {
        if "`e(cmd)'" != "stmata" {
            di as error "last estimates not found"
            exit 301
        }
        stmata_display
        exit
    }

    syntax varname [if] [in], K(integer) ///
        [ PREValence(varlist fv ts) SEED(integer 42) ITERs(integer 200) ///
          GENerate(name) replace ]

    if `k' < 2 {
        di as error "k() must be >= 2"
        exit 198
    }
    if "`generate'" == "" local generate theta

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

    // estimateEffect outputs: e(b) row (1 x k*nprev), e(V) (k*nprev square).
    if `nprev' > 0 {
        local pe = `k' * (`nprev' + 1)
        matrix stmata_eb = J(1, `pe', .)
        matrix stmata_eV = J(`pe', `pe', 0)
        matrix stmata_gamma = J(1 + `nprev', `k' - 1, .)
    }

    // Varlist order the plugin expects: text (1), theta (2..K+1), prevalence (K+2..).
    plugin call stmataplugin `varlist' `generate'1-`generate'`k' `prevvars' ///
        if `touse', fit `k' `seed' `iters' `nprev'

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
        matrix colnames stmata_eb = `bn'
        matrix rownames stmata_eV = `bn'
        matrix colnames stmata_eV = `bn'
        ereturn post stmata_eb stmata_eV, esample(`touse')
    }
    else {
        ereturn clear
    }
    ereturn scalar k            = scalar(stmata_K)
    ereturn scalar n_terms      = scalar(stmata_V)
    ereturn scalar N_docs       = scalar(stmata_D)
    ereturn scalar bound        = scalar(stmata_bound)
    ereturn scalar iters        = scalar(stmata_iters)
    ereturn scalar coherence    = scalar(stmata_coh)
    ereturn scalar exclusivity  = scalar(stmata_excl)
    ereturn scalar n_prevalence = `nprev'
    ereturn local prev_terms "`collabels'"
    ereturn local prevalence "`prevalence'"
    ereturn local generate   "`generate'"
    ereturn local textvar    "`varlist'"
    ereturn local cmd        "stmata"

    if `nprev' > 0 {
        local gcols ""
        forvalues t = 1/`=`k'-1' {
            local gcols "`gcols' topic`t'"
        }
        matrix rownames stmata_gamma = _cons `collabels'
        matrix colnames stmata_gamma = `gcols'
        ereturn matrix gamma = stmata_gamma
        ereturn local predict "stmata_predict"
    }

    stmata_display
end

// Display the stored results (estimation and replay). Reads e() only.
program stmata_display
    di ""
    di as txt "Structural Topic Model" ///
        _col(48) "Documents      = " as res %9.0fc e(N_docs)
    di as txt "Engine: topica-core (Rust)" ///
        _col(48) "Vocabulary     = " as res %9.0fc e(n_terms)
    di as txt _col(48) "Topics (K)     = " as res %9.0fc e(k)
    if e(n_prevalence) > 0 ///
        di as txt _col(48) "Prevalence     = " as res %9.0fc e(n_prevalence) as txt " term(s)"
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

// predict after stmata (xtreg-style). One topic per call via topic(#).
//   pr (default) : prevalence-fitted topic proportion, softmax([X*gamma, 0])
//   xb           : prevalence linear predictor for the topic (reference topic = 0)
program stmata_predict
    version 15.0
    syntax newvarname [if] [in] , [ PR XB STDP Topic(integer 0) EQuation(passthru) ]

    if "`e(cmd)'" != "stmata" {
        di as error "stmata estimation results not found"
        exit 301
    }
    marksample touse, novarlist

    // pr: the model's prevalence-fitted proportion, softmax([X*gamma, 0]).
    if "`pr'" != "" {
        if "`e(prevalence)'" == "" {
            di as error "pr requires a model fit with prevalence()"
            exit 459
        }
        local kk = e(k)
        if `topic' < 1 | `topic' > `kk' {
            di as error "pr requires topic(#) in 1..`kk'"
            exit 198
        }
        fvexpand `e(prevalence)'
        local expnames `r(varlist)'
        fvrevar `e(prevalence)'
        local revars `r(varlist)'
        local prevvars ""
        local i 0
        foreach nm of local expnames {
            local ++i
            local tv : word `i' of `revars'
            if !strmatch("`nm'", "*b.*") & !strmatch("`nm'", "*o.*") local prevvars `prevvars' `tv'
        }
        tempname G
        matrix `G' = e(gamma)
        quietly generate double `varlist' = .
        mata: stmata_pred("`varlist'", "`touse'", "`prevvars'", "`G'", `topic', `kk', "proportions")
        exit
    }

    // xb / stdp: the estimateEffect linear prediction for one topic equation,
    // via the native engine (margins-compatible, delta-method SEs).
    if `"`equation'"' == "" {
        if `topic' > 0 local equation equation(topic`topic')
        else local equation equation(topic1)
    }
    _predict `typlist' `varlist' if `touse', `xb' `stdp' `equation'
end

mata:
void stmata_pred(string scalar newvar, string scalar touse, string scalar prevvars,
                 string scalar Gname, real scalar topic, real scalar K, string scalar stat)
{
    real matrix G, Xcov, X, XB, full, Pr, yv, e
    real colvector out, m, s
    G = st_matrix(Gname)                         // (1+ncov) x (K-1)
    st_view(Xcov = ., ., tokens(prevvars), touse)
    n = rows(Xcov)
    X = (J(n, 1, 1), Xcov)                        // intercept + covariates
    XB = X * G                                    // N x (K-1)
    if (stat == "xb") {
        out = (topic < K ? XB[, topic] : J(n, 1, 0))
    }
    else {
        full = (XB, J(n, 1, 0))                   // reference topic = 0
        m = rowmax(full)
        e = exp(full :- m)
        s = rowsum(e)
        Pr = e :/ s
        out = Pr[, topic]
    }
    st_view(yv = ., ., newvar, touse)
    yv[., .] = out
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
