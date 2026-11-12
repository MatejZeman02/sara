## An integrated card on a system whose memory info gives no physical figure
## takes its share of `MemTotal` in `/proc/meminfo`, and with neither figure its
## memory is 0, read once and said once.
##
## Android answers `OS.get_memory_info()` with -1 for physical memory, and the
## tablet's log said `SaCardMemory: -1 bytes` at every ask, since -1 is what
## the reading keeps for not read yet. These stand an integrated adapter and a
## system in for the machine's, so they read the same on any card.
extends "res://tests/test_framework.gd"

const GIB := 1 << 30
## A tablet of 8 GiB as `/proc/meminfo` writes it, in kB.
const MEMINFO := "MemTotal:        8388608 kB\nMemFree:         1234567 kB\nMemAvailable:    4567890 kB\n"


func after_each() -> void:
    SaCardMemory.stand_in_machine(null, null)


func _integrated() -> SaCardMemory.Adapter:
    return SaCardMemory.Adapter.new(RenderingDevice.DEVICE_TYPE_INTEGRATED_GPU, "a tablet's card")


## No physical figure and a `MemTotal` line: the share of that total, and a
## source naming `/proc/meminfo`.
func test_no_physical_figure_takes_the_share_of_memtotal() -> void:
    SaCardMemory.stand_in_machine(_integrated(), SaCardMemory.System.new({"physical": -1}, MEMINFO))
    var expected := (8 * GIB) >> 1 if OS.get_name() == "Windows" else ((8 * GIB) >> 2) * 3
    assert_eq(SaCardMemory.total(), expected, "the share of MemTotal was not taken")
    var source := SaCardMemory.source()
    assert_true(source.contains("/proc/meminfo"), "the source does not name /proc/meminfo: %s" % source)


## A small system's `MemTotal` takes half, as its physical figure would.
func test_a_small_memtotal_takes_half() -> void:
    var small := "MemTotal:        3145728 kB\n"
    SaCardMemory.stand_in_machine(_integrated(), SaCardMemory.System.new({"physical": -1}, small))
    assert_eq(SaCardMemory.total(), (3 * GIB) >> 1, "a 3 GiB system did not give half")
    assert_true(SaCardMemory.source().begins_with("half of the MemTotal"), "the source reads: %s" % SaCardMemory.source())


## A physical figure the engine gives still leads over `/proc/meminfo`.
func test_a_physical_figure_leads() -> void:
    SaCardMemory.stand_in_machine(_integrated(), SaCardMemory.System.new({"physical": 2 * GIB}, MEMINFO))
    assert_eq(SaCardMemory.total(), GIB, "the engine's figure was not the one shared")
    assert_true(SaCardMemory.source().contains("the system's memory"), "the source reads: %s" % SaCardMemory.source())


## Neither figure: 0, and three asks leave one `SaCardMemory:` line.
func test_no_figure_is_zero_read_and_said_once() -> void:
    SaCardMemory.stand_in_machine(_integrated(), SaCardMemory.System.new({"physical": -1}, ""))
    var catcher := SaErrorCatcher.listening()
    var answers: Array[int] = [SaCardMemory.total(), SaCardMemory.total(), SaCardMemory.total()]
    catcher.stop()
    assert_eq(answers, [0, 0, 0] as Array[int], "the unknown memory did not read as 0 at every ask")
    var lines := 0
    for line in catcher.printed():
        if line.begins_with("SaCardMemory:"):
            lines += 1
    assert_eq(lines, 1, "the unknown memory was said %d times" % lines)
    assert_true(SaCardMemory.source().begins_with("nothing"), "the source reads: %s" % SaCardMemory.source())


## The parse of `/proc/meminfo` on its own: kB read as KiB, 0 without the line.
func test_meminfo_parse() -> void:
    assert_eq(SaCardMemory.meminfo_bytes(MEMINFO), 8 * GIB, "MemTotal was misread")
    assert_eq(SaCardMemory.meminfo_bytes("MemFree: 12 kB\n"), 0, "a text with no MemTotal gave a figure")
