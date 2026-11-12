#!/usr/bin/env bash
#
# gdformat and gdlint over every script, with a death told apart from a verdict.
#
# A gate that quotes both tools as bare commands cannot tell a death from a
# verdict: a killed run exits non-zero with nothing printed and reads exactly
# like a dirty tree. SIGTERM gives 143 and no output, an OOM kill gives 137 and
# no output, and one bad name gives 1 and names the rule, and only the third of
# those means anything about the code. A bare command has nowhere to put the
# difference, so the two lines live here.
#
# Usage:  scripts/check_style.sh [--write] [path ...]
#         with no paths, the same tree the gate has always checked.
#         --write lets gdformat rewrite rather than only report, which is the
#         one thing a person wants from these tools that the gate never does.
#         It exists so that there is no second door: a bare `.conda/bin/...`
#         written down anywhere is a copy that will drift, and the suite fails
#         the gate's own pages for carrying one.
# Exit:   0  both tools are happy
#         1  gdformat or gdlint has something to say, and said it
#         2  a tool was killed, or is not installed. Nothing was decided.
#
# 2 rather than the signal's own 128+n, because a caller reading `$?` wants one
# code for "ask again later" and the number of the signal is a detail the
# message carries. The message names the signal.
#
# Not batched, on purpose. Splitting the argv through `xargs` would be the
# answer if peak memory followed the file count, and it does not: gdlint peaks
# at 42.7 MB over 80 paths and 43.1 MB over all 821, flat, because it parses
# one file at a time and keeps nothing. So the argv stays whole and the answer
# to a killed tool is the message rather than the shape.
set -u

# A signal aimed at the whole process group hits this script as well as the
# tool it is waiting on, and the group is how a killed gate dies. The traps sit
# here, at the top, rather than beside the loop, because a signal that arrives
# in the half-millisecond before bash reads the `trap` line
# finds nothing installed and takes the default action, which is exactly the
# silent death this script exists to prevent.
#
# SIGKILL cannot be trapped by anything, so a run taken by the OOM killer still
# says nothing. That is a limit of the shell rather than of this script, and it
# only bites when the wrapper itself is the victim: a tool killed that way is
# reported by `run_tool` below, because the wrapper is still alive to report it.
TOOL_PID=""
killed_by() {
    [ -n "$TOOL_PID" ] && kill "$TOOL_PID" 2>/dev/null
    echo "check_style.sh: killed by SIG$1 before it finished." >&2
    echo "  Nothing was decided about the tree. Run the gate again." >&2
    exit 2
}
trap 'killed_by TERM' TERM
trap 'killed_by INT' INT
trap 'killed_by HUP' HUP

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_PATH="$(dirname "$SCRIPT_DIR")"

# The gdtoolkit env the gate expects, overridable so the suite can put fakes
# where the tools go. Same shape and same reason as check_lsp.sh's
# GODOT_BIN_OVERRIDE, and read before anything looks for the real ones.
#
# Without the override, the first of three places that holds gdformat: the
# conda env, then a venv as Linux and macOS lay it out, then a venv as Windows
# does, so a Windows developer need not set the variable on every run. When
# none holds it the conda env stays the answer, and is the path the refusal
# below names.
BIN_DIR="${GDTOOLKIT_BIN_DIR:-}"
if [ -z "$BIN_DIR" ]; then
    BIN_DIR="$PROJECT_PATH/.conda/bin"
    for candidate in "$PROJECT_PATH/.conda/bin" "$PROJECT_PATH/.venv/bin" "$PROJECT_PATH/.venv/Scripts"; do
        if [ -x "$candidate/gdformat" ]; then
            BIN_DIR="$candidate"
            break
        fi
    done
fi
BIN_DIR_NOTE=""

# A worktree has no .conda of its own: the env is gitignored, so only the
# clone it was linked into carries it. Without the override, and only when
# none of this worktree's own three places holds gdformat, ask git for the main
# checkout's path and borrow its env instead of refusing outright.
MAIN_BIN_DIR=""
if [ -z "${GDTOOLKIT_BIN_DIR:-}" ] && [ ! -x "$BIN_DIR/gdformat" ]; then
    MAIN_WORKTREE="$(git -C "$PROJECT_PATH" worktree list --porcelain 2>/dev/null |
        awk '/^worktree /{print substr($0, 10); exit}')"
    if [ -n "$MAIN_WORKTREE" ]; then
        MAIN_BIN_DIR="$MAIN_WORKTREE/sara-godot/.conda/bin"
        if [ -x "$MAIN_BIN_DIR/gdformat" ]; then
            BIN_DIR="$MAIN_BIN_DIR"
            BIN_DIR_NOTE=" (the main checkout's, this worktree has none)"
        fi
    fi
