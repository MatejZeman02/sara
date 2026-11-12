## Regressions found by driving the selection tools and everything
## that reads a selection through `scenarios/selection.json`,
## `scenarios/transform.json` and `scenarios/crop-fill.json`.
##
## **A `pending_` method is a regression waiting for its fix.** The framework
## runs `test_*` and nothing else, so a method named `pending_*` is written,
## committed and not run. It asserts the behaviour the fix is going to make true, and the fix renames it to
## `test_*` in the same commit. A failing assertion committed makes the gate red for everyone, and
## a deleted assertion is one nobody writes twice. Same shape as
## `tests/flakes.txt`, a list rather than a deletion.
##
## The `test_*` methods below are the half of what the drive found that already holds.
## They are here so the file proves it runs, and so a fix renaming a
## `pending_` has a working fixture beside it rather than a file of skips.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true
const Fixtures = preload("res://tests/fixtures.gd")

const ORANGE := Color(0.91, 0.70, 0.24, 1.0)


func _document(size: Vector2i = Vector2i(1024, 1024)) -> Array:
    var easel := SaEasel.create_default(size)
    return [easel, easel.document]


func _texel(texture: SaTexture, x: int, y: int) -> Color:
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    return SaFieldSpec.decode_texel(bytes, texture.format, y * texture.size.x + x)


# ---------------------------------------------------------------------------
# What holds
# ---------------------------------------------------------------------------


## The shapes land where the drag said, which is what
## `selection.json` grades through `transform.target_box` in its dumps
## 03, 06, 07 and 08.
func test_every_shape_puts_its_own_bounds_on_the_selection() -> void:
    var built := _document()
    var easel: SaEasel = built[0]
    var document: SaDocument = built[1]

    document.selection.select_rect(Rect2i(400, 400, 400, 200))
    assert_eq(document.selection.bounds, Rect2i(400, 400, 400, 200), "A rectangle is its own bounds")

    document.selection.select_ellipse(Rect2i(500, 600, 400, 250))
    assert_eq(document.selection.bounds, Rect2i(500, 600, 400, 250), "and an ellipse is the box it is inscribed in")

    var points := PackedVector2Array([Vector2(400, 596), Vector2(800, 596), Vector2(700, 916)])
    document.selection.select_polygon(points)
    assert_eq(document.selection.bounds, Rect2i(400, 596, 400, 320), "and a polygon is the box round its points")

    easel.free()


## Add grows the bounds by the union. The half of the mode pair that works,
## kept beside `pending_a_subtract_shrinks_the_bounds` so the two read together.
func test_add_grows_the_bounds_by_the_union() -> void:
    var built := _document()
    var easel: SaEasel = built[0]
    var document: SaDocument = built[1]

    document.selection.select_rect(Rect2i(400, 400, 400, 200))
    document.selection.select_rect(Rect2i(900, 640, 300, 120), SaSelection.Mode.ADD)

    assert_eq(document.selection.bounds, Rect2i(400, 400, 800, 360), "Two rectangles give the box round both")
    easel.free()


## Feather and Border reach outside the shape, and the bounds follows them.
## `selection.json` dumps 12 and 13 read 24 and 12 pixels of growth per side.
func test_feather_and_border_carry_the_bounds_outwards() -> void:
    var built := _document()
    var easel: SaEasel = built[0]
    var document: SaDocument = built[1]

    document.selection.select_rect(Rect2i(400, 400, 500, 400))
    SaSelectionFilters.feather(document.selection, 24, document.canvas_size)
    assert_eq(document.selection.bounds, Rect2i(376, 376, 548, 448), "A feather of 24 reaches 24 out on every side")

    document.selection.select_rect(Rect2i(400, 400, 500, 400))
    SaSelectionFilters.border(document.selection, 12, document.canvas_size)
    assert_eq(document.selection.bounds, Rect2i(388, 388, 524, 424), "and a border of 12 reaches 12")

    easel.free()


