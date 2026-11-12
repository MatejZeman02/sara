#!/usr/bin/env bash
#
# Backs the desktop file's "Launch with console" action. Installed alongside
# the binary.
#
# Runs Sara through its usual wrapper in the terminal the action opened, so
# every error and warning the engine prints reaches the screen, including the
# ones that never land in the run log. The window stays open after Sara exits,
# because a crash is exactly when the last lines matter and a terminal that
# closed with the process would take them away.
HERE="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")" && pwd)"

"$HERE/sara.sh" "$@"
status=$?
printf '\nSara exited with status %d. Press Enter to close this window.' "$status"
read -r _
