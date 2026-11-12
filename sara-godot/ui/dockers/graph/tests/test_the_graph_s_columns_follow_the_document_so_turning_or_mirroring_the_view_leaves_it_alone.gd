## The graph's columns follow the document, so turning or
## mirroring the view leaves it alone.
##
## A photo showed the RGB Waveform with the view turned by -11° at
## 98 %: the traces filled the middle half of the width and the columns on
## both sides were empty, because a column was a column of the screen and the
## surround had columns of its own. A real canvas is put in a viewport and
## turned, mirrored and zoomed through its `SaCanvasView`, `view_of` reads the
## parallelogram it shows, and the plot bins a document of a horizontal
## gradient through it as the docker does.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

## The document, two chunks wide, and the viewport the canvas is shown in,
## large enough that the whole document fits at `WHOLE_ZOOM` at any turn.
const DOCUMENT := Vector2i(512, 256)
const VIEWPORT := Vector2i(900, 900)
const WHOLE_ZOOM := 1.5

## Where the gradient starts and ends, in the green channel, which an sRGB
## document hands the waveform as it is.
const LEFT_END := 0.25
const RIGHT_END := 0.75

## What a texel the view leaves out of sight holds in the second suite's
## document, a green no texel of the gradient has.
const HIDDEN := Color(1.0, 0.0, 1.0, 1.0)

const GREEN := 1

var _host: Node = null
var _easel: SaEasel = null


func before_each() -> void:
    _host = Node.new()
    _host.name = "U155Host"
    EventBus.add_child(_host)


func after_each() -> void:
    if _easel != null:
        _easel.free()
        _easel = null
    if _host != null:
        _host.free()
        _host = null


## A canvas the size of the document in a viewport, in the tree.
func _canvas() -> SaCanvas:
    var viewport := SubViewport.new()
    viewport.size = VIEWPORT
    _host.add_child(viewport)
    var canvas := SaCanvas.new()
    canvas.canvas_size = DOCUMENT
    viewport.add_child(canvas)
    return canvas


## Turns the view by *degrees*, mirrors it when *mirrored*, zooms it to
## *zoom* and puts the document point *centre* in the viewport's middle.
func _look(canvas: SaCanvas, degrees: float, mirrored: bool, zoom: float, centre: Vector2) -> SaCanvasView:
    var view := SaCanvasView.for_canvas(canvas)
    view.set_zoom(zoom)
    view.set_flip(Vector2(-1.0 if mirrored else 1.0, 1.0))
    view.set_rotation(deg_to_rad(degrees))
    var middle := Vector2(VIEWPORT) * 0.5
    view.set_pan(view.get_pan() + middle - view.document_to_screen(centre))
    return view


## An sRGB document holding *image*, composited.
func _document(image: Image) -> SaEasel:
    var easel := SaEasel.create_default(DOCUMENT, null, SaColorSpace.srgb())
    for layer: SaLayer in SaLayerOps.new(easel.document).layers():
        layer.visible = false
    SaImageImport.place(easel.document, image, "Gradient", SaColorSpace.srgb())
    easel.request_full_composite()
    easel.process_pending_composite()
    easel.flush()
    return easel


## The gradient's green at document x *x*.
static func _ramp(x: float) -> float:
    return LEFT_END + (RIGHT_END - LEFT_END) * clampf(x / float(DOCUMENT.x), 0.0, 1.0)


func _gradient() -> Image:
    var image := Image.create_empty(DOCUMENT.x, DOCUMENT.y, false, Image.FORMAT_RGBAF)
    for x in DOCUMENT.x:
        var green := _ramp(float(x) + 0.5)
        for y in DOCUMENT.y:
            image.set_pixel(x, y, Color(0.5, green, 0.5, 1.0))
    return image


## The fixed grid's counts of *mode_id* through what *canvas*'s view shows,
## at a sample a pixel of the viewport, as `GraphDocker.refresh` asks.
func _counts(canvas: SaCanvas, mode_id: String) -> PackedInt32Array:
    var mapping := SaReductionService.view_of(canvas, DOCUMENT)
    var plot := SaGraphPlot.new()
    var ok := plot.run(
        _easel.output,
        DOCUMENT,
        Vector2(mapping[0], mapping[1]),
        Vector2(mapping[2], mapping[3]),
        Vector2(mapping[4], mapping[5]),
        _easel.document.color_space,
        mode_id,
        VIEWPORT
    )
    assert_true(ok, "The %s pass runs" % mode_id)
    return plot.read_counts()


## The waveform's and the parade's counts, which share their planes, and the
## histogram's rows.
func _graphs(canvas: SaCanvas) -> Dictionary:
    var trace := _counts(canvas, "waveform").slice(0, 3 * SaGraphPlot.PLANE)
    var parade := _counts(canvas, "parade").slice(0, 3 * SaGraphPlot.PLANE)
    var histogram := _counts(canvas, "histogram").slice(0, 4 * SaGraphPlot.BINS)
    return {"waveform": trace, "parade": parade, "histogram": histogram}


## The mean green bin of the waveform's column *column*, -1 when it is empty.
func _mean_green(counts: PackedInt32Array, column: int) -> float:
    var total := 0
    var weighted := 0.0
    for value in SaGraphPlot.BINS:
        var count: int = counts[(GREEN * SaGraphPlot.COLUMNS + column) * SaGraphPlot.BINS + value]
        total += count
        weighted += float(count * value)
    return weighted / float(total) if total > 0 else -1.0


static func _bin(value: float) -> float:
    return clampf(value, 0.0, 1.0) * float(SaGraphPlot.BINS - 1)


