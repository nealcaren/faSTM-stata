* Regression tests for the ado-layer fidelity fixes (issues #3, #4, #8, #9).
* Runs against the shipped plugin; no engine rebuild required.
clear all
set more off
adopath ++ "ado"
run "ado/fastm.ado"
run "ado/fastm_predict.ado"
run "ado/fastm_estat.ado"

* ---------------------------------------------------------------------------
* #3: predict xb/stdp and (plain) margins work after spline(); the B-spline
*     basis columns persist as real variables named to match e(b).
* ---------------------------------------------------------------------------
set obs 20
set seed 12345
generate str80 text = ""
replace text = "apple orange banana fruit sweet juice" if mod(_n,2)==0
replace text = "train bus rail transit station metro" if mod(_n,2)==1
generate double year = 1990 + _n

fastm text, k(2) spline(year, df(4)) seed(42) iters(40) generate(th) replace
predict xbs, xb topic(1)
assert xbs < . if e(sample)
predict ses, stdp topic(1)
assert ses < . if e(sample)
margins, predict(equation(topic1))          // plain margins over observed values
confirm variable year_s1 year_s2 year_s3    // basis persisted, matches e(b) names

* ---------------------------------------------------------------------------
* #8: generate() is all-or-nothing -- a conflict on a later topic must not
*     leave earlier topic vars behind.
* ---------------------------------------------------------------------------
clear
set obs 12
generate str80 text = "apple orange banana"
replace text = "train bus rail" in 7/12
generate double tp2 = 99                     // pre-existing conflict on topic 2
capture noisily fastm text, k(3) seed(1) iters(30) generate(tp)
assert _rc == 110
capture confirm variable tp1                 // tp1 must NOT have been created
assert _rc != 0

* ---------------------------------------------------------------------------
* #9.1: negative seed() is rejected (was silently coerced to 42 by the engine).
* ---------------------------------------------------------------------------
capture noisily fastm text, k(2) seed(-5) iters(20) generate(zz)
assert _rc == 198

* ---------------------------------------------------------------------------
* #9.2 + #4: estat labels range guard; estat thoughts runs under if.
* ---------------------------------------------------------------------------
fastm text if _n <= 10, k(2) seed(42) iters(30) generate(qq) replace
capture noisily estat labels, topic(99)
assert _rc == 198
estat thoughts, topic(1) n(2)

* ---------------------------------------------------------------------------
* #7: content() missing rows are excluded before the spline basis is built, so
*     a content-missing row is out of e(sample) and its basis cells are missing.
* ---------------------------------------------------------------------------
clear
set obs 20
set seed 777
generate str80 text = ""
replace text = "apple orange banana fruit sweet juice" if mod(_n,2)==0
replace text = "train bus rail transit station metro" if mod(_n,2)==1
generate double year = 1990 + _n
generate byte grp = mod(_n,2)
replace grp = . in 5                          // content missing on one row
fastm text, k(2) spline(year, df(4)) content(grp) seed(9) iters(30) generate(cc) replace
assert e(sample) == 0 in 5                     // content-missing row dropped
assert missing(year_s1) in 5                   // its basis cells are missing too

display as result "fidelity fixes smoke OK"
