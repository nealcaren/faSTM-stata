# Plugin load smoke test (no Stata required)

`host.c` is a minimal "fake Stata": it implements the Stata plugin ABI (the
`SF_*` callback table in `vendor/stplugin.h`) backed by in-memory arrays, loads
a shipped `fastm` plugin with the OS loader, hands over the table via `pginit`,
and calls `stata_call("fit", ...)` on a small synthetic 3-topic corpus. It
passes if the plugin loads, its exports resolve, the fit returns `0`, and every
document's topic proportions are written back and sum to 1.

This is the strongest Windows check available **without a Stata license**: on the
`windows-latest` CI runner it exercises the real shipped Windows binary on a real
Windows loader. It does *not* test Stata's own `SF_*` implementations (those are
mocked here) — that residual is what the Stata Journal reviewers' Windows run
covers.

## Run it

Native (current OS), against the bundled plugin in `ado/`:

```sh
./run.sh
```

Against a specific plugin (e.g. a freshly built one at the repo root):

```sh
./run.sh ../../fastm.plugin
```

Windows binary under Wine, from macOS/Linux (needs `wine` + a mingw
cross-compiler, e.g. `x86_64-w64-mingw32-gcc`):

```sh
WINE=1 ./run.sh
```

## In CI

The `build` workflow runs this on all three runners after building the plugin,
and additionally enforces on Windows that the binary imports no Visual C++
runtime DLL (`vcruntime140`/`msvcp140`/`msvcr*`) — the dependency that breaks a
clean Stata-for-Windows install if the static-CRT link ever regresses.
