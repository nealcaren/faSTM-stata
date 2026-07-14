#!/usr/bin/env bash
# Verify that every plugin committed to ado/ was built from the engine revision
# pinned in crate/Cargo.lock.
#
#   bash tests/check_plugins.sh
#
# Why this exists. The plugins in ado/ are prebuilt binaries, and nothing about
# committing one proves which engine went into it. In June 2026 the topica-core
# pin moved to v0.32.0, which contained a change to the spectral initialization
# ("match stm's wprob exactly"). CI rebuilt the Linux and Windows plugins; the
# macOS plugin was never rebuilt, so it kept an older engine and macOS users
# silently got different topics than everyone else for weeks.
#
# A behavioral smoke test does not catch this: tests/win_smoke runs a 60-document
# fit whose result is identical under both engines. Provenance does catch it, so
# that is what we check. Cargo embeds the git checkout path of each dependency in
# the binary's debug strings, and that path carries the short revision:
#
#   .../.cargo/git/checkouts/topica-<hash>/<short-rev>/topica-core/src/ctm.rs
#
# We read the pinned revision from Cargo.lock and require every plugin to carry
# it. A plugin built through the local path override in crate/.cargo/config.toml
# has no such revision, and is rejected too: that override is for engine
# development and must never produce a shipped binary.

set -euo pipefail
cd "$(dirname "$0")/.."

LOCK=crate/Cargo.lock
PLUGINS=(ado/fastm-macos.plugin ado/fastm-linux-x86_64.plugin ado/fastm-windows-x86_64.plugin)

# The pinned engine revision, e.g. 9fbe23a7afc5... -> 9fbe23a
full_rev=$(grep -A3 'name = "topica-core"' "$LOCK" | grep -oE '#[0-9a-f]{40}' | tr -d '#' | head -1)
if [ -z "$full_rev" ]; then
    echo "FAIL: no topica-core git revision found in $LOCK" >&2
    echo "      (is the engine pinned to a git tag/rev?)" >&2
    exit 1
fi
short_rev=${full_rev:0:7}
echo "pinned topica-core revision: $short_rev ($full_rev)"
echo

status=0
for plugin in "${PLUGINS[@]}"; do
    name=$(basename "$plugin")

    if [ ! -f "$plugin" ]; then
        printf 'FAIL  %-30s missing\n' "$name"
        status=1
        continue
    fi

    # Cargo git checkouts appear as .../checkouts/topica-<hash>/<rev>/... The
    # separator is / on Unix and \ in the Windows (MSVC) binary. Spell both out
    # rather than using a bracket: a backslash inside [] is not portable across
    # grep implementations.
    # No match is the interesting case here, so do not let pipefail abort on it.
    found=$(strings "$plugin" \
        | grep -oE 'checkouts(/|\\)topica-[0-9a-f]+(/|\\)[0-9a-f]{7,}' \
        | sed -E 's#.*(/|\\)##' \
        | cut -c1-7 | sort -u || true)

    if [ -z "$found" ]; then
        # grep -c, not grep -q: -q exits on the first match, strings then takes a
        # SIGPIPE, and under pipefail the whole pipeline reads as failed.
        local_paths=$(strings "$plugin" | grep -cE 'topica-core(/|\\)src' || true)
        if [ "${local_paths:-0}" -gt 0 ]; then
            printf 'FAIL  %-30s built from a local path, not the pinned engine\n' "$name"
            echo "      This is what crate/.cargo/config.toml does. Move it aside and rebuild:"
            echo "        mv crate/.cargo/config.toml crate/.cargo/config.toml.off && bash build/build.sh"
        else
            printf 'FAIL  %-30s no topica-core build fingerprint found\n' "$name"
        fi
        status=1
        continue
    fi

    if [ "$found" = "$short_rev" ]; then
        printf 'ok    %-30s engine %s\n' "$name" "$found"
    else
        printf 'FAIL  %-30s engine %s, expected %s\n' "$name" "$(echo "$found" | tr '\n' ' ')" "$short_rev"
        echo "      This plugin predates the current pin. Rebuild it and commit the result;"
        echo "      the build workflow publishes a plugin artifact for each OS."
        status=1
    fi
done

echo
if [ $status -eq 0 ]; then
    echo "PASS: all shipped plugins were built from the pinned engine"
else
    echo "FAIL: a shipped plugin does not match the pinned engine (see above)"
fi
exit $status
