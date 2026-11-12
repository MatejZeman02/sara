## The fill finds its region on a reference layer chosen by name.
##
## A comic painter fills a flat colour layer under the line art and wants the
## region found on the line art, not on the empty colour layer nor on the
## merged picture with the flats already laid.
##
## With a layer named, the region is found on that layer's colours and painted on
## the active layer, and the reference layer is never written. A named layer
## that is gone, or the active layer itself, finds the region as with none, and
## the bar says so.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const StateBucketFillScript = preload("res://modules/sara-base-modules/base/tools/state_bucket_fill.gd")
const BaseModuleScript = preload("res://modules/sara-base-modules/base/module.gd")
const PixelDriver = preload("res://harness/scenario/sa_scenario_pixels.gd")
const Fixtures = preload("res://tests/fixtures.gd")

const INK := Color(0.04, 0.04, 0.05, 1.0)
const BLUE := Color(0.1, 0.4, 0.9, 1.0)

const CENTRE := Vector2(256.0, 256.0)
const INNER := 90.0
const OUTER := 100.0

const WRITTEN := Rect2i(0, 0, 512, 512)
const CANVAS := Vector2i(768, 768)

const MIDDLE := Vector2i(256, 256)
const BY_THE_WALL := Vector2i(340, 256)
const BESIDE_THE_RING := Vector2i(370, 256)
const FAR_GROUND := Vector2i(650, 650)

var _surface: SaSurface = null
var _doc: SaDocument = null
var _folder: String = ""


func before_each() -> void:
    _surface = Fixtures.make_surface(CANVAS)
    _doc = _surface.get_document()
    _folder = OS.get_temp_dir().path_join("sara-reference-fill-%d" % OS.get_process_id())
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


func _ring(name: String = "Ring") -> SaLayer:
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


## A closed ring on one layer, an empty layer below it active, a fill inside the
## ring with the ring's layer as reference, reading the active layer filled inside
## the ring and nowhere outside, and the ring's layer unchanged texel for texel.
func test_fill_finds_region_on_reference_layer_and_paints_on_active_layer() -> void:
    var colour_layer := _doc.active_layer
    colour_layer.name = "Colour"
    var ring_layer := _ring("LineArt")

    var rd := GlobalShaderCompiler.get_rd()
    var before_data: Dictionary = {}
    for grid_pos: Vector2i in ring_layer.chunks:
        var chunk: SaChunk = ring_layer.chunks[grid_pos]
        var texture: SaTexture = chunk.field(chunk.fields.keys()[0])
        before_data[grid_pos] = rd.texture_get_data(texture.rid, 0)

    _doc.set_active_layer(colour_layer)
    assert_eq(_doc.active_layer, colour_layer, "The empty colour layer is active")

    var fill := StateBucketFillScript.new()
    fill.surface = _surface
    fill.reference_layer = "LineArt"
    fill.antialias = false
    SaColors.foreground = BLUE

    var touched := fill.fill_at(MIDDLE)
    assert_true(touched > 0, "The fill touched chunks on the active layer")

    var inside := _texel(colour_layer, MIDDLE)
    assert_almost_eq(inside.a, 1.0, 0.02, "Active layer is filled at the middle")
    assert_almost_eq(inside.b, BLUE.b, 0.05, "in the fill colour")

    var near_wall := _texel(colour_layer, BY_THE_WALL)
    assert_almost_eq(near_wall.a, 1.0, 0.02, "Active layer is filled inside near the ring")

    var outside := _texel(colour_layer, BESIDE_THE_RING)
    assert_almost_eq(outside.a, 0.0, 0.01, "Active layer is untouched outside the ring")

    var far := _texel(colour_layer, FAR_GROUND)
    assert_almost_eq(far.a, 0.0, 0.01, "Active layer is untouched on the far ground")

    assert_eq(ring_layer.chunks.size(), before_data.size(), "Ring layer chunk count is unchanged")
    for grid_pos: Vector2i in before_data:
        assert_true(ring_layer.chunks.has(grid_pos), "Ring layer holds chunk %s" % [grid_pos])
        var chunk: SaChunk = ring_layer.chunks[grid_pos]
        var texture: SaTexture = chunk.field(chunk.fields.keys()[0])
        var after_bytes := rd.texture_get_data(texture.rid, 0)
        assert_eq(after_bytes, before_data[grid_pos], "Ring layer is unchanged byte for byte at chunk %s" % [grid_pos])


