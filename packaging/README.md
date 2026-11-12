# Packaging

Builds Sara and installs it into your desktop environment. Everything lands under
`~/.local`, so nothing needs root and `uninstall.sh` reverses it exactly.

```bash
./packaging/install.sh            # builds if the build is not of this checkout, then installs the copy and the desktop entry
./packaging/install.sh --no-build # installs the build in build/l as it stands, and says which commit that is
./packaging/install.sh --force    # installs over an install from before builds/ while a Sara runs from it
./packaging/install.sh --pen-rule # only prints the pen module's udev rule and the one sudo command that installs it
./packaging/build.sh              # rebuild only, into build/l/, the Linux half
./packaging/build.sh windows      # the Windows half, into build/w/, zipped with the module libraries
./packaging/build.sh modules      # only the native modules' Linux and Windows libraries, no export
./packaging/uninstall.sh          # remove the installed copy, the desktop entry and the icons
```

`install.sh` reads `build/l/build_info.json` and compares its commit with the
checkout's `HEAD`. It runs `build.sh` first, saying why in one line, when
there is no binary, no stamp, a stamp at another commit, a stamp that records
uncommitted changes, or a tree with uncommitted changes now. Otherwise it
installs what is there. A caller that built on purpose and wants that build
installed whatever the tree says passes `--no-build`, which still builds when
there is no binary at all. `rebuild-and-launch.sh` passes it, because it has
just built.

The Python client travels with it too. `build.sh linux` copies the files
`client-modules.txt` lists beside `sara.x86_64` and `install.sh` installs them
into `~/.local/lib/sara` beside `sara.sh`, so `sara.py` is next to the Sara it
attaches to. No Python is shipped, the client needs numpy and a notebook
IPython and ipywidgets, which you bring in your own. `draft-release.sh` also
attaches the client as its own zip.

The native modules' libraries travel with the binary: `install.sh` copies
every `.so` the export left in `build/l` into the new build folder beside
`sara.x86_64`, where Godot loads them from. It then reads the `linux.x86_64`
line of every `.gdextension` under `sara-godot/modules` and prints one warning
line naming the module whose library is not in the installed folder. A missing
library warns and the install goes on, because `build.sh` exports a Sara
without a module whose library did not build and says so then.

Sara then appears in the application menu and as `sara` on the command line.
**Right-click the menu entry for "Rebuild from source and launch"**, which
reruns the export against the current working tree, installs the result over the
installed copy and starts it. That is the fast loop when you are changing code
and want to test the real build rather than the editor. **"Launch with
console"** beside it starts Sara in a terminal, so every error it prints is on
screen, and the window stays open after Sara exits.

## The pen's nodes

Under Wayland Godot never reports the pen's upper barrel button let go in the
air, so Sara's `linux_pen` module reads it from the kernel, off the tablet's pen
node under `/dev/input/`, which is often `root:input 0660`. **`install.sh`
ends by offering the udev rule `70-sara-pen.rules`** that gives the user at the
seat the tablet's nodes through `uaccess`, and prints the one `sudo` command
that installs it and applies it to the nodes already there. It never runs
`sudo` itself, and once the rule is in it says so in one line. Joining the
`input` group is not offered, because it gives every program the keyboard as
well. Without the rule Sara works as before, logs one line naming the node, and
the Tablet page's Middle row says the module is off and how to turn it on.
`sudo rm /etc/udev/rules.d/70-sara-pen.rules` takes the rule out again.

## Where it lands

| Path | What |
|---|---|
| `~/.local/lib/sara/builds/<time>-<commit>/sara.x86_64` | The binary, PCK embedded, one folder per install |
| `~/.local/lib/sara/builds/<time>-<commit>/lib*.so` | The native modules' libraries, beside the binary they load into |
| `~/.local/lib/sara/sara.x86_64` | A link to the newest of those, which the wrapper starts |
| `~/.local/lib/sara/sara.sh` | The launch wrapper the desktop entry runs |
| `~/.local/lib/sara/build_info.json` | A link to the newest build's version, commit and build time |
| `~/.local/bin/sara` | A symlink to the wrapper, so `sara` works from a terminal |
| `~/.local/share/applications/sara.desktop` | The desktop entry |
| `~/.local/share/icons/hicolor/...` | The icon, a PNG |

