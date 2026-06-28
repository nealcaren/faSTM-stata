#!/usr/bin/env bash
# Build and run the fake-Stata host harness against a fastm plugin.
#
#   ./run.sh [path-to-plugin]
#
# The plugin path is resolved relative to the directory you run this from. With
# no argument it picks the plugin for the current OS from the repo's ado/.
# Set WINE=1 to build a Windows host with a mingw cross-compiler and run the
# Windows plugin under Wine (a fast local approximation of the CI check).
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)   # tests/win_smoke
REPO=$(cd "$HERE/../.." && pwd)
SRC=$HERE/host.c
OUT=$(mktemp -d)
trap 'rm -rf "$OUT"' EXIT

uname_s=$(uname -s)
plugin=${1:-}

if [ "${WINE:-0}" = "1" ]; then
    : "${CC:=x86_64-w64-mingw32-gcc}"
    plugin=${plugin:-$REPO/ado/fastm-windows-x86_64.plugin}
    "$CC" -O2 -I"$REPO/vendor" "$SRC" -o "$OUT/host.exe"
    cp "$plugin" "$OUT/fastm.plugin"
    echo ">>> running Windows host under Wine"
    ( cd "$OUT" && wine ./host.exe fastm.plugin )
    exit $?
fi

case "$uname_s" in
    Darwin) SYS=3; plugin=${plugin:-$REPO/ado/fastm-macos.plugin} ;;
    Linux)  SYS=2; plugin=${plugin:-$REPO/ado/fastm-linux-x86_64.plugin} ;;
    *)      echo "unsupported uname: $uname_s (use WINE=1 for Windows)"; exit 1 ;;
esac

: "${CC:=cc}"
"$CC" -O2 -DSYSTEM=$SYS -I"$REPO/vendor" "$SRC" -o "$OUT/host" -ldl 2>/dev/null \
    || "$CC" -O2 -DSYSTEM=$SYS -I"$REPO/vendor" "$SRC" -o "$OUT/host"
echo ">>> running host against $plugin"
"$OUT/host" "$plugin"
