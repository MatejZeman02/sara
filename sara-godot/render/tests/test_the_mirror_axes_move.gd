## The mirror axes stand on two handles placed anywhere.
##
## A painter said: "I thought it would have two handles (points) that
## could be placed anywhere, so any angle would be possible." So the axis is
## the line through two handles, a drag of one turns and stretches it about the
## other, a drag of the line moves it, and the second mirror and the radial
## spokes follow its centre and angle. Before this a drag on the line painted a
## mirrored stroke, because nothing ahead of the tool machine looked at the
## axes, and the centre moved only when the canvas changed size.
extends "res://tests/test_framework.gd"

## Needs a RenderingDevice, for the main canvas's easel and the file's chunks.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const MainCanvasScript = preload("res://render/main_canvas.gd")

const SIZE := Vector2i(256, 256)
static var scratch_round_trip: String = SaDataRoot.path("test_s6_axes_round_trip.sad")
static var scratch_at_rest: String = SaDataRoot.path("test_s6_axes_at_rest.sad")

var _host: Node = null
var _picked: Array[Color] = []


func after_each() -> void:
    for path: String in [scratch_round_trip, scratch_at_rest]:
        DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
    if _host != null:
        var canvas := _host.get_child(0) as Node
        var machine: ToolMachine = canvas.get("tool_machine")
        machine.registered_tools.clear()
        machine.active_tool = null
        machine.registry = null
        _host.free()
        _host = null
    ToolMachine.pointer_holder = &""
    if EventBus.color_picked.is_connected(_on_picked):
        EventBus.color_picked.disconnect(_on_picked)


func _on_picked(color: Color) -> void:
    _picked.append(color)


func test_a_point_and_its_image_stand_either_side_of_a_slanted_line() -> void:
    var symmetry := SaSymmetry.new()
    symmetry.center = Vector2(128, 128)
    symmetry.angle = deg_to_rad(30.0)
    symmetry.mirror_horizontal = true
    var point := Vector2(60, 90)
    var images := symmetry.images(point)
    assert_eq(images.size(), 2, "One point becomes two")
    var image := images[1]
    var normal := symmetry.across_direction()
    var side := (point - symmetry.center).dot(normal)
    assert_true(absf(side) > 1.0, "The point is off the line, %s" % side)
    assert_almost_eq((image - symmetry.center).dot(normal), -side, 1e-3, "Its image is as far from the line, on the other side")
    assert_almost_eq((image - point).dot(symmetry.axis_direction()), 0.0, 1e-3, "straight across it")

    symmetry.mirror_horizontal = false
    symmetry.mirror_vertical = true
    image = symmetry.images(point)[1]
    side = (point - symmetry.center).dot(symmetry.axis_direction())
    assert_almost_eq(
        (image - symmetry.center).dot(symmetry.axis_direction()),
        -side,
        1e-3,
        "The second mirror the same, across the line at right angles"
    )


func test_angle_nought_is_the_upright_cross_there_was() -> void:
    var symmetry := SaSymmetry.new()
    symmetry.center = Vector2(100, 70)
    symmetry.mirror_horizontal = true
    symmetry.mirror_vertical = true
    var images := symmetry.images(Vector2(10, 20))
    assert_eq(images[1], Vector2(190, 20), "Across the vertical axis exactly as before")
    assert_eq(images[2], Vector2(10, 120), "across the horizontal one")
    assert_eq(images[3], Vector2(190, 120), "and both")

    var lines := symmetry.axes(Vector2(200, 140))
    assert_eq(lines[0], PackedVector2Array([Vector2(100, 0), Vector2(100, 140)]), "The vertical line spans the canvas")
    assert_eq(lines[1], PackedVector2Array([Vector2(0, 70), Vector2(200, 70)]), "and so does the horizontal one")
    assert_eq(
        symmetry.handles(),
        PackedVector2Array([Vector2(100, 70 - symmetry.reach), Vector2(100, 70 + symmetry.reach)]),
        "The handles stand on the upright line"
    )

    symmetry.mirror_horizontal = false
    symmetry.mirror_vertical = false
    symmetry.radial = 4
    lines = symmetry.axes(Vector2(200, 140))
    assert_eq(lines.size(), 4, "Four spokes")
    assert_true(lines[0][1].is_equal_approx(Vector2(200, 70)), "the first runs right to the edge, %s" % lines[0][1])
    assert_true(lines[1][1].is_equal_approx(Vector2(100, 140)), "the second straight down")
    assert_eq(symmetry.handles()[0], symmetry.center, "Radial alone has a handle on the centre")


