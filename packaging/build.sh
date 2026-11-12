#!/usr/bin/env bash
#
# Exports a build of Sara for one platform, stamped with the version from
# project.godot, the commit it was built from and whether it is the debug or
# the release build. A debug build keeps the GDScript call stacks, so a crash in
# a stranger's hands names the line that failed, which is what the alpha needs
# to be debuggable, and it stays the default.
#
# The platform is the first argument and defaults to linux. The second is the
# build, debug by default or release, and a release build lands in a folder of
# its own, build/l-release or build/w-release, so it never writes over the
# debug one. Both ship, the release build for every painter and the debug build
# to reproduce a bug in, so a Windows zip's name ends in -debug.zip or
# -release.zip. Linux lands in
# build/l as an ELF binary and its launch wrapper, which install.sh copies.
# Windows lands in build/w as sara.exe with its console wrapper, and is zipped
# there with the launcher that opens Sara's door, the sara.py client with the
# modules beside it that packaging/client-modules.txt lists, AGENTS.md, the guide for a coding agent,
# README.txt, the page for the painter, LICENSE and THIRDPARTY.txt, and the native modules' libraries the export put
# beside the exe, because the alpha hands a stranger a zip rather than an
# installer. Linux gets both guides, the two licence files and the same client
# modules beside its binary too, and no Python is shipped on either platform,
# the client needs numpy and a notebook IPython and ipywidgets, which a user
# brings in their own Python.
#
# The word public, after the platform or the build, makes the build a stranger
# may be handed: it leaves out every folder packaging/not-public.txt names, the
# private mixing module today, says so in the zip's name, and lands in a folder
# of its own, build/l-public or build/w-release-public. Without the word a build
# keeps every module, and that is the build a tester takes. The
# preset names the icon, so the exe carries Sara's artwork and its version
# strings into the Windows file properties. Android lands in build/a as a
# debug APK for a tablet, sara-android-v<version>-<commit>-debug.apk, and
# packaging/android-sdk.sh sets up the SDK, the JDK 17 and the debug key it
# needs, with painter-guide.txt beside it as README.txt, the page that tells
# the painter how to install it and where its log and notes are.
#
# Kept here rather than in build/, which is gitignored: a script that lives in
# an ignored folder is not reviewed with the tree, and the one that did rotted
# through a project rename into referring to files that are not there.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
PROJECT_DIR="$REPO_ROOT/sara-godot"

# The two platforms the presets in sara-godot/export_presets.cfg carry. The
# output directory, the artefact name and the preset name travel together, so
# they are chosen once here rather than spelled again below.
#
# A Windows build fails before its export when a native module's Windows
# library is not built, because the zip a stranger is handed would carry no
# JPEG XL or LZW TIFF and nobody would be told.
# --without-modules lets it go on, and the zip's name then ends in
# -without-<module> for each library it lacks.
PLATFORM=""
KIND=""
WITHOUT_MODULES=false
PUBLIC=false
for arg in "$@"; do
    case "${arg,,}" in
        --without-modules) WITHOUT_MODULES=true ;;
        public) PUBLIC=true ;;
        -*) printf 'Unknown switch "%s". The one switch is --without-modules.\n' "$arg" >&2; exit 2 ;;
        *) if [ -z "$PLATFORM" ]; then PLATFORM="$arg"
           elif [ -z "$KIND" ]; then KIND="$arg"
           else printf 'A third argument, "%s". build.sh takes a platform, then debug or release, and the word public.\n' "$arg" >&2; exit 2
           fi ;;
    esac
done
PLATFORM="${PLATFORM:-linux}"
PLATFORM="${PLATFORM,,}"
KIND="${KIND:-debug}"
KIND="${KIND,,}"
case "$KIND" in
    debug|release) ;;
    *) printf 'Unknown build "%s". The builds are debug, the default, and release.\n' "$KIND" >&2; exit 2 ;;
