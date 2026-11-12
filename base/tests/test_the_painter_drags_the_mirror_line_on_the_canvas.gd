## The painter drags a mirror layer's line on the canvas.
##
## The line is placed on the canvas the way the symmetry axes are, not by typing
## numbers. While a mirror layer is the
## active layer its line and two handles stand over the canvas, a drag on a
## handle turns the line about the other, a drag on the line moves it, and each
## is one undo step. The presses go through `MainCanvas`'s own input, the way a
## pointer reaches it, and the record's values are read back.
extends "res://tests/test_framework.gd"

## Needs a RenderingDevice, for the main canvas's easel.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const MainCanvasScript = preload("res://render/main_canvas.gd")
const MirrorFilter = preload("res://modules/sara-base-modules/base/usual/mirror_filter.gd")

const OWNER: StringName = &"sara-base-modules"
const MIRROR: StringName = &"sara-base-modules.mirror"
const SIZE := Vector2i(256, 256)

var _host: Node = null
var _record: SaAttachedFilter = null


func after_each() -> void:
    if _host != null:
        var canvas := _host.get_child(0) as Node
        var machine: ToolMachine = canvas.get("tool_machine")
        machine.registered_tools.clear()
        machine.active_tool = null
        machine.registry = null
        _host.free()
        _host = null
    _record = null
    ToolMachine.pointer_holder = &""


func test_a_drag_on_a_handle_turns_the_line_about_the_other_and_one_undo_restores_it() -> void:
    var main := _canvas_with_a_mirror()
    var doc := _doc(main)
    var guide := SaEffectGuide.of(doc, _filters(main))
    assert_not_null(guide, "The mirror layer is the active layer, so its line is there")
    var ends := guide.handles()
    assert_eq(ends[0], Vector2(128, 128) - Vector2(guide.arm(), 0.0), "The line is level through the middle, a handle each side")
    var steps := doc.history.position()

    var turned := ends[0] + Vector2.from_angle(deg_to_rad(30.0)) * 2.0 * guide.arm()
    _drag(main, ends[1], [ends[1].lerp(turned, 0.5), turned])
    assert_almost_eq(float(_record.parameters["angle"]), 30.0, 0.01, "The record's angle moved to thirty degrees")
    assert_true(guide.handles()[0].is_equal_approx(ends[0]), "about the handle that was not dragged")
    assert_true(guide.handles()[1].is_equal_approx(turned), "and the dragged one stands where the pointer turned it")
    assert_eq(doc.history.position(), steps + 1, "The whole drag is one step")
    assert_true(doc.modified, "and a change the document has to save")
    assert_false(main.get("_capturing_stroke") == true, "Nothing was painted by the drag")

    assert_true(doc.undo(), "One undo")
    assert_almost_eq(SaTyped.real(_record.parameters.get("angle"), 0.0), 0.0, 1e-6, "puts the angle back")
    assert_eq(doc.history.position(), steps, "and the history where it was")
    assert_true(doc.redo(), "and a redo")
    assert_almost_eq(float(_record.parameters["angle"]), 30.0, 0.01, "brings the turn back")


func test_the_other_handle_turns_it_too_and_shift_snaps_the_angle() -> void:
    var main := _canvas_with_a_mirror()
    var guide := SaEffectGuide.of(_doc(main), _filters(main))
    var ends := guide.handles()
    var pulled := ends[1] + Vector2.from_angle(deg_to_rad(-44.0)) * 2.0 * guide.arm()
    _drag(main, ends[0], [pulled], true)
    # The dragged handle is the one behind the point, so the line's direction
    # runs from the pointer to the pivot, 135 degrees for the line at minus 45.
    assert_almost_eq(float(_record.parameters["angle"]), 135.0, 0.01, "Shift turns by whole steps of fifteen degrees")
    assert_true(guide.handles()[1].is_equal_approx(ends[1]), "about the handle that stayed")


