## Flip View Vertically costs what Flip View Horizontally does.
##
## A sweep on Linux logged `Sara stall: a frame took 2.2 s` at Ctrl+Shift+H on
## a painted canvas, and 1.1 s at the second press, with no such line for H. The
## cause was never found on the machine this was built on. There a vertical
## press was a longest frame of 16 to 46 ms, a horizontal one 23 to 54 ms and a
## window with no press in it 32 to 49 ms, in a document of 3000 by 2000 and in
## one of 6000 by 4000, with the Minimap docker open and closed, the pan and
## the brush tool, and the pointer over the canvas and off it (the scenario is
## `scenarios/flip-view-vertically-does-not-stall.json`). So this holds what
## the flip is meant to be and what the stall would break: a view flip is a
## move of the view and nothing else, whichever axis it takes.
##
## - It composites nothing and dispatches nothing, because a flip about the
##   middle of the viewport shows the same document rectangle it showed.
## - It touches no chunk and takes no undo step.
## - It is drawn the way a pan is, at half size for the frames it moves, the
##   same for both axes.
## - Flipped twice it is back exactly where it began.
## - The CPU a frame of it takes is within a frame's budget of the horizontal
##   one's, which is the line a 1.1 s second press would have crossed.
##
## A frame here is a call to the canvas's `_process`, which is what the engine
## calls once a frame: the runner cannot advance a frame, and an await drops
## every assertion after it.
extends "res://tests/test_framework.gd"

## A canvas builds an easel, and an easel composites.
const REQUIRES_GPU := true

const WINDOW := Vector2i(512, 384)
const CANVAS := Vector2i(2048, 1536)
const RED := Color(1.0, 0.0, 0.0, 1.0)

## One frame at sixty to the second, which is what a press may cost beyond the
## other axis's before it is a stall rather than noise.
const FRAME_BUDGET_USEC: int = 16667
## How many presses of each axis the cost is taken over, the median of which is
## what is compared.
const ROUNDS: int = 7

var _host: Node = null
var _setting_before: bool = false


## Parented to an autoload rather than to the root, because the runner calls
## this from its own `_ready` and a parent mid-`_ready` rejects `add_child`.
func before_each() -> void:
    _setting_before = SaSettings.half_size_view_while_moving
    SaSettings.half_size_view_while_moving = true
    _host = Node.new()
    _host.name = "S58TestHost"
    EventBus.add_child(_host)


func after_each() -> void:
    SaSettings.half_size_view_while_moving = _setting_before
    if _host != null:
        _host.free()
        _host = null


## A painted canvas: four chunks of the active layer red, the canvas panned off
## centre at a zoom of one, everything composited once and a frame run.
func _canvas() -> SaCanvas:
    var viewport := SubViewport.new()
    viewport.size = WINDOW
    _host.add_child(viewport)
    var canvas := SaCanvas.new()
    canvas.canvas_size = CANVAS
    canvas.easel = SaEasel.create_default(CANVAS, null, SaColorSpace.srgb())
    canvas.add_child(canvas.easel)
    viewport.add_child(canvas)
    canvas.scale = Vector2.ONE
    canvas.position = Vector2(-300.0, -200.0)
    var changed: Dictionary = {}
    for grid_pos: Vector2i in [Vector2i(1, 1), Vector2i(2, 1), Vector2i(1, 2), Vector2i(2, 2)]:
        var chunk := canvas.document.active_layer.get_or_create_field(grid_pos)
        GlobalShaderCompiler.get_rd().texture_clear(chunk.rid, RED, 0, 1, 0, 1)
        changed[grid_pos] = SaDocument.WHOLE_CHUNK
    canvas.document.invalidate_chunk_regions(changed)
    canvas.easel.process_pending_composite()
    canvas._process(0.0)
    return canvas


## One press of a flip as the engine frames it: the flip, the composite the
## frame runs and the canvas's own frame. Answers the microseconds it took.
static func _press(canvas: SaCanvas, horizontal: bool) -> int:
    var began := Time.get_ticks_usec()
    SaCanvasView.for_canvas(canvas).flip_view(horizontal)
    canvas.easel.process_pending_composite()
    canvas._process(0.0)
    return Time.get_ticks_usec() - began


