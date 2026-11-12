#!/usr/bin/env bash
#
# Sets up what build.sh android needs and what an emulator start of the APK
# needs, with no sudo and nothing outside one folder under the home directory:
# the Android SDK's command-line tools, platform tools, build tools, one
# platform, the emulator and one x86_64 system image with Google APIs, from
# Google, and a JDK 17 from Adoptium, since Godot's Android export asks for 17
# and the machine's default Java may be another. The SDK's
# licences are accepted through sdkmanager, because whoever runs this has asked
# for an Android build and the export cannot start without them. It also makes the debug key the APK is
# signed with, kept here and never in the repository, and an emulator, an AVD,
# for the start that proves the APK runs.
#
#   packaging/android-sdk.sh            sets everything up, or says it is there
#   packaging/android-sdk.sh env        prints the exports build.sh android reads
#   packaging/android-sdk.sh smoke APK OUT
#                                       starts the emulator, installs APK, starts
#                                       Sara, paints a stroke and writes the logs
#                                       and two screenshots into OUT
#
# SARA_ANDROID_DIR moves the whole folder, which is ~/.local/share/sara/android
# unless it is set. Running it a second time downloads nothing it already has.
set -euo pipefail

ROOT="${SARA_ANDROID_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/sara/android}"
SDK="$ROOT/sdk"
JDK="$ROOT/jdk-17"
KEYSTORE="$ROOT/debug.keystore"
AVD_HOME="$ROOT/avd"
AVD_NAME="sara-x86_64"

# The versions are pinned, so a second machine gets the SDK this one tested.
# build-tools and the platform are the ones Godot 4.7's export targets.
CMDLINE_TOOLS_ZIP="commandlinetools-linux-13114758_latest.zip"
PLATFORM="platforms;android-35"
BUILD_TOOLS="build-tools;35.0.1"
SYSTEM_IMAGE="system-images;android-35;google_apis;x86_64"
ADOPTIUM="https://api.adoptium.net/v3/binary/latest/17/ga/linux/x64/jdk/hotspot/normal/eclipse"

# The keystore's alias and password are Android's own debug convention, which
# says nothing secret, so they live here in the open.
KEY_ALIAS="androiddebugkey"
KEY_PASSWORD="android"

say() { printf '  %s\n' "$1"; }
die() { printf '\n✗ %s\n\n' "$1" >&2; exit 1; }

print_env() {
    printf 'export ANDROID_HOME=%q\n' "$SDK"
    printf 'export JAVA_HOME=%q\n' "$JDK"
    printf 'export GODOT_ANDROID_KEYSTORE_DEBUG_PATH=%q\n' "$KEYSTORE"
    printf 'export GODOT_ANDROID_KEYSTORE_DEBUG_USER=%q\n' "$KEY_ALIAS"
    printf 'export GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD=%q\n' "$KEY_PASSWORD"
}

