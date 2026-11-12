#!/usr/bin/env bash
#
# Installs Sara for the current user: the binary and the native modules' libraries beside it, its launcher, LICENSE,
# THIRDPARTY.txt, README.txt, the page for the painter, and the Python client's modules under ~/.local/lib/sara, a `sara` command in ~/.local/bin,
# the desktop entry and the icons. Nothing the desktop launches lives inside the checkout afterwards, so
# moving the repository or running `git clean` does not break the install. Only
# the desktop entry's Rebuild action points back at the source, because a
# rebuild needs it.
#
# Everything goes under ~/.local, or under SARA_PREFIX when set, so no root and
# nothing outside the user's own directories. Run packaging/uninstall.sh to
# reverse it exactly.
#
# It builds first when the build in build/l is not of the checkout: no binary,
# no stamp, a stamp at another commit than HEAD, or a tree with uncommitted
# changes. `--no-build` installs whatever build/l holds, for a caller that built
# on purpose, and says which commit that is.
#
# Each install puts the binary in a folder of its own under builds/, and
# sara.x86_64 beside the launcher becomes a link to the newest. A running Sara
# reads its embedded pack again by the path it started from, which the kernel
# resolves to the real file in builds/, so a later install never changes the
# files under it. The folders no running Sara holds are pruned, all but the
# newest. An install before this one left sara.x86_64 a plain file, and a Sara
# running from that would read the new link, so the script refuses while one
# runs, names it, and `--force` overrides.
#
# Last it offers the udev rule the pen module needs, and prints the one sudo
# command that installs it, which it never runs. `--pen-rule` runs that step
# alone, building and installing nothing.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$REPO_ROOT/build/l"

PREFIX="${SARA_PREFIX:-$HOME/.local}"
LIB_DIR="$PREFIX/lib/sara"
BIN_DIR="$PREFIX/bin"
APP_DIR="$PREFIX/share/applications"
ICON_ROOT="$PREFIX/share/icons/hicolor"
MIME_DIR="$PREFIX/share/mime"

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    C_DIM=$'\033[38;5;242m'; C_OK=$'\033[38;5;114m'; C_ERR=$'\033[38;5;203m'
    C_BRAND=$'\033[38;5;215m'; C_OFF=$'\033[0m'
else
    C_DIM=""; C_OK=""; C_ERR=""; C_BRAND=""; C_OFF=""
fi
die() { printf '\n%s✗ %s%s\n\n' "$C_ERR" "$1" "$C_OFF" >&2; exit 1; }

NO_BUILD=false
PEN_RULE_ONLY=false
FORCE=false
for argument in "$@"; do
    case "$argument" in
        --no-build) NO_BUILD=true ;;
        --pen-rule) PEN_RULE_ONLY=true ;;
        --force) FORCE=true ;;
        *) die "unknown argument $argument, the only ones are --no-build, --pen-rule and --force" ;;
    esac
done

BUILDS_DIR="$LIB_DIR/builds"

