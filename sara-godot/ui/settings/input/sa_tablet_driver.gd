## The tablet driver the engine reads the pen through, and what the Workspace
## row that switches it offers.
##
## Windows has two, WinTab and Windows Ink. Painting and dragging worked under
## WinTab where they did not under Ink, so `project.godot` starts Windows on
## WinTab. That is a way to paint today and not a verdict on Ink: a tablet whose
## vendor ships no `wintab32.dll` falls back to Ink on its own, and this row is
## how a painter picks either one by hand, for this launch and every one after.
##
## **A WinTab that cannot start is looked for.** The engine opens a WinTab
## context per window and, when that fails, says so only in verbose mode and
## goes on naming WinTab while the pen arrives as a mouse with no pressure. That
## happens while the tablet's own service is stopped. GDScript cannot call
## `wintab32.dll`, so a PowerShell helper opens a context the way the engine
## does, against the DLL the engine loaded, and closes it again. When it cannot,
## Sara reads the pen through Windows Ink for the session and the Tablet page
## says why, and the profile keeps asking for WinTab.
##
## Built from a list of driver names rather than from `DisplayServer` itself, so
## a suite on a machine with no tablet can hand it the list Windows would name.
class_name SaTabletDriver
extends RefCounted

## What the row calls a driver the engine names. A name missing here is shown
## as the engine spells it with its first letter raised, so no entry of the list
## reads lowercase. `auto` is the engine's own pick, and `label_of` says which
## driver that is on this system.
const LABELS: Dictionary = {
    "auto": "Automatic",
    "wintab": "WinTab",
    "winink": "Windows Ink",
    "default": "The system's own",
    "dummy": "None",
}

## What `auto` resolves to, in the order the engine tries them: Windows Ink
## where the system has it, WinTab where it does not. Read from the engine's
## `tablet_set_current_driver`, which walks the same two in the same order.
const AUTO_ORDER: PackedStringArray = ["winink", "wintab"]

## The helper, `{dll}` the path of the DLL to open. It prints `open`, `failed`
## when no context opens, `absent` when the DLL or its calls are missing, and
## `unknown` when the helper itself breaks. The context is the engine's: the
## system's default with messages asked for, opened on a window of its own.
const WINTAB_LOOK := """try {
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class SaWinTabLook {
    [DllImport("kernel32", CharSet = CharSet.Unicode)] static extern IntPtr LoadLibraryW(string path);
    [DllImport("kernel32", CharSet = CharSet.Ansi)] static extern IntPtr GetProcAddress(IntPtr module, string name);
    [DllImport("user32", CharSet = CharSet.Unicode)] static extern IntPtr CreateWindowExW(uint ex, string cls, string title,
        uint style, int x, int y, int w, int h, IntPtr parent, IntPtr menu, IntPtr inst, IntPtr param);
    [DllImport("user32")] static extern bool DestroyWindow(IntPtr window);
    delegate uint Info(uint category, uint index, IntPtr output);
    delegate IntPtr Open(IntPtr window, IntPtr context, bool enable);
    delegate bool Close(IntPtr context);
    public static string Run(string path) {
        IntPtr dll = LoadLibraryW(path);
        if (dll == IntPtr.Zero) return "absent";
        IntPtr info = GetProcAddress(dll, "WTInfoW"), open = GetProcAddress(dll, "WTOpenW"),
            close = GetProcAddress(dll, "WTClose");
        if (info == IntPtr.Zero || open == IntPtr.Zero || close == IntPtr.Zero) return "absent";
        IntPtr context = Marshal.AllocHGlobal(1024);
        for (int i = 0; i < 1024; i += 4) Marshal.WriteInt32(context, i, 0);
        ((Info)Marshal.GetDelegateForFunctionPointer(info, typeof(Info)))(4, 0, context);
        Marshal.WriteInt32(context, 80, Marshal.ReadInt32(context, 80) | 4);
        IntPtr window = CreateWindowExW(0, "STATIC", "", 0, 0, 0, 0, 0, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero);
        IntPtr opened = ((Open)Marshal.GetDelegateForFunctionPointer(open, typeof(Open)))(window, context, false);
        if (opened != IntPtr.Zero) ((Close)Marshal.GetDelegateForFunctionPointer(close, typeof(Close)))(opened);
        DestroyWindow(window);
        Marshal.FreeHGlobal(context);
        return opened == IntPtr.Zero ? "failed" : "open";
    }
}
'@
[SaWinTabLook]::Run('{dll}')
} catch { 'unknown' }
"""

