#!/usr/bin/env bash
#
# Proves that a crash of the built binary can be read. It crashes
# build/l/sara.x86_64 on purpose through core/app/sa_crash_probe.gd and fails
# unless the engine's handler printed a backtrace whose GDScript frames name
# that file with a line number. The first crash of an installed build printed
# nothing, and this is the check that would have said so before it shipped.
#
# The binary is started with --headless, so no display and no GPU are needed:
# the probe sits above the bootstrap's headless return. Its profile is a
# temporary folder, so no real settings or layout are touched.
#
#   ./packaging/check_crash_report.sh              build if stale, then check
#   SARA_CRASH_BIN=/path/to/binary ./packaging/check_crash_report.sh
#                                                  check that binary as it is
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
BIN="${SARA_CRASH_BIN:-}"
LIMIT="${SARA_CRASH_TIMEOUT:-120}"

fail() { printf '✗ %s\n' "$1" >&2; exit 1; }

if [ -z "$BIN" ]; then
    BIN="$REPO_ROOT/build/l/sara.x86_64"
    # Stale means any tracked source under the project or this folder is newer
    # than the binary. build/ and .godot/ are output and are never looked at.
    NEWER=""
    if [ -x "$BIN" ]; then
        NEWER="$(find "$REPO_ROOT/sara-godot" "$SCRIPT_DIR" "$REPO_ROOT/CHANGELOG.md" \
            -path "$REPO_ROOT/sara-godot/.godot" -prune -o \
            -path "$REPO_ROOT/sara-godot/scratch" -prune -o \
            -path "$REPO_ROOT/sara-godot/.conda" -prune -o \
            -type f -newer "$BIN" -print -quit 2>/dev/null)"
    fi
    if [ ! -x "$BIN" ] || [ -n "$NEWER" ]; then
        "$SCRIPT_DIR/build.sh"
    fi
fi
[ -x "$BIN" ] || fail "$BIN is missing or not executable."

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
ERR="$WORK/stderr.log"

# A crash is a non-zero exit, so the code is read rather than trusted to set -e.
# The inner shell is there to swallow bash's own "Aborted" job notice, which
# would otherwise sit above the result as if it were a finding.
CODE=0
SARA_CRASH_ON_PURPOSE=boot XDG_DATA_HOME="$WORK/data" XDG_CONFIG_HOME="$WORK/config" \
    bash -c 'timeout -k 5 "$1" "$2" --headless >"$3" 2>"$4"; exit $?' _ \
    "$LIMIT" "$BIN" "$WORK/stdout.log" "$ERR" 2>/dev/null || CODE=$?

[ "$CODE" -ne 124 ] || fail "The binary was still running after ${LIMIT}s, so the probe never fired."
[ "$CODE" -ne 0 ] || fail "The binary exited 0 with SARA_CRASH_ON_PURPOSE=boot set, so it did not crash."

HANDLER="$(grep -a -m1 'Program crashed with signal' "$ERR" || true)"
if [ -z "$HANDLER" ]; then
    tail -5 "$ERR" >&2
    fail "Exit code $CODE and no 'Program crashed with signal' on stderr: this build has no crash handler."
fi

FRAME="$(grep -a -m1 -E 'sa_crash_probe\.gd:[1-9][0-9]*' "$ERR" || true)"
if [ -z "$FRAME" ]; then
    grep -a -A4 'GDScript backtrace' "$ERR" >&2 || true
    fail "The handler ran and no frame names sa_crash_probe.gd with a line number."
fi

printf '✓ exit code %s\n' "$CODE"
printf '✓ %s\n' "$HANDLER"
# The handler's own backtrace is the last one on stderr: OS.crash reports an
# error first, which carries a backtrace of its own above it.
grep -a -A3 'GDScript backtrace' "$ERR" | tail -4 | sed 's/^ */  /'
