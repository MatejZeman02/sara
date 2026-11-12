## A blur on an adjustment layer reads the backdrop's
## neighbours, at rest, under a stroke on a layer below it across a chunk edge,
## and folded into the cache below an active layer above it, and a flatten and
## a merge down bake what the canvas shows.
##
## The painting is four chunks, each an opaque colour of its own with a bar
## across it, so every chunk edge is a step a blur smooths and a band along the
## grid, a neighbour read as transparent, shows as a dark line. The reference is
## the same painting inside an isolated group carrying the same blur, the road a
## blur took before this row. The group's blur reads transparent past the
## canvas while the adjustment keeps the backdrop's alpha, so the two are read
## inside a margin of the canvas's edge wider than the blur.
extends "res://tests/test_framework.gd"

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")
const Fixtures = preload("res://tests/fixtures.gd")

const REQUIRES_GPU := true

const SIZE := Vector2i(512, 512)
const COLOURS: Dictionary[Vector2i, Color] = {
    Vector2i(0, 0): Color(0.125, 0.625, 0.25, 1.0),
    Vector2i(1, 0): Color(0.75, 0.25, 0.125, 1.0),
    Vector2i(0, 1): Color(0.25, 0.375, 0.875, 1.0),
    Vector2i(1, 1): Color(0.875, 0.75, 0.25, 1.0),
}
const BAR := Color(0.0625, 0.0625, 0.125, 1.0)
const YELLOW := Color(1.0, 0.875, 0.125, 1.0)
## The stroke, in document pixels, across the edge between the top two chunks.
const STROKE := Rect2i(226, 90, 60, 50)
const RADIUS := 6.0
const TOLERANCE := 1.0e-3
## Past the blur's reach, where the group's blur starts reading past the canvas.
const MARGIN := 24

var _types: SaLayerTypeRegistry


func before_each() -> void:
    _types = Fixtures.make_registries().layer_types
    SaProblems.pending_refusals = PackedStringArray()


## The painting of the header on the background, left active. With *grouped*
## the background sits in an isolated group carrying the blur, and with
## *stroked* the stroke is painted into it already.
func _painting(grouped: bool, stroked: bool = false) -> SaEasel:
    var easel := Bench.easel(SIZE)
    _with_filters(easel)
    var doc := easel.document
    var base := doc.get_node("Background") as SaLayer
    for grid_pos: Vector2i in base.chunks.keys():
        base.chunks.erase(grid_pos)
    for grid_pos: Vector2i in COLOURS:
        _paint(base.get_or_create_chunk(grid_pos).albedo(), grid_pos, COLOURS[grid_pos], stroked)
    doc.set_active_layer(base)
    if grouped:
        var ops := SaLayerOps.new(doc)
        var group := ops.group_active()
        ops.set_isolated(group, true)
        _attach(doc, group)
        doc.set_active_layer(base)
    return easel


## *texture*, the chunk at *grid_pos*, filled with *fill* and a bar across it,
## and the stroke's texels over it with *stroked*.
func _paint(texture: SaTexture, grid_pos: Vector2i, fill: Color, stroked: bool) -> void:
    var side := texture.size.x
    var half := texture.format == RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
    var image := Image.create_empty(side, side, false, Image.FORMAT_RGBAH if half else Image.FORMAT_RGBAF)
    image.fill(fill)
    image.fill_rect(Rect2i(0, 100 + 20 * grid_pos.x, side, 12), BAR)
    if stroked:
        var local := Rect2i(STROKE.position - grid_pos * side, STROKE.size).intersection(Rect2i(0, 0, side, side))
        if local.size.x > 0 and local.size.y > 0:
            image.fill_rect(local, YELLOW)
    GlobalShaderCompiler.get_rd().texture_update(texture.rid, 0, image.get_data())


## The stroke alone, in the live stroke buffer of *easel*, over the chunks it
## crosses.
func _stroke(easel: SaEasel) -> Dictionary[Vector2i, Rect2i]:
    var doc := easel.document
    var regions: Dictionary[Vector2i, Rect2i] = {}
    for grid_pos: Vector2i in [Vector2i(0, 0), Vector2i(1, 0)]:
        var texture := doc.stroke_layer.get_or_create_chunk(grid_pos).albedo()
        var side := texture.size.x
        var half := texture.format == RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
        var image := Image.create_empty(side, side, false, Image.FORMAT_RGBAH if half else Image.FORMAT_RGBAF)
        image.fill(Color(0, 0, 0, 0))
        var local := Rect2i(STROKE.position - grid_pos * side, STROKE.size).intersection(Rect2i(0, 0, side, side))
        image.fill_rect(local, YELLOW)
        GlobalShaderCompiler.get_rd().texture_update(texture.rid, 0, image.get_data())
        regions[grid_pos] = local
    doc.stroke_layer.visible = true
    return regions


## An adjustment layer directly above the active one, carrying the blur.
func _adjust(easel: SaEasel) -> SaLayer:
    var layer := SaLayerOps.new(easel.document).add(SaBackdropLayer.TYPE_ID, _types)
    layer.name = "Adjust"
    _attach(easel.document, layer)
    return layer


func _attach(doc: SaDocument, node: SaLayer) -> void:
    var key := SaFilterRegistry.key_for(&"sara-base-modules", SaGaussianBlurFilter.new())
    assert_not_null(SaFilterOps.new(doc).attach(node, key, {"radius": RADIUS}), "The blur attaches to %s" % node.name)


static func _with_filters(easel: SaEasel) -> void:
    easel.compositor.filter_chain.registry.register(SaGaussianBlurFilter.new(), &"sara-base-modules")
    easel.compositor.filter_chain.registry.register(SaWrapOffsetFilter.new(), &"sara-base-modules")


