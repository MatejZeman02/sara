## A hidden layer adds nothing to the Graph docker.
##
## A photo showed the Oklab Cloud carrying colours of two hidden
## layers beside the strokes of the one shown. A red layer and a yellow one are
## painted into chunks of their own and one they share, red on top, and the red
## one is hidden. The cloud and the histogram are then read for red, before and
## after a stroke on the yellow layer, with the layer hidden before the first
## composite as when a document opens so, and hidden after it as when the
## painter hides it with the docker open. Each is read twice, once a sample a
## texel and once through a view zoomed out, where a sample averages a block of
## texels as the view does.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

const REQUIRES_GPU := true

const RED := Color(1.0, 0.0, 0.0, 1.0)
const YELLOW := Color(1.0, 1.0, 0.0, 1.0)

## The cloud keeps a cell's Oklab a as a sum of `(a / 0.4 * 0.5 + 0.5) * 255`,
## so red's mean is about 198 and yellow's about 105. A cell whose mean is over
## this holds red, alone or mixed into the cell.
const RED_A := 150.0


func _chunk() -> int:
    return SaChunk.SIZE


func _size() -> Vector2i:
    return Vector2i(_chunk() * 3, _chunk())


## Yellow below at grid positions 1 and 2, red above at 0 and 1, the active
## layer the yellow one, and nothing else shown.
func _easel() -> Array:
    var easel := SaEasel.create_default(_size())
    easel.compositor.set_registry(Fixtures.make_registries().blend_modes)
    var doc := easel.document
    var yellow := doc.get_node("Layer 1") as SaLayer
    for grid_pos: Vector2i in [Vector2i(1, 0), Vector2i(2, 0)]:
        yellow.get_or_create_chunk(grid_pos).clear(YELLOW)
    var red := SaLayerOps.new(doc).add()
    for grid_pos: Vector2i in [Vector2i(0, 0), Vector2i(1, 0)]:
        red.get_or_create_chunk(grid_pos).clear(RED)
    # The grey background a document is laid on would show under both, so it
    # is hidden and a chunk only red stores is clear once red is.
    for layer: SaLayer in SaLayerOps.new(doc).layers():
        if layer != red and layer != yellow:
            layer.visible = false
    doc.set_active_layer(yellow)
    doc.invalidate_chunks([Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)])
    return [easel, red, yellow]


func _composite(easel: SaEasel) -> void:
    easel.document.update_caches()
    easel.process_pending_composite()
    easel.flush()


## A stroke held on the yellow layer over the left half of grid position 2 and
## committed, which is a partial composite of the chunk it reaches.
func _stroke(easel: SaEasel) -> void:
    easel.document.begin_stroke(1.0, SaLayer.BLEND_MODE.NORMAL)
    var chunk := easel.document.stroke_layer.get_or_create_chunk(Vector2i(2, 0))
    chunk.clear(YELLOW)
    easel.document.invalidate_chunks([Vector2i(2, 0)])
    _composite(easel)
    easel.document.commit_stroke()
    _composite(easel)


## The counts of *mode_id* over the whole canvas, at *shown* samples across
## and down: the canvas's own size is a sample a texel, less is a view zoomed
## out.
func _counts(easel: SaEasel, mode_id: String, shown: Vector2i) -> PackedInt32Array:
    var plot := SaGraphPlot.new()
    var size := Vector2(_size())
    var ok := plot.run(
        easel.output,
        _size(),
        Vector2.ZERO,
        Vector2(size.x, 0.0),
        Vector2(0.0, size.y),
        easel.document.color_space,
        mode_id,
        shown
    )
    assert_true(ok, "The %s pass runs" % mode_id)
    return plot.read_counts()


## How many samples the cloud put in a cell that holds red.
func _red_in_cloud(counts: PackedInt32Array) -> int:
    var red := 0
    for cell in SaGraphPlot.PLANE:
        var count := counts[cell]
        if count > 0 and float(counts[2 * SaGraphPlot.PLANE + cell]) / float(count) > RED_A:
            red += count
    return red


## How many samples the histogram put where green is low, which yellow never
## is and red always is.
func _red_in_histogram(counts: PackedInt32Array) -> int:
    var red := 0
    for bin in int(SaGraphPlot.BINS * 0.5):
        red += counts[SaGraphPlot.BINS + bin]
    return red


func _no_red(easel: SaEasel, when: String) -> void:
    for shown: Vector2i in [_size(), Vector2i(Vector2(_size()) * 0.25)]:
        var how := "%s, %d samples across" % [when, shown.x]
        var cloud := _counts(easel, "cloud", shown)
        assert_true(cloud[0] >= 0, "the cloud is read")
        assert_eq(_red_in_cloud(cloud), 0, "No cell of the cloud holds red, %s" % how)
        assert_eq(_red_in_histogram(_counts(easel, "histogram", shown)), 0, "No bin of the histogram holds red, %s" % how)


## The suite's own reading of red, so a pass that finds none is not a reading
## that could find none.
func test_a_shown_red_layer_is_read_as_red() -> void:
    var made := _easel()
    var easel: SaEasel = made[0]
    _composite(easel)
    assert_true(_red_in_cloud(_counts(easel, "cloud", _size())) > 0, "The cloud holds red while the red layer shows")
    assert_true(_red_in_histogram(_counts(easel, "histogram", _size())) > 0, "and so does the histogram")
    easel.free()


## A texel the canvas shows nearly clear weighs its alpha rather than a whole
## sample: red at a hundredth over a chunk nothing else stores adds about a
## hundredth of the chunk's samples, where it once added every one of them.
func test_a_nearly_clear_texel_counts_by_its_alpha() -> void:
    var made := _easel()
    var easel: SaEasel = made[0]
    var red: SaLayer = made[1]
    red.get_or_create_chunk(Vector2i(0, 0)).clear(Color(1.0, 0.0, 0.0, 0.01))
    _composite(easel)
    var whole := _chunk() * _chunk()
    var found := _red_in_cloud(_counts(easel, "cloud", _size()))
    # Red stays opaque in the chunk it shares with yellow, so that chunk is all
    # red and the faint one adds its hundredth beside it.
    var faint := found - whole
    assert_true(
        faint > whole * 0.005 and faint < whole * 0.02,
        "A chunk of red at alpha 0.01 adds about a hundredth of its samples, %d of %d" % [faint, whole]
    )
    easel.free()


func test_a_layer_hidden_before_the_first_composite_adds_nothing() -> void:
    var made := _easel()
    var easel: SaEasel = made[0]
    SaLayerOps.new(easel.document).set_visible(made[1], false)
    _composite(easel)
    _no_red(easel, "hidden before the first composite")
    _stroke(easel)
    _no_red(easel, "and after a stroke on the yellow layer")
    easel.free()


func test_a_layer_hidden_after_a_composite_adds_nothing() -> void:
    var made := _easel()
    var easel: SaEasel = made[0]
    _composite(easel)
    SaLayerOps.new(easel.document).set_visible(made[1], false)
    _composite(easel)
    _no_red(easel, "hidden with the docker open")
    _stroke(easel)
    _no_red(easel, "and after a stroke on the yellow layer")
    easel.free()
