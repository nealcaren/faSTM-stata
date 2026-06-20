# Appendix A reproduction: compare fastm with the original R package stm on
# poliblog. fastm and stm are independent implementations of the same model, so we
# do not expect identical optima; we check that they recover the same topics.
#
# Prereq: run the fastm side first to export its topic-word matrix, e.g.
#   . use tests/parity/poliblog.dta, clear
#   . fastm text, k(20) prevalence(i.liberal) seed(2138) saving("fastm_beta.dta", replace)
# then point FASTM_BETA below at that file.
suppressMessages({library(stm); library(haven)})
FASTM_BETA <- Sys.getenv("FASTM_BETA", "/tmp/fastm_beta.dta")

# poliblog ships with stm; faSTM re-exports the same object. Use whichever is present.
if (requireNamespace("faSTM", quietly = TRUE)) { library(faSTM); data(poliblog) } else { data(poliblog) }
docs <- poliblog$documents; vocab <- poliblog$vocab; meta <- poliblog$meta

fit <- stm::stm(docs, vocab, K = 20, prevalence = ~ rating, data = meta,
                init.type = "Spectral", seed = 2138, max.em.its = 200, verbose = FALSE)
cat("stm prevalence bound =", round(tail(fit$convergence$bound, 1), 2),
    " iters =", fit$convergence$its, "\n")

stmbeta <- exp(fit$beta$logbeta[[1]]); stmvocab <- fit$vocab
fb   <- haven::read_dta(FASTM_BETA)
fmat <- as.matrix(fb[, grep("^topic", names(fb))])
fmat <- fmat[match(stmvocab, fb$word), ]          # align vocab by word

cors <- cor(t(stmbeta), fmat)                      # 20 (stm) x 20 (fastm)
mf <- integer(20); mc <- numeric(20); avail <- 1:20
for (i in order(-apply(cors, 1, max))) {           # greedy 1:1 topic matching
  j <- avail[which.max(cors[i, avail])]; mf[i] <- j; mc[i] <- cors[i, j]
  avail <- setdiff(avail, j)
}
t10 <- function(p, v, n = 10) v[order(-p)[1:n]]
jac <- sapply(1:20, function(i)
  length(intersect(t10(stmbeta[i, ], stmvocab), t10(fmat[, mf[i]], stmvocab))) /
  length(union(t10(stmbeta[i, ], stmvocab), t10(fmat[, mf[i]], stmvocab))))

cat(sprintf("topic-word correlation: mean %.3f  median %.3f  min %.3f\n",
            mean(mc), median(mc), min(mc)))
cat(sprintf("top-10 Jaccard:         mean %.3f  median %.3f\n", mean(jac), median(jac)))
