## Lens Correction reaches the amount it is asked for on a
## canvas of any size. A texel's read that moves past a chunk, 10.2 percent on a
## photograph 4000 pixels wide, is not held back by the slider. Past that move
## the filter records a pass that reads the whole node, whose `carries` answers the band of
## the canvas whose reads land in a changed rectangle.
##
## Three things are held here. The band is worked out on the CPU against every
## texel of a small canvas: each texel whose bilinear read touches the changed
## rectangle stands inside it, at either sign, with the crop and without, and
## for a rectangle on the canvas's edge. The attached filter on a canvas six
## chunks wide at 30 percent, where the corner moves 326 pixels, shows what
## Apply bakes into the layer. And a small square painted under it redraws a
## few of the canvas's 36 chunks, shows where the model carries it, and reads
## as a composite of everything does.
##
## SPDX-License-Identifier: GPL-3.0-or-later
extends "res://tests/test_framework.gd"

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")

## Real dispatches into real chunks.
const REQUIRES_GPU := true

const OWNER := &"sara-base-modules"
## Six chunks on a side, whose half diagonal is 1086 pixels, so 30 percent
## moves a corner 326 and the pass reads the whole node.
const CHUNKS := 6
## The canvas the band is checked against texel by texel.
const SMALL := Vector2i(400, 300)
## The changed rectangles of the band's check on [const SMALL]: near the
## middle, out towards a corner, on the left edge and in the bottom right corner.
const CHANGES: Array[Rect2i] = [Rect2i(190, 140, 8, 8), Rect2i(330, 40, 10, 6), Rect2i(0, 120, 6, 12), Rect2i(392, 292, 8, 8)]
const GREEN := Color(0.1, 0.9, 0.2, 1.0)
## The grid painted on the layer, its spacing and its lines' width.
const GRID := 24
const LINE := 2
## The stride of the texels two whole reads of the canvas are weighed at, odd
## so it crosses the grid's lines at every phase.
const EVERY := 5

var _easel: SaEasel = null
var _layer: SaLayer = null
var _key: StringName = &""


func after_each() -> void:
    _layer = null
    if _easel != null:
        _easel.free()
    _easel = null


## The texels of a canvas of *canvas* pixels whose read touches *area*, under
## *amount* in percent with the switch at *crop*, worked out from the model
## here rather than from the filter: a texel at its middle stands at its
## distance over the crop's factor and reads at (1 - k r²) times that, kept to
## the canvas, and a bilinear read takes the texel it falls on and the next.
static func _readers(canvas: Vector2i, area: Rect2i, amount: float, crop: bool) -> Array[Vector2i]:
    var bend := amount / 100.0
    var scale := SaLensCorrectionFilter.zoom(bend, canvas, crop)
    var centre := Vector2(canvas) * 0.5
    var half := centre.length()
    var last := Vector2(canvas - Vector2i.ONE)
    var found: Array[Vector2i] = []
    for y in canvas.y:
        for x in canvas.x:
            var seen := (Vector2(x, y) + Vector2(0.5, 0.5) - centre) / scale
            var r := seen.length() / half
            var read := (centre + seen * (1.0 - bend * r * r) - Vector2(0.5, 0.5)).clamp(Vector2.ZERO, last)
            var first := Vector2i(read.floor())
            if area.intersects(Rect2i(first, Vector2i(2, 2))):
                found.append(Vector2i(x, y))
    return found


func test_the_band_a_change_is_carried_to_holds_every_texel_that_reads_it() -> void:
    for amount: float in [30.0, -30.0]:
        for crop: bool in [false, true]:
            var bend := amount / 100.0
            var scale := SaLensCorrectionFilter.zoom(bend, SMALL, crop)
            for area: Rect2i in CHANGES:
                var said := "At %+.0f with Crop to fill %s, %s" % [amount, "on" if crop else "off", area]
                var bands := SaLensCorrectionFilter.reading(area, SMALL, bend, scale)
                assert_eq(bands.size(), 1, "%s is carried to one band" % said)
                if bands.is_empty():
                    continue
                var band := bands[0]
                var missed := 0
                var first := ""
                for reader: Vector2i in _readers(SMALL, area, amount, crop):
                    if not band.has_point(reader):
                        missed += 1
                        if first.is_empty():
                            first = str(reader)
                assert_eq(missed, 0, "%s: every texel reading it stands in %s, the first missed at %s" % [said, band, first])