## The whole document shown at 0°, at -11° as the photo's, at 90° and
## mirrored, plain and turned: every graph's counts are the same as at 0°, and
## the first column holds the gradient's left end.
func test_turning_or_mirroring_a_view_of_the_whole_document_changes_no_count() -> void:
    _easel = _document(_gradient())
    var canvas := _canvas()
    var centre := Vector2(DOCUMENT) * 0.5
    _look(canvas, 0.0, false, WHOLE_ZOOM, centre)
    var upright := _graphs(canvas)
    var left := _mean_green(upright["waveform"], 0)
    var right := _mean_green(upright["waveform"], SaGraphPlot.COLUMNS - 1)
    var left_bin := _bin(LEFT_END)
    assert_true(absf(left - left_bin) <= 1.5, "The first column holds the left end, %.1f against %.1f" % [left, left_bin])
    assert_true(absf(right - _bin(RIGHT_END)) <= 1.5, "and the last the right end, %.1f" % right)
    var empty := 0
    for column in SaGraphPlot.COLUMNS:
        if _mean_green(upright["waveform"], column) < 0.0:
            empty += 1
    assert_eq(empty, 0, "and no column is empty, since the surround has none")
    for spec: Array in [[-11.0, false], [90.0, false], [0.0, true], [-11.0, true], [90.0, true]]:
        _look(canvas, spec[0], spec[1], WHOLE_ZOOM, centre)
        var turned := _graphs(canvas)
        var named := "%s° %s" % [spec[0], "mirrored" if spec[1] else "plain"]
        for mode_id: String in ["waveform", "parade", "histogram"]:
            assert_eq(turned[mode_id], upright[mode_id], "The %s at %s is the one at 0°" % [mode_id, named])
        var first := _mean_green(turned["waveform"], 0)
        assert_true(absf(first - _bin(LEFT_END)) <= 1.5, "and its first column holds the left end at %s, %.1f" % [named, first])


## Zoomed in on the document's left edge and turned, so part of the screen is
## the surround and the box of the shown part has corners the screen does
## not. Every texel more than two texels outside what the view shows is
## `HIDDEN`, whose green is 0: no bin may hold it, the histogram counts the
## samples inside both the document and the view and no other, and every
## waveform column holds the gradient's values of its own run of x.
func test_a_turned_view_zoomed_in_bins_the_shown_part_of_the_document_only() -> void:
    var canvas := _canvas()
    var zoom := 4.0
    var centre := Vector2(40.0, float(DOCUMENT.y) * 0.5)
    var view := _look(canvas, -30.0, true, zoom, centre)
    var mapping := SaReductionService.view_of(canvas, DOCUMENT)
    var origin := Vector2(mapping[0], mapping[1])
    var span_x := Vector2(mapping[2], mapping[3])
    var span_y := Vector2(mapping[4], mapping[5])
    var back := Transform2D(span_x, span_y, origin).affine_inverse()
    var margin := Vector2(2.0 / span_x.length(), 2.0 / span_y.length())
    var image := _gradient()
    for x in DOCUMENT.x:
        for y in DOCUMENT.y:
            var at := back * Vector2(float(x) + 0.5, float(y) + 0.5)
            if at.x < -margin.x or at.y < -margin.y or at.x > 1.0 + margin.x or at.y > 1.0 + margin.y:
                image.set_pixel(x, y, HIDDEN)
    _easel = _document(image)
    assert_true(view.get_zoom() == zoom, "The view is zoomed in")

    var histogram := _counts(canvas, "histogram")
    var green_row := GREEN * SaGraphPlot.BINS
    assert_eq(histogram[green_row], 0, "No sample read a texel the view leaves out of sight")
    var binned := 0
    for value in SaGraphPlot.BINS:
        binned += histogram[green_row + value]

    var box := SaGraphPlot.shown_box(origin, span_x, span_y, DOCUMENT)
    var grid := SaGraphPlot.samples_over(box, VIEWPORT, span_x, span_y)
    assert_true(Rect2(Vector2.ZERO, Vector2(DOCUMENT)).encloses(box), "The samples' box lies inside the document")
    var expected := 0
    for j in grid.y:
        for i in grid.x:
            var at := box.position + box.size * (Vector2(float(i), float(j)) + Vector2(0.5, 0.5)) / Vector2(grid)
            var on_screen := back * at
            if on_screen.x >= 0.0 and on_screen.y >= 0.0 and on_screen.x <= 1.0 and on_screen.y <= 1.0:
                expected += 1
    var all := grid.x * grid.y
    assert_true(expected > 0 and expected < all, "The view shows part of the box, %d of %d" % [expected, all])
    var slack := ceili(float(expected) * 0.005)
    assert_true(absi(binned - expected) <= slack, "The pass binned the shown samples alone, %d against %d" % [binned, expected])

    var trace := _counts(canvas, "waveform")
    var strays := 0
    for column in SaGraphPlot.COLUMNS:
        var low := _bin(_ramp(box.position.x + box.size.x * (float(column) - 0.5) / float(SaGraphPlot.COLUMNS - 1))) - 1.0
        var high := _bin(_ramp(box.position.x + box.size.x * (float(column) + 0.5) / float(SaGraphPlot.COLUMNS - 1))) + 1.0
        for value in SaGraphPlot.BINS:
            var count: int = trace[(GREEN * SaGraphPlot.COLUMNS + column) * SaGraphPlot.BINS + value]
            if count > 0 and (float(value) < low or float(value) > high):
                strays += count
    assert_eq(strays, 0, "Every column holds the gradient of its own run of document x and nothing else")
