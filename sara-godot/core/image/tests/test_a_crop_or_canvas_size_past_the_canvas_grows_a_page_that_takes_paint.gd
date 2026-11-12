## A Crop tool box dragged past the canvas in Canvas mode grows the document,
## the new area holds the ground, and a stroke there lays paint. Image > Canvas
## Size growing the document takes paint in its margin the same way.
##
## The box is drawn by the tool's own input, a press, a motion and a release on
## a suite's view, and Enter crops, so the grow is met where a painter meets it
## and not by calling `SaCrop` past the tool. The strokes go through the brush
## tool as `test_the_page_grows_by_whole_chunks_under_a_stroke.gd` draws
## its own.
extends "res://tests/test_framework.gd"

## The strokes dispatch real dabs and the crop allocates real chunks.
const REQUIRES_GPU := true

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")
const Fixtures = preload("res://tests/fixtures.gd")

## A painter's case, a 1024 by 1024 page and a box 300 pixels past two edges.
const CANVAS := Vector2i(1024, 1024)
const PAST := 300
const GROWN := Vector2i(1324, 1324)
const STEP := 16.0
const RADIUS := 12.0

var _surface: SaSurface
var _machine: ToolMachine
var _doc: SaDocument


func before_each() -> void:
    SaProblems.pending_refusals = PackedStringArray()
    _surface = Fixtures.make_surface(CANVAS)
    _machine = Fixtures.make_bound_machine(_surface)
    _doc = _surface.easel.document


func after_each() -> void:
    Fixtures.teardown(_surface, _machine)
    _surface = null
    _machine = null
    _doc = null


func _point(at: Vector2) -> void:
    (_surface.view as Fixtures.FakeView).mouse_position = at


static func _button(pressed: bool) -> InputEventMouseButton:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = pressed
    return event


static func _motion() -> InputEventMouseMotion:
    var event := InputEventMouseMotion.new()
    event.pressure = 1.0
    return event


## The Crop tool in its default mode, with the skeleton's engines a bare machine
## does not hand it, a box drawn from *from* to *to* and Enter. *mode* is the
## tool's Crop row, -1 for the default the painter meets.
##
## A box that reaches past the canvas is drawn from its far corner, because
## now a press on the canvas's corner grabs the handle of the box the
## tool stands on there.
func _crop(from: Vector2, to: Vector2, mode: int = -1) -> void:
    _machine.set_active_tool(&"crop")
    var tool: Object = _machine.active_tool
    tool.roles = Fixtures.make_registries().roles
    if mode >= 0:
        tool.mode = mode
    _point(from)
    tool.handle_input(_button(true))
    _point(to)
    tool.handle_input(_motion())
    tool.handle_input(_button(false))
    var enter := InputEventKey.new()
    enter.keycode = KEY_ENTER
    enter.pressed = true
    tool.handle_input(enter)


## A stroke of the brush from *from* to *to*, in document pixels, on the active
## layer.
func _stroke(from: Vector2, to: Vector2) -> void:
    _machine.set_active_tool(&"brush")
    var brush: Object = _machine.active_tool
    brush.is_tablet = false
    brush.settings.stabilizer_amount = 0.0
    brush.settings.radius = RADIUS / float(_doc.canvas_size.y)
    brush.settings.color = Color(0.1, 0.25, 0.8, 1.0)
    _point(from)
    brush.handle_input(_button(true))
    var steps := ceili(from.distance_to(to) / STEP)
    for index in range(1, steps + 1):
        _point(from.lerp(to, float(index) / float(steps)))
        brush.handle_input(_motion())
    brush.handle_input(_button(false))


## What *layer* holds at *at* in document pixels, nothing where it holds no
## chunk there.
static func _at(layer: SaLayer, at: Vector2i) -> Color:
    var side := SaLayer.CHUNK_SIZE
    var grid_pos := Vector2i(floori(float(at.x) / side), floori(float(at.y) / side))
    var texture := layer.get_field(grid_pos, SaFieldSpec.ALBEDO)
    if texture == null:
        return Color(0, 0, 0, 0)
    return Bench.texel(texture, at - grid_pos * side)


## The bottom layer, the one a default document keeps its ground in.
func _ground_layer() -> SaLayer:
    for child: Node in _doc.get_children():
        var layer := child as SaLayer
        if layer != null and layer != _doc.stroke_layer:
            return layer
    return null


## A fresh paint layer above the ground, active, for the stroke to land on.
func _paint_layer() -> SaLayer:
    var layer := SaLayerOps.new(_doc).add()
    _doc.set_active_layer(layer)
    return layer


func _assert_ground(at: Vector2i, said: String) -> void:
    var held := _at(_ground_layer(), at)
    var ground := _doc.background_fill()
    assert_true(held.is_equal_approx(ground), "%s: %s against the ground %s" % [said, held, ground])


