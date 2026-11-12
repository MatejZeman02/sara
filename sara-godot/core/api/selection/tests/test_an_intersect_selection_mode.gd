## Intersect, the fourth selection mode, on Shift+Alt as in Photoshop and
## Krita: what a new shape, a wand click, a colour range or a layer's alpha
## shares with the selection is what stays. Shift+Alt used to fall to Add,
## because every press handler asked about Shift first.
##
## Every mask is read back from VRAM, because an intersect drawn through the
## wrong kernel hands back plausible numbers rather than an error, and a chunk
## left holding zeros would still draw no ants.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const PaintKernel = preload("res://tests/fixtures/paint_kernel.gd")
const BaseModule = preload("res://modules/sara-base-modules/base/module.gd")

const RED := Color(1.0, 0.0, 0.0, 1.0)
## One dab in the lower left chunk and one in the upper right, so a range or a
## wand can choose one and a marquee keep the other.
const LOW_DAB := Vector2(100, 400)
const HIGH_DAB := Vector2(400, 100)

var _surface: SaSurface = null
var _machine: ToolMachine = null
var _doc: SaDocument = null
var _feather_was: float = 0.0


## Two by two chunks, so a shape crosses a seam and a chunk can be dropped.
func before_each() -> void:
    _surface = Fixtures.make_surface(Vector2i(512, 512))
    _machine = Fixtures.make_bound_machine(_surface)
    _doc = _surface.get_document()
    _feather_was = SaSettings.selection_feather
    SaSettings.selection_feather = 0.0


func after_each() -> void:
    SaSettings.selection_feather = _feather_was
    Fixtures.teardown(_surface, _machine)
    _surface = null
    _machine = null
    _doc = null


func _steps() -> int:
    return _doc.undo_redo.get_history_count()


func _coverage(x: int, y: int) -> float:
    @warning_ignore("integer_division")
    var grid := Vector2i(x / SaChunk.SIZE, y / SaChunk.SIZE)
    var chunk: SaChunk = _doc.selection.chunks.get(grid, null)
    if chunk == null:
        return 0.0
    var texture := chunk.field(SaSelection.FIELD)
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    var local := Vector2i(x - grid.x * SaChunk.SIZE, y - grid.y * SaChunk.SIZE)
    return bytes.decode_float((local.y * texture.size.x + local.x) * 4)


## Every chunk of the mask as its bytes, read back, so two masks compare whole.
func _mask() -> Dictionary:
    var out := {}
    for grid_pos: Vector2i in _doc.selection.chunks:
        var texture := (_doc.selection.chunks[grid_pos] as SaChunk).field(SaSelection.FIELD)
        out[grid_pos] = GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    return out


## One hard red dab onto the active layer, as one stroke and one step.
func _stroke(pos: Vector2) -> void:
    var compute := PaintKernel.compute()
    var region := Rect2(pos.x - 12.0, pos.y - 12.0, 24.0, 24.0)
    _doc.begin_stroke(1.0, SaLayer.BLEND_MODE.NORMAL)
    var paint := SaPaintContext.for_region(_doc, region, false)
    paint.dispatch_batch(
        compute,
        "paint",
        func(target: SaPaintContext.Target) -> void:
            compute.set_texture(0, target.texture.rid)
            compute.set_push_constant_float_array(
                PaintKernel.pack_params(paint.local_point(target, pos), target.render_offset, RED, 12.0, 1.0, 1.0, 1.0)
            )
    )
    paint.commit_invalidation()
    _doc.commit_stroke()


static func _button(pressed: bool, shift: bool = false, alt: bool = false) -> InputEventMouseButton:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = pressed
    event.shift_pressed = shift
    event.alt_pressed = alt
    return event


## A drag of *tool* from *from* to *to*, with Shift or Alt on the press.
func _drag(tool: StringName, from: Vector2, to: Vector2, shift: bool = false, alt: bool = false) -> void:
    _machine.set_active_tool(tool)
    var state := _machine.active_tool
    _surface.view.mouse_position = from
    state.handle_input(_button(true, shift, alt))
    _surface.view.mouse_position = to
    state.handle_input(InputEventMouseMotion.new())
    state.handle_input(_button(false))


## A freehand lasso round *path*, with Shift and Alt held on the press.
func _lasso_both(path: Array) -> void:
    _machine.set_active_tool(&"lasso")
    var state := _machine.active_tool
    _surface.view.mouse_position = path[0]
    state.handle_input(_button(true, true, true))
    for i in range(1, path.size()):
        _surface.view.mouse_position = path[i]
        state.handle_input(InputEventMouseMotion.new())
    state.handle_input(_button(false))


