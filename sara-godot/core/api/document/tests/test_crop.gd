## Cropping the document, read back texel by texel.
##
## The claim is that paint sits at the new origin afterwards
## and that undo restores the size, so the sample at a known point is taken
## before and after and again after the undo. The rest are the ways the
## re-tiling could be wrong quietly: an origin that is not a multiple of the
## chunk edge, a chunk wholly outside the rectangle, and a selection whose
## bounds the Image menu crops to.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true
const Fixtures = preload("res://tests/fixtures.gd")

var _easel: SaEasel = null
var _doc: SaDocument = null
var _crop: SaCrop = null


func before_each() -> void:
    _easel = SaEasel.create_default(Vector2i(1024, 768))
    _doc = _easel.document
    _crop = SaCrop.new(_doc)


func after_each() -> void:
    _crop = null
    _easel.free()
    _easel = null
    _doc = null


func _texel(x: int, y: int) -> Color:
    return _texel_of(_doc.active_layer, x, y)


## The same read on a named layer, because the ground a grow lays down goes to
## the background rather than to the layer the brush is on.
func _texel_of(layer: SaLayer, x: int, y: int) -> Color:
    @warning_ignore("integer_division")
    var grid := Vector2i(x / SaChunk.SIZE, y / SaChunk.SIZE)
    var texture := layer.get_field(grid)
    if texture == null:
        return Color.TRANSPARENT
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    return SaFieldSpec.decode_texel(
        bytes, texture.format, (y - grid.y * SaChunk.SIZE) * texture.size.x + (x - grid.x * SaChunk.SIZE)
    )


## Paints a small square a colour nothing else is, so a sample can say where
## it ended up. Through the selection and a fill, because that is the door a
## painter would use and `texture_update` writes a whole texture or nothing.
func _mark(at: Vector2i, color: Color) -> void:
    _doc.selection.select_rect(Rect2i(at, Vector2i(8, 8)))
    _doc.fill_layer(color)
    _doc.selection.deselect()


## The case that matters. The crop starts at (300, 200), which is inside a
## chunk rather than on its edge, so every texel moves within its tile as well
## as between tiles.
func test_the_paint_sits_at_the_new_origin() -> void:
    _doc.active_layer.fill(Color(0.2, 0.2, 0.2, 1.0))
    _mark(Vector2i(497, 397), Color(1.0, 0.0, 0.5, 1.0))
    assert_almost_eq(_texel(500, 400).r, 1.0, 1e-4, "The mark is where it was put")

    assert_true(_crop.crop_to(Rect2i(300, 200, 400, 300)), "The crop happens")
    assert_eq(_doc.canvas_size, Vector2i(400, 300), "and the document is the rectangle")

    var moved := _texel(200, 200)
    assert_almost_eq(moved.r, 1.0, 1e-4, "The mark moved to the new origin")
    assert_almost_eq(moved.g, 0.0, 1e-4, "whole")
    assert_almost_eq(moved.b, 0.5, 1e-4, "and unchanged")
    assert_almost_eq(_texel(190, 200).r, 0.2, 1e-4, "and the fill around it came across too")


## Undo puts the size and the released chunks back together, because either
## alone is a document that disagrees with itself.
func test_undo_restores_the_size_and_the_paint() -> void:
    _doc.active_layer.fill(Color(0.2, 0.2, 0.2, 1.0))
    _mark(Vector2i(897, 697), Color(0.0, 1.0, 0.25, 1.0))
    var steps := _doc.history.step_count()

    assert_true(_crop.crop_to(Rect2i(0, 0, 300, 300)), "A crop that throws that corner away")
    assert_eq(_doc.history.step_count(), steps + 1, "is one step")
    assert_eq(_doc.canvas_size, Vector2i(300, 300), "and the document is smaller")

    assert_true(_doc.undo(), "which undoes")
    assert_eq(_doc.canvas_size, Vector2i(1024, 768), "restoring the size")
    assert_almost_eq(_texel(900, 700).g, 1.0, 1e-4, "and the paint the crop released")


## A rectangle reaching past two edges grows the document instead of being
## clipped back to it, because the tool commits what the hand dragged. The
## ground the canvas gains is the document's own background, which is the background's
## rule, and undo takes both the size and the ground away again.
func test_a_rectangle_past_two_edges_grows_the_document() -> void:
    var background: SaLayer = _doc.get_child(0)
    _doc.active_layer.fill(Color(0.2, 0.2, 0.2, 1.0))
    _mark(Vector2i(97, 97), Color(1.0, 0.0, 0.5, 1.0))
    var steps := _doc.history.step_count()

    assert_true(_crop.crop_to(Rect2i(-200, -100, 1424, 968)), "A rectangle off the top and the left commits")
    assert_eq(_doc.canvas_size, Vector2i(1424, 968), "and the canvas is the rectangle, larger than it was")
    assert_eq(_doc.history.step_count(), steps + 1, "as one step")
    assert_almost_eq(_texel(300, 200).r, 1.0, 1e-4, "The old picture moved with the origin")

    var ground := _doc.background_fill()
    var gained := _texel_of(background, 20, 20)
    assert_almost_eq(gained.a, 1.0, 1e-4, "The ground the canvas gained is opaque")
    assert_almost_eq(gained.r, ground.r, 1e-3, "and it is the document's background rather than transparency")
    assert_true(background.chunks.has(Vector2i(0, 0)), "with a chunk along the grown edge")
    assert_true(background.chunks.has(Vector2i(5, 3)), "and one at the far corner the grow reached")

    assert_true(_doc.undo(), "The one step undoes")
    assert_eq(_doc.canvas_size, Vector2i(1024, 768), "and the canvas is what it was")


