## A stroke that paints nothing says why.
##
## A painter could not paint. The selection was active and held no chunk, so
## every dab was clipped to nothing and no ants drew, and behind it the brush's
## Erase was on. These hold that no change leaves an active selection of
## nothing, that each such drop is one undo step, and that a stroke clipped
## away by the selection or erasing an empty layer says so once on the line
## the status line shows.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")

var _surface: SaSurface = null
var _machine: ToolMachine = null
var _doc: SaDocument = null
var _said: Array[String] = []


## Two by two chunks, so a shape and a stroke can cross a seam.
func before_each() -> void:
    _surface = Fixtures.make_surface(Vector2i(512, 512))
    _machine = Fixtures.make_bound_machine(_surface)
    _doc = _surface.get_document()
    _said.clear()
    SaStrokeNote.say("")
    EventBus.stroke_explained.connect(_hear)


func after_each() -> void:
    EventBus.stroke_explained.disconnect(_hear)
    SaStrokeNote.say("")
    Fixtures.teardown(_surface, _machine)
    _surface = null
    _machine = null
    _doc = null


func _hear(line: String) -> void:
    _said.append(line)


## A press and a release of the active tool at *at* with no motion between.
## A fraction into a pixel, as a pointer usually is, which is what made a click
## of the marquee a one pixel box.
func _click(at: Vector2) -> void:
    (_surface.view as Fixtures.FakeView).mouse_position = at
    _machine.active_tool.handle_input(_button(true))
    _machine.active_tool.handle_input(_button(false))


static func _button(pressed: bool) -> InputEventMouseButton:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = pressed
    return event


func _steps() -> int:
    return _doc.undo_redo.get_history_count()


## A click of each marquee drops the selection, as one undo step that brings it
## back. An earlier guess was that a click was where the empty selection came from: it
## was not, since a click a fraction into a pixel selected that one pixel, which
## is a selection the pen paints nothing outside of either.
func test_a_click_of_each_marquee_drops_the_selection_as_one_step() -> void:
    for tool: StringName in [&"marquee", &"ellipse_select"]:
        _machine.set_active_tool(tool)
        _doc.selection.select_rect(Rect2i(100, 100, 100, 100))
        var steps := _steps()
        _click(Vector2(300.4, 300.6))
        assert_false(_doc.selection.active, "A click of %s leaves no selection" % tool)
        assert_eq(_doc.selection.chunks.size(), 0, "and no chunk")
        assert_eq(_steps(), steps + 1, "in one step")
        _doc.undo_redo.undo()
        assert_true(_doc.selection.active, "which an undo takes back")
        assert_eq(_doc.selection.bounds, Rect2i(100, 100, 100, 100), "to the square it was")
        _doc.undo_redo.redo()
        assert_false(_doc.selection.active, "and a redo drops again")
        _doc.selection.deselect_and_forget()


## A click with nothing selected records nothing, because nothing changed.
func test_a_click_with_nothing_selected_records_nothing() -> void:
    _machine.set_active_tool(&"marquee")
    var steps := _steps()
    _click(Vector2(300.4, 300.6))
    assert_false(_doc.selection.active, "Nothing is selected")
    assert_eq(_steps(), steps, "and no step was written")


func test_subtracting_all_of_it_leaves_no_selection() -> void:
    var selection := _doc.selection
    selection.select_rect(Rect2i(100, 100, 300, 300))
    var steps := _steps()
    selection.select_rect(Rect2i(50, 50, 400, 400), SaSelection.Mode.SUBTRACT)
    assert_false(selection.active, "A subtract over the whole of it leaves no selection")
    assert_eq(_steps(), steps + 1, "in one step")
    _doc.undo_redo.undo()
    assert_true(selection.active, "The undo brings it back")
    assert_eq(selection.chunks.size(), 4, "with its four chunks")
    assert_almost_eq(_coverage(250, 250), 1.0, 0.001, "holding what they held, untouched by the subtract")

    selection.select_rect(Rect2i(100, 100, 300, 150), SaSelection.Mode.SUBTRACT)
    assert_true(selection.active, "A subtract of part of it leaves the rest")


func test_a_wand_that_takes_all_of_it_leaves_no_selection() -> void:
    _doc.selection.select_rect(Rect2i(100, 100, 200, 200))
    var steps := _steps()
    # The layer is empty, so the flood reaches the whole canvas and takes the
    # square with it.
    var reached := SaWand.new().flood(_doc, Vector2i(10, 10), 0.05, SaSelection.Mode.SUBTRACT, null, _doc.active_layer)
    assert_true(reached > 0, "The flood reached the canvas")
    assert_false(_doc.selection.active, "and left no selection")
    assert_eq(_steps(), steps + 1, "in one step")
    _doc.undo_redo.undo()
    assert_eq(_doc.selection.bounds, Rect2i(100, 100, 200, 200), "which an undo takes back")


