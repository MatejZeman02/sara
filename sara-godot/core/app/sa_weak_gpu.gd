## Whether the running GPU is weak enough for Sara to offer the light mode, the
## rule written down beside the code that keeps it.
##
## **The rule.** A CPU device is offered, because a software rasteriser is the
## weakest thing Sara can run on. An integrated GPU is offered when the machine
## has less than [constant MEMORY_CEILING_BYTES] of memory. A discrete GPU is
## not offered, and neither is a virtual one or one the driver calls other,
## because what stands behind those is unknown and the Performance page is
## always there for a painter who wants it.
##
## **Why integrated alone is too loose.** An integrated GPU in a laptop with
## memory to spare, an `Intel(R) UHD Graphics (TGL GT1)` for one, paints Sara
## without the light mode. So the rule reads one more fact, the memory the device shares. An integrated GPU has no
## memory of its own, it draws from the machine's, and Godot names no video
## memory size (`RenderingDevice.get_device_total_memory` is what Sara has
## allocated, not what the card holds). The machine's memory is therefore the
## device's, and `OS.get_memory_info` says it without a dispatch. A machine sold
## with 8 GB, which the system reports as about 7.8 GiB, is under the ceiling.
## One sold with 16 GB, what a laptop with a discrete RTX beside its Intel is
## sold with, is over it. A stroke timed at start would be the other way, and
## it is not taken: it is a dispatch and a readback at a moment the
## kernels are still compiling, it lands on the first frame the painter waits
## for, and a figure from one stroke on a cold GPU says more about the driver's
## warm-up than about the device.
##
## Read once, at start, by whoever asks for [method read_running]. Until then
## nothing is judged and nothing is offered, which is how a suite and a
## scenario run: they never read the device, and a scenario that wants the offer
## says which device to pretend with [method fake].
@tool
class_name SaWeakGpu
extends RefCounted

## Below this much memory an integrated GPU is offered the light mode. Twelve
## GiB sits between the machines sold with 8 GB and those sold with 16 GB, so
## neither lands near the line whatever the firmware keeps back.
const MEMORY_CEILING_BYTES: int = 12 * 1024 * 1024 * 1024

## `RenderingDevice.DeviceType` by the word the dump and the scenario use.
const TYPE_NAMES := {
    RenderingDevice.DEVICE_TYPE_OTHER: "other",
    RenderingDevice.DEVICE_TYPE_INTEGRATED_GPU: "integrated",
    RenderingDevice.DEVICE_TYPE_DISCRETE_GPU: "discrete",
    RenderingDevice.DEVICE_TYPE_VIRTUAL_GPU: "virtual",
    RenderingDevice.DEVICE_TYPE_CPU: "cpu",
}

## The device being judged: `type`, `memory` in bytes, `name`, and `faked` when
## a scenario or a suite put it here. Empty until read or faked.
static var _device: Dictionary[String, Variant] = {}


## The rule itself, handed its two facts so a suite asks every answer without a
## GPU of that kind. *memory* is the machine's in bytes, 0 when unknown, and an
## unknown memory is not a reason to offer.
static func judge(type: int, memory: int) -> bool:
    match type:
        RenderingDevice.DEVICE_TYPE_CPU:
            return true
        RenderingDevice.DEVICE_TYPE_INTEGRATED_GPU:
            return memory > 0 and memory < MEMORY_CEILING_BYTES
    return false


## Why [method judge] answers as it does, in one line for a dump and a record.
static func reason(type: int, memory: int) -> String:
    var gib := "%.1f GiB" % (float(memory) / float(1024 * 1024 * 1024))
    match type:
        RenderingDevice.DEVICE_TYPE_CPU:
            return "a CPU device is always offered"
        RenderingDevice.DEVICE_TYPE_INTEGRATED_GPU:
            if memory <= 0:
                return "integrated, and the machine did not say its memory"
            if judge(type, memory):
                return "integrated with %s, under the 12 GiB ceiling" % gib
            return "integrated with %s, at or over the 12 GiB ceiling" % gib
    return "a %s device is not offered" % type_name(type)


## The running app's device and the machine's memory, read from what Godot
## already knows. Allocates nothing on the GPU and dispatches nothing.
static func read_running() -> void:
    _device = running()


## What the running device is, without keeping it: the dump's line for a run
## that pretends another device, so the record still names the real one.
static func running() -> Dictionary[String, Variant]:
    var memory_info := OS.get_memory_info()
    var physical: int = memory_info.get("physical", 0)
    return {
        "type": RenderingServer.get_video_adapter_type(),
        "memory": physical,
        "name": RenderingServer.get_video_adapter_name(),
        "faked": false,
    }


## Judges *type_word*, one of [constant TYPE_NAMES]' words, with *memory* bytes,
## in place of the running device. A word the table does not have is other.
static func fake(type_word: String, memory: int) -> void:
    var type: int = RenderingDevice.DEVICE_TYPE_OTHER
    for known: int in TYPE_NAMES:
        if TYPE_NAMES[known] == type_word:
            type = known
    _device = {"type": type, "memory": memory, "name": "faked %s" % type_word, "faked": true}


## Nothing judged again, as a process starts.
static func forget() -> void:
    _device = {}


## Whether the device read or faked is one the rule offers, and false while
## none has been.
static func weak() -> bool:
    if _device.is_empty():
        return false
    var type: int = _device["type"]
    var memory: int = _device["memory"]
    return judge(type, memory)


## The device judged, with the rule's answer and its reason, for a dump.
static func state() -> Dictionary[String, Variant]:
    if _device.is_empty():
        return {"judged": false}
    var type: int = _device["type"]
    var memory: int = _device["memory"]
    return {
        "judged": true,
        "name": _device["name"],
        "type": type_name(type),
        "memory": memory,
        "faked": _device["faked"],
        "weak": judge(type, memory),
        "reason": reason(type, memory),
    }


static func type_name(type: int) -> String:
    return str(TYPE_NAMES.get(type, "other"))
