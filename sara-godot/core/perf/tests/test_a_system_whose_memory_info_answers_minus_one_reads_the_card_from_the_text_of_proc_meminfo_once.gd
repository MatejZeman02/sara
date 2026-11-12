## On a system whose memory info answers -1, as Android's does, an integrated
## card's memory is the share of `MemTotal` read from the text of
## `/proc/meminfo`, and with no such text it is 0, read once a run.
##
## The tablet's log said the card's memory came "from half the system's
## memory" and answered nothing. The share and the parse were right when the
## text was handed to them. What failed was the read of the file, which
## `FileAccess.get_file_as_string` answers empty for any file under `/proc`,
## since the kernel gives such a file a length of 0. The last test reads this
## machine's own file, so the gate fails again if that read goes back.
extends "res://tests/test_framework.gd"

const GIB := 1 << 30
## An Android tablet of 6 GiB as its kernel writes `/proc/meminfo`, in kB.
const MEMINFO := "MemTotal:        6291456 kB\nMemFree:          812345 kB\nMemAvailable:    2345678 kB\n"


func after_each() -> void:
    SaCardMemory.stand_in_machine(null, null)


func _android(meminfo: String, type: int = RenderingDevice.DEVICE_TYPE_INTEGRATED_GPU, name: String = "Adreno (TM) 740") -> void:
    SaCardMemory.stand_in_machine(
        SaCardMemory.Adapter.new(type, name),
        SaCardMemory.System.new({"physical": -1, "free": -1, "available": -1, "stack": -1}, meminfo, "Android")
    )


func _said(lines: PackedStringArray) -> int:
    var count := 0
    for line in lines:
        if line.begins_with("SaCardMemory:"):
            count += 1
    return count


## Memory info of -1 and a `MemTotal` line: the share of that total, said once
## with `/proc/meminfo` named as its source, and kept for the next ask.
func test_the_share_of_memtotal_is_taken_and_kept() -> void:
    _android(MEMINFO)
    var catcher := SaErrorCatcher.listening()
    var answers: Array[int] = [SaCardMemory.total(), SaCardMemory.total()]
    catcher.stop()
    var expected := ((6 * GIB) >> 2) * 3
    assert_eq(answers, [expected, expected] as Array[int], "the share of MemTotal was not taken and kept")
    assert_eq(_said(catcher.printed()), 1, "the reading was said more than once")
    var source := SaCardMemory.source()
    assert_true(source.contains("/proc/meminfo"), "the source does not name /proc/meminfo: %s" % source)


## Memory info of -1 and no `meminfo` text: 0, and a second ask reads nothing
## again, so one line is said and the source says nothing gave a figure.
func test_no_text_is_zero_and_a_second_ask_does_not_read_again() -> void:
    _android("")
    var catcher := SaErrorCatcher.listening()
    var first := SaCardMemory.total()
    var second := SaCardMemory.total()
    catcher.stop()
    assert_eq(first, 0, "a system with no figure did not answer 0")
    assert_eq(second, 0, "the second ask did not keep the 0")
    assert_eq(_said(catcher.printed()), 1, "the second ask read the system again")
    assert_true(SaCardMemory.source().begins_with("nothing"), "the source reads: %s" % SaCardMemory.source())


## The emulator passes the host's card through and reports it as discrete,
## and no reading of a card's own memory answers on Android, so the share of
## `MemTotal` is taken all the same, and the source names the card.
func test_a_discrete_card_on_android_takes_the_share_too() -> void:
    _android(MEMINFO, RenderingDevice.DEVICE_TYPE_DISCRETE_GPU, "NVIDIA GeForce RTX 3090")
    assert_eq(SaCardMemory.total(), ((6 * GIB) >> 2) * 3, "a discrete card on Android read no share")
    var source := SaCardMemory.source()
    assert_true(source.contains("NVIDIA GeForce RTX 3090 on Android"), "the source reads: %s" % source)


## A `/proc` file read whole gives every line the kernel writes, where
## `FileAccess.get_file_as_string` gives none.
func test_this_machine_s_proc_meminfo_reads_whole() -> void:
    if not OS.get_name() in ["Linux", "Android"] or not FileAccess.file_exists("/proc/meminfo"):
        skip("no /proc/meminfo on this system")
        return
    var text := SaCardMemory.System.proc_text("/proc/meminfo")
    assert_true(SaCardMemory.meminfo_bytes(text) > 0, "this machine's /proc/meminfo gave no MemTotal")
    assert_true(text.split("\n").size() > 3, "only part of /proc/meminfo was read")
    assert_true(SaCardMemory.meminfo_bytes(SaCardMemory.System.this_machine().meminfo) > 0, "the system read no MemTotal")


## A path that does not open gives an empty text, not an error.
func test_a_missing_file_gives_no_text() -> void:
    assert_eq(SaCardMemory.System.proc_text("/proc/no-such-file-sara-reads"), "", "a missing file gave text")
