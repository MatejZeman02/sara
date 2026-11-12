## The fill grows its region under the line by a number of texels.
##
## A fill against an anti-aliased line stops where the line begins to fade and
## leaves a pale fringe between colour and line. The Grow option on the fill
## bar expands the flooded region by 0 to 10 texels so the fill tucks under the
## line art rather than stopping short of it.
##
## With Grow at 0, the fill behaves exactly as before. With Grow above 0, the
## region is grown through SaSelectionFilters.grow before painting, passing under
## the reference layer's line.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const StateBucketFillScript = preload("res://modules/sara-base-modules/base/tools/state_bucket_fill.gd")
const BaseModuleScript = preload("res://modules/sara-base-modules/base/module.gd")
const PixelDriver = preload("res://harness/scenario/sa_scenario_pixels.gd")
const Fixtures = preload("res://tests/fixtures.gd")

const INK := Color(0.04, 0.04, 0.05, 1.0)
const BLUE := Color(0.1, 0.4, 0.9, 1.0)
const RED := Color(0.9, 0.2, 0.1, 1.0)

const CENTRE := Vector2(256.0, 256.0)
const INNER_EMPTY := 85.0
const INNER_SOLID := 95.0
const OUTER_SOLID := 105.0
const OUTER_EMPTY := 115.0

const WRITTEN := Rect2i(0, 0, 512, 512)
const CANVAS := Vector2i(768, 768)

const MIDDLE := Vector2i(256, 256)
const BESIDE_THE_RING := Vector2i(370, 256)
const FAR_GROUND := Vector2i(650, 650)

var _surface: SaSurface = null
var _doc: SaDocument = null
var _folder: String = ""


func before_each() -> void:
    _surface = Fixtures.make_surface(CANVAS)
    _doc = _surface.get_document()
    _folder = OS.get_temp_dir().path_join("sara-grow-fill-%d" % OS.get_process_id())
    DirAccess.make_dir_recursive_absolute(_folder)


func after_each() -> void:
    for name in DirAccess.get_files_at(_folder):
        DirAccess.remove_absolute(_folder.path_join(name))
    DirAccess.remove_absolute(_folder)
    _doc.free()
    _surface.easel.free()
    _surface = null
    _doc = null


static func _coverage_at(at: Vector2) -> float:
    var d := at.distance_to(CENTRE)
    var inner := clampf((d - INNER_EMPTY) / (INNER_SOLID - INNER_EMPTY), 0.0, 1.0)
    var outer := clampf((OUTER_EMPTY - d) / (OUTER_EMPTY - OUTER_SOLID), 0.0, 1.0)
    return inner * outer


func _ring(name: String = "LineArt") -> SaLayer:
    var stored := _doc.color_space.from_display(INK)
    var floats := PackedFloat32Array()
    floats.resize(WRITTEN.size.x * WRITTEN.size.y * 4)
    for y in WRITTEN.size.y:
        for x in WRITTEN.size.x:
            var alpha := _coverage_at(Vector2(x, y) + Vector2(0.5, 0.5))
            if alpha <= 0.0:
                continue
            var at := (y * WRITTEN.size.x + x) * 4
            floats[at] = stored.r
            floats[at + 1] = stored.g
            floats[at + 2] = stored.b
            floats[at + 3] = alpha
    var file := FileAccess.open(_folder.path_join("ring.npy"), FileAccess.WRITE)
    file.store_buffer(PixelDriver.Npy.header(WRITTEN.size))
    file.store_buffer(floats.to_byte_array())
    file.close()
    var rect := [WRITTEN.position.x, WRITTEN.position.y, WRITTEN.size.x, WRITTEN.size.y]
    var answer := PixelDriver.write_from(_doc, {"new_layer": name, "rect": rect, "file": "ring.npy"}, _folder)
    assert_false(answer.has("error"), "The harness wrote the ring: %s" % answer)
    _surface.easel.request_full_composite()
    _surface.easel.process_pending_composite()
    return _doc.active_layer


