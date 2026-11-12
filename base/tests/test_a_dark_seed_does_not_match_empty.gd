## A fill seeded on a dark colour does not match empty pixels.
##
## The `paint` sweep drew a near-black ring with the Inked Pen and two airbrush
## blobs of the same colour on one layer, took Fill at the default 10 percent
## and clicked the middle of a blob. The whole layer took the new colour, the
## transparent ground, the other blob and the ring with it. The wand measured
## every colour composited over a backdrop it read from the merged picture at
## the seed, and under a near-opaque seed that picture is the seed itself, so
## every empty texel was seen as the seed's colour. The distance is now taken
## over the premultiplied colour and the alpha, which needs no backdrop at all.
##
## The layer is the sweep's, built through the harness's `write_pixels` step:
## a ring with a one texel soft edge, and two blobs whose alpha falls from 0.95
## in the middle to nothing at their rim, the way an airbrush lays it. The ring
## and the blobs sit in the first four chunks and the canvas is nine, so the
## flood meets both empty texels the layer holds and chunks it never had.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const StateBucketFillScript = preload("res://modules/sara-base-modules/base/tools/state_bucket_fill.gd")
const StateWandScript = preload("res://modules/sara-base-modules/base/wand/state_wand.gd")
const PixelDriver = preload("res://harness/scenario/sa_scenario_pixels.gd")
const Fixtures = preload("res://tests/fixtures.gd")

## The Inked Pen's near-black, a display colour, and the fill's blue.
const INK := Color(0.04, 0.04, 0.05, 1.0)
const BLUE := Color(0.1, 0.4, 0.9, 1.0)
## A mid grey, which is what the old kernel saw behind every empty texel when
## it had nothing better.
const GREY := Color(0.5, 0.5, 0.5, 1.0)

## The ring, and the two blobs with the alpha in their middle.
const RING_CENTRE := Vector2(140.0, 140.0)
const RING_INNER := 60.0
const RING_OUTER := 72.0
const BLOB := Vector2(380.0, 140.0)
const OTHER_BLOB := Vector2(380.0, 390.0)
const BLOB_RADIUS := 60.0
const BLOB_ALPHA := 0.95

## What the write covers, the first four chunks of nine.
const WRITTEN := Rect2i(0, 0, 512, 512)
const CANVAS := Vector2i(768, 768)

## Texels the assertions read: on the ring, its far side, its hole, the ground
## in a chunk the layer holds and in one it does not, and a blob's soft flank
## where the airbrush laid about half its alpha.
const ON_RING := Vector2i(206, 140)
const RING_FAR_SIDE := Vector2i(74, 140)
const RING_HOLE := Vector2i(140, 140)
const GROUND := Vector2i(20, 330)
const FAR_GROUND := Vector2i(650, 650)
const BLOB_FLANK := Vector2i(410, 140)

var _surface: SaSurface = null
var _doc: SaDocument = null
var _folder: String = ""


func before_each() -> void:
    _surface = Fixtures.make_surface(CANVAS)
    _doc = _surface.get_document()
    _folder = OS.get_temp_dir().path_join("sara-s3-dark-seed-%d" % OS.get_process_id())
    DirAccess.make_dir_recursive_absolute(_folder)


func after_each() -> void:
    for name in DirAccess.get_files_at(_folder):
        DirAccess.remove_absolute(_folder.path_join(name))
    DirAccess.remove_absolute(_folder)
    _doc.free()
    _surface.easel.free()
    _surface = null
    _doc = null


## The alpha the picture holds at *at*: the ring, solid with a one texel ramp
## at both its edges, and the blobs, falling from BLOB_ALPHA to nothing.
static func _coverage_at(at: Vector2) -> float:
    var d := at.distance_to(RING_CENTRE)
    var ring := clampf(RING_OUTER + 0.5 - d, 0.0, 1.0) * clampf(d - RING_INNER + 0.5, 0.0, 1.0)
    var blob := 0.0
    for centre: Vector2 in [BLOB, OTHER_BLOB]:
        var fall := clampf(1.0 - pow(at.distance_to(centre) / BLOB_RADIUS, 2.0), 0.0, 1.0)
        blob = maxf(blob, BLOB_ALPHA * fall * fall)
    return maxf(ring, blob)


## The sweep's layer, "Line art", above the active one, as the harness writes
## it: *colour* wherever the picture has coverage, in the document's numbers.
func _line_art(colour: Color) -> SaLayer:
    var stored := _doc.color_space.from_display(colour)
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
    return _write(floats)


