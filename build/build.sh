#!/usr/bin/env bash
# Build fastm.plugin for the current OS.
#
#   On macOS, builds a UNIVERSAL binary (x86_64 + arm64) so it loads in both
#   Intel/Rosetta Stata and native Apple Silicon Stata. Set MACOS_ARCHS to one
#   arch (e.g. MACOS_ARCHS=arm64) for a faster single-arch dev build.
#
#   Stata is an x86_64 program through Stata 16 (and runs under Rosetta on Apple
#   Silicon); Stata 17+ on Apple Silicon is native arm64. On Linux, Stata is
#   x86_64. Override the Linux Rust target with RTARGET=... if needed.
#
# Usage:  bash build/build.sh
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
CRATE="$ROOT/crate"
VENDOR="$ROOT/vendor"
OBJ="$ROOT/build"
OUT="$ROOT/fastm.plugin"

UNAME="$(uname -s)"
case "$UNAME" in
  Darwin)
    SYS=3                                  # APPLEMAC
    ARCHS="${MACOS_ARCHS:-x86_64 arm64}"
    SLICES=()
    for arch in $ARCHS; do
      case "$arch" in
        x86_64) RT=x86_64-apple-darwin ;;
        arm64)  RT=aarch64-apple-darwin ;;
        *) echo "unknown macOS arch: $arch" >&2; exit 1 ;;
      esac
      echo ">> Rust staticlib  ($RT)"
      ( cd "$CRATE"
        rustup target add "$RT" >/dev/null 2>&1 || true
        cargo build --release --target "$RT" )
      ALIB="$CRATE/target/$RT/release/libfastm.a"
      [ -f "$ALIB" ] || { echo "missing $ALIB" >&2; exit 1; }
      echo ">> shim + link ($arch, SYSTEM=$SYS)"
      cc -arch "$arch" -DSYSTEM=$SYS -I"$VENDOR" -c "$VENDOR/stplugin.c" -o "$OBJ/stplugin_$arch.o"
      cc -arch "$arch" -DSYSTEM=$SYS -I"$VENDOR" -c "$CRATE/src/shim.c"   -o "$OBJ/shim_$arch.o"
      cc -arch "$arch" -bundle -o "$OBJ/fastm_$arch.plugin" \
         "$OBJ/shim_$arch.o" "$OBJ/stplugin_$arch.o" "$ALIB"
      SLICES+=("$OBJ/fastm_$arch.plugin")
    done
    if [ "${#SLICES[@]}" -gt 1 ]; then
      echo ">> lipo -> universal $OUT"
      lipo -create "${SLICES[@]}" -output "$OUT"
    else
      cp "${SLICES[0]}" "$OUT"
    fi
    ;;
  Linux)
    SYS=2                                  # OPUNIX
    RTARGET="${RTARGET:-x86_64-unknown-linux-gnu}"
    echo ">> Rust staticlib  ($RTARGET)"
    ( cd "$CRATE"
      rustup target add "$RTARGET" >/dev/null 2>&1 || true
      cargo build --release --target "$RTARGET" )
    ALIB="$CRATE/target/$RTARGET/release/libfastm.a"
    [ -f "$ALIB" ] || { echo "missing $ALIB" >&2; exit 1; }
    echo ">> shim + link (SYSTEM=$SYS)"
    cc -fPIC -DSYSTEM=$SYS -I"$VENDOR" -c "$VENDOR/stplugin.c" -o "$OBJ/stplugin.o"
    cc -fPIC -DSYSTEM=$SYS -I"$VENDOR" -c "$CRATE/src/shim.c"   -o "$OBJ/shim.o"
    cc -shared -o "$OUT" "$OBJ/shim.o" "$OBJ/stplugin.o" "$ALIB" -lm -ldl -lpthread
    ;;
  *) echo "unsupported OS: $UNAME" >&2; exit 1 ;;
esac

echo "built: $OUT"
file "$OUT" 2>/dev/null || true
lipo -info "$OUT" 2>/dev/null || true
echo "exported entry points (want stata_call + pginit):"
nm -g "$OUT" 2>/dev/null | grep -E 'stata_call|pginit' || true
