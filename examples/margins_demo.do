* Postestimation demo: test / lincom / margins after fastm.
* Run from repo root after build/build.sh.

clear all
run "ado/fastm.ado"

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

gen byte sporty = (_n <= 6)

fastm text, k(2) prevalence(i.sporty) seed(42) iters(200)

* Wald test and cross-topic linear combination on the posted e(b)/e(V):
test [topic1]1.sporty
lincom [topic1]1.sporty - [topic2]1.sporty

* Predicted topic-1 proportion by the covariate (delta-method SEs):
margins i.sporty, predict(equation(topic1))
* marginsplot     // graphics: run interactively

* predict (xtreg-style):
predict p1, pr topic(1)        // model prevalence-fitted proportion
predict xb1, xb topic(1)       // estimateEffect linear prediction
predict se1, stdp topic(1)     // its standard error
list sporty theta1 p1 xb1 se1 in 1/3, noobs
