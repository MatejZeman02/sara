## The door's `save` holds no frame for two seconds on a large file.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A door `save` was a save at once, `SaExport.save_sad`, and on a large
## file it held one frame of 2.2 s. It is now the background save Ctrl+S
## starts, and the door holds its answer until the file is whole. These save a
## painted document of several layers through a real door over TCP, with the
## save's shares lowered so a small document takes many turns as a large
## file does, and read that frames ran while the answer was held, that the
## answer came only once the file stood complete at its path, and that the
## file opens with every chunk of every layer equal to the document before the
## save.
extends "res://tests/test_framework.gd"

## The save reads its copies back from the main RenderingDevice.
const REQUIRES_GPU := true

const AgentDoor := preload("res://harness/door/sa_agent_door.gd")
const StepTable := preload("res://harness/sa_step_table.gd")
const CaptureRun := preload("res://harness/sa_capture_run.gd")
const Fixtures := preload("res://tests/fixtures.gd")
const MainCanvasScript := preload("res://render/main_canvas.gd")
const DoorRunner := preload("res://tests/fixtures/door_runner.gd")

static var scratch_known: String = SaDataRoot.path("door/door.json")
static var scratch_port_file: String = SaDataRoot.path("door/door.port")
static var scratch_run_folder: String = SaDataRoot.path("door-run")

## Rounds of polling before a case gives up on an answer.
const ROUNDS: int = 2000
const LAYERS := 5

var _host: Node = null
var _main: Node = null
var _door: AgentDoor = null
var _run: CaptureRun = null
var _runner: DoorRunner = null
var _table: StepTable = null
var _front: Fixtures.FrontDocuments = null
var _client: StreamPeerTCP = null
var _folder: String = ""
var _path: String = ""
var _asked: int = 0
var _a_turn := 0
var _usec_a_turn := 0

## What each frame of the runner saw after its part: the frames a save was
## running in, and the first frame the file stood whole at its path.
var _frames := 0
var _frames_saving := 0
var _whole_at := -1


## Parented to an autoload, because the runner calls this from its own `_ready`
## and a parent mid-`_ready` rejects `add_child`.
func before_each() -> void:
    SaSadSave.finish_all()
    _a_turn = SaSadSnapshot.HashShares.a_turn
    _usec_a_turn = SaSadWalk.usec_a_turn
    SaSadSnapshot.HashShares.a_turn = 3
    SaSadWalk.usec_a_turn = 0
    SaCursorPolicy.forget_pointer_device()
    _host = Node.new()
    _host.name = "U643DoorTestHost"
    EventBus.add_child(_host)
    _main = MainCanvasScript.new()
    _host.add_child(_main)
    _main.bind_tools(Fixtures.make_tool_registry())
    _main.notification(Container.NOTIFICATION_SORT_CHILDREN)
    _front = Fixtures.FrontDocuments.over(_main.canvas as SaCanvas)
    _door = AgentDoor.new(scratch_known)
    _run = CaptureRun.new(scratch_run_folder)
    _table = StepTable.new(_run)
    _runner = DoorRunner.new(_door, _table, _run, ROUNDS, scratch_known, Callable(), _after_frame)
    _folder = OS.get_temp_dir().path_join("sara-door-%d" % OS.get_process_id())
    DirAccess.make_dir_recursive_absolute(_folder)
    _path = _folder.path_join("probe.sad")
    _asked = 0
    _frames = 0
    _frames_saving = 0
    _whole_at = -1
    assert_true(_door.open_port(scratch_port_file), "The TCP way in opens")
    _client = _runner.connect_client()


func after_each() -> void:
    SaSadSave.finish_all()
    SaSadSnapshot.HashShares.a_turn = _a_turn
    SaSadWalk.usec_a_turn = _usec_a_turn
    if _client != null:
        _client.disconnect_from_host()
        _client = null
    _door.close()
    _door = null
    _table = null
    _runner = null
    _run = null
    if _front != null:
        _front.put_back()
        _front = null
    if _host != null:
        _host.free()
        _host = null
    _main = null
    SaCursorPolicy.forget_pointer_device()
    for name in DirAccess.get_files_at(_folder):
        DirAccess.remove_absolute(_folder.path_join(name))
    DirAccess.remove_absolute(_folder)


## What stood after each runner frame, whose part turned the save's loop as
## the tree's process frame turns it in the app.
func _after_frame() -> void:
    _frames += 1
    if SaSadFile.saving():
        _frames_saving += 1
    if _whole_at < 0 and FileAccess.file_exists(_path):
        _whole_at = _frames


