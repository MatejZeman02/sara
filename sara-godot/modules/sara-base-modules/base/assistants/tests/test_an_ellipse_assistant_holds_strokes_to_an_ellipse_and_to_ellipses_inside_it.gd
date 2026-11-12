## An ellipse assistant holds strokes to an ellipse and, with Concentric on, to
## the ellipses inside it.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The ellipse is placed the way the painter places it, with the Assistants
## tool in hand and its Shape on Ellipse: a drag from one end of an axis to the
## other, and a drag of the third handle that sets the other axis. A pen path
## that wobbles [constant WOBBLE] pixels either side of the curve then goes
## through the same machine with the stamp brush and with the noise brush, and
## every dab centre either engine lays is read back and measured against the
## curve by a search of this suite's own, not the assistant's. With Concentric
## on, a path starting well inside the ellipse is measured against the ellipse
## of the same shape and centre through the path's first point.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")

const MODULES: Array[String] = [
    "res://modules/sara-base-modules/stamp-brush/module.gd",
    "res://modules/sara-base-modules/base/module.gd",
    "res://modules/sara-noise-brush-engine/module.gd",
]
const NOISE := &"noise_brush"

const CANVAS := Vector2i(512, 384)
## The ends of the first axis, slanted so neither canvas axis hides a wobble,
## and the half length of the other axis the third handle sets.
const END_A := Vector2(100.0, 150.0)
const END_B := Vector2(410.0, 230.0)
const MINOR := 90.0
## How far either side of the curve the pen wanders, over how many samples.
const WOBBLE := 6.0
const SAMPLES := 90
## The scale of the ellipse the concentric path wanders about.
const INSIDE := 0.55
## The most a held dab centre may lie off its ellipse, and the least the wobble
## shows when nothing holds it.
const HELD := 0.5
const KEPT := 3.0

static var scratch: String = SaDataRoot.path("test_ellipses.sad")

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
    _machine.get_tool(SaAssistants.TOOL).set("shape", SaAssistants.StateAssistantsScript.Shape.ELLIPSE)


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


func _drag(from: Vector2, to: Vector2) -> void:
    _button(from, true)
    for i in range(1, 9):
        _move(from.lerp(to, i / 8.0))
    _button(to, false)


func _steps() -> int:
    return _doc.undo_redo.get_history_count()


## The centre, the unit first axis and the two half axes the test placed.
func _centre() -> Vector2:
    return (END_A + END_B) * 0.5


func _axis() -> Vector2:
    return (END_B - END_A).normalized()


func _halves() -> Vector2:
    return Vector2(END_A.distance_to(END_B) * 0.5, MINOR)


## The point of the ellipse scaled by *scale* at the angle *turn*, widened by
## *out* pixels along the radius.
func _on_curve(turn: float, scale: float, out: float = 0.0) -> Vector2:
    var half := _halves() * scale
    var spot := Vector2(cos(turn) * half.x, sin(turn) * half.y)
    spot += spot.normalized() * out
    return _centre() + _axis() * spot.x + _axis().orthogonal() * spot.y


## Places the test's ellipse with the tool, by its axis and then its third
## handle, which stands a quarter of the axis off the centre once placed.
func _place() -> void:
    _machine.set_active_tool(SaAssistants.TOOL)
    _drag(END_A, END_B)
    var third := _centre() + _axis().orthogonal() * END_A.distance_to(END_B) * 0.25
    _drag(third, _centre() + _axis().orthogonal() * MINOR)


## How far *at* lies from the ellipse scaled by *scale*, by a sweep of 720
## angles and a narrowing search about the nearest, which needs nothing of the
## assistant's own projection.
func _off_curve(at: Vector2, scale: float) -> float:
    var best := 0.0
    var nearest := INF
    for index in 720:
        var turn := TAU * index / 720.0
        var gap := at.distance_to(_on_curve(turn, scale))
        if gap < nearest:
            nearest = gap
            best = turn
    var low := best - TAU / 720.0
    var high := best + TAU / 720.0
    for _step in 60:
        var one := lerpf(low, high, 1.0 / 3.0)
        var two := lerpf(low, high, 2.0 / 3.0)
        if at.distance_to(_on_curve(one, scale)) < at.distance_to(_on_curve(two, scale)):
            high = two
        else:
            low = one
    return minf(nearest, at.distance_to(_on_curve((low + high) * 0.5, scale)))