fi
# The last place, for a machine that installed gdtoolkit with pip or a package
# manager and has no env in the tree: wherever gdformat is on PATH, taken only
# when nothing above held one. gdlint is looked for beside it.
if [ -z "${GDTOOLKIT_BIN_DIR:-}" ] && [ ! -x "$BIN_DIR/gdformat" ]; then
    ON_PATH="$(command -v gdformat 2>/dev/null || true)"
    if [ -n "$ON_PATH" ] && [ -x "$ON_PATH" ]; then
        BIN_DIR="$(dirname "$ON_PATH")"
        BIN_DIR_NOTE=" (found on PATH)"
    fi
fi
echo "check_style.sh: gdtoolkit env $BIN_DIR$BIN_DIR_NOTE" >&2

# The tree the gate checks. The harness and every module are in it, because a
# folder left out drifts from the style the rest keeps: the gate once named
# only the base modules, and the other modules grew lines past the 130 column
# limit that gdlint's max-line-length and gdformat's line_length set, which
# nothing said until an editor did. A module that is a repository of its
# own is still checked from here, with this folder's gdlintrc and gdformatrc, so
# there is one style. A module a copy leaves out has no folder, and is skipped.
# A string that has to stay whole, a message the catalogue is keyed on, carries
# `# gdlint:ignore=max-line-length` on the line above it.
TREE=(core render tools ui utils tests harness)
for module_dir in "$PROJECT_PATH"/modules/*/; do
    [ -d "$module_dir" ] && TREE+=("modules/$(basename "$module_dir")")
done

FORMAT_ARGS=(--check)
if [ "${1:-}" = "--write" ]; then
    FORMAT_ARGS=()
    shift
fi

if [ "$#" -gt 0 ]; then
    FILES=("$@")
else
    mapfile -t FILES < <(cd "$PROJECT_PATH" && find "${TREE[@]}" -name "*.gd" | sort)
fi

if [ "${#FILES[@]}" -eq 0 ]; then
    echo "check_style.sh: no .gd file to check under ${TREE[*]}." >&2
    exit 2
fi

# A signal by name, because "killed by SIGKILL" is actionable and "exit 137" is
# a number the reader has to know to subtract 128 from. `kill -l` answers the
# name for a number it recognizes and fails for one it does not, and a code
# above 128 that no signal claims is left as itself.
signal_name() {
    local name
    name="$(kill -l "$(( $1 - 128 ))" 2>/dev/null)" || return 1
    [ -n "$name" ] || return 1
    printf 'SIG%s' "$name"
}

# One tool, run over the whole list, with the three outcomes kept apart.
run_tool() {
    local tool="$1"
    shift
    local bin="$BIN_DIR/$tool"
    if [ ! -x "$bin" ]; then
        if [ -n "$MAIN_BIN_DIR" ] && [ "$BIN_DIR" != "$MAIN_BIN_DIR" ]; then
            echo "check_style.sh: no $tool at $bin, nor at $MAIN_BIN_DIR/$tool." >&2
        else
            echo "check_style.sh: no $tool at $bin." >&2
        fi
        echo "  the gate needs a gdtoolkit env there." >&2
        echo "  GDTOOLKIT_BIN_DIR overrides where it looks, and a gdformat on PATH is the last place." >&2
        return 2
    fi
    # Backgrounded and waited on rather than run in the foreground, for two
    # reasons and neither is concurrency. A foreground command killed by a
    # signal makes bash print its own `Terminated` line with the unexpanded
    # source text of the call, which lands above this script's message and
    # reads like a second, stranger error. And bash defers a trap until a
    # foreground child returns, so a signal at the process group would sit
    # unhandled behind a tool that is still dying.
    #
    # Backgrounding silences that line for every signal except SIGKILL, which
    # bash reports whatever it is asked, so an OOM kill still prints a raw
    # `Killed  "$bin" ...` above the sentence that explains it. Swallowing it
    # would mean swallowing the tool's own output, which is the one thing this
    # script must not do.
    "$bin" "$@" "${FILES[@]}" &
    TOOL_PID=$!
    wait "$TOOL_PID"
    local code=$?
    TOOL_PID=""
    [ "$code" -eq 0 ] && return 0
    if [ "$code" -gt 128 ]; then
        local name
        name="$(signal_name "$code")" || name="signal $(( code - 128 ))"
        echo "check_style.sh: $tool was killed by $name, exit $code." >&2
        echo "  Nothing was decided about the tree. It says nothing when it dies," >&2
        echo "  so this is not a formatting or lint failure. Run the gate again." >&2
        return 2
    fi
    echo "check_style.sh: $tool exited $code, and what it printed above is why." >&2
    return 1
}

# gdformat first and gdlint after it either way, because a reader fixing style
# wants both lists in one run rather than one, a fix, and then the other. The
# worst outcome of the two is what the script exits on, a kill outranking a
# verdict: a run where one tool was killed did not check the whole tree, so a
# green from the other is not a green.
WORST=0
for tool in gdformat gdlint; do
    if [ "$tool" = "gdformat" ]; then
        run_tool gdformat "${FORMAT_ARGS[@]}"
    else
        run_tool gdlint
    fi
    code=$?
    [ "$code" -eq 2 ] && WORST=2
    [ "$code" -eq 1 ] && [ "$WORST" -eq 0 ] && WORST=1
done

exit "$WORST"
