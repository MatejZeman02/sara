## A drive of the selection and transform tools: the marquee, the lasso, the
## wand, the transform, the crop, the two fills and the gradient.
##
## The session is `scenarios/selection-transform-crop-fill-and-gradient.json`.
## Most of what it drives already has a suite, so this file holds only what
## nothing else asserts: the mechanism each defect turns on.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")
const StateTransformScript = preload("res://modules/sara-base-modules/base/transform/state_transform.gd")

## Every case here needs a real device: a wand floods on the GPU, a transform
## lifts into the stroke buffer, and the bar cannot be built without a machine.
const REQUIRES_GPU := true

## The block the drive painted for the wand to find, in document pixels.
## Smaller than the chunk grid it lands on, which is the whole of what the
## wand's box case is about.
const BLOCK := Rect2i(300, 300, 200, 120)

var _easel: SaEasel = null
var _doc: SaDocument = null


func before_each() -> void:
    _easel = SaEasel.create_default(Vector2i(512, 512))
    _doc = _easel.document


func after_each() -> void:
    _easel.free()
    _easel = null
    _doc = null


## Fills *rect* of the active layer and drops the selection, so a flood has a
## region to find on an otherwise empty layer. The shape `test_wand.gd` and
## `test_wand_subtract_bounds.gd` both use.
func _paint_rect(rect: Rect2i, color: Color) -> void:
    _doc.selection.select_rect(rect)
    _doc.fill_layer(color, _doc.active_layer)
    _doc.selection.deselect()


# --- The wand's box and what crops to it ---------------------------------------


## The mechanism the wand's box turns on: Image > Crop to Selection resizes to
## `SaSelection.bounds` and to nothing else, so whatever that box says is the
## canvas a painter is left with.
func test_crop_to_selection_takes_the_selections_own_box() -> void:
    _doc.selection.select_rect(Rect2i(40, 60, 100, 80))

    assert_true(SaCrop.new(_doc).crop_to_selection(), "There was a selection to crop to")

    assert_eq(_doc.canvas_size, Vector2i(100, 80), "and the canvas is the box the selection carried")


## A shape writer knows the rectangle it drew, so the marquee's box is tight and
## the crop that reads it lands on the painted edge. The comparison the wand's
## own case is measured against.
func test_a_marquee_leaves_a_box_that_is_the_rectangle_it_drew() -> void:
    _doc.selection.select_rect(BLOCK)

    assert_eq(_doc.selection.bounds, BLOCK, "The marquee wrote down what it drew")
    assert_eq(_doc.selection.measure_bounds(), BLOCK, "and the pixels agree with it")


## A wand replace must claim the coverage inside the chunk rectangles it reaches and not
## the rectangles, or the box is up to a chunk too big on every edge and Crop to Selection
## cuts the canvas to the chunk grid. `measure_bounds` is the answer the subtract branch of
## the same function already uses.
func test_f17_a_wand_replace_leaves_a_box_round_what_it_covered() -> void:
    _paint_rect(BLOCK, Color(0.9, 0.7, 0.2, 1.0))

    var wand := SaWand.new()
    # Written out rather than derived from the rectangle, because halving a
    # `Vector2i` is an integer division the language server warns about.
    var inside := Vector2i(400, 360)
    var reached := wand.flood(_doc, inside, 0.05, SaSelection.Mode.REPLACE, null, _doc.active_layer)

    assert_true(reached > 0, "The flood found the block")
    assert_eq(_doc.selection.bounds, BLOCK, "and the box is the block, not the chunks the block sits in")
    assert_eq(_doc.selection.measure_bounds(), _doc.selection.bounds, "so the pixels and the bookkeeping agree")


## The add branch, which the filing asked the fixer to write rather than fix
## only what was already asserted. It had the same shape: `reach` merged in as
## the chunk rectangles the second flood touched, so one add over a block in a
## fresh chunk grew the box to the grid whatever the block's own edges were.
##
## The second block sits in the first chunk of a 512 by 512 canvas, two chunks
## across, and the first sits across all four. A box taken from the chunks would
## be the whole canvas, and the two blocks together reach (60, 60) to (500, 420).
func test_a_wand_add_leaves_a_box_round_both_blocks_and_not_their_chunks() -> void:
    var second := Rect2i(60, 60, 80, 60)
    _paint_rect(BLOCK, Color(0.9, 0.7, 0.2, 1.0))
    _paint_rect(second, Color(0.9, 0.7, 0.2, 1.0))
    var wand := SaWand.new()

    wand.flood(_doc, Vector2i(400, 360), 0.05, SaSelection.Mode.REPLACE, null, _doc.active_layer)
    var added := wand.flood(_doc, Vector2i(100, 90), 0.05, SaSelection.Mode.ADD, null, _doc.active_layer)

    assert_true(added > 0, "The second flood found the second block")
    assert_eq(_doc.selection.bounds, BLOCK.merge(second), "and the box is the two blocks together")
    assert_eq(_doc.selection.measure_bounds(), _doc.selection.bounds, "which is what the pixels say too")


# --- Undoing a transform --------------------------------------------------------


## A transform over a selection, dragged and let go, which is the state before
## the commit. Answers the surface, the machine and the tool, the way
## `test_escape_puts_it_back.gd` does.
func _dragged() -> Array:
    var surface := Fixtures.make_surface(Vector2i(1024, 1024))
    var machine := Fixtures.make_bound_machine(surface)
    var document := surface.get_document()
    document.active_layer.get_or_create_chunk(Vector2i(1, 1))
    document.selection.select_rect(Rect2i(400, 384, 500, 400))
    machine.set_active_tool(&"transform")
    var tool := machine.active_tool
    surface.view.mouse_position = Vector2(650, 584)
    tool.handle_input(_press(true))
    surface.view.mouse_position = Vector2(850, 684)
    tool.handle_input(InputEventMouseMotion.new())
    tool.handle_input(_press(false))
    return [surface, machine, tool, document]