# Every process of this user whose program is a file at or under $1, one
# "pid path" a line. The kernel adds " (deleted)" to a program whose file was
# replaced, which still counts, because that Sara reads the path again.
sara_processes_under() {
    local exe pid
    for exe in /proc/[0-9]*/exe; do
        pid="${exe#/proc/}"; pid="${pid%/exe}"
        local target
        target="$(readlink "$exe" 2>/dev/null)" || continue
        target="${target% (deleted)}"
        case "$target" in
            "$1"|"$1"/*) printf '%s %s\n' "$pid" "$target" ;;
        esac
    done
}

# The pen module reads the tablet's pen node under /dev/input, which is
# root:input 0660 on Fedora, so the seat's user reads it once the rule beside
# this script is in. Putting it there is root's, so this prints the one command
# that does, with udev told to read the rules again and apply them to the nodes
# already there, and never runs sudo itself. Joining the input group is not
# offered, because that group reads every keyboard as well.
PEN_RULE="$SCRIPT_DIR/70-sara-pen.rules"
UDEV_RULES_DIR="${SARA_UDEV_RULES_DIR:-/etc/udev/rules.d}"
offer_pen_rule() {
    local installed="$UDEV_RULES_DIR/70-sara-pen.rules"
    if cmp -s "$PEN_RULE" "$installed"; then
        printf '  %s✓%s %s  %sthe pen module may read the tablet%s\n' "$C_OK" "$C_OFF" "$installed" "$C_DIM" "$C_OFF"
        return 0
    fi
    printf '\n  %sThe pen module hears the upper barrel button let go in the air once this udev rule is in %s:%s\n\n' \
        "$C_DIM" "$installed" "$C_OFF"
    grep -v '^#' "$PEN_RULE" | sed 's/^/    /'
    printf '\n  %sTo install it, run this one command, which asks for your password:%s\n\n' "$C_DIM" "$C_OFF"
    printf '    sudo sh -c %s sh %q %q\n\n' \
        "'install -m 644 \"\$1\" \"\$2\" && udevadm control --reload && udevadm trigger --subsystem-match=input --action=change'" \
        "$PEN_RULE" "$installed"
}

if [ "$PEN_RULE_ONLY" = true ]; then
    offer_pen_rule
    exit 0
fi

STAMP="$BUILD_DIR/build_info.json"
stamp_field() { sed -n "s/.*\"$1\": \"\([^\"]*\)\".*/\1/p" "$STAMP" 2>/dev/null | head -n 1; }

# Why the build in build/l is not the checkout's, or nothing when it is. A
# checkout with no git has no HEAD to compare, so the build there is taken as
# it stands.
stale_reason() {
    local head_full stamp_commit
    head_full="$(git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null || true)"
    [ -n "$head_full" ] || return 0
    if [ ! -f "$STAMP" ]; then echo "the build has no stamp"; return 0; fi
    stamp_commit="$(stamp_field commit_full)"
    if [ -z "$stamp_commit" ]; then echo "the build's stamp names no commit"; return 0; fi
    if [ "$stamp_commit" != "$head_full" ]; then
        echo "the build is of ${stamp_commit:0:7} and the tree is at ${head_full:0:7}"; return 0
    fi
    if grep -q '"dirty": true' "$STAMP"; then echo "the build at ${head_full:0:7} had uncommitted changes in it"; return 0; fi
    if [ -n "$(git -C "$REPO_ROOT" status --porcelain --untracked-files=no 2>/dev/null)" ]; then
        echo "the tree has uncommitted changes since ${head_full:0:7}"; return 0
    fi
}

if [ ! -x "$BUILD_DIR/sara.x86_64" ]; then
    printf '  %sno build found, running packaging/build.sh first%s\n' "$C_DIM" "$C_OFF"
    "$SCRIPT_DIR/build.sh"
elif [ "$NO_BUILD" = true ]; then
    printf '  %s--no-build, installing the build at %s%s\n' "$C_DIM" "$(stamp_field commit | grep . || echo unknown)" "$C_OFF"
else
    REASON="$(stale_reason)"
    if [ -n "$REASON" ]; then
        printf '  %s%s, running packaging/build.sh first%s\n' "$C_DIM" "$REASON" "$C_OFF"
        "$SCRIPT_DIR/build.sh"
    fi
fi

printf '\n  %sSara%s %sinstall%s\n\n' "$C_BRAND" "$C_OFF" "$C_DIM" "$C_OFF"

# The desktop action needs a terminal to run the rebuild in, and which one exists
# varies by desktop. Pick the first available rather than assuming GNOME.
TERMINAL=""
for candidate in kgx "gnome-terminal --" konsole "xfce4-terminal -x" "alacritty -e" "kitty" "foot" "xterm -e"; do
    if command -v "${candidate%% *}" >/dev/null 2>&1; then TERMINAL="$candidate"; break; fi
done
[ -n "$TERMINAL" ] || printf '  %swarning: no terminal emulator found; the Rebuild and console actions may not show output%s\n' "$C_DIM" "$C_OFF"

# A plain sara.x86_64 is an install from before builds/, and a Sara running
# from it would read the link this install puts in its place.
if [ -f "$LIB_DIR/sara.x86_64" ] && [ ! -L "$LIB_DIR/sara.x86_64" ]; then
    RUNNING="$(sara_processes_under "$LIB_DIR/sara.x86_64")"
    if [ -n "$RUNNING" ] && [ "$FORCE" != true ]; then
        printf '\n%s✗ Sara is running from %s, and installing now would change the files it reads:%s\n\n' \
            "$C_ERR" "$LIB_DIR/sara.x86_64" "$C_OFF" >&2
        printf '%s\n' "$RUNNING" | sed 's/^/    pid /' >&2
        printf '\n  %sSave and quit that Sara, or end it with kill and the pid above, then install again.%s\n' "$C_DIM" "$C_OFF" >&2
        printf '  %s--force installs anyway, and that Sara may crash. Later installs never need it.%s\n\n' "$C_DIM" "$C_OFF" >&2
        exit 1
    fi
fi

mkdir -p "$LIB_DIR" "$BUILDS_DIR" "$BIN_DIR" "$APP_DIR" "$MIME_DIR/packages"

# The copy is the install. build/ is output and may be deleted at any time.
# The folder is named by the time and the stamp's commit, and a number when two
# installs fall in one second.
BUILD_NAME="$(date +%Y%m%d-%H%M%S)-$(stamp_field commit | grep . || echo unstamped)"
NEW_DIR="$BUILDS_DIR/$BUILD_NAME"
n=1
while [ -e "$NEW_DIR" ]; do n=$((n + 1)); NEW_DIR="$BUILDS_DIR/$BUILD_NAME-$n"; done
mkdir -p "$NEW_DIR"
install -m 755 "$BUILD_DIR/sara.x86_64" "$NEW_DIR/sara.x86_64"
if [ -f "$BUILD_DIR/build_info.json" ]; then
    install -m 644 "$BUILD_DIR/build_info.json" "$NEW_DIR/build_info.json"
fi
# The native modules' libraries the export left beside the binary go with it,
# since Godot loads each from the binary's own folder, and an install without
# them would run with no JPEG XL and unpack LZW in GDScript.
for library in "$BUILD_DIR"/*.so; do
    [ -f "$library" ] || continue
    install -m 755 "$library" "$NEW_DIR/${library##*/}"
