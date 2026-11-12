## The ICC profile the system assigns the monitor a screen of Sara's stands on,
## found by asking the system rather than by the painter finding the file.
##
## On Linux colord holds it, set by a calibration tool or matched from the
## monitor's EDID, and `colormgr` answers for every display in one call, under
## the C locale so its labels are the same words on every desktop. colord names
## a display by its output, `DP-2`, and Godot names a screen by its index alone,
## so the two are matched by where they stand: `xrandr --listmonitors` gives each
## output's rectangle, which Godot's `screen_get_position` and `screen_get_size`
## give too. On Windows the profile comes from `GetICMProfile` on a device
## context of each monitor, called from Windows PowerShell with `Add-Type`, so
## Sara ships no native library for it, and `Screen.AllScreens` gives each
## monitor's rectangle in the same pixels Godot's are, the call being made DPI
## aware first. Android has no such profile, and nothing is asked there.
##
## **Asked once and aside**, on the worker pool: PowerShell compiling its one
## class takes about a second, and Sara's first frame does not wait for it. Until
## the answer lands the reading says the system has not answered yet, and the
## display stays on sRGB for that moment. A test hands a callable in place of the
## system and is answered at once.
##
## `SARA_SYSTEM_PROFILE` stands in for the system when it is set: a path is the
## profile every screen is given, and `none` is a system with no profile. The
## harnesses set `none`, because a nested compositor's output can stand where
## the painter's own monitor does, and a shot is the same on every machine.
@tool
class_name SaSystemProfile
extends RefCounted

## The value of `SARA_SYSTEM_PROFILE` that is a system with no profile.
const NONE := "none"

## How long the system is given to answer, in seconds, so a colord that hangs on
## D-Bus never holds a worker for ever.
const ASK_SECONDS := 5

## How far apart two aspect ratios may stand and still be one monitor, so a
## screen Godot sizes in logical pixels on a scaled desktop meets the output the
## system sizes in device ones.
const ASPECT_SLACK := 0.01

## Every display the system answered for, or empty while it has not.
var _displays: Array[Display] = []

## Whether [member _displays] holds the system's answer.
var _answered := false

## The worker pool task asking the system, or -1.
var _task := -1

## What the task found, taken once it is complete.
var _aside: Array[Display] = []

## The stand-in for the system, a callable returning `Array[Display]`, or an
## invalid one to ask the real system.
var _ask: Callable


## *ask* in place of the system when it is valid, called at once rather than on
## the worker pool.
func _init(ask: Callable = Callable()) -> void:
    _ask = ask


## What the system says for *screen* among *screens*, each Godot screen's
## rectangle by its index. Starts the question when nothing has asked it yet.
func reading(screen: int, screens: Array[Rect2i]) -> Reading:
    if not _take_answer():
        return Reading.new("", "", "The system has not said yet which profile this monitor has.", false)
    if _displays.is_empty():
        return Reading.new("", "", "The system names no colour profile for any monitor.")
    var display := matched(_displays, screens, screen)
    if display == null:
        return Reading.new("", "", "The system names no monitor that stands where this screen of Sara's does.")
    if display.path.is_empty():
        return Reading.new(display.name, "", "The system names no colour profile for the monitor %s." % display.name)
    return Reading.new(display.name, display.path, "")


## Whether an answer has arrived and not been taken yet, so the window watching the
## screen can redraw once it has. Never starts a question.
func just_answered() -> bool:
    if _answered or _task < 0 or not WorkerThreadPool.is_task_completed(_task):
        return false
    return _take_answer()


## Forgets the answer, so the next reading asks the system again.
func forget() -> void:
    if _task >= 0:
        WorkerThreadPool.wait_for_task_completion(_task)
        _task = -1
    _answered = false
    _displays.clear()


## Whether [member _displays] holds the answer, asking or taking it first.
func _take_answer() -> bool:
    if _answered:
        return true
    if _ask.is_valid():
        var answer: Array = _ask.call()
        _displays.assign(answer)
        _answered = true
        return true
    if _task < 0:
        _task = WorkerThreadPool.add_task(func() -> void: _aside = SaSystemProfile.ask_platform(), false, "system profile")
        return false
    if not WorkerThreadPool.is_task_completed(_task):
        return false
    WorkerThreadPool.wait_for_task_completion(_task)
    _task = -1
    _displays = _aside
    _answered = true
    return true