setup() {
    mkdir -p "$ROOT"
    command -v curl >/dev/null || die "curl is needed to download the SDK and the JDK."
    command -v unzip >/dev/null || die "unzip is needed to unpack the SDK's command-line tools."

    if [ ! -x "$JDK/bin/java" ]; then
        say "JDK 17 from Adoptium…"
        rm -rf "$JDK.part" && mkdir -p "$JDK.part"
        curl -fsSL "$ADOPTIUM" | tar -xz -C "$JDK.part" --strip-components=1
        mv "$JDK.part" "$JDK"
    fi
    [[ "$("$JDK/bin/java" -version 2>&1 || true)" == *'version "17.'* ]] || die "$JDK/bin/java is not a Java 17."

    if [ ! -x "$SDK/cmdline-tools/latest/bin/sdkmanager" ]; then
        say "the SDK's command-line tools…"
        local zip="$ROOT/$CMDLINE_TOOLS_ZIP"
        curl -fsSL -o "$zip" "https://dl.google.com/android/repository/$CMDLINE_TOOLS_ZIP"
        rm -rf "$SDK/cmdline-tools" && mkdir -p "$SDK/cmdline-tools"
        unzip -q "$zip" -d "$SDK/cmdline-tools"
        mv "$SDK/cmdline-tools/cmdline-tools" "$SDK/cmdline-tools/latest"
        rm -f "$zip"
    fi

    local sdkmanager=("$SDK/cmdline-tools/latest/bin/sdkmanager" "--sdk_root=$SDK")
    say "accepting the SDK's licences…"
    yes | JAVA_HOME="$JDK" "${sdkmanager[@]}" --licenses >/dev/null 2>&1 || true
    say "platform tools, build tools, the platform, the emulator and the system image…"
    JAVA_HOME="$JDK" "${sdkmanager[@]}" "platform-tools" "$BUILD_TOOLS" "$PLATFORM" "emulator" "$SYSTEM_IMAGE" \
        > "$ROOT/sdkmanager.log" 2>&1 || { tail -5 "$ROOT/sdkmanager.log" >&2; die "sdkmanager failed, its log is $ROOT/sdkmanager.log"; }

    if [ ! -f "$KEYSTORE" ]; then
        say "the debug key…"
        "$JDK/bin/keytool" -genkeypair -keystore "$KEYSTORE" -storepass "$KEY_PASSWORD" -keypass "$KEY_PASSWORD" \
            -alias "$KEY_ALIAS" -dname "CN=Android Debug,O=Android,C=US" -keyalg RSA -keysize 2048 -validity 9999 \
            >/dev/null 2>&1 || die "keytool could not make $KEYSTORE."
    fi

    if [ ! -f "$AVD_HOME/$AVD_NAME.ini" ]; then
        say "the emulator's device, $AVD_NAME…"
        mkdir -p "$AVD_HOME"
        echo no | ANDROID_AVD_HOME="$AVD_HOME" ANDROID_HOME="$SDK" JAVA_HOME="$JDK" \
            "$SDK/cmdline-tools/latest/bin/avdmanager" create avd -n "$AVD_NAME" -k "$SYSTEM_IMAGE" -d pixel_tablet \
            >/dev/null || die "avdmanager could not make the device $AVD_NAME."
        # 4 GB for the guest, so the emulator leaves room for the rest of the machine.
        sed -i 's/^hw\.ramSize=.*/hw.ramSize=4096/' "$AVD_HOME/$AVD_NAME.avd/config.ini"
        grep -q '^hw.ramSize=' "$AVD_HOME/$AVD_NAME.avd/config.ini" || echo 'hw.ramSize=4096' >> "$AVD_HOME/$AVD_NAME.avd/config.ini"
    fi

    printf '\n✓ the Android SDK, a JDK 17 and the debug key are in %s\n' "$ROOT"
    printf '  build.sh android finds the SDK and the JDK through the first two, and takes\n'
    printf '  the key from here when the third is unset:\n\n'
    print_env | sed 's/^/    /'
    printf '\n'
}

