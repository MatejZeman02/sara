## An adjustment layer runs its point filters over the backdrop
## the walk has built below it, mixes the result in its own blend mode by its
## opacity, mask and clip, and keeps the backdrop's alpha.
##
## The painting is two chunks across, its grey background hidden so the
## canvas is transparent under the paint. An opaque layer covers the left chunk,
## and a stroke at half alpha covers both above it, so the right chunk's
## backdrop is half covered and the alpha kept there is read. The reference for
## the headline is the same painting inside an isolated group carrying the same
## brightness and contrast record, the road a filter took before this row.
extends "res://tests/test_framework.gd"

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")
const Fixtures = preload("res://tests/fixtures.gd")

const REQUIRES_GPU := true

const SIZE := Vector2i(512, 256)
const LEFT := Vector2i(0, 0)
const RIGHT := Vector2i(1, 0)
const UNDER := Color(0.125, 0.625, 0.25, 1.0)
const HALF := Color(0.75, 0.25, 0.125, 0.5)
const OUTSIDE := Color(0.5, 0.375, 0.875, 1.0)
const DAB := Color(0.25, 0.5, 0.75, 1.0)
const RECORD := {"brightness": 30.0, "contrast": 25.0}
const TOLERANCE := 1.0e-5
## The one tolerance above the headline's: a Multiply mixes in the blend space
## and comes back, which is two conversions a Normal mix never makes.
const MIXED := 1.0e-4

var _types: SaLayerTypeRegistry


func before_each() -> void:
    _types = Fixtures.make_registries().layer_types
    SaProblems.pending_refusals = PackedStringArray()


## The painting of the header. With *grouped* the opaque layer and the stroke
## sit in an isolated group carrying the record, and with *outside* a third
## opaque layer lies below everything, outside any group. The stroke is active.
func _painting(grouped: bool, outside: bool = false) -> SaEasel:
    var easel := Bench.easel(SIZE)
    _with_filters(easel)
    var doc := easel.document
    var ops := SaLayerOps.new(doc)
    (doc.get_node("Background") as SaLayer).visible = false
    var first := doc.get_node("Layer 1") as SaLayer
    doc.set_active_layer(first)
    var under := first
    if outside:
        first.get_or_create_chunk(LEFT).clear(OUTSIDE)
        first.get_or_create_chunk(RIGHT).clear(OUTSIDE)
        under = ops.add()
    under.get_or_create_chunk(LEFT).clear(UNDER)
    if grouped:
        var group := ops.group_active()
        ops.set_isolated(group, true)
        _attach(doc, group)
        doc.set_active_layer(under)
    var stroke := ops.add()
    stroke.name = "Stroke"
    for grid_pos: Vector2i in [LEFT, RIGHT]:
        stroke.get_or_create_chunk(grid_pos).clear(HALF)
    return easel


## An adjustment layer above the active one, carrying the record, left active.
func _adjust(easel: SaEasel) -> SaLayer:
    var layer := SaLayerOps.new(easel.document).add(SaBackdropLayer.TYPE_ID, _types)
    layer.name = "Adjust"
    _attach(easel.document, layer)
    return layer


func _attach(doc: SaDocument, node: SaLayer) -> void:
    var key := SaFilterRegistry.key_for(&"sara-base-modules", SaBrightnessContrastFilter.new())
    assert_not_null(SaFilterOps.new(doc).attach(node, key, RECORD), "The brightness and contrast attaches to %s" % node.name)


func _show(easel: SaEasel, active: SaLayer = null) -> void:
    if active != null:
        easel.document.set_active_layer(active)
    easel.document.invalidate_chunks([LEFT, RIGHT])
    Bench.composite(easel)


static func _bytes(texture: SaTexture) -> PackedByteArray:
    return GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)


static func _texel(bytes: PackedByteArray, texture: SaTexture, at: Vector2i) -> Color:
    return SaFieldSpec.decode_texel(bytes, texture.format, at.y * texture.size.x + at.x)


static func _apart(a: Color, b: Color) -> float:
    return maxf(maxf(absf(a.r - b.r), absf(a.g - b.g)), maxf(absf(a.b - b.b), absf(a.a - b.a)))


## The texels the checks read: one inside each chunk.
static func _probes() -> Array[Vector2i]:
    return [Vector2i(100, 100), Vector2i(400, 100)]


## Every probe of *found* against the colour *wanted* makes of the texel of
## *expected* there, within *tolerance*.
func _each(found: SaEasel, expected: SaEasel, wanted: Callable, tolerance: float, what: String) -> void:
    var got := _bytes(found.output)
    var from := _bytes(expected.output)
    for at: Vector2i in _probes():
        var have := _texel(got, found.output, at)
        var want: Color = wanted.call(_texel(from, expected.output, at), at)
        var off := _apart(have, want)
        assert_true(off <= tolerance, "%s at %s: %s against %s, apart by %s" % [what, at, have, want, off])


static func _same(texel: Color, _at: Vector2i) -> Color:
    return texel


