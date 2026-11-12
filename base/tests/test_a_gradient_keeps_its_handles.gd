## A gradient keeps its two ends after the release.
##
## With no handles once the button is up, the only
## way to move an end would be Ctrl+Z and a second drag. The release lays the
## ramp as one history step, and the ends stay: a press on one drags it and its
## release lays the ramp again under that same step. Enter, a press away from
## both, a tool switch, another layer, a save or any other step let the ends go
## with the ramp as it is, an undo finishes it first, and Escape takes it back
## off.
##
## Driven through `handle_input` with the fixture's view holding the pointer,
## the door the tool machine hands every event to, and read back texel by texel
## off a black to white ramp along y = 100 of a 512 square: past the release
## end the ramp holds white, so a texel at x = 300 is white while the far end
## is at 200 and grey once it has been dragged to 400.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")
const SaGradientScript = preload("res://modules/sara-base-modules/base/gradient/sa_gradient.gd")

const REQUIRES_GPU := true

## The ramp's first drag, and where its far end is dragged after the release.
const FROM := Vector2(10.0, 100.0)
const TO := Vector2(200.0, 100.0)
const FARTHER := Vector2(400.0, 100.0)
## The texel read: past TO, inside FARTHER.
const PROBE := Vector2i(300, 100)

var _surface: SaSurface = null
var _machine: ToolMachine = null
var _tool: ToolState = null
var _document: SaDocument = null
var _view: Fixtures.FakeView = null


func before_each() -> void:
    _surface = Fixtures.make_surface(Vector2i(512, 512))
    _machine = Fixtures.make_bound_machine(_surface)
    _machine.set_active_tool(&"gradient")
    _tool = _machine.get_tool(&"gradient")
    _tool.ramp = SaColorRamp.from_pair(Color.BLACK, Color.WHITE)
    _document = _surface.get_document()
    _view = _surface.view


func after_each() -> void:
    Fixtures.teardown(_surface, _machine)
    _surface = null
    _machine = null
    _tool = null
    _document = null
    _view = null


func test_the_release_lays_the_ramp_and_keeps_both_ends() -> void:
    var steps := _document.history.step_count()
    _drag(FROM, TO)

    assert_eq(_document.history.step_count(), steps + 1, "The release lays the ramp as one step")
    assert_true(_document.stroke_layer.chunks.is_empty(), "and the preview is gone")
    assert_true(_texel(PROBE).r > 0.95, "Past the far end the ramp holds white, %.3f" % _texel(PROBE).r)
    var shape: Dictionary = _tool.preview_shape()
    assert_eq(shape.get("rings", PackedVector2Array()), PackedVector2Array([FROM, TO]), "Two round handles stay on the ends")
    assert_true(shape.get("joined", false), "with the line between them")
    assert_true(_report()["held"], "The dump says the ends are held")


func test_a_drag_on_the_far_end_moves_the_ramp_under_the_same_step() -> void:
    var steps := _document.history.step_count()
    _drag(FROM, TO)
    var gradient_pass: SaGradientScript = _tool._pass_for(_document)
    var previews := gradient_pass.previews

    _view.mouse_position = TO + Vector2(4.0, 3.0)
    _tool.handle_input(_button(true))
    assert_eq(_report()["grabbed"], "to", "A press five pixels off the far end takes it")
    assert_almost_eq(_texel(PROBE).a, 0.0, 0.001, "and the layer gives the ramp back while the end moves")
    _tool.tick(0.016)
    assert_eq(gradient_pass.previews, previews + 1, "The preview shows it at once instead")
    _view.mouse_position = FARTHER
    _tool.handle_input(InputEventMouseMotion.new())
    _tool.handle_input(InputEventMouseMotion.new())
    _tool.tick(0.016)
    assert_eq(gradient_pass.previews, previews + 2, "Two motions in a frame dispatch one preview")
    _tool.handle_input(_button(false))

    var grey := _texel(PROBE)
    assert_eq(_document.history.step_count(), steps + 1, "The moved ramp is still the one step")
    assert_true(grey.r > 0.05 and grey.r < 0.95, "The ramp runs on past 300 now, %.3f" % grey.r)
    assert_almost_eq(grey.a, 1.0, 0.001, "laid opaque")
    assert_true(_document.stroke_layer.chunks.is_empty(), "with the preview gone again")
    assert_eq(
        _tool.preview_shape().get("rings", PackedVector2Array()),
        PackedVector2Array([FROM, FARTHER]),
        "The handle sits on the moved end"
    )

    _machine.close_session()
    assert_true(_document.undo(), "Ctrl+Z")
    assert_almost_eq(_texel(PROBE).a, 0.0, 0.001, "takes the ramp off whole")
    assert_almost_eq(_texel(Vector2i(20, 100)).a, 0.0, 0.001, "near end and all")


