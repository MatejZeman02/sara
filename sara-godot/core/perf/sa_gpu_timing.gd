## GPU time per kernel and per category, from pairs of timestamp queries.
##
## The half of a stroke's cost GDScript cannot see: `SaEasel` times the issuing
## of a composite and says the GPU "finishes later and cannot be timed from here
## without a stall". A timestamp query is the way round it. The driver stamps the
## command stream where the capture was recorded, and the answer is read back
## frames later as a number, so nothing waits, nothing is dispatched to measure
## and no texel leaves VRAM (hard rules 1 and 2).
##
## **Behind a flag, and the only measure that is.** The engine's pool is 256
## captures per drawn frame, `--gpu-profile` shares it, and a stroke frame opens
## dozens of lists, so pairs that were always on would log engine errors on
## exactly the frames worth measuring. `enabled` is off until a window turns it
## on, and with it off every call here returns on its first line.
##
## **Two kinds of pair.** A list pair brackets one compute list from outside,
## because the engine refuses a capture while a list is open, and is keyed by the
## `shader/kernel` label the list was begun under. A category pair brackets a
## whole composite or a whole stroke commit. The categories draw on a reserve of
## their own, so a frame that opens more lists than the pool holds still times
## its composite, and every pair that did not fit is counted in `skipped` under
## its key rather than handed to the engine to refuse.
##
## **A list read inside the step.** A buffer read on the main device flushes
## the device and moves it to its next frame slot without a drawn frame, so the
## slot it lands in hands back the captures of a flush or a drawn frame before,
## and the next read hands back the next. `collect()` runs once a process frame
## and the wand reads five times inside one step, so without a fold at each
## read its kernels would read `untimed`. `read_done` folds the
## slot after every read and times the read itself, which is the CPU waiting on
## the card, under the key of the last list closed before it.
##
## Everything folds into count, sum and max per key. No list of samples grows
## with the stroke.
@tool
class_name SaGpuTiming
extends RefCounted

## The most captures this takes in one drawn frame, under the engine's pool of
## 256 so the frame's own captures and a late pair still fit.
const CEILING: int = 250

## How many of those are kept for the category pairs.
const CATEGORY_RESERVE: int = 8

## What every capture name starts with, so the engine's own entries in the same
## pool are passed over.
const PREFIX: String = "sa"

## Above this many GPU ticks per CPU microsecond the driver is counting
## nanoseconds, below it microseconds. The geometric middle of 1 and 1000.
const NANOSECOND_THRESHOLD: float = 31.6

## Whether pairs are captured at all. Written by whoever opens a measuring
## window, and by nothing on a painter's path.
static var enabled: bool = false

static var _kernels: Dictionary[String, Dictionary] = {}
static var _categories: Dictionary[String, Dictionary] = {}

## The buffer reads on the main device, by the key of the list closed last
## before each: how many, and the microseconds the CPU spent in them.
static var _reads: Dictionary[String, Dictionary] = {}

## The key of the list the main device closed last, which is whose result a
## read that follows it is waiting for.
static var _last_list: String = ""

## The drawn frame the two counts below belong to.
static var _count_frame: int = -1
static var _list_captures: int = 0
static var _category_captures: int = 0

## The running index that makes every pair's two names unique.
static var _next_index: int = 0

## The begin names still waiting for their end, by key. A list is one at a time
## on a device and a category does not nest in itself, so one slot per key.
static var _open: Dictionary[String, String] = {}

## The name of the first capture of ours in the slot `collect()` folded last,
## which is what makes it safe to call from every easel's `_process` and after
## every read. The slot's frame index cannot tell two slots apart, because a
## read moves the device on and not the drawn frame the index is taken from.
static var _collected_first: String = ""
static var _frames_collected: int = 0

static var _first_gpu: int = -1
static var _first_cpu: int = -1
static var _last_gpu: int = -1
static var _last_cpu: int = -1

## How many drawn frames after its capture an entry became readable, smallest
## and largest seen: the index the device gives the readable frame, less the
## drawn frame the capture's own name carries. A forced draw moves the device on
## and not `Engine.get_frames_drawn()`, so a run of forced draws reads 0.
static var _readable_after_min: int = -1
static var _readable_after_max: int = -1


