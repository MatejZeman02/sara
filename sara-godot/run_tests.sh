#!/usr/bin/env bash
set -e

# Resolve project directories relative to this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_PATH="$SCRIPT_DIR"
LOG_FILE="/tmp/sara_test_output_$$.log"

# Godot only exits when run_all.gd calls get_tree().quit(), so a script that
# fails to parse, or a suite that blocks, would hang the run. A watchdog turns a
# hang into a failure after this many seconds, about three times a loaded full
# run. SARA_TEST_TIMEOUT raises it for a slower machine, and a lower value
# brings back false timeouts. tests/README.md has the reasoning.
DEFAULT_TEST_TIMEOUT=1980
: "${SARA_TEST_TIMEOUT:=$DEFAULT_TEST_TIMEOUT}"

# Bounds on what a run writes, so a loop on one suite's script error cannot fill
# /tmp. scripts/run_log_ceiling.py stands where `tee` stood and stops the engine
# past this many MB of output, or past this many repeats of one error at one
# place. tests/README.md says how the numbers were chosen.
DEFAULT_LOG_CEILING_MB=256
: "${SARA_TEST_LOG_CEILING_MB:=$DEFAULT_LOG_CEILING_MB}"
DEFAULT_REPEATED_ERRORS=10000
: "${SARA_TEST_REPEATED_ERRORS:=$DEFAULT_REPEATED_ERRORS}"

# The most resident memory in MiB the engine may reach, checked by run_all.gd
# after each suite. Passing it fails the run and names the suite. 0 for no limit.
DEFAULT_TEST_MEMORY_LIMIT_MB=8400
: "${SARA_TEST_MEMORY_LIMIT_MB:=$DEFAULT_TEST_MEMORY_LIMIT_MB}"
export SARA_TEST_MEMORY_LIMIT_MB

# Colour only when a terminal is going to render it. Piped output and CI logs get
# plain text, so escape codes never end up in a file someone greps later.
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    C_DIM=$'\033[38;5;242m'; C_OK=$'\033[38;5;114m'; C_ERR=$'\033[38;5;203m'
    C_WARN=$'\033[38;5;221m'; C_BRAND=$'\033[38;5;215m'; C_OFF=$'\033[0m'
else
    C_DIM=""; C_OK=""; C_ERR=""; C_WARN=""; C_BRAND=""; C_OFF=""
fi

fail() { printf '\n%s✗ %s%s\n\n' "$C_ERR" "$1" "$C_OFF"; rm -f "$LOG_FILE"; exit "${2:-1}"; }

# Windows has a script of its own, and this one is not made to run there. Under
# Git Bash it hangs with nothing printed: Git Bash has no `flock`, so the slot
# below fails every time and its loop sleeps for ever. Past that it would start
# the windowed `godot.exe`, whose output the pipe to `tee` never sees, move
# `XDG_DATA_HOME` and not `APPDATA`, so the engine would write into the
# painter's own folder, and its skeleton boot wants a weston. run_tests.ps1 does
# all of that for Windows, so this says so and stops, first of all and before
# anything is started, with the exit 2 a misuse gets.
case "$(uname -s 2>/dev/null || true)" in
    MINGW* | MSYS* | CYGWIN*)
        fail "run_tests.sh is for Linux. On Windows run: powershell -File run_tests.ps1" 2
        ;;
esac

# The submodule gitlink, before anything is launched.
#
# A checkout whose submodule is behind what the commit records is a red suite
# with 30-odd failures that name none of the cause: test_layer_locks failing to
# parse on a class the module declares, test_option_specs missing options,
# test_dynamics_provenance missing copyright lines. Finding it takes far longer
# than the repair of one line, so the run says it in a sentence instead.
#
# The check is a script of the repository's own, run in its gate
# mode, and it needs no network and no branch name. SARA_SKIP_GITLINK_CHECK=1
# turns it off for the case where the submodule is deliberately pinned back.
GITLINK_GUARD="$SCRIPT_DIR/../scripts/agents/gitlink_guard.py"
if [ -z "${SARA_SKIP_GITLINK_CHECK:-}" ] && [ -f "$GITLINK_GUARD" ] &&
    command -v git &> /dev/null && git -C "$SCRIPT_DIR" rev-parse --git-dir &> /dev/null; then
    if ! python "$GITLINK_GUARD" --check --repo "$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"; then
        fail "a submodule points backwards, so the suite below would be red for the wrong reason"
    fi
fi

# Determine Godot binary location (defaults to system godot in PATH or common installation paths)
if [ -n "$GODOT_BIN_OVERRIDE" ]; then
    GODOT_BIN="$GODOT_BIN_OVERRIDE"
elif [ -n "$GODOT_BIN" ]; then
    :
elif command -v godot &> /dev/null; then
    GODOT_BIN="godot"
elif command -v godot4 &> /dev/null; then
    GODOT_BIN="godot4"
else
    echo "Error: Godot executable not found in PATH."
    echo "Please ensure 'godot' or 'godot4' is in your PATH, or set the GODOT_BIN environment variable."
    exit 1
fi

