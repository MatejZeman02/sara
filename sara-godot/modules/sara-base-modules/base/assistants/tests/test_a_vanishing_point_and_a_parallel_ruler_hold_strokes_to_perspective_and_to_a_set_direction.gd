## A vanishing point and a parallel ruler hold strokes to perspective and to a
## set direction.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Each assistant is placed the way the painter places it, with the Assistants
## tool in hand and its Assistant row on the shape: a press for a vanishing
## point, a drag from one handle to the other for a parallel ruler. Pen paths
## that wobble [constant WOBBLE] pixels either side of where they head then go
## through the same machine with the stamp brush in hand, and every dab centre
## it lays is read back. With Snap on each lies within [constant HELD] pixels
## of the line from the stroke's first point to the vanishing point, or of the
## line through its first point along the parallel ruler. With two or three
## vanishing points each stroke runs to the one its first motion heads for.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const StateAssistantsScript = preload("res://modules/sara-base-modules/base/assistants/state_assistants.gd")

const MODULES: Array[String] = [
    "res://modules/sara-base-modules/stamp-brush/module.gd",
    "res://modules/sara-base-modules/base/module.gd",
]

const CANVAS := Vector2i(512, 384)
## The one vanishing point, and three presses far apart on the canvas.
const POINT := Vector2(440.0, 60.0)
const STARTS: Array[Vector2] = [Vector2(60.0, 300.0), Vector2(100.0, 120.0), Vector2(300.0, 340.0)]
## Three points for three point perspective, left and right on the horizon
## and one far below for the verticals.
const LEFT := Vector2(20.0, 60.0)
const RIGHT := Vector2(490.0, 60.0)
const BELOW := Vector2(256.0, 1800.0)
## A parallel ruler's handles, and the presses of two hatching strokes.
const PARALLEL_A := Vector2(60.0, 40.0)
const PARALLEL_B := Vector2(200.0, 90.0)
const HATCHES: Array[Vector2] = [Vector2(80.0, 200.0), Vector2(150.0, 300.0)]
## How far either side of its heading the pen wanders, over how many samples,
## and how far the path runs.
const WOBBLE := 5.0
const SAMPLES := 60
const RUN := 220.0
## The most a held dab centre may lie off its line, and the least the wobble
## shows when nothing holds it.
const HELD := 0.5
const KEPT := 3.0

static var scratch: String = SaDataRoot.path("test_assistants.sad")

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


## Places an assistant of *shape*, a `Shape` of the tool, by a press at *from*
## and a release at *to*, with the Assistants tool in hand.
func _place(shape: int, from: Vector2, to: Vector2) -> void:
    _machine.set_active_tool(SaAssistants.TOOL)
    _machine.active_tool.set("shape", shape)
    _button(from, true)
    for i in range(1, 9):
        _move(from.lerp(to, i / 8.0))
    _button(to, false)


## The pen's path at *i* of [constant SAMPLES] from *start* heading for
## *toward*, wandering across its heading as a hand does, slowly.
func _path_point(start: Vector2, toward: Vector2, i: int) -> Vector2:
    var heading := (toward - start).normalized()
    var t := float(i) / SAMPLES
    return start + heading * RUN * t + heading.orthogonal() * WOBBLE * sin(float(i) * 0.2)


## Plays the path from *start* heading for *toward* with the stamp brush and
## answers every dab centre it laid, read after each event.
func _stroke(start: Vector2, toward: Vector2) -> PackedVector2Array:
    _machine.set_active_tool(&"brush")
    var state := _machine.active_tool
    state.set("is_tablet", false)
    state.get("settings").set("radius", 3.0 / CANVAS.y)
    var centres := PackedVector2Array()
    _button(_path_point(start, toward, 0), true)
    _read(state, centres)
    for i in range(1, SAMPLES + 1):
        _move(_path_point(start, toward, i))
        _read(state, centres)
    _button(_path_point(start, toward, SAMPLES), false)
    for dab: SaDabParams in state.get("sampled_dabs"):
        centres.append(dab.position)
    return centres


func _read(state: ToolState, centres: PackedVector2Array) -> void:
    var dab: SaDabParams = state.get("last_dab")
    if dab != null:
        centres.append(dab.position)


## The farthest of *centres* from the line through *through* along *along*.
func _farthest(centres: PackedVector2Array, through: Vector2, along: Vector2) -> float:
    var across := along.normalized().orthogonal()
    var most := 0.0
    for at: Vector2 in centres:
        most = maxf(most, absf((at - through).dot(across)))
    return most


func test_a_press_places_a_vanishing_point_as_one_undo_step() -> void:
    var before := _steps()
    _place(StateAssistantsScript.Shape.VANISHING, POINT, POINT)
    var placed := SaAssistants.of_shape(_doc, SaAssistants.VANISHING)
    assert_eq(placed.size(), 1, "A press places one vanishing point")
    if placed.size() == 1:
        assert_eq(placed[0].a, POINT, "where the press was")
    assert_eq(_steps(), before + 1, "as one step")
    # A drag from its handle moves it, one step more.
    _place(StateAssistantsScript.Shape.RULER, POINT, POINT + Vector2(-30.0, 10.0))
    placed = SaAssistants.of_shape(_doc, SaAssistants.VANISHING)
    assert_eq(SaAssistants.guides(_doc).size(), 1, "A drag from its handle places nothing new")
    if placed.size() == 1:
        assert_eq(placed[0].a, POINT + Vector2(-30.0, 10.0), "and moves the point")
    assert_eq(_steps(), before + 2, "as one step")
    _doc.undo_redo.undo()
    _doc.undo_redo.undo()
    assert_eq(SaAssistants.guides(_doc).size(), 0, "Undoing the place leaves no assistant")