## Forgets every figure. The flag is left as it is, because a window resets
## after it has turned the flag on.
static func reset() -> void:
    _kernels.clear()
    _categories.clear()
    _reads.clear()
    _last_list = ""
    _open.clear()
    _count_frame = -1
    _list_captures = 0
    _category_captures = 0
    _collected_first = ""
    _frames_collected = 0
    _first_gpu = -1
    _first_cpu = -1
    _last_gpu = -1
    _last_cpu = -1
    _readable_after_min = -1
    _readable_after_max = -1


## Called by a dispatch list before it opens its compute list on *rd*.
static func list_pair_begin(rd: RenderingDevice, label: String) -> void:
    if not enabled:
        return
    var main := _main_device()
    if main == null or rd != main:
        return
    _roll_frame()
    if _list_captures + 2 > CEILING - CATEGORY_RESERVE:
        _entry(_kernels, label)["skipped"] += 1
        return
    _list_captures += 2
    _open["L|" + label] = _capture(main, "L", label)


## Called by a dispatch list after it has closed its compute list. Captures only
## when the matching begin did, so a pair is never half taken.
static func list_pair_end(label: String) -> void:
    if not enabled:
        return
    _last_list = label
    _close(_main_device(), "L|" + label)


## Called by a buffer after a read on *rd* came back, *waited_usec* after it
## was asked for. The read flushed the device into a fresh slot, whose pool is
## empty and whose answers are the captures of an earlier slot, so the counts
## start again and the answers are folded now, before the next read replaces
## them.
static func read_done(rd: RenderingDevice, waited_usec: int) -> void:
    if not enabled:
        return
    var main := _main_device()
    if main == null or rd != main:
        return
    var key := _last_list if _last_list != "" else "read"
    if not _reads.has(key):
        var fresh: Dictionary[String, int] = {"reads": 0, "wait_usec": 0, "wait_usec_max": 0}
        _reads[key] = fresh
    var entry: Dictionary[String, int] = _reads[key]
    entry["reads"] += 1
    entry["wait_usec"] += waited_usec
    entry["wait_usec_max"] = maxi(entry["wait_usec_max"], waited_usec)
    _list_captures = 0
    _category_captures = 0
    collect()


## Opens the category pair *category*: `composite` or `commit`.
static func category_begin(category: String) -> void:
    if not enabled:
        return
    var main := _main_device()
    if main == null:
        return
    _roll_frame()
    if _category_captures + 2 > CATEGORY_RESERVE:
        _entry(_categories, category)["skipped"] += 1
        return
    _category_captures += 2
    _open["C|" + category] = _capture(main, "C", category)


## Closes the category pair and adds *work*, the size of the work the pair
## bracketed, to the category's sums. The load is CPU knowledge, so it is kept
## whether or not the pair fitted in the pool.
static func category_end(category: String, work: Dictionary[String, int]) -> void:
    if not enabled:
        return
    var entry := _entry(_categories, category)
    var sums: Dictionary[String, int] = entry["load"]
    for key: String in work:
        sums[key] = sums.get(key, 0) + work[key]
    _close(_main_device(), "C|" + category)


## Folds whatever captured frame the device has made readable. Idempotent per
## captured frame, so every easel may call it every process frame.
static func collect() -> void:
    if not enabled:
        return
    var main := _main_device()
    if main == null:
        return
    var count := main.get_captured_timestamps_count()
    if count == 0:
        return
    var frame := int(main.get_captured_timestamps_frame())
    var first := _first_name(main, count)
    if first == "" or first == _collected_first:
        return
    _collected_first = first

    var begins: Dictionary[String, Array] = {}
    var found := false
    for i: int in count:
        var parts := main.get_captured_timestamp_name(i).split("|")
        if parts.size() != 6 or parts[0] != PREFIX:
            continue
        found = true
        var gpu := int(main.get_captured_timestamp_gpu_time(i))
        var cpu := int(main.get_captured_timestamp_cpu_time(i))
        if _first_gpu < 0:
            _first_gpu = gpu
            _first_cpu = cpu
        _last_gpu = gpu
        _last_cpu = cpu
        var pair_id := parts[1] + parts[2]
        if parts[5] == "b":
            begins[pair_id] = [gpu, cpu]
            _note_readable_after(frame - int(parts[3]))
            continue
        if not begins.has(pair_id):
            continue
        var begun: Array = begins[pair_id]
        var table := _kernels if parts[1] == "L" else _categories
        var begun_gpu: int = begun[0]
        var begun_cpu: int = begun[1]
        _fold(_entry(table, parts[4]), gpu - begun_gpu, cpu - begun_cpu)
    if found:
        _frames_collected += 1


