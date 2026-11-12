#!/usr/bin/env bash
#
# Launch wrapper. Installed alongside the binary.
#
# Filters the two GNOME warnings Sara can do nothing about so a launch from a
# terminal looks clean. The build itself prefers native Wayland, the project's
# display_server/driver.linuxbsd, because XWayland cannot report a display
# scale and the UI then has to guess it from DPI, and Godot falls back to X11
# by itself where no Wayland compositor answers.
set -euo pipefail
HERE="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")" && pwd)"

# --no-header suppresses Godot's own two startup lines (engine version, then
# rendering driver and device). Nothing is lost: the boot banner reports the
# driver, API version, rendering method, adapter and engine build hash itself,
# and does it without printing before the app has said hello.
DRIVER_ARGS=(--no-header)

# `--version` asks which Sara this is, and a window would be the wrong answer to
# that. Godot opens its window before the first autoload runs, so the app cannot
# keep it from appearing alone: --headless does, and opens no window. The
# app prints the line and quits when it finds the flag in its own arguments.
HEADLESS=0
for arg in "$@"; do
    if [ "$arg" = "--version" ]; then HEADLESS=1; fi
done
# A file opened while the painter's Sara runs goes to that Sara as a tab, and
# the window this start would map must never appear, for the same reason as
# above. So when the lock in Sara's user folder names a live process and a file
# was given, a windowless run asks the app to hand the files over first, and
# its status 0 means they went. Any other status starts Sara as before, and the
# app decides again there, so a lock this reads wrongly costs one short run.
# `--settings-dir`, the door's own socket or port file and a capture run never
# hand over, which the app's own check says too.
hand_over_lock() {
    local lock="${XDG_DATA_HOME:-$HOME/.local/share}/godot/app_userdata/Sara/running.json"
    local pid=""
    local wants_a_file=0
    for arg in "$@"; do
        case "$arg" in
            --settings-dir=*|--capture|--capture=*|--agent-socket=*|--agent-port-file=*|--version) return 1 ;;
            -*|"") ;;
            *) wants_a_file=1 ;;
        esac
    done
    [ "$wants_a_file" = 1 ] && [ -f "$lock" ] || return 1
    pid="$(grep -o '"pid":[0-9]*' "$lock" | cut -d: -f2 || true)"
    [ -n "$pid" ] && [ -d "/proc/$pid" ]
}
if hand_over_lock "$@"; then
    "$HERE/sara.x86_64" --no-header --headless -- --hand-over "$@" 2> /dev/null && exit 0
fi

if [ "$HEADLESS" = 1 ]; then
    DRIVER_ARGS+=(--headless)
elif [ -z "${WAYLAND_DISPLAY:-}" ] && [ -n "${DISPLAY:-}" ]; then
    # Only an X server here. Godot would try Wayland first and print three
    # errors and a warning on the way to X11, so the wrapper names X11 at once.
    DRIVER_ARGS+=(--display-driver x11)
fi

# Godot prints each warning as a WARNING: line plus an indented "at:" line, so
# filtering only the first leaves an orphaned file:line dangling in the output.
# Tells the app not to point at warnings this wrapper has just hidden.
export SARA_WARNINGS_FILTERED=1

# Godot's headless display server has no rendering device, and the first
# autoload says so on stderr with a backtrace, which a painter asking for a
# version cannot act on. So stderr is held back and shown only when the run
# failed, and a successful one leaves exactly the line.
if [ "$HEADLESS" = 1 ]; then
    HELD="$(mktemp)"
    trap 'rm -f "$HELD"' EXIT
    STATUS=0
    "$HERE/sara.x86_64" "${DRIVER_ARGS[@]}" -- "$@" 2> "$HELD" || STATUS=$?
    if [ "$STATUS" != 0 ]; then cat "$HELD" >&2; fi
    exit "$STATUS"
fi

# After `--`, so Godot hands them to the app rather than reading them as engine
# flags. A path from a file manager or a terminal arrives that way, and
# OS.get_cmdline_user_args() is what the app reads.
exec "$HERE/sara.x86_64" "${DRIVER_ARGS[@]}" -- "$@" 2> >(
    grep -Ev \
        -e "Can't obtain the XDG decoration manager" \
        -e "xdg-toplevel-icon protocol not found" \
        -e "at: init \(platform/linuxbsd/wayland/wayland_thread\.cpp" >&2
)
