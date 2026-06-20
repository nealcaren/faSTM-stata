* M0 smoke test for the fastm plugin.
* Build first:  bash build/build.sh   (produces ./fastm.plugin in the repo root)
* Then run this from the repo root:  do examples/hello.do

capture program drop fastm
program fastm, plugin using("fastm.plugin")

sysuse auto, clear
gen double doubled = .

* Pass two variables: mpg (input, j=1) and doubled (output, j=2).
plugin call fastm mpg doubled

list mpg doubled in 1/5
di as result "fastm_mean (should equal mean of mpg) = " fastm_mean
summarize mpg, meanonly
di as result "Stata's mean of mpg               = " r(mean)
