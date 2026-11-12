## A ruler the painter places on the canvas holds every brush stroke to its
## line while snapping is on.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The ruler is placed the way the painter places it, a press at one end, a
## drag and a release at the other, with the Assistants tool in hand. A pen
## path that wobbles [constant WOBBLE] pixels either side of the ruler's line
## then goes through the same machine with the stamp brush and with the noise
## brush in hand, and every dab centre either engine lays is read back. With
## Snap on each lies within [constant HELD] pixels of the line, and with Snap
## off, or the rulers hidden, the same path keeps its wobble.
##
## The file half saves two rulers in a `.sad`, opens it into another document
## and finds both where they were, and opens a file saved before rulers
## existed with nothing said and no ruler in it.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")

const MODULES: Array[String] = [
    "res://modules/sara-base-modules/stamp-brush/module.gd",
    "res://modules/sara-base-modules/base/module.gd",
    "res://modules/sara-noise-brush-engine/module.gd",
    "res://modules/sara-base-modules/filter-brush/module.gd",
]
const NOISE := &"noise_brush"

const CANVAS := Vector2i(512, 384)
## The ruler's two ends, a slanted line so neither axis hides a wobble.
const RULER_A := Vector2(60.0, 110.0)
const RULER_B := Vector2(450.0, 250.0)
## A second ruler for the file, far from the first.
const SECOND_A := Vector2(80.0, 330.0)
const SECOND_B := Vector2(420.0, 300.0)
## How far either side of the line the pen wanders, over how many samples.
const WOBBLE := 6.0
const SAMPLES := 90
## The most a held dab centre may lie off the line, and the least the wobble
## shows when nothing holds it.
const HELD := 0.5
const KEPT := 3.0
## A file saved before rulers existed.
const OLD_FILE := "res://tests/data/plain_v4.sad"

static var scratch: String = SaDataRoot.path("test_rulers.sad")

var _surface: SaSurface = null
var _doc: SaDocument = null
var _registries: SaRegistries = null
var _modules: Array[SaModule] = []
var _machine: ToolMachine = null


func before_each() -> void:
    _surface = Fixtures.make_surface(CANVAS)
    _doc = _surface.easel.document
    _registries = Fixtures.make_registries(_surface)
    for path: String in MODULES:
        var module: SaModule = load(path).new()
        module.register(_registries.context.for_module(module.get_id()))
        _modules.append(module)
    _machine = ToolMachine.new()
    _machine.name = "ToolMachine"
    _machine._ready()
    _machine.bind(_surface, _registries.tools, _registries.roles)
    SaAssistants.switches.snap = true
    SaAssistants.switches.shown = true


func after_each() -> void:
    for module: SaModule in _modules:
        module.unregister(_registries.context.for_module(module.get_id()))
    _modules.clear()
    Fixtures.teardown(_surface, _machine)
    _surface = null
    _doc = null
    _machine = null
    _registries = null
    DirAccess.remove_absolute(ProjectSettings.globalize_path(scratch))


func _button(at: Vector2, pressed: bool) -> void:
    _surface.view.mouse_position = at
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = pressed
    event.position = at
    event.global_position = at
    _machine.handle_input(event)


func _move(at: Vector2) -> void:
    _surface.view.mouse_position = at
    var event := InputEventMouseMotion.new()
    event.position = at
    event.global_position = at
    event.pressure = 0.8
    event.button_mask = MOUSE_BUTTON_MASK_LEFT
    _machine.handle_input(event)


func _steps() -> int:
    return _doc.undo_redo.get_history_count()


## Places a ruler from *from* to *to* with the Assistants tool.
func _place(from: Vector2, to: Vector2) -> void:
    _machine.set_active_tool(SaAssistants.TOOL)
    _button(from, true)
    for i in range(1, 9):
        _move(from.lerp(to, i / 8.0))
    _button(to, false)


## The point on the pen's path at *i* of [constant SAMPLES], along the
## ruler's middle and wobbling across it.
func _path_point(i: int) -> Vector2:
    var along := RULER_A.lerp(RULER_B, 0.15 + 0.7 * float(i) / SAMPLES)
    var across := (RULER_B - RULER_A).normalized().orthogonal()
    return along + across * WOBBLE * sin(float(i) * 0.7 + 0.4)


