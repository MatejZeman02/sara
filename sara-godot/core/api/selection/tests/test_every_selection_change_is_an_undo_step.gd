## Every change a painter makes to the selection is one undo step, under the
## name the Undo History docker lists it by: the marquee, the ellipse, the
## lasso, the wand, Colour Range, and the Select commands. A wrong marquee used
## to cost the stroke before it, because Ctrl+Z skipped the selection and took
## the last step that was recorded.
##
## Add and Subtract write into the chunks they find, so the change copies a
## chunk before its first write and the step holds the original. Every mask is
## read back from VRAM, because a way back that held the live chunks would hand
## back plausible numbers rather than an error.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const PaintKernel = preload("res://tests/fixtures/paint_kernel.gd")

const RED := Color(1.0, 0.0, 0.0, 1.0)
const FIRST_STROKE := Vector2(100, 400)
const SECOND_STROKE := Vector2(400, 100)

var _surface: SaSurface = null
var _machine: ToolMachine = null
var _registries: SaRegistries = null
var _doc: SaDocument = null
var _feather_was: float = 0.0


## Two by two chunks, so a shape crosses a seam and a copy is made per chunk.
func before_each() -> void:
    _surface = Fixtures.make_surface(Vector2i(512, 512))
    _machine = Fixtures.make_bound_machine(_surface)
    _registries = Fixtures.make_registries(_surface)
    _doc = _surface.get_document()
    _feather_was = SaSettings.selection_feather
    SaSettings.selection_feather = 0.0


func after_each() -> void:
    SaSettings.selection_feather = _feather_was
    Fixtures.teardown(_surface, _machine)
    _surface = null
    _machine = null
    _registries = null
    _doc = null


func _steps() -> int:
    return _doc.undo_redo.get_history_count()


func _title() -> String:
    return _doc.undo_redo.get_current_action_name()


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


func _alpha(at: Vector2) -> float:
    var grid := Vector2i(floori(at.x / SaChunk.SIZE), floori(at.y / SaChunk.SIZE))
    var texture := _doc.active_layer.get_field(grid)
    if texture == null:
        return 0.0
    var local := Vector2i(at) - grid * SaChunk.SIZE
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    return SaFieldSpec.decode_texel(bytes, texture.format, local.y * texture.size.x + local.x).a


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


## A drag of the active tool from *from* to *to*, with Shift or Alt on the press.
func _drag(from: Vector2, to: Vector2, shift: bool = false, alt: bool = false) -> void:
    var tool := _machine.active_tool
    _surface.view.mouse_position = from
    tool.handle_input(_button(true, shift, alt))
    _surface.view.mouse_position = to
    tool.handle_input(InputEventMouseMotion.new())
    tool.handle_input(_button(false))


func _lasso(path: Array) -> void:
    var tool := _machine.active_tool
    _surface.view.mouse_position = path[0]
    tool.handle_input(_button(true))
    for i in range(1, path.size()):
        _surface.view.mouse_position = path[i]
        tool.handle_input(InputEventMouseMotion.new())
    tool.handle_input(_button(false))


func _run(command_id: StringName) -> bool:
    return _registries.commands.execute(command_id)


func test_a_marquee_after_two_strokes_is_undone_alone_and_redone() -> void:
    _stroke(FIRST_STROKE)
    _stroke(SECOND_STROKE)
    var steps := _steps()
    _machine.set_active_tool(&"marquee")
    _drag(Vector2(200, 200), Vector2(300, 300))
    assert_eq(_steps(), steps + 1, "The marquee is one step")
    assert_eq(_title(), SaSelection.RECT_TITLE, "named for the tool")

    assert_true(_doc.undo(), "Ctrl+Z")
    assert_false(_doc.selection.active, "takes the marquee away")
    assert_almost_eq(_alpha(FIRST_STROKE), 1.0, 0.01, "and leaves the first stroke")
    assert_almost_eq(_alpha(SECOND_STROKE), 1.0, 0.01, "and the second")

    assert_true(_doc.redo(), "Ctrl+Shift+Z")
    assert_true(_doc.selection.active, "brings the marquee back")
    assert_eq(_doc.selection.bounds, Rect2i(200, 200, 100, 100), "where it was dragged")
    assert_almost_eq(_coverage(250, 250), 1.0, 0.001, "holding its middle")
    assert_almost_eq(_alpha(SECOND_STROKE), 1.0, 0.01, "with both strokes still there")


