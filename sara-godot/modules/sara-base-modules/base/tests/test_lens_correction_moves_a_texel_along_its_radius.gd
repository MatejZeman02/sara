## Lens Correction moves every texel along its radius from the
## document's centre by the first term of the radial model, so a single white
## texel at the centre stays where it was and three along one diagonal land
## where the model puts them, outwards above nought and inwards below it, on a
## layer that holds the document's top left chunk and nothing else. The
## filter attached agrees with the layer baked over paint that crosses a chunk
## edge, and on a canvas too wide for a halo to reach the amount the pass
## reads the whole node instead.
##
## SPDX-License-Identifier: GPL-3.0-or-later
extends "res://tests/test_framework.gd"

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")
const Fixtures = preload("res://tests/fixtures.gd")

## Real dispatches into real chunks.
const REQUIRES_GPU := true

const OWNER := &"sara-base-modules"
## A document two chunks wide and high, whose centre is the corner four chunks
## share.
const CHUNKS := 2
## The amount every reading here runs at, in percent, and either way.
const AMOUNT := 20.0
## How far along the diagonal towards the top left corner each lone texel sits
## from the one at the centre, in texels on each axis.
const ALONG: Array[int] = [40, 100, 160]
## The texel whose corner is the document's centre, up and to the left of it.
const CENTRE := Vector2i(255, 255)
## How far round the expected place the texels are weighed, on each side.
const WINDOW := 5
## The spacing of the grid painted across the chunk edge, and its lines' width.
const GRID := 24
const LINE := 2
## A photograph 4000 by 3000, whose half diagonal is 2500 pixels, so a halo
## reaches 255 over 2500 of it, a little over ten percent.
const PHOTO := Vector2i(4000, 3000)

var _easel: SaEasel = null
var _document: SaDocument = null
var _filter: SaLensCorrectionFilter = null
var _key: StringName = &""


func before_each() -> void:
    _make_easel()


func after_each() -> void:
    _easel.free()
    _easel = null
    _document = null
    _filter = null


func _make_easel() -> void:
    _easel = SaEasel.create_default(Vector2i(SaChunk.SIZE, SaChunk.SIZE) * CHUNKS)
    _easel.compositor.set_registry(Fixtures.make_registries().blend_modes)
    var registry := SaFilterRegistry.new()
    _filter = SaLensCorrectionFilter.new()
    registry.register(_filter, OWNER)
    _key = SaFilterRegistry.key_for(OWNER, _filter)
    _easel.compositor.filter_chain.registry = registry
    _document = _easel.document
    _document.color_space = SaColorSpace.linear_srgb()


## Writes "Layer 1" from *texel_of*, a callable answering the straight colour of
## a document pixel, over the chunks at *grids* alone.
func _paint(grids: Array[Vector2i], texel_of: Callable) -> SaLayer:
    var layer := _document.get_node("Layer 1") as SaLayer
    for grid_pos in grids:
        var chunk := layer.get_or_create_chunk(grid_pos)
        var side := chunk.pixel_size()
        var values := PackedFloat32Array()
        values.resize(side * side * 4)
        for py in side:
            for px in side:
                var colour: Color = texel_of.call(grid_pos * SaChunk.SIZE + Vector2i(px, py))
                var i := (py * side + px) * 4
                values[i] = colour.r
                values[i + 1] = colour.g
                values[i + 2] = colour.b
                values[i + 3] = colour.a
        GlobalShaderCompiler.get_rd().texture_update(chunk.field(SaFieldSpec.ALBEDO).rid, 0, values.to_byte_array())
    return layer


static func _every_chunk() -> Array[Vector2i]:
    var out: Array[Vector2i] = []
    for y in CHUNKS:
        for x in CHUNKS:
            out.append(Vector2i(x, y))
    return out


## Opaque black with a white texel at the centre and at each of [const ALONG].
static func _lone_texels(at: Vector2i) -> Color:
    if at == CENTRE:
        return Color.WHITE
    for step in ALONG:
        if at == CENTRE - Vector2i(step, step):
            return Color.WHITE
    return Color.BLACK


## Opaque black with white lines every [const GRID] pixels both ways, the lines
## crossing the edge between the two chunks they are painted over.
static func _grid(at: Vector2i) -> Color:
    if posmod(at.x, GRID) < LINE or posmod(at.y, GRID) < LINE:
        return Color.WHITE
    return Color.BLACK


## The composite as bytes, read back once.
func _read() -> Array:
    Bench.composite(_easel)
    var texture := _easel.output
    return [GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0), texture]


