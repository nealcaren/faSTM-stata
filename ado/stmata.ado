*! stmata 0.1.0  Structural Topic Models in Stata (engine: topica-core, Rust)
*! Syntax:  stmata textvar [if] [in], k(#) [seed(#) iters(#) prefix(name) replace]
program stmata, eclass
    version 15.0
    syntax varname [if] [in], K(integer) ///
        [ SEED(integer 42) ITERs(integer 200) PREfix(name) replace ]

    if `k' < 2 {
        di as error "k() must be >= 2"
        exit 198
    }
    if "`prefix'" == "" local prefix theta

    // Sample: honors if/in and drops empty/missing text (strok = string ok).
    marksample touse, strok

    // Create the K topic-proportion variables the plugin writes into.
    forvalues t = 1/`k' {
        capture confirm new variable `prefix'`t'
        if _rc & "`replace'" == "" {
            di as error "`prefix'`t' already exists; use replace or a different prefix()"
            exit 110
        }
        capture drop `prefix'`t'
        quietly generate double `prefix'`t' = .
    }

    // text var (1) then the K theta vars (2..K+1); plugin honors `touse'.
    plugin call stmataplugin `varlist' `prefix'1-`prefix'`k' if `touse', fit `k' `seed' `iters'

    ereturn clear
    ereturn scalar k       = scalar(stmata_K)
    ereturn scalar n_terms = scalar(stmata_V)
    ereturn scalar N_docs  = scalar(stmata_D)
    ereturn scalar bound  = scalar(stmata_bound)
    ereturn scalar iters  = scalar(stmata_iters)
    ereturn local prefix  "`prefix'"
    ereturn local textvar "`varlist'"
    ereturn local cmd     "stmata"

    di ""
    di as txt "Structural Topic Model" ///
        _col(48) "Documents      = " as res %9.0fc e(N_docs)
    di as txt "Engine: topica-core (Rust)" ///
        _col(48) "Vocabulary     = " as res %9.0fc e(n_terms)
    di as txt _col(48) "Topics (K)     = " as res %9.0fc e(k)
    di as txt _col(48) "Final bound    = " as res %9.2f e(bound)
    di as txt "Topic proportions written to " as res "`prefix'1-`prefix'`k'" ///
        as txt " (EM iters " as res %9.0f e(iters) as txt ")"
end

// --------------------------------------------------------------------------
// One-time plugin load. This is BARE top-level code (not inside a program):
// a plugin loaded inside a running program does not register for `plugin call`
// in other scopes, so it must load here, when this ado is sourced/auto-loaded.
// --------------------------------------------------------------------------
capture findfile stmata.plugin
if _rc {
    di as error "stmata: stmata.plugin not found on the adopath (or current dir)"
}
else {
    capture program stmataplugin, plugin using(`"`r(fn)'"')
}
