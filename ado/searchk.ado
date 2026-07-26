*! searchk 0.2.0  K selection for fastm (held-out likelihood + coherence/exclusivity)
*! searchk textvar [if] [in], k(numlist) [prevalence(...) heldout(#) <prep opts>]
program searchk, rclass
    version 15.0
    syntax varname [if] [in], K(numlist integer >=2 sort) ///
        [ PREValence(varlist fv ts) HELDout(real 50) ///
          noLOWercase STOPwords(string) MINdocfreq(integer 1) MAXdocpct(real 100) ///
          SEED(integer 42) ITERs(integer 200) ]

    confirm string variable `varlist'
    if `seed' < 0 {
        di as error "seed() must be a non-negative integer"
        exit 198
    }
    if `iters' < 1 {
        di as error "iters() must be positive"
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
    if `heldout' <= 0 | `heldout' >= 100 {
        di as error "heldout() must be in (0,100)"
        exit 198
    }
    local lower = ("`lowercase'" != "nolowercase")

    // stopwords() -> file path the plugin loads (same resolution as fastm).
    // The plugin API has no string-option channel, so this path is passed by a
    // transient global and cleared after the search.
    local stopfile ""
    if "`stopwords'" != "" & "`stopwords'" != "none" {
        if "`stopwords'" == "english" {
            capture findfile fastm_english.stops
            if _rc {
                di as error "english stopword list not found on the adopath"
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
    global fastm_betafile ""

    marksample touse, strok

    // prevalence() -> numeric design tempvars (drop base/omitted), same as fastm.
    local prevvars ""
    if "`prevalence'" != "" {
        fvexpand `prevalence'
        local expnames `r(varlist)'
        fvrevar `prevalence'
        local revars `r(varlist)'
        local i 0
        foreach nm of local expnames {
            local ++i
            local tv : word `i' of `revars'
            if !strmatch("`nm'", "*b.*") & !strmatch("`nm'", "*o.*") local prevvars `prevvars' `tv'
        }
        markout `touse' `prevvars'
    }
    local nprev : word count `prevvars'

    local nk : word count `k'
    tempname SK
    matrix `SK' = J(`nk', 6, .)
    matrix colnames `SK' = K heldout_ll coherence exclusivity bound residuals

    local r 0
    local rn ""
    foreach kk of local k {
        local ++r
        local rn `rn' k`kk'
        plugin call fastmplugin `varlist' `prevvars' if `touse', ///
            searchk `kk' `seed' `iters' `nprev' `heldout' `mindocfreq' `maxdocpct' `lower'
        matrix `SK'[`r',1] = `kk'
        matrix `SK'[`r',2] = scalar(fastm_sk_heldout)
        matrix `SK'[`r',3] = scalar(fastm_sk_coh)
        matrix `SK'[`r',4] = scalar(fastm_sk_excl)
        matrix `SK'[`r',5] = scalar(fastm_sk_bound)
        matrix `SK'[`r',6] = scalar(fastm_sk_resid)
    }
    capture macro drop fastm_stopfile
    capture macro drop fastm_betafile
    matrix rownames `SK' = `rn'

    di ""
    di as txt "fastm model selection" ///
        _col(40) "held-out: " as res %4.0f `heldout' as txt "% of tokens per doc"
    di as txt "(higher held-out LL and coherence are better; residuals near 1 are" ///
        _n "  better -- residuals >> 1 suggest K is too small, Taddy 2012)"
    matlist `SK', border(rows) format(%10.3f)
    return matrix table = `SK'
    return local cmd "searchk"
end

// Plugin load: BARE top-level code (auto-load runs this; an in-program load does
// not persist). Dev build first, else the per-OS plugin shipped with the package.
// This block is intentionally duplicated from fastm.ado so either command can
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