func test_the_chord_reads_intersect_for_shift_and_alt_together() -> void:
    var replace := SaSelection.Mode.REPLACE
    assert_eq(SaSelection.mode_for_press(replace, true, true), SaSelection.Mode.INTERSECT, "Shift and Alt intersect")
    assert_eq(SaSelection.mode_for_press(replace, true, false), SaSelection.Mode.ADD, "Shift alone adds")
    assert_eq(SaSelection.mode_for_press(replace, false, true), SaSelection.Mode.SUBTRACT, "Alt alone subtracts")
    assert_eq(SaSelection.mode_for_press(SaSelection.Mode.ADD, false, false), SaSelection.Mode.ADD, "and neither keeps the bar's")
    assert_eq(SaSelection.Mode.INTERSECT, 3, "Intersect is last, so no stored mode moves")


func test_the_tools_dropdown_lists_intersect() -> void:
    var labels := []
    for choice: Dictionary in BaseModule.selection_mode_option().choices:
        labels.append(choice["label"])
    assert_eq(labels, ["Replace", "Add", "Subtract", "Intersect"], "The marquee, ellipse, lasso and wand's Selection row")
    assert_eq(BaseModule.selection_mode_option().choices[3]["id"], SaSelection.Mode.INTERSECT, "and the fourth is the mode")


## The note's own gesture: a marquee, then Shift+Alt and a second across part
## of it. The second rectangle crosses three seams and the first sits in one
## chunk, so the overlap is one chunk and the three the shape made go.
func test_a_marquee_with_shift_and_alt_keeps_the_overlap_only() -> void:
    _drag(&"marquee", Vector2(20, 20), Vector2(200, 200))
    var steps := _steps()
    _drag(&"marquee", Vector2(120, 120), Vector2(450, 450), true, true)
    assert_eq(_steps(), steps + 1, "The intersect is one step")
    assert_eq(_doc.undo_redo.get_current_action_name(), SaSelection.RECT_TITLE, "named for the tool")
    assert_eq(_doc.selection.bounds, Rect2i(120, 120, 80, 80), "The selection is the overlap")
    assert_almost_eq(_coverage(160, 160), 1.0, 0.001, "holding its middle")
    assert_almost_eq(_coverage(60, 60), 0.0, 0.001, "and none of the first rectangle outside it")
    assert_eq(_doc.selection.chunks.keys(), [Vector2i(0, 0)], "nor any chunk of the second outside it")
    assert_almost_eq(_coverage(300, 300), 0.0, 0.001, "which Add used to keep")


func test_two_rectangles_that_do_not_meet_leave_no_selection_and_undo_brings_the_first() -> void:
    _drag(&"marquee", Vector2(20, 20), Vector2(120, 120))
    var first := _mask()
    var steps := _steps()
    _drag(&"marquee", Vector2(300, 300), Vector2(400, 400), true, true)
    assert_false(_doc.selection.active, "Nothing shared is no selection")
    assert_true(_doc.selection.chunks.is_empty(), "and no chunk")
    assert_eq(_steps(), steps + 1, "in one step")
    assert_true(_doc.undo(), "Ctrl+Z")
    assert_eq(_doc.selection.bounds, Rect2i(20, 20, 100, 100), "brings back the first rectangle")
    assert_eq(_mask(), first, "to the last bit")


func test_an_intersect_with_nothing_selected_is_a_replace() -> void:
    _drag(&"marquee", Vector2(300, 40), Vector2(380, 90), true, true)
    assert_eq(_doc.selection.bounds, Rect2i(300, 40, 80, 50), "Everything is selected, so the shape is what both hold")
    assert_almost_eq(_coverage(340, 60), 1.0, 0.001, "and it is selected")


## Undo puts the rectangle back exactly and redo the overlap, so the step holds
## both sides whole although the meet wrote into chunks of its own.
func test_an_intersect_undoes_to_the_exact_earlier_mask() -> void:
    _drag(&"marquee", Vector2(50, 50), Vector2(450, 450))
    var whole := _mask()
    _drag(&"ellipse_select", Vector2(200, 200), Vector2(500, 500), true, true)
    var met := _mask()
    assert_almost_eq(_coverage(350, 350), 1.0, 0.001, "The ellipse keeps its middle")
    assert_almost_eq(_coverage(475, 475), 0.0, 0.001, "but not past the rectangle")
    assert_almost_eq(_coverage(100, 100), 0.0, 0.001, "nor the rectangle outside the ellipse")
    assert_almost_eq(_coverage(205, 205), 0.0, 0.001, "nor the box's corner outside the ellipse")
    _doc.undo()
    assert_eq(_mask(), whole, "Ctrl+Z gives the rectangle back to the last bit")
    _doc.redo()
    assert_eq(_mask(), met, "and Ctrl+Shift+Z the overlap")