## The pen's path at *i* of [constant SAMPLES], round most of the ellipse
## scaled by *scale* and wobbling across it.
func _path_point(i: int, scale: float) -> Vector2:
    var turn := 0.2 * PI + 1.3 * PI * float(i) / SAMPLES
    return _on_curve(turn, scale, WOBBLE * sin(float(i) * 0.7 + 0.4))


## Plays the wobbling path about the ellipse scaled by *scale* with *tool* in
## hand and answers every dab centre it laid, read after each event.
func _stroke(tool: StringName, scale: float) -> PackedVector2Array:
    _machine.set_active_tool(tool)
    var state := _machine.active_tool
    if tool != NOISE:
        state.set("is_tablet", false)
        state.get("settings").set("radius", 3.0 / CANVAS.y)
    var centres := PackedVector2Array()
    _button(_path_point(0, scale), true)
    _read(state, tool, centres)
    for i in range(1, SAMPLES + 1):
        _move(_path_point(i, scale))
        _read(state, tool, centres)
    _button(_path_point(SAMPLES, scale), false)
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


func _farthest(centres: PackedVector2Array, scale: float) -> float:
    var most := 0.0
    for at: Vector2 in centres:
        most = maxf(most, _off_curve(at, scale))
    return most


## The scale of the ellipse of the test's shape and centre through *at*.
func _scale_through(at: Vector2) -> float:
    var offset := at - _centre()
    var half := _halves()
    return Vector2(offset.dot(_axis()) / half.x, offset.dot(_axis().orthogonal()) / half.y).length()


func test_the_tool_places_an_ellipse_by_three_handles_each_drag_one_step() -> void:
    var before := _steps()
    _machine.set_active_tool(SaAssistants.TOOL)
    _drag(END_A, END_B)
    var ellipses := SaAssistants.ellipses(_doc)
    assert_eq(ellipses.size(), 1, "A drag with Shape on Ellipse places one ellipse")
    assert_eq(SaAssistants.of_shape(_doc, SaAssistants.RULER).size(), 0, "and no ruler")
    assert_eq(_steps(), before + 1, "as one step")
    var third := _centre() + _axis().orthogonal() * END_A.distance_to(END_B) * 0.25
    _drag(third, _centre() + _axis().orthogonal() * MINOR)
    ellipses = SaAssistants.ellipses(_doc)
    assert_true(
        (
            ellipses[0].a.distance_to(END_A) < 0.01
            and ellipses[0].b.distance_to(END_B) < 0.01
            and absf(ellipses[0].minor - MINOR) < 0.01
        ),
        "The third handle sets the other axis, %s" % ellipses[0].entry()
    )
    assert_eq(_steps(), before + 2, "as one step more")
    # A drag on the curve moves the whole ellipse.
    var on := _on_curve(0.25 * PI, 1.0)
    _drag(on, on + Vector2(12.0, 0.0))
    ellipses = SaAssistants.ellipses(_doc)
    assert_true(
        ellipses[0].a.distance_to(END_A + Vector2(12.0, 0.0)) < 0.01 and absf(ellipses[0].minor - MINOR) < 0.01,
        "A drag on the curve moves the whole ellipse, %s" % ellipses[0].entry()
    )
    # An end moves alone and keeps the other axis.
    _drag(END_B + Vector2(12.0, 0.0), END_B + Vector2(30.0, 0.0))
    ellipses = SaAssistants.ellipses(_doc)
    assert_true(
        (
            ellipses[0].b.distance_to(END_B + Vector2(30.0, 0.0)) < 0.01
            and ellipses[0].a.distance_to(END_A + Vector2(12.0, 0.0)) < 0.01
            and absf(ellipses[0].minor - MINOR) < 0.01
        ),
        "A drag on an end moves that end alone, %s" % ellipses[0].entry()
    )
    assert_eq(_steps(), before + 4, "each one step")
    _machine.active_tool.set("concentric", true)
    assert_true(SaAssistants.ellipses(_doc)[0].concentric, "Concentric is the picked ellipse's own")
    assert_eq(_steps(), before + 5, "and turning it is one step")
    _machine.active_tool.call("delete_picked")
    assert_eq(SaAssistants.ellipses(_doc).size(), 0, "Delete Assistant takes the ellipse away")
    for i in 6:
        _doc.undo_redo.undo()
    assert_eq(SaAssistants.ellipses(_doc).size(), 0, "and undoing every step leaves none")


