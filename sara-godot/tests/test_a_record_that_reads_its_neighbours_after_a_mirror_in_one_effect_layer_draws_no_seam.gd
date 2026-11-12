## On an Effect Layer whose first record is Mirror, a record after it that
## reads its neighbours drew a straight line at every chunk edge across the
## reflection, seen as a ripple on a lake and caused by the next chunk's
## unmirrored source read at each chunk's edge.
##
## The painting: four chunks across and three down, the background hidden, a
## layer named Bank painted red over every row above the level line through the
## canvas's middle at y 384, and above it an Effect Layer of Mirror then a
## Gaussian Blur. The reflection is red below the line, and the blur of a red
## field is red, so a column at a chunk's edge differs from the one beside it
## by no more than the blur changes the field anywhere else.
extends "res://tests/test_framework.gd"

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")
const Fixtures = preload("res://tests/fixtures.gd")
const MirrorFilter = preload("res://modules/sara-base-modules/base/usual/mirror_filter.gd")

const REQUIRES_GPU := true

const OWNER: StringName = &"sara-base-modules"
const MIRROR: StringName = &"sara-base-modules.mirror"
const BLUR: StringName = &"sara-base-modules.gaussian_blur"
const RIPPLE: StringName = &"sara-base-modules.wobble"
const SIZE := Vector2i(1024, 768)
const RED := Color(1.0, 0.0, 0.0, 1.0)
const LINE := 384
const RADIUS := 8.0
## What a column may differ from its neighbour by over and above the blur's own
## change: the rounding of a half float.
const TOLERANCE := 1.0e-3
## The rows of the reflection read, clear of the level line and the canvas's
## bottom edge by more than the blur reaches.
const FIRST_ROW := LINE + 24
const LAST_ROW := 744

var _types: SaLayerTypeRegistry


func before_each() -> void:
    _types = Fixtures.make_registries().layer_types
    SaProblems.pending_refusals = PackedStringArray()


## The painting of the header, composited, its Effect Layer holding Mirror and
## then a Gaussian Blur of *radius*, or *after* with *values* when it is named.
func _painting(radius: float, after: StringName = BLUR, values: Dictionary = {}) -> SaEasel:
    var easel := Bench.easel(SIZE)
    var filters := easel.compositor.filter_chain.registry
    filters.register(MirrorFilter.new(), OWNER)
    filters.register(SaGaussianBlurFilter.new(), OWNER)
    filters.register(SaWobbleFilter.new(), OWNER)
    var doc := easel.document
    (doc.get_node("Background") as SaLayer).visible = false
    var bank := doc.get_node("Layer 1") as SaLayer
    bank.name = "Bank"
    doc.set_active_layer(bank)
    _paint(bank, Rect2i(0, 0, SIZE.x, LINE), RED)
    var effect := SaLayerOps.new(doc).add(SaEffectLayer.TYPE_ID, _types)
    effect.name = "Lake"
    var ops := SaFilterOps.new(doc)
    assert_not_null(ops.attach(effect, MIRROR, {}), "The Mirror attaches to the Effect Layer")
    var given := values if after != BLUR else {"radius": radius}
    assert_not_null(ops.attach(effect, after, given), "and %s after it" % after)
    doc.set_active_layer(bank)
    Bench.composite(easel)
    return easel


## Writes *colour* over *area*, in document pixels, into *layer*'s chunks,
## making the chunks it needs.
static func _paint(layer: SaLayer, area: Rect2i, colour: Color) -> void:
    var side := SaChunk.SIZE
    var first := Vector2i((Vector2(area.position) / side).floor())
    var last := Vector2i((Vector2(area.end - Vector2i.ONE) / side).floor())
    for gy in range(first.y, last.y + 1):
        for gx in range(first.x, last.x + 1):
            var grid_pos := Vector2i(gx, gy)
            var part := area.intersection(Rect2i(grid_pos * side, Vector2i(side, side)))
            var local := Rect2i(part.position - grid_pos * side, part.size)
            var chunk := layer.get_or_create_chunk(grid_pos)
            if local.size == Vector2i(side, side):
                chunk.clear(colour)
                continue
            var texture := chunk.field(SaFieldSpec.ALBEDO)
            var rd := GlobalShaderCompiler.get_rd()
            var bytes := rd.texture_get_data(texture.rid, 0)
            var texel := SaFieldSpec.BYTES_PER_TEXEL.get(texture.format, 16) as int
            var one := SaTexture.new(Vector2i.ONE, texture.format)
            one.clear(colour)
            var paint := rd.texture_get_data(one.rid, 0)
            for y in range(local.position.y, local.end.y):
                for x in range(local.position.x, local.end.x):
                    var at := (y * texture.size.x + x) * texel
                    for i in texel:
                        bytes[at + i] = paint[i]
            rd.texture_update(texture.rid, 0, bytes)