# Offscreen mode. Godot cannot produce a RenderingDevice under --headless (4.7
# still hands back null from both get_rendering_device() and
# create_local_rendering_device()), so 19 of 28 suites are GPU suites that only a
# real display server can run. Without this the run maps a borderless fullscreen
# window over whatever the user is doing, which is unbearable when the gate runs
# in the background.
#
# A nested headless compositor gives a real Vulkan device with no window on any
# monitor, and several of them can run at once - so several runs can hold the gate
# simultaneously. weston is the one that ships on Fedora; cage and `sway
# --headless` work identically if you prefer them.
GODOT_WRAPPER=""
DISPLAY_ARGS=""
SETTINGS_DIR_ARGS=""
WESTON_PID=""
# An automated run never opens on the desktop, where the painter is often working.
# Claude Code sets CLAUDECODE in every shell it starts, so a run that forgets
# the variable still gets the nested compositor. SARA_TEST_ONSCREEN=1 keeps a
# window for a run that is asked to show one.
if [ -n "${CLAUDECODE:-}" ] && [ -z "${SARA_TEST_ONSCREEN:-}" ]; then
    SARA_TEST_OFFSCREEN=1
fi
if [ -n "${SARA_TEST_OFFSCREEN:-}" ]; then
    if ! command -v weston &> /dev/null; then
        echo "SARA_TEST_OFFSCREEN needs weston (dnf install weston)." >&2
        exit 1
    fi
    WL_SOCKET="sara-test-$$"
    # weston's own output is kept rather than thrown away. A loaded machine
    # takes the compositor down mid-suite, Godot aborts on the dead socket with
    # "Wayland client error code 32", and the one account of why weston left was
    # going to /dev/null. One file per run under the gate's scratch folder, and
    # the files of runs whose weston is gone are cleared as the next one starts,
    # so the folder holds the live runs and nothing older.
    WESTON_LOG_DIR="$PROJECT_PATH/scratch/xdg-gate"
    mkdir -p "$WESTON_LOG_DIR"
    for old in "$WESTON_LOG_DIR"/weston-*.log; do
        [ -e "$old" ] || continue
        old_pid="${old##*/weston-}"
        old_pid="${old_pid%.log}"
        kill -0 "$old_pid" 2>/dev/null || rm -f "$old"
    done
    WESTON_LOG="$WESTON_LOG_DIR/weston-$$.log"
    # A function because a run can need a second compositor: the wake below
    # stops the first one to free an engine hung on exit, and a retry after it
    # needs a socket to draw on. The stale socket file is removed first, or the
    # wait would see it and go on before the new weston is listening.
    start_compositor() {
        rm -f "${XDG_RUNTIME_DIR}/${WL_SOCKET}"
        weston --backend=headless --renderer="${SARA_WESTON_RENDERER:-gl}" --width=1920 --height=1080 --socket="$WL_SOCKET" --idle-time=0 >>"$WESTON_LOG" 2>&1 9>&- &
        WESTON_PID=$!
        for _ in $(seq 1 40); do
            [ -S "${XDG_RUNTIME_DIR}/${WL_SOCKET}" ] && break
            sleep 0.25
        done
        if [ ! -S "${XDG_RUNTIME_DIR}/${WL_SOCKET}" ]; then
            echo "Offscreen compositor never came up." >&2
            kill "$WESTON_PID" 2>/dev/null
            exit 1
        fi
    }
    start_compositor
    # `|| true` because this script runs under `set -e` and the trap runs on the
    # way out of `exit 0`. A weston that has already died, which is what a
    # loaded machine does to it, makes the kill fail, and a failing command in
    # an EXIT trap under `set -e` replaces the status the script chose with 1.
    # The run then prints ALL TESTS PASSED, prints the skeleton boot line, and
    # exits 1 with nothing said, which is the one failure the gate's own rule
    # about reading the exit code cannot be told apart from a real one.
    trap 'kill "$WESTON_PID" 2>/dev/null || true' EXIT
    export WAYLAND_DISPLAY="$WL_SOCKET"
    DISPLAY_ARGS="--display-driver wayland"
fi

# Godot's user:// is $XDG_DATA_HOME/godot/app_userdata/Sara, which is one
# directory for every checkout of this repository and for the user's own
# installed copy. Two gates in two worktrees then write the same settings
# file and the same SPIR-V cache at once, and test_docker_layout_scaling
# deletes docker_layout.cfg there, which is the user's real layout. So a run
# gets a user directory of its own, per checkout, under the gitignored
# scratch/.
#
# **The desktop run too.** A desktop run gets a directory of its own as well,
# because a suite has no business in the painter's own folder, windowed or not:
# one that kept the real one left a dozen `test_*` entries beside their colours
# and their recovery copies. The two runs get a directory each, `xdg-gate` and
# `xdg-desktop`, so a desktop run in the same checkout never hands the gate a
# profile it wrote.
#
# **scratch/xdg-gate, not scratch/xdg**. The captures own the third one, and if
# they shared it a scenario that wrote a layout preset, a UI scale and a top bar
# order into the profile would send the next gate red in files nobody had opened,
# every one of them a test asserting what a *default* profile holds. A suite that
# asserts a default is entitled to a default, so the two get a directory each
# rather than the suite getting a deletion it would have to remember.
# user:// is split with it, not only the settings: `user://brush_presets`
# is written by the brush editor and read by the preset suites, and it is
# the same trap one directory over. The SPIR-V cache is under user:// too,
# so the first gate in a fresh directory compiles cold and costs about two
# seconds more, once.
ISOLATION_DIR="$PROJECT_PATH/scratch/xdg-gate"
if [ -z "$WESTON_PID" ]; then
    ISOLATION_DIR="$PROJECT_PATH/scratch/xdg-desktop"
