{smcl}
{* *! version 0.4.0  fastm}{...}
{vieweralsosee "" "--"}{...}
{viewerjumpto "Syntax" "fastm##syntax"}{...}
{viewerjumpto "Description" "fastm##description"}{...}
{viewerjumpto "Options" "fastm##options"}{...}
{viewerjumpto "Examples" "fastm##examples"}{...}
{viewerjumpto "Stored results" "fastm##results"}{...}
{title:Title}

{phang}
{cmd:fastm} {hline 2} Structural Topic Models (engine: topica-core, Rust)


{marker syntax}{...}
{title:Syntax}

{p 8 15 2}
{cmd:fastm} {varname} {ifin}{cmd:,} {opt k(#)} [{it:options}]

{pstd}
where {varname} is a string variable holding one document per observation.

{synoptset 24 tabbed}{...}
{synopthdr}
{synoptline}
{syntab:Model}
{synopt:{opt k(#)}}number of topics ({cmd:k}>=2); required{p_end}
{synopt:{opt preval:ence(varlist)}}prevalence covariates; factor variables
({cmd:i.}, {cmd:c.}, {cmd:##}) allowed{p_end}
{synopt:{opt iter:s(#)}}maximum EM iterations; default {cmd:iters(200)}{p_end}
{synopt:{opt seed(#)}}random seed (used for random init and the effect draws);
default {cmd:seed(42)}{p_end}

{syntab:Output}
{synopt:{opt gen:erate(name)}}stub for the topic-proportion variables; default
{cmd:generate(theta)}{p_end}
{synopt:{opt replace}}overwrite existing topic-proportion variables{p_end}
{synoptline}


{marker description}{...}
{title:Description}

{pstd}
{cmd:fastm} fits a Structural Topic Model to a corpus held in a Stata string
variable, one document per observation. Fitting (logistic-normal variational EM
with spectral initialization), tokenization, FREX/coherence/exclusivity, and
covariate-effect estimation all run in {cmd:topica-core}, a self-contained Rust
engine, through a compiled plugin. No Python or Rust toolchain is required to use
the command.

{pstd}
The command writes each document's topic proportions to {it:generate}1 ..
{it:generate}{cmd:k}. With {opt prevalence()}, it conditions the topic prevalence
on the covariates and reports their effects on each topic's proportion by the
method of composition, with standard errors that propagate the per-document
topic-estimation uncertainty.

{pstd}
Typing {cmd:fastm} without arguments redisplays the last fit.


{marker options}{...}
{title:Options}

{phang}{opt k(#)} sets the number of topics; required, must be at least 2.

{phang}{opt prevalence(varlist)} lists prevalence covariates. Factor-variable and
time-series operators are allowed (e.g. {cmd:i.party c.year i.party##c.year}); the
design is expanded with base/omitted levels dropped, and an intercept is added.

{phang}{opt iters(#)} caps the EM iterations (default 200); the fit stops earlier
on convergence.

{phang}{opt seed(#)} sets the random seed (default 42).

{phang}{opt generate(name)} sets the stub for the created topic-proportion
variables (default {cmd:theta}).

{phang}{opt replace} overwrites existing {it:generate}# variables.


{marker examples}{...}
{title:Examples}

{pstd}Fit 20 topics on a text variable:{p_end}
{phang2}{cmd:. fastm abstract, k(20)}{p_end}

{pstd}With prevalence covariates and an interaction:{p_end}
{phang2}{cmd:. fastm abstract, k(20) prevalence(i.party c.year i.party##c.year)}{p_end}

{pstd}On a subsample, with a custom variable stub:{p_end}
{phang2}{cmd:. fastm speech if chamber==1, k(15) generate(tp)}{p_end}

{pstd}Redisplay the last fit:{p_end}
{phang2}{cmd:. fastm}{p_end}


{marker results}{...}
{title:Stored results}

{pstd}{cmd:fastm} stores the following in {cmd:e()}:

{synoptset 22 tabbed}{...}
{p2col 5 22 26 2: Scalars}{p_end}
{synopt:{cmd:e(k)}}number of topics{p_end}
{synopt:{cmd:e(n_terms)}}vocabulary size after tokenization{p_end}
{synopt:{cmd:e(N_docs)}}documents fit{p_end}
{synopt:{cmd:e(bound)}}final evidence bound (ELBO){p_end}
{synopt:{cmd:e(iters)}}EM iterations run{p_end}
{synopt:{cmd:e(coherence)}}mean semantic coherence{p_end}
{synopt:{cmd:e(exclusivity)}}mean exclusivity{p_end}
{synopt:{cmd:e(n_prevalence)}}number of prevalence terms{p_end}

{p2col 5 22 26 2: Macros}{p_end}
{synopt:{cmd:e(cmd)}}{cmd:fastm}{p_end}
{synopt:{cmd:e(textvar)}}name of the text variable{p_end}
{synopt:{cmd:e(prevalence)}}prevalence specification{p_end}
{synopt:{cmd:e(prev_terms)}}expanded prevalence term names{p_end}
{synopt:{cmd:e(generate)}}topic-proportion variable stub{p_end}

{p2col 5 22 26 2: Matrices}{p_end}
{synopt:{cmd:e(b)}}covariate-effect coefficients (one equation per topic){p_end}
{synopt:{cmd:e(V)}}their covariance (block-diagonal by topic){p_end}
{synopt:{cmd:e(gamma)}}prevalence coefficients (design x K-1){p_end}


{marker postestimation}{...}
{title:Postestimation}

{pstd}{cmd:fastm} posts {cmd:e(b)}/{cmd:e(V)} (the method-of-composition effects,
one equation per topic), so the usual tools apply:{p_end}
{phang2}{cmd:. test [topic1]1.party}{p_end}
{phang2}{cmd:. lincom [topic1]year - [topic2]year}{p_end}
{phang2}{cmd:. margins party, predict(equation(topic1))}{p_end}
{phang2}{cmd:. marginsplot}{p_end}

{pstd}{cmd:predict} after {cmd:fastm} (one topic per call):{p_end}
{synoptset 30 tabbed}{...}
{synopt:{cmd:predict} {it:nv}{cmd:, xb topic(}{it:#}{cmd:)}}estimateEffect linear prediction{p_end}
{synopt:{cmd:predict} {it:nv}{cmd:, stdp topic(}{it:#}{cmd:)}}its standard error{p_end}
{synopt:{cmd:predict} {it:nv}{cmd:, pr topic(}{it:#}{cmd:)}}prevalence-fitted proportion, softmax(X*gamma){p_end}


{title:Author}

{pstd}Neal Caren. Engine: {cmd:topica-core}. Cite the Structural Topic Model
(Roberts, Stewart, and Tingley).
