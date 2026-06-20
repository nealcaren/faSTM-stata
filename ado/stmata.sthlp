{smcl}
{* *! version 0.4.0  stmata}{...}
{vieweralsosee "" "--"}{...}
{viewerjumpto "Syntax" "stmata##syntax"}{...}
{viewerjumpto "Description" "stmata##description"}{...}
{viewerjumpto "Options" "stmata##options"}{...}
{viewerjumpto "Examples" "stmata##examples"}{...}
{viewerjumpto "Stored results" "stmata##results"}{...}
{title:Title}

{phang}
{cmd:stmata} {hline 2} Structural Topic Models (engine: topica-core, Rust)


{marker syntax}{...}
{title:Syntax}

{p 8 15 2}
{cmd:stmata} {varname} {ifin}{cmd:,} {opt k(#)} [{it:options}]

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
{cmd:stmata} fits a Structural Topic Model to a corpus held in a Stata string
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
Typing {cmd:stmata} without arguments redisplays the last fit.


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
{phang2}{cmd:. stmata abstract, k(20)}{p_end}

{pstd}With prevalence covariates and an interaction:{p_end}
{phang2}{cmd:. stmata abstract, k(20) prevalence(i.party c.year i.party##c.year)}{p_end}

{pstd}On a subsample, with a custom variable stub:{p_end}
{phang2}{cmd:. stmata speech if chamber==1, k(15) generate(tp)}{p_end}

{pstd}Redisplay the last fit:{p_end}
{phang2}{cmd:. stmata}{p_end}


{marker results}{...}
{title:Stored results}

{pstd}{cmd:stmata} stores the following in {cmd:e()}:

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
{synopt:{cmd:e(cmd)}}{cmd:stmata}{p_end}
{synopt:{cmd:e(textvar)}}name of the text variable{p_end}
{synopt:{cmd:e(prevalence)}}prevalence specification{p_end}
{synopt:{cmd:e(prev_terms)}}expanded prevalence term names{p_end}
{synopt:{cmd:e(generate)}}topic-proportion variable stub{p_end}

{p2col 5 22 26 2: Matrices}{p_end}
{synopt:{cmd:e(effects)}}topics x terms covariate-effect coefficients{p_end}
{synopt:{cmd:e(effects_se)}}their standard errors{p_end}


{title:Author}

{pstd}Neal Caren. Engine: {cmd:topica-core}. Cite the Structural Topic Model
(Roberts, Stewart, and Tingley).