## *floats* through the harness's `write_pixels`, into a new layer over WRITTEN,
## and the merged picture brought up to date the way a frame would.
func _write(floats: PackedFloat32Array) -> SaLayer:
    var file := FileAccess.open(_folder.path_join("line-art.npy"), FileAccess.WRITE)
    file.store_buffer(PixelDriver.Npy.header(WRITTEN.size))
    file.store_buffer(floats.to_byte_array())
    file.close()
    var rect := [WRITTEN.position.x, WRITTEN.position.y, WRITTEN.size.x, WRITTEN.size.y]
    var answer := PixelDriver.write_from(_doc, {"new_layer": "Line art", "rect": rect, "file": "line-art.npy"}, _folder)
    assert_false(answer.has("error"), "The harness wrote the layer: %s" % answer)
    _surface.easel.request_full_composite()
    _surface.easel.process_pending_composite()
    return _doc.active_layer


func _fill() -> Object:
    var fill := StateBucketFillScript.new()
    fill.surface = _surface
    SaColors.foreground = BLUE
    return fill


func _wand(merged: bool, tolerance: float = 0.1) -> Object:
    var wand := StateWandScript.new()
    wand.surface = _surface
    wand.sample_merged = merged
    wand.tolerance = tolerance
    return wand


## The layer's texel at *at* in the document's numbers, transparent where the
## layer holds no chunk.
func _texel(layer: SaLayer, at: Vector2i) -> Color:
    var grid := Vector2i(floori(float(at.x) / SaChunk.SIZE), floori(float(at.y) / SaChunk.SIZE))
    var chunk: SaChunk = layer.chunks.get(grid, null)
    if chunk == null:
        return Color(0, 0, 0, 0)
    var texture: SaTexture = chunk.field(chunk.fields.keys()[0])
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    var local := at - grid * SaChunk.SIZE
    return SaFieldSpec.decode_texel(bytes, texture.format, local.y * texture.size.x + local.x)


func _selected(at: Vector2i) -> float:
    var grid := Vector2i(floori(float(at.x) / SaChunk.SIZE), floori(float(at.y) / SaChunk.SIZE))
    var chunk: SaChunk = _doc.selection.chunks.get(grid, null)
    if chunk == null:
        return 0.0
    var texture := chunk.field(SaSelection.FIELD)
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    var local := at - grid * SaChunk.SIZE
    return SaFieldSpec.decode_texel(bytes, texture.format, local.y * texture.size.x + local.x).r


## Whether the layer holds *colour*, opaque or nearly, at *at*.
func _is(layer: SaLayer, at: Vector2i, colour: Color) -> bool:
    var stored := _doc.color_space.from_display(colour)
    var texel := _texel(layer, at)
    var off := maxf(absf(texel.r - stored.r), maxf(absf(texel.g - stored.g), absf(texel.b - stored.b)))
    return texel.a > 0.9 and off < 0.01


## The ask's own gesture: Fill at 10 percent on the middle of a blob colours
## that blob and nothing else.
func test_a_fill_on_a_dark_blob_colours_the_blob_and_leaves_the_rest() -> void:
    var layer := _line_art(INK)
    var chunks := layer.chunks.size()
    var touched: int = _fill().fill_at(Vector2i(BLOB))

    assert_true(touched > 0, "The click painted, %d chunk(s)" % touched)
    assert_true(_is(layer, Vector2i(BLOB), BLUE), "The blob's middle took the blue")
    assert_true(_is(layer, ON_RING, INK), "The ring is still ink")
    assert_true(_is(layer, Vector2i(OTHER_BLOB), INK), "and so is the other blob")
    assert_almost_eq(_texel(layer, GROUND).a, 0.0, 0.001, "The ground between them is still empty")
    assert_almost_eq(_texel(layer, RING_HOLE).a, 0.0, 0.001, "and so is the ring's hole")
    assert_almost_eq(_texel(layer, FAR_GROUND).a, 0.0, 0.001, "and the ground past what the layer held")
    assert_eq(layer.chunks.size(), chunks, "The fill made no chunk the blob does not reach")