esac
# A release build's folder has its own name, so the debug build install.sh
# copies out of build/l is never written over.
FOLDER_SUFFIX=""
[ "$KIND" = release ] && FOLDER_SUFFIX="-release"
# A public build's folder has its own name too, so the build a tester takes and
# the one install.sh copies keep every module.
[ "$PUBLIC" = true ] && FOLDER_SUFFIX="$FOLDER_SUFFIX-public"
case "$PLATFORM" in
    linux)
        PRESET="Linux"
        OUT_DIR="$REPO_ROOT/build/l$FOLDER_SUFFIX"
        OUT_BIN_NAME="sara.x86_64"
        ;;
    windows)
        PRESET="Windows Desktop"
        OUT_DIR="$REPO_ROOT/build/w$FOLDER_SUFFIX"
        OUT_BIN_NAME="sara.exe"
        ;;
    android)
        # A debug APK for a tablet, arm64-v8a and x86_64, from Godot's prebuilt
        # template rather than a Gradle build. Its name takes
        # the version and the commit once they are read below.
        PRESET="Android"
        OUT_DIR="$REPO_ROOT/build/a"
        OUT_BIN_NAME=""
        [ "$KIND" = debug ] || { printf 'android builds a debug APK alone so far, "%s" asks for another.\n' "$KIND" >&2; exit 2; }
        ;;
    modules)
        # Only the native modules' libraries, both platforms, and no export.
        PRESET=""
        OUT_DIR="$REPO_ROOT/build"
        OUT_BIN_NAME=""
        [ "$KIND" = debug ] && [ "$PUBLIC" = false ] || { printf 'modules builds the native libraries alone and takes no build, "%s" asks for one.\n' "$*" >&2; exit 2; }
        ;;
    *)
        printf 'Unknown platform "%s". The platforms are linux, windows and android, and modules builds the native modules alone.\n' "$PLATFORM" >&2
        exit 2
        ;;
esac
OUT_BIN="$OUT_DIR/$OUT_BIN_NAME"
CONSOLE_WRAPPER="$OUT_DIR/sara.console.exe"
# The Windows zip's second launcher, which starts sara.exe with its door.
DOOR_LAUNCHER="sara-with-door.cmd"

# Written into the project so the export packs it, moved beside the binary once
# the export is done, and removed from the project whatever happens: a stamp
# left behind would tell every editor run that it is last week's build.
# core/app/sa_build_info.gd reads it, and install.sh reads the copy in build/.
STAMP="$PROJECT_DIR/build_info.json"

# The changelog lives at the repository root, where a person reads it, and the
# export can only pack what is under res://. So it is copied into the project
# for the length of the export and removed again by the trap below, the way the
# stamp is. core/app/sa_changelog.gd reads the packed copy back.
CHANGELOG="$REPO_ROOT/CHANGELOG.md"
CHANGELOG_COPY="$PROJECT_DIR/CHANGELOG.md"

# The step kinds the door answers {"steps": true} with. They are parsed out of
# doc comments, which an export does not carry, so the catalogue is written for
# the length of the export the way the changelog is copied, and removed by the
# same trap. harness/door/sa_door_catalogue.gd reads it back.
CATALOGUE="$PROJECT_DIR/step_catalogue.json"

# The page for a coding agent that has the build and nothing else, packed
# beside the binary on both platforms as AGENTS.md, the name most agents read
# unasked. In the repository it has a name of its own, so an agent working on
# the packaging never takes the build's guide for its own instructions.
AGENT_GUIDE="$SCRIPT_DIR/agent-guide.md"
# The page for the painter, which zip to take, what a first start needs, where
# Sara keeps its data and how to send a bug. Plain text, packed as README.txt
# beside the binary on both platforms, and beside the APK, so a double click opens it on any
# machine.
PAINTER_GUIDE="$SCRIPT_DIR/painter-guide.txt"

# GPLv3 asks that the licence travels with the program, and the libraries the
# build carries each ask for their notice, so both files ride beside the binary
# on both platforms.
LICENCE_FILES=(LICENSE THIRDPARTY.txt)
# The folders a public build leaves out, read from the one file that names them
# and says why, as paths under the project, which is what the export's filters
# are written in.
NOT_PUBLIC_LIST="$SCRIPT_DIR/not-public.txt"
PRESETS="$PROJECT_DIR/export_presets.cfg"
PRESETS_KEPT=""
not_public_folders() {
    sed -e 's/#.*//' -e 's/[[:space:]]*$//' "$NOT_PUBLIC_LIST" | while read -r path; do
        [ -n "$path" ] && printf '%s\n' "${path#sara-godot/}"
    done
}

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    C_DIM=$'\033[38;5;242m'; C_OK=$'\033[38;5;114m'; C_ERR=$'\033[38;5;203m'
    C_BRAND=$'\033[38;5;215m'; C_OFF=$'\033[0m'
else
    C_DIM=""; C_OK=""; C_ERR=""; C_BRAND=""; C_OFF=""
fi
die() { printf '\n%s✗ %s%s\n\n' "$C_ERR" "$1" "$C_OFF" >&2; exit 1; }

# The Python client's modules, read from the one list install.sh and
# draft-release.sh read too.
CLIENT_LIST="$SCRIPT_DIR/client-modules.txt"
[ -f "$CLIENT_LIST" ] || die "packaging/client-modules.txt is missing, and it names the Python client's files."
CLIENT_MODULES=()
while read -r module; do
    [ -n "$module" ] && CLIENT_MODULES+=("$module")
done < <(sed -e 's/#.*//' -e 's/[[:space:]]*$//' "$CLIENT_LIST")
[ "${#CLIENT_MODULES[@]}" -gt 0 ] || die "packaging/client-modules.txt names no file."

