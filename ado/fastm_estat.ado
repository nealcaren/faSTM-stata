*! fastm_estat 0.5.1  estat dispatch for fastm (labels, thoughts, perspectives)
*! In its own ado so Stata can autoload it when estat is called after fastm.

// estat dispatch (registered via e(estat_cmd)). Supports: thoughts.
program fastm_estat
    version 15.0
    gettoken sub 0 : 0, parse(" ,")
    if "`sub'" == "thoughts" {
        fastm_thoughts `0'
    }
    else if "`sub'" == "labels" {
        fastm_labels `0'
    }
    else if "`sub'" == "perspectives" {
        fastm_perspectives `0'
    }
    else {
        di as error `"unknown estat subcommand "`sub'""'
        exit 198
    }
end

// estat perspectives: for a content model, the words each content level emphasizes
// in a topic (the SAGE deviation, as stm's sageLabels). Shows the per-group contrast.
program fastm_perspectives
    version 15.0
    syntax , Topic(integer) [ N(integer 7) ]
    if "`e(cmd)'" != "fastm" {
        di as error "fastm results not found"
        exit 301
    }
    if e(n_content) == 0 {
        di as error "estat perspectives requires a content() covariate"
        exit 198
    }
    local kk = e(k)
    if `topic' < 1 | `topic' > `kk' {
        di as error "topic() must be in 1..`kk'"
        exit 198
    }
    local ng = e(n_content)
    di ""
    di as txt "Topic `topic' by content level (`e(content)'): distinctive words"
    forvalues g = 0/`=`ng' - 1' {
        local nm "${fastm_clev_`g'}"
        if `"`nm'"' == "" local nm "level `g'"
        local words "${fastm_persp_`g'_`topic'}"
        local show ""
        forvalues j = 1/`n' {
            local w : word `j' of `words'
            if "`w'" != "" local show `show' `w'
        }
        di as txt %-16s abbrev(`"`nm'"', 15) "  " as result "`show'"
    }
end

// estat labels: redisplay topic labels by score type (prob/frex/lift/score).
program fastm_labels
    version 15.0
    syntax , [ Type(string) N(integer 7) Topic(integer 0) ]
    if "`e(cmd)'" != "fastm" {
        di as error "fastm results not found"
        exit 301
    }
    if "`type'" == "" local type frex
    if !inlist("`type'", "prob", "frex", "lift", "score") {
        di as error "type() must be prob, frex, lift, or score"
        exit 198
    }
    local kk = e(k)
    di ""
    di as txt "Topic labels (`type', top `n')"
    forvalues t = 1/`kk' {
        if `topic' == 0 | `topic' == `t' {
            local words "${fastm_lbl_`type'_`t'}"
            local show ""
            forvalues j = 1/`n' {
                local w : word `j' of `words'
                if "`w'" != "" local show `show' `w'
            }
            di as txt "Topic " %2.0f `t' ":  " as result "`show'"
        }
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
