// content_demo.do  --  a content covariate (stm's SAGE model).
// A content covariate explains how a topic's words differ across groups, rather
// than which topics a document is about (that is prevalence).
// Run from the repo root:  do examples/content_demo.do
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
gen byte source = mod(_n, 2)        // a two-level content covariate

// Fit a content (SAGE) model: topic-word distributions shift by `source'.
fastm text, k(2) stopwords(english) content(source) seed(7)

// A content covariate combines with prevalence covariates.
gen byte era = _n > 6
fastm text, k(2) stopwords(english) prevalence(i.era) content(source) seed(7) replace