fi
export XDG_DATA_HOME="$ISOLATION_DIR/data"
mkdir -p "$XDG_DATA_HOME"
# The settings file and the docker layout live wherever get_settings_dir()
# resolves to, so the same isolation has to cover it, or a test that flips
# a setting rewrites the person's real ~/.config/sara
# --settings-dir is the flag
# form of the isolation this used to reach through XDG_CONFIG_HOME, and
# it also moves the data root with it, so what the app itself writes
# lands under `$SETTINGS_DIR/data` on every platform, Windows included. The
# engine's own folder is not Sara's to move, and the flag leaves it where it is
# Here XDG_DATA_HOME above moves it, and on Windows
# run_tests.ps1 moves it with APPDATA.
SETTINGS_DIR="$ISOLATION_DIR/config/sara"
mkdir -p "$SETTINGS_DIR"
SETTINGS_DIR_ARGS="--settings-dir=$SETTINGS_DIR"

# The engine's own log goes to a scratch folder of the gate's, in both modes.
# Godot keeps ten logs in user://logs and every run writes
# one, so ten gates on the desktop rotated away the log a painter's freeze left.
# --log-file moves it and tells the app nothing, so SARA_LOG_FILE names the same
# file for SaTrail.log_path(), which the suites that read their own log ask.
ENGINE_LOG_DIR="$PROJECT_PATH/scratch/logs/gate"
mkdir -p "$ENGINE_LOG_DIR"
export SARA_LOG_FILE="$ENGINE_LOG_DIR/godot.log"
# The display profile follows the system's profile for the monitor by default,
# and a suite is the same on every machine, so the system is one with none.
export SARA_SYSTEM_PROFILE="${SARA_SYSTEM_PROFILE:-none}"

printf '\n  %sSara%s %stest suite%s\n' "$C_BRAND" "$C_OFF" "$C_DIM" "$C_OFF"
printf '  %sgodot%s   %s\n' "$C_DIM" "$C_OFF" "$GODOT_BIN"
printf '  %stimeout%s %ss\n' "$C_DIM" "$C_OFF" "$SARA_TEST_TIMEOUT"
printf '  %smemory%s  %s MiB at most\n' "$C_DIM" "$C_OFF" "$SARA_TEST_MEMORY_LIMIT_MB"
if [ -n "$WESTON_PID" ]; then
    printf '  %soffscreen%s nested weston, no window on any monitor\n' "$C_DIM" "$C_OFF"
fi
if [ -n "${1:-}" ]; then
    printf '  %sfilter%s  %s\n' "$C_DIM" "$C_OFF" "$*"
fi

# A `class_name` added since an editor last looked is not in
# .godot/global_script_class_cache.cfg, and a suite that uses it fails to parse.
# The run then times out before any test starts, which reads as a hang, and
# the rescan would otherwise have to be run by hand before each gate.
# The rescan takes four seconds and rewrites the cache's mtime even when nothing
# changed, so one script newer than the cache is the whole test. A tree with no
# .godot/ at all, a fresh checkout or a worktree, takes the same pass: the editor
# imports what it finds before it quits, in about a minute, and the fonts and
# icons come out right. `--import` on its own does not: it can
# segfault in a bare worktree after the fonts, and UI suites go red.
#
# A picture is the same, read through its import under .godot/imported, which
# only the editor writes. A picture and its `.import` merged with no script
# beside them would run no pass, and the next whole run would fail suites on a
# picture that "does not load". So a `.import` newer than the cache counts too,
# and so does a file with one beside it, which is a picture replaced in the tree.
#
# Godot loads a GDExtension once .godot/extension_list.cfg names it, and 4.7.2
# corrupts its memory importing a fresh tree with the JPEG XL module loaded:
# with no list, the scan that finds the module segfaulted in the reimport, and
# with the list written first, five first imports of six crashed. So a
# first import holds the module's .gdextension under another name, which the
# scan passes over and a deleted .godot does not take with it, and a second
# pass lists it and loads it over the imported tree, as packaging/build.sh's
# list does, which went cleanly twelve times of twelve. The threaded reimport
# raced without the module too, eight crashes or hangs in thirty fresh gates
# against none in twenty with editor/import/use_multiple_threads off in
# project.godot. The first import is still tried twice, a pass is killed
# after five minutes where one takes under one, and a pass that fails ends
# the run with its last lines. The TIFF reader's LZW library of the base
# modules is held and listed the same way, beside the JPEG XL one.
CLASS_CACHE="$PROJECT_PATH/.godot/global_script_class_cache.cfg"
EXTENSIONS=(modules/sara-jxl/sara_jxl.gdextension modules/sara-base-modules/tiff-lzw/sara_tiff_lzw.gdextension)
hold_extensions() {
    local extension
    for extension in "${EXTENSIONS[@]}"; do
        [ -f "$PROJECT_PATH/$extension" ] && mv "$PROJECT_PATH/$extension" "$PROJECT_PATH/$extension.held"
    done
    return 0
}
release_extensions() {
    local extension
    for extension in "${EXTENSIONS[@]}"; do
        [ -f "$PROJECT_PATH/$extension.held" ] && mv "$PROJECT_PATH/$extension.held" "$PROJECT_PATH/$extension"
    done
    return 0
}
editor_pass() {
    local log status=0
    log="$(mktemp /tmp/sara_import_XXXXXX.log)"
    timeout -k 10 "${SARA_IMPORT_TIMEOUT:-300}" "$GODOT_BIN" --headless $SETTINGS_DIR_ARGS --path "$PROJECT_PATH" --editor --quit >"$log" 2>&1 || status=$?
    [ "$status" != 124 ] || echo "the editor pass stopped answering and was killed after ${SARA_IMPORT_TIMEOUT:-300} seconds" >>"$log"
    [ "$status" = 0 ] || sed 's/\x1b\[[0-9;]*m//g' "$log" | grep -v '^\[ *[0-9]*% \]' | tail -15
    rm -f "$log"
    return "$status"
}
release_extensions
if [ ! -f "$CLASS_CACHE" ]; then
    printf '  %simport%s  no class cache yet, letting the editor import the tree\n' "$C_DIM" "$C_OFF"
    mkdir -p "$PROJECT_PATH/.godot"
    hold_extensions
    IMPORT_STATUS=0
    editor_pass || { printf '  %simport%s  exited with status %s, trying once more\n' "$C_DIM" "$C_OFF" "$?"; editor_pass; } || IMPORT_STATUS=$?
    release_extensions
    [ "$IMPORT_STATUS" = 0 ] || fail "The first import of the tree exited with status $IMPORT_STATUS, its last lines are above."