## A click on the ring recolours the ring alone, all the way round.
func test_a_fill_on_the_ring_recolours_the_ring_alone() -> void:
    var layer := _line_art(INK)
    _fill().fill_at(ON_RING)

    assert_true(_is(layer, ON_RING, BLUE), "The ring took the blue where it was clicked")
    assert_true(_is(layer, RING_FAR_SIDE, BLUE), "and on its far side")
    assert_almost_eq(_texel(layer, RING_HOLE).a, 0.0, 0.001, "The hole is still empty")
    assert_almost_eq(_texel(layer, GROUND).a, 0.0, 0.001, "and so is the ground")
    assert_true(_is(layer, Vector2i(BLOB), INK), "The blobs are still ink")
    assert_true(_is(layer, Vector2i(OTHER_BLOB), INK), "both of them")


## Contiguous off is the same distance, so the ring, which is within 10
## percent of the blob's middle, joins it, and the ground still does not.
func test_contiguous_off_takes_the_matching_ink_and_leaves_the_ground() -> void:
    var layer := _line_art(INK)
    var fill := _fill()
    fill.contiguous = false
    fill.fill_at(Vector2i(BLOB))

    assert_true(_is(layer, Vector2i(OTHER_BLOB), BLUE), "The other blob's middle matches")
    assert_almost_eq(_texel(layer, GROUND).a, 0.0, 0.001, "and the ground does not")
    assert_almost_eq(_texel(layer, FAR_GROUND).a, 0.0, 0.001, "here or past the layer's chunks")


## The wand shares the kernel, so a click on the blob selects the blob,
## whichever picture it reads.
func test_the_wand_on_a_blob_selects_the_blob() -> void:
    _line_art(INK)
    for merged: bool in [true, false]:
        _doc.selection.deselect()
        _wand(merged).flood(Vector2i(BLOB))
        assert_almost_eq(_selected(Vector2i(BLOB)), 1.0, 0.001, "The blob is selected, merged %s" % merged)
        assert_almost_eq(_selected(ON_RING), 0.0, 0.001, "the ring is not, merged %s" % merged)
        assert_almost_eq(_selected(Vector2i(OTHER_BLOB)), 0.0, 0.001, "nor the other blob, merged %s" % merged)
        assert_almost_eq(_selected(GROUND), 0.0, 0.001, "nor the ground, merged %s" % merged)
        assert_almost_eq(_selected(FAR_GROUND), 0.0, 0.001, "nor the ground past the layer, merged %s" % merged)


## The soft edge still answers to the tolerance. The flank holds about half the
## middle's alpha, so it is out at 10 percent and in at 80, while the empty
## ground, a whole 0.95 of alpha away, stays out of both.
func test_a_soft_edge_joins_the_middle_at_a_high_tolerance() -> void:
    var layer := _line_art(INK)
    var flank := _texel(layer, BLOB_FLANK).a
    assert_true(flank > 0.4 and flank < 0.6, "The flank holds about half the alpha, %.3f" % flank)

    _wand(false, 0.1).flood(Vector2i(BLOB))
    assert_almost_eq(_selected(BLOB_FLANK), 0.0, 0.001, "At 10 percent the flank is not the middle's colour")
    _doc.selection.deselect()
    _wand(false, 0.8).flood(Vector2i(BLOB))
    assert_almost_eq(_selected(BLOB_FLANK), 1.0, 0.001, "At 80 it is")
    assert_almost_eq(_selected(GROUND), 0.0, 0.001, "and the empty ground is still not")


## The sibling case: an opaque mid grey on a layer read alone,
## in an sRGB document where the old neutral backdrop was that same grey, so
## every empty texel was seen as the seed.
func test_a_fill_on_an_opaque_grey_leaves_the_empty_ground() -> void:
    _doc.color_space = SaColorSpace.srgb()
    var floats := PackedFloat32Array()
    floats.resize(WRITTEN.size.x * WRITTEN.size.y * 4)
    for y in range(100, 200):
        for x in range(100, 200):
            var at := (y * WRITTEN.size.x + x) * 4
            floats[at] = GREY.r
            floats[at + 1] = GREY.g
            floats[at + 2] = GREY.b
            floats[at + 3] = 1.0
    var layer := _write(floats)
    _fill().fill_at(Vector2i(150, 150))

    assert_true(_is(layer, Vector2i(150, 150), BLUE), "The grey square took the blue")
    assert_almost_eq(_texel(layer, Vector2i(20, 20)).a, 0.0, 0.001, "and the ground beside it is still empty")
    assert_almost_eq(_texel(layer, FAR_GROUND).a, 0.0, 0.001, "here and past the layer's chunks")
