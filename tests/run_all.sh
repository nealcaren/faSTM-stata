#!/usr/bin/env bash
# Run the Stata smoke tests and report pass/fail.
#
#   bash tests/run_all.sh
#
# Stata writes its batch log to the working directory, so running the suite from
# the repo root litters it with a .log per do-file. This runs each test from a
# scratch directory instead and only surfaces the log of a test that fails.
#
# STATA overrides the interpreter. The default is the console binary: the `stata`
# on PATH is often the GUI app, which opens a window per run.

set -uo pipefail
cd "$(dirname "$0")/.."
REPO=$PWD

STATA=${STATA:-/Applications/Stata/StataMP.app/Contents/MacOS/stata-mp}
if [ ! -x "$STATA" ]; then
    STATA=$(command -v stata || true)
    [ -n "$STATA" ] || { echo "no Stata found; set STATA=/path/to/stata" >&2; exit 1; }
fi

TESTS=(api_cleanup_smoke predict_smoke margins_metadata_smoke estat_restore_smoke searchk_smoke fidelity_fixes_smoke)

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

status=0
for t in "${TESTS[@]}"; do
    # The do-files use paths relative to the repo root (adopath ++ "ado"), so run
    # from a scratch dir that has the repo's contents linked in.
    rm -rf "$WORK/run" && mkdir -p "$WORK/run"
    for item in ado data tests examples; do
        [ -e "$REPO/$item" ] && ln -s "$REPO/$item" "$WORK/run/$item"
    done

    ( cd "$WORK/run" && "$STATA" -b do "tests/$t.do" ) >/dev/null 2>&1
    log="$WORK/run/$t.log"

    if [ -f "$log" ] && ! grep -qE '^r\([0-9]+\);' "$log"; then
        printf 'PASS  %s\n' "$t"
    else
        printf 'FAIL  %s\n' "$t"
        status=1
        if [ -f "$log" ]; then
            grep -B6 -m1 -E '^r\([0-9]+\);' "$log" | sed 's/^/      /'
            cp "$log" "$REPO/$t.log"
            echo "      (log kept at $t.log)"
        else
            echo "      (Stata produced no log; is $STATA correct?)"
        fi
    fi
done

echo
[ $status -eq 0 ] && echo "all tests passed" || echo "some tests failed"
exit $status
