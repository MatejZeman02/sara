## Paint moves the surface towards the brush's own height
## rewritten when the ceiling went).
##
## The door's `height_deposit` library moves the surface a texel shows, the
## surface beneath its layer plus the layer's own height, towards the brush's
## height by the brush's load times its coverage times a mobility, and the
## layer keeps the new surface less the surface beneath. `SaStrokeHeights`
## hands a writer the layer's height and that surface beneath. The writer here
## is a fixture kernel that imports the library and lays a round dab of it,
## driven through the same `SaPaintContext` targets an engine gets, so the rule
## is held apart from any engine's field. The eraser's half is the stamp
## brush's own kernel and the document's own commit. Every height is a texel
## read back, because a height that came back zero looks like a height nobody
## painted rather than like a fault.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const SaBrushTipScript = preload("res://core/api/tip/sa_brush_tip.gd")
const StateBrushScript = preload("res://modules/sara-base-modules/stamp-brush/tools/state_brush.gd")

## The fixture writer's shader name and where its source is written, under
## `user://` so the boot walk never compiles it, the route
## `tests/fixtures/paint_kernel.gd` takes and says why.
const WRITER := "height_mix_fixture"
static var scratch_writer_path: String = SaDataRoot.path("height_mix_fixture.gmacs")

const WRITER_SOURCE := """# A round dab of height, the smallest writer of the deposition library.

kernel height_mix

import height_deposit

image height: r16f
image beneath: r16f, readonly

params:
    vec2 centre
    vec2 offset
    float radius
    float brush
    float paint_load
    float pad


def height_mix():
    ivec2 pixel = ivec2(global_id.xy) + ivec2(offset)
    if pixel.x >= image_size(height).x or pixel.y >= image_size(height).y:
        return
    float coverage = clamp(radius - distance(vec2(pixel), centre), 0.0, 1.0)
    if coverage <= 0.0:
        return
    float under = image_load(beneath, pixel).r
    float thick = image_load(height, pixel).r
    image_store(height, pixel, vec4(sa_height_mixed(thick, under, brush, paint_load, coverage), 0.0, 0.0, 1.0))
"""

## Where the one-texel suites work, well inside the first chunk.
const SPOT := Vector2(100.0, 100.0)

var _registries: SaRegistries = null
var _easel: SaEasel = null
var _doc: SaDocument = null
var _writer: SaCompute = null


func before_each() -> void:
    _registries = Fixtures.make_registries()
    _easel = SaEasel.create_default(Vector2i(768, 768))
    _easel.compositor.set_registry(_registries.blend_modes)
    _doc = _easel.document
    if GlobalShaderCompiler.get_kernel_names(WRITER).is_empty():
        var file := FileAccess.open(scratch_writer_path, FileAccess.WRITE)
        file.store_string(WRITER_SOURCE)
        file.close()
        GlobalShaderCompiler.compile_compute_shader(scratch_writer_path)
    _writer = SaCompute.new(WRITER)


func after_each() -> void:
    _writer = null
    _easel.free()
    _easel = null
    _doc = null
    _registries = null


## One dab of the fixture writer at *centre*, document pixels, over every
## chunk it reaches, through `reach` and `beneath` the way an engine would.
func _dab(heights: SaStrokeHeights, centre: Vector2, radius: float, brush: float, paint_load: float) -> void:
    var region := Rect2(centre - Vector2(radius, radius), Vector2(radius, radius) * 2.0)
    var paint := SaPaintContext.for_region(_doc, region, false)
    for target: SaPaintContext.Target in paint.targets:
        var height := heights.reach(target.grid_pos)
        var beneath := heights.beneath(target.grid_pos)
        if height == null or beneath == null:
            continue
        _writer.set_texture(0, height.rid)
        _writer.set_texture(1, beneath.rid)
        var local := paint.local_point(target, centre)
        _writer.set_push_constant_float_array(
            PackedFloat32Array([local.x, local.y, target.render_offset.x, target.render_offset.y, radius, brush, paint_load, 0.0])
        )
        _writer.dispatch_kernel("height_mix", target.groups_x, target.groups_y, 1)
    paint.commit_invalidation()


