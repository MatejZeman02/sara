## How much memory the graphics card has, how much of it the open documents
## hold, and whether a new document fits beside them.
##
## The limit is what the card holds and not a count of documents, because a
## fixed count would refuse a fifth small sketch to keep out one huge painting.
## New and Open ask `refusal` before they build anything, and a document that
## would take what open documents hold past the card's memory less a margin is
## refused with a sentence giving the budget, the card and the two numbers.
##
## **Where the card's memory comes from.** Godot 4.7 answers what its device
## has allocated, `get_memory_usage`, and nothing about the size of the card's
## heaps, so the number is read off the system, once, and kept:
##
## - NVIDIA, on Linux and on Windows alike: `nvidia-smi`, which the driver
##   installs on both, asked for `memory.total`.
## - AMD on Linux: the amdgpu driver's `mem_info_vram_total` under
##   `/sys/class/drm`.
## - Any discrete card on Windows the above did not answer: the display
##   adapter's `HardwareInformation.qwMemorySize` in the registry, which the
##   driver writes and `dxdiag` reads.
## - An integrated card has no memory of its own and takes the system's. Mesa
##   gives it a heap of three quarters of the system's memory, half at 4 GiB or
##   less, and Windows shares half, so that share of `OS.get_memory_info()` is
##   its memory. Android answers that with -1, so where it gives no figure the
##   share is taken of `MemTotal` in `/proc/meminfo`, which Android and Linux
##   both write. On Android every card is read this way, whatever type it
##   reports, since none of the readings above answers there.
##
## `--card-memory=<MiB>` on the command line stands in for all of them.
##
## A card none of these reads answers 0, and nothing is refused: a limit made
## up where the card says nothing would be the fixed count this class exists to
## avoid. The query is of the system and never of the canvas, so hard rule 1 is
## untouched.
##
## **What a document needs** was measured on the card and read texture by
## texture: the easel's canvas-sized textures
## cost 32 bytes a canvas texel before a stroke, the fold's bottom cache 16
## more a canvas texel once anything is painted, and a painted texel 16. So a
## document with a paint layer costs 48 bytes a canvas texel and 16 a texel of
## paint beyond it.
class_name SaCardMemory
extends RefCounted

## The easel's canvas-sized textures, per canvas texel, measured on an empty
## document.
const CANVAS_BYTES_PER_TEXEL := 32
## `SaLayerFold.bottom_cache`, per canvas texel and charged once. It is an
## RGBA32F texture made by `core/composite/sa_layer_fold.gd`, 16 bytes of a
## canvas texel and once, growing with the canvas and not the view, made when
## the first paint layer goes over the background. A document with paint
## on the background alone would not need it, and is charged it all the same,
## which errs towards refusing rather than towards running the card out.
const FOLD_CACHE_BYTES_PER_TEXEL := 16
## A chunk's colour field, per painted texel, an RGBA32F texture made by
## `core/api/document/sa_chunk.gd`, growing with the painted area by whole
## chunk: every chunk painted after the first adds its 16 bytes
## and no more, at 1024 and at 4096 alike.
const PAINTED_BYTES_PER_TEXEL := 16
## What is kept back for the desktop, the engine's own textures and pipelines,
## and the history a painting grows: a tenth of the card, and never under a
## GiB, because the driver was measured counting up to 0.7 GiB above Sara's
## own.
const MARGIN_SHARE := 0.1
const MARGIN_FLOOR := 1 << 30

## The refusal, given the budget, the card's memory, what the open documents
## hold and what the new one needs. The budget leads because it is the figure the painter set and can raise again in Preferences.
# gdlint:ignore=max-line-length
const NO_ROOM := "There is no room on the graphics card for another document. Sara keeps to a budget of %s of the card's %s, the open documents hold %s and this one needs %s. Close a document and try again."
## The command line's stand-in for the card's memory, in MiB.
const FLAG := "--card-memory="

const _GIB := 1 << 30
const _MIB := 1 << 20
## The registry key every display adapter of Windows sits under.
const _DISPLAY_CLASS := "HKLM\\SYSTEM\\CurrentControlSet\\Control\\Class\\{4d36e968-e325-11ce-bfc1-08002be10318}"

## A figure a suite put in place of the card's, or -1 for the card's own.
static var _stood_in := -1
## The card's memory once read, -1 until then and 0 when nothing read it.
static var _read := -1
## Where `_read` came from, in words, for the log and the Done paragraph.
static var _source := ""
## The adapter and the system a suite put in place of this machine's, null
## for this machine's own.
static var _machine_adapter: Adapter = null
static var _machine_system: System = null
## The worker task `read_aside` started, -1 when none is pending.
static var _task := -1
## What the worker read, kept apart from `_read` until `total` has waited on it.
static var _aside := -1


