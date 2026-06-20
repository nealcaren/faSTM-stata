#!/usr/bin/env bash
# Build stmata.plugin for the current OS, targeting x86_64.
#
#   Stata 15 is an x86_64 binary, so the plugin MUST be x86_64 even on Apple
#   Silicon (where Stata 15 runs under Rosetta). On Longleaf, Stata is x86_64
#   Linux. Override the Rust target with RTARGET=... if needed.
#
# Usage:  bash build/build.sh
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
CRATE="$ROOT/crate"
VENDOR="$ROOT/vendor"
OBJ="$ROOT/build"
OUT="$ROOT/stmata.plugin"

UNAME="$(uname -s)"
case "$UNAME" in
  Darwin)
    SYS=3                                  # APPLEMAC
    RTARGET="${RTARGET:-x86_64-apple-darwin}"
    CCARCH="-arch x86_64"
    LINK="-bundle"
    SYSLIBS=""
    ;;
  Linux)
    SYS=2                                  # OPUNIX
    RTARGET="${RTARGET:-x86_64-unknown-linux-gnu}"
    CCARCH=""
    LINK="-shared -fPIC"
    SYSLIBS="-lm -ldl -lpthread"
    ;;
  *) echo "unsupported OS: $UNAME" >&2; exit 1 ;;
esac

echo ">> Rust staticlib  (target $RTARGET)"
( cd "$CRATE"
  rustup target add "$RTARGET" >/dev/null 2>&1 || true
  cargo build --release --target "$RTARGET" )
ALIB="$CRATE/target/$RTARGET/release/libstmata.a"
[ -f "$ALIB" ] || { echo "missing $ALIB" >&2; exit 1; }

echo ">> StataCorp shim  (SYSTEM=$SYS, SAFEMODE)"
cc $CCARCH -DSYSTEM=$SYS -I"$VENDOR" -c "$VENDOR/stplugin.c" -o "$OBJ/stplugin.o"
cc $CCARCH -DSYSTEM=$SYS -I"$VENDOR" -c "$CRATE/src/shim.c"   -o "$OBJ/shim.o"

echo ">> link $OUT"
cc $CCARCH $LINK -o "$OUT" "$OBJ/shim.o" "$OBJ/stplugin.o" "$ALIB" $SYSLIBS

echo "built: $OUT"
file "$OUT" 2>/dev/null || true
echo "exported entry points (want stata_call + pginit):"
nm -g "$OUT" 2>/dev/null | grep -E 'stata_call|pginit' || true
