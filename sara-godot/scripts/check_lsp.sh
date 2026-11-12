#!/usr/bin/env bash
#
# Compile diagnostics for every script, without needing an editor on screen.
#
# The LSP lives inside the Godot editor, so a check that does not start one of
# its own runs only while someone has the project open in VS Code. A headless
# editor serves the same protocol on the same port, so this starts one, asks
# it, and stops it again. An editor that is already listening is left completely alone: it is
# probably the user's, and killing it would be rude.
#
# Usage:  scripts/check_lsp.sh [--which-port]
# Exit:   whatever check_lsp_errors.py returns, so it can gate a script.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_PATH="$(dirname "$SCRIPT_DIR")"
# The same three places check_style.sh looks for gdtoolkit in, conda first and
# a venv after it, then whatever Python is on PATH.
PYTHON="python3"
for candidate in "$PROJECT_PATH/.conda/bin" "$PROJECT_PATH/.venv/bin" "$PROJECT_PATH/.venv/Scripts"; do
    if [ -x "$candidate/python" ]; then
        PYTHON="$candidate/python"
        break
    fi
done

# Which port this checkout's editor listens on is asked of check_lsp_errors.py,
# which owns the rule, so that godot_console.py and the checker run by hand
# default to the same port as this script. The main
# `sara` checkout gets 6005, every other clone or worktree one derived from its path,
# and SARA_LSP_PORT overrides. `--which-port` prints it and does nothing else.
PORT="$("$PYTHON" "$SCRIPT_DIR/check_lsp_errors.py" --which-port "$PROJECT_PATH")"
if [ "${1:-}" = "--which-port" ]; then
    echo "$PORT"
    exit 0
fi

# The override is read first, not last. Applied after the search, it would
# never be looked at on a machine with no godot at all, and the name promises
# the opposite. test_check_lsp.py leans on this to put a fake language server
# where the editor goes.
if [ -n "${GODOT_BIN_OVERRIDE:-}" ]; then
    GODOT_BIN="$GODOT_BIN_OVERRIDE"
elif command -v godot &> /dev/null; then
    GODOT_BIN="godot"
elif command -v godot4 &> /dev/null; then
    GODOT_BIN="godot4"
else
    echo "check_lsp.sh: no godot on PATH. Set GODOT_BIN_OVERRIDE." >&2
    exit 1
fi

# Asked of Python with a connect rather than of `ss`, which Git Bash does not
# have, so a run on Windows that reads `ss` starts a second editor and waits
# out a minute for a port it cannot see.
listening() { "$PYTHON" "$SCRIPT_DIR/check_lsp_errors.py" --listening "$PORT"; }

EDITOR_PID=""
# Kill the editor this script started, and wait for it to actually go. A dying
# editor's port stays open for as long as the process is alive, which under
# load is several seconds, so a run that returns while its own editor is still
# exiting hands the next run a socket nobody will ever answer on, which reads
# as "Please ensure Godot Editor is running" and alternates pass, fail, pass,
# fail down a loop of twenty. Bounded at thirty seconds so an editor that
# ignores the signal cannot hang the gate.
cleanup() {
    local status=$?
    [ -n "$EDITOR_PID" ] || return 0
    # Every kill takes an `|| true`: `set -e` is on, and a bare simple command
    # that fails inside an EXIT trap aborts the trap and takes the script's
    # exit code with it. A `kill -9` on a process that has already gone fails,
    # so ten clean runs in a row reported 782 files checked and exited 1.
    kill "$EDITOR_PID" 2>/dev/null || true
    for _ in $(seq 1 60); do
        kill -0 "$EDITOR_PID" 2>/dev/null || break
        sleep 0.5
    done
    kill -9 "$EDITOR_PID" 2>/dev/null || true
    # The editor's log is kept for a failed run and removed after a green one,
    # or every gate leaves one in the temporary folder for good, hundreds of
    # them on a machine a board runs on.
    if [ "$status" -eq 0 ] && [ -n "${LSP_LOG:-}" ]; then
        rm -f "$LSP_LOG" || true
    fi
    return 0
}
trap cleanup EXIT

if listening; then
    echo "check_lsp.sh: using the editor already listening on $PORT"
else
    echo "check_lsp.sh: starting a headless editor for the language server"
    LSP_LOG="${TMPDIR:-/tmp}/sara_lsp_editor_$$.log"
    # The editor runs the `@tool` settings autoload, which saves the painter's
    # own ~/.config/sara/settings.cfg on every check and touches their user://
    # as well. So it gets a scratch folder of each, the way run_tests.sh gives
    # the suites theirs, and --settings-dir moves the settings file and the
    # data root together.
    LSP_SCRATCH="$PROJECT_PATH/scratch/xdg-lsp"
    mkdir -p "$LSP_SCRATCH/data" "$LSP_SCRATCH/config/sara"
    XDG_DATA_HOME="$LSP_SCRATCH/data" "$GODOT_BIN" --path "$PROJECT_PATH" --editor --headless --lsp-port "$PORT" \
        --settings-dir="$LSP_SCRATCH/config/sara" >"$LSP_LOG" 2>&1 &
    EDITOR_PID=$!
    # The editor imports before it opens the port, so a cold .godot cache is the
    # slow case this waits for rather than a fixed sleep.
    for _ in $(seq 1 120); do
        listening && break
        sleep 0.5
    done
    if ! listening; then
        echo "check_lsp.sh: the headless editor never opened port $PORT." >&2
        echo "  its log: $LSP_LOG" >&2
        exit 1
    fi
fi

# --connect-timeout is generous here and nowhere else: this script has just
# watched the port open, so a refusal now is the editor still settling rather
# than an editor that is not there. It goes before "$@" so a caller can still
# override it. The handshake and diagnostics waits are the client's own
# defaults, which are wide enough for a loaded machine.
"$PYTHON" "$SCRIPT_DIR/check_lsp_errors.py" --port "$PORT" --connect-timeout 30 "$@"
