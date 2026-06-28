*------------------------------------------------------------------------------
* fastm_sj_replication.do
*
* Replication file for:
*   Caren, N. "fastm: Structural topic models in Stata." The Stata Journal.
*
* Reproduces every command and result in Section 4 (the worked example on the
* poliblog corpus), including Figure 1. The code below is exactly the code shown
* in the article; the only additions are the install step, the log, and the
* graph export that saves Figure 1.
*
* To run: place this file and poliblog.dta in the same folder, set that folder
* as the working directory, and do this file. fastm ships precompiled plugins
* for Linux, macOS, and Windows, so no Python or Rust toolchain is required.
*------------------------------------------------------------------------------

clear all
set more off
capture log close
log using "fastm_sj_replication.log", replace text

*--- Install fastm (with searchk) from GitHub ---------------------------------
net install fastm, ///
    from("https://raw.githubusercontent.com/nealcaren/faSTM-stata/main/ado") replace
discard          // drop any fastm already in memory so the fresh install loads
which fastm

*==============================================================================
* 4  Example: a corpus of political blogs
*==============================================================================
use poliblog, clear
describe text liberal day
list liberal day in 1/5, noobs

*--- 4.1  Fitting a model and reading the topics ------------------------------
fastm text, k(20) seed(2138)
estat labels, type(frex) n(7)
estat thoughts, topic(4) n(2)

*--- 4.2  Conditioning prevalence on a covariate ------------------------------
fastm text, k(20) prevalence(i.liberal) seed(2138) replace
estat labels, type(frex) n(6) topic(8)
test [topic8]1.liberal
margins liberal, predict(equation(topic8))
marginsplot
graph export "fig_topic8.eps", replace          // Figure 1
graph export "fig_topic8.png", width(1600) replace
predict p8, pr topic(8)
summarize p8

*--- 4.3  A smooth trend over time --------------------------------------------
fastm text, k(20) prevalence(i.liberal) spline(day, df(5)) seed(2138) replace
estat labels, type(frex) n(5) topic(15)
test [topic15]day_s1 [topic15]day_s2 [topic15]day_s3 [topic15]day_s4 ///
     [topic15]day_s5

*--- 4.4  How groups word the same topic --------------------------------------
fastm text, k(20) content(liberal) seed(2138) replace
estat perspectives, topic(4) n(8)

*--- 4.5  Saving and reusing the fitted model ---------------------------------
fastm text, k(20) seed(2138) saving(poliblog_beta, replace) replace
preserve
use poliblog_beta, clear
gsort -topic8
list word topic8 in 1/8, noobs sep(0)
restore

*--- 4.6  Choosing the number of topics ---------------------------------------
searchk text, k(10 20 30) seed(2138)

log close
*------------------------------------------------------------------------------
* End of replication. Section 4.7 (agreement with stm) is reproduced separately
* by the R + Stata scripts in the package's tests/parity directory.
*------------------------------------------------------------------------------