func test_the_hit_test_finds_a_handle_then_a_line() -> void:
    var symmetry := SaSymmetry.new()
    symmetry.reset_axes(Vector2(SIZE))
    symmetry.mirror_horizontal = true
    var size := Vector2(SIZE)
    var ends := symmetry.handles()
    assert_eq(symmetry.hit(ends[0] + Vector2(5, 0), 8.0, 6.0, size), 0, "Near the first handle")
    assert_eq(symmetry.hit(ends[1] + Vector2(0, 3), 8.0, 6.0, size), 1, "near the second")
    assert_eq(symmetry.hit(Vector2(132, 20), 8.0, 6.0, size), SaSymmetry.HIT_LINE, "on the line away from both")
    assert_eq(symmetry.hit(Vector2(150, 20), 8.0, 6.0, size), SaSymmetry.HIT_NONE, "and off it")
    symmetry.mirror_horizontal = false
    assert_eq(symmetry.hit(Vector2(132, 20), 8.0, 6.0, size), SaSymmetry.HIT_NONE, "No line is there with the mirror off")


func test_a_drag_of_the_lower_handle_leans_the_line_and_the_stroke_follows() -> void:
    var main := _canvas_in_the_tree()
    var doc := _doc(main)
    var symmetry := doc.symmetry
    symmetry.mirror_horizontal = true
    var upper := symmetry.handles()[0]
    var lower := symmetry.handles()[1]
    var span := 2.0 * symmetry.reach
    var leaned := upper + Vector2.DOWN.rotated(deg_to_rad(-30.0)) * span

    _drag(main, lower, [lower.lerp(leaned, 0.5), leaned])
    assert_almost_eq(rad_to_deg(absf(symmetry.angle)), 30.0, 0.01, "The line leans by thirty degrees")
    assert_true(symmetry.handles()[0].is_equal_approx(upper), "about the handle that was not dragged")
    assert_true(symmetry.handles()[1].is_equal_approx(leaned), "and the dragged one is under the pointer")
    assert_false(main.get("_capturing_stroke") == true, "Nothing was painted by the drag")
    assert_true(doc.active_layer.chunks.is_empty(), "and no paint landed")
    assert_true(doc.modified, "A moved axis is a change the document has to save")

    var paint := SaPaintContext.for_region(doc, Rect2(70, 110, 10, 10), false, 0.0)
    assert_eq(paint.targets.size(), 2, "A dab on one side is two dabs")
    var dab := Vector2(75, 115)
    var mirrored := symmetry.images(dab)[1]
    var normal := symmetry.across_direction()
    assert_almost_eq(
        (mirrored - symmetry.center).dot(normal), -(dab - symmetry.center).dot(normal), 1e-3, "the second across the slanted line"
    )


func test_a_drag_on_the_line_moves_it_without_turning() -> void:
    var main := _canvas_in_the_tree()
    var symmetry := _doc(main).symmetry
    symmetry.mirror_horizontal = true
    var on_the_line := Vector2(128, 20)
    var third := float(SIZE.x) / 3.0
    _drag(main, on_the_line, [on_the_line + Vector2(third, 0.0)])
    assert_almost_eq(symmetry.center.x, 128.0 + third, 1e-3, "The axis moved a third of the way across")
    assert_almost_eq(symmetry.angle, 0.0, 0.0, "without turning")


func test_shift_snaps_the_turn_and_a_double_click_puts_the_line_back() -> void:
    var main := _canvas_in_the_tree()
    var symmetry := _doc(main).symmetry
    symmetry.mirror_horizontal = true
    var upper := symmetry.handles()[0]
    var lower := symmetry.handles()[1]
    var off_step := upper + Vector2.DOWN.rotated(deg_to_rad(-37.0)) * 2.0 * symmetry.reach
    _drag(main, lower, [off_step], true)
    assert_almost_eq(rad_to_deg(absf(symmetry.angle)), 30.0, 1e-3, "Thirty seven degrees with Shift held is thirty")

    var handle := symmetry.handles()[1]
    _press(main, handle, false)
    _release(main, handle)
    _press(main, handle, true)
    _release(main, handle)
    assert_true(symmetry.is_at_rest(Vector2(SIZE)), "A double click stands the line upright in the middle")
    assert_eq(symmetry.reach, 64.0, "with the handles a quarter of the shorter side out")


