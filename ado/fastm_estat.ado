*! fastm_estat 0.6.0  estat dispatch for fastm (labels, thoughts, perspectives)
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

// The engine stores a fixed number of ranked words per topic (10), so n() cannot
// exceed what was saved. Clamp rather than truncate silently; the full topic-word
// matrix is available through fastm's saving() option if more words are wanted.
program fastm_clamp_n, rclass
    version 15.0
    args want have
    if `have' > 0 & `want' > `have' {
        di as txt "note: only `have' words per topic are stored; showing `have'"
        return scalar n = `have'
    }
    else {
        return scalar n = `want'
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
    local stored : word count `e(persp_0_`topic')'
    fastm_clamp_n `n' `stored'
    local n = r(n)
    di ""
    di as txt "Topic `topic' by content level (`e(content)'): distinctive words"
    forvalues g = 0/`=`ng' - 1' {
        local clevname clev_`g'
        local perspname persp_`g'_`topic'
        local nm `"`e(`clevname')'"'
        if `"`nm'"' == "" local nm "level `g'"
        local words `"`e(`perspname')'"'
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
    // type() takes the abbreviation ty, not t: t() is topic() in every other
    // estat subcommand and in predict, and a silent misbinding here would be
    // worse than typing one more letter.
    syntax , [ TYpe(string) N(integer 7) Topic(integer 0) ]
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
    // topic(0) means "all"; anything else must be a real topic (thoughts and
    // perspectives already guard this -- labels silently showed nothing).
    if `topic' < 0 | `topic' > `kk' {
        di as error "topic() must be in 1..`kk'"
        exit 198
    }
    local stored : word count `e(lbl_`type'_1)'
    fastm_clamp_n `n' `stored'
    local n = r(n)
    di ""
    di as txt "Topic labels (`type', top `n')"
    forvalues t = 1/`kk' {
        if `topic' == 0 | `topic' == `t' {
            local lblname lbl_`type'_`t'
            local words `"`e(`lblname')'"'
            local show ""
            forvalues j = 1/`n' {
                local w : word `j' of `words'
                if "`w'" != "" local show `show' `w'
            }
            di as txt "Topic " %2.0f `t' ":  " as result "`show'"
        }
    }
end

// estat thoughts: the highest-theta (representative) documents for a topic.
// Documents are printed as wrapped excerpts rather than through -list-, which
// truncates a long string variable to the width of one column.
program fastm_thoughts
    version 15.0
    syntax , Topic(integer) [ N(integer 5) Chars(integer 240) DETail ]
    if "`e(cmd)'" != "fastm" {
        di as error "fastm results not found"
        exit 301
    }
    local kk = e(k)
    if `topic' < 1 | `topic' > `kk' {
        di as error "topic() must be in 1..`kk'"
        exit 198
    }
    if `n' < 1 {
        di as error "n() must be positive"
        exit 198
    }
    if `chars' < 1 {
        di as error "chars() must be positive"
        exit 198
    }
    local tv `e(generate)'`topic'
    capture confirm numeric variable `tv'
    if _rc {
        di as error "`tv' is not in the data (topic proportions were dropped); rerun fastm"
        exit 198
    }
    local txt `e(textvar)'

    preserve
    // Number rows in the ORIGINAL dataset before subsetting, so the reported
    // "(observation #)" points at the user's row, not the e(sample) sub-index.
    tempvar obs
    generate long `obs' = _n
    quietly keep if e(sample)
    gsort -`tv'
    local nshow = min(`n', _N)

    di ""
    di as txt "Representative documents for topic `topic' (highest `tv')"
    forvalues i = 1/`nshow' {
        local th   = `tv'[`i']
        local id   = `obs'[`i']
        local doc  = `txt'[`i']
        di ""
        di as txt "  `i'.  `tv' = " as result %6.4f `th' ///
            as txt "   (observation " as result `id' as txt ")"
        if "`detail'" == "" {
            local full = length(`"`doc'"')
            local doc  = substr(`"`doc'"', 1, `chars')
            if `full' > `chars' local doc `"`doc' ..."'
        }
        fastm_wrap `"`doc'"'
    }
    restore
end

// Print a string across as many lines as it needs, breaking at spaces.
program fastm_wrap
    version 15.0
    args doc
    local width = max(40, c(linesize) - 8)
    local rest `"`doc'"'
    while `"`rest'"' != "" {
        if length(`"`rest'"') <= `width' {
            di as result "      " `"`rest'"'
            local rest ""
        }
        else {
            local cut : display substr(`"`rest'"', 1, `width')
            local sp = strrpos(`"`cut'"', " ")
            if `sp' == 0 local sp = `width' + 1
            di as result "      " `"`=substr(`"`rest'"', 1, `sp' - 1)'"'
            local rest = trim(substr(`"`rest'"', `sp' + 1, .))
        }
    }
end