# Starts the emulator with no window, under a memory cap of its own so
# it leaves room for the rest of the machine, installs the APK, starts Sara, waits a
# minute reading the log, drags a stylus across the canvas between two
# screenshots and stops the emulator again. Every file lands in OUT.
smoke() {
    local apk="$1" out="$2"
    [ -f "$apk" ] || die "No APK at $apk."
    [ -x "$SDK/emulator/emulator" ] || die "No emulator in $SDK, run packaging/android-sdk.sh first."
    mkdir -p "$out"
    local adb="$SDK/platform-tools/adb" port=5584 package
    local serial="emulator-$port"
    package="$("$SDK/build-tools/${BUILD_TOOLS#build-tools;}/aapt2" dump packagename "$apk")"
    ANDROID_AVD_HOME="$AVD_HOME" ANDROID_HOME="$SDK" ANDROID_SDK_ROOT="$SDK" \
        systemd-run --user --scope -q -p MemoryMax=6G -p MemorySwapMax=0 \
        "$SDK/emulator/emulator" -avd "$AVD_NAME" -port "$port" -no-window -no-audio -no-boot-anim \
        -no-snapshot -memory 4096 -gpu "${SARA_EMULATOR_GPU:-host}" -feature Vulkan \
        > "$out/emulator.log" 2>&1 &
    EMULATOR_PID=$!
    # Stopped however the run ends, by the id kept when it started.
    trap 'kill "$EMULATOR_PID" 2>/dev/null; wait "$EMULATOR_PID" 2>/dev/null || true' EXIT
    say "the emulator, pid $EMULATOR_PID, booting…"
    "$adb" -s "$serial" wait-for-device
    local waited=0
    until [ "$("$adb" -s "$serial" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = 1 ]; do
        sleep 2; waited=$((waited + 2))
        [ "$waited" -lt 300 ] || die "The emulator did not boot in five minutes, its log is $out/emulator.log"
    done
    say "booted in about ${waited}s, installing $package…"
    "$adb" -s "$serial" install -r "$apk" > "$out/install.log" 2>&1 || { cat "$out/install.log" >&2; die "adb install failed."; }
    "$adb" -s "$serial" logcat -c
    "$adb" -s "$serial" shell monkey -p "$package" -c android.intent.category.LAUNCHER 1 > "$out/start.log" 2>&1
    say "started, reading the log for 60 seconds…"
    sleep "${SARA_SMOKE_WAIT:-60}"
    "$adb" -s "$serial" exec-out screencap -p > "$out/started.png"
    "$adb" -s "$serial" shell uiautomator dump /sdcard/window.xml >/dev/null 2>&1 \
        && "$adb" -s "$serial" exec-out cat /sdcard/window.xml > "$out/window.xml"
    local size w h got_it
    size="$("$adb" -s "$serial" shell wm size | tr -d '\r' | sed -n 's/.*: \([0-9]*x[0-9]*\)$/\1/p' | tail -1)"
    w="${size%x*}"; h="${size#*x}"
    # Android's own note on a full-screen app, "Viewing full screen", sits
    # over the top of the window until its Got it is pressed.
    got_it="$(sed 's/></>\n</g' "$out/window.xml" 2>/dev/null | grep 'text="Got it"' \
        | sed -n 's/.*bounds="\[\([0-9]*\),\([0-9]*\)\]\[\([0-9]*\),\([0-9]*\)\]".*/\1 \2 \3 \4/p' | head -1 || true)"
    if [ -n "$got_it" ]; then
        read -r x1 y1 x2 y2 <<<"$got_it"
        "$adb" -s "$serial" shell input tap $(((x1 + x2) / 2)) $(((y1 + y2) / 2))
        sleep 2
    fi
    # Sara opens on its welcome window, which on a tablet's screen covers the
    # canvas, and a press on the bar outside it puts it away, so one tap on
    # the empty right of the bar comes before the stroke.
    "$adb" -s "$serial" shell input tap $((w * 80 / 100)) 15
    sleep 3
    "$adb" -s "$serial" exec-out screencap -p > "$out/before.png"
    "$adb" -s "$serial" shell input stylus swipe $((w * 35 / 100)) $((h * 40 / 100)) $((w * 65 / 100)) $((h * 60 / 100)) 1500
    sleep 3
    "$adb" -s "$serial" exec-out screencap -p > "$out/after.png"
    "$adb" -s "$serial" logcat -d > "$out/logcat.txt"
    "$adb" -s "$serial" shell pidof "$package" > "$out/pid.txt" 2>&1 || true
    "$adb" -s "$serial" emu kill >/dev/null 2>&1 || true
    "$adb" kill-server >/dev/null 2>&1 || true
    say "the log, the two screenshots and the emulator's log are in $out"
}

case "${1:-setup}" in
    setup) setup ;;
    env) print_env ;;
    smoke) [ $# -eq 3 ] || die "smoke takes the APK and a folder for what it writes."; smoke "$2" "$3" ;;
    *) die "Unknown command \"$1\". The commands are setup, the default, env and smoke." ;;
esac
