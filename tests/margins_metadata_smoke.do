clear all
set more off

adopath ++ "ado"
run "ado/fastm.ado"
run "ado/fastm_predict.ado"

input str244 text
"the team won the game with a great goal by the star player"
"our coach told the players to pass the ball and take the shot"
"the striker scored twice and the goalkeeper made a fine save"
"fans cheered as the home team beat their rivals on the court"
"the player dribbled past the defender and scored the winning basket"
"a hard fought match ended when the team scored a late goal"
"preheat the oven and bake the cake until the sponge is golden"
"mix the flour sugar and butter then knead the dough for the bread"
"add a pinch of salt to the soup and let the stew simmer slowly"
"whisk the eggs and fold in the flour to make a light batter"
"roast the vegetables in the oven and season the sauce with herbs"
"the recipe needs fresh dough fresh flour and a hot oven to bake"
end

generate byte sporty = (_n <= 6)
fastm text, k(2) prevalence(i.sporty) seed(42) iters(200)

assert "`e(marginsok)'" == "XB default"
assert strpos("`e(marginsnotok)'", "STDP")

capture noisily margins i.sporty
assert _rc == 0
capture noisily margins i.sporty, predict(equation(topic1))
assert _rc == 0
capture noisily margins i.sporty, predict(equation(topic1)) noestimcheck
assert _rc == 0

fastm text, k(2) seed(42) iters(50) replace
assert "`e(marginsnotok)'" == "_ALL"
capture noisily margins, predict(pr topic(1))
assert _rc != 0

display as result "margins metadata smoke OK"
