# stmata

Structural Topic Models in **Stata**, backed by the same Rust engine
(`topica-core`) as [faSTM](https://github.com/nealcaren/faSTM) (R). No Python and
no Rust toolchain required to *use* it: you install an ado/Mata package plus a
precompiled `stmata.plugin`.

> Status: **M1 done** — fits an STM end to end in Stata 15.1: reads a text
> variable, fits via `topica-core`, writes topic proportions (θ) back, prints top
> words per topic. No covariates yet. See [DESIGN.md](DESIGN.md).

## Layout

```
crate/        Rust plugin (lib.rs) + the C shim (shim.c) over StataCorp's interface
vendor/       StataCorp's stplugin.c / stplugin.h, unmodified (see vendor/NOTICE.md)
build/        build.sh — compiles + links stmata.plugin for x86_64 (macOS / Linux)
ado/  mata/   Stata side (added from M2)
examples/     hello.do — the M0 smoke test
tests/parity/ parity checks vs R stm / faSTM (added from M1)
docs/         design + notes
```

## Build + smoke test

```sh
bash build/build.sh          # -> ./stmata.plugin  (x86_64)
# then, in Stata 15, from the repo root:
#   do examples/hello.do
```

`hello.do` loads the plugin, reads `mpg`, writes `2*mpg` into a new variable, and
saves a Stata scalar — proving the Stata<->Rust round-trip before any modeling.

## Why a plugin (not Python, not pure Mata)

The constraint is no end-user Python or Rust. A pure-Mata reimplementation would
be far slower than R `stm` (its hot loop is compiled C++; Mata is interpreted and
single-threaded). Shipping the validated Rust engine as a precompiled plugin keeps
the speed and reuses one cross-validated codebase. See [DESIGN.md](DESIGN.md) for
the full rationale and the FFI decision.