## A change near the middle is carried to a band about its own size, and not to
## the canvas, which is what keeps a stroke's redraw small.
func test_a_change_away_from_the_edges_is_carried_to_a_band_of_its_own_size() -> void:
    var area := CHANGES[0]
    var bend := 0.3
    var band := SaLensCorrectionFilter.reading(area, SMALL, bend, 1.0)[0]
    assert_true(band.size.x < 40 and band.size.y < 40, "An 8 pixel square near the middle is read by a band %s" % band)


## The Background as a grid over every other chunk, the rest held by nothing,
## with the filter registered.
func _bench() -> void:
    _easel = Bench.easel(Vector2i(SaChunk.SIZE, SaChunk.SIZE) * CHUNKS)
    var filter := SaLensCorrectionFilter.new()
    _easel.compositor.filter_chain.registry.register(filter, OWNER)
    _key = SaFilterRegistry.key_for(OWNER, filter)
    _layer = _easel.document.get_node("Background") as SaLayer
    for grid_pos: Vector2i in _layer.chunks.keys():
        _layer.chunks.erase(grid_pos)
    for y in CHUNKS:
        for x in CHUNKS:
            if (x + y) % 2 == 0:
                _paint_grid(Vector2i(x, y))


func _paint_grid(grid_pos: Vector2i) -> void:
    var chunk := _layer.get_or_create_chunk(grid_pos)
    var side := chunk.pixel_size()
    var values := PackedFloat32Array()
    values.resize(side * side * 4)
    for py in side:
        for px in side:
            var at := grid_pos * SaChunk.SIZE + Vector2i(px, py)
            var on := at.x % GRID < LINE or at.y % GRID < LINE
            var i := (py * side + px) * 4
            values[i] = 1.0 if on else 0.2
            values[i + 1] = float(at.x) / (SaChunk.SIZE * CHUNKS)
            values[i + 2] = float(at.y) / (SaChunk.SIZE * CHUNKS)
            values[i + 3] = 1.0
    var texture := chunk.field(SaFieldSpec.ALBEDO)
    var bytes := values.to_byte_array()
    if texture.format != RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT:
        var image := Image.create_from_data(side, side, false, Image.FORMAT_RGBAF, bytes)
        image.convert(Image.FORMAT_RGBAH)
        bytes = image.get_data()
    GlobalShaderCompiler.get_rd().texture_update(texture.rid, 0, bytes)


func _bytes() -> PackedByteArray:
    return GlobalShaderCompiler.get_rd().texture_get_data(_easel.output.rid, 0)


## The largest difference of any channel between two reads of the output, at
## every [const EVERY]th texel of every [const EVERY]th row.
func _worst(one: PackedByteArray, other: PackedByteArray) -> float:
    var format := _easel.output.format
    var size := _easel.output.size
    var worst := 0.0
    for y in range(0, size.y, EVERY):
        for x in range(0, size.x, EVERY):
            var i := y * size.x + x
            var a := SaFieldSpec.decode_texel(one, format, i)
            var b := SaFieldSpec.decode_texel(other, format, i)
            worst = maxf(worst, maxf(maxf(absf(a.r - b.r), absf(a.g - b.g)), maxf(absf(a.b - b.b), absf(a.a - b.a))))
    return worst


