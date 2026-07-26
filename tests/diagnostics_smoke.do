* Regression tests for the diagnostics features: searchk residual dispersion (#11)
* and multi-start per-candidate diagnostics (#5). Runs against the shipped plugin.
clear all
set more off
adopath ++ "ado"
run "ado/fastm.ado"
run "ado/fastm_predict.ado"
run "ado/searchk.ado"

set obs 60
set seed 424242
generate str100 text = ""
replace text = "tax budget deficit economy jobs spending revenue fiscal" if mod(_n,3)==0
replace text = "election vote campaign senate congress party ballot poll" if mod(_n,3)==1
replace text = "climate energy carbon emissions warming policy renewable" if mod(_n,3)==2

* #11: searchk reports a residual-dispersion column (stm searchK residuals).
searchk text, k(2 3 4) heldout(30) seed(42) iters(40)
matrix S = r(table)
local cn : colnames S
assert strpos("`cn'", "residuals") > 0
assert colsof(S) == 6
forvalues r = 1/`=rowsof(S)' {
    assert S[`r', 6] < . & S[`r', 6] > 0
}

* #5: multi-start reports per-candidate diagnostics; kept model has the best bound.
fastm text, k(3) nstart(4) seed(7) iters(40) generate(th) replace
matrix ND = e(nstart_diag)
assert rowsof(ND) == 4
assert colsof(ND) == 3
local ndc : colnames ND
assert strpos("`ndc'", "bound") > 0
assert strpos("`ndc'", "coherence") > 0
assert strpos("`ndc'", "exclusivity") > 0
forvalues s = 1/4 {
    assert ND[`s', 1] < .
}
mata: st_numscalar("mx", colmax(st_matrix("ND")[,1])[1])
assert reldif(e(bound), mx) < 1e-6

* nstart(1) (default) is a single deterministic start (no multi-start selection).
fastm text, k(3) seed(7) iters(40) generate(tt) replace
assert e(nstart) == 1

display as result "diagnostics smoke OK"