else
    STALE="$(find "$PROJECT_PATH" \( -name .godot -o -name scratch -o -name .conda -o -name build \) -prune -o \
        -type f -newer "$CLASS_CACHE" \( -name '*.gd' -o -name '*.import' -o -exec sh -c 'test -f "$1.import"' sh {} \; \) \
        -print -quit)"
    if [ -n "$STALE" ]; then
        printf '  %srescan%s  %s is newer than the class cache, letting the editor look\n' "$C_DIM" "$C_OFF" "${STALE#"$PROJECT_PATH"/}"
        "$GODOT_BIN" --headless $SETTINGS_DIR_ARGS --path "$PROJECT_PATH" --editor --quit >/dev/null 2>&1 || true
    fi
fi
EXTENSION_NAMES=("JPEG XL module" "TIFF LZW module")
LISTED=""
for at in "${!EXTENSIONS[@]}"; do
    extension="${EXTENSIONS[$at]}"
    if [ -f "$PROJECT_PATH/$extension" ] && ! grep -qs "res://$extension" "$PROJECT_PATH/.godot/extension_list.cfg"; then
        echo "res://$extension" >> "$PROJECT_PATH/.godot/extension_list.cfg"
        LISTED="${LISTED:+$LISTED and }the ${EXTENSION_NAMES[$at]}"
    fi
done
if [ -n "$LISTED" ]; then
    printf '  %simport%s  loading %s over the imported tree\n' "$C_DIM" "$C_OFF" "$LISTED"
    editor_pass || fail "The editor pass that loads $LISTED exited with status $?, its last lines are above."
fi

# Note: We run without --headless because Godot 4's headless mode defaults to the Dummy
# rendering driver where RenderingDevice is null, which is incompatible with compute shaders.
# One machine, one GPU, and every concurrent run gates on it.
# Many runs at once can put eighteen Godot processes on an 8 GB card and a 15 GB
# machine, and the driver answers allocations with NV_ERR_NO_MEMORY, which reads
# as a red gate for a change that was fine. So a gate takes one of
# SARA_GATE_SLOTS slots (three by default) in a directory every run shares, and
# waits for one when all are taken. The slot is a flock on a file, released when
# this script exits, so a killed run frees it too. scripts/sara_shot.py takes the
# same slots for a capture.
#
# **A slot is inherited, not taken twice**. This script holds its slot to
# the end and then runs scripts/check_skeleton_boots.py, which runs
# scripts/sara_shot.py. A gate that needs two slots and takes them one at a time
# is a deadlock waiting for enough company: with the default of three, three
# concurrent gates reaching the skeleton boot together hold all three and each
# waits for a fourth, and `SARA_GATE_SLOTS=1 ./run_tests.sh` would hang in the
# skeleton boot on its own.
#
# So the slot is exported and sara_shot.py takes none when it sees it. That is
# safe rather than a loophole: the whole point of the cap is the number of Godots
# on the card at once, and this script runs one at a time, the suite and then the
# skeleton boot, never both.
#
# **A priority holder has a slot of its own.** A run that holds a merge lock
# would otherwise queue behind three whole runs while everything else waits on
# it. SARA_GATE_PRIORITY gives it slot 0, and only one run holds that, so the
# extra slot adds one Godot to the card at most.
#
# **The slot stays in this script.** Descriptor 9 is inherited by every
# child bash starts, and the lock lives while any process holds it, so a child
# that outlives the run holds the slot after the run has ended, for instance a
# pen reader's `cat` started by a Godot this script started. Bash cannot
# mark a descriptor close-on-exec, so every child started once the slot is
# held, the Godot, the compositor, the wake and the skeleton boot, is started
# with `9>&-`. The variable below says a slot is held, the descriptor never.
gate_slot() {
    local dir="${SARA_GATE_LOCK_DIR:-/tmp/sara-gate}" n="${SARA_GATE_SLOTS:-3}" i waited=0 first=1
    mkdir -p "$dir"
    [ "${SARA_GATE_PRIORITY:-}" = 1 ] && first=0
    while :; do
        for ((i = first; i <= n; i++)); do
            if [ "$i" = 0 ]; then exec 9>"$dir/slot-holder"; else exec 9>"$dir/slot-$i"; fi
            if flock -n 9; then
                [ "$waited" -gt 0 ] && printf '  %sgate slot %s after %ss%s\n' "$C_DIM" "$i" "$waited" "$C_OFF"
                # Exported where it is taken, so the variable is true exactly
                # when a slot is held and never a moment before.
                export SARA_GATE_SLOT_HELD=1
                return 0
            fi
        done
        sleep 5
        waited=$((waited + 5))
    done
}

