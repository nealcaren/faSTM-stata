# fastm

`fastm` brings **structural topic models** (STM) to **Stata**. It is essentially a
Stata port of the R package [**stm**](https://www.structuraltopicmodel.com/)
(Roberts, Stewart, and Tingley 2019): it fits the same model — where document-level
covariates shape both how prevalent a topic is and how its words are chosen — and
reproduces stm's results to within 0.001% on the poliblog corpus. Fitting,
tokenization, labels, diagnostics, and covariate-effect estimation all run in a
compiled Rust plugin, so **no Python and no Rust toolchain are needed to use it**:
you install an ado/Mata package plus a precompiled `fastm.plugin`.

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
  `c.year`, interactions `i.party##c.year`, and smooth `spline()` terms (stm's
  `s()`).
- **Content covariates** (`content()`): the SAGE content model, shifting
  topic-word distributions across groups.
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

## Install

No Python or Rust toolchain needed. From Stata:

```stata
net install fastm, from("https://raw.githubusercontent.com/nealcaren/faSTM-stata/main/ado/") replace
help fastm
```

This installs the ado files and the plugins for all three operating systems;
`fastm.ado` loads the one matching yours. The macOS plugin is a universal binary
(Intel and Apple Silicon), so it works on native Apple Silicon Stata as well as
under Rosetta; the Linux and Windows plugins are x86_64. Requires Stata 15+.

Prebuilt binaries are also attached to each
[release](https://github.com/nealcaren/faSTM-stata/releases) if you prefer to
place them on the adopath by hand.

**From source.** Clone the repo and run the build (needs a Rust toolchain); see
[Build](#build) below.

## Build

**Most users never need this.** `net install` ships precompiled plugins for macOS,
Linux, and Windows, and `fastm.ado` loads the right one. Building from source is
only for developers changing the Rust engine or shim, or anyone targeting a
platform without a prebuilt binary. It needs a Rust toolchain:

```sh
bash build/build.sh          # -> ./fastm.plugin  (universal on macOS, x86_64 on Linux)
```

Then, from the repo root in Stata:

```stata
. run "ado/fastm.ado"
. do examples/margins_demo.do
```

On macOS `build.sh` builds a universal `-bundle` (x86_64 + arm64, combined with
`lipo`), so the plugin loads in both Intel/Rosetta Stata and native Apple Silicon
Stata; set `MACOS_ARCHS=arm64` for a faster single-arch dev build. On Linux it
builds an x86_64 `-shared` object. On Windows, `build/build.ps1` does the same with
MSVC (run it from a Developer PowerShell for VS). The `build` GitHub Actions
workflow compiles the plugin on Linux, macOS, and Windows on every push and uploads
each as an artifact, so a Windows binary is produced without a Windows machine. It
still needs a smoke test on a Windows copy of Stata before release.

## Why a plugin (not Python, not pure Mata)

The constraint is no end-user Python or Rust. A pure-Mata reimplementation would
be far slower than R `stm` (whose hot loop is compiled C++; Mata is interpreted
and single-threaded). Shipping the validated Rust engine as a precompiled plugin
keeps the speed and reuses one cross-validated codebase.

## Layout

```
ado/          fastm.ado/.sthlp, searchk.ado/.sthlp, fastm_english.stops, plugins
crate/        Rust plugin (lib.rs) + the C shim (shim.c) over StataCorp's interface
vendor/       StataCorp's stplugin.c / stplugin.h, unmodified (see vendor/NOTICE.md)
build/        build.sh / build.ps1: compile + link fastm.plugin per OS
examples/     *.do demos (fit, covariates, factor vars, margins)
tests/        win_smoke/: load the plugin and run a fit, no Stata (CI smoke test)
```

## Status and roadmap

Done: fitting, preprocessing controls, prevalence with factor variables and
smooth `spline()` terms, content (SAGE) covariates, labels/diagnostics,
estimateEffect with `e(b)`/`e(V)` (test/lincom/margins), `predict`, `searchk`,
`estat thoughts`/`estat labels`, `e(topiccorr)`, `heldout()`, `nstart()`,
`saving()`, replay, help files, and real-corpus parity vs R `stm` on poliblog
(prevalence, `s(day)`, and content models all match to <0.001%).

Next:

- **Packaging**: ship prebuilt macOS + Linux (and Windows) plugins, `net install`
  / SSC.
- A Stata Journal article introducing the command.

## Relation to stm, faSTM, and topica

`fastm` implements the structural topic model introduced in R's `stm`. The engine
and its post-fit math live once, in `topica-core` (Rust), shared with faSTM (R) and
topica (Python); the estimator is parity-checked against R `stm` on poliblog.

If you use `fastm`, please cite the structural topic model:

> Roberts, M. E., B. M. Stewart, and D. Tingley. 2019. stm: An R Package for
> Structural Topic Models. *Journal of Statistical Software* 91(2): 1–40.
