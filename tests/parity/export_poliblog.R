suppressMessages({library(faSTM); library(haven)})
data(poliblog)
docs  <- poliblog$documents; vocab <- poliblog$vocab; meta <- poliblog$meta
cat("poliblog: ", length(docs), "docs,", length(vocab), "vocab; rating levels:",
    paste(levels(factor(meta$rating)), collapse="/"), "\n")

# Reconstruct each document as a bag-of-words string (word repeated by its count),
# so fastm's tokenizer rebuilds the SAME document-term matrix stm used.
bow <- vapply(docs, function(m) paste(rep(vocab[m[1,]], m[2,]), collapse=" "), character(1))
df <- data.frame(text = bow,
                 liberal = as.integer(meta$rating == "Liberal"),
                 day = as.integer(meta$day),
                 stringsAsFactors = FALSE)
haven::write_dta(df, "tests/parity/poliblog.dta")
cat("wrote tests/parity/poliblog.dta:", nrow(df), "docs\n")

# Reference fit: same engine fastm uses, prevalence = ~rating, K=20, spectral init.
fit <- faSTM::stm(docs, vocab, K=20, prevalence=~rating, data=meta,
                  init.type="Spectral", seed=2138, max.em.its=200, verbose=FALSE)
cat("faSTM fit: V=", length(vocab), " D=", length(docs),
    " iters=", fit$convergence$its, " bound=", round(tail(fit$convergence$bound,1),2), "\n", sep="")

frex <- faSTM::label_topics(fit, n=7)$frex          # 20 x 7 top FREX words
coh  <- faSTM::semantic_coherence(fit, M=10)        # 20
writeLines(apply(frex, 1, paste, collapse=" "), "tests/parity/gold_frex.txt")
write.csv(data.frame(topic=1:20, coherence=round(coh,4)),
          "tests/parity/gold_coherence.csv", row.names=FALSE)
cat("gold FREX (first 3 topics):\n"); print(apply(frex,1,paste,collapse=" ")[1:3])
cat("gold coherence (first 5):", round(coh[1:5],2), "\n")
