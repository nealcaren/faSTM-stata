// Covers the API cleanups made for the Stata Journal submission:
//   * predict requires topic() unless margins supplies equation()
//   * stem is no longer a recognized option
//   * estat labels/perspectives clamp n() to the stored word count with a note
clear all
set more off

adopath ++ "ado"
run "ado/fastm.ado"
run "ado/fastm_predict.ado"
run "ado/fastm_estat.ado"
run "ado/searchk.ado"

set obs 12
generate str80 text = ""
replace text = "apple orange banana fruit sweet" in 1/6
replace text = "train bus rail transit station" in 7/12
generate byte group = _n > 6

// stem is gone from both commands
capture noisily fastm text, k(2) seed(42) iters(50) stem
assert _rc == 198
capture noisily searchk text, k(2) stem
assert _rc == 198

fastm text, k(2) prevalence(i.group) seed(42) iters(50) generate(theta)

// pr has no defensible default topic, so topic() is required
capture noisily predict p_bad, pr
assert _rc == 198

// xb/stdp follow Stata's multiequation rule: no equation means the first one
predict xb1, xb
predict xb1b, xb topic(1)
assert reldif(xb1, xb1b) < 1e-12 if e(sample)

predict p1, pr topic(1)
assert p1 < . if e(sample)

// both margins paths must keep working
margins i.group
margins i.group, predict(equation(topic1))

// The engine stores 10 ranked words per topic, so n() up to 10 is honored...
local stored : word count `e(lbl_frex_1)'
assert `stored' == 10
estat labels, type(frex) n(7)
estat labels, type(frex) n(10)

// ...and beyond that estat clamps with a note rather than truncating silently
estat labels, type(frex) n(40)

// t() means topic() everywhere, including here, where type() must be spelled ty
estat labels, t(2) n(3)
estat labels, ty(prob) n(3)
capture noisily estat labels, t(frex)
assert _rc == 198

display "api_cleanup_smoke: OK"