`SARA_PREFIX` replaces `~/.local` for all of them, which is how the installer is
tested without touching a real profile.

The install is a copy and not the checkout itself, so moving the checkout does
not break the menu entry and `git clean -x` does not delete the application.
The only line that still points into the checkout is the Rebuild action, because
a rebuild needs the source. Move the repository and only that action breaks,
until `install.sh` is run again.

## Installing while Sara is running

Installing while Sara runs is safe, and that Sara keeps the build it started
on. A running Sara reads its embedded pack again by path whenever it loads a
resource it has not loaded yet, and that path is the one the engine read off
`/proc/self/exe` at start, which the kernel resolves through the link to the
real file in the build's own `builds/` folder. So each install puts the new binary in a
folder of its own and turns the `sara.x86_64` link to it. Every later launch,
from the menu or `sara`, starts the new build, and the Sara already open goes
on reading its own files. A binary written over in place makes the old Sara read
the new file's pack at the old offsets and crash on a palette.

Each install deletes the older folders, all but the ones a running Sara of
yours still starts from, which it lists as kept, so the next install after that
Sara quits clears them.

An install from before `builds/` left `sara.x86_64` a plain file, and a Sara
running from it would read the link. The first install over one refuses while
such a Sara runs, prints its pid and how to close it, and changes nothing.
`--force` installs anyway, and that Sara may crash. Every install after the
first needs no flag.

`sara --version` prints one line, the version and the commit, `Sara 0.17.3
(5cd5c8c)`, with ` dirty` before the bracket's end for an export of a tree with
edits in it, and exits with status 0. The wrapper starts the binary with
`--headless` for it, so no window opens, and holds stderr back unless the run
fails. On Windows there is no wrapper, and `sara.exe --version` is Godot's own
flag.

## The build knows what it is

`build.sh` writes `build_info.json` into the project just before the export,
holding the version from `project.godot`, the commit, whether tracked files had
uncommitted changes, and the time. The export packs it, and the script then
moves it beside the binary and out of the project, so an editor run never sees
a stamp from last week's build. `core/app/sa_build_info.gd` reads it at startup and
the boot header prints it:

```
Build        v0.1.0  ·  ae1b0fa  ·  exported 2026-09-02 01:12 UTC
```

An editor run has no stamp and reads `.git/HEAD` instead, printing "working
tree, not exported" after the commit, because a commit named by a binary and
one named by a tree with edits in it are different claims. The version has one
source, `project.godot`.

## The native modules

Sara has two native modules, GDExtensions whose libraries are built by
`build.sh` and never committed: `sara-godot/modules/sara-jxl`, the JPEG XL
codec, and `tiff-lzw` in `sara-godot/modules/sara-base-modules`, the TIFF
reader's LZW unpacker, which needs godot-cpp alone. Each
`build.sh linux` or `build.sh windows` builds that platform's libraries before
the export, into each module's `bin/` where its `.gdextension` names them, so
the export carries them beside the binary. `build.sh modules` builds all four
libraries and exports nothing, and fails when any does not build.

The sources, libjxl with the module's patches fetched by the module's
`scripts/fetch_libjxl.sh` and godot-cpp cloned from GitHub, and the builds
themselves are kept in `~/.cache/sara/native`, or `SARA_NATIVE_DIR`, outside
the tree. `JXL_JOBS` sets the build's jobs and defaults to the machine's
cores. The Windows library is cross-built on Linux with llvm-mingw:
`LLVM_MINGW` names the unpacked toolchain, or else the
`x86_64-w64-mingw32-clang` on `PATH` is used. A Linux library that fails to
build, or a clone with no module checked out, still exports, as a Sara without
JPEG XL or with LZW unpacked in GDScript, and the build says so in a dim note
line.

The Windows zip is what a stranger is handed, so `build.sh windows` zips every
library a `.gdextension` under `sara-godot/modules/` names for
`windows.x86_64`, from beside the exe where the export put it, and fails
before the export when a module's Windows library is not built, naming each
missing library and `LLVM_MINGW`. `build.sh windows
--without-modules` goes on without them, and the zip's name then ends in
`-without-sara-jxl`, `-without-sara-tiff-lzw` or both, so a short zip is
never taken for a whole one. A CMake build folder remembers the checkout it
was configured from and refuses any other, so each checkout builds into
folders of its own, `jxl-linux-<hash>` or `tiff-lzw-windows-<hash>`, the hash
being a short one of the module's path, while libjxl and godot-cpp stay one
shared copy. Folders of a checkout that is gone are left
where they are. A library that fails to build names the configure or build
log to read beside its folder. Once a library is built, the script adds
its module to `sara-godot/.godot/extension_list.cfg`, which
Godot reads to load an extension and which only the editor's scan writes
otherwise.

