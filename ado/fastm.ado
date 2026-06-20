*! fastm 0.5.0  Structural Topic Models in Stata (engine: topica-core, Rust)
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
        [ PREValence(varlist fv ts) ///
          noLOWercase STOPwords(string) MINdocfreq(integer 1) MAXdocpct(real 100) STEM ///
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

    // Varlist order the plugin expects: text (1), theta (2..K+1), prevalence (K+2..).
    plugin call fastmplugin `varlist' `generate'1-`generate'`k' `prevvars' ///
        if `touse', fit `k' `seed' `iters' `nprev' `mindocfreq' `maxdocpct' `lower'

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

// estat dispatch (registered via e(estat_cmd)). Supports: thoughts.
program fastm_estat
    version 15.0
    gettoken sub 0 : 0, parse(" ,")
    if "`sub'" == "thoughts" {
        fastm_thoughts `0'
    }
    else {
        di as error `"unknown estat subcommand "`sub'""'
        exit 198
    }
end

// estat thoughts: list the highest-theta (representative) documents for a topic.
program fastm_thoughts
    version 15.0
    syntax , Topic(integer) [ N(integer 5) ]
    if "`e(cmd)'" != "fastm" {
        di as error "fastm results not found"
        exit 301
    }
    local kk = e(k)
    if `topic' < 1 | `topic' > `kk' {
        di as error "topic() must be in 1..`kk'"
        exit 198
    }
    local tv `e(generate)'`topic'
    capture confirm numeric variable `tv'
    if _rc {
        di as error "`tv' is not in the data (topic proportions were dropped); rerun fastm"
        exit 198
    }
    local txt `e(textvar)'
    di ""
    di as txt "Representative documents for topic `topic' (highest `tv')"
    preserve
    gsort -`tv'
    list `txt' `tv' in 1/`n', noobs
    restore
end

// predict after fastm (xtreg-style). One topic per call via topic(#).
//   pr (default) : prevalence-fitted topic proportion, softmax([X*gamma, 0])
//   xb           : prevalence linear predictor for the topic (reference topic = 0)
program fastm_predict
    version 15.0
    syntax newvarname [if] [in] , [ PR XB STDP Topic(integer 0) EQuation(passthru) ]

    if "`e(cmd)'" != "fastm" {
        di as error "fastm estimation results not found"
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
        mata: fastm_pred("`varlist'", "`touse'", "`prevvars'", "`G'", `topic', `kk', "proportions")
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
void fastm_pred(string scalar newvar, string scalar touse, string scalar prevvars,
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
capture findfile fastm.plugin
if _rc {
    di as error "fastm: fastm.plugin not found on the adopath (or current dir)"
}
else {
    capture program fastmplugin, plugin using(`"`r(fn)'"')
}
