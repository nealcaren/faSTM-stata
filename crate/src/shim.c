/*
 * shim.c — the only C we write. It owns the Stata plugin ABI and re-exposes
 * StataCorp's SF_* macros (which expand to (_stata_)->fnptr(...)) as real,
 * linkable extern "C" functions that the Rust side (lib.rs) can call.
 *
 * Build (see build/build.sh): compiled together with the unmodified StataCorp
 * files in vendor/ (stplugin.c defines _stata_ and pginit) and the Rust
 * staticlib, then linked into `stmata.plugin`.
 *
 * IMPORTANT: compile with -DSYSTEM=2 (OPUNIX/Linux) or -DSYSTEM=3 (APPLEMAC).
 * If SYSTEM is left undefined, stplugin.h defaults to STWIN32 and STDLL picks
 * up __declspec(dllexport), which is wrong on macOS/Linux.
 */
#include "stplugin.h"

/* Rust entry point, defined in crate/src/lib.rs. */
extern ST_retcode stmata_entry(int argc, char *argv[]);

/* Stata calls this for `plugin call stmata ...`. */
STDLL stata_call(int argc, char *argv[])
{
    return stmata_entry(argc, argv);
}

/* --- SF_* macros -> linkable symbols for Rust ------------------------------ */
void       rs_display(char *s)                        { SF_display(s); }
void       rs_error(char *s)                          { SF_error(s); }
ST_int     rs_nobs(void)                              { return SF_nobs(); }
ST_int     rs_nvars(void)                             { return SF_nvars(); }
ST_int     rs_in1(void)                               { return SF_in1(); }
ST_int     rs_in2(void)                               { return SF_in2(); }
ST_retcode rs_vdata(ST_int i, ST_int j, ST_double *d) { return SF_vdata(i, j, d); }
ST_retcode rs_vstore(ST_int i, ST_int j, ST_double v) { return SF_vstore(i, j, v); }
ST_int     rs_is_missing(ST_double v)                 { return SF_is_missing(v); }
ST_retcode rs_scal_save(char *s, ST_double d)         { return SF_scal_save(s, d); }