## Crop to Selection takes the selection's bounds as the new canvas, which
## `crop-fill.json` grades on `document.canvas_size` either side of the
## Image menu item.
func test_crop_to_selection_takes_the_bounds_as_the_canvas() -> void:
    var built := _document(Vector2i(1600, 900))
    var easel: SaEasel = built[0]
    var document: SaDocument = built[1]

    document.active_layer.get_or_create_chunk(Vector2i(1, 1)).clear(ORANGE)
    document.selection.select_rect(Rect2i(300, 200, 600, 400))
    SaCrop.new(document).crop_to(document.selection.bounds)

    assert_eq(document.canvas_size, Vector2i(600, 400), "The canvas is the selection, to the pixel")
    easel.free()


# ---------------------------------------------------------------------------
# The regressions, waiting for their F units
# ---------------------------------------------------------------------------


## `SaSelection` keeps a coverage box per chunk and `bounds` is their
## union, so a strip taken off the top of one chunk's coverage lifts the total
## without touching the chunk beside it. Before that fix `_select_shape` merged
## the shape's box into `bounds` in every mode but SUBTRACT, and nothing ever
## recomputed it downwards, so a subtract that takes a whole strip off the top
## left the bounds where it was. What
## reads `bounds` reads the wrong rectangle: the transform tool's box is drawn
## round it, and `selection.json`'s dump 05 has it 105 pixels too tall while
## `05-subtract-shrinks-the-mask.png` shows the mask itself is right.
func test_a_subtract_shrinks_the_bounds() -> void:
    var built := _document()
    var easel: SaEasel = built[0]
    var document: SaDocument = built[1]

    document.selection.select_rect(Rect2i(400, 400, 400, 200))
    document.selection.select_rect(Rect2i(900, 640, 300, 120), SaSelection.Mode.ADD)
    document.selection.select_rect(Rect2i(380, 390, 440, 115), SaSelection.Mode.SUBTRACT)

    assert_eq(
        document.selection.bounds,
        Rect2i(400, 505, 800, 255),
        "Taking the top strip off the first rectangle lifts the bounds' top edge with it"
    )
    easel.free()


## The other half. The quick mask paints coverage straight into the
## selection's chunks, so `get_or_create_chunk` claims the whole chunk it hands
## out: the selection is never told where inside it a dab landed, and a
## chunk-aligned over-estimate is the only honest answer. Before that fix no
## writer of `bounds` was on the path at all, so coverage painted well outside
## the bounds was invisible to everything that reads it. `16-quick-mask-off.png`
## shows ants round a brush path the dump's `transform.target_box` in
## `16-quick-mask-off.json` does not reach.
func test_painting_the_quick_mask_carries_the_bounds_with_it() -> void:
    var built := _document()
    var easel: SaEasel = built[0]
    var document: SaDocument = built[1]

    document.selection.select_rect(Rect2i(400, 400, 500, 400))
    document.selection.editing = true
    document.selection.get_or_create_chunk(Vector2i(3, 2)).clear(Color(1.0, 1.0, 1.0, 1.0))

    assert_true(
        document.selection.bounds.encloses(Rect2i(768, 512, 256, 256)),
        "A chunk painted in the quick mask is inside the bounds afterwards"
    )
    easel.free()


## Growing the canvas used to leave the new margin transparent, because a
## default document's Background is a layer of stored pixels rather than a
## generated one, so it covers the rectangle it was made at and nothing more.
## `SaCrop` lays the ground into every destination chunk before it copies the
## old picture over, so the margin comes back opaque and the chunks straddling
## the old edge come back whole.
func test_growing_the_canvas_carries_the_background_with_it() -> void:
    var built := _document(Vector2i(1024, 768))
    var easel: SaEasel = built[0]
    var document: SaDocument = built[1]

    SaCrop.new(document).resize_to(Vector2i(1400, 1000), Vector2i(1, 1))
    assert_eq(document.canvas_size, Vector2i(1400, 1000), "The canvas grew")
    easel.request_full_composite()
    easel.process_pending_composite()

    var margin := _texel(easel.output, 40, 40)
    assert_almost_eq(margin.a, 1.0, 0.01, "and a texel in the new margin is opaque background rather than nothing")
    easel.free()