## The display among *displays* that *screen* of *screens* shows, or null.
##
## The same rectangle first. Then the one display of the screen's shape, which
## is a scaled desktop sizing one side in logical pixels and the other in device
## ones. Then, with one screen and one display and no rectangle to go by, that
## display. A screen of a shape no display has is matched to nothing, so a
## nested compositor's output never takes the profile of the monitor under it.
static func matched(displays: Array[Display], screens: Array[Rect2i], screen: int) -> Display:
    if screen < 0 or screen >= screens.size():
        return null
    var rect := screens[screen]
    for display: Display in displays:
        if display.rect.has_area() and display.rect == rect:
            return display
    var shaped: Array[Display] = []
    for display: Display in displays:
        if (
            display.rect.has_area()
            and rect.has_area()
            and absf(_aspect(display.rect) - _aspect(rect)) <= ASPECT_SLACK * _aspect(rect)
        ):
            shaped.append(display)
    if shaped.size() == 1:
        return shaped[0]
    if screens.size() == 1 and displays.size() == 1 and not displays[0].rect.has_area():
        return displays[0]
    return null


## Every screen's rectangle as Godot places it, by Godot's index for it.
static func godot_screens() -> Array[Rect2i]:
    var rects: Array[Rect2i] = []
    for index: int in DisplayServer.get_screen_count():
        rects.append(Rect2i(DisplayServer.screen_get_position(index), DisplayServer.screen_get_size(index)))
    return rects


## Every display the system knows, asked of this platform. Called on the worker
## pool, so it touches nothing but the processes it starts.
static func ask_platform() -> Array[Display]:
    var stood_in := OS.get_environment("SARA_SYSTEM_PROFILE")
    if not stood_in.is_empty():
        return stand_in(stood_in)
    match OS.get_name():
        "Linux", "FreeBSD", "NetBSD", "OpenBSD", "BSD":
            return _ask_colord()
        "Windows":
            return _ask_windows()
    return []


## The system `SARA_SYSTEM_PROFILE` describes: one display with no rectangle and
## the file *named*, or none at all for [constant NONE].
static func stand_in(named: String) -> Array[Display]:
    var displays: Array[Display] = []
    if named != NONE:
        displays.append(Display.new("every monitor", Rect2i(), named))
    return displays


static func _ask_colord() -> Array[Display]:
    var said: Array = []
    var timeout := str(ASK_SECONDS)
    if OS.execute("env", ["LC_ALL=C", "timeout", timeout, "colormgr", "get-devices-by-kind", "display"], said) != 0:
        return []
    var displays := colormgr_displays(str(said[0]) if not said.is_empty() else "")
    var placed: Array = []
    if OS.execute("timeout", [timeout, "xrandr", "--listmonitors"], placed) == 0 and not placed.is_empty():
        var rects := xrandr_rects(str(placed[0]))
        for display: Display in displays:
            display.rect = rects.get(display.name, Rect2i())
    return displays


## Every display in *text*, `colormgr get-devices-by-kind display` under the C
## locale: its output's name from the `XRANDR_name` metadata, or the device id
## when it has none, and the first profile's file, which is the default colord
## hands out. A display with no profile keeps an empty path.
static func colormgr_displays(text: String) -> Array[Display]:
    var displays: Array[Display] = []
    var current: Display = null
    var in_profile := false
    for line: String in text.split("\n"):
        var stripped := line.strip_edges()
        if line.begins_with("Object Path:"):
            current = Display.new("", Rect2i(), "")
            displays.append(current)
            in_profile = false
            continue
        if current == null or stripped.is_empty():
            continue
        if line.begins_with("Device ID:") and current.name.is_empty():
            current.name = stripped.trim_prefix("Device ID:").strip_edges()
        elif line.begins_with("Metadata:") and stripped.contains("XRANDR_name="):
            current.name = stripped.get_slice("XRANDR_name=", 1).strip_edges()
        elif line.begins_with("Profile "):
            in_profile = current.path.is_empty() and line.begins_with("Profile 1:")
        elif not line.begins_with(" "):
            in_profile = false
        elif in_profile and stripped.begins_with("/"):
            current.path = stripped
            in_profile = false
    return displays