# The native modules, each a GDExtension whose two libraries are built here
# from its CMakeLists.txt and never committed: the Linux one natively, the
# Windows one cross-built on Linux with llvm-mingw, both landing in the
# module's bin/ where its .gdextension names them, so the export copies the
# platform's own beside the binary. The JPEG XL codec, modules/sara-jxl, is
# one, and the TIFF reader's LZW unpacker, tiff-lzw in the base modules, the
# other. The sources they are built from, godot-cpp
# and libjxl with the JPEG XL module's patches, and the builds, are kept in
# ~/.cache/sara/native, or SARA_NATIVE_DIR, outside the tree, whose checks
# would otherwise read libjxl's own pages as Sara's. LLVM_MINGW names the
# unpacked llvm-mingw, or else the one on PATH is used. A platform whose
# library fails to build still exports, as a Sara without that module, and
# says so.
JXL_DIR="$PROJECT_DIR/modules/sara-jxl"
LZW_DIR="$PROJECT_DIR/modules/sara-base-modules/tiff-lzw"
NATIVE_DIR="${SARA_NATIVE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/sara/native}"
JXL_JOBS="${JXL_JOBS:-$(nproc 2>/dev/null || echo 4)}"
# A module by its short name: its folder, its library's stem, its
# .gdextension, and the name a line of this script calls it.
native_module() {
    case "$1" in
        jxl) MODULE_DIR="$JXL_DIR"; MODULE_STEM=sara-jxl; MODULE_LIST=sara_jxl.gdextension; MODULE_NAME="jpeg xl" ;;
        lzw) MODULE_DIR="$LZW_DIR"; MODULE_STEM=sara-tiff-lzw; MODULE_LIST=sara_tiff_lzw.gdextension; MODULE_NAME="tiff lzw" ;;
    esac
}
native_library() {
    native_module "$1"
    case "$2" in
        linux) printf '%s/bin/lib%s.linux.template_release.x86_64.so' "$MODULE_DIR" "$MODULE_STEM" ;;
        windows) printf '%s/bin/lib%s.windows.template_release.x86_64.dll' "$MODULE_DIR" "$MODULE_STEM" ;;
    esac
}
# The one place godot-cpp is named, a commit of its master that builds the
# native modules against Godot 4.7.
GODOT_CPP_URL=https://github.com/godotengine/godot-cpp.git
GODOT_CPP_REF=2bb1acf6f8ae1ce96ac7b9ba3a10b499c59c49ec
native_sources() {
    if [ "$1" = jxl ] && [ ! -d "$NATIVE_DIR/libjxl" ]; then
        mkdir -p "$NATIVE_DIR"
        bash "$JXL_DIR/scripts/fetch_libjxl.sh" "$NATIVE_DIR/libjxl.part" || return 1
        mv "$NATIVE_DIR/libjxl.part" "$NATIVE_DIR/libjxl"
    fi
    if [ ! -d "$NATIVE_DIR/godot-cpp" ]; then
        mkdir -p "$NATIVE_DIR"
        # A pinned commit, because a branch moves under the build with no commit
        # here saying so. godot-cpp has no tag for Godot 4.7 (its last is
        # godot-4.5-stable, and master carries the newer API). A
        # godot-4.7-stable tag, once it exists, is what GODOT_CPP_REF should name.
        git init -q "$NATIVE_DIR/godot-cpp.part" || return 1
        git -C "$NATIVE_DIR/godot-cpp.part" fetch -q --depth 1 "$GODOT_CPP_URL" "$GODOT_CPP_REF" || return 1
        git -c advice.detachedHead=false -C "$NATIVE_DIR/godot-cpp.part" checkout -q FETCH_HEAD || return 1
        mv "$NATIVE_DIR/godot-cpp.part" "$NATIVE_DIR/godot-cpp"
    fi
}
# The build folder of module $1 for platform $2, whose source is the module
# folder $3. A CMake cache remembers the source and the output it was
# configured with and refuses any other, so a folder shared by two checkouts
# builds for the first one alone. Each checkout's builds
# therefore stand apart, named after the module, the platform and a short hash
# of the module's own path, while the fetched sources, libjxl and godot-cpp,
# stay shared in NATIVE_DIR. A folder of a checkout that is gone is left alone.
native_build_dir() {
    local stem="$1" path
    [ "$1" = lzw ] && stem=tiff-lzw
    path="$(cd "$3" 2>/dev/null && pwd -P || printf '%s' "$3")"
    printf '%s/%s-%s-%s' "$NATIVE_DIR" "$stem" "$2" "$(printf '%s' "$path" | sha1sum | cut -c1-8)"
}
# Builds module $1 for platform $2, and when it fails names the log of the
# step that failed, the configure's or the build's.
build_native() {
    native_module "$1"
    local module="$1" platform="$2" build started=$SECONDS log
    local toolchain=() extra=() path="$PATH" dir="$MODULE_DIR" name="$MODULE_NAME"
    build="$(native_build_dir "$module" "$platform" "$dir")"
    if [ ! -f "$dir/CMakeLists.txt" ]; then
        printf '%s  note: the %s module is not checked out, git submodule update --init fetches it%s\n' "$C_DIM" "$name" "$C_OFF"
        return 1
    fi
    if [ "$platform" = windows ]; then
        [ -n "${LLVM_MINGW:-}" ] && path="$LLVM_MINGW/bin:$PATH"
        if ! PATH="$path" command -v x86_64-w64-mingw32-clang >/dev/null 2>&1; then
            printf '%s  note: no llvm-mingw, so no Windows %s library. Set LLVM_MINGW to the unpacked toolchain%s\n' "$C_DIM" "$name" "$C_OFF"
            return 1
        fi
        toolchain=(-DCMAKE_TOOLCHAIN_FILE="$dir/cmake/llvm-mingw.cmake")
    fi
    [ "$module" = jxl ] && extra=(-DLIBJXL="$NATIVE_DIR/libjxl")
    printf '  %s%s%s %s library…\n' "$C_DIM" "$name" "$C_OFF" "$platform"
    native_sources "$module" || { printf '%s  note: the %s sources could not be fetched%s\n' "$C_DIM" "$name" "$C_OFF"; return 1; }
    mkdir -p "$build"
    log="$build.configure.log"
    if PATH="$path" cmake -S "$dir" -B "$build" "${toolchain[@]}" -DGODOT_CPP="$NATIVE_DIR/godot-cpp" \
            "${extra[@]}" -DCMAKE_BUILD_TYPE=Release -DGODOTCPP_TARGET=template_release \
            >"$log" 2>&1; then
        log="$build.build.log"
        PATH="$path" cmake --build "$build" -j "$JXL_JOBS" >"$log" 2>&1 && log=""
    fi
    if [ -n "$log" ]; then
        tail -5 "$log"
        printf '%s  note: the %s %s library failed to build, read %s%s\n' "$C_DIM" "$platform" "$name" "$log" "$C_OFF"
        return 1
    fi
    [ -f "$(native_library "$module" "$platform")" ] || return 1
    printf '  %s%s%s %s library in %ss\n' "$C_DIM" "$name" "$C_OFF" "$platform" "$((SECONDS - started))"
}