func test_a_stamp_and_a_noise_stroke_near_the_ellipse_lay_every_dab_on_it() -> void:
    _place()
    for tool: StringName in [&"brush", NOISE]:
        var centres := _stroke(tool, 1.0)
        var most := _farthest(centres, 1.0)
        print("%s laid %d dab centres read, the farthest %.3f px off the ellipse" % [tool, centres.size(), most])
        assert_true(centres.size() > 20, "%s lays dabs to read, %d" % [tool, centres.size()])
        assert_true(most <= HELD, "Every %s dab lies within %.1f px of the ellipse, the farthest %.3f" % [tool, HELD, most])


func test_with_concentric_on_a_stroke_inside_follows_the_ellipse_through_its_first_point() -> void:
    _place()
    _machine.set_active_tool(SaAssistants.TOOL)
    _machine.active_tool.set("concentric", true)
    var scale := _scale_through(_path_point(0, INSIDE))
    assert_true(scale < 0.7, "The path starts well inside the ellipse, at %.3f of it" % scale)
    for tool: StringName in [&"brush", NOISE]:
        var centres := _stroke(tool, INSIDE)
        var most := _farthest(centres, scale)
        print(
            (
                "with Concentric on %s laid %d dab centres read, the farthest %.3f px off the ellipse at %.3f"
                % [tool, centres.size(), most, scale]
            )
        )
        assert_true(centres.size() > 20, "%s lays dabs to read, %d" % [tool, centres.size()])
        assert_true(
            most <= HELD,
            "Every %s dab lies within %.1f px of the ellipse through the first point, the farthest %.3f" % [tool, HELD, most]
        )


func test_with_snap_off_the_same_path_keeps_its_wobble() -> void:
    _place()
    SaAssistants.switches.snap = false
    for tool: StringName in [&"brush", NOISE]:
        var most := _farthest(_stroke(tool, 1.0), 1.0)
        print("with Snap off %s lies %.3f px off the ellipse at most" % [tool, most])
        assert_true(most >= KEPT, "With Snap off %s keeps its wobble, %.3f px off the ellipse" % [tool, most])


func test_an_ellipse_saved_in_a_sad_comes_back_with_its_concentric_switch() -> void:
    var kept := SaAssistants.Ellipse.new(END_A, END_B, MINOR, true)
    SaAssistants.keep(_doc, [SaAssistants.Guide.new(END_A, END_B, SaAssistants.RULER).entry(), kept.entry()])
    assert_eq(SaExport.save_sad(_doc, scratch), OK, "Saving succeeds")
    var reopened := SaDocument.new()
    reopened.setup_default_document(Vector2i(16, 16), SaCompositor.new())
    assert_eq(SaExport.load_sad(reopened, scratch), OK, "Loading succeeds")
    var ellipses := SaAssistants.ellipses(reopened)
    assert_eq(ellipses.size(), 1, "The ellipse comes back")
    assert_eq(SaAssistants.of_shape(reopened, SaAssistants.RULER).size(), 1, "beside the ruler")
    if ellipses.size() == 1:
        assert_eq(ellipses[0].entry(), kept.entry(), "where it was, Concentric on")
    reopened.free()
