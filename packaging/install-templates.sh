#!/usr/bin/env bash
#
# Installs the Godot export templates that match the editor on PATH, which
# `build.sh` needs and which are a separate download from the editor, about
# 1.3 GB. Run it once for each Godot version.
#
#   ./packaging/install-templates.sh              # download and install
#   ./packaging/install-templates.sh --all        # keep every platform's templates, not only x86_64
#   ./packaging/install-templates.sh --from FILE  # use a .tpz already downloaded
#   ./packaging/install-templates.sh --print      # say the version, the URL and the folder, change nothing
#
# GODOT names the editor (default godot), and SARA_TEMPLATES_URL replaces the
# whole download address, for a mirror.
#
# The editor reports its version as `4.7.2.stable.official.ed1daf0bf` or, for a
# release with no patch number, `4.7.stable.official.ed1daf0bf`, and a
# pre-release says `4.8.rc1` where a release says `stable`. The templates
# folder Godot reads is the report without the last two fields, and the
# release's tag is that with the status joined by a hyphen, `4.7.2-stable`
# or `4.8-rc1`, which is also in the file name on GitHub. Nothing here
# guesses a patch number, so a Godot that is not a tagged release (a `dev` or
# `custom_build` status) is refused with the reason.
#
# The download goes into a folder of its own made by mktemp, which is removed
# when the script ends, and the templates are unpacked straight into the
# folder Godot reads them from.
set -euo pipefail

GODOT_BIN="${GODOT:-godot}"
KEEP='*x86_64*'
FROM=""
PRINT=false

die() { printf '\n✗ %s\n\n' "$1" >&2; exit 1; }

while [ $# -gt 0 ]; do
    case "$1" in
        --all) KEEP='*'; shift ;;
        --print) PRINT=true; shift ;;
        --from)
            [ $# -ge 2 ] || die "--from wants a .tpz file after it."
            FROM="$2"; shift 2 ;;
        -h|--help)
            sed -n '3,25p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
            exit 0 ;;
        *) die "Unknown argument \"$1\". The flags are --all, --from FILE, --print and --help." ;;
    esac
done

# The editor's report, split into what names the templates. $1 is the report,
# and the result is "<folder name> <tag>" or nothing when it is not a release.
template_names() {
    local report="$1" version status
    report="${report%%[[:space:]]*}"
    # Drop the build kind and hash (.official.ed1daf0bf), the last two fields.
    version="$(printf '%s' "$report" | sed -E 's/\.[a-z_]+\.[0-9a-f]+$//')"
    # What is left ends in the status: stable, rc1, beta2.
    status="${version##*.}"
    case "$status" in
        stable|rc[0-9]*|beta[0-9]*) ;;
        *) return 1 ;;
    esac
    case "${version%.*}" in
        [0-9]*.[0-9]*) ;;
        *) return 1 ;;
    esac
    printf '%s %s-%s\n' "$version" "${version%.*}" "$status"
}

if [ -n "${SARA_TEMPLATES_TEST_REPORT:-}" ]; then
    REPORT="$SARA_TEMPLATES_TEST_REPORT"
else
    command -v "$GODOT_BIN" >/dev/null 2>&1 || die "No $GODOT_BIN on PATH. Set GODOT to the editor whose templates are wanted."
    REPORT="$("$GODOT_BIN" --version 2>/dev/null | head -1)"
fi
[ -n "$REPORT" ] || die "$GODOT_BIN --version printed nothing."
NAMES="$(template_names "$REPORT")" \
    || die "\"$REPORT\" is not a tagged release of Godot, so there are no templates to name. Install the templates by hand from godotengine.org."
FOLDER_NAME="${NAMES%% *}"
TAG="${NAMES##* }"
FILE="Godot_v${TAG}_export_templates.tpz"
URL="${SARA_TEMPLATES_URL:-https://github.com/godotengine/godot/releases/download/${TAG}/${FILE}}"
TARGET="${XDG_DATA_HOME:-$HOME/.local/share}/godot/export_templates/$FOLDER_NAME"

printf '  editor   %s\n  version  %s\n  url      %s\n  folder   %s\n' "$REPORT" "$FOLDER_NAME" "$URL" "$TARGET"
[ "$PRINT" = true ] && exit 0

command -v unzip >/dev/null 2>&1 || die "No unzip on PATH."
SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/sara-templates.XXXXXX")"
trap 'rm -r -- "$SCRATCH"' EXIT

if [ -n "$FROM" ]; then
    [ -f "$FROM" ] || die "$FROM is not a file."
    ARCHIVE="$FROM"
else
    command -v curl >/dev/null 2>&1 || die "No curl on PATH."
    ARCHIVE="$SCRATCH/$FILE"
    curl -fL --retry 3 -o "$ARCHIVE" "$URL" || die "The download failed. The release may not carry templates under that name, so look at $URL."
fi

unzip -tq "$ARCHIVE" >/dev/null || die "$ARCHIVE is not a whole zip file."
mkdir -p "$TARGET"
unzip -oj "$ARCHIVE" "templates/$KEEP" templates/version.txt -d "$TARGET" >/dev/null \
    || die "Nothing under templates/ in the archive matched, so the release is laid out in a way this does not know."
SAID="$(tr -d '[:space:]' < "$TARGET/version.txt" 2>/dev/null || true)"
[ "$SAID" = "$FOLDER_NAME" ] \
    || die "The templates say they are \"$SAID\" and the editor is \"$FOLDER_NAME\". Look in $TARGET."
printf '\n  ✓ templates for %s are in %s\n\n' "$FOLDER_NAME" "$TARGET"