# Godot loads an extension the project's .godot/extension_list.cfg names, and
# only the editor's scan writes that list. A run with no scan since the build
# would load no native module, and Godot 4.7.2 aborts at the exit of the open
# whose scan first finds a GDExtension (the JPEG XL module's README, "The first
# open of a project"), so the list is written here once a library is built.
list_native() {
    native_module "$1"
    local list="$PROJECT_DIR/.godot/extension_list.cfg" line="res://${MODULE_DIR#"$PROJECT_DIR"/}/$MODULE_LIST"
    [ -f "$MODULE_DIR/$MODULE_LIST" ] || return 0
    grep -qsF "$line" "$list" && return 0
    mkdir -p "$PROJECT_DIR/.godot"
    echo "$line" >> "$list"
}

# The Android export finds the SDK through ANDROID_HOME and its JDK through
# JAVA_HOME, and Godot asks for a JDK 17, so the build says in one line which
# is missing before anything is exported. packaging/android-sdk.sh sets both
# up and its env command prints them. The debug key is the one that script
# made unless GODOT_ANDROID_KEYSTORE_DEBUG_PATH names another, since Godot
# would otherwise make one of its own among the editor files of whoever runs it.
ANDROID_SETUP="$SCRIPT_DIR/android-sdk.sh"
if [ "$PLATFORM" = android ]; then
    [ -n "${ANDROID_HOME:-}" ] && [ -d "$ANDROID_HOME/platform-tools" ] \
        || die "ANDROID_HOME names no Android SDK${ANDROID_HOME:+ at $ANDROID_HOME}. packaging/android-sdk.sh sets one up and its env command prints the line."
    JAVA_VERSION="$([ -n "${JAVA_HOME:-}" ] && "$JAVA_HOME/bin/java" -version 2>&1 || true)"
    [[ "$JAVA_VERSION" == *'version "17.'* ]] \
        || die "JAVA_HOME names no JDK 17${JAVA_HOME:+ at $JAVA_HOME}. packaging/android-sdk.sh sets one up and its env command prints the line."
    if [ -z "${GODOT_ANDROID_KEYSTORE_DEBUG_PATH:-}" ]; then
        eval "$(bash "$ANDROID_SETUP" env | grep KEYSTORE)"
        export GODOT_ANDROID_KEYSTORE_DEBUG_PATH GODOT_ANDROID_KEYSTORE_DEBUG_USER GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD
    fi
    [ -f "$GODOT_ANDROID_KEYSTORE_DEBUG_PATH" ] \
        || die "No debug key at $GODOT_ANDROID_KEYSTORE_DEBUG_PATH. packaging/android-sdk.sh makes one."
