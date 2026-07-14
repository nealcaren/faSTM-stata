clear all
set more off

adopath ++ "ado"
run "ado/fastm.ado"
run "ado/fastm_predict.ado"

set obs 12
generate str80 text = ""
replace text = "apple orange banana fruit sweet" in 1/6
replace text = "train bus rail transit station" in 7/12
generate byte group = _n > 6

fastm text, k(2) seed(42) iters(50) generate(theta)
predict p1, pr topic(1)
assert p1 < . if e(sample)
capture noisily predict xb1, xb topic(1)
assert _rc == 459

fastm text, k(2) prevalence(i.group) seed(42) iters(50) generate(tp) replace
predict pp1, pr topic(1)
predict xb2, xb topic(1)
predict se2, stdp topic(1)
assert pp1 < . if e(sample)
assert xb2 < . if e(sample)
assert se2 < . if e(sample)

clear
set obs 13
generate str80 text = ""
replace text = "apple orange banana fruit sweet" in 1/6
replace text = "train bus rail transit station" in 7/12
replace text = "" in 13
fastm text, k(2) seed(42) iters(50) generate(theta)
assert e(sample) == 0 in 13
assert missing(theta1) in 13
quietly count if e(sample)
assert r(N) == e(N_docs)

display as result "predict smoke OK"