## The largest difference between two colours over their four channels.
static func _apart(a: Color, b: Color) -> float:
    return maxf(maxf(absf(a.r - b.r), absf(a.g - b.g)), maxf(absf(a.b - b.b), absf(a.a - b.a)))


## The output decoded once, row by row, so a suite reads every texel it needs
## from one transfer.
static func _rows(texture: SaTexture) -> Callable:
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    return func(at: Vector2i) -> Color: return SaFieldSpec.decode_texel(bytes, texture.format, at.y * texture.size.x + at.x)


## The largest difference between two neighbouring columns, over the rows of
## the reflection, at the column pairs *pairs* name by their left column.
static func _worst(texel: Callable, pairs: Array[int]) -> float:
    var worst := 0.0
    for x: int in pairs:
        for y in range(FIRST_ROW, LAST_ROW + 1, 4):
            worst = maxf(worst, _apart(texel.call(Vector2i(x, y)), texel.call(Vector2i(x + 1, y))))
    return worst


func test_the_reflection_is_red_below_the_line() -> void:
    var easel := _painting(RADIUS)
    var texel := _rows(easel.output)
    var middle: Color = texel.call(Vector2i(128, 640))
    assert_true(_apart(middle, RED) <= TOLERANCE, "The reflection inside a chunk is the red field, read %s" % middle)
    easel.free()


## Every pair of columns within the blur's reach of a chunk edge the reflection
## crosses, against the largest step between two columns farther from every
## edge, which is the blur's own change. A seam is symmetric about its edge, so
## the two columns either side of it read alike and the step is beside them.
func test_no_column_at_a_chunk_edge_differs_more_than_the_blur_changes_the_field() -> void:
    var easel := _painting(RADIUS)
    var texel := _rows(easel.output)
    var edges: Array[int] = []
    var inside: Array[int] = []
    var near := int(RADIUS) + 2
    for x in range(near, SIZE.x - near):
        var off := (x + 1) % SaChunk.SIZE
        if off <= near or off >= SaChunk.SIZE - near:
            edges.append(x)
        elif x % 4 == 0:
            inside.append(x)
    var bound := _worst(texel, inside) + TOLERANCE
    var seam := _worst(texel, edges)
    print("bound %.6f, largest difference across a chunk edge %.6f" % [bound, seam])
    assert_true(seam <= bound, "No chunk edge draws a seam: largest %.6f against the blur's own %.6f" % [seam, bound])
    var before: Color = texel.call(Vector2i(SaChunk.SIZE - 1, 640))
    assert_true(_apart(before, RED) <= TOLERANCE, "The column before the edge at x 256 is the red field, read %s" % before)
    easel.free()


## The edge across the reflection's rows, y 512, read the same way.
func test_no_row_at_a_chunk_edge_differs_more_than_the_blur_changes_the_field() -> void:
    var easel := _painting(RADIUS)
    var texel := _rows(easel.output)
    var worst := 0.0
    var edge := 2 * SaChunk.SIZE
    for x in range(int(RADIUS) + 2, SIZE.x - int(RADIUS) - 2, 4):
        for y in range(edge - int(RADIUS) - 2, edge + int(RADIUS) + 2):
            worst = maxf(worst, _apart(texel.call(Vector2i(x, y)), texel.call(Vector2i(x, y + 1))))
    print("largest difference across the row edge at y 512 %.6f" % worst)
    assert_true(worst <= TOLERANCE, "The chunk edge at y 512 draws no seam either, largest %.6f" % worst)
    easel.free()


## The painter's own record, the ripple, moves texels a few pixels and so reads
## the chunk beside its own along every edge. Over a red field every texel of
## the reflection stays red, and before the cure a strip at each chunk edge read
## the empty, unmirrored neighbour.
func test_the_ripple_after_the_mirror_keeps_every_texel_at_a_chunk_edge_red() -> void:
    var easel := _painting(RADIUS, RIPPLE, {"amplitude": 6.0, "wavelength": 48.0, "turbulence": 40.0})
    var texel := _rows(easel.output)
    var worst := 0.0
    for edge: int in [SaChunk.SIZE, 2 * SaChunk.SIZE, 3 * SaChunk.SIZE]:
        for x in range(edge - 12, edge + 12):
            for y in range(FIRST_ROW, LAST_ROW + 1, 2):
                worst = maxf(worst, _apart(texel.call(Vector2i(x, y)), RED))
    for x in range(16, SIZE.x - 16, 2):
        for y in range(2 * SaChunk.SIZE - 12, 2 * SaChunk.SIZE + 12):
            worst = maxf(worst, _apart(texel.call(Vector2i(x, y)), RED))
    print("the ripple's largest difference from the red field along the chunk edges %.6f" % worst)
    assert_true(worst <= TOLERANCE, "The ripple draws no seam, largest %.6f off the red field" % worst)
    easel.free()