## The whole output of *found* is the one of *expected* within *tolerance*.
func _alike(found: SaEasel, expected: SaEasel, tolerance: float, what: String) -> void:
    var got := _bytes(found.output)
    var from := _bytes(expected.output)
    var worst := 0.0
    var worst_at := Vector2i.ZERO
    for y in range(0, SIZE.y, 3):
        for x in range(0, SIZE.x, 3):
            var at := Vector2i(x, y)
            var off := _apart(_texel(got, found.output, at), _texel(from, expected.output, at))
            if off > worst:
                worst = off
                worst_at = at
    assert_true(worst <= tolerance, "%s, worst %s at %s" % [what, worst, worst_at])


func test_it_gives_the_output_of_an_isolated_group_carrying_the_record() -> void:
    var easel := _painting(false)
    _adjust(easel)
    _show(easel)
    var group := _painting(true)
    _show(group)
    _alike(easel, group, TOLERANCE, "The adjustment is the isolated group carrying the record")
    var right := _texel(_bytes(easel.output), easel.output, _probes()[1])
    assert_true(absf(right.a - HALF.a) <= TOLERANCE, "and the half-covered stroke keeps its alpha, %s" % right.a)
    easel.free()
    group.free()


func test_opacity_mask_and_multiply_mix_as_a_layer_does() -> void:
    var plain := _painting(false)
    _show(plain)
    var full := _painting(false)
    _adjust(full)
    _show(full)
    var half := _painting(false)
    SaLayerOps.new(half.document).set_opacity(_adjust(half), 0.5)
    _show(half)
    var halfway := func(under: Color, at: Vector2i) -> Color:
        var over := _texel(_bytes(full.output), full.output, at)
        return Color(lerpf(under.r, over.r, 0.5), lerpf(under.g, over.g, 0.5), lerpf(under.b, over.b, 0.5), under.a)
    _each(half, plain, halfway, TOLERANCE, "At opacity 0.5 the output lies halfway")
    var masked := _painting(false)
    var layer := _adjust(masked)
    layer.add_mask(1.0).get_or_create(LEFT).clear(Color(0.0, 0.0, 0.0, 0.0))
    _show(masked)
    var left := _probes()[0]
    var shown := _texel(_bytes(masked.output), masked.output, left)
    var backdrop := _texel(_bytes(plain.output), plain.output, left)
    assert_true(
        _apart(shown, backdrop) <= TOLERANCE, "A mask painted to zero shows the backdrop, %s against %s" % [shown, backdrop]
    )
    var right := _probes()[1]
    var kept := _texel(_bytes(masked.output), masked.output, right)
    var adjusted := _texel(_bytes(full.output), full.output, right)
    assert_true(_apart(kept, adjusted) <= TOLERANCE, "and adjusts where it is not painted")
    var multiplied := _painting(false)
    SaLayerOps.new(multiplied.document).set_blend_mode(_adjust(multiplied), SaLayer.BLEND_MODE.MULTIPLY)
    _show(multiplied)
    var product := _texel(_bytes(multiplied.output), multiplied.output, left)
    var times := Color(
        backdrop.r * adjusted_at(full, left).r,
        backdrop.g * adjusted_at(full, left).g,
        backdrop.b * adjusted_at(full, left).b,
        backdrop.a
    )
    assert_true(
        _apart(product, times) <= MIXED,
        "Multiply multiplies the backdrop by the adjusted colour, %s against %s" % [product, times]
    )
    for made: SaEasel in [plain, full, half, masked, multiplied]:
        made.free()


static func adjusted_at(easel: SaEasel, at: Vector2i) -> Color:
    return _texel(_bytes(easel.output), easel.output, at)


func test_inside_a_group_it_reaches_the_members_below_it_or_everything() -> void:
    for isolated: bool in [true, false]:
        var easel := _painting(false, true)
        var doc := easel.document
        var ops := SaLayerOps.new(doc)
        var stroke := doc.get_node("Stroke") as SaLayer
        var under := doc.get_child(stroke.get_index() - 1) as SaLayer
        doc.set_active_layer(under)
        var group := ops.group_active()
        ops.set_isolated(group, isolated)
        doc.set_active_layer(under)
        doc.move_child(stroke, under.get_index() + 1)
        stroke.group = group
        doc.set_active_layer(stroke)
        var layer := _adjust(easel)
        assert_eq(SaLayerStack.parent_of(layer), group, "The adjustment is a member of the group")
        _show(easel)
        # The isolated group reaches its two members, the painting whose group
        # carries the record. The pass-through one reaches everything, the
        # adjustment at the top of the document, which the first case has
        # shown to be an isolated group of everything carrying the record.
        var wanted := _painting(true, true) if isolated else _painting(false, true)
        if not isolated:
            _adjust(wanted)
        _show(wanted)
        var what := "isolated, the members below it only" if isolated else "pass-through, everything below it"
        _alike(easel, wanted, TOLERANCE, "Inside a group %s" % what)
        easel.free()
        wanted.free()