## A stroke of *dabs* dabs at *centre* on the active layer, begun and
## committed on the document.
func _stroke(centre: Vector2, dabs: int, brush: float, paint_load: float, radius: float = 6.0) -> void:
    _doc.begin_stroke(1.0, SaLayer.BLEND_MODE.NORMAL)
    var heights := SaStrokeHeights.new(_doc, _doc.active_layer)
    for i in dabs:
        _dab(heights, centre, radius, brush, paint_load)
    _doc.commit_stroke()


## *layer*'s height at a document texel, zero where it holds none. The active
## layer's when none is named.
func _height(at: Vector2i, layer: SaLayer = null) -> float:
    var reading := layer if layer != null else _doc.active_layer
    var grid := Vector2i(floori(at.x / float(SaLayer.CHUNK_SIZE)), floori(at.y / float(SaLayer.CHUNK_SIZE)))
    var texture := reading.get_field(grid, SaFieldSpec.HEIGHT)
    if texture == null:
        return 0.0
    var local := at - grid * SaLayer.CHUNK_SIZE
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    return bytes.decode_half((local.y * texture.size.x + local.x) * 2)


## The relief the view sums over *rect*, document texel -> millimetres,
## resolved afresh.
func _relief(rect: Rect2i) -> Dictionary[Vector2i, float]:
    _easel.request_full_composite()
    _easel.process_pending_composite()
    var out: Dictionary[Vector2i, float] = {}
    var heights := _easel.relief.heights
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(heights.rid, 0)
    for y in rect.size.y:
        for x in rect.size.x:
            var at := rect.position + Vector2i(x, y)
            out[at] = bytes.decode_half((at.y * heights.size.x + at.x) * 2)
    return out


## The lowest and highest of *values*.
static func _span(values: Array) -> Vector2:
    return Vector2(values.min(), values.max())


## Fills the active layer's height in the chunk at *grid* with *value*, and its
## colour with opaque white, the ground the eraser suites lower.
func _ground(grid: Vector2i, value: float) -> SaTexture:
    SaHeightOps.new(_doc).gain(_doc.active_layer)
    var height := _doc.active_layer.get_or_create_field(grid, SaFieldSpec.HEIGHT)
    var bytes := PackedByteArray()
    bytes.resize(height.size.x * height.size.y * 2)
    for i in height.size.x * height.size.y:
        bytes.encode_half(i * 2, value)
    GlobalShaderCompiler.get_rd().texture_update(height.rid, 0, bytes)
    _doc.active_layer.get_or_create_chunk(grid).albedo().clear(Color(1.0, 1.0, 1.0, 1.0))
    return height


func _approaches_the_brushs_height_at(paint_load: float) -> void:
    var brush := 1.5
    _doc.begin_stroke(1.0, SaLayer.BLEND_MODE.NORMAL)
    var heights := SaStrokeHeights.new(_doc, _doc.active_layer)
    var spot := Vector2i(SPOT)
    var last := 0.0
    var over := 0
    var fell := 0
    var off_course := 0
    for i in 100:
        _dab(heights, SPOT, 6.0, brush, paint_load)
        var now := _height(spot)
        if now > brush:
            over += 1
        if now < last:
            fell += 1
        # The rule's own curve, a share *paint_load* of the gap each dab. A half
        # float that truncates each store lags it by up to one of its steps a
        # dab, and the lag settles where the share of the gap is one step,
        # a step of 1.5 over the load.
        if absf(now - brush * (1.0 - pow(1.0 - paint_load, i + 1))) > 0.001 / paint_load + 0.002:
            off_course += 1
        last = now
    _doc.commit_stroke()
    assert_eq(over, 0, "At a load of %.2f no dab of a hundred leaves the texel above the brush's height" % paint_load)
    assert_eq(fell, 0, "and none lowers it")
    assert_eq(off_course, 0, "and every dab moves it by the load's share of the gap")
    assert_almost_eq(last, brush, brush * 0.01, "A hundred dabs bring it within a hundredth of the brush's height")