static func _at(read: Array, at: Vector2i) -> Color:
    var texture := read[1] as SaTexture
    return SaFieldSpec.decode_texel(read[0], texture.format, at.y * texture.size.x + at.x)


## Where the white of the texels within [const WINDOW] of *around* weighs in,
## each texel standing at its middle, and how much white there is.
static func _centroid(read: Array, around: Vector2) -> Array:
    var sum := Vector2.ZERO
    var weight := 0.0
    var middle := Vector2i(floori(around.x), floori(around.y))
    for y in range(middle.y - WINDOW, middle.y + WINDOW + 1):
        for x in range(middle.x - WINDOW, middle.x + WINDOW + 1):
            var white := _at(read, Vector2i(x, y)).r
            sum += (Vector2(x, y) + Vector2(0.5, 0.5)) * white
            weight += white
    return [sum / maxf(weight, 1e-6), weight]


## The forward model: how far from the centre of a document of *canvas* pixels
## a texel *distance* from it lands under the fraction *bend*. The kernel says
## where each texel reads from, r (1 - k r²) in half diagonals, so this solves
## that for r by bisection over the stretch where the read still rises. Written
## here and not taken from the filter, so the suite reads the model and not the
## filter's own arithmetic.
static func _landing(distance: float, bend: float, canvas: Vector2i) -> float:
    var whole := Vector2(canvas).length() * 0.5
    var low := 0.0
    var high := whole * 4.0
    if bend > 0.0:
        high = whole / sqrt(3.0 * bend)
    for _step in 64:
        var middle := (low + high) * 0.5
        var reads := middle * (1.0 - bend * middle * middle / (whole * whole))
        if reads < distance:
            low = middle
        else:
            high = middle
    return (low + high) * 0.5


## Attaches the filter at *amount* over the lone texels and reads where each
## landed against where the model puts it. The layer holds the top left chunk
## alone, every texel of it, so a centre taken from the layer's paint rather
## than the document would sit at the middle of that chunk, 128 texels up and
## left of the document's, and no texel would land where the model puts it.
func _check_the_texels_land(amount: float) -> void:
    var corner: Array[Vector2i] = [Vector2i(0, 0)]
    SaFilterOps.new(_document).attach(_paint(corner, _lone_texels), _key, {"amount": amount})
    var read := _read()
    var centre := _at(read, CENTRE)
    assert_true(centre.r > 0.99, "The centre's texel is still white where it was: %s" % centre)
    # The centre's texel is the chunk's last, so its neighbours to the right and
    # below are the document's grey where the layer holds nothing.
    var sides: Array[Vector2i] = [Vector2i(-1, 0), Vector2i(0, -1), Vector2i(-1, -1)]
    for beside: Vector2i in sides:
        var next := _at(read, CENTRE + beside)
        assert_true(next.r < 0.01, "and its neighbour at %s took none of it: %s" % [beside, next])
    var middle := Vector2(_document.canvas_size) * 0.5
    var inwards := Vector2(-1.0, -1.0).normalized()
    for step in ALONG:
        var source := Vector2(CENTRE - Vector2i(step, step)) + Vector2(0.5, 0.5)
        var distance := source.distance_to(middle)
        var lands := _landing(distance, amount / 100.0, _document.canvas_size)
        var expected := middle + inwards * lands
        var found := _centroid(read, expected)
        var where := found[0] as Vector2
        # A bilinear read drawing the picture in samples it more sparsely than
        # its texels, so a lone texel keeps only part of its white below nought.
        assert_true(float(found[1]) > 0.5, "The texel %d along is there to find: %f of white" % [step, found[1]])
        var said := "The texel %d along, %.2f from the centre, lands %.2f out" % [step, distance, lands]
        assert_true(where.distance_to(expected) < 1.0, "%s, at %s, and the model puts it at %s" % [said, where, expected])
        # A texel near the middle barely moves, since the move grows as the cube
        # of its distance, so the sign is read on the furthest alone.
        if step == ALONG[-1]:
            var moved := where.distance_to(middle) - distance
            if amount > 0.0:
                assert_true(moved > 10.0, "Above nought the furthest moved outwards, by %.2f" % moved)
            else:
                assert_true(moved < -10.0, "Below nought the furthest moved inwards, by %.2f" % moved)


func test_above_nought_each_texel_lands_further_out_by_the_model() -> void:
    _check_the_texels_land(AMOUNT)


func test_below_nought_each_texel_lands_further_in_by_the_model() -> void:
    _check_the_texels_land(-AMOUNT)