# The wake, for the Wayland teardown race described under the first run below.
#
# The engine hangs after the result is printed, with its main thread joining the
# "Wayland Events" thread, which sits in poll() on the compositor's socket and
# is never woken. Stopping the compositor closes that socket, poll() returns,
# the join completes and the engine finishes its own shutdown, leak report
# included. Measured: every hung run exited 0.4s after its weston
# was stopped, and a probe suite leaking one object printed its leak warning on
# the woken runs exactly as on the clean ones.
#
# A hang is told from a slow exit by CPU time, not by the clock. Healthy exits
# took 0.12 to 0.22s after the result, but a machine carrying several runs
# can stretch that, and an engine still shutting down is still spending CPU.
# One that has spent none for SARA_TEST_EXIT_GRACE seconds (two by default) is
# parked, so a loaded machine delays the wake instead of provoking a false one.
WAKE_MARK="$LOG_FILE.woke"
CEILING_MARK="$LOG_FILE.ceiling"
cpu_ticks() { sed 's/.*) //' "/proc/$1/stat" 2>/dev/null | awk '{print $12 + $13}'; }
wake_on_hang() {
    local grace="${SARA_TEST_EXIT_GRACE:-2}" watch engine="" cpu last="" idle=0
    until suite_finished || summary_printed; do sleep 0.25; done
    # The engine is the child of the `timeout` this script started.
    watch=$(pgrep -P $$ -x timeout | head -1)
    [ -n "$watch" ] && engine=$(pgrep -P "$watch" | head -1)
    [ -n "$engine" ] || return 0
    while kill -0 "$engine" 2>/dev/null; do
        cpu=$(cpu_ticks "$engine")
        if [ -n "$cpu" ] && [ "$cpu" = "$last" ]; then idle=$((idle + 1)); else idle=0; fi
        last=$cpu
        if [ "$idle" -ge $((grace * 2)) ]; then
            : >"$WAKE_MARK"
            kill "$WESTON_PID" 2>/dev/null
            return 0
        fi
        sleep 0.5
    done
}

run_once() {
    set +e
    local started=$SECONDS watcher=""
    WOKEN=""
    # A compositor stopped by the wake, or lost on its own, is replaced before
    # the next attempt, which would otherwise die on a dead socket.
    if [ -n "$WESTON_PID" ] && ! kill -0 "$WESTON_PID" 2>/dev/null; then
        start_compositor
    fi
    if [ -n "$WESTON_PID" ]; then
        wake_on_hang >/dev/null 2>&1 9>&- &
        watcher=$!
    fi
    # --foreground so the timeout applies to this pipeline rather than a detached
    # process group; -k sends KILL if Godot ignores the first TERM.
    timeout --foreground -k 10 "$SARA_TEST_TIMEOUT" \
        $GODOT_WRAPPER "$GODOT_BIN" --no-header --log-file "$SARA_LOG_FILE" $DISPLAY_ARGS $SETTINGS_DIR_ARGS --path "$PROJECT_PATH" res://tests/run_all.tscn ${1:+--} "$@" 9>&- 2>&1 |
        python "$PROJECT_PATH/scripts/run_log_ceiling.py" "$LOG_FILE" "$CEILING_MARK" $$ \
            "$SARA_TEST_LOG_CEILING_MB" "$SARA_TEST_REPEATED_ERRORS" 9>&-
    EXIT_CODE=${PIPESTATUS[0]}
    # How long the watched command actually ran, which is what tells a kill at
    # the limit from a death that happens to share its code. Only the watched
    # command: the wait for a gate slot is before this and is not the watchdog's.
    RUN_SECONDS=$((SECONDS - started))
    if [ -n "$watcher" ]; then
        kill "$watcher" 2>/dev/null
        wait "$watcher" 2>/dev/null
    fi
    if [ -e "$WAKE_MARK" ]; then
        rm -f "$WAKE_MARK"
        WOKEN=1
        printf '\n%s⚠ The suite printed its result, then the engine hung on exit.%s\n' "$C_WARN" "$C_OFF"
        printf '%s  Known Wayland teardown race, not a test failure. It spent no CPU for %ss,\n' "$C_DIM" "${SARA_TEST_EXIT_GRACE:-2}"
        printf '  so the compositor was stopped to wake it, and it finished its own shutdown.%s\n\n' "$C_OFF"
    fi
    set -e
    # A run the ceiling stopped is a failure whatever else its log holds, and no
    # retry or rerun below may start it again, so it ends here.
    if [ -e "$CEILING_MARK" ]; then
        printf '\n%s✗ %s%s\n' "$C_ERR" "$(cat "$CEILING_MARK")" "$C_OFF"
        printf '%s  The log is %s bytes, its first lines say where the run began to repeat.%s\n' \
            "$C_DIM" "$(wc -c <"$LOG_FILE")" "$C_OFF"
        rm -f "$CEILING_MARK"
        where_to_look
        exit 1
    fi
}