func test_a_drag_on_the_line_moves_its_point_and_keeps_its_angle() -> void:
    var main := _canvas_with_a_mirror({"angle": 20.0})
    var doc := _doc(main)
    var guide := SaEffectGuide.of(doc, _filters(main))
    var steps := doc.history.position()
    var on_the_line := guide.point() + Vector2.from_angle(deg_to_rad(20.0)) * 100.0
    var travel := Vector2(10, -30)
    _drag(main, on_the_line, [on_the_line + travel * 0.5, on_the_line + travel])
    assert_almost_eq(float(_record.parameters["angle"]), 20.0, 1e-4, "The angle is kept")
    assert_almost_eq(
        float(_record.parameters["point_x"]), (128.0 + 10.0) / 256.0 * 100.0, 1e-3, "and the point moved across by the travel"
    )
    assert_almost_eq(float(_record.parameters["point_y"]), (128.0 - 30.0) / 256.0 * 100.0, 1e-3, "and up")
    assert_eq(doc.history.position(), steps + 1, "One step")
    assert_true(doc.undo(), "and one undo")
    assert_almost_eq(SaTyped.real(_record.parameters.get("point_y"), 50.0), 50.0, 1e-6, "puts the point back")
    assert_almost_eq(SaTyped.real(_record.parameters.get("angle"), 0.0), 20.0, 1e-6, "with the angle where it was")


func test_a_press_that_moves_nothing_makes_no_step() -> void:
    var main := _canvas_with_a_mirror()
    var doc := _doc(main)
    var guide := SaEffectGuide.of(doc, _filters(main))
    var steps := doc.history.position()
    var at := guide.handles()[1]
    _drag(main, at, [at])
    assert_eq(doc.history.position(), steps, "A press and a release in place leave the history alone")


func test_a_layer_that_is_not_a_mirror_has_no_line_and_the_press_goes_to_the_tool() -> void:
    var main := _canvas_with_a_mirror()
    var doc := _doc(main)
    var plain := SaLayerOps.new(doc).add()
    doc.set_active_layer(plain)
    assert_null(SaEffectGuide.of(doc, _filters(main)), "A plain layer has no line")
    main.call("_on_canvas_gui_input", _button(main, Vector2(30, 128), true))
    assert_false(main.get("_axes_held") == true, "so a press where the line was is not taken")
    main.call("_input", _global(_button(main, Vector2(30, 128), false), main))


## The main canvas over a document of [constant SIZE], the brush in hand, and a
## mirror layer, active, whose first record is the Mirror with *values*.
func _canvas_with_a_mirror(values: Dictionary = {}) -> Node:
    _host = Node.new()
    _host.name = "GuideHost"
    var main: Node = MainCanvasScript.new()
    var canvas: SaCanvas = main.get("canvas")
    canvas.canvas_size = SIZE
    _host.add_child(main)
    EventBus.add_child(_host)
    main.call("bind_tools", Fixtures.make_tool_registry())
    (main.get("tool_machine") as ToolMachine).set_active_tool(&"brush")
    (main.get("canvas") as SaCanvas).compositor.filter_chain.registry = SaFilterRegistry.new()
    _filters(main).register(MirrorFilter.new(), OWNER)
    var doc := _doc(main)
    var mirror := SaLayerOps.new(doc).add(SaEffectLayer.TYPE_ID, Fixtures.make_registries().layer_types)
    _record = SaFilterOps.new(doc).attach(mirror, MIRROR, values)
    doc.set_active_layer(mirror)
    return main


func _filters(main: Node) -> SaFilterRegistry:
    return (main.get("canvas") as SaCanvas).compositor.filter_chain.registry


func _doc(main: Node) -> SaDocument:
    return (main.get("canvas") as SaCanvas).document


## A press on *from*, a motion through each of *path* and the release at its
## end, the press through the surface's GUI and the rest through `_input` as a
## held drag arrives.
func _drag(main: Node, from: Vector2, path: Array, shift: bool = false) -> void:
    main.call("_on_canvas_gui_input", _button(main, from, true))
    var at := from
    for each: Vector2 in path:
        at = each
        var motion := InputEventMouseMotion.new()
        motion.position = _local(main, at)
        motion.shift_pressed = shift
        motion.button_mask = MOUSE_BUTTON_MASK_LEFT
        main.call("_input", _global(motion, main))
    var release := _button(main, at, false)
    release.shift_pressed = shift
    main.call("_input", _global(release, main))


func _local(main: Node, document: Vector2) -> Vector2:
    return (main.get("canvas") as SaCanvas).get_transform() * document


func _global(event: InputEventMouse, main: Node) -> InputEventMouse:
    return event.xformed_by((main.get("control_node") as Control).get_global_transform()) as InputEventMouse


func _button(main: Node, document: Vector2, pressed: bool) -> InputEventMouseButton:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = pressed
    event.position = _local(main, document)
    event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
    return event
