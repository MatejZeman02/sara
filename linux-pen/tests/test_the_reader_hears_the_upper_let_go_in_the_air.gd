## The pen module's reader hears the upper barrel button let go in the air.
##
## Under Wayland Godot reports the upper as the tip's left press, so the upper
## let go with the tip up is no event Sara hears. The kernel's node reports it,
## and the reader is fed here the records a pen sends there, in the order the
## painter's hand would: the pen into range, the upper pressed, a touch, a
## lift, a second touch, the upper let go in the air, a third touch, and out of
## range. The upper is the Intuos Pro's, `BTN_STYLUS2`. The second half runs the
## source the module registers, reading a pipe through `cat` on its own thread,
## and stops it the way Sara's exit does.
extends "res://tests/test_framework.gd"

const PenRecords := preload("res://modules/sara-base-modules/linux-pen/pen_records.gd")
const PenNode := preload("res://modules/sara-base-modules/linux-pen/pen_node.gd")
const Module := preload("res://modules/sara-base-modules/linux-pen/module.gd")

## The upper as the kernel numbers it on an Intuos Pro pen.
const UPPER := PenRecords.BTN_STYLUS2

## A Wacom pen's key bits as sysfs writes them: the pen and the rubber, the
## touch and the three barrels, and nothing below them.
const PEN_KEYS := "1e03 0 0 0 0 0"
## A keyboard's, which carry no pen.
const KEYBOARD_KEYS := "1000000000007 ff800000000007ff febeffdff3cfffff fffffffffffffffe"

## Where a case writes its files, under the data root the run isolates. Set
## in [method before_each] rather than as a static, which left every script
## in use at exit when this suite ran after the pen registry's.
var scratch_dir: String = ""

## The upper in the door's numbering. Not a constant, because a constant naming
## a global class breaks the class cache.
var _upper_barrel := SaPenSource.Barrel.SECOND

## The writers a case started, killed by their ids when it ends.
var _started: Array[int] = []


func before_each() -> void:
    scratch_dir = SaDataRoot.path("test_the_pen_reader")
    DirAccess.make_dir_recursive_absolute(scratch_dir)


func after_each() -> void:
    for pid: int in _started:
        OS.kill(pid)
    _started.clear()
    _remove_tree(scratch_dir)


# --- The reader --------------------------------------------------------------


## The ask's sequence, read after each frame.
func test_the_upper_is_held_through_two_touches_and_the_third_is_the_tips() -> void:
    var reader := PenRecords.new()
    reader.feed(_frame([[PenRecords.BTN_TOOL_PEN, 1]]))
    var pen := reader.now()
    assert_not_null(pen, "The pen coming into range makes the state known")
    assert_true(pen.in_range, "and in range")
    assert_false(pen.rubber, "by its tip's end")
    assert_eq(pen.barrels, 0, "with no barrel held")

    reader.feed(_frame([[UPPER, 1]]))
    assert_true(reader.now().held(_upper_barrel), "The upper pressed in the air is held")
    assert_eq(reader.now().last_pressed, _upper_barrel, "and the barrel pressed last")

    reader.feed(_frame([[PenRecords.BTN_TOUCH, 1]]))
    assert_true(reader.now().touching, "The first touch is on the surface")
    assert_true(reader.now().held(_upper_barrel), "with the upper held")
    reader.feed(_frame([[PenRecords.BTN_TOUCH, 0]]))
    assert_false(reader.now().touching, "The lift leaves the surface")
    assert_true(reader.now().held(_upper_barrel), "and the upper still held, which Godot loses at the lift")

    reader.feed(_frame([[PenRecords.BTN_TOUCH, 1]]))
    assert_true(reader.now().held(_upper_barrel), "The second touch is under the held upper as well")
    reader.feed(_frame([[PenRecords.BTN_TOUCH, 0]]))

    reader.feed(_frame([[UPPER, 0]]))
    pen = reader.now()
    assert_false(pen.held(_upper_barrel), "The upper let go in the air is heard")
    assert_true(pen.in_range, "with the pen still in range")

    reader.feed(_frame([[PenRecords.BTN_TOUCH, 1]]))
    pen = reader.now()
    assert_true(pen.touching, "The third touch is on the surface")
    assert_eq(pen.barrels, 0, "with no barrel held, so it is the tip's")
    reader.feed(_frame([[PenRecords.BTN_TOUCH, 0]]))

    reader.feed(_frame([[PenRecords.BTN_TOOL_PEN, 0]]))
    pen = reader.now()
    assert_not_null(pen, "Out of range the state is still known")
    assert_false(pen.in_range, "and out of range")
    assert_false(pen.touching, "nothing touches")
    assert_eq(pen.barrels, 0, "and every button is let go")


