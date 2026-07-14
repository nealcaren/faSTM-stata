{smcl}
{* *! version 0.6.0  fastm}{...}
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
{synopt:{opt sp:line(varlist[, df(#) degree(#)])}}B-spline basis of continuous
covariate(s) in prevalence (stm's {cmd:s()}); default {cmd:df(10) degree(3)}{p_end}
{synopt:{opt cont:ent(varname)}}content covariate: a single categorical that
shifts topic-word distributions (stm's SAGE content model){p_end}
{synopt:{opt iter:s(#)}}maximum EM iterations; default {cmd:iters(200)}{p_end}
{synopt:{opt seed(#)}}random seed (used for random init and the effect draws);
default {cmd:seed(42)}{p_end}

{syntab:Text preprocessing}
{synopt:{opt stop:words(spec)}}{cmd:none} (default), {cmd:english}, or a
filename (one stopword per line){p_end}
{synopt:{opt min:docfreq(#)}}drop terms appearing in fewer than # documents
(#>=1);
default {cmd:mindocfreq(1)}{p_end}
{synopt:{opt max:docpct(#)}}drop terms appearing in more than #% of documents;
must be in (0,100]; default {cmd:maxdocpct(100)}{p_end}
{synopt:{opt nolow:ercase}}keep token case (default lowercases){p_end}

{syntab:Diagnostics}
{synopt:{opt held:out(#)}}also report held-out log-likelihood (document
completion), holding out #% of each document's tokens; must be in [0,100){p_end}
{synopt:{opt nstart(#)}}random restarts; keep the best bound (default 1 =
deterministic spectral init){p_end}

{syntab:Output}
{synopt:{opt gen:erate(name)}}stub for the topic-proportion variables; default
{cmd:generate(theta)}{p_end}
{synopt:{opt sav:ing(file[, replace])}}save topic-word probabilities + vocabulary
to a dataset (one row per term: {cmd:word topic1 ... topicK}){p_end}
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

{phang}{opt spline(varlist[, df(#) degree(#)])} adds a B-spline basis of each
continuous covariate to the prevalence design, the way R {cmd:stm}'s {cmd:s()}
does. Defaults match {cmd:stm}: {cmd:df(10)}, {cmd:degree(3)}, with interior knots
at sample quantiles. The basis columns ({it:var}{cmd:_s1}, {it:var}{cmd:_s2}, ...)
enter {cmd:e(b)} like any other prevalence term, so {cmd:test} and {cmd:lincom}
work on them. Combine with {opt prevalence()} for mixed designs.

{phang}{opt content(varname)} adds a content covariate: a single categorical
variable whose levels shift the topic-word distributions, via the SAGE content
model inside STM (stm's {cmd:content =}). Prevalence covariates explain which
topics a document is about; a content covariate explains how the words of a topic
differ across groups. Combine with {opt prevalence()} and {opt spline()}.

{phang}{opt iters(#)} caps the EM iterations (default 200); the fit stops earlier
on convergence. The value must be positive.

{phang}{opt seed(#)} sets the random seed (default 42).

{phang}{opt stopwords(spec)} controls stopword removal: {cmd:none} (default),
{cmd:english} (a bundled Snowball English list), or a filename with one stopword
per line.

{phang}{opt mindocfreq(#)} drops terms appearing in fewer than # documents
(default 1, i.e. keep all). {opt maxdocpct(#)} drops terms appearing in more than
#% of documents (default 100). {opt mindocfreq()} must be at least 1, and
{opt maxdocpct()} must be in (0,100]. Together these are the vocabulary trimming that R
{cmd:stm}'s {cmd:prepDocuments} performs.

{phang}{opt nolowercase} keeps tokens in their original case; by default tokens
are lowercased before counting.

{pstd}
{cmd:fastm} does not stem. Neither does R {cmd:stm} by default, so the vocabularies
are comparable out of the box; stem upstream if your application calls for it.

{phang}{opt heldout(#)} also reports a held-out log-likelihood by document
completion, holding out #% of each document's tokens and scoring the model on
them. The value must be in [0,100); the result is returned in
{cmd:e(heldout_ll)} per token. See {help searchk} to compare this across a range
of {opt k()}.

{phang}{opt nstart(#)} runs # random restarts and keeps the fit with the best
evidence bound. The default, {cmd:nstart(1)}, uses the deterministic spectral
initialization and so is reproducible without a seed sweep. Variational EM is
nonconvex, so restarts guard against a poor local optimum.

{phang}{opt generate(name)} sets the stub for the created topic-proportion
variables (default {cmd:theta}).

{phang}{opt saving(file[, replace])} writes the fitted topic-word probabilities
and the vocabulary to a dataset, one row per term
({cmd:word topic1} ... {cmd:topic}{it:K}). This is how the full beta matrix is
recovered for custom labeling or for rankings deeper than {cmd:estat labels}
reports.

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
{synopt:{cmd:e(n_content)}}number of content-covariate groups (0 if none){p_end}
{synopt:{cmd:e(nstart)}}number of random restarts{p_end}
{synopt:{cmd:e(heldout_ll)}}held-out log-likelihood per token (if {opt heldout()}){p_end}

{p2col 5 22 26 2: Macros}{p_end}
{synopt:{cmd:e(cmd)}}{cmd:fastm}{p_end}
{synopt:{cmd:e(textvar)}}name of the text variable{p_end}
{synopt:{cmd:e(prevalence)}}prevalence specification{p_end}
{synopt:{cmd:e(content)}}content variable (if any){p_end}
{synopt:{cmd:e(prev_terms)}}expanded prevalence term names{p_end}
{synopt:{cmd:e(generate)}}topic-proportion variable stub{p_end}
{synopt:{cmd:e(properties)}}{cmd:b V}, or {cmd:nob noV} with no prevalence terms{p_end}
{synopt:{cmd:e(predict)}}{cmd:fastm_predict}{p_end}
{synopt:{cmd:e(estat_cmd)}}{cmd:fastm_estat}{p_end}
{synopt:{cmd:e(marginsok)}}predictions allowed by {cmd:margins}{p_end}
{synopt:{cmd:e(marginsnotok)}}predictions disallowed by {cmd:margins}{p_end}
{synopt:{cmd:e(lbl_}{it:type}{cmd:_}{it:t}{cmd:)}}top 10 words of topic {it:t} for
{it:type} = {cmd:prob}, {cmd:frex}, {cmd:lift}, {cmd:score}; replayed by
{cmd:estat labels}{p_end}
{synopt:{cmd:e(clev_}{it:g}{cmd:)}}label of content level {it:g} (content models){p_end}
{synopt:{cmd:e(persp_}{it:g}{cmd:_}{it:t}{cmd:)}}top 10 words level {it:g} emphasizes
in topic {it:t}; replayed by {cmd:estat perspectives}{p_end}

{p2col 5 22 26 2: Matrices}{p_end}
{synopt:{cmd:e(topiccorr)}}topic correlation matrix (K x K){p_end}
{synopt:{cmd:e(b)}}covariate-effect coefficients (one equation per topic);
{opt prevalence()} or {opt spline()} models only{p_end}
{synopt:{cmd:e(V)}}their covariance (block-diagonal by topic); same models{p_end}
{synopt:{cmd:e(gamma)}}prevalence coefficients (design x K-1); same models{p_end}

{pstd}
The label and perspective macros are stored with the estimates rather than in
global macros, so {cmd:estat labels} and {cmd:estat perspectives} keep working
after {cmd:estimates store} and {cmd:estimates restore}, and after another
{cmd:fastm} fit.


{marker postestimation}{...}
{title:Postestimation}

{pstd}{cmd:fastm} posts {cmd:e(b)}/{cmd:e(V)} (the method-of-composition effects,
one equation per topic), so the usual tools apply:{p_end}
{phang2}{cmd:. test [topic1]1.party}{p_end}
{phang2}{cmd:. lincom [topic1]year - [topic2]year}{p_end}
{phang2}{cmd:. margins party, predict(equation(topic1))}{p_end}
{phang2}{cmd:. marginsplot}{p_end}

{pstd}Representative documents for a topic (highest topic proportion):{p_end}
{phang2}{cmd:. estat thoughts, topic(}{it:#}{cmd:)} [{cmd:n(}{it:#}{cmd:) chars(}{it:#}{cmd:) detail}]{p_end}

{pstd}
{opt n(#)} sets how many documents to show (default 5). Each is printed as a
wrapped excerpt of its first {opt chars(#)} characters (default 240); {opt detail}
prints each document in full.{p_end}

{pstd}Redisplay topic labels by score type ({cmd:prob}, {cmd:frex}, {cmd:lift},
{cmd:score}):{p_end}
{phang2}{cmd:. estat labels} [{cmd:, type(}{it:t}{cmd:) n(}{it:#}{cmd:) topic(}{it:#}{cmd:)}]{p_end}

{pstd}After a {opt content()} model, the words each content level emphasizes in a
topic (the per-group contrast):{p_end}
{phang2}{cmd:. estat perspectives, topic(}{it:#}{cmd:)} [{cmd:n(}{it:#}{cmd:)}]{p_end}

{pstd}
{cmd:estat labels} and {cmd:estat perspectives} replay word lists that the fit
stored, and the engine stores the top 10 words per topic per ranking. {cmd:n()}
larger than 10 therefore shows 10 and says so. For a deeper ranking, export the
full topic-word matrix with {opt saving()}.

{pstd}{cmd:predict} after {cmd:fastm} (one topic per call):{p_end}
{synoptset 34 tabbed}{...}
{synopt:{cmd:predict} {it:nv}{cmd:, pr topic(}{it:#}{cmd:)}}posterior document-topic proportion for the fitted document{p_end}
{synopt:{cmd:predict} {it:nv}{cmd:, xb} [{cmd:topic(}{it:#}{cmd:)}]}linear prediction from the posted topic-effect equation; requires {opt prevalence()} or {opt spline()}{p_end}
{synopt:{cmd:predict} {it:nv}{cmd:, stdp} [{cmd:topic(}{it:#}{cmd:)}]}standard error of the linear prediction; requires {opt prevalence()} or {opt spline()}{p_end}
{synopt:{cmd:predict} {it:nv}}{cmd:xb} after {opt prevalence()} or {opt spline()}; {cmd:pr} otherwise{p_end}

{pstd}
{opt topic(#)} names the topic. It is required with {cmd:pr}, which has no
default topic. With {cmd:xb} and {cmd:stdp} it follows Stata's rule for
multiequation models: an unspecified topic means the first one. The equivalent
{opt equation(topic#)} may be given instead, and is what {cmd:margins} uses.

{pstd}
With {opt prevalence()} or {opt spline()}, {cmd:fastm} posts {cmd:e(b)} and
{cmd:e(V)}. Without prevalence terms, {cmd:fastm} still stores {cmd:e(sample)}
but posts no coefficient vector or covariance matrix.

{pstd}
For margins based on posted topic-effect coefficients, use the topic equation:
{cmd:margins} {it:varlist}{cmd:, predict(equation(topic}{it:#}{cmd:))}. If
Stata reports an estimability warning for a particular factor-variable design,
add {cmd:noestimcheck}; the posted effects are method-of-composition summaries
rather than parameters from a conventional likelihood.

{pstd}
For models with posted prevalence or spline effects, {cmd:e(marginsok)} allows
{cmd:margins} for the default linear prediction and {cmd:xb}; {cmd:pr} and
{cmd:stdp} are not allowed by {cmd:margins}. For models without posted effects,
{cmd:e(marginsnotok)} is {cmd:_ALL}.


{title:Author}

{pstd}Neal Caren. Engine: {cmd:topica-core}. Cite the Structural Topic Model
(Roberts, Stewart, and Tingley).