func test_the_second_mirror_and_the_spokes_follow() -> void:
    var symmetry := SaSymmetry.new()
    symmetry.reset_axes(Vector2(SIZE))
    symmetry.mirror_horizontal = true
    symmetry.mirror_vertical = true
    symmetry.move_handle(1, Vector2(180, 200), Vector2(SIZE), false)
    var lines := symmetry.axes(Vector2(SIZE))
    var first := (lines[0][1] - lines[0][0]).normalized()
    var second := (lines[1][1] - lines[1][0]).normalized()
    assert_almost_eq(first.dot(second), 0.0, 1e-4, "The second line stays at right angles")
    assert_almost_eq(
        Geometry2D.get_closest_point_to_segment(symmetry.center, lines[1][0], lines[1][1]).distance_to(symmetry.center),
        0.0,
        1e-3,
        "through the midpoint"
    )

    symmetry.mirror_horizontal = false
    symmetry.mirror_vertical = false
    symmetry.radial = 6
    symmetry.move_handle(0, Vector2(100, 90), Vector2(SIZE), false)
    var turned := symmetry.angle
    assert_eq(symmetry.center, Vector2(100, 90), "The centre handle moves the spokes")
    assert_almost_eq(symmetry.angle, turned, 0.0, "without turning them")
    symmetry.move_handle(1, Vector2(100, 190), Vector2(SIZE), false)
    assert_almost_eq(rad_to_deg(symmetry.angle), 90.0, 1e-3, "and the spoke handle turns them")
    var spoke := symmetry.axes(Vector2(SIZE))[0]
    assert_true((spoke[1] - spoke[0]).normalized().is_equal_approx(Vector2.DOWN), "the first spoke now straight down")


func test_the_eyedropper_on_a_handle_moves_it_and_picks_nothing() -> void:
    var main := _canvas_in_the_tree()
    var machine: ToolMachine = main.get("tool_machine")
    machine.set_active_tool(&"eyedropper")
    var symmetry := _doc(main).symmetry
    symmetry.mirror_horizontal = true
    EventBus.color_picked.connect(_on_picked)
    _picked.clear()
    var lower := symmetry.handles()[1]
    _drag(main, lower, [lower + Vector2(40, 0)])
    assert_false(symmetry.handles()[1].is_equal_approx(lower), "The handle moved")
    assert_eq(_picked.size(), 0, "and no colour was picked")

    machine.set_active_tool(&"marquee")
    var before := symmetry.handles()[1]
    var event := _button(main, before, true, false)
    main.call("_on_canvas_gui_input", event)
    assert_false(main.get("_axes_held") == true, "A selection tool's press is its own")
    main.call("_on_canvas_gui_input", _button(main, before, false, false))


func test_hovering_a_handle_gives_the_pointer_a_move_cursor() -> void:
    var main := _canvas_in_the_tree()
    var canvas: SaCanvas = main.get("canvas")
    var symmetry := canvas.document.symmetry
    symmetry.mirror_horizontal = true
    main.call("_on_canvas_gui_input", _motion(main, symmetry.handles()[0], false))
    assert_eq(ToolMachine.pointer_holder, MainCanvasScript.AXES_HOLDER, "Over a handle the axes hold the pointer")
    assert_eq(ToolMachine.pointer_holder_shape, Control.CURSOR_MOVE, "for a move cursor")
    assert_true(canvas.cursor_ring_radius < 0.0, "and the brush ring goes")
    main.call("_on_canvas_gui_input", _motion(main, Vector2(30, 200), false))
    assert_eq(ToolMachine.pointer_holder, &"", "Away from them the tool has it back")
    assert_true(canvas.cursor_ring_radius > 0.0, "ring and all")

    ToolMachine.pointer_holder = &"note_mode"
    main.call("_on_canvas_gui_input", _motion(main, symmetry.handles()[0], false))
    assert_eq(ToolMachine.pointer_holder, &"note_mode", "Another holder is left alone")


func test_a_press_off_the_axes_still_paints() -> void:
    var main := _canvas_in_the_tree()
    _doc(main).symmetry.mirror_horizontal = true
    var away := Vector2(30, 200)
    main.call("_on_canvas_gui_input", _button(main, away, true, false))
    assert_true(main.get("_capturing_stroke") == true, "A press away from the axes is the brush's")
    main.call("_input", _global(_button(main, away, false, false), main))