func test_strokes_from_three_places_run_to_the_vanishing_point() -> void:
    _place(StateAssistantsScript.Shape.VANISHING, POINT, POINT)
    for start: Vector2 in STARTS:
        var first := _path_point(start, POINT, 0)
        var centres := _stroke(start, POINT)
        var most := _farthest(centres, first, POINT - first)
        print("from %s %d dab centres, the farthest %.3f px off the line to the point" % [start, centres.size(), most])
        assert_true(centres.size() > 20, "The stamp lays dabs to read from %s, %d" % [start, centres.size()])
        assert_true(most <= HELD, "Every dab from %s runs to the vanishing point, the farthest %.3f px off" % [start, most])


func test_with_three_vanishing_points_a_stroke_runs_to_the_one_it_heads_for() -> void:
    for point: Vector2 in [LEFT, RIGHT, BELOW]:
        _place(StateAssistantsScript.Shape.VANISHING, point, point)
    var start := Vector2(250.0, 220.0)
    for point: Vector2 in [LEFT, RIGHT, BELOW]:
        var first := _path_point(start, point, 0)
        var most := _farthest(_stroke(start, point), first, point - first)
        print("heading for %s, the farthest dab %.3f px off the line to it" % [point, most])
        assert_true(most <= HELD, "A stroke heading for %s runs to it, the farthest %.3f px off" % [point, most])


func test_hatching_strokes_run_parallel_to_the_parallel_ruler() -> void:
    _place(StateAssistantsScript.Shape.PARALLEL, PARALLEL_A, PARALLEL_B)
    var placed := SaAssistants.of_shape(_doc, SaAssistants.PARALLEL)
    assert_eq(placed.size(), 1, "A drag places one parallel ruler")
    var along := PARALLEL_B - PARALLEL_A
    for start: Vector2 in HATCHES:
        var first := _path_point(start, start + along, 0)
        var centres := _stroke(start, start + along)
        var most := _farthest(centres, first, along)
        print("hatching from %s, %d centres, the farthest %.3f px off" % [start, centres.size(), most])
        assert_true(centres.size() > 20, "The stamp lays dabs to read from %s, %d" % [start, centres.size()])
        assert_true(most <= HELD, "Every dab from %s runs parallel to the ruler, the farthest %.3f px off" % [start, most])


func test_a_press_on_a_ruler_keeps_to_the_ruler_beside_a_vanishing_point() -> void:
    var ruler_a := Vector2(60.0, 200.0)
    var ruler_b := Vector2(450.0, 260.0)
    _place(StateAssistantsScript.Shape.VANISHING, POINT, POINT)
    _place(StateAssistantsScript.Shape.RULER, ruler_a, ruler_b)
    var start := ruler_a.lerp(ruler_b, 0.1) + Vector2(0.0, 3.0)
    var most := _farthest(_stroke(start, start + (ruler_b - ruler_a)), ruler_a, ruler_b - ruler_a)
    assert_true(most <= HELD, "A stroke pressed beside a ruler keeps to it, the farthest %.3f px off" % most)


func test_with_snap_off_a_stroke_keeps_its_wobble() -> void:
    _place(StateAssistantsScript.Shape.VANISHING, POINT, POINT)
    SaAssistants.switches.snap = false
    var first := _path_point(STARTS[0], POINT, 0)
    var most := _farthest(_stroke(STARTS[0], POINT), first, POINT - first)
    assert_true(most >= KEPT, "With Snap off the stroke keeps its wobble, %.3f px off the line" % most)


func test_every_shape_saved_in_a_sad_comes_back_where_it_was() -> void:
    var kept := [
        SaAssistants.Guide.new(LEFT, LEFT, SaAssistants.VANISHING).entry(),
        SaAssistants.Guide.new(PARALLEL_A, PARALLEL_B, SaAssistants.PARALLEL).entry(),
        SaAssistants.Guide.new(STARTS[0], STARTS[1]).entry(),
    ]
    SaAssistants.keep(_doc, kept)
    assert_eq(SaExport.save_sad(_doc, scratch), OK, "Saving succeeds")
    var reopened := SaDocument.new()
    reopened.setup_default_document(Vector2i(16, 16), SaCompositor.new())
    assert_eq(SaExport.load_sad(reopened, scratch), OK, "Loading succeeds")
    var back: Array = []
    for guide: SaAssistants.Guide in SaAssistants.guides(reopened):
        back.append(guide.entry())
    assert_eq(back, kept, "A vanishing point, a parallel ruler and a ruler come back where they were")
    reopened.free()