func test_inverting_a_whole_selection_leaves_no_selection() -> void:
    var selection := _doc.selection
    selection.select_all(_doc.canvas_size)
    var steps := _steps()
    SaSelectionFilters.invert(selection, _doc.canvas_size)
    assert_false(selection.active, "The invert of everything is no selection")
    assert_eq(_steps(), steps + 1, "in one step")
    _doc.undo_redo.undo()
    assert_true(selection.active, "The undo selects everything again")
    assert_almost_eq(_coverage(300, 300), 1.0, 0.001, "over the canvas")

    selection.deselect()
    steps = _steps()
    SaSelectionFilters.invert(selection, _doc.canvas_size)
    assert_false(selection.active, "With nothing selected an invert changes nothing")
    assert_eq(_steps(), steps, "and records nothing")


## The quick mask turned on and off with nothing painted was the other way to an
## active selection of nothing, the state a painter's capture showed.
func test_the_quick_mask_off_with_nothing_painted_is_no_selection() -> void:
    _doc.selection.editing = true
    assert_true(_doc.selection.active, "The quick mask makes a selection to paint")
    _doc.selection.editing = false
    assert_false(_doc.selection.active, "and leaving it with nothing painted is none")


## A stroke whose every dab falls outside the selection says so once, and the
## next stroke of the same cause says nothing more.
func test_a_stroke_outside_the_selection_says_so_once() -> void:
    _doc.selection.select_rect(Rect2i(400, 400, 50, 50))
    var brush := _brush()
    _stroke(brush, Vector2(100, 100))
    assert_eq(_said, [SaStrokeNote.OUTSIDE_SELECTION] as Array[String], "The stroke says nothing is selected there")
    _stroke(brush, Vector2(120, 100))
    assert_eq(_said.size(), 1, "and a second one like it says nothing more")
    _stroke(brush, Vector2(420, 420))
    assert_eq(_said.size(), 2, "A stroke inside the selection clears the line")
    assert_eq(_said[1], "", "with an empty line")


## The capture's state itself: active, no chunk. No change leaves it now, so it
## is set by hand, and a stroke under it still says why.
func test_a_stroke_under_an_empty_selection_says_so() -> void:
    _doc.selection.active = true
    _stroke(_brush(), Vector2(100, 100))
    assert_eq(_said, [SaStrokeNote.OUTSIDE_SELECTION] as Array[String], "A stroke under an empty selection says so")


func test_an_erase_stroke_on_an_empty_layer_says_erase_is_on() -> void:
    var brush := _brush()
    brush.set(&"eraser_toggled", true)
    _stroke(brush, Vector2(100, 100))
    assert_eq(_said, [SaStrokeNote.ERASING_NOTHING] as Array[String], "Erasing an empty layer says Erase is on")
    _stroke(brush, Vector2(140, 100))
    assert_eq(_said.size(), 1, "once")
    brush.set(&"eraser_toggled", false)
    _stroke(brush, Vector2(100, 100))
    assert_eq(_said.size(), 2, "and paint that lands clears it")
    brush.set(&"eraser_toggled", true)
    _stroke(brush, Vector2(100, 100))
    assert_eq(_said.size(), 2, "An eraser over paint says nothing")


## The machine's brush, a hard tenth of the canvas.
func _brush() -> ToolState:
    _machine.set_active_tool(&"brush")
    var brush := _machine.active_tool
    brush.set(&"eraser_toggled", false)
    return brush


## One press and one release at *at*, which is one dab and one stroke.
func _stroke(brush: ToolState, at: Vector2) -> void:
    (_surface.view as Fixtures.FakeView).mouse_position = at
    brush.handle_input(_button(true))
    brush.handle_input(_button(false))


func _coverage(x: int, y: int) -> float:
    @warning_ignore("integer_division")
    var chunk: SaChunk = _doc.selection.chunks.get(Vector2i(x / SaChunk.SIZE, y / SaChunk.SIZE), null)
    if chunk == null:
        return 0.0
    var texture := chunk.field(SaSelection.FIELD)
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    return bytes.decode_float(((y % SaChunk.SIZE) * texture.size.x + x % SaChunk.SIZE) * 4)
