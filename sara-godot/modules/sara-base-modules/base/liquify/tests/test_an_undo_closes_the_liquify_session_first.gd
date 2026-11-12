## "the liquify tool doesn't work with Undo. After and undo and
## new liquify, weird square seam appeared."
##
## A session stays open until Enter, and Ctrl+Z went past it to the step under
## it, the stroke the painter pushed. The session went on holding originals of
## a picture that was no longer there, and the next push drew its chunks from
## them. An undo now asks the tool machine to close the session first, so the
## push is the step the undo takes back.
##
## A stroke across the seam between the first two chunks is one history step,
## a push across the same seam opens the session, an undo, and a second push.
## The layer has to end where the stroke and the second push alone leave it,
## which a fresh document measures.
extends "res://tests/test_framework.gd"

## Chunks are real textures, so this needs a RenderingDevice.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")

const CANVAS := Vector2i(1024, 512)
## A stripe painted with no history under the stroke, far from the brush, and
## the stroke's own stripe across the seam at x 256.
const GROUND := Vector2i(100, 104)
const STROKE := Vector2i(248, 264)
const ROW: int = 128
const RED := Color(0.9, 0.1, 0.1, 1.0)
## The two pushes along the row, the first to the left and the second to the right.
const FIRST_FROM := Vector2(256.0, ROW)
const FIRST_TO := Vector2(240.0, ROW)
const SECOND_FROM := Vector2(256.0, ROW)
const SECOND_TO := Vector2(270.0, ROW)

var _surface: SaSurface = null
var _machine: ToolMachine = null
var _canvas: SaCanvas = null


func after_each() -> void:
    if _canvas != null:
        _canvas.easel = null
        _canvas.free()
    _canvas = null
    if _surface != null:
        Fixtures.teardown(_surface, _machine)
    _surface = null
    _machine = null


static func _image_format(texture: SaTexture) -> Image.Format:
    return Image.FORMAT_RGBAH if texture.format == RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT else Image.FORMAT_RGBAF


## A fresh document whose active layer holds the ground stripe, and with
## *stroke* the stroke's stripe as one history step over it. The machine is on
## liquify at full strength.
func _open(stroke: bool) -> SaLayer:
    if _surface != null:
        Fixtures.teardown(_surface, _machine)
    _surface = Fixtures.make_surface(CANVAS)
    _machine = Fixtures.make_bound_machine(_surface)
    var doc := _surface.get_document()
    var layer := SaLayerOps.new(doc).add(&"", null, 1.0)
    doc.active_layer = layer
    _paint(layer, [GROUND])
    if stroke:
        var state: Dictionary = {}
        for gx in 2:
            var grid_pos := Vector2i(gx, 0)
            var local := Rect2i(STROKE.x - gx * SaChunk.SIZE, 0, STROKE.y - STROKE.x, SaChunk.SIZE)
            local = local.intersection(Rect2i(0, 0, SaChunk.SIZE, SaChunk.SIZE))
            state[grid_pos] = SaChunkDelta.capture(layer.chunks[grid_pos], local)
        _paint(layer, [GROUND, STROKE])
        doc.record_pixel_step("Paint", layer, state)
    _machine.set_active_tool(&"liquify")
    _machine.active_tool.settings.set(&"strength", 1.0)
    return layer


## Writes the top row of chunks whole, red where one of *stripes* covers x.
func _paint(layer: SaLayer, stripes: Array) -> void:
    for gx in 2:
        var grid_pos := Vector2i(gx, 0)
        var chunk := layer.get_or_create_chunk(grid_pos)
        var texture := chunk.albedo()
        var image := Image.create_empty(SaChunk.SIZE, SaChunk.SIZE, false, _image_format(texture))
        for x in SaChunk.SIZE:
            var at := gx * SaChunk.SIZE + x
            var inside := false
            for stripe: Vector2i in stripes:
                inside = inside or (at >= stripe.x and at < stripe.y)
            for y in SaChunk.SIZE:
                image.set_pixel(x, y, RED if inside else Color(0.0, 0.0, 0.0, 0.0))
        GlobalShaderCompiler.get_rd().texture_update(texture.rid, 0, image.get_data())
        layer.mark_unresolved(grid_pos)
    _surface.get_document().invalidate_chunks(layer.chunks.keys())


func _push(from: Vector2, to: Vector2) -> void:
    var tool: ToolState = _machine.active_tool
    tool.call(&"press", from)
    tool.call(&"drag_to", to)
    tool.call(&"release")


## The alpha of the top row of chunks, one value a pixel, rows first.
func _alpha(layer: SaLayer) -> PackedFloat32Array:
    var width := SaChunk.SIZE * 2
    var alpha := PackedFloat32Array()
    alpha.resize(width * SaChunk.SIZE)
    for gx in 2:
        var chunk: SaChunk = layer.chunks.get(Vector2i(gx, 0), null)
        if chunk == null:
            continue
        var texture := chunk.albedo()
        var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
        var texels := Image.create_from_data(SaChunk.SIZE, SaChunk.SIZE, false, _image_format(texture), bytes)
        for y in SaChunk.SIZE:
            for x in SaChunk.SIZE:
                alpha[y * width + gx * SaChunk.SIZE + x] = texels.get_pixel(x, y).a
    return alpha


