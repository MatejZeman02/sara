## A group chosen as the fill's reference fills by what the group shows.
##
## A painter keeps the line art in a group named Lines, makes another layer
## active, names Lines as the Bucket's reference and clicks inside a closed
## ring. A group holds no paint of its own, so the flood read it as empty and
## took the whole canvas. Here the region is found on the picture the group
## shows, with Contiguous on and off, and a mask on the group that hides half
## the ring lets the fill out through that half, which shows the region follows
## what the group shows and not what its members hold.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const StateBucketFillScript = preload("res://modules/sara-base-modules/base/tools/state_bucket_fill.gd")
const PixelDriver = preload("res://harness/scenario/sa_scenario_pixels.gd")
const Fixtures = preload("res://tests/fixtures.gd")

const INK := Color(0.04, 0.04, 0.05, 1.0)
const PAPER := Color(0.95, 0.93, 0.88, 1.0)
const BLUE := Color(0.1, 0.4, 0.9, 1.0)

const CENTRE := Vector2(256.0, 256.0)
const INNER := 90.0
const OUTER := 100.0

const WRITTEN := Rect2i(0, 0, 512, 512)
const CANVAS := Vector2i(768, 768)

## Inside the ring, in its left half, which the mask leaves shown.
const INSIDE := Vector2i(200, 256)
const BESIDE_THE_RING := Vector2i(370, 256)
const LEFT_OF_THE_RING := Vector2i(130, 256)
const FAR_GROUND := Vector2i(650, 650)

var _surface: SaSurface = null
var _doc: SaDocument = null
var _folder: String = ""


func before_each() -> void:
    _surface = Fixtures.make_surface(CANVAS)
    _doc = _surface.get_document()
    _folder = OS.get_temp_dir().path_join("sara-group-reference-%d" % OS.get_process_id())
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
    return clampf(OUTER + 0.5 - d, 0.0, 1.0) * clampf(d - INNER + 0.5, 0.0, 1.0)


## The ring of ink on a new layer named *name*, and with *papered* its inside
## laid with paper, so the inside and the ground outside differ.
func _ring(name: String = "Ring", papered: bool = false) -> SaLayer:
    var stored := _doc.color_space.from_display(INK)
    var paper := _doc.color_space.from_display(PAPER)
    var floats := PackedFloat32Array()
    floats.resize(WRITTEN.size.x * WRITTEN.size.y * 4)
    for y in WRITTEN.size.y:
        for x in WRITTEN.size.x:
            var centre := Vector2(x, y) + Vector2(0.5, 0.5)
            var alpha := _coverage_at(centre)
            var at := (y * WRITTEN.size.x + x) * 4
            if papered and alpha <= 0.0 and centre.distance_to(CENTRE) < INNER:
                floats[at] = paper.r
                floats[at + 1] = paper.g
                floats[at + 2] = paper.b
                floats[at + 3] = 1.0
                continue
            if alpha <= 0.0:
                continue
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


## The empty colour layer, and the ring on a layer of its own inside a group
## named Lines, the colour layer active again and the fill's reference Lines.
func _lines(papered: bool = false) -> Array:
    var colour_layer := _doc.active_layer
    colour_layer.name = "Colour"
    var ring_layer := _ring("Ink", papered)
    var group := SaLayerOps.new(_doc).group_layers([ring_layer])
    assert_not_null(group, "The ring's layer was grouped")
    group.name = "Lines"
    assert_true(SaLayerStack.is_inside(ring_layer, group), "The ring's layer is inside Lines")
    _doc.set_active_layer(colour_layer)
    assert_eq(_doc.active_layer, colour_layer, "The empty colour layer is active")
    return [colour_layer, ring_layer, group]


func _fill(contiguous: bool) -> int:
    var fill := StateBucketFillScript.new()
    fill.surface = _surface
    fill.reference_layer = "Lines"
    fill.antialias = false
    fill.contiguous = contiguous
    SaColors.foreground = BLUE
    return fill.fill_at(INSIDE)


func _bytes(layer: SaLayer) -> Dictionary:
    var rd := GlobalShaderCompiler.get_rd()
    var out: Dictionary = {}
    for grid_pos: Vector2i in layer.chunks:
        var chunk: SaChunk = layer.chunks[grid_pos]
        out[grid_pos] = rd.texture_get_data(chunk.field(chunk.fields.keys()[0]).rid, 0)
    return out


