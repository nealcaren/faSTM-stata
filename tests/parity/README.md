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

### Content (`content = ~rating`) case

`export_content_gold.R` fits the reference SAGE content model
(`content = ~rating`, writing `gold_content_bound.txt`); `parity_check_content.do`
runs `fastm text, k(20) content(liberal)` on the same `.dta`.

## Result (2026-06)

| quantity | fastm | faSTM gold |
|---|---|---|
| vocabulary V | 2632 | 2632 |
| documents D | 5000 | 5000 |
| final bound, `~rating` | -6,943,448 | -6,943,536 (Δ 0.001%) |
| final bound, `s(day)` | -6,943,287 | -6,943,310 (Δ 0.0003%) |
| final bound, `content=~rating` | -6,969,239.0 | -6,969,239.5 (Δ 7e-6%) |

Topics align by position; FREX labels match (minor FREX rank ties on near-equal
words); per-topic coherence matches for most topics, the rest within the
non-convex-optimum tolerance. `fastm` uses faSTM's engine (`topica-core`), so the
residual bound differences come from internal vocabulary ordering in the spectral
initialization, not the math.

## Versus the original stm package (`compare_stm.R`)

The table above is against **faSTM**, which shares fastm's engine, so the match is
numerical (bounds agree to <0.001%). The **original stm** package is an independent
implementation: it optimizes the same model differently and reaches a different
local optimum, so its bound differs by about 0.08% (it actually lands a bit higher,
e.g. -6,937,826 vs -6,943,448 for the prevalence model). The right check there is
topic recovery, not the bound. `compare_stm.R` fits stm, matches its 20 topics to
fastm's one-to-one, and reports:

| stm vs fastm, 20 matched topics | mean | median | min |
|---|---|---|---|
| topic-word correlation | 0.95 | 0.996 | 0.35 |
| top-10 word overlap (Jaccard) | 0.79 | 0.82 | |

Most topics are near-identical (median r 0.996); one of 20 diverges, the expected
behavior of two optimizers on a non-convex objective. Run: export fastm's beta with
`fastm ..., saving("fastm_beta.dta")`, then `Rscript tests/parity/compare_stm.R`.
This comparison is Appendix A of the article.