func test_a_hundred_dabs_approach_the_brushs_height_and_never_pass_it_at_a_light_load() -> void:
    _approaches_the_brushs_height_at(0.05)


func test_a_hundred_dabs_approach_the_brushs_height_and_never_pass_it_at_a_heavy_load() -> void:
    _approaches_the_brushs_height_at(0.3)


## There is no ceiling and nothing to stack on: twenty strokes of one brush
## over one spot settle at its height, the first at full load reaching it and
## none of the others moving it.
func test_strokes_of_one_brush_settle_at_its_height_rather_than_stacking() -> void:
    var brush := 0.6
    var spot := Vector2i(SPOT)
    var moved := PackedStringArray()
    for stroke in 20:
        _stroke(SPOT, 3, brush, 1.0)
        var now := _height(spot)
        if absf(now - brush) > 0.0005:
            moved.append("stroke %d stands at %.4f" % [stroke + 1, now])
    assert_true(moved.is_empty(), "Every stroke leaves the spot at the brush's 0.6: %s" % ", ".join(moved))


## The mobility: a surface at or below the brush's height gives way wholly,
## and one above it moves by the brush's height over its own, so a bump four
## times the brush's height closes a quarter of the gap in one full dab and a
## bump at twice it half.
func test_a_bump_moves_less_the_higher_it_stands_above_the_brush() -> void:
    var brush := 0.5
    var cases := [[0.2, 0.5], [0.5, 0.5], [1.0, 0.75], [2.0, 1.625]]
    for case: Array in cases:
        _ground(Vector2i.ZERO, case[0])
        _stroke(SPOT, 1, brush, 1.0)
        var now := _height(Vector2i(SPOT))
        var said := "A surface at %.2f under one full dab of a 0.5 mm brush stands at %.4f" % [case[0], case[1]]
        assert_almost_eq(now, case[1], 0.002, said)


## A brush of nought moves nothing that stands above it, and a load of nought
## moves nothing at all.
func test_a_brush_of_nought_and_a_load_of_nought_leave_the_surface() -> void:
    _ground(Vector2i.ZERO, 1.0)
    _stroke(SPOT, 5, 0.0, 1.0)
    assert_eq(_height(Vector2i(SPOT)), 1.0, "A brush of nought leaves a millimetre of paint standing")
    _stroke(SPOT, 5, 0.5, 0.0)
    assert_eq(_height(Vector2i(SPOT)), 1.0, "and a load of nought leaves it too")


## A bump on a lower layer is part of the surface the stroke moves: a lower
## brush lowers the sum, the painted layer keeps the difference, negative, and
## the lower layer keeps its own height.
func test_a_bump_on_a_lower_layer_is_lowered_by_a_negative_height_above_it() -> void:
    var below := _doc.active_layer
    _ground(Vector2i.ZERO, 2.0)
    var painted := SaLayerOps.new(_doc).add()
    _doc.set_active_layer(painted)
    _stroke(SPOT, 1, 0.5, 1.0)
    var took := _height(Vector2i(SPOT), painted)
    assert_almost_eq(took, -0.375, 0.002, "The painted layer stores the 0.375 the stroke took off the 2 mm bump")
    assert_eq(_height(Vector2i(SPOT), below), 2.0, "and the lower layer keeps its own 2 mm")
    _stroke(SPOT, 1, 3.0, 1.0)
    var raised := _height(Vector2i(SPOT), painted)
    assert_almost_eq(raised, 1.0, 0.002, "A brush above the surface raises it to its own 3 mm, a millimetre over the bump")


