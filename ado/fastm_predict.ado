*! fastm_predict 0.7.0  predict handler for fastm (pr / xb / stdp)
*! In its own ado so Stata can autoload it when predict/margins is called.

// predict after fastm (xtreg-style). One topic per call via topic(#).
//   pr (default) : fitted document-topic proportion
//   xb           : prevalence linear predictor for the topic (reference topic = 0)
program fastm_predict
    version 15.0
    syntax newvarname [if] [in] , [ PR XB STDP Topic(integer 0) EQuation(passthru) ]

    if "`e(cmd)'" != "fastm" {
        di as error "fastm estimation results not found"
        exit 301
    }
    marksample touse, novarlist

    local nstat = ("`pr'" != "") + ("`xb'" != "") + ("`stdp'" != "")
    if `nstat' > 1 {
        di as error "only one of pr, xb, or stdp may be specified"
        exit 198
    }

    local kk = e(k)

    // Which statistic are we producing? With none named, xb is the default for a
    // model carrying posted prevalence effects and pr otherwise.
    local stat "`pr'`xb'`stdp'"
    if "`stat'" == "" {
        if e(n_prevalence) > 0 | `"`equation'"' != "" local stat xb
        else local stat pr
    }

    // pr names a topic and nothing else, so there is no defensible default:
    // silently returning topic 1 would be a wrong answer, not a convention.
    // xb and stdp follow Stata's rule for multiequation models, where an
    // unspecified equation means the first one -- this is also how margins
    // calls us.
    if `topic' == 0 {
        if "`stat'" == "pr" & `"`equation'"' == "" {
            di as error "topic() is required"
            exit 198
        }
        local topic 1
    }
    if `topic' < 1 | `topic' > `kk' {
        di as error "topic() must be in 1..`kk'"
        exit 198
    }

    if "`stat'" == "pr" {
        local tv `e(generate)'`topic'
        capture confirm numeric variable `tv'
        if _rc {
            di as error "`tv' is not in the data (topic proportions were dropped); rerun fastm"
            exit 198
        }
        quietly generate double `varlist' = `tv' if `touse'
        exit
    }

    // xb / stdp: the estimateEffect linear prediction for one topic equation,
    // via the native engine (margins-compatible, delta-method SEs).
    if "`e(prevalence)'" == "" & e(n_prevalence) == 0 {
        di as error "xb and stdp require a model fit with prevalence() or spline()"
        exit 459
    }
    if `"`equation'"' == "" {
        local equation equation(topic`topic')
    }
    _predict `typlist' `varlist' if `touse', `stat' `equation'
end