func test_select_all_undone_leaves_no_selection() -> void:
    var steps := _steps()
    assert_true(_run(&"select_all"), "Ctrl+A")
    assert_eq(_steps(), steps + 1, "is one step")
    assert_eq(_title(), SaSelection.ALL_TITLE, "called Select All")
    _doc.undo()
    assert_false(_doc.selection.active, "and Ctrl+Z leaves no selection")
    _doc.redo()
    assert_almost_eq(_coverage(500, 500), 1.0, 0.001, "and a redo selects the whole canvas again")


## A hole cut out of a rectangle, then a Shift-drag across the hole and three
## seams. The Add writes into four chunks that the Subtract's step and its own
## undo both need as they were, so an undo that handed back the live chunks
## would show the hole filled.
func test_an_add_and_a_subtract_undo_to_the_exact_earlier_mask() -> void:
    _machine.set_active_tool(&"marquee")
    _drag(Vector2(50, 50), Vector2(450, 450))
    var whole := _mask()
    _drag(Vector2(150, 150), Vector2(240, 240), false, true)
    assert_almost_eq(_coverage(200, 200), 0.0, 0.001, "Alt cuts a hole")
    var holed := _mask()
    var steps := _steps()
    _drag(Vector2(200, 200), Vector2(300, 300), true)
    assert_eq(_steps(), steps + 1, "Shift adds in one step")
    assert_almost_eq(_coverage(220, 220), 1.0, 0.001, "over the hole")

    _doc.undo()
    assert_eq(_mask(), holed, "The undo of the Add is the holed mask to the last bit")
    assert_almost_eq(_coverage(220, 220), 0.0, 0.001, "so the first rectangle has its hole again")
    _doc.undo()
    assert_eq(_mask(), whole, "and the undo of the Subtract is the whole rectangle")
    _doc.redo()
    _doc.redo()
    assert_almost_eq(_coverage(220, 220), 1.0, 0.001, "Two redos fill the hole again")
    assert_almost_eq(_coverage(160, 160), 0.0, 0.001, "where the Add did not reach")


## The Add's step holds the four chunks it copied, so the history's budget sees
## them, and a Replace holds the chunks it let go of.
func test_a_step_pays_for_the_chunks_it_holds() -> void:
    _machine.set_active_tool(&"marquee")
    _drag(Vector2(50, 50), Vector2(450, 450))
    var chunk_bytes := (_doc.selection.chunks.values()[0] as SaChunk).byte_size()
    var paid := _doc.history.total_bytes()
    _drag(Vector2(200, 200), Vector2(300, 300), true)
    assert_eq(_doc.history.total_bytes() - paid, 4 * chunk_bytes, "An Add across a crossing of seams pays four copies")
    paid = _doc.history.total_bytes()
    _drag(Vector2(10, 10), Vector2(40, 40))
    assert_eq(_doc.history.total_bytes() - paid, 4 * chunk_bytes, "and a Replace pays the four chunks it let go of")


func test_each_tool_and_command_is_one_step_under_its_title() -> void:
    _stroke(FIRST_STROKE)
    var cases: Array = [
        [SaSelection.RECT_TITLE, _marquee],
        [SaSelection.ELLIPSE_TITLE, _ellipse],
        [SaSelection.FREEHAND_TITLE, _freehand],
        [SaSelection.WAND_TITLE, _wand],
        [SaSelection.COLOR_RANGE_TITLE, _color_range],
        [SaSelection.FEATHER_TITLE, _feather],
        [SaSelection.BORDER_TITLE, _border],
        [SaSelection.ALL_TITLE, _run.bind(&"select_all")],
        [SaSelection.INVERT_TITLE, _run.bind(&"select_invert")],
        [SaSelection.ALL_TITLE, _run.bind(&"select_all")],
        [SaSelection.DROP_TITLE, _run.bind(&"select_none")],
        [SaSelection.RESELECT_TITLE, _run.bind(&"select_reselect")],
        [SaSelection.DROP_TITLE, _marquee_click],
    ]
    for case: Array in cases:
        var steps := _steps()
        (case[1] as Callable).call()
        assert_eq(_steps(), steps + 1, "%s is one step" % case[0])
        assert_eq(_title(), case[0], "listed as %s" % case[0])


func _marquee() -> void:
    _machine.set_active_tool(&"marquee")
    _drag(Vector2(20, 20), Vector2(120, 120))


## Pressed outside the marquee before it, because a press inside a
## selection moves its outline rather than drawing a shape.
func _ellipse() -> void:
    _machine.set_active_tool(&"ellipse_select")
    _drag(Vector2(130, 20), Vector2(330, 120))