## The paper's tooth is part of the surface a stroke stands on, and the
## stroke fills it rather than the view: a full dab over the paper leaves the
## layer holding the brush's height less the tooth, and the relief the view
## sums, the tooth added whole under that, stands flat at the brush's height.
func test_a_full_dab_over_the_papers_tooth_levels_the_relief_the_view_shows() -> void:
    var painted := _doc.active_layer
    SaLayerOps.new(_doc).add(&"paper", _registries.layer_types)
    _doc.set_active_layer(painted)
    # Wholly covered by a dab of radius 40 at the spot.
    var window := Rect2i(Vector2i(SPOT) - Vector2i(25, 25), Vector2i(51, 51))
    var tooth := _relief(window)
    var bare := _span(tooth.values())
    assert_true(bare.y - bare.x > 0.03, "The paper's tooth spans %.4f to %.4f mm before the dab" % [bare.x, bare.y])
    _stroke(SPOT, 1, 1.0, 1.0, 40.0)
    var shown := _span(_relief(window).values())
    assert_true(
        shown.x > 0.99 and shown.y < 1.01, "The view's relief stands from %.4f to %.4f mm under a 1 mm brush" % [shown.x, shown.y]
    )
    assert_true(
        shown.y - shown.x < (bare.y - bare.x) * 0.1,
        "flat to %.4f mm where the tooth spanned %.4f mm, the fibres overlaid" % [shown.y - shown.x, bare.y - bare.x]
    )
    var off := 0.0
    for at: Vector2i in tooth:
        off = maxf(off, absf(_height(at) - (1.0 - tooth[at])))
    assert_true(off < 0.003, "and the layer holds the brush's height less the tooth, within %.4f mm" % off)


## The first height-writing dab gains the layer its height as a step, and
## undo takes the stroke and then the step back.
func test_the_first_dab_gains_the_height_and_undo_takes_it_back() -> void:
    var layer := _doc.active_layer
    assert_false(layer.carries_height(), "A new paint layer carries no height")
    _stroke(SPOT, 10, 1.0, 1.0)
    assert_true(layer.carries_height(), "The first dab that writes height gains the layer its field")
    assert_almost_eq(_height(Vector2i(SPOT)), 1.0, 0.001, "and the stroke stands at the brush's height")
    assert_true(_doc.undo(), "Undo takes the stroke back")
    assert_null(layer.get_field(Vector2i.ZERO, SaFieldSpec.HEIGHT), "and the chunk's height with it")
    assert_true(_doc.undo(), "Undo takes the gaining step back")
    assert_false(layer.carries_height(), "and the layer carries no height again")


## A dab across a chunk's edge writes both chunks, allocates height in those
## two alone, and reads the same on either side of the seam.
func test_a_dab_at_a_chunks_edge_writes_both_chunks_with_no_seam() -> void:
    var edge := float(SaLayer.CHUNK_SIZE)
    _stroke(Vector2(edge, 100.0), 1, 2.0, 1.0, 8.0)
    var holding := 0
    for grid: Vector2i in _doc.active_layer.chunks:
        if (_doc.active_layer.chunks[grid] as SaChunk).has_field(SaFieldSpec.HEIGHT):
            holding += 1
    assert_eq(holding, 2, "Height is allocated in the two chunks the dab reached and no other")
    var seam := PackedStringArray()
    for k in range(1, 8):
        var left := _height(Vector2i(SaLayer.CHUNK_SIZE - k, 100))
        var right := _height(Vector2i(SaLayer.CHUNK_SIZE + k, 100))
        if left != right:
            seam.append("%d: %.4f against %.4f" % [k, left, right])
    assert_true(seam.is_empty(), "The height mirrors across the seam: %s" % ", ".join(seam))
    assert_eq(_height(Vector2i(SaLayer.CHUNK_SIZE - 1, 100)), 2.0, "The last texel of the left chunk stands full")
    assert_eq(_height(Vector2i(SaLayer.CHUNK_SIZE, 100)), 2.0, "and so does the first of the right one")