func test_a_lasso_with_shift_and_alt_keeps_the_overlap() -> void:
    _drag(&"marquee", Vector2(20, 20), Vector2(200, 200))
    var steps := _steps()
    _lasso_both([Vector2(100, 100), Vector2(300, 100), Vector2(300, 300), Vector2(100, 300)])
    assert_eq(_steps(), steps + 1, "The lasso's intersect is one step")
    assert_eq(_doc.undo_redo.get_current_action_name(), SaSelection.FREEHAND_TITLE, "named for the tool")
    assert_almost_eq(_coverage(150, 150), 1.0, 0.001, "It keeps what both hold")
    assert_almost_eq(_coverage(50, 50), 0.0, 0.001, "and none of the rectangle outside the outline")
    assert_almost_eq(_coverage(250, 250), 0.0, 0.001, "nor of the outline outside the rectangle")
    assert_eq(_doc.selection.bounds, Rect2i(100, 100, 100, 100), "The measured box is the overlap")


## A wand click on the empty ground selects all of it but the two dabs, and
## Shift+Alt keeps only the part inside the marquee, which holds the high dab.
func test_a_wand_click_with_shift_and_alt_keeps_the_overlap() -> void:
    _stroke(LOW_DAB)
    _stroke(HIGH_DAB)
    _drag(&"marquee", Vector2(0, 0), Vector2(512, 256))
    _machine.set_active_tool(&"wand")
    _machine.active_tool.sample_merged = false
    var steps := _steps()
    _surface.view.mouse_position = Vector2(250, 450)
    _machine.active_tool.handle_input(_button(true, true, true))
    assert_eq(_steps(), steps + 1, "The wand's intersect is one step")
    assert_eq(_doc.undo_redo.get_current_action_name(), SaSelection.WAND_TITLE, "named for the tool")
    assert_almost_eq(_coverage(250, 100), 1.0, 0.001, "The ground inside the marquee stays")
    assert_almost_eq(_coverage(int(HIGH_DAB.x), int(HIGH_DAB.y)), 0.0, 0.001, "the dab inside it goes")
    assert_almost_eq(_coverage(250, 450), 0.0, 0.001, "and the ground outside it was never there")
    assert_eq(_doc.selection.bounds, Rect2i(0, 0, 512, 256), "The box is the marquee's")


## A colour range of the red over a marquee of the upper half keeps the high
## dab alone, and the chunk of the upper left, which holds no red, goes.
func test_a_colour_range_in_intersect_keeps_the_overlap() -> void:
    _stroke(LOW_DAB)
    _stroke(HIGH_DAB)
    _drag(&"marquee", Vector2(0, 0), Vector2(512, 256))
    var steps := _steps()
    SaColorRange.new(_doc).select(RED, 40.0, SaSelection.Mode.INTERSECT, null, _doc.active_layer)
    assert_eq(_steps(), steps + 1, "Colour Range's intersect is one step")
    assert_almost_eq(_coverage(int(HIGH_DAB.x), int(HIGH_DAB.y)), 1.0, 0.001, "The red inside the marquee stays")
    assert_almost_eq(_coverage(int(LOW_DAB.x), int(LOW_DAB.y)), 0.0, 0.001, "the red outside it is not added")
    assert_almost_eq(_coverage(100, 100), 0.0, 0.001, "and the ground inside it goes")
    assert_eq(_doc.selection.chunks.keys(), [Vector2i(1, 0)], "leaving the one chunk that holds the dab")


## Ctrl, Shift and Alt on a layer's thumbnail ask the chord for the mode, as
## `SaLayerPick.select_opaque` does, and Select Opaque meets the selection.
func test_select_opaque_with_shift_and_alt_keeps_the_overlap() -> void:
    _stroke(LOW_DAB)
    _stroke(HIGH_DAB)
    _drag(&"marquee", Vector2(0, 0), Vector2(512, 256))
    var steps := _steps()
    var mode := SaSelection.mode_for_press(SaSelection.Mode.REPLACE, true, true)
    assert_true(SaSelectOpaque.new(_doc).select(_doc.active_layer, mode), "Select Opaque takes the layer")
    assert_eq(_steps(), steps + 1, "in one step")
    assert_eq(_doc.undo_redo.get_current_action_name(), SaSelectOpaque.TITLE, "under its own name")
    assert_almost_eq(_coverage(int(HIGH_DAB.x), int(HIGH_DAB.y)), 1.0, 0.001, "The paint inside the marquee stays")
    assert_almost_eq(_coverage(int(LOW_DAB.x), int(LOW_DAB.y)), 0.0, 0.001, "the paint outside it is not added")
    _doc.undo()
    assert_eq(_doc.selection.bounds, Rect2i(0, 0, 512, 256), "and Ctrl+Z gives the marquee back")