func _press(pressed: bool) -> InputEventMouseButton:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = pressed
    return event


## The mechanism an undo turns on: the commit carries the selection to where the
## pixels landed, so the box the tool draws still holds the thing it is a box
## around.
func test_a_commit_carries_the_selection_to_where_the_pixels_landed() -> void:
    var parts := _dragged()
    var tool: StateTransformScript = parts[2]
    var document: SaDocument = parts[3]

    assert_true(tool.commit_move(), "The drag committed")

    assert_eq(document.selection.bounds.position, Vector2i(600, 484), "and the selection went with it")
    Fixtures.teardown(parts[0], parts[1])


## The commit carries the selection and the step carries the mask the carry
## replaced, so an undo puts both back and a redo moves both again. The mirror
## of the carry on the undo side, and the same argument decides it: the box this
## tool draws is the selection's bounds.
func test_f18_an_undo_puts_the_selection_back_with_the_pixels() -> void:
    var parts := _dragged()
    var tool: StateTransformScript = parts[2]
    var document: SaDocument = parts[3]
    assert_true(tool.commit_move(), "The drag committed")
    assert_eq(document.selection.bounds.position, Vector2i(600, 484), "and the selection moved with it")
    var moved_chunks: int = document.selection.chunks.size()

    assert_true(document.undo_redo.undo(), "The commit is one undo step")

    assert_eq(document.selection.bounds, Rect2i(400, 384, 500, 400), "and the selection is back where it was lifted from")

    assert_true(document.undo_redo.redo(), "The redo is the same step the other way")
    assert_eq(document.selection.bounds.position, Vector2i(600, 484), "and the selection moves with the pixels again")
    assert_eq(document.selection.chunks.size(), moved_chunks, "with the mask it landed as, not a resample of a resample")
    Fixtures.teardown(parts[0], parts[1])


# --- The bar's painting-mode row -----------------------------------------------


## A bar over the built-in tools, built the way `test_brush_controls_on_the_bar.gd`
## builds one. Answers the surface, the machine and the bar.
func _bar_parts() -> Array:
    var surface := Fixtures.make_surface()
    var machine := Fixtures.make_bound_machine(surface)
    var registries := Fixtures.make_registries(surface)
    var bar := ToolOptionsBar.new()
    bar.target_tool_machine = machine
    bar._ready()
    bar.bind_registries(registries.blend_modes)
    return [surface, machine, bar]


## With a selection tool chosen the painting-mode row still belongs to the
## brush, so that is the tool it reads from and writes to.
func test_the_painting_mode_row_belongs_to_the_brush_whatever_is_chosen() -> void:
    var parts := _bar_parts()
    var machine: ToolMachine = parts[1]
    var bar: ToolOptionsBar = parts[2]

    for id: StringName in [&"brush", &"marquee", &"crop", &"gradient"]:
        machine.set_active_tool(id)
        assert_eq(String(bar.owner_of(&"blend_mode")), "brush", "the row still edits the brush with %s chosen" % id)

    parts[2].free()
    Fixtures.teardown(parts[0], parts[1])


## `_sync_ui_from_settings` fills the shared controls from every painting tool
## in registration order and the eraser is second, so with any other tool chosen
## the eraser's `erase` could be the last thing written into the row while
## `owner_of` names the brush, and the next stroke would not be the one the row
## describes. The loop walks the painting tools backwards, so the last writer of a shared key is the first
## declarer, which is the tool `owner_of` answers.
func test_f19_the_painting_mode_row_shows_the_mode_it_writes() -> void:
    var parts := _bar_parts()
    var machine: ToolMachine = parts[1]
    var bar: ToolOptionsBar = parts[2]
    machine.set_active_tool(&"brush")
    assert_eq(String(bar.control_value(&"blend_mode")), "normal", "The brush is on Normal to start with")

    machine.set_active_tool(&"marquee")

    assert_eq(String(bar.owner_of(&"blend_mode")), "brush", "The row still edits the brush")
    assert_eq(String(bar.control_value(&"blend_mode")), "normal", "and shows the brush's mode rather than the eraser's")

    parts[2].free()
    Fixtures.teardown(parts[0], parts[1])


## The other half, and the reason the fix is the loop's order rather than a
## branch on `blend_mode`: every other shared key
## holds the same value on both tools, so a fix aimed at the one key would
## pass the case above and leave the next divergent key to be found the same
## way. This makes a second key divergent by hand and asks the same question of
## it.
func test_every_shared_row_shows_the_tool_owner_of_names_not_the_last_synced() -> void:
    var parts := _bar_parts()
    var machine: ToolMachine = parts[1]
    var bar: ToolOptionsBar = parts[2]
    var brush := machine.get_tool(&"brush")
    var eraser := machine.get_tool(&"eraser")
    assert_not_null(brush, "the brush is registered")
    assert_not_null(eraser, "and so is the eraser, which is what makes a key shared")

    # A key both declare, moved apart on the two tools. `radius` is a fraction
    # of the canvas, so these are two sizes rather than two pixel counts.
    brush.settings.radius = 0.02
    eraser.settings.radius = 0.09
    machine.set_active_tool(&"marquee")

    assert_eq(String(bar.owner_of(&"radius")), "brush", "Size belongs to the brush with the marquee chosen")
    assert_almost_eq(float(bar.control_value(&"radius")), 0.02, 1e-6, "and the row shows the brush's, not the eraser's")

    parts[2].free()
    Fixtures.teardown(parts[0], parts[1])
