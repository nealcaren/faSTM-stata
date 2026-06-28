/*
 * host.c — a "fake Stata" that loads the shipped fastm plugin and drives one
 * real STM fit, WITHOUT Stata. It implements the Stata plugin ABI (the SF_*
 * callback table in vendor/stplugin.h) backed by in-memory arrays, loads the
 * plugin with the OS loader, calls pginit() to hand over the table, then calls
 * stata_call("fit", ...) on a tiny synthetic corpus and checks the result.
 *
 * Purpose: a smoke test that the *shipped binary* loads, resolves its exports,
 * matches the calling convention, and runs the engine to completion on the
 * target OS. On windows-latest CI this exercises the real Windows binary on a
 * real Windows loader — the strongest check available without a Stata license.
 * It does NOT test Stata's own SF_* implementations (those are mocked here);
 * that residual is what the Stata Journal reviewers' Windows run covers.
 *
 * Build/run: see run.sh (Unix/Wine) and the win-smoke CI job in build.yml.
 *
 * The struct/typedefs come from vendor/stplugin.h. Define SYSTEM to match the
 * host OS (STWIN32=4 on Windows is the header default; OPUNIX=2 / APPLEMAC=3
 * elsewhere) so the function-pointer typedefs are picked up cleanly.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "stplugin.h"   /* ST_plugin struct + ST_int/ST_double/etc. typedefs */

#if defined(_WIN32)
#include <windows.h>
typedef HMODULE dl_t;
static dl_t dl_open(const char *p) { return LoadLibraryA(p); }
static void *dl_sym(dl_t h, const char *s) { return (void *)GetProcAddress(h, s); }
#else
#include <dlfcn.h>
typedef void *dl_t;
static dl_t dl_open(const char *p)
{
    /* dlopen() of a bare leaf name searches the system library path, not the
     * cwd; prepend ./ so a plain "fastm.plugin" resolves locally (Linux). */
    char buf[1024];
    if (!strchr(p, '/')) { snprintf(buf, sizeof buf, "./%s", p); p = buf; }
    return dlopen(p, RTLD_NOW | RTLD_LOCAL);
}
static void *dl_sym(dl_t h, const char *s) { return dlsym(h, s); }
#endif

/* ----------------------------------------------------------------------------
 * In-memory "dataset": one string text var (var 1) and K theta vars (2..K+1).
 * -------------------------------------------------------------------------- */
#define NDOCS  60
#define KTOP    3
#define NVARS  (1 + KTOP)   /* text + theta1..theta3 */

static char  g_text[NDOCS][64];
static double g_theta[NDOCS][KTOP];   /* captured from the plugin's vstore */
static int    g_zero = 0;             /* for the stopflag pointer */

/* A clean 3-topic corpus, vocab of 15 alphabetic words (5 per topic). The
 * engine's default tokenizer keeps letter-only tokens of length >= 2, so the
 * words must be real letters. Each doc draws its 11 words from its own topic
 * block plus 1 from the next block, so the co-occurrence structure is well
 * separated and the spectral init is stable. */
static const char *VOCAB[KTOP][5] = {
    { "apple",  "apricot", "avocado", "almond", "acorn"  },
    { "river",  "ocean",   "lake",    "stream", "pond"   },
    { "copper", "iron",    "silver",  "bronze", "nickel" },
};
static void build_corpus(void)
{
    for (int i = 0; i < NDOCS; i++) {
        int topic = i % KTOP;
        char *p = g_text[i];
        p[0] = '\0';
        for (int w = 0; w < 12; w++) {
            const char *word = (w < 11)
                ? VOCAB[topic][w % 5]
                : VOCAB[(topic + 1) % KTOP][i % 5]; /* 1 cross word */
            if (w) strncat(p, " ", sizeof(g_text[i]) - strlen(p) - 1);
            strncat(p, word, sizeof(g_text[i]) - strlen(p) - 1);
        }
    }
}

/* ----------------------------------------------------------------------------
 * SF_* callbacks. Signatures must match the typedefs in stplugin.h exactly.
 * -------------------------------------------------------------------------- */
static ST_int     cb_display(char *s)            { fputs(s, stdout); return 0; }
static ST_int     cb_error(char *s)              { fputs(s, stderr); return 0; }
static ST_int     cb_nobs(void)                  { return NDOCS; }
static ST_int     cb_nvars(void)                 { return NVARS; }
static ST_int     cb_in1(void)                   { return 1; }
static ST_int     cb_in2(void)                   { return NDOCS; }
static ST_boolean cb_selobs(ST_int obs)          { (void)obs; return 1; }
static ST_boolean cb_ismissing(ST_double v)      { (void)v; return 0; }

static ST_int cb_vdata(ST_int var, ST_int obs, ST_double *d) /* no prevalence vars here */
{ (void)var; (void)obs; *d = 0.0; return 0; }

static ST_int cb_store(ST_int var, ST_int obs, ST_double v)  /* theta write-back */
{
    int t = var - 2;          /* var 2 -> theta col 0 */
    int o = obs - 1;          /* obs is 1-based */
    if (t >= 0 && t < KTOP && o >= 0 && o < NDOCS) g_theta[o][t] = v;
    return 0;
}

