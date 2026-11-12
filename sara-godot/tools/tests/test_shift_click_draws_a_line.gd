## A Shift click draws a straight line from where the last stroke let go.
##
## Click at A, hold Shift and click at B, and Krita, Photoshop and Clip Studio
## draw a line from A to B. Sara took every Shift press with a sized tool as the
## start of a resize, swallowed the release with it, and the brush never heard
## of the click. A Shift press that never travels now draws the line through the
## brush's own press, walk and release, and one that travels still sizes the
## brush. Each case drives the machine with Shift-flagged events as the canvas
## hands them on, and reads the layer's texels and the history.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const NoiseBrushScript = preload("res://modules/sara-noise-brush-engine/state_noise_brush.gd")

## The first stroke runs from here to [constant A], where it lets go.
const START := Vector2(40.0, 60.0)
const A := Vector2(60.0, 60.0)
## Where the Shift click lands, and the middle of the line it draws.
const B := Vector2(200.0, 200.0)
const MIDDLE := Vector2(130.0, 130.0)
## Off the line and off the first stroke, where nothing may land.
const ASIDE := Vector2(200.0, 60.0)

var _surface: SaSurface = null
var _doc: SaDocument = null
var _machine: ToolMachine = null
var _said: Array[String] = []


func before_each() -> void:
    _surface = Fixtures.make_surface(Vector2i(256, 256))
    _doc = _surface.easel.document
    _machine = Fixtures.make_bound_machine(_surface)
    _machine.set_active_tool(&"brush")
    _brush().is_tablet = false
    _brush().settings.radius = 4.0 / 256.0
    # What an earlier suite left said would keep the same line from being said again.
    SaStrokeNote.say("")
    _said.clear()
    EventBus.stroke_explained.connect(_hear)


func after_each() -> void:
    if EventBus.stroke_explained.is_connected(_hear):
        EventBus.stroke_explained.disconnect(_hear)
    SaStrokeNote.say("")
    Fixtures.teardown(_surface, _machine)
    _surface = null
    _doc = null
    _machine = null


func _hear(line: String) -> void:
    _said.append(line)


func _brush() -> Object:
    return _machine.active_tool


func _button(at: Vector2, pressed: bool, shift: bool = false) -> void:
    _surface.view.mouse_position = at
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = pressed
    event.shift_pressed = shift
    event.position = at
    event.global_position = at
    _machine.handle_input(event)


func _move(at: Vector2, pressure: float = 0.0, shift: bool = false) -> void:
    _surface.view.mouse_position = at
    var event := InputEventMouseMotion.new()
    event.position = at
    event.global_position = at
    event.pressure = pressure
    event.shift_pressed = shift
    event.button_mask = MOUSE_BUTTON_MASK_LEFT
    _machine.handle_input(event)


## A plain stroke from [constant START] to [constant A], a mouse's.
func _stroke() -> void:
    _button(START, true)
    for i in range(1, 5):
        _move(START.lerp(A, i / 4.0))
    _button(A, false)


func _shift_click(at: Vector2) -> void:
    _button(at, true, true)
    _button(at, false, true)


func _steps() -> int:
    return _doc.undo_redo.get_history_count()


static func _alpha(layer: SaLayer, at: Vector2) -> float:
    var pixel := Vector2i(at)
    var grid := Vector2i(floori(float(pixel.x) / layer.CHUNK_SIZE), floori(float(pixel.y) / layer.CHUNK_SIZE))
    var chunk: SaChunk = layer.chunks.get(grid)
    if chunk == null:
        return 0.0
    var texture := chunk.albedo()
    @warning_ignore("integer_division")
    var local := (pixel - grid * layer.CHUNK_SIZE) * chunk.pixel_size() / layer.CHUNK_SIZE
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    return SaFieldSpec.decode_texel(bytes, texture.format, local.y * texture.size.x + local.x).a