## The name of the first capture of ours among the *count* the device answers,
## or empty when none is ours.
static func _first_name(main: RenderingDevice, count: int) -> String:
    for i: int in count:
        var name := main.get_captured_timestamp_name(i)
        if name.begins_with(PREFIX + "|"):
            return name
    return ""


## The figures as one dictionary, a deep copy. Times are raw driver ticks beside
## the divisor that turns them into microseconds, because the class reference
## says microseconds and the Intel driver counts nanoseconds.
static func block() -> Dictionary[String, Variant]:
    var skipped := 0
    for table: Dictionary[String, Dictionary] in [_kernels, _categories]:
        for key: String in table:
            var entry_skipped: int = table[key]["skipped"]
            skipped += entry_skipped
    return {
        "enabled": enabled,
        "device": "main" if _main_device() != null else "local",
        "frames_collected": _frames_collected,
        "ticks_per_usec": _ticks_per_usec(),
        "skipped": skipped,
        "readable_after_min": _readable_after_min,
        "readable_after_max": _readable_after_max,
        "kernels": _kernels.duplicate(true),
        "categories": _categories.duplicate(true),
        "reads": _reads.duplicate(true),
    }


## The main device, the only one whose captures are ever resolved: a local
## device advances no frame of its own unless somebody submits and syncs it,
## which is the stall this exists to avoid.
static func _main_device() -> RenderingDevice:
    return RenderingServer.get_rendering_device()


static func _roll_frame() -> void:
    var drawn := Engine.get_frames_drawn()
    if drawn == _count_frame:
        return
    _count_frame = drawn
    _list_captures = 0
    _category_captures = 0


## Captures the begin half and answers the name of the end half.
static func _capture(rd: RenderingDevice, kind: String, key: String) -> String:
    var stem := "%s|%s|%d|%d|%s|" % [PREFIX, kind, _next_index, Engine.get_frames_drawn(), key]
    _next_index += 1
    rd.capture_timestamp(stem + "b")
    return stem + "e"


static func _close(rd: RenderingDevice, slot: String) -> void:
    if not _open.has(slot):
        return
    var end_name: String = _open[slot]
    _open.erase(slot)
    if rd != null:
        rd.capture_timestamp(end_name)


static func _entry(table: Dictionary[String, Dictionary], key: String) -> Dictionary[String, Variant]:
    if not table.has(key):
        var sums: Dictionary[String, int] = {}
        var fresh: Dictionary[String, Variant] = {
            "pairs": 0, "gpu_ticks": 0, "gpu_ticks_max": 0, "cpu_usec": 0, "cpu_usec_max": 0, "skipped": 0, "load": sums
        }
        table[key] = fresh
    return table[key]


static func _fold(entry: Dictionary[String, Variant], gpu_ticks: int, cpu_usec: int) -> void:
    entry["pairs"] += 1
    entry["gpu_ticks"] += gpu_ticks
    var gpu_ticks_max: int = entry["gpu_ticks_max"]
    var cpu_usec_max: int = entry["cpu_usec_max"]
    entry["gpu_ticks_max"] = maxi(gpu_ticks_max, gpu_ticks)
    entry["cpu_usec"] += cpu_usec
    entry["cpu_usec_max"] = maxi(cpu_usec_max, cpu_usec)


static func _note_readable_after(after: int) -> void:
    if _readable_after_min < 0 or after < _readable_after_min:
        _readable_after_min = after
    _readable_after_max = maxi(_readable_after_max, after)


## 1000 when the driver counts nanoseconds, 1 when it counts microseconds, 0
## when the window holds too little to tell.
static func _ticks_per_usec() -> int:
    var cpu_span := _last_cpu - _first_cpu
    var gpu_span := _last_gpu - _first_gpu
    if cpu_span <= 0 or gpu_span <= 0:
        return 0
    return 1000 if float(gpu_span) / float(cpu_span) > NANOSECOND_THRESHOLD else 1