## What the last look at WinTab found, one of the helper's answers, or empty
## before any.
static var wintab_found: String = ""

## What the look runs in place of the PowerShell helper, handed the DLL's path
## and answering as the helper prints. Empty means the helper. A suite sets it
## to a stand-in, as Linux has no PowerShell and no WinTab.
static var ask: Callable = Callable()

## The thread the helper runs on, null when none is.
static var _looking: Thread = null

## The running helper's process id, 0 before it starts. Written by the thread
## and read by `stop_looking`, under `_helper_lock`.
static var _helper_pid: int = 0

## True once `stop_looking` has let the look go, so a helper not yet started
## is never started.
static var _given_up: bool = false

## Keeps the thread from starting a helper while `stop_looking` ends one.
static var _helper_lock: Mutex = Mutex.new()

## The drivers on offer, in the engine's order. Never empty while a driver is in
## use, because a platform that names none still has the one it is using.
var names: PackedStringArray

## The driver in use.
var current: String

## Switches the live driver, called with the name.
var _switch: Callable

## Answers the driver the engine is using now, so the row can say so after a
## switch rather than repeat what it was built with. Empty means *current* is
## the answer.
var _read: Callable


func _init(
    driver_names: PackedStringArray, current_driver: String, switch: Callable = Callable(), read: Callable = Callable()
) -> void:
    names = driver_names
    current = current_driver
    if names.is_empty() and not current.is_empty():
        names.append(current)
    _switch = switch
    _read = read


## The drivers the running engine names.
static func engine_names() -> PackedStringArray:
    var found := PackedStringArray()
    for i in DisplayServer.tablet_get_driver_count():
        found.append(DisplayServer.tablet_get_driver_name(i))
    return found


## Switches to the driver the profile asked for, at launch. A stored name this
## engine does not offer is left alone, so a profile carried from Windows to
## Linux asks for nothing. The editor loads the autoload that calls this, and
## its own pen is not the painter's business.
static func apply_stored() -> void:
    var wanted := SaSettings.tablet_driver
    if wanted.is_empty() or Engine.is_editor_hint():
        return
    if engine_names().has(wanted) and DisplayServer.tablet_get_current_driver() != wanted:
        DisplayServer.tablet_set_current_driver(wanted)
    look_at_wintab()


## Starts the helper on a thread when the engine is on WinTab on Windows. The
## DLL is the one beside the executable when there is one, as the engine loads
## that before the system's.
static func look_at_wintab() -> void:
    if DisplayServer.get_name() != "Windows" or DisplayServer.tablet_get_current_driver() != "wintab":
        return
    var beside := OS.get_executable_path().get_base_dir().path_join("wintab32.dll")
    look_at(beside if FileAccess.file_exists(beside) else "wintab32.dll")


## Starts the look at the DLL at *path* on a thread, whatever the platform, so a
## suite on Linux can start it with a stand-in in `ask`. Nothing when a look is
## already running.
static func look_at(path: String) -> void:
    if _looking != null:
        return
    wintab_found = ""
    _helper_lock.lock()
    _given_up = false
    _helper_pid = 0
    _helper_lock.unlock()
    _looking = Thread.new()
    _looking.start(_look.bind(path, _looking))


## Lets the look go when Sara quits. The helper is ended rather than waited
## for, as PowerShell compiling its type can take seconds and nothing bounds
## it, and the thread is joined, so the engine never destroys it running. Its
## answer, should one still be queued, finds no thread of its own and is
## dropped. Nothing when no look is running.
static func stop_looking() -> void:
    if _looking == null:
        return
    _helper_lock.lock()
    _given_up = true
    if _helper_pid > 0:
        OS.kill(_helper_pid)
    _helper_lock.unlock()
    _looking.wait_to_finish()
    _looking = null