## The distance of *at* from the first ruler's line.
func _off_line(at: Vector2) -> float:
    var direction := (RULER_B - RULER_A).normalized()
    return absf((at - RULER_A).dot(direction.orthogonal()))


## Plays the wobbling path with *tool* in hand and answers every dab centre it
## laid, read after each event.
func _stroke(tool: StringName) -> PackedVector2Array:
    _machine.set_active_tool(tool)
    var state := _machine.active_tool
    if tool != NOISE:
        state.set("is_tablet", false)
        state.get("settings").set("radius", 3.0 / CANVAS.y)
    var centres := PackedVector2Array()
    _button(_path_point(0), true)
    _read(state, tool, centres)
    for i in range(1, SAMPLES + 1):
        _move(_path_point(i))
        _read(state, tool, centres)
    _button(_path_point(SAMPLES), false)
    if tool != NOISE:
        for dab: SaDabParams in state.get("sampled_dabs"):
            centres.append(dab.position)
    return centres


func _read(state: ToolState, tool: StringName, centres: PackedVector2Array) -> void:
    if tool == NOISE:
        var point: Variant = state.get("_newest")
        if point != null:
            centres.append(point.at)
        return
    var dab: SaDabParams = state.get("last_dab")
    if dab != null:
        centres.append(dab.position)


func _farthest(centres: PackedVector2Array) -> float:
    var most := 0.0
    for at: Vector2 in centres:
        most = maxf(most, _off_line(at))
    return most


func test_the_assistants_tool_places_a_ruler_as_one_undo_step() -> void:
    var before := _steps()
    _place(RULER_A, RULER_B)
    var rulers := SaAssistants.guides(_doc)
    assert_eq(rulers.size(), 1, "One ruler is placed")
    assert_true(
        rulers[0].a.distance_to(RULER_A) < 0.01 and rulers[0].b.distance_to(RULER_B) < 0.01,
        "from where the press was to where the release was, %s to %s" % [rulers[0].a, rulers[0].b]
    )
    assert_eq(_steps(), before + 1, "Placing it is one step")
    # A drag from the middle moves the whole ruler, one step more.
    _machine.set_active_tool(SaAssistants.TOOL)
    var middle := RULER_A.lerp(RULER_B, 0.5)
    _button(middle, true)
    _move(middle + Vector2(0.0, 10.0))
    _move(middle + Vector2(0.0, 20.0))
    _button(middle + Vector2(0.0, 20.0), false)
    rulers = SaAssistants.guides(_doc)
    assert_true(
        rulers[0].a.distance_to(RULER_A + Vector2(0.0, 20.0)) < 0.01,
        "A drag from its middle moves the whole ruler, %s" % rulers[0].a
    )
    assert_eq(_steps(), before + 2, "and is one step")
    # A drag from an end moves that end alone.
    _button(RULER_B + Vector2(0.0, 20.0), true)
    _move(RULER_B + Vector2(0.0, 40.0))
    _button(RULER_B + Vector2(0.0, 40.0), false)
    rulers = SaAssistants.guides(_doc)
    assert_true(
        (
            rulers[0].b.distance_to(RULER_B + Vector2(0.0, 40.0)) < 0.01
            and rulers[0].a.distance_to(RULER_A + Vector2(0.0, 20.0)) < 0.01
        ),
        "A drag from an end moves that end alone, %s to %s" % [rulers[0].a, rulers[0].b]
    )
    assert_eq(_steps(), before + 3, "and is one step")
    _machine.active_tool.call("delete_picked")
    assert_eq(SaAssistants.guides(_doc).size(), 0, "Delete Assistant takes it away")
    assert_eq(_steps(), before + 4, "as one step")
    _doc.undo_redo.undo()
    assert_eq(SaAssistants.guides(_doc).size(), 1, "and an undo brings it back")
    _doc.undo_redo.undo()
    _doc.undo_redo.undo()
    _doc.undo_redo.undo()
    assert_eq(SaAssistants.guides(_doc).size(), 0, "Undoing the place leaves no ruler")


