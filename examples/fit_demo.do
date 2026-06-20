* M1 demo: fit a 2-topic STM on a tiny two-theme corpus and write theta back.
* Build first:  bash build/build.sh   (-> ./stmata.plugin)
* Run from repo root:  do examples/fit_demo.do

capture program drop stmata
program stmata, plugin using("stmata.plugin")

clear
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

local K = 2
forvalues t = 1/`K' {
    gen double theta`t' = .
}

plugin call stmata text theta1 theta2, fit `K' 42 200

list text theta1 theta2 in 1/12, noobs
di as result "K=" stmata_K "  V=" stmata_V "  D=" stmata_D ///
    "  bound=" %9.2f stmata_bound "  iters=" stmata_iters