fi

if [ "$PLATFORM" = modules ]; then
    failed=0
    for module in jxl lzw; do
        build_native "$module" linux || failed=1
        build_native "$module" windows || failed=1
        list_native "$module"
    done
    [ "$failed" = 0 ] || die "A native module's library failed to build."
    printf '\n  %s✓%s built the JPEG XL and TIFF LZW modules for linux and windows\n\n' "$C_OK" "$C_OFF"
    exit 0
fi
MISSING_STEMS=()
# The native modules are built with CMake for Linux and Windows only, and the
# Android preset leaves their folders out, so an APK starts without them.
NATIVE_MODULES=(jxl lzw)
[ "$PLATFORM" = android ] && NATIVE_MODULES=()
for module in ${NATIVE_MODULES[@]+"${NATIVE_MODULES[@]}"}; do
    build_native "$module" "$PLATFORM" || true
    list_native "$module"
    if [ "$PLATFORM" = windows ] && [ ! -f "$(native_library "$module" windows)" ]; then
        native_module "$module"
        MISSING_STEMS+=("$MODULE_STEM")
        printf '%s  missing: %s%s\n' "$C_ERR" "$(native_library "$module" windows)" "$C_OFF" >&2
    fi
done
if [ "${#MISSING_STEMS[@]}" -gt 0 ] && [ "$WITHOUT_MODULES" = false ]; then
    die "The Windows libraries above are not built, so the zip would open no JPEG XL or LZW TIFF. Set LLVM_MINGW to the unpacked llvm-mingw and build again, or pass --without-modules to zip a Sara without them."
fi

# The Windows libraries the export copies beside the exe, read from the
# windows.x86_64 line of every .gdextension under modules/, the files Godot
# loads them by, so a module added later rides in the zip without a word here.
# Each is printed by its file name, which is the name the export gives it.
windows_libraries() {
    find "$PROJECT_DIR/modules" \( -name godot-cpp -o -name build -o -name .godot \) -prune \
            -o -name '*.gdextension' -type f -print 2>/dev/null | sort | while read -r list; do
        sed -n 's/^[[:space:]]*windows\.x86_64[[:space:]]*=[[:space:]]*"\(.*\)"[[:space:]]*$/\1/p' "$list" \
            | while read -r library; do basename "$library"; done
    done
}

GODOT_BIN="${GODOT_BIN:-}"
if [ -z "$GODOT_BIN" ]; then
    if command -v godot >/dev/null 2>&1; then GODOT_BIN=godot
    elif command -v godot4 >/dev/null 2>&1; then GODOT_BIN=godot4
    else die "Godot not found on PATH. Set GODOT_BIN=/path/to/godot."
    fi
fi

# The version has one source, project.godot, and the commit is whatever HEAD is
# in this checkout. "dirty" means a tracked file has uncommitted changes, so a
# build made mid-edit says so in its own header rather than blaming the commit.
# A source copy has no .git for git to answer from, so it carries the commit it
# was cut at in SOURCE_COMMIT, which the maintainers' source archive writes:
# without it such a build names no commit at all and a bug report from the
# person who built it names none either.
VERSION="$(sed -n 's/^config\/version="\(.*\)"$/\1/p' "$PROJECT_DIR/project.godot")"
[ -n "$VERSION" ] || die "project.godot carries no application/config/version."
COMMIT_FULL="$(git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null || cat "$REPO_ROOT/SOURCE_COMMIT" 2>/dev/null || true)"
COMMIT="${COMMIT_FULL:0:7}"
[ -n "$COMMIT" ] || COMMIT="unknown"
DIRTY=false
if [ -n "$COMMIT_FULL" ] && [ -n "$(git -C "$REPO_ROOT" status --porcelain --untracked-files=no 2>/dev/null)" ]; then
    DIRTY=true
fi
if [ "$PLATFORM" = android ]; then
    APK_SUFFIX="$KIND"
    [ "$PUBLIC" = true ] && APK_SUFFIX="public-$KIND"
    OUT_BIN_NAME="sara-android-v$VERSION-$COMMIT-$APK_SUFFIX.apk"
    OUT_BIN="$OUT_DIR/$OUT_BIN_NAME"
fi

# The Android export reads and writes editor settings, so it gets a config
# folder of its own and the Godot settings of whoever runs it are never written.
GODOT_ENV=()
if [ "$PLATFORM" = android ]; then
    GODOT_ENV=(env "XDG_CONFIG_HOME=${XDG_CONFIG_HOME:-$HOME/.config}/sara/android-godot")
    mkdir -p "${GODOT_ENV[1]#XDG_CONFIG_HOME=}"