## Image > Crop to Selection clips where the tool grows, because a menu entry
## that quietly made the document bigger would be a different operation under
## the same name.
func test_crop_to_selection_still_clips_to_the_canvas() -> void:
    _doc.active_layer.fill(Color(0.2, 0.2, 0.2, 1.0))
    _doc.selection.select_rect(Rect2i(-100, -100, 400, 400))
    assert_true(_crop.crop_to_selection(), "A selection reaching off the canvas crops")
    assert_eq(_doc.canvas_size, Vector2i(300, 300), "to the part of it that was on the canvas")


## A chunk the rectangle does not reach is not carried over, so a crop is also
## the moment a document stops paying for paint nobody can see (hard rule 3).
func test_a_chunk_outside_the_rectangle_is_released() -> void:
    _doc.active_layer.fill(Color(0.2, 0.2, 0.2, 1.0))
    var held := _doc.active_layer.chunks.size()
    assert_true(held > 4, "The fill allocated the grid")

    assert_true(_crop.crop_to(Rect2i(0, 0, 256, 256)), "A crop to one chunk")
    assert_eq(_doc.active_layer.chunks.size(), 1, "leaves one chunk")


## Image > Crop to Selection is the same pass reading the selection's bounds,
## and the selection goes with it because its chunks are in the old
## coordinates.
func test_crop_to_selection_uses_the_bounds_and_drops_the_selection() -> void:
    _doc.active_layer.fill(Color(0.2, 0.2, 0.2, 1.0))
    assert_false(_crop.crop_to_selection(), "With no selection there is nothing to crop to")

    _doc.selection.select_rect(Rect2i(100, 100, 500, 400))
    assert_true(_crop.crop_to_selection(), "and with one the crop happens")
    assert_eq(_doc.canvas_size, Vector2i(500, 400), "at the selection's bounds")
    assert_false(_doc.selection.active, "The selection is dropped rather than left pointing elsewhere")


## A crop to the whole canvas changes nothing, and must not put a step on the
## stack that does nothing when it fires.
func test_a_crop_that_changes_nothing_records_nothing() -> void:
    _doc.active_layer.fill(Color(0.2, 0.2, 0.2, 1.0))
    var steps := _doc.history.step_count()
    assert_false(_crop.crop_to(Rect2i(Vector2i.ZERO, _doc.canvas_size)), "The whole canvas is not a crop")
    assert_false(_crop.crop_to(Rect2i(-50, -50, 0, 0)), "and neither is a rectangle with no area")
    assert_eq(_doc.history.step_count(), steps, "so nothing is recorded")


## The gestures the tool offers, run headless through a bound machine the way
## the selection tools' suite runs the marquee's.
##
## A drag draws the rectangle, a press on a corner pulls it, a press inside
## moves the whole thing, and Escape drops it.
func test_the_rectangle_is_drawn_pulled_and_moved() -> void:
    var surface := Fixtures.make_surface(Vector2i(512, 512))
    var machine := Fixtures.make_bound_machine(surface)
    machine.set_active_tool(&"crop")
    var tool := machine.active_tool
    var view := surface.view

    view.mouse_position = Vector2(100, 100)
    tool.handle_input(_button(true))
    view.mouse_position = Vector2(300, 200)
    tool.handle_input(InputEventMouseMotion.new())
    assert_eq(tool.preview_shape().get("rect"), Rect2(100, 100, 200, 100), "A drag draws the rectangle")
    assert_true(tool.preview_shape().get("handles", false), "and asks the overlay for handles")
    tool.handle_input(_button(false))
    assert_eq(tool.pending_rect(), Rect2i(100, 100, 200, 100), "which stays after the release")

    view.mouse_position = Vector2(300, 200)
    tool.handle_input(_button(true))
    view.mouse_position = Vector2(260, 180)
    tool.handle_input(InputEventMouseMotion.new())
    tool.handle_input(_button(false))
    assert_eq(tool.pending_rect(), Rect2i(100, 100, 160, 80), "The bottom right handle pulls that corner")

    view.mouse_position = Vector2(150, 150)
    tool.handle_input(_button(true))
    view.mouse_position = Vector2(170, 140)
    tool.handle_input(InputEventMouseMotion.new())
    tool.handle_input(_button(false))
    assert_eq(tool.pending_rect(), Rect2i(120, 90, 160, 80), "A press inside moves the whole rectangle")

    tool.handle_input(_key(KEY_ESCAPE))
    assert_eq(tool.pending_rect(), Rect2i(0, 0, 512, 512), "and Escape drops it, the box back on the canvas")
    Fixtures.teardown(surface, machine)


static func _button(pressed: bool) -> InputEventMouseButton:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = pressed
    return event


static func _key(keycode: Key) -> InputEventKey:
    var event := InputEventKey.new()
    event.keycode = keycode
    event.pressed = true
    return event