## Contiguous on: the fill stops at the ring the group shows, and the ring's
## layer and the group are left as they were.
func test_a_group_as_reference_stops_the_flood_at_its_ring() -> void:
    var made := _lines()
    var colour_layer: SaLayer = made[0]
    var ring_layer: SaLayer = made[1]
    var group: SaLayer = made[2]
    var ring_before := _bytes(ring_layer)
    var count := _doc.get_child_count()

    assert_true(_fill(true) > 0, "The fill touched chunks on the active layer")

    var inside := _texel(colour_layer, INSIDE)
    assert_almost_eq(inside.a, 1.0, 0.02, "The active layer is filled inside the ring")
    assert_almost_eq(inside.b, BLUE.b, 0.05, "in the fill colour")
    assert_almost_eq(_texel(colour_layer, BESIDE_THE_RING).a, 0.0, 0.01, "and not beside the ring")
    assert_almost_eq(_texel(colour_layer, FAR_GROUND).a, 0.0, 0.01, "nor on the far ground")
    assert_eq(_bytes(ring_layer), ring_before, "The ring's layer is unchanged texel for texel")
    assert_true(group.chunks.is_empty(), "The group still holds no paint of its own")
    assert_eq(_doc.get_child_count(), count, "The picture the flood read never entered the document")


## Contiguous off: `select_matching` reads the group too. The ring's inside is
## laid with paper, so every texel the colour of the clicked one is the
## inside, and the fill reaches the whole of it and none of the ground outside
## the ring, though nothing joins the two.
func test_a_group_as_reference_is_read_with_contiguous_off() -> void:
    var made := _lines(true)
    var colour_layer: SaLayer = made[0]

    assert_true(_fill(false) > 0, "The fill touched chunks on the active layer")

    assert_almost_eq(_texel(colour_layer, INSIDE).a, 1.0, 0.02, "The ring's inside is filled")
    assert_almost_eq(_texel(colour_layer, Vector2i(300, 230)).a, 1.0, 0.02, "across the whole of it")
    var on_ring := Vector2i(int(CENTRE.x) + 95, int(CENTRE.y))
    assert_almost_eq(_texel(colour_layer, on_ring).a, 0.0, 0.01, "The ring itself is not filled")
    assert_almost_eq(_texel(colour_layer, BESIDE_THE_RING).a, 0.0, 0.01, "nor the ground beside it")
    assert_almost_eq(_texel(colour_layer, FAR_GROUND).a, 0.0, 0.01, "nor the far ground")


## Contiguous off over a ring that is the only thing in a ground of its own
## colour: with an ink ring and a click on the ink, only the ring is filled,
## which the empty reading of today, the whole canvas, cannot give.
func test_a_click_on_the_ring_with_contiguous_off_fills_the_ring_alone() -> void:
    var made := _lines()
    var colour_layer: SaLayer = made[0]
    var fill := StateBucketFillScript.new()
    fill.surface = _surface
    fill.reference_layer = "Lines"
    fill.antialias = false
    fill.contiguous = false
    SaColors.foreground = BLUE
    var on_ring := Vector2i(int(CENTRE.x) - 95, int(CENTRE.y))
    assert_true(fill.fill_at(on_ring) > 0, "The fill touched chunks on the active layer")

    assert_almost_eq(_texel(colour_layer, on_ring).a, 1.0, 0.02, "The ring is filled")
    assert_almost_eq(_texel(colour_layer, INSIDE).a, 0.0, 0.01, "and its inside is not")
    assert_almost_eq(_texel(colour_layer, FAR_GROUND).a, 0.0, 0.01, "nor the ground outside it")


## A mask on the group hides the ring's right half, the chunks from x 256 on,
## so the group shows a broken ring and the fill leaks out through the gap to
## the ground beside the ring and far from it.
func test_a_mask_on_the_group_lets_the_fill_out_where_it_hides_the_ring() -> void:
    var made := _lines()
    var colour_layer: SaLayer = made[0]
    var group: SaLayer = made[2]
    var mask := group.add_mask(1.0)
    for grid_pos: Vector2i in [Vector2i(1, 0), Vector2i(1, 1)]:
        var hidden := mask.get_or_create(grid_pos)
        hidden.clear(Color(0.0, 0.0, 0.0, 0.0))
        # A transfer is not ordered against the compute that reads it, and a
        # read back waits for it.
        GlobalShaderCompiler.get_rd().texture_get_data(hidden.rid, 0)

    assert_true(_fill(true) > 0, "The fill touched chunks on the active layer")

    assert_almost_eq(_texel(colour_layer, INSIDE).a, 1.0, 0.02, "The ring's inside is filled")
    assert_almost_eq(_texel(colour_layer, BESIDE_THE_RING).a, 1.0, 0.02, "and past the hidden half beside the ring")
    assert_almost_eq(_texel(colour_layer, FAR_GROUND).a, 1.0, 0.02, "and on the far ground")
    var shown_ring := Vector2i(int(CENTRE.x) - 95, int(CENTRE.y))
    assert_almost_eq(_texel(colour_layer, shown_ring).a, 0.0, 0.01, "but not on the half of the ring the mask shows")