func test_a_stamp_stroke_with_snap_on_lays_every_dab_on_the_ruler() -> void:
    _place(RULER_A, RULER_B)
    var centres := _stroke(&"brush")
    var most := _farthest(centres)
    print("the stamp laid %d dab centres read, the farthest %.3f px off the ruler" % [centres.size(), most])
    assert_true(centres.size() > 20, "The stamp lays dabs to read, %d" % centres.size())
    assert_true(most <= HELD, "Every stamp dab lies within %.1f px of the ruler, the farthest %.3f" % [HELD, most])


func test_an_eraser_stroke_with_snap_on_lays_every_dab_on_the_ruler() -> void:
    _place(RULER_A, RULER_B)
    var centres := _stroke(&"eraser")
    var most := _farthest(centres)
    assert_true(centres.size() > 20, "The eraser lays dabs to read, %d" % centres.size())
    assert_true(most <= HELD, "Every eraser dab lies within %.1f px of the ruler, the farthest %.3f" % [HELD, most])


## Every brush engine is held, the filter brush among them, and a fill, a
## gradient or a liquify is not, whose press is a place and not a path.
func test_every_brush_engine_takes_the_hold_and_no_other_tool_does() -> void:
    for tool: StringName in [&"brush", &"eraser", NOISE, &"filter_brush"]:
        assert_true(_machine.get_tool(tool).takes_holds, "%s is held to a ruler" % tool)
    for tool: StringName in [&"bucket_fill", &"gradient", SaAssistants.TOOL]:
        assert_false(_machine.get_tool(tool).takes_holds, "%s is never held" % tool)


func test_a_noise_stroke_with_snap_on_lays_every_dab_on_the_ruler() -> void:
    _place(RULER_A, RULER_B)
    var centres := _stroke(NOISE)
    var most := _farthest(centres)
    print("the noise brush laid %d dab centres read, the farthest %.3f px off the ruler" % [centres.size(), most])
    assert_true(centres.size() > 20, "The noise brush lays dabs to read, %d" % centres.size())
    assert_true(most <= HELD, "Every noise dab lies within %.1f px of the ruler, the farthest %.3f" % [HELD, most])


func test_with_snap_off_the_same_path_keeps_its_wobble() -> void:
    _place(RULER_A, RULER_B)
    SaAssistants.switches.snap = false
    for tool: StringName in [&"brush", NOISE]:
        var most := _farthest(_stroke(tool))
        print("with Snap off %s lies %.3f px off the ruler at most" % [tool, most])
        assert_true(most >= KEPT, "With Snap off %s keeps its wobble, %.3f px off the line" % [tool, most])


func test_a_hidden_ruler_holds_no_stroke() -> void:
    _place(RULER_A, RULER_B)
    SaAssistants.switches.shown = false
    var most := _farthest(_stroke(&"brush"))
    assert_true(most >= KEPT, "With the rulers hidden the stamp keeps its wobble, %.3f px off the line" % most)


func test_two_rulers_saved_in_a_sad_come_back_where_they_were() -> void:
    SaAssistants.keep(
        _doc, [SaAssistants.Guide.new(RULER_A, RULER_B).entry(), SaAssistants.Guide.new(SECOND_A, SECOND_B).entry()]
    )
    assert_eq(SaExport.save_sad(_doc, scratch), OK, "Saving succeeds")
    var reopened := SaDocument.new()
    reopened.setup_default_document(Vector2i(16, 16), SaCompositor.new())
    assert_eq(SaExport.load_sad(reopened, scratch), OK, "Loading succeeds")
    var rulers := SaAssistants.guides(reopened)
    assert_eq(rulers.size(), 2, "Both rulers come back")
    if rulers.size() == 2:
        assert_eq([rulers[0].a, rulers[0].b], [RULER_A, RULER_B], "the first where it was")
        assert_eq([rulers[1].a, rulers[1].b], [SECOND_A, SECOND_B], "and the second where it was")
    reopened.free()


func test_a_sad_saved_before_rulers_opens_with_none() -> void:
    var opened := SaDocument.new()
    opened.setup_default_document(Vector2i(16, 16), SaCompositor.new())
    assert_eq(SaExport.load_sad(opened, OLD_FILE), OK, "A file saved before rulers opens")
    assert_eq(SaAssistants.guides(opened).size(), 0, "with no ruler in it")
    opened.free()