## Deleting the reference layer and filling again causes the fill to find its
## region as with none.
func test_deleting_reference_layer_finds_region_as_with_none() -> void:
    var colour_layer := _doc.active_layer
    colour_layer.name = "Colour"
    var ring_layer := _ring("LineArt")

    _doc.set_active_layer(colour_layer)

    var fill := StateBucketFillScript.new()
    fill.surface = _surface
    fill.reference_layer = "LineArt"
    fill.antialias = false
    SaColors.foreground = BLUE

    fill.fill_at(MIDDLE)
    assert_almost_eq(_texel(colour_layer, BESIDE_THE_RING).a, 0.0, 0.01, "First fill stopped at the ring")

    var specs := StateBucketFillScript.fill_options()
    var ref_spec: SaOptionSpec = specs[5]
    var control := ref_spec.build_control.call(ref_spec, Callable()) as SaChoiceButton
    control.set_meta(&"document", _doc)
    ref_spec.bind_value.call(control, "LineArt")
    assert_eq(control.text, "LineArt", "Options bar shows LineArt selected before deletion")
    _doc.child_order_changed.connect(StateBucketFillScript._on_doc_structure_changed.bind(control))

    _doc.remove_child(ring_layer)
    ring_layer.free()
    _doc.clear_layer(colour_layer)

    assert_eq(control.text, "None (gone)", "The options bar updates live to say None (gone) when the reference layer is gone")
    _doc.child_order_changed.disconnect(StateBucketFillScript._on_doc_structure_changed.bind(control))
    control.free()

    assert_almost_eq(_texel(colour_layer, MIDDLE).a, 0.0, 0.01, "Active layer is cleared")

    fill.fill_at(MIDDLE)

    assert_almost_eq(_texel(colour_layer, MIDDLE).a, 1.0, 0.02, "Middle is filled")
    assert_almost_eq(
        _texel(colour_layer, BESIDE_THE_RING).a, 1.0, 0.02, "Beside the ring is filled because the reference layer is gone"
    )
    assert_almost_eq(
        _texel(colour_layer, FAR_GROUND).a, 1.0, 0.02, "Far ground is filled as with none over the whole empty canvas"
    )


## When the active layer itself is named as reference, the fill finds its region
## as with none.
func test_active_layer_as_reference_finds_region_as_with_none() -> void:
    var colour_layer := _doc.active_layer
    colour_layer.name = "Colour"

    var fill := StateBucketFillScript.new()
    fill.surface = _surface
    fill.reference_layer = "Colour"
    fill.antialias = false
    SaColors.foreground = BLUE

    fill.fill_at(MIDDLE)
    assert_almost_eq(_texel(colour_layer, FAR_GROUND).a, 1.0, 0.02, "Active layer fills as with none")


## The reference option dropdown control shows document layers and reports state
## when none, active, or gone.
func test_reference_option_choice_control() -> void:
    var colour_layer := _doc.active_layer
    colour_layer.name = "Colour"
    var ring_layer := _ring("LineArt")
    _doc.set_active_layer(colour_layer)

    var specs := StateBucketFillScript.fill_options()
    var ref_spec: SaOptionSpec = null
    for s in specs:
        if s.key == &"fill_reference":
            ref_spec = s
            break
    assert_not_null(ref_spec, "The fill options declare fill_reference")

    var writes: Array = []
    var write := func(val: Variant) -> void: writes.append(val)
    var control := ref_spec.build_control.call(ref_spec, write) as SaChoiceButton
    assert_not_null(control, "The reference control is an SaChoiceButton")
    control.set_meta(&"document", _doc)

    ref_spec.bind_value.call(control, "")
    assert_eq(control.text, "None", "Empty reference displays None")
    assert_true(control.choice_labels().has("None"), "Choice list includes None")
    assert_true(control.choice_labels().has("LineArt"), "Choice list includes LineArt")
    assert_true(control.choice_labels().has("Colour"), "Choice list includes Colour")

    ref_spec.bind_value.call(control, "LineArt")
    assert_eq(control.text, "LineArt", "Valid reference layer displays its name")

    ref_spec.bind_value.call(control, "Colour")
    assert_eq(control.text, "None (active)", "Active layer as reference displays None (active)")

    ref_spec.bind_value.call(control, "NonExistentLayer")
    assert_eq(control.text, "None (gone)", "Deleted layer displays None (gone)")

    control.free()
    ring_layer.free()