# The three codes a watched run comes back on when it was killed rather than
# finished, and this used to read two of them.
#
# coreutils hands back 124 when it kills the child on its own clock, and 137
# when the child sat through that TERM and the -k KILL was the one that landed.
# The third is the whole pipeline being signalled from outside: --foreground
# deliberately leaves `timeout` in this terminal's own process group, so a TERM
# to the group reaches `timeout` itself and the shell reports 128+15, which is
# 143. An unattended run can come back 143, and a guard that only knew 124 and
# 137 would fall past it and print "Test run failed (exit code
# 143)" and nothing else, while the branch below already held the sentence that
# reader needed.
#
# The elapsed check is what keeps the branch honest. A run that dies of one of
# these codes a second in was not killed by a clock it never reached, so it goes
# to the generic tail and gets the log rather than advice about a limit. The
# slack of one second is for SECONDS rounding down against a kill on the mark.
timed_out() {
    case "$EXIT_CODE" in
        124 | 137 | 143) [ "$RUN_SECONDS" -ge "$((SARA_TEST_TIMEOUT - 1))" ] ;;
        *) return 1 ;;
    esac
}
suite_finished() { grep -qE "ALL TESTS PASSED|FILTERED RUN PASSED" "$LOG_FILE"; }
# Whether run_all.gd got as far as its totals, which it prints on a pass and on a
# failure alike. `suite_finished` reads the success marker, and a run with
# a failure never prints one, so on its own it cannot tell a run that stopped
# early from one that ran every suite, reported failures and then hung on exit.
summary_printed() { sed 's/\x1b\[[0-9;]*m//g' "$LOG_FILE" | grep -qE '[0-9]+ suites +[0-9]+ assertions'; }

# Whatever killed a run, the log holds three things the reader needs and the
# script would otherwise delete along with it: the last suite that reported, whether the
# success marker is there, and where the log is. A run that stops after one suite and says only "exit code 1",
# with the runs either side of it green, tells the reader a number and gives
# nowhere to look.
# True when this run started an offscreen compositor and it is no longer there.
# The trap has not fired yet wherever this is asked, so a weston that is gone
# went on its own or was taken by something else. The one exception is the
# wake, which stops it on purpose after the result and says so itself.
compositor_died() {
    [ -n "$WESTON_PID" ] && [ -z "$WOKEN" ] && ! kill -0 "$WESTON_PID" 2>/dev/null
}

where_to_look() {
    local last reported
    last=$(sed 's/\x1b\[[0-9;]*m//g' "$LOG_FILE" |
        grep -oE '^ +[✓✗] +[A-Za-z0-9_]+ +[0-9]+ asrt' | tail -1 | awk '{print $2}')
    # A compositor that left mid-run is the machine rather than the tree, and it
    # comes first because it explains everything under it. Godot's own line for
    # it is "Wayland client error code 32", EPIPE on the dead socket, and the
    # exit is usually 134 at whichever suite happened to be drawing.
    if compositor_died; then
        reported=$(sed 's/\x1b\[[0-9;]*m//g' "$LOG_FILE" | grep -cE '^ +[✓✗] +[A-Za-z0-9_]+ +[0-9]+ asrt' || true)
        printf '%s  the offscreen compositor died after %s suites, so this is the machine and not the tree\n' "$C_DIM" "$reported"
        printf '  its own log is kept at %s\n' "$WESTON_LOG"
    fi
    printf '%s  last suite to report  %s\n' "$C_DIM" "${last:-none, the run died before the first}"
    if suite_finished; then
        printf '  the success marker is in the log, so every suite did run\n'
    elif summary_printed; then
        printf '  the summary is in the log, so every suite ran and the failures above are the result\n'
    else
        printf '  no success marker, so the run stopped before the end\n'
    fi
    printf '  the log is kept at %s%s\n\n' "$LOG_FILE" "$C_OFF"
}

gate_slot
run_once "$@"

# Two different failures share exit 124, and only the log tells them apart.
#
# The one the watchdog is for is a run that never got to the end: run_all.gd
# failed to parse, or a test added a Window to the tree and blocked. The success
# marker is absent, because nothing reached the line that prints it.
#
# The other is Godot's Wayland driver failing to shut down. Every suite has run
# and the result is printed, then the main thread blocks forever in
# pthread_join on the "Wayland Events" thread, which is parked in poll() and
# never wakes. Measured at 7 hangs in 65 offscreen runs under nested weston,
# and 0 in 56 on a real compositor, so it is the nested one that provokes it.
# Each cost the whole limit, six minutes a run, before the wake above. Offscreen, the wake now frees it within about two
# seconds of the result, so the watchdog and the retry here are the fallback
# for a hang the wake could not reach.
#
# Retry rather than accept, because a process killed mid-shutdown never prints
# the leak report the checks below read - accepting it would trade a false red
# for a blind spot in the one check that has caught a real leak here. Two
# consecutive hangs are not this flake, so the retries are bounded and each one
# says so out loud.
RETRIES=0
while timed_out && suite_finished && [ "$RETRIES" -lt 2 ]; do
    RETRIES=$((RETRIES + 1))
    printf '\n%s⚠ The suite finished and printed its result, then the engine hung on exit.%s\n' "$C_WARN" "$C_OFF"
    printf '%s  Known Wayland teardown race, not a test failure. Retrying (%s of 2), because\n' "$C_DIM" "$RETRIES"
    printf '  only a process that exits reports whether anything leaked.%s\n\n' "$C_OFF"
    run_once "$@"
done

# A known flake is a test that has failed once and passed on the next run, with
# nothing changed. Its name is in tests/flakes.txt, one per line. When every
# failed test of a run is on that list, the run is repeated once and the second
# result counts, said out loud so the flake stays visible. One unknown failure
# among them and there is no rerun: a new failure is a failure. The list is
# kept short on purpose, a flake that stops flaking leaves it, and one that
# keeps flaking is a bug with a name.
FLAKED=""
flaky_only() {
    local list="$PROJECT_PATH/tests/flakes.txt" names n
    [ -f "$list" ] || return 1
    names=$(sed 's/\x1b\[[0-9;]*m//g' "$LOG_FILE" | grep -oE '\[FAIL\] [A-Za-z0-9_]+' | awk '{print $2}' | sort -u)
    [ -n "$names" ] || return 1
    for n in $names; do
        grep -qxF "$n" "$list" || return 1
    done
    FLAKED=$(printf '%s ' $names)
    return 0
}