## The check the row is done on: a line joins A and B, and one undo takes it.
func test_a_shift_click_draws_a_line_from_the_last_stroke() -> void:
    _stroke()
    var layer := _doc.active_layer
    var before := _steps()
    assert_eq(_alpha(layer, MIDDLE), 0.0, "Nothing is between A and B before the click")
    _shift_click(B)
    assert_eq(_steps(), before + 1, "The line is one step")
    assert_true(_alpha(layer, MIDDLE) > 0.5, "and paints the middle of A to B, %f" % _alpha(layer, MIDDLE))
    assert_true(_alpha(layer, B) > 0.5, "and B itself")
    assert_eq(_alpha(layer, ASIDE), 0.0, "and nothing off the line")
    assert_false(_brush().is_drawing, "The line's stroke is closed")
    assert_true(_doc.undo(), "One undo")
    assert_eq(_alpha(layer, MIDDLE), 0.0, "takes the line away")
    assert_true(_alpha(layer, START.lerp(A, 0.5)) > 0.5, "and leaves the first stroke")


## A second Shift click carries on from the first's end, so clicks draw a path.
func test_a_second_shift_click_starts_where_the_first_line_ended() -> void:
    _stroke()
    _shift_click(B)
    _shift_click(Vector2(200.0, 120.0))
    assert_true(_alpha(_doc.active_layer, Vector2(200.0, 160.0)) > 0.5, "The second line runs down from B")


## Shift click as the first mark on a layer paints nothing and says why.
func test_a_first_shift_click_paints_nothing_and_says_why() -> void:
    var before := _steps()
    _shift_click(B)
    assert_eq(_steps(), before, "No step")
    assert_true(_doc.active_layer.chunks.is_empty(), "and no paint")
    assert_eq(_said, [tr(SaShiftPress.NO_STROKE_YET)] as Array[String], "and the status line says why")


## A stroke on one layer draws no line on another.
func test_another_layer_has_no_line_to_draw_from() -> void:
    _stroke()
    var upper := SaLayerOps.new(_doc).add()
    assert_eq(_doc.active_layer, upper, "The new layer is the one painted")
    var before := _steps()
    _shift_click(B)
    assert_eq(_steps(), before, "No line from the layer below")
    assert_true(upper.chunks.is_empty(), "and no paint")
    assert_eq(_said, [tr(SaShiftPress.NO_STROKE_YET)] as Array[String], "and the status line says why")


## Shift drag still resizes the radius and paints nothing.
func test_a_shift_drag_still_sizes_the_brush_and_paints_nothing() -> void:
    _stroke()
    var radius: float = _brush().settings.radius
    var before := _steps()
    _button(B, true, true)
    _move(B + Vector2(40.0, 0.0), 0.0, true)
    _button(B + Vector2(40.0, 0.0), false, true)
    _machine.tell_moved_size()
    assert_true(_brush().settings.radius > radius, "The drag grew the radius")
    assert_eq(_steps(), before, "and drew nothing")
    assert_eq(_alpha(_doc.active_layer, MIDDLE), 0.0, "no line either")


## A pen that slips a pixel as it lands is still clicking, and its size holds.
func test_a_click_that_slips_a_pixel_is_a_click() -> void:
    _stroke()
    var radius: float = _brush().settings.radius
    _button(B, true, true)
    _move(B + Vector2(2.0, 0.0), 0.0, true)
    _button(B + Vector2(2.0, 0.0), false, true)
    assert_eq(_brush().settings.radius, radius, "The slip sized nothing")
    assert_true(_alpha(_doc.active_layer, MIDDLE) > 0.5, "and the line is drawn")


## The click's press and release leave the brush free, so the next plain
## stroke paints as ever.
func test_the_next_stroke_paints_after_a_shift_click() -> void:
    _stroke()
    _shift_click(B)
    assert_false(_machine.block_brush_until_release, "No block is left standing")
    var before := _steps()
    _button(Vector2(30.0, 200.0), true)
    _move(Vector2(40.0, 200.0))
    _button(Vector2(40.0, 200.0), false)
    assert_eq(_steps(), before + 1, "The next stroke is a step")
    assert_true(_alpha(_doc.active_layer, Vector2(35.0, 200.0)) > 0.5, "and paints")


## A mouse's line is walked at full pressure and leaves the brush a mouse's.
func test_a_mouse_line_leaves_the_brush_reading_a_mouse() -> void:
    _stroke()
    _shift_click(B)
    assert_false(_brush().is_tablet, "The line's motion did not pass for a pen")