func test_no_amount_leaves_every_lone_texel_where_it_was() -> void:
    SaFilterOps.new(_document).attach(_paint(_every_chunk(), _lone_texels), _key, {"amount": 0.0})
    var read := _read()
    var steps: Array[int] = [0]
    steps.append_array(ALONG)
    for step: int in steps:
        var at := CENTRE - Vector2i(step, step)
        assert_true(_at(read, at).r > 0.99, "The texel %d along is where it was" % step)


## The grid over the top two chunks alone, so its lines cross the edge between
## them and the read near the bottom of the paint reaches chunks the layer does
## not hold.
func _check_attached_is_baked(amount: float) -> void:
    var grids: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0)]
    var settings := {"amount": amount}
    SaFilterOps.new(_document).attach(_paint(grids, _grid), _key, settings)
    var attached := _read()
    var attached_values: Array[Color] = []
    var side := SaChunk.SIZE * CHUNKS
    for y in side:
        for x in side:
            attached_values.append(_at(attached, Vector2i(x, y)))
    _easel.free()
    _make_easel()
    var whole := _paint(grids, _grid)
    _filter.set_parameters(settings)
    var ctx := SaFilterContext.new(_document, whole, OWNER, _filter.title(), false)
    assert_true(SaFilterApply.call_run(_filter, ctx), "The run records a pass")
    assert_true(SaFilterApply.apply(ctx, _filter.title()), "which Apply bakes into the layer")
    var baked := _read()
    var worst := 0.0
    var differs := 0
    var index := 0
    for y in side:
        for x in side:
            var a := attached_values[index]
            var b := _at(baked, Vector2i(x, y))
            worst = maxf(worst, maxf(absf(a.r - b.r), maxf(absf(a.g - b.g), maxf(absf(a.b - b.b), absf(a.a - b.a)))))
            if absf(b.r - _grid(Vector2i(x, y)).r) > 0.5 and y < SaChunk.SIZE:
                differs += 1
            index += 1
    assert_true(worst < 1e-4, "At %.0f the attached composite is the baked layer's, off by %f" % [amount, worst])
    assert_true(differs > 1000, "and the grid moved for them to agree on: %d texels changed" % differs)


func test_attached_and_baked_agree_across_a_chunk_edge_above_nought() -> void:
    _check_attached_is_baked(AMOUNT)


func test_attached_and_baked_agree_across_a_chunk_edge_below_nought() -> void:
    _check_attached_is_baked(-AMOUNT)


## Over a photograph with Crop to fill off, an amount whose corner moves less
## than a chunk is read through a halo of that move, the pass a saved record has
## always laid, and one past it through a pass that reads the whole node at the
## amount asked.
func test_on_a_wide_canvas_an_amount_past_a_chunk_reads_the_whole_node() -> void:
    var photo := SaDocument.new()
    photo.canvas_size = PHOTO
    var filter := SaLensCorrectionFilter.new()
    filter.set_parameters({"amount": 10.0, String(SaLensCorrectionFilter.CROP): false})
    var ctx := SaFilterContext.new(photo, null, OWNER, filter.title(), true)
    filter.run(ctx)
    var recorded := ctx.point as SaNeighbourhoodPass
    assert_true(recorded != null and not recorded.whole(), "At 10 the corner moves 250 and a halo reads it")
    if recorded != null:
        assert_true(
            recorded.radius >= 250 and recorded.radius <= 251, "a halo of the move and the bilinear texel: %d" % recorded.radius
        )
        assert_eq(recorded.kernel, SaLensCorrectionFilter.KERNEL, "through the kernel a saved record lays")
    filter.set_parameters({"amount": 25.0, String(SaLensCorrectionFilter.CROP): false})
    ctx = SaFilterContext.new(photo, null, OWNER, filter.title(), true)
    filter.run(ctx)
    recorded = ctx.point as SaNeighbourhoodPass
    assert_true(recorded != null and recorded.whole(), "At 25 the corner moves 625 and the pass reads the whole node")
    if recorded != null:
        assert_almost_eq(float(recorded.params["amount"]), 0.25, 1e-6, "at the amount asked")
        assert_eq(recorded.writes, SaNeighbourhoodPass.WRITES_CANVAS, "writing wherever the paint spreads to")
    photo.free()


func test_it_is_listed_under_distort_and_found_by_its_name() -> void:
    var filter := SaLensCorrectionFilter.new()
    assert_eq(filter.family(), &"distort", "It is a Distort filter")
    assert_eq(filter.title(), "Lens Correction", "called Lens Correction")
    assert_false(filter.finishes(), "and it runs where it stands in a chain")
    assert_eq(SaLensCorrectionFilter.reach(10.0), 11, "Its halo is the corner's move and the bilinear texel")
    assert_eq(SaLensCorrectionFilter.reach(10.5), 11, "a part of a texel included")
