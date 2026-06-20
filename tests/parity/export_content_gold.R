# Content (SAGE) parity gold: fit the reference engine with a content covariate
# (content = ~rating, the stm vignette's content example) and record the bound.
# fastm content(liberal) should match it (same SAGE content model in topica-core).
suppressMessages({library(faSTM)})
data(poliblog)
docs <- poliblog$documents; vocab <- poliblog$vocab; meta <- poliblog$meta

fit <- faSTM::stm(docs, vocab, K = 20, content = ~ rating, data = meta,
                  init.type = "Spectral", seed = 2138, max.em.its = 200, verbose = FALSE)
b <- round(tail(fit$convergence$bound, 1), 2)
cat("faSTM content=~rating: iters=", fit$convergence$its, " bound=", b, "\n", sep = "")
writeLines(as.character(b), "tests/parity/gold_content_bound.txt")