## Starts the reading on a worker thread, so that nothing on the main thread
## waits for it later. The boot calls it. Otherwise the first stroke after a
## start pays for `nvidia-smi` at its release, 20 ms and more of one frame,
## since a painting pass's settle is the first to ask for `total`. The
## adapter is asked here on the calling thread, and only the system is read
## on the worker, which `total` waits for when it is asked before the worker
## is done.
static func read_aside() -> void:
    if _read >= 0 or _task >= 0:
        return
    _read = _flagged()
    if _read >= 0:
        print("SaCardMemory: %d bytes, from %s" % [_read, _source])
        return
    var adapter := _adapter()
    var stood_system := _machine_system
    _task = WorkerThreadPool.add_task(
        func() -> void: _aside = _reading(adapter, stood_system if stood_system != null else System.this_machine()),
        false,
        "card memory"
    )


## Collects the worker task `read_aside` started, which the boot's exit calls.
## **A finished task keeps its lambda until somebody waits for it.** A quit
## before the first `total` left the task's callable, and the adapter and
## system it holds, with the worker pool, which drops them after GDScript is
## gone, where freeing a lambda's script locks the language's mutex through a
## null singleton and aborts the engine (the pitfall "A worker task nobody
## waited for aborts the engine at exit"). Waiting here frees them while the
## language is still up, and keeps the figure for any `total` after it.
static func finish_aside() -> void:
    if _task < 0:
        return
    WorkerThreadPool.wait_for_task_completion(_task)
    _task = -1
    _read = _aside


## Puts *bytes* in place of the card's memory, and -1 gives the card's back. A
## suite's door, so that a refusal can be read on any machine.
static func stand_in(bytes: int) -> void:
    _stood_in = bytes


## Puts *adapter* and *system* in place of this machine's and forgets what
## was read, so the next `total` reads them, once. Null for both gives this
## machine back and forgets again. A suite's door, so that an integrated card
## on a system with no memory figure can be read on any machine.
static func stand_in_machine(adapter: Adapter, system: System) -> void:
    if _task >= 0:
        WorkerThreadPool.wait_for_task_completion(_task)
        _task = -1
    _machine_adapter = adapter
    _machine_system = system
    _read = -1
    _aside = -1
    _source = ""


## The card's memory in bytes, 0 when no reading answered.
static func total() -> int:
    if _stood_in >= 0:
        return _stood_in
    if _task >= 0:
        WorkerThreadPool.wait_for_task_completion(_task)
        _task = -1
        _read = _aside
        print("SaCardMemory: %d bytes, from %s, read aside" % [_read, _source])
        return _read
    if _read >= 0:
        return _read
    _read = _flagged()
    if _read < 0:
        _read = _reading(_adapter(), _machine_system if _machine_system != null else System.this_machine())
    print("SaCardMemory: %d bytes, from %s" % [_read, _source])
    return _read


## Where the figure `total` answers was read, in words.
static func source() -> String:
    if _stood_in >= 0:
        return "a figure stood in"
    total()
    return _source


## What the open documents hold now: every texture Sara allocated, the easels,
## the layers and the history of all of them.
static func held() -> int:
    return SaTexture.allocated_bytes


## What is kept back from a card of *card* bytes.
static func margin(card: int) -> int:
    return maxi(MARGIN_FLOOR, roundi(float(card) * MARGIN_SHARE))


## What a document of *size* needs with *painted* texels of paint on it: the
## easel's textures over the canvas, the fold's bottom cache once beside them
## when anything is painted, and a chunk's colour field a painted texel.
static func for_canvas(size: Vector2i, painted: int = 0) -> int:
    var texels := size.x * size.y
    var cache := texels * FOLD_CACHE_BYTES_PER_TEXEL if painted > 0 else 0
    return texels * CANVAS_BYTES_PER_TEXEL + cache + painted * PAINTED_BYTES_PER_TEXEL


## What the `.sad` at *path* needs once open, from its header: its canvas, and
## every chunk of every layer at the resolution it was saved at. Zero for a
## file whose header does not read, which the loader then refuses on its own.
static func for_sad(path: String) -> int:
    var header := SaSadFile.header_at(path)
    if header.is_empty():
        return 0
    var size := Vector2i(SaTyped.int_at(header, "width", 0), SaTyped.int_at(header, "height", 0))
    var painted := 0
    for raw_layer: Variant in SaTyped.list(header.get("layers")):
        var layer := SaTyped.strings(raw_layer)
        for raw_chunk: Variant in SaTyped.list(layer.get("chunks")):
            var chunk := SaTyped.strings(raw_chunk)
            # The edge `SaChunk.pixel_size()` gives a chunk of this scale. No
            # chunk exists yet to ask, so its formula is applied to the scale.
            var scale := SaTyped.float_at(chunk, "resolution_scale", 1.0)
            var edge := maxi(1, roundi(float(SaChunk.SIZE) * scale))
            painted += edge * edge
    return for_canvas(size, painted)


