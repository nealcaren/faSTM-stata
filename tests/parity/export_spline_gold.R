# Spline parity gold: fit the reference engine with a smooth s(day) prevalence
# term and record the converged bound. fastm's spline(day, df(10)) should match it
# (same B-spline design span), the same way the base case matches ~rating.
suppressMessages({library(faSTM)})
data(poliblog)
docs <- poliblog$documents; vocab <- poliblog$vocab; meta <- poliblog$meta

fit <- faSTM::stm(docs, vocab, K = 20, prevalence = ~ s(day), data = meta,
                  init.type = "Spectral", seed = 2138, max.em.its = 200, verbose = FALSE)
b <- round(tail(fit$convergence$bound, 1), 2)
cat("faSTM s(day): iters=", fit$convergence$its, " bound=", b, "\n", sep = "")
writeLines(as.character(b), "tests/parity/gold_spline_bound.txt")
