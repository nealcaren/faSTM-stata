* M2 demo: the `fastm` command on the two-theme corpus.
* Build first:  bash build/build.sh
* Run from repo root:  do examples/cmd_demo.do

clear all
run "ado/fastm.ado"      // define the command (and load the plugin on first use)

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

fastm text, k(2) seed(42) iters(200)

list text theta1 theta2 in 1/4, noobs
ereturn list