## Files

| File | Purpose |
|---|---|
| `build.sh` | Stamps and exports a debug build for `linux` or `windows`, `build/l/sara.x86_64` or the zipped `build/w/`, and with a second argument `release` the release build into `build/l-release/` or `build/w-release/`, via the matching preset, building the native modules' libraries first and zipping the Windows ones. The word `public` leaves out what `not-public.txt` names, into a folder ending in `-public`. `windows --without-modules` zips a Sara without the libraries that did not build. `modules` builds the module's two libraries alone |
| `install-templates.sh` | Downloads the export templates of the editor on `PATH` (about 1.3 GB) into the folder Godot reads them from, naming the release from `godot --version`. `--print` shows the address and the folder and changes nothing, `--from FILE` uses a `.tpz` already downloaded, `--all` keeps every platform |
| `check_crash_report.sh` | Crashes the built binary on purpose and fails unless the report names a script line |
| `install.sh` | Copies the build under the prefix, then the desktop entry, icons and `sara` command, and offers the pen's udev rule |
| `70-sara-pen.rules` | The udev rule that gives the seat's user the tablet's nodes, which `install.sh` prints the command for |
| `uninstall.sh` | Removes what `install.sh` created, the client modules with the rest of the lib folder |
| `client-modules.txt` | The eight Python client files of `sara-godot/scripts`, the one list `build.sh`, `install.sh` and `draft-release.sh` read, so the Linux build, the Windows zip and the client download cannot drift |
| `client-readme.txt` | The `README.txt` of the separate client download, what it is, what Python it needs and how to attach |
| `appimage.sh` | Wraps `build/l/` into `build/a/Sara-<version>-x86_64.AppImage`, the Linux half of a release |
| `sara.sh` | Launch wrapper, installed next to the binary. A start with files while your Sara runs hands them to it as tabs, from a windowless run, and exits |
| `sara-console.sh` | Backs the desktop file's console action: `sara.sh` in a terminal that stays open after Sara exits |
| `sara-with-door.cmd` | The Windows zip's launcher that starts `sara.exe` with its door |
| `rebuild-and-launch.sh` | Backs the desktop file's Rebuild action: build, install, launch |
| `sara.desktop.in` | Template. Absolute paths are substituted at install time |
| `sara-mime.xml` | The MIME type of a Sara document, which `install.sh` puts in the user's MIME database and `uninstall.sh` removes |
| `agent-guide.md` | The guide for a coding agent, which `build.sh` puts beside the binary as `AGENTS.md` |
| `draft-release.sh` | Drafts the GitHub Release, the four builds, the AppImage and the Android debug APK, and `sara-python-v<version>-<commit>.zip`, the client alone, read from `HEAD` with `client-readme.txt` and `LICENSE`. A missing or doubled AppImage or APK fails the draft, naming the command that makes it. `--dry-run` packs it and runs no `gh` |
| `painter-guide.txt` | The page for the painter, which zip to take, what a first start needs, where Sara keeps its data and how to send a bug, which `build.sh` puts beside the binary and `install.sh` beside the installed one as `README.txt` |

## The source

A clone of the repository has everything a build reads, the modules included
under `sara-godot/modules/`, and `./packaging/build.sh` inside it exports a
build. A source archive of a release unpacks as the same single folder, with a
file `SOURCE_COMMIT` naming the commit it was cut at.

Because there is no `.git` in such an archive, `git rev-parse HEAD` has nothing
to answer and the build's stamp would say `unknown`. `build.sh` reads
`SOURCE_COMMIT` when git has no answer, so a build made from the archive still
names the commit it came from and so does a bug report about it.

## Building for Windows

The build a stranger on Windows is handed is a zip rather than an installer,
because the alpha has no installer and the zip needs no privileges to unpack.
`./packaging/build.sh windows` zips **sixteen files**, and one library beside
them for each native module a `.gdextension` names for Windows, two of them
today. The count below is the one count of a zip's contents this page gives,
and `unzip -l` of a zip with both modules in it prints eighteen entries. The table has a row for each of the sixteen, then the libraries
and the zip itself:

