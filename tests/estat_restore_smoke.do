clear all
set more off

adopath ++ "ado"
run "ado/fastm.ado"
run "ado/fastm_estat.ado"

input str244 text byte group
"the team won the game with a great goal by the star player" 0
"our coach told the players to pass the ball and take the shot" 0
"the striker scored twice and the goalkeeper made a fine save" 0
"fans cheered as the home team beat their rivals on the court" 0
"the player dribbled past the defender and scored the winning basket" 0
"a hard fought match ended when the team scored a late goal" 0
"preheat the oven and bake the cake until the sponge is golden" 1
"mix the flour sugar and butter then knead the dough for the bread" 1
"add a pinch of salt to the soup and let the stew simmer slowly" 1
"whisk the eggs and fold in the flour to make a light batter" 1
"roast the vegetables in the oven and season the sauce with herbs" 1
"the recipe needs fresh dough fresh flour and a hot oven to bake" 1
end

fastm text, k(2) content(group) seed(42) iters(50)
assert "`e(lbl_frex_1)'" != ""
assert "`e(clev_0)'" != ""
assert "`e(persp_0_1)'" != ""
estimates store content_model

fastm text, k(2) seed(99) iters(25) replace
estimates restore content_model

capture noisily estat labels, topic(1) n(3)
assert _rc == 0
capture noisily estat perspectives, topic(1) n(3)
assert _rc == 0

display as result "estat restore smoke OK"
