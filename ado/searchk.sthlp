{smcl}
{* *! version 0.2.0  searchk}{...}
{viewerjumpto "Syntax" "searchk##syntax"}{...}
{viewerjumpto "Description" "searchk##description"}{...}
{viewerjumpto "Examples" "searchk##examples"}{...}
{title:Title}

{phang}
{cmd:searchk} {hline 2} Choose the number of topics for {help fastm:fastm}


{marker syntax}{...}
{title:Syntax}

{p 8 15 2}
{cmd:searchk} {varname} {ifin}{cmd:,} {opt k(numlist)} [{it:options}]

{synoptset 24 tabbed}{...}
{synopthdr}
{synoptline}
{synopt:{opt k(numlist)}}topic counts to evaluate (each >=2); required{p_end}
{synopt:{opt held:out(#)}}percent of each document's tokens held out; default
{cmd:heldout(50)}; must be in (0,100){p_end}
{synopt:{opt preval:ence(varlist)}}prevalence covariates (factor variables allowed){p_end}
{synopt:{opt seed(#)} {opt iter:s(#)}}as in {help fastm:fastm}{p_end}
{synopt:{it:prep options}}{opt stop:words()}, {opt min:docfreq()},
{opt max:docpct()}, {opt nolow:ercase} — as in {help fastm:fastm}{p_end}
{synoptline}


{marker description}{...}
{title:Description}

{pstd}
{cmd:searchk} fits {help fastm:fastm} at each requested number of topics and
reports diagnostics for choosing K, using the same engine and preprocessing as
{cmd:fastm}. For each K it holds out a fraction of every document's tokens, fits
on the rest, and scores the held-out tokens (document completion). It reports the
held-out log-likelihood per token, mean semantic coherence, mean exclusivity, and
the final bound. Higher held-out likelihood and coherence are better; the choice
of K is left to you.

{marker examples}{...}
{title:Examples}

{phang2}{cmd:. searchk abstract, k(5(5)30)}{p_end}
{phang2}{cmd:. searchk abstract, k(10 20 30) prevalence(i.party) stopwords(english) mindocfreq(5)}{p_end}
{phang2}{cmd:. matrix list r(table)}{p_end}


{marker results}{...}
{title:Stored results}

{pstd}{cmd:searchk} stores the following in {cmd:r()}:

{synoptset 22 tabbed}{...}
{p2col 5 22 26 2: Macros}{p_end}
{synopt:{cmd:r(cmd)}}{cmd:searchk}{p_end}

{p2col 5 22 26 2: Matrices}{p_end}
{synopt:{cmd:r(table)}}one row per K, with columns {cmd:k}, held-out
log-likelihood per token, mean semantic coherence, mean exclusivity, and the
final bound{p_end}


{title:Also see}

{psee}{help fastm:fastm}{p_end}
