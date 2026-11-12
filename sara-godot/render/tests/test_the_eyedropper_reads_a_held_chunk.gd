## The second suite: the eyedropper over a chunk the window left
## unshown reads the painted colour.
##
## A chunk painted while the window was elsewhere waits in the easel's backlog,
## and the output there still holds what it held before. The eyedropper reads
## the merged picture through `SaEasel.snapshot_merged`, which flushes the held
## chunks under its square first, so it picks the paint and not the stale
## output.
extends "res://tests/test_framework.gd"

## A canvas builds an easel, and the pick reads a snapshot back.
const REQUIRES_GPU := true

const StateEyedropperScript = preload("res://modules/sara-base-modules/base/tools/state_eyedropper.gd")

const WINDOW := Vector2i(512, 512)
const CANVAS := Vector2i(2048, 2048)
const PAINT := Color(0.9, 0.3, 0.1, 1.0)

var _host: Node = null


## Parented to an autoload rather than to the root, because the runner calls
## this from its own `_ready` and a parent mid-`_ready` rejects `add_child`.
func before_each() -> void:
    _host = Node.new()
    _host.name = "B2EyedropperTestHost"
    EventBus.add_child(_host)


func after_each() -> void:
    if _host != null:
        _host.free()
        _host = null


func test_the_eyedropper_over_a_held_chunk_reads_the_paint() -> void:
    var viewport := SubViewport.new()
    viewport.size = WINDOW
    _host.add_child(viewport)
    var canvas := SaCanvas.new()
    canvas.canvas_size = CANVAS
    canvas.easel = SaEasel.create_default(CANVAS, null, SaColorSpace.srgb())
    canvas.add_child(canvas.easel)
    viewport.add_child(canvas)
    canvas.scale = Vector2.ONE
    # The window over the far corner, and everything it reaches composited.
    canvas.position = -Vector2(CANVAS - WINDOW)
    var easel := canvas.easel
    easel.process_pending_composite()

    # The first corner painted where the window does not reach.
    var chunk := canvas.document.active_layer.get_or_create_field(Vector2i.ZERO)
    GlobalShaderCompiler.get_rd().texture_clear(chunk.rid, PAINT, 0, 1, 0, 1)
    canvas.document.invalidate_chunk_regions({Vector2i.ZERO: SaDocument.WHOLE_CHUNK})
    easel.process_pending_composite()
    assert_true(easel.backlog._regions.has(Vector2i.ZERO), "The painted chunk waits outside the window")
    var stale := SaExport.get_texture_image_float(easel.output).get_pixel(20, 20)
    assert_true(absf(stale.r - PAINT.r) > 0.1, "and the output there does not hold the paint yet")

    var eyedropper := StateEyedropperScript.new()
    eyedropper.surface = SaSurface.create(&"b2", easel, SaCanvasView.for_canvas(canvas))
    eyedropper.sample_from = StateEyedropperScript.SampleFrom.VIEW
    var picked: Color = eyedropper.pick_color_at_pos(Vector2(20, 20))
    assert_almost_eq(picked.r, PAINT.r, 0.01, "The pick reads the painted red")
    assert_almost_eq(picked.g, PAINT.g, 0.01, "its green")
    assert_almost_eq(picked.b, PAINT.b, 0.01, "and its blue")
    assert_false(easel.backlog._regions.has(Vector2i.ZERO), "The pick flushed the chunk under it")
    assert_true(easel.backlog._regions.has(Vector2i(1, 1)), "and nothing it did not read")