func test_a_drag_on_the_near_end_moves_that_end() -> void:
    _drag(FROM, TO)
    _view.mouse_position = FROM
    _tool.handle_input(_button(true))
    assert_eq(_report()["grabbed"], "from", "A press on the near end takes the near end")
    _view.mouse_position = Vector2(250.0, 100.0)
    _tool.handle_input(InputEventMouseMotion.new())
    _tool.tick(0.016)
    _tool.handle_input(_button(false))
    assert_eq(
        _tool.preview_shape().get("rings", PackedVector2Array()),
        PackedVector2Array([Vector2(250.0, 100.0), TO]),
        "and only it moves"
    )
    assert_true(_texel(Vector2i(100, 100)).r > 0.95, "The ramp now runs backwards, white before the far end")


func test_enter_lets_the_ends_go_and_keeps_the_one_step() -> void:
    var steps := _document.history.step_count()
    _drag(FROM, TO)
    _drag(TO, FARTHER)
    _tool.handle_input(_key(KEY_ENTER))

    assert_true(_tool.preview_shape().is_empty(), "Enter lets the ends go")
    assert_eq(_document.history.step_count(), steps + 1, "and the ramp is one undo step")
    var grey := _texel(PROBE).r
    assert_true(grey > 0.05 and grey < 0.95, "as it was left, %.3f" % grey)
    _view.mouse_position = FARTHER
    _tool.handle_input(_button(true))
    assert_false(_report()["grabbed"] == "to", "A press on the old end starts a new ramp rather than taking it")
    _tool.handle_input(_key(KEY_ESCAPE))
    assert_true(_document.undo(), "Ctrl+Z")
    assert_almost_eq(_texel(PROBE).a, 0.0, 0.001, "removes the ramp whole")


func test_escape_takes_the_ramp_back_off() -> void:
    var steps := _document.history.step_count()
    var at := _document.history.position()
    _drag(FROM, TO)
    _drag(TO, FARTHER)
    _tool.handle_input(_key(KEY_ESCAPE))

    assert_almost_eq(_texel(PROBE).a, 0.0, 0.001, "Escape leaves the layer as it was before the drag")
    assert_almost_eq(_texel(Vector2i(20, 100)).a, 0.0, 0.001, "near end and all")
    assert_true(_tool.preview_shape().is_empty(), "with no handles")
    assert_eq(_document.history.position(), at, "and the history where it stood")
    assert_true(_document.undo_redo.has_redo(), "with the ramp on the redo list for Ctrl+Shift+Z")
    assert_eq(_document.history.step_count(), steps + 1, "which is the one step it was")


func test_escape_during_the_first_drag_lays_nothing() -> void:
    var steps := _document.history.step_count()
    _view.mouse_position = FROM
    _tool.handle_input(_button(true))
    _view.mouse_position = TO
    _tool.handle_input(InputEventMouseMotion.new())
    _tool.tick(0.016)
    _tool.handle_input(_key(KEY_ESCAPE))
    _tool.handle_input(_button(false))

    assert_true(_document.stroke_layer.chunks.is_empty(), "Escape drops the preview")
    assert_eq(_document.history.step_count(), steps, "and the release after it lays nothing")
    assert_true(_tool.preview_shape().is_empty(), "with no handles")


func test_switching_tool_keeps_the_ramp_and_lets_the_ends_go() -> void:
    var steps := _document.history.step_count()
    _drag(FROM, TO)
    _machine.set_active_tool(&"eyedropper")

    assert_eq(_document.history.step_count(), steps + 1, "The switch keeps the ramp's one step")
    assert_true(_texel(PROBE).r > 0.95, "and its pixels")
    _machine.set_active_tool(&"gradient")
    assert_true(_tool.preview_shape().is_empty(), "Back on the gradient its ends are gone")


