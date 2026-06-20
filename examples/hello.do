* M0 smoke test for the stmata plugin.
* Build first:  bash build/build.sh   (produces ./stmata.plugin in the repo root)
* Then run this from the repo root:  do examples/hello.do

capture program drop stmata
program stmata, plugin using("stmata.plugin")

sysuse auto, clear
gen double doubled = .

* Pass two variables: mpg (input, j=1) and doubled (output, j=2).
plugin call stmata mpg doubled

list mpg doubled in 1/5
di as result "stmata_mean (should equal mean of mpg) = " stmata_mean
summarize mpg, meanonly
di as result "Stata's mean of mpg               = " r(mean)
