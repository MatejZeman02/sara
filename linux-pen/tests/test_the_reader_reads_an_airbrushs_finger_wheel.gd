## The pen module's reader reads an airbrush's finger wheel.
##
## An airbrush comes into range as `BTN_TOOL_AIRBRUSH` and reports its finger
## wheel as `ABS_WHEEL`, and Godot hears neither. The reader is fed here the
## records an airbrush sends: into range, the wheel at the lowest, the middle
## and the highest of the range its node declares, and out of range. The range
## is the kernel's wacom driver's for an Intuos airbrush, 0 to 1023, and a
## second, centred on nought, shows the reader scales by the range it is built
## with rather than by one it assumes.
extends "res://tests/test_framework.gd"

const PenRecords := preload("res://modules/sara-base-modules/linux-pen/pen_records.gd")
const PenNode := preload("res://modules/sara-base-modules/linux-pen/pen_node.gd")

## The wheel's range on an Intuos airbrush's node.
const INTUOS_WHEEL := Vector2i(0, 1023)

## Where a case writes its files, under the data root the run isolates.
var scratch_dir: String = ""


func before_each() -> void:
    scratch_dir = SaDataRoot.path("test_the_airbrush_wheel")
    DirAccess.make_dir_recursive_absolute(scratch_dir)


func after_each() -> void:
    for file: String in DirAccess.get_files_at(scratch_dir):
        DirAccess.remove_absolute(scratch_dir.path_join(file))
    DirAccess.remove_absolute(scratch_dir)


# --- The reader --------------------------------------------------------------


## The ask: an airbrush into range, and its wheel at its lowest, middle and
## highest values.
func test_an_airbrush_in_range_reads_its_wheel_at_nought_a_half_and_one() -> void:
    var reader := PenRecords.new(INTUOS_WHEEL)
    assert_true(reader.reads_wheel(), "A range with room in it is read")
    reader.feed(_frame([[PenRecords.BTN_TOOL_AIRBRUSH, 1]], [[PenRecords.ABS_WHEEL, 0]]))
    var pen := reader.now()
    assert_not_null(pen, "The airbrush coming into range makes the state known")
    assert_true(pen.in_range, "The airbrush is in range")
    assert_true(pen.airbrush, "The tool in range reads as an airbrush")
    assert_false(pen.rubber, "An airbrush is not the eraser")
    assert_eq(pen.wheel, 0.0, "The wheel at its lowest reads nought")
    reader.feed(_frame([[PenRecords.BTN_TOUCH, 1]], [[PenRecords.ABS_WHEEL, 512]]))
    pen = reader.now()
    assert_true(pen.touching, "The airbrush is touching")
    assert_almost_eq(pen.wheel, 512.0 / 1023.0, 0.0001, "The wheel at its middle reads about a half")
    assert_almost_eq(reader.wheel(), pen.wheel, 0.0, "The per-dab read is the state's wheel")
    reader.feed(_frame([], [[PenRecords.ABS_WHEEL, 1023]]))
    pen = reader.now()
    assert_eq(pen.wheel, 1.0, "The wheel at its highest reads one")
    assert_true(pen.airbrush, "A frame that carries only the wheel keeps the airbrush in range")


## The pen's end is not an airbrush, and the wheel moves with no tool code.
func test_a_pen_in_range_is_not_an_airbrush() -> void:
    var reader := PenRecords.new(INTUOS_WHEEL)
    reader.feed(_frame([[PenRecords.BTN_TOOL_PEN, 1]], []))
    assert_false(reader.now().airbrush, "The pen's end reads as no airbrush")
    reader.feed(_frame([[PenRecords.BTN_TOOL_PEN, 0], [PenRecords.BTN_TOOL_AIRBRUSH, 1]], []))
    assert_true(reader.now().airbrush, "The airbrush in the pen's place reads as one")
    assert_true(reader.now().in_range, "and in range")