## The stamp's build-up eraser lowers the height by its own strength, the
## deposition rule with a target of nought, in the same dab that takes the
## alpha.
func _erase_with_the_dab(strength: float) -> Array:
    var rd := GlobalShaderCompiler.get_rd()
    var side := 64
    var canvas := SaTexture.new(Vector2i(side, side))
    canvas.clear(Color(1.0, 1.0, 1.0, 1.0))
    var height := SaTexture.new(Vector2i(side, side), SaFieldSpec.HEIGHT_FORMAT)
    height.clear(Color(2.0, 0.0, 0.0, 0.0))
    var tip: Resource = SaBrushTipScript.new()
    tip.diameter = 24.0
    tip.ratio = 1.0
    tip.horizontal_fade = 1.0
    tip.vertical_fade = 1.0
    var compute := SaCompute.new("dab")
    compute.set_texture(0, canvas.rid)
    var selection := SaTexture.new(Vector2i(1, 1), SaSelection.FORMAT)
    selection.clear(Color(1.0, 1.0, 1.0, 1.0))
    compute.set_texture(SaSelection.BINDING, selection.rid)
    var mask := SaStampBindings.bind(compute, tip, null)
    compute.set_texture(StateBrushScript.HEIGHT_BINDING, height.rid)
    compute.set_push_constant_float_array(
        SaDabPacking.pack_dab_params(
            Vector2(32.0, 32.0),
            Vector2.ZERO,
            Color(1, 1, 1, strength),
            tip.half_extent(),
            0.0,
            tip.effective_fade(),
            1.0,
            SaDabGeometry.PaintMode.ERASE,
            false,
            tip
        )
    )
    compute.dispatch_kernel("dab", 8, 8, 1)
    assert_not_null(mask, "The tip's binder answered a mask")
    var heights := rd.texture_get_data(height.rid, 0)
    var colour := rd.texture_get_data(canvas.rid, 0)
    var centre := 32 * side + 32
    return [heights.decode_half(centre * 2), colour.decode_float(centre * 16 + 12), heights.decode_half(2 * 2)]


func test_the_build_up_eraser_halves_the_height_at_half_strength() -> void:
    var read := _erase_with_the_dab(0.5)
    assert_almost_eq(read[0], 1.0, 0.002, "Erasing a height of 2 at half strength leaves 1")
    assert_almost_eq(read[1], 0.5, 0.002, "and the alpha falls by the same share")
    assert_eq(read[2], 2.0, "A texel the dab missed keeps its height")


func test_the_build_up_eraser_lowers_by_its_own_strength() -> void:
    var read := _erase_with_the_dab(0.25)
    assert_almost_eq(read[0], 1.5, 0.002, "A quarter strength takes a quarter of the height")


## The wash eraser gathers coverage in the stroke buffer and lowers the height
## by its opacity. The buffer here is filled with no region reported, so the
## commit's last pass is what lowers it, and undo puts the height back. The
## lowering as the dabs land is the suite beside this one.
func test_the_wash_eraser_halves_the_height_at_its_commit() -> void:
    var grid := Vector2i.ZERO
    _ground(grid, 2.0)
    _doc.begin_stroke(0.5, SaLayer.BLEND_MODE.ERASE, SaLayer.BLEND_MODE.ERASE)
    var buffer := _doc.stroke_layer.get_or_create_chunk(grid).albedo()
    buffer.clear(Color(1.0, 1.0, 1.0, 1.0))
    _doc.stroke_transaction.note_region(grid, Rect2i(96, 96, 16, 16))
    _doc.commit_stroke()
    assert_almost_eq(_height(Vector2i(100, 100)), 1.0, 0.002, "The wash eraser at half opacity halves the height it covers")
    assert_eq(_height(Vector2i(10, 10)), 2.0, "and leaves the height outside the region it painted")
    assert_true(_doc.undo(), "Undo takes the erase back")
    assert_eq(_height(Vector2i(100, 100)), 2.0, "and the height stands as it did")


## A wash erase over a layer without height gives it none.
func test_the_wash_eraser_gives_a_flat_layer_no_height() -> void:
    var grid := Vector2i.ZERO
    _doc.active_layer.get_or_create_chunk(grid).albedo().clear(Color(1.0, 1.0, 1.0, 1.0))
    _doc.begin_stroke(0.5, SaLayer.BLEND_MODE.ERASE, SaLayer.BLEND_MODE.ERASE)
    _doc.stroke_layer.get_or_create_chunk(grid).albedo().clear(Color(1.0, 1.0, 1.0, 1.0))
    _doc.stroke_transaction.note_region(grid, Rect2i(96, 96, 16, 16))
    _doc.commit_stroke()
    assert_false(_doc.active_layer.carries_height(), "The layer carries no height after the erase")