func test_switching_tool_during_an_end_s_drag_lays_it_where_it_is() -> void:
    var steps := _document.history.step_count()
    _drag(FROM, TO)
    _view.mouse_position = TO
    _tool.handle_input(_button(true))
    _view.mouse_position = FARTHER
    _tool.handle_input(InputEventMouseMotion.new())
    _tool.tick(0.016)
    _machine.set_active_tool(&"eyedropper")

    var grey := _texel(PROBE).r
    assert_true(grey > 0.05 and grey < 0.95, "The end is laid where the switch found it, %.3f" % grey)
    assert_eq(_document.history.step_count(), steps + 1, "under the same step")
    assert_true(_document.stroke_layer.chunks.is_empty(), "with no preview left over")


func test_a_press_away_from_both_ends_starts_the_next_ramp() -> void:
    var steps := _document.history.step_count()
    _drag(FROM, TO)
    _drag(Vector2(10.0, 400.0), Vector2(200.0, 400.0))

    assert_eq(_document.history.step_count(), steps + 2, "Each ramp is a step of its own")
    assert_true(_texel(PROBE).r > 0.95, "The first stays as laid")
    assert_eq(
        _tool.preview_shape().get("rings", PackedVector2Array()),
        PackedVector2Array([Vector2(10.0, 400.0), Vector2(200.0, 400.0)]),
        "and the handles are the second's"
    )


func test_another_layer_lets_the_ends_go() -> void:
    var first := _document.active_layer
    var second := SaLayerOps.new(_document).add()
    _document.set_active_layer(first)
    _drag(FROM, TO)
    _document.set_active_layer(second)
    _tool.tick(0.016)

    assert_true(_tool.preview_shape().is_empty(), "Another layer lets the ends go")
    assert_true(_texel_of(first, PROBE).r > 0.95, "and the ramp stays on the layer it was laid on")
    _view.mouse_position = TO
    _tool.handle_input(_button(true))
    assert_eq(_report()["grabbed"], "none", "A press on the old end starts a ramp on the new layer")
    _tool.handle_input(_key(KEY_ESCAPE))


func test_an_undo_during_an_end_s_drag_finishes_the_ramp_first() -> void:
    _drag(FROM, TO)
    _view.mouse_position = TO
    _tool.handle_input(_button(true))
    _view.mouse_position = FARTHER
    _tool.handle_input(InputEventMouseMotion.new())
    _tool.tick(0.016)

    _machine.close_session()
    assert_true(_tool.preview_shape().is_empty(), "The undo's close lets the ends go")
    var grey := _texel(PROBE).r
    assert_true(grey > 0.05 and grey < 0.95, "with the dragged end laid, %.3f" % grey)
    assert_true(_document.undo(), "so the undo")
    assert_almost_eq(_texel(PROBE).a, 0.0, 0.001, "takes the ramp back whole")
    assert_true(_document.redo(), "and a redo")
    grey = _texel(PROBE).r
    assert_true(grey > 0.05 and grey < 0.95, "puts back the ramp as it was dragged, %.3f" % grey)


func test_a_changed_option_lays_the_held_ramp_again() -> void:
    var steps := _document.history.step_count()
    _drag(FROM, TO)
    _tool.repeat = SaGradientScript.Repeat.MIRROR
    _tool.tick(0.016)

    var mirrored := _texel(PROBE).r
    assert_true(mirrored > 0.05 and mirrored < 0.95, "Mirror runs the ramp back past the far end, %.3f" % mirrored)
    assert_eq(_document.history.step_count(), steps + 1, "under the same step")
    var below := Vector2i(10, 250)
    assert_true(_texel(below).r < 0.05, "Straight below the near end the linear ramp is black, %.3f" % _texel(below).r)
    _tool.shape = SaGradientScript.Shape.RADIAL
    _tool.tick(0.016)
    var round_ramp := _texel(below).r
    assert_true(round_ramp > 0.3, "A radial shape lays the ramp again around the near end, %.3f" % round_ramp)
    assert_eq(_document.history.step_count(), steps + 1, "still under the same step")
    _tool.shape = SaGradientScript.Shape.LINEAR
    _tool.tick(0.016)
    _tool.ramp = SaColorRamp.from_pair(Color.WHITE, Color.BLACK)
    _tool.tick(0.016)
    assert_true(_texel(Vector2i(10, 100)).r > 0.95, "A ramp edited while the ends are held is laid again in its colours")
    assert_eq(_document.history.step_count(), steps + 1, "and is still the one step")


func test_a_save_lets_the_ends_go() -> void:
    _drag(FROM, TO)
    _document.mark_saved(SaDataRoot.path("s59.sad"))
    _tool.tick(0.016)
    assert_true(_tool.preview_shape().is_empty(), "A save keeps the ramp as it went into the file")