## A pen's line is walked at the pressure the click pressed with.
func test_a_pen_line_takes_the_clicks_pressure() -> void:
    _brush().is_tablet = true
    _brush().settings.opacity_by_pressure = true
    _stroke_with_pen(0.9)
    _button(B, true, true)
    _move(B, 0.3, true)
    _button(B, false, true)
    var dab: SaDabParams = _brush().last_dab
    assert_not_null(dab, "The line laid dabs")
    assert_true(dab.opacity < 0.6, "at the click's light pressure, %f" % dab.opacity)
    assert_true(_alpha(_doc.active_layer, MIDDLE) > 0.0, "along the line")


## Under Wayland a pen's touch is reported before its press, and a tap that
## sends nothing after it draws its line at that report's pressure.
func test_a_pen_tap_reported_before_its_press_draws_at_that_pressure() -> void:
    _brush().is_tablet = true
    _stroke_with_pen(0.9)
    var touch := InputEventMouseMotion.new()
    touch.pressure = 0.7
    touch.tilt = Vector2(0.1, 0.0)
    touch.global_position = B
    _surface.view.mouse_position = B
    _machine.handle_input(touch)
    _shift_click(B)
    assert_true(_alpha(_doc.active_layer, MIDDLE) > 0.5, "The tap's line is drawn")


## A pen that touched and lifted between two reports, which Windows Ink can
## send, said no pressure, and the line is walked at full rather than at none.
## Asked of the gesture alone, because under Wayland the machine holds such a
## press back as the upper barrel's.
func test_a_pen_tap_with_no_report_is_walked_at_full_pressure() -> void:
    var gesture := SaShiftPress.new()
    var hover := InputEventMouseMotion.new()
    hover.tilt = Vector2(0.1, 0.0)
    gesture.take(hover, _machine)
    assert_eq(gesture._line_motion().pressure, 1.0, "A pen's hover becomes a full press")
    gesture.take(InputEventMouseMotion.new(), _machine)
    assert_eq(gesture._line_motion().pressure, 0.0, "and a mouse's stays a mouse's")


func _stroke_with_pen(pressure: float) -> void:
    _button(START, true)
    for i in range(1, 5):
        _move(START.lerp(A, i / 4.0), pressure)
    _button(A, false)


## With Mirror H on, the line is mirrored. The point read is far enough from
## the axis that the line itself cannot reach its mirror.
func test_with_symmetry_h_the_line_is_mirrored() -> void:
    _doc.symmetry.center = Vector2(128.0, 128.0)
    _doc.symmetry.mirror_horizontal = true
    _stroke()
    _shift_click(B)
    var on_line := Vector2(180.0, 180.0)
    var mirrored := Vector2(256.0 - on_line.x, on_line.y)
    assert_true(_alpha(_doc.active_layer, on_line) > 0.5, "The line is drawn")
    assert_true(_alpha(_doc.active_layer, mirrored) > 0.5, "and its mirror image, %f" % _alpha(_doc.active_layer, mirrored))


## The noise engine draws the line with no code of its own, through the door.
func test_the_noise_brush_draws_a_line_through_the_door() -> void:
    var noise: ToolState = NoiseBrushScript.new()
    noise.surface = _surface
    noise.stroke_seed = 7
    noise.settings.radius = 4.0 / 256.0
    # A first stroke with a thickness gives the layer its height as a step of its own.
    noise.settings.thickness = 0.0
    var before := _steps()
    noise.straight_line_to(A, B, InputEventMouseMotion.new())
    assert_eq(_steps(), before + 1, "The noise line is one step")
    assert_true(_alpha(_doc.active_layer, MIDDLE) > 0.0, "and paints the middle of A to B")
    assert_eq(_alpha(_doc.active_layer, ASIDE), 0.0, "and nothing off it")
    assert_eq(noise.get_document_mouse_position(), Vector2.ZERO, "The pointer reads the view again once the line is done")


## A preset's picture is painted by the brush, and its strokes on their own
## document leave the status line saying what the painter was told. The eraser's
## said "Erase is on" over it, and a brush's cleared it within the frame.
func test_a_presets_picture_leaves_the_line_the_painter_was_told() -> void:
    _shift_click(B)
    for id: StringName in [&"eraser", &"brush"]:
        var tool := _machine.get_tool(id)
        var picture := SaPresetThumbs._paint(tool.get_script(), tool.get("settings"), Vector2i(64, 64), false)
        assert_not_null(picture, "%s: the picture is drawn" % id)
        assert_eq(_said[-1], tr(SaShiftPress.NO_STROKE_YET), "%s: and the status line says what it said" % id)
