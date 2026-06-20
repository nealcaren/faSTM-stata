// spline_demo.do  --  smooth (B-spline) prevalence terms, like stm's s().
// Run from the repo root:  do examples/spline_demo.do
adopath ++ "`c(pwd)'/ado"
run "ado/fastm.ado"

clear
input str244 text
"the team won the game with a great goal by the star player striker"
"our coach told the players to pass the ball and take the shot goal"
"the striker scored twice and the goalkeeper made a fine save player"
"fans cheered as the home team beat their rivals on the court game"
"the player dribbled past the defender and scored the winning basket net"
"a hard fought match ended when the team scored a late goal win"
"preheat the oven and bake the cake until the sponge is golden flour"
"mix the flour sugar and butter then knead the dough for the bread oven"
"add a pinch of salt to the soup and let the stew simmer bake heat"
"whisk the eggs and fold in the flour to make a light batter cake"
"roast the vegetables in the oven and season the sauce with herbs salt"
"the recipe needs fresh dough fresh flour and a hot oven to bake pie"
end
gen day = _n

// A smooth trend in topic prevalence over `day' (df=5 B-spline basis).
fastm text, k(2) stopwords(english) spline(day, df(5)) seed(7)

// The basis columns are ordinary prevalence terms: jointly test the trend.
test [topic1]day_s1 [topic1]day_s2 [topic1]day_s3 [topic1]day_s4 [topic1]day_s5

// Mix a factor covariate with a smooth term.
gen byte genre = _n > 6
fastm text, k(2) stopwords(english) prevalence(i.genre) spline(day, df(4)) seed(7) replace
