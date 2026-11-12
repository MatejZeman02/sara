#!/usr/bin/env bash
# Removes everything install.sh created. Leaves build/ alone.
set -euo pipefail
PREFIX="${SARA_PREFIX:-$HOME/.local}"
LIB_DIR="$PREFIX/lib/sara"
BIN_DIR="$PREFIX/bin"
APP_DIR="$PREFIX/share/applications"
ICON_ROOT="$PREFIX/share/icons/hicolor"
MIME_DIR="$PREFIX/share/mime"

rm -fv "$BIN_DIR/sara" \
       "$APP_DIR/sara.desktop" \
       "$MIME_DIR/packages/sara.xml" \
       "$ICON_ROOT/scalable/apps/sara.svg" \
       "$ICON_ROOT/512x512/apps/sara.png"
rm -rfv "$LIB_DIR"

command -v update-mime-database    >/dev/null 2>&1 && update-mime-database "$MIME_DIR" || true
command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database -q "$APP_DIR" || true
command -v gtk-update-icon-cache   >/dev/null 2>&1 && gtk-update-icon-cache -qtf "$ICON_ROOT" 2>/dev/null || true
echo "Sara uninstalled."