## The pen leaving the range with the upper and the tip held, and the frame
## saying nothing of them: out of range every button is let go all the same.
func test_out_of_range_every_button_is_let_go_whatever_the_frame_says() -> void:
    var reader := PenRecords.new()
    reader.feed(_frame([[PenRecords.BTN_TOOL_PEN, 1], [UPPER, 1], [PenRecords.BTN_STYLUS, 1]]))
    reader.feed(_frame([[PenRecords.BTN_STYLUS3, 1], [PenRecords.BTN_TOUCH, 1]]))
    assert_eq(_held_count(reader.now()), 3, "Three barrels are held")
    reader.feed(_frame([[PenRecords.BTN_TOOL_PEN, 0]]))
    var pen := reader.now()
    assert_eq(pen.barrels, 0, "and none out of range")
    assert_false(pen.touching, "nor the tip")


## The records come off a pipe in pieces of any length. Fed a byte at a time
## the reader ends where it ends fed whole.
func test_records_cut_anywhere_read_the_same() -> void:
    var bytes := _frame([[PenRecords.BTN_TOOL_PEN, 1]]) + _frame([[UPPER, 1]]) + _frame([[PenRecords.BTN_TOUCH, 1]])
    var whole := PenRecords.new()
    whole.feed(bytes)
    var cut := PenRecords.new()
    for at: int in bytes.size():
        cut.feed(bytes.slice(at, at + 1))
    assert_eq(_words(cut.now()), _words(whole.now()), "A byte at a time reads as the whole")
    assert_true(cut.now().held(_upper_barrel), "the upper held")
    assert_true(cut.now().touching, "and the tip down")


## A frame is the state of one moment, so the tools never read half of one.
func test_a_frame_counts_only_once_it_is_closed() -> void:
    var reader := PenRecords.new()
    reader.feed(_frame([[PenRecords.BTN_TOOL_PEN, 1]]))
    reader.feed(_record(PenRecords.EV_KEY, UPPER, 1))
    assert_false(reader.now().held(_upper_barrel), "A press with its frame still open is not read")
    reader.feed(_record(PenRecords.EV_SYN, PenRecords.SYN_REPORT, 0))
    assert_true(reader.now().held(_upper_barrel), "and is once the report closes it")


## A reader opened with the pen already over the tablet hears changes and not
## the state they changed from, so it knows nothing until the pen moves in or
## out of range.
func test_a_reader_opened_with_the_pen_in_range_knows_nothing_until_it_leaves() -> void:
    var reader := PenRecords.new()
    reader.feed(_frame([[UPPER, 1]]))
    reader.feed(_frame([[PenRecords.BTN_TOUCH, 1]]))
    assert_null(reader.now(), "Changes alone say nothing of the state")
    reader.feed(_frame([[PenRecords.BTN_TOUCH, 0]]))
    reader.feed(_frame([[PenRecords.BTN_TOOL_PEN, 0]]))
    assert_not_null(reader.now(), "The pen leaving the range does")
    assert_eq(reader.now().barrels, 0, "with every button let go")


## The kernel's buffer overran and changes were lost, which a pipe cannot ask
## again, so nothing is known until the pen comes into range again.
func test_a_dropped_frame_forgets_the_state_until_the_pen_comes_back() -> void:
    var reader := PenRecords.new()
    reader.feed(_frame([[PenRecords.BTN_TOOL_PEN, 1], [UPPER, 1]]))
    reader.feed(_record(PenRecords.EV_SYN, PenRecords.SYN_DROPPED, 0))
    reader.feed(_frame([[UPPER, 0]]))
    assert_null(reader.now(), "After a drop the state is not known")
    reader.feed(_frame([[PenRecords.BTN_TOOL_PEN, 0]]))
    reader.feed(_frame([[PenRecords.BTN_TOOL_PEN, 1]]))
    assert_not_null(reader.now(), "and is once the pen comes into range again")
    assert_eq(reader.now().barrels, 0, "with nothing held")


## The eraser's end in range is in range, and says it is the eraser's.
func test_the_eraser_end_is_in_range_as_the_rubber() -> void:
    var reader := PenRecords.new()
    reader.feed(_frame([[PenRecords.BTN_TOOL_RUBBER, 1]]))
    assert_true(reader.now().in_range, "The eraser end is in range")
    assert_true(reader.now().rubber, "and the rubber")


