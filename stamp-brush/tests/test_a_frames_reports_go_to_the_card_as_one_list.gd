## A frame's reports go to the card as one list and commit once, and paint what
## a list a report painted, to the bit.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A pen or a mouse reports several times a frame, and each report's walk sent
## a compute list of its own, committed its dirty rectangles and sent a smudge
## stroke's queue, which grew the stroke's snapshot every time. `SaWalkBatch`
## now holds what a frame's walks laid until `process_frame`, and the lift and
## a reset send it at once. What this holds is the count, the one ask a frame,
## the texels, and the lift and the reset. The timing is the scenario's,
## `scenarios/a-small-brush-keeps-up-with-the-pen-measured.json`.
##
## A test cannot await a frame, so [method _frame] runs what the batch asked of
## `process_frame` the way the tree would.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const ShippedPresetsScript = preload("res://modules/sara-base-modules/stamp-brush/presets/sa_shipped_presets.gd")

## Never the real `user://brush_presets`, which is the painter's own folder.
static var scratch_dir: String = SaDataRoot.path("test_d15_presets")
## The canvas's short side, which a radius is a fraction of.
const SIDE: float = 256.0
## The press, inside the first chunk as every report below is.
const FROM := Vector2(20, 40)
## Reports a frame, the four the scenario's middle rate sends.
const A_FRAME: int = 4
## How far apart two reports land.
const STEP := Vector2(12, 3)

var _surface: SaSurface = null
var _machine: ToolMachine = null


func before_each() -> void:
    SaPenClock.pin_to_frames()
    _fresh()


func after_each() -> void:
    SaPenClock.unpin()
    Fixtures.teardown(_surface, _machine)
    _surface = null
    _machine = null
    if DirAccess.dir_exists_absolute(scratch_dir):
        for file_name: String in DirAccess.get_files_at(scratch_dir):
            DirAccess.remove_absolute(scratch_dir.path_join(file_name))
        DirAccess.remove_absolute(scratch_dir)


## A canvas and a brush of their own, after any the test painted before.
func _fresh() -> void:
    if _surface != null:
        Fixtures.teardown(_surface, _machine)
    _surface = Fixtures.make_surface(Vector2i(int(SIDE), int(SIDE)))
    _machine = Fixtures.make_bound_machine(_surface)
    _machine.set_active_tool(&"brush")


func _brush() -> Object:
    return _machine.active_tool


func _button(pressed: bool) -> void:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = pressed
    _brush().handle_input(event)


func _motion(at: Vector2) -> void:
    var motion := InputEventMouseMotion.new()
    motion.pressure = 0.8
    _surface.view.mouse_position = at
    _brush().handle_input(motion)


## The lists and dispatches the tally holds for *key*, as a pair.
static func _tally(key: String) -> Vector2i:
    var entry: Dictionary = SaCompute.kernel_counters().get(key, {})
    return Vector2i(int(entry.get("lists", 0)), int(entry.get("dispatches", 0)))


## Runs what the brush's batch asked of this frame's `process_frame`, as the
## tree would, and answers how many times it asked.
func _frame() -> int:
    var tree := Engine.get_main_loop() as SceneTree
    var asked: Array[Callable] = []
    for connection: Dictionary in tree.process_frame.get_connections():
        var callable: Callable = connection["callable"]
        if callable.get_object() == _brush()._walk_batch:
            asked.append(callable)
    for callable in asked:
        tree.process_frame.disconnect(callable)
        callable.call()
    return asked.size()


## *preset* at *size* px, pressed at [constant FROM] with its first report
## sent. Answers false when the shipped recipe could not be loaded.
func _press(preset: String, size: float) -> bool:
    var store := SaPresetStore.new()
    store.dir = scratch_dir
    store.install_shipped(_brush().settings, ShippedPresetsScript)
    if not store.apply_preset(preset, _brush().settings):
        return false
    _brush().settings.radius = size * 0.5 / SIDE
    _surface.view.mouse_position = FROM
    _button(true)
    _motion(FROM + STEP)
    _frame()
    return true


