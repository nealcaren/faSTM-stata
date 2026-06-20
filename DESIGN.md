# stmata — design

Structural Topic Models in Stata, with **no end-user Python and no end-user Rust
toolchain**. The user installs a Stata package (ado/Mata + a precompiled
`stmata.plugin` binary) and nothing else.

This is the Stata sibling of [faSTM](https://github.com/nealcaren/faSTM) (R) and
shares the same engine, `topica-core`.

## Constraints (set by the user)

- **No Python**, ever. (Also forced by Stata 15, which has no native Python.)
- **No Rust on the end-user's machine.** We compile; they install binaries.
- **Target Stata 15+.** Dev machines: macOS Stata 15 (local, x86_64 under
  Rosetta) and Linux Stata on Longleaf (x86_64, via ssh).
- **Graphics are out of scope for now** (entirely separate work).

## Three layers

```
  Stata (ado + Mata)                 <- syntax, options, orchestration, output
        |  plugin call  (the ONLY C/FFI boundary)
  stmata.plugin   = shim.c + vendor/stplugin.c + Rust   <- marshals Stata <-> Rust
        |  plain Rust calls (no FFI)
  topica-core (Rust)                 <- the fit + (eventually) the post-fit layer
```

The plugin is itself Rust, so it depends on `topica-core` as an ordinary crate.
**FFI exists only between Stata and the plugin**, not between the plugin and the
engine.

## Strategy: push everything we can into topica-core

Per the user's plan: **(a)** do as much as possible in Rust inside `topica-core`,
so faSTM (R), topica (Python), and stmata (Stata) all benefit; **(b)** write the
rest in Mata/ado, keeping speed-sensitive inner loops on the Rust side.

What lives where today (from a scan of the repos):

| Capability | topica-core (Rust) | Action |
|---|---|---|
| Estimator: CTM/variational EM, Laplace E-step, spectral init, Σ/Γ | present | reuse as-is |
| In-memory text -> Corpus (tokenize, stopwords, doc-freq trim) | only `load_text_file(path)` | **add `from_texts(Vec<String>, opts)`** |
| FREX / lift / score labels | absent (Python/R only) | **port down into core** |
| semantic coherence / exclusivity | partial | **finish in core** |
| estimate_effect (method of composition) | absent (Python/R only) | **port down into core** |

Porting the post-fit layer *down* into `topica-core` turns "write it a third time
in Mata" into "write it once in Rust, three consumers." That is the main leverage
of this project and the reason (a) comes before (b).

Mata/ado then owns: command syntax, pulling a text variable + covariates out of
Stata, handing them to the plugin, writing θ back as variables, storing β/labels
in matrices, formatting tables, and any glue not worth a Rust round-trip.

## FFI decision: a tiny C shim, not direct Rust FFI

StataCorp's `SF_*` (e.g. `SF_vdata`, `SF_nobs`) are **preprocessor macros** that
expand to `(_stata_)->fnptr(...)` calls through the `ST_plugin` struct of
function pointers (see `vendor/stplugin.h`). They are not linkable symbols.

- **Direct Rust FFI** would require hand-mirroring the entire `ST_plugin` struct
  ABI in Rust and tracking it across Stata versions. Fragile.
- **C shim (chosen):** `crate/src/shim.c` (~15 lines) `#include`s the StataCorp
  header and re-exposes each macro as a real `extern "C"` function. The compiler
  expands the macros correctly; Rust links against stable symbols.

`vendor/stplugin.c` and `vendor/stplugin.h` are StataCorp's, unmodified.

### Build notes (bite us if forgotten)

- **x86_64 always.** Stata 15 is x86_64; the plugin must match even on Apple
  Silicon. `build/build.sh` targets `x86_64-apple-darwin` / `x86_64-unknown-linux-gnu`.
- **Define `SYSTEM`.** Compile the C with `-DSYSTEM=3` (APPLEMAC) or `-DSYSTEM=2`
  (OPUNIX/Linux); otherwise `stplugin.h` defaults to Windows and `STDLL` uses
  `__declspec`.
- **Panics.** `stmata_entry` wraps its body in `catch_unwind` and returns a Stata
  return code; panics never cross into Stata. (So keep `panic = "unwind"`.)
- **macOS:** plugin is a `-bundle`; **Linux:** `-shared -fPIC`.

## opendo

opendo (the user's open-source Stata in Rust) is a resource, not a dependency.
Two future payoffs, neither blocking:
1. If opendo implements the host side of the stplugin ABI (provide the `SF_*`
   callbacks, load `.plugin`, call `stata_call`), the *same* binary runs there.
2. Because both opendo and the engine are Rust, opendo could call `topica-core`
   in-process and skip the FFI entirely.

## Validation

Mirror faSTM's approach: fit the same corpus (poliblog) through stmata and through
R `stm`/faSTM and assert the numbers match (labels identical, coherence/
exclusivity to floating point). The engine is already cross-validated against R
`stm`, so stmata inherits correctness and we just check the marshaling.

## Milestones

- **M0 — toolchain/FFI smoke test. DONE, validated in Stata 15.1.** `stmata.plugin`
  loads; reads a variable, writes `2*x` into a second, saves a scalar that matches
  `summarize` to the digit. Proves the build + shim + arch end to end. (Gotcha
  banked: `SF_vdata`/`SF_vstore` are `(variable, observation)`, both 1-based.)
- **M1 — fit round-trip. DONE, validated in Stata 15.1.** `plugin call stmata
  <text> <theta1..thetaK>, fit <K> <seed> <iters>` reads the text variable, builds
  a corpus via `topica_core::from_texts`, fits with `fit_ctm` (spectral init, no
  covariates yet), writes θ back per observation, prints top words per topic, and
  saves `stmata_K/V/D/bound/iters`. Two-theme demo (`examples/fit_demo.do`) splits
  sports vs cooking cleanly (θ₁≈0.98 on sports docs).
- **M2 — post-fit in core + Mata wrappers.** FREX/lift/score, coherence,
  exclusivity ported into `topica-core`; `stm`/`labeltopics`-style ado output.
- **M3 — estimateEffect.** Port method-of-composition into core; native-feeling
  coefficient table in Stata.
- **M4 — packaging.** Prebuilt plugins (Linux + macOS, later Windows), `net
  install`, help files, parity tests in CI.

Graphics: deferred.
