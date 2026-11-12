# Contributing to Sara

Sara is a GPU-first painting program in Godot. This page says how to build it,
test and send a change, and holds the rules the code follows. A comment that
says "hard rule 4" or "the rules of structure" points here. Questions and ideas
are welcome on [Discord](https://discord.gg/DHxbD7m6y) before you start.

## Setup

- **Godot 4.7** and the build tools that [Building Sara](#building-sara) below
  lists.
- **The gdtoolkit tools** for the style checks, in a Python environment that
  `sara-godot/scripts/check_style.sh` and `check_lsp.sh` look for at
  `sara-godot/.conda` or `sara-godot/.venv`:
  `python -m venv sara-godot/.venv && sara-godot/.venv/bin/pip install "gdtoolkit==4.5.*"`
  (`.venv\Scripts\pip` on Windows), the 4.5 series the project is formatted
  with. A `gdformat` and `gdlint` on `PATH` are used when neither folder
  exists.
- **A Vulkan graphics card**, which most suites need, and `weston` on Linux for
  the offscreen runs below (`dnf install weston` on Fedora, `apt install weston`
  on Debian).
- The first run of a fresh checkout imports the project, which takes a minute.

## Sending a change

Fork the repository, make a branch, and open a pull request. Keep a change to
one purpose and say in its message why it is made. Run the tests and the style
check below first. By sending a change you agree that it is released under the
GPLv3, the licence of the rest of Sara (see `LICENSE`).

## The seven hard rules

1. **No CPU-GPU ping-pong.** The canvas never leaves the graphics card's memory
   during a stroke, and a stroke's commit is a copy on the card. A read back to
   the processor is one of a few kinds, each outside a stroke: writing a file
   (export and save), one texel at a click (the eyedroppers), a kernel's own
   result rather than the canvas, a brush built before a stroke, a test's
   reading, a filter that asks for its pixels by name, a picture of the window,
   a scratch canvas made for one picture, and a layer nobody is painting on
   evicted past the memory budget. `READBACK_ALLOWED` in
   `sara-godot/tests/test_hard_rules.gd` lists the files that may read back,
   and the run fails on any other.
2. **Dirty-rect dispatch only.** A compute shader is never dispatched over the
   whole canvas. The brush works out a tight box per dab and dispatches only
   the chunks it overlaps.
3. **Sparse chunks.** The canvas is 256 by 256 tiles, allocated only where
   paint lands, never pre-allocated as one texture or as a full grid. Ask
   `chunk.pixel_size()` for a chunk's texels and `SaFieldSpec.BYTES_PER_TEXEL`
   for a texel's bytes, and never write 256 or 16 for either.
4. **RAII.** `SaTexture` and `SaCompute` are `RefCounted` and free their GPU
   resources when the last reference goes. Never `free()` them or their RIDs
   by hand.
5. **Colour precision.** Float textures throughout. Nothing clamps, and values
   outside 0 to 1, negatives included, survive painting, compositing and
   export to EXR.
6. **Built-ins go through the public door.** A built-in tool, blend mode, layer
   type or command registers through `SaRegistries` exactly as a third-party
   module would, so a gap in the module API breaks a built-in first.
7. **One writer for UI scale.** Only `SaUI.apply_to_window()` writes
   `Window.content_scale_factor`. Everything else sizes in logical units.

Rules 1, 4 and 7 are checked by a search in `tests/test_hard_rules.gd`. Rule 6
is held by `core/api/descriptors/tests/test_module_api_contract.gd`, which
registers a synthetic module and asserts it reaches where a built-in does.

## The rules of structure

- **A feature is a folder with one facade.** The facade carries the feature's
  name and is its public surface. Everything else in the folder is private to
  it, and a small helper is an inner class rather than a sibling file.
  `sara-godot/packages.json` says which files of a package are public.
- **A class is never cut to fit a line count.** A class split off owns state
  of its own and holds no reference back.
- **Dependencies run one way.** A module sees only the public door
  (`core/api`, `core/custom-shader`, `utils` and the widget toolkit under
  `ui`). `core` and `render` never name a class under `ui`, and the skeleton
  never names a module.
- **A tool's engine lives with the tool.** The skeleton keeps only what two or
  more features use.
- **The harness lives in its own folder.** The automation door, its drivers
  and its captures are not the UI.
- **Length is an alarm.** A file over a thousand lines fails the run.

## Conventions

- A private member, one starting with an underscore, is written only by its
  own class. Reading it from outside is fine. There are no getters or setters
  that only wrap a field.
- Every class and every public function has a `##` doc comment that says what
  it is for.
- A comment says why, not what the next line does, and states what the code is
  rather than how it came to be.
- British spelling in prose and in every string Sara shows, American spelling
  in identifiers. No em dashes and no semicolons in prose, comments included.
- A test suite is named for the behaviour it checks.

## Modules

Every tool, the brush, the eraser, the fill, the eyedropper, pan and zoom, and
every filter lives in a module, and registers itself through the same public
door a module of your own would use. The modules sit under
`sara-godot/modules/`, and a module is a folder holding a `module.gd`. Sara
also loads a module dropped into the `modules` folder of its user data, or one
named on the command line as `--modules-dir=<path>`.

Every module but the skeleton can be switched off. **Preferences > Modules**,
also opened from the **Modules** menu's **Turn Modules On or Off...**, lists
every module with a switch, and a change takes effect at the next start. A
module that needs one you switched off is off too, with the reason beside it.
**Restore Defaults** turns them all on again. The skeleton alone, a canvas with
an empty toolbox that says so, is how Sara shows the module door is real.

Each module is a branch of the repository, and `main` merges them all. A few
modules Sara is built with are left out of the public repository and of every
public build for now. Each is being worked on and will join when it is ready.

| Module | What it does | Why it is left out | What is being done |
|---|---|---|---|
| **Paint mixing** | Colours that mix the way paints do, so blue and yellow make green rather than grey. | It comes from research that is not published yet. | It joins once the research is published. |
| **Blender live** | A live Blender viewport as a layer, painted over while the camera moves. | It is not stable enough to hand out. | It is being made stable, and then joins as a module of its own. |
| **Lessons** | Short lessons that replay a painting stroke by stroke, with the painter's voice, and stop for your own turn. | The lessons are still being recorded. | More lessons are being recorded, and the module joins with the first full set. |
| **Drifting sky** | A paper that moves over time, a first try at a layer that changes while you watch. | It is an experiment rather than a tool for painting. | It is being explored, and grows into a layer type if the idea holds. |

## Painting through the door

Sara can be driven by a program through a local door, which is also how it is
tested. On Linux, start Sara with the door open and a folder for its pictures,
then post JSON steps to it with `curl`:

```bash
godot --path sara-godot -- --agent-door --capture-out="$PWD/shots" &
DOOR_FILE="${XDG_DATA_HOME:-$HOME/.local/share}/godot/app_userdata/Sara/door.json"
until [ -f "$DOOR_FILE" ]; do sleep 1; done
PORT=$(sed -n 's/.*"port": *\([0-9]*\).*/\1/p' "$DOOR_FILE")
TOKEN=$(sed -n 's/.*"token": *"\([^"]*\)".*/\1/p' "$DOOR_FILE")
door() { curl -sS -H "Authorization: Bearer $TOKEN" --data-binary "$1" "http://127.0.0.1:$PORT/step"; }
door '{"steps": true}'     # every step the door knows, each described
door '[{"stroke": {"from": [420, 400], "to": [1120, 400], "colour": "#c04020"}}, {"shot": "first-stroke"}]'
```

The second call paints a stroke and saves the window as `shots/first-stroke.png`.
[`packaging/agent-guide.md`](packaging/agent-guide.md) covers the rest, Windows
included, and `sara-godot/scripts/sara.py` is the same door as a Python client
for a notebook.

## Building Sara

This part is written for Linux. A Windows build is made from Linux as well, and
[`packaging/README.md`](packaging/README.md) says what it needs.

You need:

- **Godot** 4.7, the version `sara-godot/project.godot` names under
  `config/features`, on `PATH` as `godot`. The editor from
  [godotengine.org](https://godotengine.org/download) is one file in a zip, so
  unzip it and move it to a folder on your `PATH` under the name `godot`,
  `~/.local/bin/godot` for example. A Godot under another name is given to the
  build as `GODOT_BIN=/path/to/it`.
- **Godot's export templates** of exactly that version, because the build is a
  Godot export. They are a download of their own, see below.
- **git**, **Python 3**, which the build writes the door's step catalogue with,
  **curl** and **unzip** for the templates, and **cmake** with a C++ compiler
  for the JPEG XL library.

### Get the source and build

Every command runs in the source's root folder. Clone the repository, whose
`main` branch carries every module already, and step into the folder it made:

```bash
git clone https://github.com/MatejZeman02/sara.git
cd sara
```

A source archive of a release has the modules unpacked inside it as well, and
a file `SOURCE_COMMIT` naming the commit it was cut at.

The export templates first, once for each Godot version. The script reads the
editor's version, downloads that release's templates (about 1.3 GB) into a
scratch folder and unpacks them where Godot looks for them:

```bash
./packaging/install-templates.sh
```

Then the build and the install:

```bash
./packaging/build.sh      # exports build/l/sara.x86_64, a debug build
./packaging/install.sh    # installs it under ~/.local, with the desktop entry
```

`install.sh` builds if it needs to, then installs a desktop entry and a launch
wrapper under `~/.local`, so nothing needs root. Sara then appears in your
application menu, `sara` starts it from a terminal, and right-clicking the menu
entry offers **Rebuild from source and launch**. Its last lines offer a udev
rule that lets Sara read a drawing tablet's pen, and the one `sudo` command
that installs it. The rule is optional and the script never runs `sudo`
itself. `./packaging/uninstall.sh` reverses the install exactly, and moving the
source folder means running `install.sh` again, because the install records
where it is.

The build fetches libjxl and godot-cpp from GitHub to build the JPEG XL
module's library. Without them it builds a Sara that saves and opens
everything but JPEG XL.

Other builds:

```bash
./packaging/build.sh linux release   # the release build, in build/l-release
./packaging/build.sh windows         # the Windows zip, in build/w
./packaging/build.sh windows release # the Windows release zip
./build/l/sara.sh                    # runs a build without installing it
```

[`packaging/README.md`](packaging/README.md) says what each script does, and
what a Windows build needs.

### Run from source without installing

A clone has no `.godot/` import cache, and only the editor builds one, so
import the project once (about a minute), then run it:

```bash
godot --headless --path sara-godot --editor --quit   # once, the import pass
godot --path sara-godot --display-driver wayland
```

Or open the `sara-godot` folder in Godot and run it from there. To try the code
without touching your own paintings and settings, add `--settings-dir=<dir>`
to the run line. Sara then keeps everything under that folder, and its log is
`<dir>/data/logs/godot.log`.

Run native Wayland where you can. X11 and XWayland work, but cannot report a
display scale, so the size of the interface has to be guessed from the screen's
DPI and is capped. The program needs a display. The offscreen path, a nested
`weston`, belongs to the test runner only.

Sara draws its own title bar and keeps its dockers inside the main window,
because Wayland does not let a program place or decorate its own windows. For
several monitors, **Window > New Secondary Workspace** opens a window you can
move to a second display and arrange dockers in. Two warnings at start on GNOME
are expected and cannot be fixed from Sara's side, and the `sara.sh` wrapper
filters them out. A third one, about libdecor failing to start GTK, means
`GDK_BACKEND=x11` is set in your shell.

## Running the tests

```bash
cd sara-godot
SARA_TEST_OFFSCREEN=1 ./run_tests.sh
```

A clean run exits with 0, with no failed assertion, no script error and no
leaked resource. Read the exit code rather than the summary line. A filter
runs part of it, `./run_tests.sh transform` for the suites whose names hold
the word. A full run needs a Vulkan device. `SARA_TEST_OFFSCREEN=1` draws into
a nested `weston` so no window opens on your desktop, and it is also the way to
run on a machine with no display at all. Without it the run draws on your desktop and
needs one. On Windows use
`run_tests.ps1`. `sara-godot/tests/README.md` explains the run's limits.

## Style tools

```bash
cd sara-godot
./scripts/check_style.sh            # gdformat and gdlint, exit 0 when clean
./scripts/check_style.sh --write    # lets gdformat rewrite what it would change
./scripts/check_lsp.sh              # the editor's compile diagnostics
```

`check_style.sh` uses the environment from Setup, and `check_lsp.sh` needs
only `godot` on `PATH`.

## The wider checks

`run_tests.sh` is the largest check and not the only one. A change should pass
these as well, each run from `sara-godot`:

```bash
python -m unittest discover -s scripts           # the Python suites
python scripts/gmacs_format.py --check           # kernels are in the formatted dialect
python scripts/check_translated.py && python scripts/write_pseudo.py --check
                                                 # shown text and its catalogues agree
python scripts/write_en_us.py --check           # the American English catalogue is current
python scripts/gen_file_map.py --check          # the generated file-map pages are current
```

The Python suites run with plain `unittest`. Two of them, `test_sara_live` and
`test_sara_notebook`, skip their cases until `pip install ipywidgets` has been
run. A single suite runs as
`PYTHONPATH=scripts python -m unittest scripts.test_sara`, for example. A
change that moves shown text regenerates the catalogues with `write_pseudo.py`
and `write_en_us.py`, and a change that moves files regenerates the map with
`gen_file_map.py`, each without `--check`.

## Writing a module

A module is a folder with a `module.gd` that extends `SaModule` and a
`manifest.cfg`, and it registers through `SaRegistries` the way a built-in
does. `sara-godot/modules/sara-noise-brush-engine/README.md` shows a small
module, and `sara-godot/modules/sara-base-modules/README.md` says how the
loader finds one. The classes a module may use are the ones under
`sara-godot/core/api`, and the manual's chapters on
[filters](sara-godot/manual/07-filters.md) and
[brush presets](sara-godot/manual/03-brush-presets.md) say what a painter sees
of them.