| Path | What |
|---|---|
| `build/w/sara.exe` | The binary, PCK and its icon embedded, so it is one file to run. A painter starts this, and it opens no door |
| `build/w/sara.console.exe` | The console wrapper, without which a crash report has nowhere to go |
| `build/w/sara-with-door.cmd` | The launcher a student starts, `sara.exe -- --agent-door`, so a notebook can attach |
| `build/w/sara.py` | The client a student copies beside a notebook, which attaches to the Sara the launcher started |
| `build/w/sara_notebook.py` | The `%%gmacs` magic, which the first cell of a notebook imports |
| `build/w/sara_array.py` | The array that stays on the GPU, which imports `sara.py` as the magic does |
| `build/w/sara_live.py` | The runner `sara.live` imports at its first call, a NumPy function with sliders |
| `build/w/sara_params.py` | The reader of that function's `PARAMS`, the format the Krita template takes |
| `build/w/sara_documents.py` | What `doc.documents` imports, the open paintings and which is in front |
| `build/w/sara_measure.py` | What `sara.bench` and `sara.check` import, a kernel's time and a layer's distance from an array |
| `build/w/sara_start.py` | How `sara.connect` starts a Sara that outlives the notebook kernel which started it |
| `build/w/AGENTS.md` | The guide for a coding agent, with CRLF endings |
| `build/w/README.txt` | The page for the painter, with CRLF endings |
| `build/w/LICENSE` | GPLv3, which asks to travel with the program |
| `build/w/THIRDPARTY.txt` | The notice of every library in the build, which each of them asks for |
| `build/w/build_info.json` | The stamp, the same file the Linux build gets |
| `build/w/libsara-jxl.windows.*.dll`, `build/w/libsara-tiff-lzw.windows.*.dll` | One library for each native module, put there by the export and read from the `.gdextension` files, so the number varies with the modules a checkout has |
| `build/w/sara-windows-x86_64-v<version>-<commit>-<kind>.zip` | The sixteen and the libraries, and what is handed over |

The build clears only the zips of the version, commit and kind it is about to
write, so a folder that has seen several builds keeps the zips of the versions
before them. The name carries the version, which is what tells them apart, and a
release attaches the zip whose name holds the tag.

The launcher is `packaging/sara-with-door.cmd`, written into the build with
CRLF endings, since the repository keeps LF and `cmd.exe` reads a batch file by
CRLF. It opens the door on the loopback address, and while Sara listens it
writes the port and its token to
`%APPDATA%\Godot\app_userdata\Sara\door.json`, which `sara.py` reads to attach
and Sara removes when it closes. A Preferences switch that kept the door open
on every start is not offered, because a painter who never scripts did not ask
for a door. The attach itself is the Attach section of the door guide.

The `Windows Desktop` preset in `sara-godot/export_presets.cfg` is what exports
it, and it names `sara-godot/ui/icon.ico`, which is Sara's own 1024 pixel artwork
cut down to the seven sizes Windows asks for, 16 through 256. The icon and the
version strings of `project.godot` land in the exe's Windows resources, so the
file properties of a download name Sara and its version.

Windows itself is not needed to make one. The templates for every platform are
one download, and a machine that has them exports a Windows build from Linux:

```bash
./packaging/install-templates.sh
```

The folder has to hold the templates of exactly that version. The engine inside
an export is the template's, so templates of another version under the editor's
folder name build a Sara whose About window and boot header name that other
version. `build.sh` reads the folder's `version.txt` and refuses such a folder.

`build.sh` checks the artefact, not the exit code: the exe has to be there, the
console wrapper has to be there, and the pack has to be embedded. Godot writes
the console wrapper only when the preset asks for one, which it does for both
builds, and a
zip without it is a bug report nobody can read, which is what the three hand
exports of the first sittings shipped.

The zip is smoke-tested on a machine with Steam's Proton before it goes to a
tester, and the pen is read on Windows itself. The Linux
build is unchanged by any of this and still lands in `build/l/`.

## Building for other Linux distros

