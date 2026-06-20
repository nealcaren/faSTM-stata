# Real-corpus parity vs R stm / faSTM

Confirms `fastm` (Stata) reproduces the reference engine on the **poliblog** corpus
from the stm/faSTM vignette.

## How

1. `export_poliblog.R` writes `poliblog.dta` and the gold reference:
   - Each document is reconstructed as a **bag-of-words string** (each vocab word
     repeated by its count). fastm's tokenizer then rebuilds the *exact same*
     document-term matrix stm used, sidestepping any stemming/stopword mismatch.
   - It fits faSTM (`prevalence = ~ rating`, K=20, spectral init) and saves
     `gold_frex.txt` (top-7 FREX per topic) and `gold_coherence.csv`.
2. `parity_check.do` runs `fastm text, k(20) prevalence(i.liberal)` on `poliblog.dta`.

Run: `Rscript tests/parity/export_poliblog.R` then `do tests/parity/parity_check.do`.

### Spline (`s(day)`) case

`export_spline_gold.R` fits the reference with a smooth `prevalence = ~ s(day)`
term (writing `gold_spline_bound.txt`); `parity_check_spline.do` runs
`fastm text, k(20) spline(day, df(10))` on the same `.dta`. This checks that
fastm's B-spline basis spans stm's `s()` design space (same quantile knots), so the
fit matches even though the basis parameterization (the gammas) differs.

## Result (2026-06)

| quantity | fastm | faSTM gold |
|---|---|---|
| vocabulary V | 2632 | 2632 |
| documents D | 5000 | 5000 |
| final bound, `~rating` | -6,943,448 | -6,943,536 (Δ 0.001%) |
| final bound, `s(day)` | -6,943,287 | -6,943,310 (Δ 0.0003%) |

Topics align by position; FREX labels match (minor FREX rank ties on near-equal
words); per-topic coherence matches for most topics, the rest within the
non-convex-optimum tolerance (same pattern faSTM shows vs stm). `fastm` uses
faSTM's engine (`topica-core`), so the residual differences come from internal
vocabulary ordering in the spectral initialization, not the math.