static func _median(values: Array[int]) -> int:
    var sorted := values.duplicate()
    sorted.sort()
    return sorted[sorted.size() >> 1]


func test_a_vertical_flip_composites_nothing_and_dispatches_nothing() -> void:
    var canvas := _canvas()
    var easel := canvas.easel
    var composites := easel.composite_count
    var before := SaCompute.counters()
    var held := easel.backlog._regions.keys()

    _press(canvas, false)

    assert_eq(easel.composite_count, composites, "No composite ran for the flip")
    assert_eq(SaCompute.counters()["dispatches"], before["dispatches"], "and no compute pass was dispatched")
    assert_eq(easel.backlog._regions.keys(), held, "and the chunks held back past the window are the ones that were")
    var shown := Rect2(Vector2(300.0, 200.0), Vector2(WINDOW))
    assert_eq(canvas.shown_in_document(), shown, "The window shows the rectangle it showed")


func test_a_vertical_flip_touches_no_chunk_and_takes_no_undo_step() -> void:
    var canvas := _canvas()
    var document := canvas.document
    var layer := document.active_layer
    var held := layer.chunks.keys()
    var steps := document.history.step_count()
    var depth := document.history.position()

    _press(canvas, false)
    _press(canvas, false)

    assert_eq(layer.chunks.keys(), held, "The same chunks are allocated, none new and none dropped")
    assert_eq(document.history.step_count(), steps, "No history step was made")
    assert_eq(document.history.position(), depth, "and the history stands where it stood")
    assert_eq(document.canvas_size, CANVAS, "The document is the size it was")


func test_a_vertical_flip_flipped_back_is_where_it_began() -> void:
    var canvas := _canvas()
    var view := SaCanvasView.for_canvas(canvas)
    var scale := canvas.scale
    var position := canvas.position
    var rotation := canvas.rotation

    _press(canvas, false)
    assert_eq(view.get_flip(), Vector2(1.0, -1.0), "The view is flipped top to bottom and only that")
    assert_almost_eq(view.get_zoom(), 1.0, 0.0001, "at the zoom it had")
    _press(canvas, false)

    assert_eq(view.get_flip(), Vector2.ONE, "The second press puts it back the way round it was")
    assert_true(canvas.scale.is_equal_approx(scale), "at the scale it had")
    assert_true(canvas.position.is_equal_approx(position), "at the position it had")
    assert_almost_eq(canvas.rotation, rotation, 0.0001, "and the turn it had")


func test_both_flips_are_drawn_at_half_size_alike() -> void:
    var vertical := _canvas()
    _press(vertical, false)
    var down: Dictionary = vertical.capture_state()["half_size_view"]
    var horizontal := _canvas()
    _press(horizontal, true)
    var across: Dictionary = horizontal.capture_state()["half_size_view"]

    assert_true(down["active"], "A vertical flip is drawn at half size for the frames it moves")
    assert_eq(down["active"], across["active"], "as a horizontal one is")
    assert_eq(down["drawn_size"], across["drawn_size"], "at the same size")
    for _frame in SaHalfSizeView.REST_FRAMES:
        vertical._process(0.0)
    assert_false(vertical.capture_state()["half_size_view"]["active"], "and the full size comes back once the view rests")


func test_a_vertical_flip_costs_a_frame_budget_of_a_horizontal_one() -> void:
    var canvas := _canvas()
    # One of each first, which pays whatever is paid once.
    _press(canvas, true)
    _press(canvas, true)
    _press(canvas, false)
    _press(canvas, false)
    var across: Array[int] = []
    var down: Array[int] = []
    for _round in ROUNDS:
        across.append(_press(canvas, true))
        across.append(_press(canvas, true))
        down.append(_press(canvas, false))
        down.append(_press(canvas, false))
    var across_median := _median(across)
    var down_median := _median(down)
    assert_true(
        down_median <= across_median + FRAME_BUDGET_USEC,
        "A vertical press took %d us at the median, a horizontal one %d us" % [down_median, across_median]
    )