# --- Finding the node --------------------------------------------------------


## The pen's node is the one whose key bits carry `BTN_TOOL_PEN`, and not a
## keyboard's before it.
func test_the_pens_node_is_found_by_its_key_bits() -> void:
    var root := scratch_dir.path_join("sys")
    _device(root, "event2", KEYBOARD_KEYS)
    _device(root, "event11", PEN_KEYS)
    _device(root, "event12", "0")
    assert_eq(PenNode.Reader.find(root), "/dev/input/event11", "The pen's node is the one with the pen's key")
    assert_eq(PenNode.Reader.find(scratch_dir.path_join("nothing")), "", "and none is found under a root with no devices")
    assert_true(PenNode.Reader.carries(PEN_KEYS, PenRecords.BTN_STYLUS2), "A pen's bits carry the upper")
    assert_true(PenNode.Reader.carries(PEN_KEYS, PenRecords.BTN_TOUCH), "and the touch")
    assert_false(PenNode.Reader.carries(KEYBOARD_KEYS, PenRecords.BTN_TOOL_PEN), "A keyboard's carry no pen")
    assert_false(PenNode.Reader.carries("", PenRecords.BTN_TOOL_PEN), "and empty bits carry nothing")


# --- The source on its thread ------------------------------------------------


## The source reads its node through `cat` on a thread, so the records a pen
## sends reach [method now] without the main thread reading anything, and
## stopping it lets go of a read that is blocked on the pen at once.
func test_the_source_reads_its_node_on_a_thread_and_stops_without_waiting_on_the_pen() -> void:
    var fifo := ProjectSettings.globalize_path(scratch_dir.path_join("event-fifo"))
    var records := ProjectSettings.globalize_path(scratch_dir.path_join("records"))
    var file := FileAccess.open(records, FileAccess.WRITE)
    file.store_buffer(_frame([[PenRecords.BTN_TOOL_PEN, 1]]) + _frame([[UPPER, 1]]) + _frame([[PenRecords.BTN_TOUCH, 1]]))
    file.close()
    if OS.execute("mkfifo", [fifo]) != 0:
        skip("no mkfifo here")
        return
    # The writer keeps the pipe open after the records, as a pen held still does.
    var writer := OS.execute_with_pipe("sh", ["-c", 'exec 3>"$0"; cat "$1" >&3; exec sleep 30', fifo, records], false)
    _started.append(int(writer["pid"]))
    var source := PenNode.new(fifo)
    source.start()
    var pen: SaPenSource.State = null
    var waited := 0
    while pen == null and waited < 3000:
        OS.delay_msec(10)
        waited += 10
        pen = source.now()
    assert_not_null(pen, "The source read the records off its node")
    if pen != null:
        assert_true(pen.held(_upper_barrel), "the upper held")
        assert_true(pen.touching, "and the tip down")
    assert_true(source.reads(), "It says it reads")
    assert_eq(source.said(), "The pen module reads %s." % fifo, "and names the node")
    var began := Time.get_ticks_msec()
    source.stop()
    var took := Time.get_ticks_msec() - began
    assert_true(took < 500, "Stopping with a read blocked on the pen took %d ms" % took)
    assert_false(source.reads(), "and it reads no more")


## A node the user may not read is refused, and the page's sentence names it
## and says how to turn the module on.
func test_a_node_the_user_may_not_read_is_refused_and_said() -> void:
    # Git for Windows has a chmod, and its mode 000 is the read-only flag, which
    # stops no read but stops the next run's write and every delete.
    if OS.get_name() == "Windows":
        skip("a Windows file has no mode that stops its owner reading it")
        return
    var node := ProjectSettings.globalize_path(scratch_dir.path_join("event-locked"))
    FileAccess.open(node, FileAccess.WRITE).close()
    OS.execute("chmod", ["000", node])
    if OS.execute("test", ["-r", node]) == 0:
        skip("this user reads a file of mode 000, as root does")
        return
    var source := PenNode.new(node)
    source.start()
    var waited := 0
    while source.said().is_empty() and waited < 3000:
        OS.delay_msec(10)
        waited += 10
    var said := source.said()
    source.stop()
    assert_true(said.contains("may not read %s" % node), "The sentence names the node: %s" % said)
    assert_true(said.contains("packaging/install.sh"), "and says what turns the module on")
    assert_false(source.reads(), "and nothing is read")
    assert_null(source.now(), "or known")
    var line := PenNode.REFUSED_LINE % node
    assert_true(line.contains(node) and line.contains("no read permission"), "The log line names the node and the permission")