done

# Every library the linux.x86_64 line of a .gdextension under modules/ names,
# one "module library" a line, the module named by the folder its file is in.
linux_libraries() {
    find "$REPO_ROOT/sara-godot/modules" \( -name godot-cpp -o -name build -o -name .godot \) -prune \
            -o -name '*.gdextension' -type f -print 2>/dev/null | sort | while read -r list; do
        sed -n 's/^[[:space:]]*linux\.x86_64[[:space:]]*=[[:space:]]*"\(.*\)"[[:space:]]*$/\1/p' "$list" \
            | while read -r library; do
                module="${list%/*}"
                printf '%s %s\n' "${module##*/}" "${library##*/}"
            done
    done
}

# A library missing is a warning, not a failure, because build.sh exports a
# Sara without a module whose library did not build and says so then.
MISSING_MODULES=()
while read -r module library; do
    [ -n "$library" ] || continue
    [ -f "$NEW_DIR/$library" ] || MISSING_MODULES+=("$module $library")
done < <(linux_libraries)
# A link made beside and renamed over, so sara.x86_64 is never missing for a
# launch that falls in between.
ln -sfn "builds/${NEW_DIR##*/}/sara.x86_64" "$LIB_DIR/sara.x86_64.new"
mv -fT "$LIB_DIR/sara.x86_64.new" "$LIB_DIR/sara.x86_64"
if [ -f "$NEW_DIR/build_info.json" ]; then
    ln -sfn "builds/${NEW_DIR##*/}/build_info.json" "$LIB_DIR/build_info.json.new"
    mv -fT "$LIB_DIR/build_info.json.new" "$LIB_DIR/build_info.json"
else
    rm -f "$LIB_DIR/build_info.json"
fi
install -m 755 "$SCRIPT_DIR/sara.sh" "$LIB_DIR/sara.sh"
install -m 755 "$SCRIPT_DIR/sara-console.sh" "$LIB_DIR/sara-console.sh"
# The licence and the third-party notices go beside the binary, since GPLv3
# asks that the licence travels with the program.
install -m 644 "$REPO_ROOT/LICENSE" "$LIB_DIR/LICENSE"
install -m 644 "$REPO_ROOT/THIRDPARTY.txt" "$LIB_DIR/THIRDPARTY.txt"
# The page for the painter goes beside them, as it does in the zip.
install -m 644 "$SCRIPT_DIR/painter-guide.txt" "$LIB_DIR/README.txt"
# The Python client goes beside them too, the files build.sh put beside the
# binary from the list it reads, so a notebook finds sara.py in the folder
# sara.sh starts Sara from. One a build lacks warns and the install goes on,
# as a missing library does, because a build older than the client has none.
while read -r module; do
    [ -n "$module" ] || continue
    if [ -f "$BUILD_DIR/$module" ]; then
        install -m 644 "$BUILD_DIR/$module" "$LIB_DIR/$module"
    else
        printf '  %swarning%s the build holds no %s, so the install has no Python client file of that name. Build again.\n' "$C_ERR" "$C_OFF" "$module" >&2
    fi