func _check_attached_is_baked(amount: float) -> void:
    _bench()
    var settings := {"amount": amount, String(SaLensCorrectionFilter.CROP): false}
    SaFilterOps.new(_easel.document).attach(_layer, _key, settings)
    Bench.composite(_easel)
    var record := _layer.filters[0]
    var recorded := record.cached_pass as SaNeighbourhoodPass
    assert_true(recorded != null and recorded.whole(), "At %+.0f the attached pass reads the whole node" % amount)
    var attached := _bytes()
    _easel.free()
    _bench()
    var filter := SaLensCorrectionFilter.new()
    filter.set_parameters(settings)
    var ctx := SaFilterContext.new(_easel.document, _layer, OWNER, filter.title(), false)
    assert_true(SaFilterApply.call_run(filter, ctx), "The run records a pass")
    assert_true(SaFilterApply.apply(ctx, filter.title()), "which Apply bakes into the layer")
    Bench.composite(_easel)
    var baked := _bytes()
    var worst := _worst(attached, baked)
    assert_true(worst < 1e-3, "At %+.0f the attached composite is the baked layer's, off by %f" % [amount, worst])


func test_attached_and_baked_agree_at_the_strongest_amount_above_nought() -> void:
    _check_attached_is_baked(30.0)


func test_attached_and_baked_agree_at_the_strongest_amount_below_nought() -> void:
    _check_attached_is_baked(-30.0)


## Paints *area*, in document pixels inside one chunk the layer holds, green,
## and redraws what that dirtied, answering how many dispatches of the whole
## kernel the redraw took.
func _paint(area: Rect2i) -> int:
    var grid_pos := Vector2i((Vector2(area.position) / SaChunk.SIZE).floor())
    var local := Rect2i(area.position - grid_pos * SaChunk.SIZE, area.size)
    var texture := _layer.get_or_create_chunk(grid_pos).field(SaFieldSpec.ALBEDO)
    var rd := GlobalShaderCompiler.get_rd()
    var bytes := rd.texture_get_data(texture.rid, 0)
    var texel := SaFieldSpec.BYTES_PER_TEXEL.get(texture.format, 16) as int
    var one := SaTexture.new(Vector2i.ONE, texture.format)
    one.clear(GREEN)
    var green := rd.texture_get_data(one.rid, 0)
    for y in range(local.position.y, local.end.y):
        for x in range(local.position.x, local.end.x):
            var at := (y * texture.size.x + x) * texel
            for i in texel:
                bytes[at + i] = green[i]
    rd.texture_update(texture.rid, 0, bytes)
    _easel.document.invalidate_chunk_regions({grid_pos: local})
    var before := _tally()
    _easel.process_pending_composite()
    return _tally() - before


static func _tally() -> int:
    var count := 0
    for key: String in SaCompute.by_kernel:
        if key.ends_with("/" + SaLensCorrectionFilter.WHOLE_KERNEL):
            count += int((SaCompute.by_kernel[key] as Dictionary)["dispatches"])
    return count


## A square painted out towards the bottom right corner, in chunk (4, 4), shows
## further out along the diagonal, where a texel at 30 percent reads it, and the
## redraw runs the kernel on a few chunks of the 36 and reads as a composite of
## everything does.
func test_a_square_painted_under_it_redraws_where_it_lands_and_nothing_else() -> void:
    _bench()
    SaFilterOps.new(_easel.document).attach(_layer, _key, {"amount": 30.0, String(SaLensCorrectionFilter.CROP): false})
    Bench.composite(_easel)
    var square := Rect2i(1100, 1100, 16, 16)
    var took := _paint(square)
    assert_true(took > 0, "The kernel ran")
    assert_true(
        took <= 8, "on %d dispatches, where a redraw of the picture is one a chunk at least, %d" % [took, CHUNKS * CHUNKS]
    )
    var canvas := Vector2(_easel.document.canvas_size)
    var centre := canvas * 0.5
    var away := Vector2(square.get_center()) - centre
    var half := centre.length()
    var lands := SaLensCorrectionFilter.read_by(centre + away, centre, half, 0.3, 1.0)
    var shown := Bench.texel(_easel.output, Vector2i(lands.round()))
    assert_true(
        lands.distance_to(centre + away) > 20.0, "The model carries the square's middle %s to %s" % [centre + away, lands]
    )
    assert_true(absf(shown.g - GREEN.g) < 0.05 and absf(shown.r - GREEN.r) < 0.05, "and the green shows there: %s" % shown)
    var redrawn := _bytes()
    Bench.composite(_easel)
    assert_true(redrawn == _bytes(), "The redraw is the bytes a composite of everything gives")