## Each output's rectangle in *text*, `xrandr --listmonitors`, whose lines read
## ` 0: +*DP-2 1920/520x1200/320+0+0  DP-2`, by the output's name.
static func xrandr_rects(text: String) -> Dictionary[String, Rect2i]:
    var rects: Dictionary[String, Rect2i] = {}
    var shape := RegEx.create_from_string("(\\d+)/\\d+x(\\d+)/\\d+([+-]\\d+)([+-]\\d+)\\s+(\\S+)\\s*$")
    for line: String in text.split("\n"):
        var found := shape.search(line)
        if found == null:
            continue
        var size := Vector2i(int(found.get_string(1)), int(found.get_string(2)))
        var at := Vector2i(int(found.get_string(3)), int(found.get_string(4)))
        rects[found.get_string(5)] = Rect2i(at, size)
    return rects


## The PowerShell that prints one line per monitor, its device name, rectangle
## and the profile `GetICMProfile` gives its device context, tab separated.
const WINDOWS_ASK := """
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Text;
public static class SaIcm {
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    [DllImport("gdi32.dll", CharSet = CharSet.Unicode)]
    static extern IntPtr CreateDC(string driver, string device, string output, IntPtr mode);
    [DllImport("gdi32.dll")] static extern bool DeleteDC(IntPtr dc);
    [DllImport("gdi32.dll", CharSet = CharSet.Unicode)]
    static extern bool GetICMProfile(IntPtr dc, ref uint size, StringBuilder name);
    public static string Of(string device) {
        IntPtr dc = CreateDC(device, null, null, IntPtr.Zero);
        if (dc == IntPtr.Zero) return "";
        uint size = 1024;
        StringBuilder name = new StringBuilder(1024);
        bool found = GetICMProfile(dc, ref size, name);
        DeleteDC(dc);
        return found ? name.ToString() : "";
    }
}
'@
[void][SaIcm]::SetProcessDPIAware()
foreach ($screen in [System.Windows.Forms.Screen]::AllScreens) {
    $b = $screen.Bounds
    "{0}`t{1}`t{2}`t{3}`t{4}`t{5}" -f $screen.DeviceName, $b.X, $b.Y, $b.Width, $b.Height, [SaIcm]::Of($screen.DeviceName)
}
"""


static func _ask_windows() -> Array[Display]:
    var said: Array = []
    # Encoded rather than passed as text, because the script's quotes and lines
    # would otherwise go through Windows' quoting of one argument.
    var encoded := Marshalls.raw_to_base64(WINDOWS_ASK.to_utf16_buffer())
    var args := ["-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-EncodedCommand", encoded]
    if OS.execute("powershell.exe", args, said) != 0 or said.is_empty():
        return []
    return windows_displays(str(said[0]))


## Every monitor in *text*, the lines [constant WINDOWS_ASK] prints.
static func windows_displays(text: String) -> Array[Display]:
    var displays: Array[Display] = []
    for line: String in text.split("\n"):
        # Only the carriage return goes, since a monitor with no profile ends
        # its line on the tab before the empty field.
        var fields := line.trim_suffix("\r").split("\t")
        if fields.size() < 6:
            continue
        var rect := Rect2i(int(fields[1]), int(fields[2]), int(fields[3]), int(fields[4]))
        displays.append(Display.new(fields[0], rect, fields[5]))
    return displays


static func _aspect(rect: Rect2i) -> float:
    return float(rect.size.x) / float(rect.size.y)


## One monitor as the system knows it.
class Display:
    extends RefCounted
    ## Its output's name, `DP-2` or `\\.\DISPLAY1`.
    var name: String
    ## Where it stands on the desktop, empty when the system did not say.
    var rect: Rect2i
    ## Its profile's file, empty when it has none.
    var path: String

    func _init(display_name: String, where: Rect2i, profile_path: String) -> void:
        name = display_name
        rect = where
        path = profile_path


## What the system said for one screen: the monitor, its profile's file, and
## why there is none when there is none.
class Reading:
    extends RefCounted
    var monitor: String
    var path: String
    var problem: String
    ## False while the system has not answered, which is no fault to report.
    var answered: bool
    ## The file read, set by whoever reads it, `SaSettingsProofs`.
    var profile: SaIccProfile = null

    func _init(monitor_name: String, profile_path: String, why_not: String, has_answered: bool = true) -> void:
        monitor = monitor_name
        path = profile_path
        problem = why_not
        answered = has_answered