func _ask(step: Dictionary) -> Dictionary:
    _asked += 1
    var request := step.duplicate()
    request["id"] = _asked
    var answer := _runner.ask(_client, request)
    return answer.get("body", answer) as Dictionary


func _document() -> SaDocument:
    return (_main.canvas as SaCanvas).document


## Layers of chunks in colours on the twelve bit grid, so the save's rounding
## keeps them as they are.
func _paint() -> void:
    var doc := _document()
    for index in LAYERS:
        var layer := SaLayer.new()
        layer.name = "layer %d" % index
        layer.schema = SaFieldSpec.schema_for_space(doc.color_space)
        doc.add_child(layer)
        for x in 3:
            if (x + index) % 2 == 0 or x == 1:
                layer.get_or_create_chunk(Vector2i(x, index % 2)).clear(Color(0.125 * x + 0.25, 0.0625 * index, 0.5, 1.0))
        doc.active_layer = layer
    doc.modified = true
    # Composited now, so the save's request owes the door no drawn frame.
    var easel := doc.get_parent() as SaEasel
    easel.request_full_composite()
    easel.process_pending_composite()


## Every chunk of every layer of *doc* as the card holds it, by the layer's
## name, the place and the field.
static func _texels(doc: SaDocument) -> Dictionary[String, PackedByteArray]:
    var found: Dictionary[String, PackedByteArray] = {}
    for child in doc.get_children():
        var layer := child as SaLayer
        if layer == null:
            continue
        for grid_pos: Vector2i in layer.chunks:
            var chunk: SaChunk = layer.chunks[grid_pos]
            for field_id: StringName in chunk.fields if chunk != null else {}:
                var texture: SaTexture = chunk.fields[field_id]
                if texture != null and texture.rid.is_valid():
                    found["%s/%s/%s" % [layer.name, grid_pos, field_id]] = texture.rd.texture_get_data(texture.rid, 0)
    return found


func test_the_door_s_save_runs_over_frames_and_answers_once_the_file_is_whole() -> void:
    _paint()
    var before := _texels(_document())
    assert_true(before.size() >= LAYERS, "The document holds painted chunks to save, %d" % before.size())
    assert_false(FileAccess.file_exists(_path), "No file stands at the path before the save")
    var answer := _ask({"save": _path})
    var answered_at := _frames
    var saved := answer.get("save", {}) as Dictionary
    assert_true(bool(answer.get("ok", false)), "The answer is ok: %s" % str(answer))
    assert_eq(String(saved.get("error", "")), "OK", "The save took: %s" % str(answer))
    assert_false(SaSadFile.saving(), "No save is still running when the answer is read")
    assert_true(_frames_saving > 1, "Frames ran while the save was written, %d of them" % _frames_saving)
    assert_true(_whole_at > 0, "The file stood whole at its path")
    assert_true(_whole_at <= answered_at, "and before the answer came, frame %d against %d" % [_whole_at, answered_at])
    var size := FileAccess.get_file_as_bytes(_path).size()
    assert_eq(int(saved.get("bytes", 0)), size, "The answer names the bytes the file holds")
    assert_false(FileAccess.file_exists(_path + SaSadFile.SAD_TEMP_SUFFIX), "and no side file is left")
    assert_false(_document().modified, "The document is marked saved")
    assert_eq(_document().file_path, _path, "as the file it was written to")
    var easel := SaEasel.create_default((_document()).canvas_size)
    assert_eq(SaExport.load_sad(easel.document, _path), OK, "The file opens")
    var after := _texels(easel.document)
    var differing: Array[String] = []
    for key: String in before:
        if not after.has(key) or after[key] != before[key]:
            differing.append(key)
    for key: String in after:
        if not before.has(key):
            differing.append(key)
    assert_eq(differing, [] as Array[String], "Every chunk of every layer reads as the document held it")
    easel.free()


func test_a_save_that_asks_for_no_frames_is_written_at_once() -> void:
    _paint()
    var answer := _ask({"save": {"path": _path, "over_frames": false}})
    assert_eq(String((answer.get("save", {}) as Dictionary).get("error", "")), "OK", "The save took: %s" % str(answer))
    assert_eq(_frames_saving, 0, "No frame ran while it was written")
    assert_true(FileAccess.file_exists(_path), "and the file is there")
    assert_false(_document().modified, "and the document is marked saved")