## The sentence refusing a document that needs *needed* bytes beside the
## *held_now* the open documents hold, or an empty one when it fits or the
## card's memory is not known. *held_now* is `held()` when left at -1.
static func refusal(needed: int, held_now: int = -1) -> String:
    var figures := _figures_past_room(needed, held_now)
    return "" if figures.is_empty() else TranslationServer.translate(NO_ROOM) % figures


## Whether a document needing *needed* bytes is refused, the refusal said in
## the corner when it is. What New and Open ask before they build anything.
static func refuses(needed: int, held_now: int = -1) -> bool:
    var figures := _figures_past_room(needed, held_now)
    if figures.is_empty():
        return false
    SaProblems.refuse("SaCardMemory", TranslationServer.translate(NO_ROOM) % figures)
    return true


## The budget, the card's memory, what is held and what is needed, in words,
## when the document does not fit, and nothing when it does or the card is not
## known.
static func _figures_past_room(needed: int, held_now: int) -> Array:
    var card := total()
    if card <= 0:
        return []
    if held_now < 0:
        held_now = held()
    if held_now + needed <= card - margin(card):
        return []
    return [size_words(SaMemoryBudget.budget(card)), size_words(card), size_words(held_now), size_words(needed)]


## *bytes* in GiB from one GiB up and in MiB below it, as a painter reads them.
static func size_words(bytes: int) -> String:
    if bytes >= _GIB:
        return TranslationServer.translate("%.1f GiB") % (float(bytes) / _GIB)
    return TranslationServer.translate("%.0f MiB") % (float(bytes) / _MIB)


# --- The reading --------------------------------------------------------------


## The `--card-memory=<MiB>` Sara was started with, -1 without one. A scenario
## stands a small card in by it, and so can a painter who wants Sara to keep
## to less of the card than it has.
static func _flagged() -> int:
    var args := OS.get_cmdline_args() + OS.get_cmdline_user_args()
    for arg in args:
        if arg.begins_with(FLAG):
            _source = arg
            return maxi(0, arg.trim_prefix(FLAG).to_int()) * _MIB
    return -1


## The adapter a suite stood in, or this machine's, asked on the calling
## thread.
static func _adapter() -> Adapter:
    return _machine_adapter if _machine_adapter != null else Adapter.new()


## The card's memory as *system* tells it for *adapter*. Runs on a worker
## thread when `read_aside` started it, so it asks nothing of the rendering
## server.
static func _reading(adapter: Adapter, system: System) -> int:
    var name := adapter.name
    # An Android device's card takes the system's memory whatever type it
    # reports, and no other reading answers there. The emulator reports the
    # host's card as discrete, and without this it read 0.
    if system.platform == "Android":
        return _shared(system, "%s on Android" % name)
    if (name + adapter.vendor).to_lower().contains("nvidia"):
        var nvidia := _nvidia_smi(name)
        if nvidia > 0:
            return nvidia
    if adapter.type == RenderingDevice.DEVICE_TYPE_INTEGRATED_GPU:
        return _shared(system, "an integrated card")
    if OS.get_name() == "Windows":
        var registry := _windows_registry()
        if registry > 0:
            return registry
    else:
        var sysfs := _amdgpu_sysfs()
        if sysfs > 0:
            return sysfs
    _source = "nothing, %s answered no reading" % name
    return 0


## `nvidia-smi`'s total for the card named *name*, or for its only card.
static func _nvidia_smi(name: String) -> int:
    var out: Array = []
    var args := PackedStringArray(["--query-gpu=name,memory.total", "--format=csv,noheader,nounits"])
    if OS.execute("nvidia-smi", args, out) != 0 or out.is_empty():
        return 0
    var bytes := nvidia_bytes(str(out[0]), name)
    if bytes > 0:
        _source = "nvidia-smi, memory.total of %s" % name
    return bytes


## The total *text*, `nvidia-smi`'s lines of a name and MiB, gives the card
## named *name*, or its only card. Public so a suite reads the parse with no
## NVIDIA card.
static func nvidia_bytes(text: String, name: String) -> int:
    var lines := text.strip_edges().split("\n")
    for line in lines:
        var parts := line.rsplit(",", true, 1)
        if parts.size() == 2 and (lines.size() == 1 or parts[0].strip_edges() == name):
            return parts[1].strip_edges().to_int() * _MIB
    return 0


