run "ado/fastm.ado"
use tests/parity/poliblog.dta, clear
fastm text, k(20) prevalence(i.liberal) seed(2138) iters(200)
di "PARITY_V=" e(n_terms) " PARITY_D=" e(N_docs) " PARITY_BOUND=" %12.0f e(bound) " PARITY_ITERS=" e(iters)