fi

printf '\n  %sSara%s %sbuild%s\n' "$C_BRAND" "$C_OFF" "$C_DIM" "$C_OFF"
printf '  %sgodot%s   %s\n' "$C_DIM" "$C_OFF" "$(command -v "$GODOT_BIN" || echo "$GODOT_BIN")"
printf '  %spreset%s  %s\n' "$C_DIM" "$C_OFF" "$PRESET"
printf '  %sbuild%s   %s%s\n' "$C_DIM" "$C_OFF" "$KIND" "$([ "$PUBLIC" = true ] && printf ', public')"
printf '  %soutput%s  %s\n' "$C_DIM" "$C_OFF" "$OUT_BIN"

# Export templates are a separate download from the editor, and their absence
# fails deep inside the export with a much less obvious message. The folder is
# the editor's version without its build and hash ("4.7.2.stable"), and the
# engine inside the binary is the template's, not the editor's, so a folder
# holding another version's templates under the right name builds a Sara whose
# About window names the other version. version.txt inside it is what the
# templates really are.
GODOT_VERSION="$("$GODOT_BIN" --version 2>/dev/null | head -1 | cut -d. -f1-3)"
TEMPLATE_NAME="$("$GODOT_BIN" --version 2>/dev/null | head -1 | sed -E 's/\.[a-z_]+\.[0-9a-f]+$//')"
TEMPLATE_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/godot/export_templates/$TEMPLATE_NAME"
if [ ! -d "$TEMPLATE_DIR" ]; then
    printf '%s  note: no export templates at %s, so the export fails unless a preset names its own. ./packaging/install-templates.sh installs them%s\n' \
        "$C_DIM" "$TEMPLATE_DIR" "$C_OFF"
elif [ -f "$TEMPLATE_DIR/version.txt" ] && [ "$(tr -d '[:space:]' < "$TEMPLATE_DIR/version.txt")" != "$TEMPLATE_NAME" ]; then
    die "the export templates in $TEMPLATE_DIR are $(tr -d '[:space:]' < "$TEMPLATE_DIR/version.txt"), not $TEMPLATE_NAME. Install the templates of the editor's own version with ./packaging/install-templates.sh."
fi

mkdir -p "$OUT_DIR"

EXPORT_LOG="$(mktemp)"
# The export presets a public build narrows are put back whatever happens, the
# way the stamp is removed, so a failed export leaves no module out of the next.
restore_presets() { [ -z "$PRESETS_KEPT" ] || mv -f "$PRESETS_KEPT" "$PRESETS"; }
trap 'rm -f "$EXPORT_LOG" "$STAMP" "$CHANGELOG_COPY" "$CATALOGUE"; restore_presets' EXIT

[ -f "$CHANGELOG" ] || die "CHANGELOG.md is missing from the repository root."
cp "$CHANGELOG" "$CHANGELOG_COPY"
[ -f "$AGENT_GUIDE" ] || die "packaging/agent-guide.md is missing."
[ -f "$PAINTER_GUIDE" ] || die "packaging/painter-guide.txt is missing."
PYTHON="$(command -v python3 || command -v python || true)"
[ -n "$PYTHON" ] || die "Python not found on PATH, and the door's step catalogue is written by it."
"$PYTHON" "$PROJECT_DIR/scripts/sara_steps.py" --json > "$CATALOGUE" \
    || die "scripts/sara_steps.py --json failed, so the build would carry no step catalogue."

BUILT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
# The commit of each module repository under the project, by its folder, so the
# About dialog and the loader name what a module was built from.
MODULE_COMMITS="$(git -C "$REPO_ROOT" submodule --quiet foreach 'printf "\"%s\": \"%s\", " "${sm_path#sara-godot/}" "$(git rev-parse --short=7 HEAD)"' 2>/dev/null || true)"
printf '{\n  "version": "%s",\n  "commit": "%s",\n  "commit_full": "%s",\n  "dirty": %s,\n  "built": "%s",\n  "build": "%s",\n  "modules": {%s}\n}\n' \
    "$VERSION" "$COMMIT" "$COMMIT_FULL" "$DIRTY" "$BUILT" "$KIND" "${MODULE_COMMITS%, }" > "$STAMP"
printf '  %sstamp%s   v%s  %s%s%s\n\n' "$C_DIM" "$C_OFF" "$VERSION" "$COMMIT" \
    "$([ "$DIRTY" = true ] && printf ' (uncommitted changes)')" ""