## The largest difference between two pictures of the top row.
static func _farthest(a: PackedFloat32Array, b: PackedFloat32Array) -> float:
    var most := 0.0
    for i in a.size():
        most = maxf(most, absf(a[i] - b[i]))
    return most


## How much more than *fresh* any texel of *alpha* differs from its
## neighbour across the seam at x 256. The seam the note saw is a chunk drawn
## from originals the rest of the layer no longer matches.
static func _seam_excess(alpha: PackedFloat32Array, fresh: PackedFloat32Array) -> float:
    var width := SaChunk.SIZE * 2
    var most := 0.0
    for y in SaChunk.SIZE:
        var at := y * width + SaChunk.SIZE
        var step := absf(alpha[at] - alpha[at - 1])
        var allowed := absf(fresh[at] - fresh[at - 1])
        most = maxf(most, step - allowed)
    return most


## What the stroke and the second push alone leave, on a document of its own.
func _fresh_alpha() -> PackedFloat32Array:
    var layer := _open(true)
    _push(SECOND_FROM, SECOND_TO)
    return _alpha(layer)


## With the session open, Ctrl+Z takes back the push and the stroke stays.
func test_an_undo_with_a_session_open_takes_back_the_push_and_not_the_stroke() -> void:
    var fresh := _fresh_alpha()
    var layer := _open(true)
    var stroked := _alpha(layer)
    var doc := _surface.get_document()
    _push(FIRST_FROM, FIRST_TO)
    assert_true(_farthest(_alpha(layer), stroked) > 0.5, "The first push moved the stroke")

    _machine.close_session()
    assert_true(doc.undo(), "The undo after the hook has a step to take")
    assert_almost_eq(_farthest(_alpha(layer), stroked), 0.0, 0.001, "and the step it took is the push, the stroke stands")

    _push(SECOND_FROM, SECOND_TO)
    var alpha := _alpha(layer)
    assert_almost_eq(_farthest(alpha, fresh), 0.0, 0.001, "The second push lands as on a document that never had the first")
    assert_almost_eq(_seam_excess(alpha, fresh), 0.0, 0.001, "and draws no seam along the chunk's edge")


## The same through the chord, the way a keyboard sends Ctrl+Z to the router
## the main window hands every unhandled key to.
func test_ctrl_z_closes_the_session_before_it_undoes() -> void:
    var fresh := _fresh_alpha()
    var layer := _open(true)
    var stroked := _alpha(layer)
    var stroke_step := _surface.get_document().undo_redo.get_current_action()
    var router := ShortcutRouter.new()
    _canvas = SaCanvas.new()
    _canvas.easel = _surface.easel
    router.canvas_provider = func() -> SaCanvas: return _canvas
    router.tool_machine_provider = func() -> ToolMachine: return _machine
    _push(FIRST_FROM, FIRST_TO)

    var chord := InputEventKey.new()
    chord.keycode = KEY_Z
    chord.physical_keycode = KEY_Z
    chord.key_label = KEY_Z
    chord.ctrl_pressed = true
    chord.pressed = true
    assert_eq(router._handle_history(chord), &"edit_undo", "Ctrl+Z is the undo")
    assert_almost_eq(_farthest(_alpha(layer), stroked), 0.0, 0.001, "and what it took back is the push")
    var at := _surface.get_document().undo_redo.get_current_action()
    assert_eq(at, stroke_step, "with the stroke still the step the stack stands on")

    _push(SECOND_FROM, SECOND_TO)
    var alpha := _alpha(layer)
    assert_almost_eq(_farthest(alpha, fresh), 0.0, 0.001, "The second push lands as on a document that never had the first")
    assert_almost_eq(_seam_excess(alpha, fresh), 0.0, 0.001, "and draws no seam along the chunk's edge")
    router.free()


## The same through the Undo History docker: a press on the stroke's row, the
## row the stack already stands on while the session is open, goes back to the
## stroke, which it could not when the session was nowhere in the history.
func test_the_strokes_row_in_the_undo_history_takes_back_the_push() -> void:
    var fresh := _fresh_alpha()
    var layer := _open(true)
    var stroked := _alpha(layer)
    var doc := _surface.get_document()
    var stroke_step := doc.undo_redo.get_current_action()
    _push(FIRST_FROM, FIRST_TO)
    assert_eq(doc.undo_redo.get_current_action(), stroke_step, "With the session open the stack stands on the stroke")

    assert_eq(UndoDocker.walk(doc, _machine, stroke_step), -1, "A press on the stroke's row goes back one step, the push's")
    assert_almost_eq(_farthest(_alpha(layer), stroked), 0.0, 0.001, "and leaves the stroke")

    _push(SECOND_FROM, SECOND_TO)
    var alpha := _alpha(layer)
    assert_almost_eq(_farthest(alpha, fresh), 0.0, 0.001, "The second push lands as on a document that never had the first")
    assert_almost_eq(_seam_excess(alpha, fresh), 0.0, 0.001, "and draws no seam along the chunk's edge")


## An undo with no session open is the plain undo it always was.
func test_with_no_session_open_the_undo_takes_the_stroke() -> void:
    var layer := _open(true)
    var doc := _surface.get_document()
    assert_false(_machine.close_session(), "No session, nothing to close")
    assert_true(doc.undo(), "The undo takes a step")
    assert_true(_alpha(layer)[ROW * SaChunk.SIZE * 2 + SaChunk.SIZE] < 0.01, "and the step is the stroke")
