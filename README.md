# fastm

Structural Topic Models in **Stata**, backed by the same Rust engine
(`topica-core`) as [faSTM](https://github.com/nealcaren/faSTM) (R) and
[topica](https://github.com/nealcaren/topica) (Python). Fitting, tokenization,
labels, diagnostics, and covariate-effect estimation all run in a compiled
plugin, so **no Python and no Rust toolchain are needed to use it**: you install
an ado/Mata package plus a precompiled `fastm.plugin`.

> Status: **working, pre-1.0.** A full estimation command, validated in Stata
> 15.1 and parity-checked against R `stm` on poliblog. Not yet packaged for
> `net install` / SSC (see the roadmap below).

## What it does

```stata
. fastm abstract, k(20) prevalence(i.party c.year i.party##c.year)

Structural Topic Model                  Documents      =     1,247
Engine: topica-core (Rust)              Vocabulary     =     3,201
                                        Topics (K)     =        20
                                        Prevalence     =         5 term(s)
                                        Final bound    = -1234567.8
Mean semantic coherence  =    -71.40    Mean exclusivity =      9.12
Topic proportions in theta1-theta20 (EM iters 38)

Covariate effects on topic proportions (method of composition)
[ multi-equation coefficient table, one equation per topic ]
```

`fastm` fits the model, writes each document's topic proportions to
`theta1 .. thetaK`, prints FREX labels and coherence/exclusivity per topic, and
(with `prevalence()`) estimates covariate effects on topic prevalence by the
method of composition, with standard errors that propagate the per-document
topic-estimation uncertainty.

Because it posts `e(b)` / `e(V)` (one equation per topic), the usual Stata
machinery works:

```stata
. test [topic5]1.party
. lincom [topic5]year - [topic8]year
. margins party, predict(equation(topic5))
. marginsplot
. predict tp5, pr topic(5)        // prevalence-fitted proportion
. fastm                            // redisplay the last fit
. help fastm
```

## Features

- **Fit** an STM from a Stata string variable (one document per observation);
  honors `if`/`in`.
- **Preprocessing controls**: `stopwords(none|english|"file")`, `mindocfreq()`,
  `maxdocpct()`, `nolowercase`: transparent vocabulary formation (stm's
  `prepDocuments`).
- **Prevalence covariates** with full factor-variable syntax: `i.party`,
  `c.year`, interactions `i.party##c.year`.
- **Labels and diagnostics**: FREX / probability / lift / score, semantic
  coherence, exclusivity (stm-faithful, computed in the engine).
- **estimateEffect**: covariate effects on topic proportions, posted as
  `e(b)` / `e(V)`, so `test`, `lincom`, `margins`, and `marginsplot` all work.
- **predict** (xtreg-style): `pr` (model prevalence-fitted proportion), `xb`,
  `stdp`, with `topic(#)`.
- **`searchk`**: choose K by held-out document completion (held-out
  log-likelihood + coherence + exclusivity + bound) in `r(table)`.
- **Save the model**: `saving()` writes topic-word probabilities + vocabulary to
  a dataset.
- **Replay** (bare `fastm`) and full **help files** (`help fastm`, `help searchk`).

## Build

The Rust core compiles into a Stata plugin. To build it yourself you need a Rust
toolchain (end users will not, once binaries are shipped):

```sh
bash build/build.sh          # -> ./fastm.plugin  (x86_64: Stata 15 is x86_64)
```

Then, from the repo root in Stata:

```stata
. run "ado/fastm.ado"
. do examples/margins_demo.do
```

`build.sh` targets `x86_64` on both macOS (a `-bundle`) and Linux
(`-shared`), since Stata 15 is an x86_64 binary even on Apple Silicon.

## How it fits together

```
  Stata (ado + Mata)                 <- syntax, factor vars, margins, output
        |  plugin call  (the only C/FFI boundary)
  fastm.plugin   = shim.c + vendor/stplugin.c + Rust   <- marshals Stata <-> Rust
        |  plain Rust calls (no FFI)
  topica-core (Rust)                 <- fit + labels + coherence + estimateEffect
```

The plugin is itself Rust and depends on `topica-core` as an ordinary crate, so
the only C boundary is Stata ↔ plugin. The engine pieces (`from_texts`,
`inspect`, `effects`) live in `topica-core` and are shared with faSTM and topica.
See [DESIGN.md](DESIGN.md) for the FFI decision and build details.

## Why a plugin (not Python, not pure Mata)

The constraint is no end-user Python or Rust. A pure-Mata reimplementation would
be far slower than R `stm` (whose hot loop is compiled C++; Mata is interpreted
and single-threaded). Shipping the validated Rust engine as a precompiled plugin
keeps the speed and reuses one cross-validated codebase.

## Layout

```
crate/        Rust plugin (lib.rs) + the C shim (shim.c) over StataCorp's interface
vendor/       StataCorp's stplugin.c / stplugin.h, unmodified (see vendor/NOTICE.md)
build/        build.sh: compiles + links fastm.plugin for x86_64 (macOS / Linux)
ado/          fastm.ado/.sthlp, searchk.ado/.sthlp, fastm_english.stops
examples/     *.do demos (fit, covariates, factor vars, margins)
tests/parity/ real-corpus parity vs R stm/faSTM on poliblog
docs/         design notes + the Stata Journal readiness plan
```

## Status and roadmap

Done: fitting, preprocessing controls, prevalence with factor variables,
labels/diagnostics, estimateEffect with `e(b)`/`e(V)` (test/lincom/margins),
`predict`, `searchk`, `saving()`, replay, help files, and real-corpus parity vs
R `stm` on poliblog.

Next (see [docs/STATA_JOURNAL_READINESS.md](docs/STATA_JOURNAL_READINESS.md)):

- `estat thoughts` (representative documents), `e(sigma)` topic correlations,
  standalone held-out likelihood, `nstart()` multi-start.
- **Content / SAGE covariates** (`content()`): the other half of STM.
- **Packaging**: ship prebuilt macOS + Linux (and Windows) plugins, `net install`
  / SSC.
- A Stata Journal article introducing the command.

## Relation to faSTM and topica

The model and its post-fit math live once, in `topica-core` (Rust), and are
consumed by faSTM (R), topica (Python), and `fastm` (Stata). The estimator is
cross-validated against R `stm` through faSTM.