# --import first: a clean checkout has no .godot/ cache, and exporting without
# one silently produces a build missing every imported asset.
printf '  %simporting resources…%s\n' "$C_DIM" "$C_OFF"
${GODOT_ENV[@]+"${GODOT_ENV[@]}"} "$GODOT_BIN" --headless --path "$PROJECT_DIR" --import >/dev/null 2>&1 || true

# A public build adds each folder not-public.txt names to both presets' exclude
# filter for the length of the export. The export applies the exclude filter
# after the include filter, so neither the module's scripts nor its kernel nor
# the tables the include filter names reach the pack.
#
# The presets file itself goes with them, because the lines this adds spell the
# left-out folders out by name and the export packs every file under the
# project that no filter catches, export_presets.cfg among them. Without this
# a public exe would hold no file of the module and still name it three times,
# in its own packed copy of the narrowed presets. Nothing in a
# build reads the presets, so a public build is the only one that has to drop
# them and the build a tester takes keeps them.
if [ "$PUBLIC" = true ]; then
    [ -f "$NOT_PUBLIC_LIST" ] || die "packaging/not-public.txt is missing, so a public build cannot tell what to leave out."
    [ -f "$PRESETS" ] || die "sara-godot/export_presets.cfg is missing."
    EXCLUDED=", $(basename "$PRESETS")"
    while read -r folder; do
        EXCLUDED="$EXCLUDED, $folder/*"
        printf '  %sleft out%s %s\n' "$C_DIM" "$C_OFF" "$folder"
    done < <(not_public_folders)
    PRESETS_KEPT="$(mktemp)"
    cp "$PRESETS" "$PRESETS_KEPT"
    sed -i "s|^exclude_filter=\"\(.*\)\"\$|exclude_filter=\"\1$EXCLUDED\"|" "$PRESETS"
fi

printf '  %sexporting…%s\n' "$C_DIM" "$C_OFF"
if ! ${GODOT_ENV[@]+"${GODOT_ENV[@]}"} "$GODOT_BIN" --headless --path "$PROJECT_DIR" --export-"$KIND" "$PRESET" "$OUT_BIN" >"$EXPORT_LOG" 2>&1; then
    tail -20 "$EXPORT_LOG" >&2
    die "Export failed."
fi
restore_presets
PRESETS_KEPT=""

# Godot can exit 0 having written nothing useful, so check the artefact itself.
if [ "$PLATFORM" = windows ] || [ "$PLATFORM" = android ]; then
    # A PE image or an APK carries no execute bit on the machine that exported it, so
    # here only the file's presence says anything.
    [ -f "$OUT_BIN" ] || die "Export reported success but $OUT_BIN is missing."
else
    [ -x "$OUT_BIN" ] || die "Export reported success but $OUT_BIN is missing."
fi
SIZE_MB=$(( $(stat -c%s "$OUT_BIN") / 1024 / 1024 ))
[ "$SIZE_MB" -gt 10 ] || die "$OUT_BIN is only ${SIZE_MB}MB - the PCK was probably not embedded."

# The stamp goes beside the binary after the export, never before it: it is
# packed under res:// and this copy is what a person reads next to the files.
mv "$STAMP" "$OUT_DIR/build_info.json"

if [ "$PLATFORM" = android ]; then
    # The APK carries Godot's library for both architectures the preset names
    # and no file of a module the preset leaves out, read from the APK itself
    # since a preset edited by the editor can lose either quietly.
    LISTING="$(unzip -l "$OUT_BIN")"
    for abi in arm64-v8a x86_64; do
        grep -q "lib/$abi/libgodot_android.so" <<<"$LISTING" || die "$OUT_BIN carries no lib/$abi/libgodot_android.so."
    done
    if grep -E 'modules/(sara-jxl|sara-base-modules/linux-pen|sara-base-modules/tiff-lzw)/' <<<"$LISTING" >&2; then
        die "$OUT_BIN carries the files above of a module the Android preset leaves out."
    fi
    # A painter has the tablet and no adb, so the guide beside the APK is how
    # they learn how to install it and where Sara writes its log and notes.
    # Its absence already failed the build above, for every platform.
    cp "$PAINTER_GUIDE" "$OUT_DIR/README.txt"