## The audit's case: Ctrl+S with the button still down on an end, which had
## taken the ramp off the layer to preview it. The save lays the end where it
## is before it writes, through the File menu's own door, so the file holds the
## ramp the painter sees.
func test_a_save_during_an_end_s_drag_writes_the_ramp_as_dragged() -> void:
    var path := SaDataRoot.path("s59_during_a_drag.sad")
    _document.mark_saved(path)
    var steps := _document.history.step_count()
    _drag(FROM, TO)
    _view.mouse_position = TO
    _tool.handle_input(_button(true))
    _view.mouse_position = FARTHER
    _tool.handle_input(InputEventMouseMotion.new())
    _tool.tick(0.016)
    assert_almost_eq(_texel(PROBE).a, 0.0, 0.001, "The end's drag has the ramp off the layer")

    var canvas := SaCanvas.new()
    canvas.easel = _surface.easel
    canvas.add_child(_machine)
    var files := SaDocumentFiles.new(func() -> SaCanvas: return canvas)
    files.run_action(&"file_save")
    assert_true(SaSadSave.finish_all(), "The save in the background ends")
    canvas.remove_child(_machine)
    canvas.easel = null
    canvas.free()
    files.free()

    assert_true(_tool.preview_shape().is_empty(), "Ctrl+S lets the ends go")
    assert_eq(_document.history.step_count(), steps + 1, "with the ramp still the one step")
    assert_false(_document.modified, "and the document saved")
    var loaded := SaDocument.new()
    assert_eq(SaExport.load_sad(loaded, path, SaCompositor.new()), OK, "The file loads")
    var back: SaLayer = loaded.get_node_or_null(str(_document.active_layer.name))
    assert_not_null(back, "with the ramp's layer")
    if back != null:
        var grey := _texel_of(back, PROBE)
        assert_true(grey.r > 0.05 and grey.r < 0.95, "holding the ramp as dragged, %.3f" % grey.r)
        assert_almost_eq(grey.a, 1.0, 0.001, "laid opaque")
    loaded.free()
    DirAccess.remove_absolute(path)
    # The door's save put the path on the run's one recent list, which
    # `test_menus` reads as File > Open Recent.
    SaSettings.remove_recent_file(path)


func test_any_other_step_lets_the_ends_go() -> void:
    _drag(FROM, TO)
    var layer := _document.active_layer
    var other := SaGradientScript.new(_document)
    var ramp := SaColorRamp.from_pair(Color.BLACK, Color.WHITE)
    assert_true(other.apply(layer, Vector2(0.0, 400.0), Vector2(100.0, 400.0), ramp, 0, 0, false), "Another step lands")
    _tool.tick(0.016)

    assert_true(_tool.preview_shape().is_empty(), "A step the tool did not write lets the ends go")
    _view.mouse_position = TO
    _tool.handle_input(_button(true))
    assert_eq(_report()["grabbed"], "none", "so a press on the old end takes nothing")
    _tool.handle_input(_key(KEY_ESCAPE))


## A press at *from*, a motion to *to* and a frame, and the release there.
func _drag(from: Vector2, to: Vector2) -> void:
    _view.mouse_position = from
    _tool.handle_input(_button(true))
    _view.mouse_position = to
    _tool.handle_input(InputEventMouseMotion.new())
    _tool.tick(0.016)
    _tool.handle_input(_button(false))


func _report() -> Dictionary:
    return _tool.capture_report(&"gradient", true)["gradient"]


func _texel(at: Vector2i) -> Color:
    return _texel_of(_document.active_layer, at)


## The texel at *at* of *layer*, transparent where it holds no chunk.
func _texel_of(layer: SaLayer, at: Vector2i) -> Color:
    @warning_ignore("integer_division")
    var grid := Vector2i(at.x / SaChunk.SIZE, at.y / SaChunk.SIZE)
    var texture := layer.get_field(grid)
    if texture == null:
        return Color.TRANSPARENT
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    return SaFieldSpec.decode_texel(
        bytes, texture.format, (at.y - grid.y * SaChunk.SIZE) * texture.size.x + (at.x - grid.x * SaChunk.SIZE)
    )


## One left button event. The tool reads the pointer off its view, not off the
## event, so the event carries no position.
func _button(pressed: bool) -> InputEventMouseButton:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = pressed
    return event


func _key(keycode: Key) -> InputEventKey:
    var event := InputEventKey.new()
    event.keycode = keycode
    event.pressed = true
    return event