## The records' kernel dispatches since the counters were reset.
static func _record_dispatches() -> int:
    var count := 0
    var tally := SaCompute.kernel_counters()
    for key: String in tally:
        if key.ends_with("brightness_contrast"):
            count += int(tally[key]["dispatches"])
    return count


## A stroke on *layer* of *easel*: an opaque dab over the left chunk, live.
func _live(easel: SaEasel, layer: SaLayer) -> void:
    _show(easel, layer)
    easel.document.begin_stroke(1.0, SaLayer.BLEND_MODE.NORMAL)
    easel.document.stroke_layer.get_or_create_chunk(LEFT).clear(DAB)
    SaCompute.reset_counters()
    easel.document.invalidate_chunks([LEFT])
    easel.process_pending_composite()


func test_a_stroke_below_shows_adjusted_and_one_above_runs_no_record() -> void:
    var easel := _painting(false)
    var layer := _adjust(easel)
    var stroke := easel.document.get_node("Stroke") as SaLayer
    _show(easel, stroke)
    _live(easel, stroke)
    assert_eq(_record_dispatches(), 1, "Below it, the record runs over the one dirty chunk and no other")
    var painted := _painting(false)
    (painted.document.get_node("Stroke") as SaLayer).get_or_create_chunk(LEFT).clear(DAB)
    _adjust(painted)
    _show(painted)
    _alike(easel, painted, TOLERANCE, "The live stroke shows adjusted")
    easel.document.commit_stroke()
    easel.document.invalidate_chunks([LEFT])
    easel.process_pending_composite()
    _alike(easel, painted, TOLERANCE, "and so does the committed one")
    var afresh := _bytes(easel.output)
    _show(easel)
    assert_eq(_bytes(easel.output), afresh, "which is the composite from scratch")
    easel.document.set_active_layer(layer)
    var top := SaLayerOps.new(easel.document).add()
    _show(easel, top)
    _live(easel, top)
    assert_eq(_record_dispatches(), 0, "Above it, a stroke runs none of its records' kernels")
    easel.document.commit_stroke()
    easel.free()
    painted.free()


func test_picking_it_leaves_the_output_as_it_was() -> void:
    var easel := _painting(false)
    var layer := _adjust(easel)
    _show(easel, easel.document.get_node("Stroke") as SaLayer)
    var before := _bytes(easel.output)
    _show(easel, layer)
    assert_eq(_bytes(easel.output), before, "Picking the adjustment as the active layer leaves the output")
    easel.free()


func test_it_holds_no_paint_refuses_a_wrap_and_reopens_the_same() -> void:
    var easel := _painting(false)
    var layer := _adjust(easel)
    _show(easel)
    assert_true(layer.chunks.is_empty(), "The adjustment holds no chunk")
    assert_true(layer.refuses_paint(), "A brush refuses it")
    assert_true(SaContext.paint_refusal_line(layer, "stroke").contains("adjusts what is below it"), "with its own sentence")
    # A blur is F3's to take, and a record reading the whole layer is still refused.
    var wrap_key := SaFilterRegistry.key_for(&"sara-base-modules", SaWrapOffsetFilter.new())
    SaProblems.announce = false
    var refused := SaFilterOps.new(easel.document).attach(layer, wrap_key, {"offset_x": 16.0})
    SaProblems.announce = true
    assert_null(refused, "A wrap record is refused")
    var said := "\n".join(SaProblems.pending_refusals)
    assert_true(said.contains("'Adjust' is an adjustment layer"), "with its sentence: %s" % said)
    var path := ProjectSettings.globalize_path(SaDataRoot.path("f1_adjustment_layer.sad"))
    assert_eq(SaExport.save_sad(easel.document, path), OK, "It saves")
    var loaded := Bench.easel(SIZE)
    _with_filters(loaded)
    assert_eq(SaExport.load_sad(loaded.document, path, loaded.compositor), OK, "and opens")
    DirAccess.remove_absolute(path)
    var layers: Array[SaLayer] = []
    for child in loaded.document.get_children():
        if child is SaLayer:
            layers.append(child)
    _types.rebind(layers)
    var reopened := loaded.document.get_node("Adjust") as SaLayer
    assert_true(reopened != null and reopened.is_adjustment(), "as an adjustment layer")
    _show(loaded)
    assert_eq(_bytes(loaded.output), _bytes(easel.output), "giving the same output")
    easel.free()
    loaded.free()


## *easel*, its chain answering the blur and the brightness the app registers.
static func _with_filters(easel: SaEasel) -> void:
    easel.compositor.filter_chain.registry.register(SaGaussianBlurFilter.new(), &"sara-base-modules")
    easel.compositor.filter_chain.registry.register(SaBrightnessContrastFilter.new(), &"sara-base-modules")
    easel.compositor.filter_chain.registry.register(SaWrapOffsetFilter.new(), &"sara-base-modules")