elif [ "$PLATFORM" = windows ]; then
    # Godot writes the console wrapper only when the preset asks for one, and
    # it asks for it on both builds, debug/export_console_wrapper=2. The alpha
    # needs it: a crash in a stranger's hands is
    # read from that console. A console-less zip that nobody notices is exactly
    # what the three hand exports shipped, so its absence fails the build here.
    [ -f "$CONSOLE_WRAPPER" ] || die "The export wrote no $CONSOLE_WRAPPER."

    # The alpha hands a stranger a zip rather than an installer, and the stamp
    # rides inside it so a lone download can still name the commit it came
    # from. The version and the commit are in the zip's own name too, so two
    # zips on one disk do not have to be told apart by their contents.
    #
    # A student starts Sara with its door from the launcher and attaches with
    # sara.py, both beside the exe, so the first cell of a notebook finds a
    # Sara that listens. That first cell imports sara_notebook, the %%gmacs
    # magic, and the array that stays on the GPU is sara_array, so both ride
    # beside sara.py and are copied the way it is. sara.live imports sara_live
    # at its first call, which reads PARAMS through sara_params, and
    # doc.documents imports sara_documents and sara.bench and sara.check
    # sara_measure, so those four ride with them, and sara_start is how sara.py
    # starts a Sara that outlives the kernel. The
    # repository keeps every text file with LF endings, and
    # the launcher is written out with CRLF, the endings cmd.exe reads a batch
    # file by.
    sed 's/\r*$/\r/' "$SCRIPT_DIR/$DOOR_LAUNCHER" > "$OUT_DIR/$DOOR_LAUNCHER"
    for module in "${CLIENT_MODULES[@]}"; do
        cp "$PROJECT_DIR/scripts/$module" "$OUT_DIR/$module"
    done
    sed 's/\r*$/\r/' "$AGENT_GUIDE" > "$OUT_DIR/AGENTS.md"
    sed 's/\r*$/\r/' "$PAINTER_GUIDE" > "$OUT_DIR/README.txt"
    for notice in "${LICENCE_FILES[@]}"; do
        sed 's/\r*$/\r/' "$REPO_ROOT/$notice" > "$OUT_DIR/$notice"
    done
    #
    # The module libraries the export put beside the exe ride in it as well,
    # because a folder that has them and a zip that does not is a Sara whose
    # modules are missing on the machine that unpacks it. One a .gdextension
    # names and the export did not copy fails the build rather than leaving
    # the zip short.
    LIBRARIES=()
    while read -r library; do
        [ -n "$library" ] || continue
        [ -f "$OUT_DIR/$library" ] || die "A .gdextension names $library for Windows, and the export put no $OUT_DIR/$library beside the exe."
        LIBRARIES+=("$library")
    done < <(windows_libraries)
    SUFFIX=""
    for stem in ${MISSING_STEMS[@]+"${MISSING_STEMS[@]}"}; do SUFFIX="$SUFFIX-without-$stem"; done
    [ "$PUBLIC" = true ] && SUFFIX="$SUFFIX-public"
    # The build is the last word of the name, so a painter handed both zips
    # takes the release one without opening either.
    ZIP="$OUT_DIR/sara-windows-x86_64-v$VERSION-$COMMIT$SUFFIX-$KIND.zip"
    rm -f "$OUT_DIR"/sara-windows-x86_64-v"$VERSION"-"$COMMIT"*-"$KIND".zip
    ( cd "$OUT_DIR" && zip -q "$ZIP" "$OUT_BIN_NAME" "$(basename "$CONSOLE_WRAPPER")" build_info.json \
        "$DOOR_LAUNCHER" "${CLIENT_MODULES[@]}" AGENTS.md README.txt \
        "${LICENCE_FILES[@]}" ${LIBRARIES[@]+"${LIBRARIES[@]}"} )
    printf '  %szip%s     %s\n' "$C_DIM" "$C_OFF" "$(basename "$ZIP")"
    for library in ${LIBRARIES[@]+"${LIBRARIES[@]}"}; do
        printf '  %slibrary%s %s\n' "$C_DIM" "$C_OFF" "$library"
    done
else
    # The wrapper lives beside the binary, and the installer copies both, so a
    # rebuild must refresh it too or an edit here never reaches a launch.
    install -m 755 "$SCRIPT_DIR/sara.sh" "$OUT_DIR/sara.sh"
    # The client rides beside the binary as it does in the Windows zip, from
    # the same list, so a Linux painter with a Python of their own attaches
    # a notebook to the Sara they started with its door.
    for module in "${CLIENT_MODULES[@]}"; do
        cp "$PROJECT_DIR/scripts/$module" "$OUT_DIR/$module"
    done
    cp "$AGENT_GUIDE" "$OUT_DIR/AGENTS.md"
    cp "$PAINTER_GUIDE" "$OUT_DIR/README.txt"
    for notice in "${LICENCE_FILES[@]}"; do
        cp "$REPO_ROOT/$notice" "$OUT_DIR/$notice"
    done

    cp "$PROJECT_DIR/ui/icon.png" "$OUT_DIR/icon.png" 2>/dev/null || true
fi

printf '\n  %s✓%s built %s%s%s for %s  %s(%s build, %s MB, v%s at %s)%s\n\n' \
    "$C_OK" "$C_OFF" "$C_BRAND" "$(basename "$OUT_BIN")" "$C_OFF" "$PLATFORM" \
    "$C_DIM" "$KIND" "$SIZE_MB" "$VERSION" "$COMMIT" "$C_OFF"