A release hands a Linux painter one file beside the Windows zip, an AppImage.
`./packaging/appimage.sh` wraps the build in `build/l/`, or the one
`./packaging/build.sh linux release public` makes with
`./packaging/appimage.sh release public`, which is the one a release hands a
stranger, since it leaves out the folders `packaging/not-public.txt` names, into
`build/a/Sara-<version>-x86_64.AppImage`, the native modules' libraries
included. It never builds, so run `build.sh`
first, and it refuses a build stamped with uncommitted changes unless
`--allow-dirty` is given. It fetches `appimagetool` once into `build/a/`, or
uses the file `APPIMAGETOOL` names.

A release attaches this AppImage and the Android debug APK
`build/a/sara-android-v<version>-<commit>-debug.apk` (`./packaging/build.sh
android`) beside the Linux `.tar.gz` and the Windows zips, and
`draft-release.sh` refuses to draft without exactly one of each, naming the
command that makes it. The APK is checked against `HEAD` by its name and its
stamp. The AppImage's name carries no commit, so it is checked only for being
newer than the `build/l-release` binary it wraps, which catches one made before
the last build. Make it again after every Linux release build.

What the file needs from the host was read off the 0.19.1 binary, not assumed.
It links only glibc, and the newest symbol it asks for is `GLIBC_2.28`, which
is Debian 10, Ubuntu 20.04 and RHEL 8. Everything else (Vulkan, Wayland, X11,
xkbcommon, audio, udev, dbus, fontconfig) is opened at run time, so the host's
own libraries and GPU driver are used and none is bundled. A missing audio
library switches audio off, and a missing `libvulkan.so.1` or display library
stops Sara. Running the AppImage itself needs FUSE 2 (`libfuse2`), which
Ubuntu 22.04 and later no longer install, and `--appimage-extract-and-run`
works without it.

An AppImage cannot install the pen's udev rule. The rule rides inside it at
`usr/share/sara/70-sara-pen.rules`, and a painter on another distro copies it
by hand with the command `./packaging/install.sh --pen-rule` prints.

## A Mac, not yet

There is no macOS preset and `build.sh` has no `macos` branch. The templates
are installed, so a Mac build can be exported from Linux the way the Windows
one is, and nothing is exported until someone with an Apple machine can test it.

## What to keep when Sara freezes

Sara writes its log line by line, and a freeze leaves lines that say where it
was. A quit prints `Sara trail:` at every stage up to the engine's own
teardown, and a main thread stuck for five seconds prints `Sara stall:` with the
last thing Sara did, while it is still stuck. The log is here:

- Linux: `~/.local/share/godot/app_userdata/Sara/logs/godot.log`
- Windows: `%APPDATA%\Godot\app_userdata\Sara\logs\godot.log`
- macOS: `~/Library/Application Support/Godot/app_userdata/Sara/logs/godot.log`,
  and after a crash the newest `.ips` report in `~/Library/Logs/DiagnosticReports/`

Sara keeps the last ten runs in that folder, setting the old `godot.log` aside
under the time of the next start, and every start of Sara writes a new one. A
Sara started while another still runs leaves that one's `godot.log` alone and
writes its own beside it, named with the time and its process number. So
before Sara is started again, copy the newest file somewhere else, and send it
with a line saying what you did last.

On Windows, while the window still says it is not responding, open Task
Manager, find `sara.exe` on the Details tab, right-click it and choose Create
memory dump file. The dump says where every thread was at that moment, and it
is gone once the process is killed. Its path is shown when it is written.

## Why it lives here and not in `build/`

`build/` is gitignored. The previous installer lived there, was never tracked,
and rotted through a project rename, it still referenced `mwe-sara.x86_64` and
`sara_icon.svg`, neither of which had existed for months. Nothing in `build/` is
authoritative. It is output, and after `install.sh` it can be deleted.

## Things worth knowing

**The build is a debug export, on purpose.** `build.sh` runs `--export-debug`,
because only the debug template carries the engine's crash handler: the first
crash of an installed build, on 2026-09-14, printed nothing at all. A debug
build prints the native backtrace and the GDScript frames under it, so a crash
in a stranger's hands names the line that failed. Measured on the development
laptop on 2026-09-17, it costs 0.2 MB of 112 and nothing at boot that clears the
noise of a loaded machine. `./packaging/check_crash_report.sh` is the proof: it
starts the binary with `--headless` and `SARA_CRASH_ON_PURPOSE=boot`, the hidden
switch in `sara-godot/core/app/sa_crash_probe.gd`, under a temporary profile, and
exits 0 only when stderr holds `Program crashed with signal` and a frame in
`sa_crash_probe.gd` with a line number. `SARA_CRASH_BIN` points it at another
binary, and against a release export it exits 1 saying the build has no crash
handler. A debug build also leaves `SARA_BREAK_KERNEL` and
`SARA_NO_RENDERING_DEVICE` live, which is how a tester shows what a bad driver
looks like.