## The largest `mem_info_vram_total` the amdgpu driver writes under `/sys`.
static func _amdgpu_sysfs() -> int:
    var largest := 0
    for card in DirAccess.get_directories_at("/sys/class/drm"):
        var path := "/sys/class/drm/%s/device/mem_info_vram_total" % card
        if FileAccess.file_exists(path):
            var bytes := FileAccess.get_file_as_string(path).strip_edges().to_int()
            if bytes > largest:
                largest = bytes
                _source = path
    return largest


## The largest `HardwareInformation.qwMemorySize` among Windows's display
## adapters.
static func _windows_registry() -> int:
    var out: Array = []
    var args := PackedStringArray(["query", _DISPLAY_CLASS, "/s", "/v", "HardwareInformation.qwMemorySize"])
    if OS.execute("reg", args, out) != 0 or out.is_empty():
        return 0
    var largest := registry_bytes(str(out[0]))
    if largest > 0:
        _source = "the registry's HardwareInformation.qwMemorySize"
    return largest


## The largest size in *text*, what `reg query` prints, one REG_QWORD in
## hexadecimal a line. Public so a suite reads the parse off Windows.
static func registry_bytes(text: String) -> int:
    var largest := 0
    for line in text.split("\n"):
        var at := line.find("0x")
        if line.contains("REG_QWORD") and at >= 0:
            largest = maxi(largest, line.substr(at + 2).strip_edges().hex_to_int())
    return largest


## The share of *system*'s memory *card* is given, 0 when the system gives no
## figure. A -1 kept as the reading would read as not read yet, and be read
## and said again at every ask.
static func _shared(system: System, card: String) -> int:
    var physical := SaTyped.int_at(SaTyped.strings(system.info), "physical", 0)
    var whose := "the system's memory"
    if physical <= 0:
        physical = meminfo_bytes(system.meminfo)
        whose = "the MemTotal of /proc/meminfo"
    if physical <= 0:
        _source = "nothing, the system gave no figure of its memory for %s" % card
        return 0
    if system.platform == "Windows" or physical <= 4 * _GIB:
        _source = "half of %s, shared with %s" % [whose, card]
        return physical >> 1
    _source = "three quarters of %s, shared with %s" % [whose, card]
    return (physical >> 2) * 3


## The `MemTotal` of *text*, what `/proc/meminfo` holds, in bytes, 0 without
## one. The file gives it in kB, which the kernel means as KiB.
static func meminfo_bytes(text: String) -> int:
    for line in text.split("\n"):
        var parts := line.split(":", true, 1)
        if parts.size() == 2 and parts[0] == String(&"MemTotal"):
            return parts[1].strip_edges().trim_suffix("kB").strip_edges().to_int() << 10
    return 0


## The graphics adapter as the rendering server names it, read on the thread
## that builds it so a worker reading the system never asks the server.
class Adapter:
    extends RefCounted
    var name := RenderingServer.get_video_adapter_name()
    var vendor := RenderingServer.get_video_adapter_vendor()
    var type := RenderingServer.get_video_adapter_type()

    ## The server's adapter, or one of *stood_type* named *stood_name* that
    ## a suite stands in.
    func _init(stood_type: int = -1, stood_name: String = "") -> void:
        if stood_type >= 0:
            type = stood_type as RenderingDevice.DeviceType
            name = stood_name
            vendor = ""


## What the system says of its memory: the engine's memory info and the text of
## `/proc/meminfo`, empty where there is none, and the name of the system as
## `OS.get_name` gives it.
class System:
    extends RefCounted
    var info: Dictionary
    var meminfo: String
    var platform: String

    func _init(given_info: Dictionary, given_meminfo: String, given_platform: String = OS.get_name()) -> void:
        info = given_info
        meminfo = given_meminfo
        platform = given_platform

    ## This machine's, read on the calling thread, which may be a worker.
    static func this_machine() -> System:
        var text := ""
        if OS.get_name() in ["Linux", "Android"]:
            text = proc_text("/proc/meminfo")
        return System.new(OS.get_memory_info(), text)

    ## The text of the kernel's file at *path*, empty when nothing reads it.
    ## A file under `/proc` gives its length as 0, and
    ## `FileAccess.get_file_as_string` reads that many bytes, so it answered
    ## an empty `/proc/meminfo` on Linux. Line by line reads until the kernel
    ## says the end. On Android the engine's file access goes through the
    ## app's storage and refuses `/proc` outright, `file_exists` false and the
    ## open failing, while `cat` run as the app reads it, so that is asked
    ## when the open fails.
    static func proc_text(path: String) -> String:
        var file := FileAccess.open(path, FileAccess.READ)
        if file == null:
            var out: Array = []
            if OS.execute("cat", PackedStringArray([path]), out) != 0 or out.is_empty():
                return ""
            return str(out[0])
        var lines := PackedStringArray()
        while true:
            var line := file.get_line()
            if file.eof_reached() and line.is_empty():
                break
            lines.append(line)
        return "\n".join(lines)
