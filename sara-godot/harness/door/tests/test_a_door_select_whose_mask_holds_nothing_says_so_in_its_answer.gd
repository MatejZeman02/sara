## A door select whose mask holds nothing says so in its
## answer, so the next fill does not cover the whole layer unawares.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A `select` with a mask of
## zeros in replace mode, the document was left with no selection, and the
## fill after it covered the whole layer with nothing in the answer to say so.
## These send three masks through the real door and read the
## answer's warnings: zeros in replace mode warn, one lit pixel does not, and
## zeros added to a rectangle that stands do not, since the selection is not
## empty.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const AgentDoor := preload("res://harness/door/sa_agent_door.gd")
const StepTable := preload("res://harness/sa_step_table.gd")
const CaptureRun := preload("res://harness/sa_capture_run.gd")
const Fixtures := preload("res://tests/fixtures.gd")
const MainCanvasScript := preload("res://render/main_canvas.gd")
const DoorRunner := preload("res://tests/fixtures/door_runner.gd")
const Npy := preload("res://harness/sa_npy.gd")

static var scratch_known: String = SaDataRoot.path("door/door.json")
static var scratch_port_file: String = SaDataRoot.path("door/door.port")
static var scratch_run_folder: String = SaDataRoot.path("door-run")

## Rounds of polling before a request gives up on an answer.
const ROUNDS: int = 4000

## The words of the warning an empty mask raises.
const SAYS := "selects nothing"

var _host: Node = null
var _door: AgentDoor = null
var _run: CaptureRun = null
var _runner: DoorRunner = null
var _table: StepTable = null
var _front: Fixtures.FrontDocuments = null
var _document: SaDocument = null


## Parented to an autoload, because the runner calls this from its own `_ready`
## and a parent mid-`_ready` rejects `add_child`.
func before_each() -> void:
    _host = Node.new()
    _host.name = "U893DoorHost"
    EventBus.add_child(_host)
    var main: Node = MainCanvasScript.new()
    _host.add_child(main)
    main.bind_tools(Fixtures.make_tool_registry())
    main.notification(Container.NOTIFICATION_SORT_CHILDREN)
    _front = Fixtures.FrontDocuments.over(main.canvas as SaCanvas)
    _document = (main.canvas as SaCanvas).document
    DirAccess.make_dir_recursive_absolute(scratch_run_folder)
    _door = AgentDoor.new(scratch_known)
    _run = CaptureRun.new(scratch_run_folder)
    _table = StepTable.new(_run)
    _runner = DoorRunner.new(_door, _table, _run, ROUNDS, scratch_known, Callable(), Input.flush_buffered_events)


func after_each() -> void:
    if _front != null:
        _front.put_back()
        _front = null
    _door.close()
    _door = null
    _table = null
    _runner = null
    _run = null
    _document = null
    if _host != null:
        _host.free()
        _host = null


## Writes a float32 mask of shape `(h, w)` the size of the canvas into the
## run's folder, 1 at each of *lit* and 0 elsewhere, and returns its name.
func _mask(file: String, lit: Array[Vector2i]) -> String:
    var size := _document.canvas_size
    var text := "{'descr': '<f4', 'fortran_order': False, 'shape': (%d, %d), }" % [size.y, size.x]
    var padded := text + " ".repeat(63 - (10 + text.length()) % 64) + "\n"
    var bytes := PackedByteArray(Npy.MAGIC)
    bytes.append_array(PackedByteArray([1, 0, padded.length() & 0xFF, padded.length() >> 8]))
    bytes.append_array(padded.to_ascii_buffer())
    var body := PackedFloat32Array()
    body.resize(size.x * size.y)
    for at in lit:
        body[at.y * size.x + at.x] = 1.0
    bytes.append_array(body.to_byte_array())
    var out := FileAccess.open(scratch_run_folder.path_join(file), FileAccess.WRITE)
    out.store_buffer(bytes)
    out.close()
    return file


## The warnings of *answer* that say a mask selected nothing.
static func _empty_warnings(answer: Dictionary) -> Array:
    var found: Array = []
    for line: Variant in answer.get("warnings", []):
        if str(line).contains(SAYS):
            found.append(line)
    return found


func test_a_mask_of_zeros_in_replace_mode_warns_and_names_the_file() -> void:
    assert_true(_door.open_port(scratch_port_file), "The TCP way in opens")
    var client := _runner.connect_client()
    _runner.ask(client, {"id": 1, "select": [10, 10, 40, 40]})
    assert_true(_document.selection.active, "A rectangle stands before the mask")
    var name := _mask("zeros.npy", [])
    var answer := _runner.ask(client, {"id": 2, "select": {"mask": name}})
    var said := _empty_warnings(answer)
    assert_eq(said.size(), 1, "The answer warns that the mask selects nothing: %s" % str(answer))
    assert_true(said.size() == 1 and str(said[0]).contains(name), "and names the mask: %s" % str(said))
    assert_true(said.size() == 1 and str(said[0]).contains("whole layer"), "and says a fill covers the whole layer")
    assert_eq(answer.get("errors"), [], "It is a warning and not an error: %s" % str(answer.get("errors")))
    assert_false(_document.selection.active, "and the selection is none, as the Select menu leaves it")


func test_a_mask_of_one_lit_pixel_warns_of_nothing() -> void:
    assert_true(_door.open_port(scratch_port_file), "The TCP way in opens")
    var client := _runner.connect_client()
    var lit: Array[Vector2i] = [Vector2i(300, 200)]
    var answer := _runner.ask(client, {"id": 1, "select": {"mask": _mask("one.npy", lit)}})
    assert_eq(_empty_warnings(answer), [], "One lit pixel raises no warning: %s" % str(answer))
    assert_true(_document.selection.active, "and selects that pixel")


func test_a_mask_of_zeros_added_to_a_selection_warns_of_nothing() -> void:
    assert_true(_door.open_port(scratch_port_file), "The TCP way in opens")
    var client := _runner.connect_client()
    _runner.ask(client, {"id": 1, "select": [10, 10, 40, 40]})
    var answer := _runner.ask(client, {"id": 2, "select": {"mask": _mask("zeros.npy", []), "mode": "add"}})
    assert_eq(_empty_warnings(answer), [], "Zeros added to a rectangle raise no warning: %s" % str(answer))
    assert_true(_document.selection.active, "and the rectangle stands")