func _texel(layer: SaLayer, at: Vector2i) -> Color:
    var grid := Vector2i(floori(float(at.x) / SaChunk.SIZE), floori(float(at.y) / SaChunk.SIZE))
    var chunk: SaChunk = layer.chunks.get(grid, null)
    if chunk == null:
        return Color(0, 0, 0, 0)
    var texture: SaTexture = chunk.field(chunk.fields.keys()[0])
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    var local := at - grid * SaChunk.SIZE
    var offset := (local.y * SaChunk.SIZE + local.x) * 16
    return Color(
        bytes.decode_float(offset),
        bytes.decode_float(offset + 4),
        bytes.decode_float(offset + 8),
        bytes.decode_float(offset + 12)
    )


## Paints an anti-aliased ring, fills inside it with Grow at 0 and then at 3
## on two layers below it, and reads the second fill reaching 3 texels further
## out under the ring's soft inner edge on every side, and no texel past the
## first fill's edge grown by 3.
func test_fill_grows_region_under_anti_aliased_ring_by_three_texels() -> void:
    var layer_grow0 := _doc.active_layer
    layer_grow0.name = "FillGrow0"

    var layer_grow3: SaLayer = SaLayerOps.new(_doc).add()
    layer_grow3.name = "FillGrow3"

    var ring_layer := _ring("LineArt")

    var rd := GlobalShaderCompiler.get_rd()
    var before_data: Dictionary = {}
    for grid_pos: Vector2i in ring_layer.chunks:
        var chunk: SaChunk = ring_layer.chunks[grid_pos]
        var texture: SaTexture = chunk.field(chunk.fields.keys()[0])
        before_data[grid_pos] = rd.texture_get_data(texture.rid, 0)

    # First fill: Grow at 0 on layer_grow0 below the ring.
    _doc.set_active_layer(layer_grow0)
    assert_eq(_doc.active_layer, layer_grow0, "layer_grow0 is active")

    var fill0 := StateBucketFillScript.new()
    fill0.surface = _surface
    fill0.reference_layer = "LineArt"
    fill0.grow = 0
    fill0.tolerance = 0.02
    fill0.antialias = false
    SaColors.foreground = BLUE

    var touched0 := fill0.fill_at(MIDDLE)
    assert_true(touched0 > 0, "The first fill touched chunks on layer_grow0")

    # Second fill: Grow at 3 on layer_grow3 below the ring.
    _doc.set_active_layer(layer_grow3)
    assert_eq(_doc.active_layer, layer_grow3, "layer_grow3 is active")

    var fill3 := StateBucketFillScript.new()
    fill3.surface = _surface
    fill3.reference_layer = "LineArt"
    fill3.grow = 3
    fill3.tolerance = 0.02
    fill3.antialias = false
    SaColors.foreground = RED

    var touched3 := fill3.fill_at(MIDDLE)
    assert_true(touched3 > 0, "The second fill touched chunks on layer_grow3")

    # Verify cardinal directions from the centre (256, 256).
    # The flood stops where distance exceeds 85.0 texels, at:
    # Right: x = 340, y = 256. Left: x = 171, y = 256.
    # Top: x = 256, y = 171. Bottom: x = 256, y = 340.
    var right0 := Vector2i(340, 256)
    var left0 := Vector2i(171, 256)
    var top0 := Vector2i(256, 171)
    var bottom0 := Vector2i(256, 340)

    # The first fill reaches the cardinal bounds at Grow 0, and stops at the next texel.
    assert_almost_eq(_texel(layer_grow0, right0).a, 1.0, 0.02, "Fill 0 reaches right edge at 340")
    assert_almost_eq(_texel(layer_grow0, right0 + Vector2i(1, 0)).a, 0.0, 0.01, "Fill 0 stops before 341")

    assert_almost_eq(_texel(layer_grow0, left0).a, 1.0, 0.02, "Fill 0 reaches left edge at 171")
    assert_almost_eq(_texel(layer_grow0, left0 - Vector2i(1, 0)).a, 0.0, 0.01, "Fill 0 stops before 170")

    assert_almost_eq(_texel(layer_grow0, top0).a, 1.0, 0.02, "Fill 0 reaches top edge at 171")
    assert_almost_eq(_texel(layer_grow0, top0 - Vector2i(0, 1)).a, 0.0, 0.01, "Fill 0 stops before 170")

    assert_almost_eq(_texel(layer_grow0, bottom0).a, 1.0, 0.02, "Fill 0 reaches bottom edge at 340")
    assert_almost_eq(_texel(layer_grow0, bottom0 + Vector2i(0, 1)).a, 0.0, 0.01, "Fill 0 stops before 341")

    # The second fill reaches 3 texels further out on every side.
    var right3 := right0 + Vector2i(3, 0)
    var left3 := left0 - Vector2i(3, 0)
    var top3 := top0 - Vector2i(0, 3)
    var bottom3 := bottom0 + Vector2i(0, 3)

    assert_almost_eq(_texel(layer_grow3, right3).a, 1.0, 0.02, "Fill 3 reaches 3 texels further out on right (343)")
    assert_almost_eq(_texel(layer_grow0, right3).a, 0.0, 0.01, "Fill 0 did not reach right 343")
    assert_almost_eq(_texel(layer_grow3, right3 + Vector2i(1, 0)).a, 0.0, 0.01, "Fill 3 stops past 343")

    assert_almost_eq(_texel(layer_grow3, left3).a, 1.0, 0.02, "Fill 3 reaches 3 texels further out on left (168)")
    assert_almost_eq(_texel(layer_grow0, left3).a, 0.0, 0.01, "Fill 0 did not reach left 168")
    assert_almost_eq(_texel(layer_grow3, left3 - Vector2i(1, 0)).a, 0.0, 0.01, "Fill 3 stops past 168")

    assert_almost_eq(_texel(layer_grow3, top3).a, 1.0, 0.02, "Fill 3 reaches 3 texels further out on top (168)")
    assert_almost_eq(_texel(layer_grow0, top3).a, 0.0, 0.01, "Fill 0 did not reach top 168")
    assert_almost_eq(_texel(layer_grow3, top3 - Vector2i(0, 1)).a, 0.0, 0.01, "Fill 3 stops past 168")

    assert_almost_eq(_texel(layer_grow3, bottom3).a, 1.0, 0.02, "Fill 3 reaches 3 texels further out on bottom (343)")
    assert_almost_eq(_texel(layer_grow0, bottom3).a, 0.0, 0.01, "Fill 0 did not reach bottom 343")
    assert_almost_eq(_texel(layer_grow3, bottom3 + Vector2i(0, 1)).a, 0.0, 0.01, "Fill 3 stops past 343")

    # Verify that at each of the extended edge texels, the ring's soft inner edge
    # is partially opaque, proving that the second fill reached under the soft inner edge.
    for pt: Vector2i in [right3, left3, top3, bottom3]:
        var ring_cov := _coverage_at(Vector2(pt.x, pt.y) + Vector2(0.5, 0.5))
        assert_true(ring_cov > 0.0, "Ring coverage at %s is above 0 (%f)" % [pt, ring_cov])
        assert_true(ring_cov < 1.0, "Ring coverage at %s is below 1 (%f), in soft edge" % [pt, ring_cov])

    # Verify that no texel past the first fill's edge grown by 3 has paint.
    # Every texel with paint on layer_grow3 must have a texel on layer_grow0 within chebyshev distance 3.
    var past_grown_edge_count := 0
    for grid_pos: Vector2i in layer_grow3.chunks:
        var chunk3: SaChunk = layer_grow3.chunks[grid_pos]
        var texture3: SaTexture = chunk3.field(chunk3.fields.keys()[0])
        var bytes3 := rd.texture_get_data(texture3.rid, 0)
        for ly in SaChunk.SIZE:
            for lx in SaChunk.SIZE:
                var offset := (ly * SaChunk.SIZE + lx) * 16
                var a3 := bytes3.decode_float(offset + 12)
                if a3 <= 0.01:
                    continue
                var global_pos := grid_pos * SaChunk.SIZE + Vector2i(lx, ly)
                var found_near := false
                for dy in range(-3, 4):
                    for dx in range(-3, 4):
                        var near_pos := global_pos + Vector2i(dx, dy)
                        if _texel(layer_grow0, near_pos).a > 0.01:
                            found_near = true
                            break
                    if found_near:
                        break
                if not found_near:
                    past_grown_edge_count += 1
    assert_eq(past_grown_edge_count, 0, "No texel of the second fill lies past the first fill's edge grown by 3")

    # Untouched areas outside the ring.
    assert_almost_eq(_texel(layer_grow3, BESIDE_THE_RING).a, 0.0, 0.01, "Second fill is untouched beside the ring")
    assert_almost_eq(_texel(layer_grow3, FAR_GROUND).a, 0.0, 0.01, "Second fill is untouched on the far ground")

    # The ring layer remains unchanged texel for texel.
    assert_eq(ring_layer.chunks.size(), before_data.size(), "Ring layer chunk count is unchanged")
    for grid_pos: Vector2i in before_data:
        assert_true(ring_layer.chunks.has(grid_pos), "Ring layer holds chunk %s" % [grid_pos])
        var chunk: SaChunk = ring_layer.chunks[grid_pos]
        var texture: SaTexture = chunk.field(chunk.fields.keys()[0])
        var after_bytes := rd.texture_get_data(texture.rid, 0)
        assert_eq(after_bytes, before_data[grid_pos], "Ring layer is unchanged byte for byte at chunk %s" % [grid_pos])