## A range centred on nought, as some nodes declare, scales the same way.
func test_the_wheel_is_scaled_by_the_range_the_node_declares() -> void:
    var reader := PenRecords.new(Vector2i(-900, 899))
    reader.feed(_frame([[PenRecords.BTN_TOOL_AIRBRUSH, 1]], [[PenRecords.ABS_WHEEL, -900]]))
    assert_eq(reader.wheel(), 0.0, "The lowest of -900 to 899 reads nought")
    reader.feed(_frame([], [[PenRecords.ABS_WHEEL, 0]]))
    assert_almost_eq(reader.wheel(), 900.0 / 1799.0, 0.0001, "Nought of -900 to 899 reads about a half")
    reader.feed(_frame([], [[PenRecords.ABS_WHEEL, 899]]))
    assert_eq(reader.wheel(), 1.0, "The highest reads one")
    reader.feed(_frame([], [[PenRecords.ABS_WHEEL, 2000]]))
    assert_eq(reader.wheel(), 1.0, "A value past the range is held at one")


## A frame is read when the report closes it, the wheel as well.
func test_the_wheel_waits_for_the_report_that_closes_its_frame() -> void:
    var reader := PenRecords.new(INTUOS_WHEEL)
    reader.feed(_frame([[PenRecords.BTN_TOOL_AIRBRUSH, 1]], [[PenRecords.ABS_WHEEL, 100]]))
    reader.feed(_record(PenRecords.EV_ABS, PenRecords.ABS_WHEEL, 1023))
    assert_almost_eq(reader.wheel(), 100.0 / 1023.0, 0.0001, "An open frame's wheel is not read yet")
    reader.feed(_record(PenRecords.EV_SYN, PenRecords.SYN_REPORT, 0))
    assert_eq(reader.wheel(), 1.0, "The report closes it")


## Out of range the airbrush is gone and the wheel stays where it was left.
func test_out_of_range_the_wheel_is_kept_and_the_airbrush_is_gone() -> void:
    var reader := PenRecords.new(INTUOS_WHEEL)
    reader.feed(_frame([[PenRecords.BTN_TOOL_AIRBRUSH, 1], [PenRecords.BTN_TOUCH, 1]], [[PenRecords.ABS_WHEEL, 1023]]))
    reader.feed(_frame([[PenRecords.BTN_TOUCH, 0]], []))
    reader.feed(_frame([[PenRecords.BTN_TOOL_AIRBRUSH, 0]], []))
    var pen := reader.now()
    assert_false(pen.in_range, "Out of range")
    assert_false(pen.airbrush, "No airbrush is in range")
    assert_false(pen.touching, "Nothing touches")
    assert_eq(pen.wheel, 1.0, "The wheel is where the airbrush left it")


## Built with no range, as for a node that declares no wheel, the wheel is
## never read.
func test_with_no_range_the_wheel_is_never_read() -> void:
    for wheel_range: Vector2i in [Vector2i.ZERO, Vector2i(5, 5), Vector2i(10, 0)]:
        var reader := PenRecords.new(wheel_range)
        assert_false(reader.reads_wheel(), "%s has no room and is not read" % wheel_range)
        reader.feed(_frame([[PenRecords.BTN_TOOL_AIRBRUSH, 1]], [[PenRecords.ABS_WHEEL, 7]]))
        assert_true(reader.now().airbrush, "The airbrush is still heard")
        assert_eq(reader.wheel(), 0.0, "The wheel stays at nought")


## Before the state is known the wheel reads nought, and a drop forgets it.
func test_the_wheel_reads_nought_while_the_state_is_not_known() -> void:
    var reader := PenRecords.new(INTUOS_WHEEL)
    reader.feed(_record(PenRecords.EV_ABS, PenRecords.ABS_WHEEL, 600) + _record(PenRecords.EV_SYN, PenRecords.SYN_REPORT, 0))
    assert_null(reader.now(), "A frame that moves nothing in or out of range leaves the state unknown")
    assert_eq(reader.wheel(), 0.0, "and the wheel at nought")
    reader.feed(_frame([[PenRecords.BTN_TOOL_AIRBRUSH, 1]], [[PenRecords.ABS_WHEEL, 1023]]))
    assert_eq(reader.wheel(), 1.0, "Known once the airbrush comes into range")
    reader.feed(_record(PenRecords.EV_SYN, PenRecords.SYN_DROPPED, 0))
    reader.feed(_frame([], [[PenRecords.ABS_WHEEL, 0]]))
    assert_eq(reader.wheel(), 0.0, "A drop forgets the state, and the wheel reads nought")