if ! timed_out && ! suite_finished && flaky_only; then
    printf '\n%s⚠ Only known flakes failed: %s%s\n' "$C_WARN" "$FLAKED" "$C_OFF"
    printf '%s  Listed in tests/flakes.txt. Rerunning once, and the second run counts.%s\n\n' "$C_DIM" "$C_OFF"
    run_once "$@"
    if suite_finished; then
        printf '\n%s⚠ FLAKED: %s(passed on the rerun)%s\n' "$C_WARN" "$FLAKED" "$C_OFF"
    fi
fi

if timed_out; then
    if suite_finished; then
        printf '\n%s✗ The engine hung on exit %s times running, after the suite passed.%s\n' "$C_ERR" "$((RETRIES + 1))" "$C_OFF"
        printf '%s  Every assertion ran, so this is not a test failure - but the run never\n' "$C_DIM"
        printf '  reported whether it leaked, so it is not a pass either. That many hangs in\n'
        printf '  a row is more than the known Wayland teardown race.%s\n\n' "$C_OFF"
        where_to_look
    elif summary_printed; then
        # Every suite ran and reported, some failed, and then the engine hung
        # on exit. The advice below is for a run that never got to the end, and it
        # pointed a reader away from the failures the log already names. The
        # failures are the result, so they are what the exit code says.
        failed_line=$(sed 's/\x1b\[[0-9;]*m//g' "$LOG_FILE" | grep -oE '[0-9]+ suite\(s\) failed:.*' | tail -1)
        printf '\n%s✗ %s%s\n' "$C_ERR" "${failed_line:-The suite reported failures.}" "$C_OFF"
        printf '%s  Then the engine hung on exit and the watchdog stopped it after %ss. Every\n' "$C_DIM" "$RUN_SECONDS"
        printf '  suite had already run and reported, so this is a test failure and not a\n'
        printf '  run that stopped early: read the failures above.%s\n\n' "$C_OFF"
        where_to_look
        exit 1
    else
        # The advice is twice the default, so it moves with the number it doubles.
        # A run that already had twice the default is likelier hung than slow,
        # and is not told to wait longer.
        suggested=$((DEFAULT_TEST_TIMEOUT * 2))
        printf '\n%s✗ Killed after %ss of a %ss limit, exit code %s.%s\n' \
            "$C_ERR" "$RUN_SECONDS" "$SARA_TEST_TIMEOUT" "$EXIT_CODE" "$C_OFF"
        printf '%s  Usual causes: run_all.gd failed to parse, or a test added a Window\n' "$C_DIM"
        if [ "$SARA_TEST_TIMEOUT" -lt "$suggested" ]; then
            printf '  to the scene tree, which maps a real OS window and blocks. Under several\n'
            printf '  runs sharing one card it is usually neither, and the limit is short.\n'
        else
            printf '  to the scene tree, which maps a real OS window and blocks. The limit was\n'
            printf '  already twice the default, so read the log before raising it again.\n'
        fi
        if [ "$EXIT_CODE" -eq 143 ]; then
            printf '  143 is a TERM to this process group rather than the watchdog firing, so\n'
            printf '  a supervisor taking the run down reads the same as a run out of time.\n'
        fi
        if [ "$SARA_TEST_TIMEOUT" -lt "$suggested" ]; then
            printf '  Raise the limit with SARA_TEST_TIMEOUT=%s ./run_tests.sh\n' "$suggested"
        fi
        printf '%s\n' "$C_OFF"
        where_to_look
    fi
    # One code whatever the kill was, so a caller reads the outcome rather than
    # which of the three signals happened to land.
    exit 124
fi

# Every script error in the log once, with how often it came: what it said,
# where, and the test that reached it, which is the backtrace's first `test_`
# frame. A run can hold more than one, and the one a reader already expects
# hides the rest: a script error read as the parse error in a new suite would
# let three null `get_tree()` calls from two other suites merge unseen. The
# refusal line stays the last `✗ ` line, which other scripts read.
script_errors() {
    sed 's/\x1b\[[0-9;]*m//g' "$LOG_FILE" | awk '
        function keep() {
            if (said == "") return
            key = said "\nat " at (from == "" ? "" : ", from " from)
            if (!(key in seen)) order[++n] = key
            seen[key]++
            said = ""
        }
        /^SCRIPT ERROR: / { keep(); said = substr($0, 15); at = "?"; from = ""; next }
        said != "" && /^ +at: / { at = $0; sub(/^ +at: /, "", at); next }
        said != "" && from == "" && /^ +\[[0-9]+\] test_/ { from = $0; sub(/^ +\[[0-9]+\] /, "", from); next }
        said != "" && /^ / { next }
        { keep() }
        END {
            keep()
            for (i = 1; i <= n && i <= 8; i++) {
                split(order[i], part, "\n")
                printf "  %s%s\n      %s\n", part[1], (seen[order[i]] > 1 ? "  (" seen[order[i]] " times)" : ""), part[2]
            }
            if (n > 8) printf "  and %d more, all in the log\n", n - 8
        }'
}