## A fill with Grow at 0 matches today's default fill texel for texel.
func test_fill_with_grow_zero_matches_default_fill_texel_for_texel() -> void:
    var layer_default := _doc.active_layer
    layer_default.name = "DefaultFill"

    var layer_zero: SaLayer = SaLayerOps.new(_doc).add()
    layer_zero.name = "GrowZeroFill"

    _ring("LineArt")

    _doc.set_active_layer(layer_default)
    var fill_default := StateBucketFillScript.new()
    fill_default.surface = _surface
    fill_default.reference_layer = "LineArt"
    # default grow is 0
    SaColors.foreground = BLUE
    var touched_def := fill_default.fill_at(MIDDLE)
    assert_true(touched_def > 0, "Default fill touched chunks")

    _doc.set_active_layer(layer_zero)
    var fill_zero := StateBucketFillScript.new()
    fill_zero.surface = _surface
    fill_zero.reference_layer = "LineArt"
    fill_zero.grow = 0
    SaColors.foreground = BLUE
    var touched_zero := fill_zero.fill_at(MIDDLE)
    assert_true(touched_zero > 0, "Explicit grow 0 fill touched chunks")

    assert_eq(layer_default.chunks.size(), layer_zero.chunks.size(), "Both layers hold the same number of chunks")

    var rd := GlobalShaderCompiler.get_rd()
    for grid_pos: Vector2i in layer_default.chunks:
        assert_true(layer_zero.chunks.has(grid_pos), "Layer zero holds chunk %s" % [grid_pos])
        var chunk_def: SaChunk = layer_default.chunks[grid_pos]
        var tex_def: SaTexture = chunk_def.field(chunk_def.fields.keys()[0])
        var bytes_def := rd.texture_get_data(tex_def.rid, 0)

        var chunk_zero: SaChunk = layer_zero.chunks[grid_pos]
        var tex_zero: SaTexture = chunk_zero.field(chunk_zero.fields.keys()[0])
        var bytes_zero := rd.texture_get_data(tex_zero.rid, 0)

        assert_eq(bytes_zero, bytes_def, "Chunk %s matches default fill byte for byte" % [grid_pos])


## The fill options declare Grow from 0 to 10 with default 0.
func test_grow_option_spec() -> void:
    var specs := StateBucketFillScript.fill_options()
    var grow_spec: SaOptionSpec = null
    for s in specs:
        if s.key == &"fill_grow":
            grow_spec = s
            break
    assert_not_null(grow_spec, "The fill options declare fill_grow")
    assert_eq(grow_spec.label, "Grow", "Option label is Grow")
    assert_eq(grow_spec.min_value, 0.0, "Minimum is 0")
    assert_eq(grow_spec.max_value, 10.0, "Maximum is 10")
    assert_eq(grow_spec.step, 1.0, "Step is 1")
    assert_eq(grow_spec.property, ^"grow", "Property binds to grow")
    assert_eq(grow_spec.decimals, 0, "Decimals is 0")
    assert_eq(grow_spec.suffix, "px", "Suffix is px")
    assert_true(grow_spec.bar, "Option bar flag is true")
    assert_true(grow_spec.tooltip.contains("anti-aliased"), "Tooltip describes anti-aliased edge")

    var fill := StateBucketFillScript.new()
    assert_eq(fill.grow, 0, "Fresh fill defaults to grow 0")