## With no pen found, stopping waits no longer than a slice of the wait.
func test_with_no_pen_found_the_source_stops_within_a_slice() -> void:
    var source := PenNode.new("", scratch_dir.path_join("nothing"))
    source.start()
    OS.delay_msec(100)
    var began := Time.get_ticks_msec()
    source.stop()
    var took := Time.get_ticks_msec() - began
    assert_true(took < 4 * PenNode.STOP_HEARD_MSEC, "Stopping took %d ms" % took)
    assert_true(source.said().contains("no tablet's pen was found"), "The sentence says no pen was found")


## A source let go of without [method PenNode.stop], as a suite dropping a
## booted module set does, stops its reader and joins the thread as it goes,
## rather than leaving a thread calling into a freed object. The first area
## gate found six of those at exit.
func test_a_source_let_go_of_without_stop_joins_its_thread() -> void:
    var source := PenNode.new("", scratch_dir.path_join("nothing"))
    source.start()
    var reader: PenNode.Reader = source._reader
    OS.delay_msec(100)
    var began := Time.get_ticks_msec()
    source = null
    var took := Time.get_ticks_msec() - began
    assert_true(reader._stopping, "The source's teardown stopped its reader")
    assert_true(took < 4 * PenNode.STOP_HEARD_MSEC, "and joined the thread, which took %d ms" % took)


# --- Where the module runs ---------------------------------------------------


## Linux under Wayland and nowhere else, since everywhere else the upper
## already arrives as the middle button or the platform has no such node.
func test_the_module_runs_on_linux_under_wayland_alone() -> void:
    assert_true(Module.wanted("Linux", "Wayland"), "Linux under Wayland")
    assert_false(Module.wanted("Linux", "X11"), "not under X11 or XWayland")
    assert_false(Module.wanted("Linux", "headless"), "not headless")
    assert_false(Module.wanted("Windows", "Windows"), "not on Windows")
    assert_eq(Module.named_node(PackedStringArray(["--capture", "--pen-node=/tmp/x"])), "/tmp/x", "The flag names a node")
    assert_eq(Module.named_node(PackedStringArray(["--capture"])), "", "and none without it")


# --- Helpers -----------------------------------------------------------------


## One `input_event` record, as a 64-bit kernel writes it.
func _record(type: int, code: int, value: int) -> PackedByteArray:
    var out := PackedByteArray()
    out.resize(PenRecords.RECORD_BYTES)
    out.encode_s64(0, 1759600000)
    out.encode_s64(8, 0)
    out.encode_u16(16, type)
    out.encode_u16(18, code)
    out.encode_s32(20, value)
    return out


## The keys *changes*, `[code, value]` each, and the report that closes them.
func _frame(changes: Array) -> PackedByteArray:
    var out := PackedByteArray()
    for change: Array in changes:
        out += _record(PenRecords.EV_KEY, change[0], change[1])
    return out + _record(PenRecords.EV_SYN, PenRecords.SYN_REPORT, 0)


func _held_count(pen: SaPenSource.State) -> int:
    var count := 0
    for barrel: SaPenSource.Barrel in [SaPenSource.Barrel.FIRST, SaPenSource.Barrel.SECOND, SaPenSource.Barrel.THIRD]:
        if pen.held(barrel):
            count += 1
    return count


## A state as words a case can compare.
func _words(pen: SaPenSource.State) -> String:
    if pen == null:
        return "unknown"
    return (
        "range=%s rubber=%s touching=%s barrels=%d last=%d"
        % [pen.in_range, pen.rubber, pen.touching, pen.barrels, pen.last_pressed]
    )


func _remove_tree(folder: String) -> void:
    if not DirAccess.dir_exists_absolute(folder):
        return
    for inner: String in DirAccess.get_directories_at(folder):
        _remove_tree(folder.path_join(inner))
    for file: String in DirAccess.get_files_at(folder):
        DirAccess.remove_absolute(folder.path_join(file))
    DirAccess.remove_absolute(folder)


## A device under *root* named *event* whose key bits are *keys*.
func _device(root: String, event: String, keys: String) -> void:
    var folder := root.path_join(event).path_join("device/capabilities")
    DirAccess.make_dir_recursive_absolute(folder)
    var file := FileAccess.open(folder.path_join("key"), FileAccess.WRITE)
    file.store_line(keys)
    file.close()