## The helper's answer for the DLL at *path*. Blocks until PowerShell exits or
## `stop_looking` ends it. Started with a pipe rather than through
## `OS.execute`, because only a process whose id Sara holds can be ended.
static func _ask(path: String) -> String:
    var command := WINTAB_LOOK.replace("{dll}", path.replace("'", "''"))
    var arguments := PackedStringArray(
        ["-NoProfile", "-NonInteractive", "-EncodedCommand", Marshalls.raw_to_base64(command.to_utf16_buffer())]
    )
    _helper_lock.lock()
    if _given_up:
        _helper_lock.unlock()
        return "unknown"
    var started := OS.execute_with_pipe("powershell", arguments)
    if not started.is_empty():
        _helper_pid = int(started["pid"])
    _helper_lock.unlock()
    if started.is_empty():
        return "unknown"
    var pipe: FileAccess = started["stdio"]
    var answer := ""
    while pipe.is_open() and pipe.get_error() == OK:
        var line := pipe.get_line().strip_edges()
        if answer.is_empty():
            answer = line
    pipe.close()
    return answer if answer in ["open", "failed", "absent"] else "unknown"


## The thread's body. *thread* is the one it runs on, so its answer can tell
## whether the look it belongs to is still the one running.
static func _look(path: String, thread: Thread) -> void:
    var asking: Callable = ask if ask.is_valid() else _ask
    _answered.call_deferred(String(asking.call(path)), thread)


## Joins the thread and goes to Windows Ink when the answer says to. An answer
## whose thread `stop_looking` has already joined is dropped, so a thread is
## never joined twice.
static func _answered(answer: String, thread: Thread) -> void:
    if _looking == null or thread != _looking:
        return
    _looking.wait_to_finish()
    _looking = null
    if _falls_back(answer):
        print("Sara: WinTab failed to start, so Windows Ink reads the pen for this session")
        DisplayServer.tablet_set_current_driver("winink")


## Keeps *answer*, and says whether the session goes to Windows Ink: WinTab
## could not open a context, the engine is still on it, and it offers Ink.
static func _falls_back(answer: String) -> bool:
    wintab_found = answer
    return answer == "failed" and DisplayServer.tablet_get_current_driver() == "wintab" and engine_names().has("winink")


## The rows of the dropdown, the id being the engine's name for the driver.
func choices() -> Array:
    var out: Array = []
    for driver_name: String in names:
        out.append({"id": driver_name, "label": label_of(driver_name)})
    return out


## What a painter reads for *driver_name*, translated and never lowercase.
## `auto` names the driver it picks here, "Automatic (Windows Ink)", because a
## bare "auto" says nothing about which pen code runs.
func label_of(driver_name: String) -> String:
    if driver_name == "auto":
        var picked := auto_pick()
        if picked.is_empty():
            return tr(String(LABELS["auto"]))
        return tr("Automatic (%s)") % label_of(picked)
    if LABELS.has(driver_name):
        return tr(String(LABELS[driver_name]))
    return driver_name.left(1).to_upper() + driver_name.substr(1)


## The driver `auto` resolves to among the ones on offer, or empty when none of
## the ones it tries is here.
func auto_pick() -> String:
    for candidate: String in AUTO_ORDER:
        if names.has(candidate):
            return candidate
    return ""


## The driver in use now, read from the engine when the model was handed a way
## to, which is what a switch to `auto` resolves to.
func in_use() -> String:
    if _read.is_valid():
        current = String(_read.call())
    return current


## True when WinTab could not start and another driver reads the pen instead.
func wintab_failed() -> bool:
    return wintab_found == "failed" and in_use() != "wintab"


## Uses *driver_name* now and at every later launch. False, and nothing
## written, when the engine does not offer it.
func choose(driver_name: String) -> bool:
    if not names.has(driver_name):
        return false
    current = driver_name
    SaSettings.tablet_driver = driver_name
    if _switch.is_valid():
        _switch.call(driver_name)
    look_at_wintab()
    return true