static ST_int cb_scalsave(char *name, ST_double v) { printf("  e(%s) = %g\n", name, v); return 0; }
static ST_int cb_matstore(char *nm, ST_int r, ST_int c, ST_double v) { (void)nm;(void)r;(void)c;(void)v; return 0; }
static ST_int cb_macresave(char *nm, char *txt)    { (void)nm; (void)txt; return 0; }
static ST_int cb_macuse(char *nm, char *buf, ST_int len) { (void)nm; if (len > 0) buf[0] = '\0'; return 0; }

static ST_int     cb_sdatalen(ST_int var, ST_int obs) { (void)var; return (ST_int)strlen(g_text[obs - 1]); }
static ST_boolean cb_isstrl(ST_int var)               { (void)var; return 0; } /* plain str#, use sdata */
static ST_int     cb_sdata(ST_int var, ST_int obs, char *buf) { (void)var; strcpy(buf, g_text[obs - 1]); return 0; }
static ST_int     cb_strldata(ST_int var, ST_int obs, char *buf, ST_int len)
{ (void)var; (void)len; strcpy(buf, g_text[obs - 1]); return (ST_int)strlen(buf); }

static void fill_table(ST_plugin *t)
{
    memset(t, 0, sizeof *t);
    t->spoutsml   = cb_display;
    t->spoutnosml = cb_display;
    t->spouterr   = cb_error;
    t->nobs       = cb_nobs;
    t->nvar       = cb_nvars;
    t->nvars      = cb_nvars;
    t->nobs1      = cb_in1;
    t->nobs2      = cb_in2;
    t->selobs     = cb_selobs;
    t->ismissing  = cb_ismissing;
    t->missval    = 8.98846567431158e307;   /* Stata's . */
    t->vdata      = cb_vdata;
    t->safevdata  = cb_vdata;
    t->store      = cb_store;
    t->safestore  = cb_store;
    t->scalsave   = cb_scalsave;
    t->matstore   = cb_matstore;
    t->safematstore = cb_matstore;
    t->macresave  = cb_macresave;
    t->macuse     = cb_macuse;
    t->sdatalen   = cb_sdatalen;
    t->isstrl     = cb_isstrl;
    t->sdata      = cb_sdata;
    t->strldata   = cb_strldata;
    t->stopflag   = &g_zero;
}

typedef ST_retcode (*pginit_t)(ST_plugin *);
typedef ST_retcode (*stata_call_t)(int, char **);

int main(int argc, char **argv)
{
    const char *plugin = (argc > 1) ? argv[1] : "fastm.plugin";

    dl_t h = dl_open(plugin);
    if (!h) { fprintf(stderr, "FAIL: could not load '%s'\n", plugin); return 2; }

    pginit_t pginit = (pginit_t)dl_sym(h, "pginit");
    stata_call_t stata_call = (stata_call_t)dl_sym(h, "stata_call");
    if (!pginit || !stata_call) {
        fprintf(stderr, "FAIL: missing export(s): pginit=%p stata_call=%p\n",
                (void *)pginit, (void *)stata_call);
        return 3;
    }
    printf("loaded '%s'; exports pginit + stata_call resolved\n", plugin);

    static ST_plugin table;
    fill_table(&table);
    pginit(&table);

    build_corpus();
    for (int i = 0; i < NDOCS; i++)
        for (int t = 0; t < KTOP; t++) g_theta[i][t] = -1.0;

    /* plugin call fastm <text> <theta1..K>, fit <K> <seed> <em_iters> */
    char *call_argv[] = { (char *)"fit", (char *)"3", (char *)"42", (char *)"30" };
    int call_argc = 4;

    ST_retcode rc = stata_call(call_argc, call_argv);
    printf("stata_call returned %d\n", (int)rc);
    if (rc != 0) { fprintf(stderr, "FAIL: fit returned nonzero rc=%d\n", (int)rc); return 4; }

    /* Each document's topic proportions must be written and sum to ~1. */
    int bad = 0;
    for (int i = 0; i < NDOCS; i++) {
        double s = 0.0;
        for (int t = 0; t < KTOP; t++) {
            double v = g_theta[i][t];
            if (v < -0.5) { fprintf(stderr, "FAIL: theta not written for doc %d topic %d\n", i, t); bad++; break; }
            if (v < -1e-9 || v > 1.0 + 1e-6) { fprintf(stderr, "FAIL: theta out of [0,1] doc %d: %g\n", i, v); bad++; break; }
            s += v;
        }
        if (!bad && (s < 1.0 - 1e-3 || s > 1.0 + 1e-3)) {
            fprintf(stderr, "FAIL: theta row %d sums to %g, not 1\n", i, s);
            bad++;
        }
        if (bad) break;
    }
    if (bad) return 5;

    printf("PASS: plugin loaded, fit ran, %d docs x %d topics written and normalized\n",
           NDOCS, KTOP);
    return 0;
}