func _freehand() -> void:
    _machine.set_active_tool(&"lasso")
    _lasso([Vector2(50, 50), Vector2(250, 50), Vector2(250, 250), Vector2(50, 250)])


func _wand() -> void:
    _machine.set_active_tool(&"wand")
    _machine.active_tool.sample_merged = false
    _machine.active_tool.flood(Vector2i(FIRST_STROKE))


func _color_range() -> void:
    SaColorRange.new(_doc).select(RED, 40.0, SaSelection.Mode.REPLACE, null, _doc.active_layer)


## What the Select menu's Feather runs once its dialog is answered, the menu
## itself needing a main scene this suite does not build. The scenario of this
## unit presses the menu row in the running app.
func _feather() -> void:
    var selection := _doc.selection
    selection.change(SaSelection.FEATHER_TITLE, SaSelectionFilters.feather.bind(selection, 6, _doc.canvas_size))


## The same for Border.
func _border() -> void:
    var selection := _doc.selection
    selection.change(SaSelection.BORDER_TITLE, SaSelectionFilters.border.bind(selection, 4, _doc.canvas_size))


func _marquee_click() -> void:
    _machine.set_active_tool(&"marquee")
    _drag(Vector2(300, 300), Vector2(300, 300))


## A Feather on the marquee lands with the shape, and the two are one step, so
## one undo takes both and leaves what stood before.
func test_a_feathered_marquee_is_one_step() -> void:
    SaSettings.selection_feather = 0.02
    _machine.set_active_tool(&"marquee")
    var steps := _steps()
    _drag(Vector2(100, 100), Vector2(300, 300))
    assert_eq(_steps(), steps + 1, "The feathered marquee is one step")
    assert_true(_coverage(97, 200) > 0.0, "softened past its edge")
    _doc.undo()
    assert_false(_doc.selection.active, "and one undo leaves no selection, as before it")


## A subtract that takes all of the selection drops it, and that drop is the
## change's step rather than a second one.
func test_a_subtract_that_takes_everything_is_one_step() -> void:
    _machine.set_active_tool(&"marquee")
    _drag(Vector2(100, 100), Vector2(200, 200))
    var steps := _steps()
    _drag(Vector2(50, 50), Vector2(250, 250), false, true)
    assert_false(_doc.selection.active, "Alt over all of it drops the selection")
    assert_eq(_steps(), steps + 1, "in one step")
    assert_eq(_title(), SaSelection.RECT_TITLE, "named for the tool")
    _doc.undo()
    assert_eq(_doc.selection.bounds, Rect2i(100, 100, 100, 100), "which an undo takes back")
    assert_almost_eq(_coverage(150, 150), 1.0, 0.001, "untouched by the subtract")


func test_a_change_that_changes_nothing_records_nothing() -> void:
    var steps := _steps()
    assert_true(_run(&"select_none"), "Deselect with nothing selected")
    assert_false(_run(&"select_reselect"), "and Reselect with nothing kept, which falls through")
    _machine.set_active_tool(&"marquee")
    _drag(Vector2(50, 50), Vector2(250, 250), false, true)
    _drag(Vector2(300, 300), Vector2(300, 300))
    assert_true(_run(&"select_quick_mask"), "The quick mask on")
    assert_true(_run(&"select_quick_mask"), "and off again, a mode and not a change")
    assert_eq(_steps(), steps, "None of these records a step")
    _machine.set_active_tool(&"lasso")
    _lasso([Vector2(50, 300), Vector2(250, 300)])
    assert_eq(_steps(), steps, "nor does a lasso around no area")


## An undone Reselect leaves Reselect able to bring the selection back again,
## because the step holds what Reselect keeps as well as what is selected.
func test_undo_puts_back_what_reselect_brings() -> void:
    _machine.set_active_tool(&"marquee")
    _drag(Vector2(100, 100), Vector2(200, 200))
    _run(&"select_none")
    assert_true(_run(&"select_reselect"), "Reselect brings the square back")
    _doc.undo()
    assert_false(_doc.selection.active, "An undo of it leaves nothing selected")
    assert_true(_doc.selection.can_reselect(), "and Reselect lit again")
    _doc.undo()
    assert_eq(_doc.selection.bounds, Rect2i(100, 100, 100, 100), "An undo of the Deselect puts the square back")
    _doc.redo()
    assert_true(_doc.selection.can_reselect(), "and its redo keeps the square for Reselect")
    assert_true(_run(&"select_reselect"), "which brings it back")
    assert_almost_eq(_coverage(150, 150), 1.0, 0.001, "whole")