func test_the_axes_survive_a_save_and_reopen() -> void:
    var easel := SaEasel.create_default(SIZE)
    var symmetry := easel.document.symmetry
    symmetry.mirror_horizontal = true
    symmetry.radial = 6
    symmetry.move_handle(1, Vector2(200, 220), Vector2(SIZE), false)
    var saved := symmetry.to_header()
    assert_eq(SaExport.save_sad(easel.document, scratch_round_trip), OK, "Saving succeeds")

    var reopened := SaEasel.create_default(Vector2i(64, 64))
    assert_eq(SaExport.load_sad(reopened.document, scratch_round_trip), OK, "Loading succeeds")
    var back := reopened.document.symmetry
    assert_true(back.center.is_equal_approx(symmetry.center), "The centre came back")
    assert_almost_eq(back.angle, symmetry.angle, 1e-5, "the angle")
    assert_almost_eq(back.reach, symmetry.reach, 1e-3, "the reach")
    assert_true(back.mirror_horizontal and back.radial == 6 and not back.mirror_vertical, "and the switches, %s" % saved)

    easel.document.symmetry.mirror_horizontal = false
    easel.document.symmetry.radial = 0
    easel.document.symmetry.reset_axes(Vector2(SIZE))
    assert_eq(SaExport.save_sad(easel.document, scratch_at_rest), OK, "Saving the axes at rest succeeds")
    assert_false(_header_of(scratch_at_rest).has("symmetry"), "and writes no key for them")
    back.mirror_vertical = true
    assert_eq(SaExport.load_sad(reopened.document, scratch_at_rest), OK, "Loading a file without the key succeeds")
    assert_false(back.is_active(), "and reads every switch off")
    assert_true(back.is_at_rest(Vector2(SIZE)), "with the axes at rest")
    easel.free()
    reopened.free()


func test_a_canvas_resize_puts_the_turn_back_only_when_it_recentres() -> void:
    var easel := SaEasel.create_default(SIZE)
    var doc := easel.document
    doc.symmetry.angle = 0.5
    doc.canvas_size = Vector2i(512, 300)
    assert_eq(doc.symmetry.center, Vector2(256, 150), "Axes in the middle go to the new middle")
    assert_almost_eq(doc.symmetry.angle, 0.0, 0.0, "upright")
    doc.symmetry.center = Vector2(100, 100)
    doc.symmetry.angle = 0.5
    doc.canvas_size = Vector2i(400, 300)
    assert_almost_eq(doc.symmetry.angle, 0.5, 0.0, "Axes the painter moved that still fit keep their turn")
    easel.free()


## A main canvas in the tree with the built-in tools and the brush in hand, the
## way the barrel suite builds one.
func _canvas_in_the_tree() -> Node:
    _host = Node.new()
    _host.name = "AxesHost"
    var main: Node = MainCanvasScript.new()
    var canvas: SaCanvas = main.get("canvas")
    canvas.canvas_size = SIZE
    _host.add_child(main)
    EventBus.add_child(_host)
    main.call("bind_tools", Fixtures.make_tool_registry())
    var machine: ToolMachine = main.get("tool_machine")
    machine.set_active_tool(&"brush")
    return main


func _doc(main: Node) -> SaDocument:
    var canvas: SaCanvas = main.get("canvas")
    return canvas.document


## A press on *from*, a motion through each of *path* and the release at its
## end, the press through the surface's GUI and the rest through `_input` as a
## held drag arrives.
func _drag(main: Node, from: Vector2, path: Array, shift: bool = false) -> void:
    _press(main, from, false)
    var at := from
    for each: Vector2 in path:
        at = each
        main.call("_input", _global(_motion(main, at, shift), main))
    var release := _button(main, at, false, false)
    release.shift_pressed = shift
    main.call("_input", _global(release, main))


func _press(main: Node, at: Vector2, double: bool) -> void:
    main.call("_on_canvas_gui_input", _button(main, at, true, double))


func _release(main: Node, at: Vector2) -> void:
    main.call("_input", _global(_button(main, at, false, false), main))


## *document* in the surface control's own space, where gui_input hands events.
func _local(main: Node, document: Vector2) -> Vector2:
    var canvas: SaCanvas = main.get("canvas")
    return canvas.get_transform() * document


func _global(event: InputEventMouse, main: Node) -> InputEventMouse:
    var control: Control = main.get("control_node")
    return event.xformed_by(control.get_global_transform()) as InputEventMouse


func _button(main: Node, document: Vector2, pressed: bool, double: bool) -> InputEventMouseButton:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = pressed
    event.double_click = double
    event.position = _local(main, document)
    event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
    return event


func _motion(main: Node, document: Vector2, shift: bool) -> InputEventMouseMotion:
    var event := InputEventMouseMotion.new()
    event.position = _local(main, document)
    event.shift_pressed = shift
    event.button_mask = MOUSE_BUTTON_MASK_LEFT
    return event


## The header of the `.sad` at *path*, read the way the loader reads it.
func _header_of(path: String) -> Dictionary:
    var file := FileAccess.open(path, FileAccess.READ)
    file.get_buffer(4)
    file.get_32()
    var packed_size := file.get_32()
    var raw_size := file.get_32()
    var raw := file.get_buffer(packed_size).decompress(raw_size, SaSadFile.SAD_BLOB_COMPRESS)
    file.close()
    var parsed: Variant = JSON.parse_string(raw.get_string_from_utf8())
    return parsed if parsed is Dictionary else {}