## Every texel of every field of the active layer's chunks, by chunk.
func _texels() -> Dictionary:
    var rd := GlobalShaderCompiler.get_rd()
    var out := {}
    var layer: SaLayer = _brush().surface.get_document().active_layer
    for at: Vector2i in layer.chunks:
        var chunk: SaChunk = layer.chunks[at]
        for field: StringName in chunk.field_ids():
            out["%s %s" % [at, field]] = rd.texture_get_data(chunk.field(field).rid, 0)
    return out


## *preset* at *size* px over twelve reports, the frame run after every
## *each* of them, and the last frame's left for the lift. Answers the layer's
## texels once the stroke is committed.
func _paint(preset: String, size: float, each: int) -> Dictionary:
    _fresh()
    assert_true(_press(preset, size), "%s loads" % preset)
    for i in 12:
        _motion(FROM + STEP * float(i + 2))
        if (i + 1) % each == 0 and i < 11:
            _frame()
    _button(false)
    return _texels()


func test_a_frames_reports_go_as_one_list() -> void:
    assert_true(_press("Pencil", 2.0), "Pencil loads")
    var before := _tally("dabs/dabs")
    var laid_before: int = _brush().stroke_info.dab_index
    for i in A_FRAME:
        _motion(FROM + STEP * float(i + 2))
    var laid: int = _brush().stroke_info.dab_index - laid_before
    assert_true(laid > A_FRAME * 10, "A 2 px Pencil lays many dabs over four reports, %d here" % laid)
    assert_eq(_tally("dabs/dabs") - before, Vector2i.ZERO, "and sends none of them while the frame's reports come in")
    assert_eq(_frame(), 1, "The four reports ask for the frame's send once")
    assert_eq(
        _tally("dabs/dabs") - before, Vector2i(1, 1), "which sends them as one list and one dispatch, the one chunk they cross"
    )
    assert_eq(_frame(), 0, "and asks for nothing more until the next report")
    _button(false)


func test_a_smudge_frame_sends_its_queue_once() -> void:
    assert_true(_press("Oil Smudge", 8.0), "Oil Smudge loads")
    var before := _tally("smudge/queue")
    for i in A_FRAME:
        _motion(FROM + STEP * float(i + 2))
    assert_eq(_tally("smudge/queue").x - before.x, 0, "A smudge stroke's four reports queue their dabs")
    _frame()
    assert_eq(_tally("smudge/queue").x - before.x, 1, "and the frame sends the queue as one list, which grows the snapshot once")
    _button(false)


func test_a_frame_paints_what_a_list_a_report_painted() -> void:
    for case: Array in [["Pencil", 2.0], ["Wash", 6.0], ["Oil Smudge", 8.0]]:
        var by_report := _paint(case[0], case[1], 1)
        var by_frame := _paint(case[0], case[1], A_FRAME)
        assert_eq(by_frame.keys(), by_report.keys(), "%s at %s px reaches the same chunks and fields" % case)
        var painted := 0
        var differing := 0
        for key: String in by_report:
            var one: PackedByteArray = by_report[key]
            var other: PackedByteArray = by_frame.get(key, PackedByteArray())
            if one != other:
                differing += 1
            for value in one:
                if value != 0:
                    painted += 1
                    break
        assert_true(painted > 0, "%s at %s px painted something" % case)
        assert_eq(differing, 0, "and a list a frame painted every texel a list a report did, to the bit")


func test_the_lift_sends_what_the_frame_held() -> void:
    assert_true(_press("Pencil", 2.0), "Pencil loads")
    var before := _tally("dabs/dabs")
    for i in A_FRAME:
        _motion(FROM + STEP * float(i + 2))
    _button(false)
    assert_eq(_tally("dabs/dabs").x - before.x, 1, "The lift sends the frame's dabs before the stroke is committed")


func test_a_reset_sends_what_the_frame_held() -> void:
    assert_true(_press("Pencil", 2.0), "Pencil loads")
    var before := _tally("dabs/dabs")
    for i in A_FRAME:
        _motion(FROM + STEP * float(i + 2))
    _brush().reset()
    assert_eq(_tally("dabs/dabs").x - before.x, 1, "A reset sends what the frame held rather than dropping it")
    assert_eq(_frame(), 0, "and the fresh batch has nothing to ask for")
