#!/usr/bin/env bash
#
# Wraps a Linux build into one AppImage, build/a/Sara-<version>-x86_64.AppImage,
# the file a release hands a Linux painter beside the Windows zip. The words
# release and public pick the build the way build.sh names its folder, build/l,
# build/l-release or build/l-release-public, and a release asset is the public
# one.
#
# The AppImage holds the binary, the launch wrapper, the stamp, the licence
# files, the pen's udev rule and the document type, and nothing the host
# supplies. Vulkan, Mesa and the display libraries stay the host's, because a
# bundled driver would not match the GPU it runs on. The binary needs glibc
# 2.28 or newer and opens its other libraries at run time. The native modules'
# libraries need 2.34 when build.sh made them with GODOT_LINUX_SDK, so one file
# runs on a distro of 2021 or later, Debian 12 and Ubuntu 22.04 among them.
#
# An AppImage cannot install the udev rule the pen module needs, so the rule
# rides inside it at usr/share/sara/ for a distro package to install and for
# a painter to copy by hand.
#
# It never builds. Run packaging/build.sh first, so the file is made from a
# build somebody chose. A build stamped with uncommitted changes is refused
# unless --allow-dirty is given, since a release should name a commit.
#
# The packer is appimagetool, taken from APPIMAGETOOL when that names a file
# and otherwise downloaded once into build/a/. The packer runs without FUSE
# (APPIMAGE_EXTRACT_AND_RUN), so a build machine needs no kernel support for it.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$REPO_ROOT/build/l"
OUT_DIR="$REPO_ROOT/build/a"
APPDIR="$OUT_DIR/Sara.AppDir"
TOOL_URL="https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage"

die() { printf '\n✗ %s\n\n' "$1" >&2; exit 1; }

ALLOW_DIRTY=false
SUFFIX=""
PUBLIC=""
for argument in "$@"; do
    case "$argument" in
        --allow-dirty) ALLOW_DIRTY=true ;;
        release) SUFFIX="-release" ;;
        public) PUBLIC="-public" ;;
        *) die "unknown argument $argument, the arguments are release, public and --allow-dirty" ;;
    esac
done
BUILD_DIR="$REPO_ROOT/build/l$SUFFIX$PUBLIC"

[ -x "$BUILD_DIR/sara.x86_64" ] || die "no build in $BUILD_DIR, run packaging/build.sh first."
STAMP="$BUILD_DIR/build_info.json"
[ -f "$STAMP" ] || die "the build has no stamp, run packaging/build.sh again."
if grep -q '"dirty": true' "$STAMP" && [ "$ALLOW_DIRTY" = false ]; then
    die "the build was made with uncommitted changes. Commit and rebuild, or pass --allow-dirty."
fi
VERSION="$(sed -n 's/.*"version": "\([^"]*\)".*/\1/p' "$STAMP" | head -n 1)"
[ -n "$VERSION" ] || die "the stamp names no version."

mkdir -p "$OUT_DIR"
TOOL="${APPIMAGETOOL:-$OUT_DIR/appimagetool}"
if [ ! -x "$TOOL" ]; then
    command -v curl >/dev/null 2>&1 || die "curl is needed to fetch appimagetool, or set APPIMAGETOOL to a copy."
    printf '  fetching appimagetool from %s\n' "$TOOL_URL"
    curl -fsSL -o "$TOOL" "$TOOL_URL" || { rm -f "$TOOL"; die "the download of appimagetool failed."; }
    chmod 755 "$TOOL"
fi

rm -rf "$APPDIR"
LIB="$APPDIR/usr/lib/sara"
SHARE="$APPDIR/usr/share/sara"
mkdir -p "$LIB" "$SHARE"

install -m 755 "$BUILD_DIR/sara.x86_64" "$LIB/sara.x86_64"
install -m 755 "$SCRIPT_DIR/sara.sh" "$LIB/sara.sh"
install -m 644 "$STAMP" "$LIB/build_info.json"
# The native modules' libraries sit beside the binary, where their .gdextension
# files look for them, so a file without them opens no JPEG XL or LZW TIFF.
for library in "$BUILD_DIR"/*.so; do
    if [ -f "$library" ]; then install -m 644 "$library" "$LIB/$(basename "$library")"; fi
done
for licence in LICENSE THIRDPARTY.txt README.txt; do
    if [ -f "$BUILD_DIR/$licence" ]; then install -m 644 "$BUILD_DIR/$licence" "$LIB/$licence"; fi
done
install -m 644 "$SCRIPT_DIR/70-sara-pen.rules" "$SHARE/70-sara-pen.rules"
install -m 644 "$SCRIPT_DIR/sara-mime.xml" "$SHARE/sara-mime.xml"

# The two files appimagetool wants at the top: an entry and its icon, named alike.
install -m 644 "$REPO_ROOT/sara-godot/ui/icon.png" "$APPDIR/sara.png"
cat > "$APPDIR/sara.desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Version=1.5
Name=Sara
GenericName=Digital Painting
Comment=GPU-first digital painting
Exec=sara %F
Icon=sara
Terminal=false
Categories=Graphics;2DGraphics;RasterGraphics;
Keywords=paint;draw;art;canvas;brush;
MimeType=application/x-sara-document;image/png;image/jpeg;image/webp;
StartupWMClass=Sara
StartupNotify=true
DESKTOP

# The wrapper finds the binary beside itself, so AppRun only has to hand over.
cat > "$APPDIR/AppRun" <<'APPRUN'
#!/bin/sh
HERE="$(dirname "$(readlink -f "$0")")"
exec "$HERE/usr/lib/sara/sara.sh" "$@"
APPRUN
chmod 755 "$APPDIR/AppRun"

OUT="$OUT_DIR/Sara-$VERSION-x86_64.AppImage"
rm -f "$OUT"
ARCH=x86_64 APPIMAGE_EXTRACT_AND_RUN=1 "$TOOL" --no-appstream "$APPDIR" "$OUT" >"$OUT_DIR/appimagetool.log" 2>&1 \
    || { tail -20 "$OUT_DIR/appimagetool.log" >&2; die "appimagetool failed."; }
[ -x "$OUT" ] || die "appimagetool reported success but $OUT is missing."
printf '  ✓ %s (%s MB)\n' "$OUT" "$(( $(stat -c%s "$OUT") / 1024 / 1024 ))"