# A test assertion is not enough: engine script errors mean a suite did not
# actually exercise the intended contract. Keep the expected renderer teardown
# warning separate until every test-owned scene has deterministic cleanup.
if grep -q "SCRIPT ERROR:" "$LOG_FILE"; then
    printf '\n%s✗ Godot reported a script error - a suite did not exercise what it claims.%s\n' "$C_ERR" "$C_OFF"
    printf '%s' "$C_DIM"
    script_errors
    printf '  the log is kept at %s%s\n\n' "$LOG_FILE" "$C_OFF"
    exit 1
fi

# Godot words a single leak in the singular, "1 ObjectDB instance was leaked at
# exit", and the plural-only pattern here let exactly one leaked object through
# the gate green.
if grep -Eq "(RIDs? of type .* leaked|RID allocations of type .* leaked|ObjectDB instances? (was|were) leaked|resources? still in use at exit)" "$LOG_FILE"; then
    fail "Renderer or object resources leaked - something was not freed."
fi

# The first frame of a script of Sara's in the crash report, or nothing. Godot
# 4.7's handler prints "handle_crash: Program crashed with signal N", the C++
# frames, then "GDScript backtrace (most recent call first):" and lines like
# "    [0] go (res://m.gd:8)" up to "-- END OF GDSCRIPT BACKTRACE --", and leaves
# that block out when no script was running. An ERROR above the handler carries
# a backtrace of its own, so only what follows the handler's line is read.
crash_script_frame() {
    sed 's/\x1b\[[0-9;]*m//g' "$LOG_FILE" | awk '
        /handle_crash: Program crashed with signal/ { crashed = 1; next }
        !crashed { next }
        /^GDScript backtrace/ { inside = 1; next }
        /^-- END OF GDSCRIPT BACKTRACE/ { inside = 0; next }
        (inside && /^ *\[[0-9]+\] /) || /\(res:\/\/[^ )]*\.gd:[0-9]+\)/ {
            sub(/^ *\[[0-9]+\] /, ""); print; exit
        }'
}

# A pass line is the result once script errors and leaks are rejected above,
# and the exit code after it is read rather than ignored. Godot's teardown
# can crash on its own after a passing suite, which is the engine's and stays
# forgiven, said in a line with the log kept. A crash whose report names a
# script of Sara's is a PREDELETE or a handler of ours, which no marker excuses.
if [ "$EXIT_CODE" -ne 0 ] && suite_finished; then
    frame=$(crash_script_frame)
    if [ -n "$frame" ]; then
        printf '\n%s✗ The suites passed, then the engine crashed at exit (exit code %s) inside a script of Sara'"'"'s.%s\n' \
            "$C_ERR" "$EXIT_CODE" "$C_OFF"
        printf '%s  first script frame    %s%s\n' "$C_DIM" "$frame" "$C_OFF"
        where_to_look
        exit 1
    fi
    if grep -q "handle_crash: Program crashed" "$LOG_FILE"; then
        printf '\n%s⚠ The engine crashed at exit (exit code %s) after the suites passed, in engine frames only, so the run stands, and the log is kept at %s%s\n' \
            "$C_WARN" "$EXIT_CODE" "$LOG_FILE" "$C_OFF"
    else
        printf '\n%s⚠ The engine exited with code %s after the suites passed and left no crash report, so the run stands, and the log is kept at %s%s\n' \
            "$C_WARN" "$EXIT_CODE" "$LOG_FILE" "$C_OFF"
    fi
fi

if [ $EXIT_CODE -eq 0 ] || suite_finished; then
    [ "$EXIT_CODE" -ne 0 ] || rm -f "$LOG_FILE"
    # The skeleton boots with no module to load: one launch of
    # the resting-app scenario against an empty modules root, read back from
    # its artefacts. On a full run only, because a filtered run is a person
    # chasing one suite, and this is a minute of compositor and GPU. It runs
    # after the suite rather than in it because the suite is one process and
    # the claim is about a launch.
    if [ $# -eq 0 ] && [ -z "${SARA_SKIP_BOOT_CHECK:-}" ]; then
        printf '\n%sSkeleton without modules%s  scripts/check_skeleton_boots.py\n' "$C_BRAND" "$C_OFF"
        if ! python "$PROJECT_PATH/scripts/check_skeleton_boots.py" 9>&-; then
            fail "The skeleton did not boot with no module to load."
        fi
        # And with every module, through a scenario that opens the one search:
        # an abort at teardown or a leak at exit fails it.
        printf '\n%sScenario exit%s  scripts/check_scenario_exit.py\n' "$C_BRAND" "$C_OFF"
        if ! python "$PROJECT_PATH/scripts/check_scenario_exit.py" 9>&-; then
            fail "A scenario run aborted at exit or leaked an object."
        fi
    fi
    exit 0
fi

# A run that failed assertions has already said so: the failures print under
# their suite and run_all.gd ends on "N suite(s) failed", so that reader is
# reading a test failure and needs nothing added under it.
if grep -q "suite(s) failed" "$LOG_FILE"; then
    fail "Test run failed (exit code $EXIT_CODE)." "$EXIT_CODE"
fi

# Nothing else, then: not a timeout, not a script error, not a leak, no success
# marker and no suite that owned up. The run died on its own, the exit code is
# all the script knows, and it is not all the log knows, so the log is named and
# kept rather than deleted under the reader.
printf '\n%s✗ Test run failed (exit code %s), and no suite reported a failure.%s\n' \
    "$C_ERR" "$EXIT_CODE" "$C_OFF"
where_to_look
exit "$EXIT_CODE"
