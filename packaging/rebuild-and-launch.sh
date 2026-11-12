#!/usr/bin/env bash
#
# Backs the desktop file's "Rebuild from source" action: export, install the
# result over the installed copy, launch it.
#
# Runs in a terminal so the export is visible rather than appearing to hang, and
# waits at the end on failure - a window that closes instantly takes the error
# with it, which is the whole reason a desktop action is hard to debug.
#
# The first argument is the prefix the install lives under, which install.sh
# baked into the desktop entry. Without it, ~/.local.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")" && pwd)"
REPO_ROOT="${SARA_REPO_ROOT:-$(dirname "$SCRIPT_DIR")}"
export SARA_PREFIX="${1:-${SARA_PREFIX:-$HOME/.local}}"
[ $# -gt 0 ] && shift

cd "$REPO_ROOT" || { echo "Cannot find the Sara repository at $REPO_ROOT"; read -r -p "Press Enter..."; exit 1; }

printf '\n\033[38;5;215m  Rebuilding Sara\033[0m \033[38;5;242mfrom %s\033[0m\n' "$REPO_ROOT"

if command -v git >/dev/null 2>&1 && [ -d .git ]; then
    printf '\033[38;5;242m  %s\033[0m\n' "$(git log --oneline -1 2>/dev/null || echo 'no commits')"
fi

# The build just made is the one to install, and a tree with edits in it would
# otherwise read as stale to install.sh and be built a second time.
if ! "$SCRIPT_DIR/build.sh" || ! "$SCRIPT_DIR/install.sh" --no-build; then
    printf '\n\033[38;5;203m  Build failed - not launching.\033[0m\n\n'
    read -r -p "Press Enter to close..."
    exit 1
fi

exec "$SARA_PREFIX/lib/sara/sara.sh" "$@"