**A release export is only a little faster.** Measured on one desktop GPU
under Linux, five interleaved runs of each through the
door, a release export of the same tree reached its ready mark about 15 percent
sooner than the debug export (a median of 7.4 seconds against 8.5 with warm
caches), and a stroke test that keeps the CPU busy every frame took about 10
percent less time, its compositing about 15 percent less CPU. Most of a boot is
shader compiling and GPU work, which the build type does not change. Strokes at
the pace the display allows showed no difference, because the frame clock sets
that pace, and the two binaries are the same size to within a fifth of a
percent. Both builds ship: a painter is pointed at
the release build, and the debug build is the one to reproduce a bug in and send
the log of. `build.sh` and `install.sh` stay on the debug export by default,
because a crash on the machines that build Sara is read by somebody.

**The release build has an argument of its own.** `./packaging/build.sh
windows release` and `./packaging/build.sh linux release` export with
`--export-release` into `build/w-release/` and `build/l-release/`, folders of
their own, so a release build never writes over the debug one and
`install.sh`, which installs `build/l/`, still installs the debug build. The
second argument is `debug` when it is left out, and anything but `debug` or
`release` exits 2 naming both. The stamp beside the binary and the one packed
inside it read `"build": "release"` or `"build": "debug"`, and the last line
of the run names which was built. A Windows zip's name ends in `-release.zip`
or `-debug.zip`, so a painter handed both takes the release one without
opening either, and the two hold the same files. The preset asks for the
console wrapper on both builds, `debug/export_console_wrapper=2`, so the
release zip carries `sara.console.exe` too.

**A build a stranger may be handed takes the word `public`.** `./packaging/build.sh
windows release public` exports with every folder [`not-public.txt`](not-public.txt)
names added to the preset's exclude filter for the length of the export, a
module that is not published yet, so its code, its kernel and its tables are not in
the pack. `export_presets.cfg` is added to that filter too, because the lines
the build writes into it name the left-out folders and the export packs the
presets file along with everything else under the project: a public exe would carry no file
of the module and still spell its name, in its own packed copy of the narrowed
presets. Nothing in a build reads
the presets, so only a public build drops them. The presets are put back when the export ends, however it ends. The
build lands in a folder of its own, `build/w-release-public/` or
`build/l-public/`, and a Windows zip's name ends in `-public-release.zip` or
`-public-debug.zip`. Without the word a build keeps the module, and that is the
zip a tester takes. `install.sh` installs the build without the word. When that module is published, deleting its line from `not-public.txt`
takes it back into every build.

**Absolute paths are baked in at install time.** A `.desktop` file cannot contain
relative paths or `$HOME`, so `install.sh` substitutes them from wherever the
prefix and the checkout actually are.

**The icon binds by `app_id`, not by the icon file.** Wayland matches a window to
its desktop entry through `StartupWMClass`, which must equal Godot's
`application/config/name`, so both must read `Sara`. This is also why Mutter not advertising
`xdg-toplevel-icon` stops
mattering once this entry is installed: the icon comes from here instead.

**The launcher forces native Wayland** when `WAYLAND_DISPLAY` is set, because
XWayland cannot report a display scale and the UI then infers it from DPI. It
also filters the two GNOME warnings Sara cannot do anything about, and sets
`SARA_WARNINGS_FILTERED` so the app does not then point at warnings you cannot
see.

**`build.sh` imports before exporting.** A clean checkout has no `.godot/` cache,
and exporting without one silently produces a build missing every imported asset.
It also checks the artefact's size afterwards, because Godot can exit 0 having
written a binary with no PCK embedded.

**The terminal for the Rebuild and console actions is detected at install time**: `kgx`,
`gnome-terminal`, `konsole`, `alacritty`, `kitty`, `foot`, `xterm`, first match
wins. If none is present the actions still run, just without visible output.