done < <(sed -e 's/#.*//' -e 's/[[:space:]]*$//' "$SCRIPT_DIR/client-modules.txt")
ln -sfn "$LIB_DIR/sara.sh" "$BIN_DIR/sara"

# The older builds go, all but the ones a Sara still runs from.
KEPT=()
for old in "$BUILDS_DIR"/*/; do
    old="${old%/}"
    [ "$old" = "$NEW_DIR" ] && continue
    if [ -n "$(sara_processes_under "$old")" ]; then
        KEPT+=("${old##*/}")
    else
        rm -rf "$old"
    fi
done

# Icons: the logo is a render, so it goes in as a PNG. The SVG an older install
# put into scalable would win over it, so it goes.
rm -f "$ICON_ROOT/scalable/apps/sara.svg"
if [ -f "$REPO_ROOT/sara-godot/ui/icon.png" ]; then
    mkdir -p "$ICON_ROOT/512x512/apps"
    install -m 644 "$REPO_ROOT/sara-godot/ui/icon.png" "$ICON_ROOT/512x512/apps/sara.png"
fi

# The document type, so a file manager has something to offer Sara for. The
# desktop entry names this type, and a name nothing declares is offered to
# nobody, which is why "Open with > Sara" was missing for a .sad.
install -m 644 "$SCRIPT_DIR/sara-mime.xml" "$MIME_DIR/packages/sara.xml"
command -v update-mime-database >/dev/null 2>&1 && update-mime-database "$MIME_DIR" || true

sed -e "s|@LIB_DIR@|$LIB_DIR|g" \
    -e "s|@PREFIX@|$PREFIX|g" \
    -e "s|@REPO_ROOT@|$REPO_ROOT|g" \
    -e "s|@TERMINAL@|$TERMINAL|g" \
    "$SCRIPT_DIR/sara.desktop.in" > "$APP_DIR/sara.desktop"
chmod 644 "$APP_DIR/sara.desktop"

command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database -q "$APP_DIR" || true
command -v gtk-update-icon-cache   >/dev/null 2>&1 && gtk-update-icon-cache -qtf "$ICON_ROOT" 2>/dev/null || true

if command -v desktop-file-validate >/dev/null 2>&1; then
    desktop-file-validate "$APP_DIR/sara.desktop" && printf '  %s✓%s desktop entry validates\n' "$C_OK" "$C_OFF"
fi

# What was installed, from the stamp the build left beside the binary, so the
# terminal says which commit is now in the application menu.
IDENTITY=""
if [ -f "$LIB_DIR/build_info.json" ]; then
    IDENTITY="v$(sed -n 's/.*"version": "\([^"]*\)".*/\1/p' "$LIB_DIR/build_info.json")"
    IDENTITY="$IDENTITY at $(sed -n 's/.*"commit": "\([^"]*\)".*/\1/p' "$LIB_DIR/build_info.json")"
    grep -q '"dirty": true' "$LIB_DIR/build_info.json" && IDENTITY="$IDENTITY, uncommitted changes"
fi

printf '  %s✓%s %s  %s%s%s\n' "$C_OK" "$C_OFF" "$NEW_DIR/sara.x86_64" "$C_DIM" "$IDENTITY" "$C_OFF"
for missing in "${MISSING_MODULES[@]}"; do
    printf '  %swarning: the module %s runs without its library, %s is not in %s%s\n' \
        "$C_ERR" "${missing%% *}" "${missing#* }" "$NEW_DIR" "$C_OFF"
done
for kept in "${KEPT[@]}"; do
    printf '  %s·%s %s  %skept, a Sara is running from it%s\n' "$C_DIM" "$C_OFF" "$BUILDS_DIR/$kept" "$C_DIM" "$C_OFF"
done
printf '  %s✓%s %s\n' "$C_OK" "$C_OFF" "$BIN_DIR/sara"
printf '  %s✓%s %s\n' "$C_OK" "$C_OFF" "$APP_DIR/sara.desktop"
printf '  %s✓%s %s\n' "$C_OK" "$C_OFF" "$ICON_ROOT/512x512/apps/sara.png"
printf '  %s✓%s %s\n' "$C_OK" "$C_OFF" "$MIME_DIR/packages/sara.xml"
offer_pen_rule
printf '\n  %sSara is in your application menu. Right-click it for "Rebuild from source".%s\n\n' "$C_DIM" "$C_OFF"
