*! fastm_predict 0.5.1  predict handler for fastm (pr / xb / stdp)
*! In its own ado so Stata can autoload it when predict/margins is called.

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

// Mata helper for the pr path. Defined here (not in fastm.ado) so it is
// compiled whenever Stata autoloads this predict handler.
mata:
void fastm_pred(string scalar newvar, string scalar touse, string scalar prevvars,
                 string scalar Gname, real scalar topic, real scalar K, string scalar stat)
{
    real matrix G, Xcov, X, XB, full, Pr, yv, e
    real colvector out, m, s
    real scalar n
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
