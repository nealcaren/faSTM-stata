run "ado/fastm.ado"
use tests/parity/poliblog.dta, clear
fastm text, k(20) spline(day, df(10)) seed(2138) iters(200)
di "SPLINE_BOUND=" %12.0f e(bound) " SPLINE_NPREV=" e(n_prevalence) " SPLINE_ITERS=" e(iters)