## The rows follow the tool when the tool moves under them.
##
## They were one-way: `ToolOptionControls.sync` ran on `EventBus.tool_changed`
## and nowhere else, so a handle drag moved the matrix and the rows kept the
## numbers they were built with. `07-scaled-by-a-corner.json` had
## `transform.scale` at (1.40, 1.29) beside a row reading `Width: 100 %`. The
## getters were always right, which `test_transform_rows.gd` proves, so what
## went in was the announcement: `EventBus.tool_options_moved`, emitted whenever
## the matrix actually moves and answered by the docker re-reading its values.
##
## **The move here is a write to one row, not a handle drag**, and that is not a
## weaker test of the same thing by accident. `ToolState.get_document_mouse_position`
## asks the view for the real pointer, so a synthetic `InputEventMouseMotion`
## handed to `handle_input` presses at (0, 0) whatever position it carries: the
## press lands outside the box, no gesture starts, and the matrix never moves.
## The `pending_` this replaces asserted a drag and could not have passed
## whatever the fix was. A row write reaches the matrix by the same
## `_write_rows`, and the five rows beside the one written are as blind to it as
## six are to a drag, so it tests the announcement rather than the pointer. The
## drag is proved on the running app, in `scenarios/transform-rows-one-way.json`.
func test_the_transform_rows_follow_the_tool_moving_under_them() -> void:
    var surface := Fixtures.make_surface(Vector2i(1024, 1024))
    var machine := Fixtures.make_bound_machine(surface)
    var host := Node.new()
    var docker := ToolOptionsDocker.new()
    host.add_child(docker)
    docker.target_tool_machine = machine
    machine.set_active_tool(&"transform")
    var tool: ToolState = machine.active_tool
    surface.get_document().active_layer.get_or_create_chunk(Vector2i(1, 1)).clear(ORANGE)

    var row_x := docker.options.control(&"transform_move_x") as FactorSlider
    var row_y := docker.options.control(&"transform_move_y") as FactorSlider
    assert_almost_eq(row_x.value, 0.0, 0.01, "Nothing has moved, so the Position X row reads zero")

    tool.set(&"move_x", 200.0)
    assert_eq(tool.move_offset(), Vector2i(200, 0), "A write to the tool moved the picture")
    assert_almost_eq(row_x.value, 200.0, 0.5, "and the Position X row says so without anyone typing in it")

    tool.set(&"move_y", 100.0)
    assert_eq(tool.move_offset(), Vector2i(200, 100), "The second write keeps the first")
    assert_almost_eq(row_y.value, 100.0, 0.5, "and the Position Y row follows it")
    assert_almost_eq(row_x.value, 200.0, 0.5, "and the row nobody wrote is still right")

    host.free()
    Fixtures.teardown(surface, machine)


## A commit carries the selection with the pixels it was holding.
##
## It did not, so the box a painter was still holding surrounded empty canvas:
## `13-committed.json` had `transform.target_box` at the pre-commit rectangle
## while the picture had moved. Sara now carries it, the way Photoshop and Krita
## do, and the box the tool draws is the selection's bounds again.
##
## The mask is resampled through the same inverse map rather than having its
## bounds offset, which `SaTransformSelection` says at length: an offset bounds
## is right for a plain translate and a lie for a rotation.
func test_a_commit_moves_the_selection_with_the_pixels() -> void:
    var surface := Fixtures.make_surface(Vector2i(1024, 1024))
    var machine := Fixtures.make_bound_machine(surface)
    machine.set_active_tool(&"transform")
    var tool: ToolState = machine.active_tool
    var document := surface.get_document()
    document.active_layer.get_or_create_chunk(Vector2i(1, 1)).clear(ORANGE)
    document.selection.select_rect(Rect2i(300, 300, 200, 160))

    assert_false(
        document.selection.covers(Vector2i(2, 1)), "The selection starts inside one chunk, and the one to its right is clear"
    )

    tool.set("move_x", 120.0)
    assert_true(tool.commit_move(), "The move commits")

    assert_eq(document.selection.bounds, Rect2i(420, 300, 200, 160), "and the selection has gone with the pixels it was holding")
    # The bounds alone would pass for a carry that moved a number and left the
    # mask behind, which is the shape of fix this unit is not.
    assert_true(document.selection.covers(Vector2i(2, 1)), "and the mask itself reaches the chunk the move put it in")
    assert_true(document.selection.covers(Vector2i(1, 1)), "and still covers the one it came from, which the box straddles")
    Fixtures.teardown(surface, machine)