# --- The node's range ---------------------------------------------------------


## The answer a range with no room in it makes is no wheel.
func test_an_asked_range_with_no_room_is_no_wheel() -> void:
    var asked := PenNode.Asked.new(PenNode.Wheel.READ, INTUOS_WHEEL)
    assert_eq(asked.wheel, PenNode.Wheel.READ, "0 to 1023 is a wheel read")
    assert_eq(asked.declared, INTUOS_WHEEL, "and its range is kept")
    var flat := PenNode.Asked.new(PenNode.Wheel.READ, Vector2i(3, 3))
    assert_eq(flat.wheel, PenNode.Wheel.NONE, "3 to 3 is none")
    assert_eq(flat.declared, Vector2i.ZERO, "and keeps no range")
    var unasked := PenNode.Asked.new(PenNode.Wheel.UNASKED, INTUOS_WHEEL)
    assert_eq(unasked.declared, Vector2i.ZERO, "A wheel not asked keeps no range")


## What is not a device is never asked, and a device with no axes has no wheel.
func test_a_node_that_declares_no_wheel_is_asked_and_reads_none() -> void:
    var file := scratch_dir.path_join("not-a-device")
    FileAccess.open(file, FileAccess.WRITE).store_string("")
    assert_eq(PenNode.Reader.ask_wheel(file).wheel, PenNode.Wheel.NONE, "A file is no device and is not asked")
    if OS.execute("python3", ["-c", "pass"]) != 0:
        skip("python3 does not run here, so a device's range cannot be asked")
        return
    assert_eq(PenNode.Reader.ask_wheel("/dev/null").wheel, PenNode.Wheel.NONE, "/dev/null answers no axes and has no wheel")


# --- The source's contract ---------------------------------------------------


func test_a_source_that_reads_nothing_reads_no_wheel() -> void:
    var source := SaPenSource.new()
    assert_eq(source.wheel(), 0.0, "The base source's wheel is nought")
    assert_false(source.reads_wheel(), "and it reads none")
    var pen := SaPenSource.State.new()
    assert_false(pen.airbrush, "A new state is no airbrush")
    assert_eq(pen.wheel, 0.0, "with the wheel at nought")
    pen.airbrush = true
    pen.wheel = 0.25
    var copied := pen.copy()
    assert_true(copied.airbrush, "A copy keeps the airbrush")
    assert_eq(copied.wheel, 0.25, "and the wheel")
    var described := pen.described()
    assert_eq(
        described.keys(), ["in_range", "rubber", "airbrush", "wheel", "touching", "barrels", "last_pressed"], "The dump's keys"
    )
    assert_eq(described["wheel"], 0.25, "The dump writes the wheel")


func test_the_dump_says_when_no_source_is_registered() -> void:
    var captured := SaPenSource.capture_state()
    assert_true(captured.has("registered"), "The dump always says whether a source is registered")
    if not captured["registered"]:
        assert_eq(captured.size(), 1, "and nothing more when none is")
    else:
        assert_true(captured.has("wheel") and captured.has("reads_wheel"), "A registered source's wheel is in the dump")


# --- Records ---------------------------------------------------------------


func _record(type: int, code: int, value: int) -> PackedByteArray:
    var out := PackedByteArray()
    out.resize(PenRecords.RECORD_BYTES)
    out.encode_s64(0, 1759600000)
    out.encode_s64(8, 0)
    out.encode_u16(16, type)
    out.encode_u16(18, code)
    out.encode_s32(20, value)
    return out


## The keys *keys* and the axes *axes*, `[code, value]` each, and the report
## that closes them.
func _frame(keys: Array, axes: Array) -> PackedByteArray:
    var out := PackedByteArray()
    for change: Array in keys:
        out += _record(PenRecords.EV_KEY, change[0], change[1])
    for change: Array in axes:
        out += _record(PenRecords.EV_ABS, change[0], change[1])
    return out + _record(PenRecords.EV_SYN, PenRecords.SYN_REPORT, 0)