func _assert_paint(layer: SaLayer, at: Vector2i, said: String) -> void:
    var held := _at(layer, at)
    assert_true(held.a > 0.5, "%s: %s" % [said, held])


func test_a_box_past_the_right_and_bottom_grows_the_page_and_a_stroke_paints_the_new_area() -> void:
    _crop(Vector2(GROWN), Vector2.ZERO)
    assert_eq(_doc.canvas_size, GROWN, "The box past the right and bottom edges grows the page to it")
    _assert_ground(Vector2i(1200, 1200), "The corner the crop added holds the ground")
    _assert_ground(Vector2i(1100, 600), "and so does the band down the right")
    var layer := _paint_layer()
    _stroke(Vector2(900, 1200), Vector2(1300, 1200))
    _assert_paint(layer, Vector2i(1200, 1200), "The stroke lands in the new area")
    _assert_paint(layer, Vector2i(1290, 1200), "and reaches near the new edge")
    _assert_paint(layer, Vector2i(950, 1200), "and is whole where it crossed the old edge's column")


func test_a_box_past_the_left_and_top_grows_the_page_one_undo_gives_it_back_and_a_stroke_paints_there() -> void:
    _crop(Vector2(-PAST, -PAST), Vector2(CANVAS))
    assert_eq(_doc.canvas_size, GROWN, "The box past the left and top edges grows the page to it")
    _assert_ground(Vector2i(100, 100), "The corner the crop added holds the ground")
    assert_true(_doc.undo(), "One undo")
    assert_eq(_doc.canvas_size, CANVAS, "gives back the old size")
    assert_true(_doc.redo(), "and a redo grows it again")
    assert_eq(_doc.canvas_size, GROWN, "to the box")
    var layer := _paint_layer()
    _stroke(Vector2(50, 150), Vector2(400, 150))
    _assert_paint(layer, Vector2i(150, 150), "The stroke lands in the new area at its place")
    _assert_paint(layer, Vector2i(350, 150), "and on the old picture past the old edge")


func test_canvas_size_growing_the_page_takes_paint_in_its_margin() -> void:
    assert_true(SaCrop.new(_doc).resize_to(GROWN, Vector2i.ZERO), "Canvas Size grows the page with the picture at the top left")
    assert_eq(_doc.canvas_size, GROWN, "to the size asked")
    _assert_ground(Vector2i(1200, 1200), "The margin holds the ground")
    var layer := _paint_layer()
    _stroke(Vector2(900, 1200), Vector2(1300, 1200))
    _assert_paint(layer, Vector2i(1200, 1200), "A stroke in the margin lands")


func test_a_box_a_strip_past_the_edge_grows_the_page_inside_the_chunk_it_already_had() -> void:
    var strip := Vector2i(CANVAS.x + 30, CANVAS.y)
    _crop(Vector2(strip), Vector2.ZERO)
    assert_eq(_doc.canvas_size, strip, "A box 30 pixels past the right edge grows the page by 30")
    _assert_ground(Vector2i(1040, 500), "The strip the crop added holds the ground")
    var layer := _paint_layer()
    _stroke(Vector2(1000, 500), Vector2(1050, 500))
    _assert_paint(layer, Vector2i(1040, 500), "and a stroke lays paint in it")


func test_the_layer_that_was_painted_before_the_crop_takes_paint_in_the_new_area() -> void:
    var layer := _paint_layer()
    _stroke(Vector2(500, 500), Vector2(800, 500))
    _crop(Vector2(GROWN), Vector2.ZERO)
    assert_eq(_doc.canvas_size, GROWN, "The box past the right and bottom edges grows the page")
    _assert_paint(layer, Vector2i(700, 500), "The layer keeps the paint it had")
    _stroke(Vector2(900, 1200), Vector2(1300, 1200))
    _assert_paint(layer, Vector2i(1200, 1200), "and takes a stroke in the area the crop added")


## The id of the tool's Crop row named *called*, read off the tool's own enum
## so the number is not written here a second time.
func _mode(called: StringName) -> int:
    _machine.set_active_tool(&"crop")
    var constants: Dictionary = _machine.active_tool.get_script().get_script_constant_map()
    return int((constants["Mode"] as Dictionary)[called])


## Layer, the choice every crop was before the Crop row was built, which is
## what a painter's own Sara did to a box past the canvas: it crops the layer
## and the page stays the size it was, so no new area is there to paint in.
func test_the_crop_rows_layer_choice_leaves_the_page_as_it_was() -> void:
    var layer := _paint_layer()
    _stroke(Vector2(500, 500), Vector2(800, 500))
    _crop(Vector2(GROWN), Vector2.ZERO, _mode(&"LAYER"))
    assert_eq(_doc.canvas_size, CANVAS, "Layer crops the layer alone and leaves the page as it was")
    _assert_paint(layer, Vector2i(700, 500), "with the paint it had still on it")