static func _bytes(texture: SaTexture) -> PackedByteArray:
    return GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)


static func _texel(bytes: PackedByteArray, texture: SaTexture, at: Vector2i) -> Color:
    return SaFieldSpec.decode_texel(bytes, texture.format, at.y * texture.size.x + at.x)


static func _apart(a: Color, b: Color) -> float:
    return maxf(maxf(absf(a.r - b.r), absf(a.g - b.g)), maxf(absf(a.b - b.b), absf(a.a - b.a)))


## Every third texel inside the margin, and every texel of the four columns and
## rows along the chunk grid, where a band would show.
static func _probes() -> Array[Vector2i]:
    var out: Array[Vector2i] = []
    for y in range(MARGIN, SIZE.y - MARGIN, 3):
        for x in range(MARGIN, SIZE.x - MARGIN, 3):
            out.append(Vector2i(x, y))
    for along in range(MARGIN, SIZE.x - MARGIN):
        for seam: int in [SaChunk.SIZE - 2, SaChunk.SIZE - 1, SaChunk.SIZE, SaChunk.SIZE + 1]:
            out.append(Vector2i(seam, along))
            out.append(Vector2i(along, seam))
    return out


## *got* against *want*, both outputs of *texture*'s shape, within the tolerance.
func _alike(texture: SaTexture, got: PackedByteArray, want: PackedByteArray, what: String) -> void:
    var worst := 0.0
    var worst_at := Vector2i.ZERO
    for at: Vector2i in _probes():
        var off := _apart(_texel(got, texture, at), _texel(want, texture, at))
        if off > worst:
            worst = off
            worst_at = at
    assert_true(worst <= TOLERANCE, "%s, worst %s at %s" % [what, worst, worst_at])


## The reference, the painting in a blurred isolated group, as its bytes.
func _reference(stroked: bool) -> PackedByteArray:
    var easel := _painting(true, stroked)
    Bench.composite(easel)
    var bytes := _bytes(easel.output)
    easel.free()
    return bytes


func test_at_rest_it_matches_a_blurred_group_with_no_band_along_the_grid() -> void:
    var want := _reference(false)
    var easel := _painting(false)
    var plain := _bytes(easel.output)
    var layer := _adjust(easel)
    Bench.composite(easel)
    assert_eq(easel.document.active_layer, layer, "The adjustment layer is active")
    assert_true(layer.chunks.is_empty(), "and holds no chunk")
    var got := _bytes(easel.output)
    assert_false(got == plain, "The blur changes the canvas")
    _alike(easel.output, got, want, "The blur on the adjustment layer is the blur on the group")
    easel.free()


func test_a_stroke_below_it_across_a_chunk_edge_reads_the_backdrop_around_it() -> void:
    var want := _reference(true)
    var easel := _painting(false)
    _adjust(easel)
    var base := easel.document.get_node("Background") as SaLayer
    easel.document.set_active_layer(base)
    Bench.composite(easel)
    # Only the stroke's regions, as a brush's dab marks them, and not a full
    # composite, so the ring past them keeps what the last composite drew.
    easel.document.invalidate_chunk_regions(_stroke(easel))
    easel.process_pending_composite()
    _alike(easel.output, _bytes(easel.output), want, "Under a live stroke below it the blur is the group's")
    easel.document.commit_stroke()
    easel.process_pending_composite()
    _alike(easel.output, _bytes(easel.output), want, "and after the commit")
    easel.free()


func test_with_the_active_layer_above_it_the_fold_reads_the_cache_around_each_chunk() -> void:
    var want := _reference(false)
    var easel := _painting(false)
    var layer := _adjust(easel)
    var above := SaLayerOps.new(easel.document).add()
    above.name = "Above"
    easel.document.set_active_layer(above)
    Bench.composite(easel)
    var folded := false
    for entry: Dictionary in easel.document.fold.bottom_stack:
        folded = folded or SaLayerStack.layer_of(entry) == easel.document.fold.bottom_cache
    assert_true(folded, "The adjustment layer is folded into the cache below the active layer")
    assert_true(layer.chunks.is_empty(), "and holds no chunk")
    _alike(easel.output, _bytes(easel.output), want, "Folded, the blur is the group's")
    easel.free()


func test_a_flatten_and_a_merge_down_bake_the_canvas() -> void:
    var easel := _painting(false)
    var layer := _adjust(easel)
    Bench.composite(easel)
    var before := _bytes(easel.output)
    var doc := easel.document
    assert_true(SaLayerOps.new(doc).flatten(), "The flatten runs")
    Bench.composite(easel)
    _alike(easel.output, _bytes(easel.output), before, "The flattened canvas is the canvas before it")
    assert_true(doc.undo(), "and it undoes")
    Bench.composite(easel)
    assert_true(SaLayerOps.new(doc).merge_down(layer), "Merge Down runs")
    Bench.composite(easel)
    _alike(easel.output, _bytes(easel.output), before, "The merged canvas is the canvas before it")
    easel.free()


func test_a_record_reading_the_whole_layer_is_refused_with_its_sentence() -> void:
    var easel := _painting(false)
    var layer := _adjust(easel)
    assert_eq(layer.filters.size(), 1, "The blur is attached")
    var wrap_key := SaFilterRegistry.key_for(&"sara-base-modules", SaWrapOffsetFilter.new())
    SaProblems.announce = false
    var refused := SaFilterOps.new(easel.document).attach(layer, wrap_key, {"offset_x": 16.0})
    SaProblems.announce = true
    assert_null(refused, "A wrap is refused")
    var said := "\n".join(SaProblems.pending_refusals)
    assert_true(
        said.contains("'Adjust' is an adjustment layer, and this filter reads the whole layer"), "with its sentence: %s" % said
    )
    easel.free()
