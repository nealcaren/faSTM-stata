run "ado/fastm.ado"
use tests/parity/poliblog.dta, clear
fastm text, k(20) content(liberal) seed(2138) iters(200)
di "CONTENT_BOUND=" %12.0f e(bound) " CONTENT_NG=" e(n_content) " CONTENT_ITERS=" e(iters)
