clear all
set more off

adopath ++ "ado"
run "ado/searchk.ado"

set obs 12
generate str80 text = ""
replace text = "apple orange banana fruit sweet" in 1/6
replace text = "train bus rail transit station" in 7/12
generate byte group = _n > 6

searchk text, k(2 3) prevalence(i.group) seed(42) iters(25) heldout(40)
matrix T = r(table)
assert rowsof(T) == 2
assert colsof(T) == 5
assert T[1,1] == 2
assert T[2,1] == 3

display as result "searchk smoke OK"
