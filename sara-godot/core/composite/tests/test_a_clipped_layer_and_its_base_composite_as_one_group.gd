## A clipping base and the layers clipped to it composite as
## one group, the way Photoshop's clipping masks do.
##
## Sara laid the base over what lay under it first, then each clipped layer
## over the result with its alpha times the base's, so wherever the base was
## partly there its own colour showed through with a weight of a(1 - a). Day 5
## of a painting pass probed it with a slab of #e0e0e0, #404040 clipped
## over all of it and its edge cut soft, on #202020: the canvas read 64 inside
## and rose to 97 in the ramp's middle, where a group falls from 64 to 32.
## `probe-4i.png` in Day 5's proof folder shows the pale rim it drew.
##
## Each case is read with the pair in every place the walk draws it from: above
## the active layer, folded below it, around it as the base and as the clipped
## layer, folded into an isolated group's cache, and around the active layer
## inside one. The expected values come from the base's alpha as stored, which
## the ramp wrote, through the group rule.
extends "res://tests/test_framework.gd"

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")

const REQUIRES_GPU := true

const SIZE := Vector2i(512, 256)
## Day 5's colours as an sRGB document stores them.
const BACKDROP := Color(32.0 / 255.0, 32.0 / 255.0, 32.0 / 255.0, 1.0)
const SLAB := Color(224.0 / 255.0, 224.0 / 255.0, 224.0 / 255.0, 1.0)
const CLIPPED := Color(64.0 / 255.0, 64.0 / 255.0, 64.0 / 255.0, 1.0)
## The slab is whole left of the ramp and gone right of it, its alpha falling
## in a straight line across the ramp on every row of the first chunk.
const RAMP_FROM := 64
const RAMP_TO := 192
const MIDDLE := 128
const ROW := 100
## Inside, across the ramp, and past it.
const READ_AT: Array[int] = [40, 72, 96, 112, 128, 144, 160, 176, 188, 200]
## A few composites at the document's depth.
const TOLERANCE := 2.0e-3
const PLACES: Array[String] = ["above", "below", "base", "clipped", "grouped", "clipped in a group"]
## The second case: a base in Normal at half opacity and a layer clipped to it
## in Multiply.
const BASE_COLOUR := Color(0.8, 0.6, 0.4, 1.0)
const MULTIPLIED := Color(0.5, 0.5, 1.0, 1.0)


func before_each() -> void:
    SaProblems.pending_refusals = PackedStringArray()


## Day 5's probe in *place*: the backdrop on Layer 1, the slab with its soft
## edge, and the darker grey clipped over all of it.
func _probe(place: String, base_colour: Color = SLAB, over: Color = CLIPPED) -> SaEasel:
    var easel := Bench.easel(SIZE)
    var doc := easel.document
    var ops := SaLayerOps.new(doc)
    (doc.get_node("Background") as SaLayer).visible = false
    var under := doc.get_node("Layer 1") as SaLayer
    doc.fill_layer(BACKDROP, under)
    doc.set_active_layer(under)
    var base := ops.add()
    base.name = "Base"
    _ramp(doc, base, base_colour)
    var clipped := ops.add()
    clipped.name = "Over"
    doc.fill_layer(over, clipped)
    SaLayerStack.set_clip_to_below(doc, clipped, true)
    assert_true(SaLayerStack.clip_base(doc, clipped) == base, "The grey is clipped to the slab (%s)" % place)
    match place:
        "above":
            doc.set_active_layer(under)
        "below":
            var top := ops.add()
            top.name = "Top"
            doc.set_active_layer(top)
        "base":
            doc.set_active_layer(base)
        "clipped":
            doc.set_active_layer(clipped)
        "grouped":
            ops.set_isolated(ops.group_layers([base, clipped]), true)
            doc.set_active_layer(under)
        "clipped in a group":
            ops.set_isolated(ops.group_layers([base, clipped]), true)
            doc.set_active_layer(clipped)
    Bench.composite(easel)
    return easel


## The slab's colour in the first chunk, whole left of the ramp and falling to
## nothing across it.
static func _ramp(doc: SaDocument, base: SaLayer, colour: Color) -> void:
    var image := Image.create_empty(SaLayer.CHUNK_SIZE, SaLayer.CHUNK_SIZE, false, Image.FORMAT_RGBAF)
    for x in image.get_width():
        var alpha := clampf(float(RAMP_TO - x) / float(RAMP_TO - RAMP_FROM), 0.0, 1.0)
        for y in image.get_height():
            image.set_pixel(x, y, Color(colour.r, colour.g, colour.b, alpha))
    SaImageImport.upload(doc, base, image)


## The base's alpha at column *x* of the probe's row, as stored.
static func _alpha_at(easel: SaEasel, x: int) -> float:
    var base := easel.document.get_node_or_null("Base") as SaLayer
    if base == null:
        base = _found(easel.document, "Base")
    return Bench.texel(base.get_field(Vector2i(0, 0)), Vector2i(x, ROW)).a


## The layer named *wanted* anywhere in the tree.
static func _found(doc: SaDocument, wanted: String) -> SaLayer:
    for child in doc.get_children():
        if child is SaLayer and child.name == wanted:
            return child
    return null


## What the group rule gives at a base alpha of *alpha* on the opaque backdrop:
## the clipped colour *shown* under the base's alpha, laid by the base's
## *opacity*, Normal over the backdrop.
static func _group(shown: Color, alpha: float, opacity: float = 1.0) -> Color:
    var cover := alpha * opacity
    return Color(
        shown.r * cover + BACKDROP.r * (1.0 - cover),
        shown.g * cover + BACKDROP.g * (1.0 - cover),
        shown.b * cover + BACKDROP.b * (1.0 - cover),
        1.0
    )


func _assert_colour(actual: Color, expected: Color, what: String) -> void:
    assert_almost_eq(actual.r, expected.r, TOLERANCE, "%s, red, %s against %s" % [what, actual, expected])
    assert_almost_eq(actual.g, expected.g, TOLERANCE, "%s, green" % what)
    assert_almost_eq(actual.b, expected.b, TOLERANCE, "%s, blue" % what)


## The canvas along the probe's row.
static func _row(easel: SaEasel) -> Array[Color]:
    var read: Array[Color] = []
    for x in READ_AT:
        read.append(Bench.texel(easel.output, Vector2i(x, ROW)))
    return read


func test_the_soft_edge_falls_from_the_clipped_colour_to_the_backdrop_with_no_rim() -> void:
    for place in PLACES:
        var easel := _probe(place)
        var row := _row(easel)
        var highest := maxf(CLIPPED.r, BACKDROP.r)
        for i in READ_AT.size():
            var x := READ_AT[i]
            var alpha := _alpha_at(easel, x)
            _assert_colour(row[i], _group(CLIPPED, alpha), "At x %d, the base at alpha %.3f, a group (%s)" % [x, alpha, place])
            assert_true(row[i].r <= highest + TOLERANCE, "and no rise above both at x %d, %s (%s)" % [x, row[i], place])
            if i > 0:
                assert_true(row[i].r <= row[i - 1].r + TOLERANCE, "and falling at x %d, %s (%s)" % [x, row[i], place])
        _assert_colour(row[0], CLIPPED, "Inside, the clipped colour whole (%s)" % place)
        _assert_colour(row[READ_AT.size() - 1], BACKDROP, "and past the edge the backdrop (%s)" % place)
        var middle := Bench.texel(easel.output, Vector2i(MIDDLE, ROW))
        assert_almost_eq(middle.r * 255.0, 48.0, 0.5, "In the ramp's middle, 48 where Day 5 read 97 (%s)" % place)
        easel.free()


## A clipped layer in Multiply blends with the base's colour alone, and the
## group is laid at the base's half opacity.
func test_a_multiply_clip_over_a_half_opaque_base_is_the_group_at_half() -> void:
    var product := Color(BASE_COLOUR.r * MULTIPLIED.r, BASE_COLOUR.g * MULTIPLIED.g, BASE_COLOUR.b * MULTIPLIED.b, 1.0)
    for place in PLACES:
        var easel := _probe(place, BASE_COLOUR, MULTIPLIED)
        var doc := easel.document
        var ops := SaLayerOps.new(doc)
        ops.set_blend_mode(_found(doc, "Over"), SaLayer.BLEND_MODE.MULTIPLY)
        ops.set_opacity(_found(doc, "Base"), 0.5)
        Bench.composite(easel)
        var row := _row(easel)
        for i in READ_AT.size():
            var alpha := _alpha_at(easel, READ_AT[i])
            var expected := _group(product, alpha, 0.5)
            _assert_colour(row[i], expected, "At x %d, the product laid at half the base's alpha (%s)" % [READ_AT[i], place])
        # The old rule laid the base at half first and multiplied the clipped
        # layer into that, which reads the backdrop into the product.
        assert_false(
            is_equal_approx(row[0].r, 0.5 * (BASE_COLOUR.r + BACKDROP.r) * MULTIPLIED.r),
            "and not the base at half with the product over it (%s)" % place
        )
        easel.free()


## An export, the merged snapshot a stroke reads, Merge Down of the clipped
## layer and Flatten each hold what the canvas shows, the soft edge included.
func test_an_export_the_merged_snapshot_a_merge_down_and_a_flatten_match_the_canvas() -> void:
    for multiply: bool in [false, true]:
        var what := "multiply at half" if multiply else "Day 5's probe"
        var shown := _shown_after(multiply, "")
        var exported := _shown_after(multiply, "export")
        var snapshot := _shown_after(multiply, "snapshot")
        var merged := _shown_after(multiply, "merge")
        var flattened := _shown_after(multiply, "flatten")
        for i in READ_AT.size():
            _assert_colour(exported[i], shown[i], "The export at x %d (%s)" % [READ_AT[i], what])
            _assert_colour(snapshot[i], shown[i], "The merged snapshot at x %d (%s)" % [READ_AT[i], what])
            _assert_colour(merged[i], shown[i], "Merge Down at x %d (%s)" % [READ_AT[i], what])
            _assert_colour(flattened[i], shown[i], "Flatten at x %d (%s)" % [READ_AT[i], what])


## The probe's row after *act*: as the canvas shows it, read off an EXR export
## of the stored numbers or off the merged snapshot a stroke takes over the
## row, or the canvas again after Merge Down of the clipped layer or after
## Flatten.
func _shown_after(multiply: bool, act: String) -> Array[Color]:
    var easel := _probe("above", BASE_COLOUR if multiply else SLAB, MULTIPLIED if multiply else CLIPPED)
    var doc := easel.document
    var ops := SaLayerOps.new(doc)
    var clipped := _found(doc, "Over")
    if multiply:
        ops.set_blend_mode(clipped, SaLayer.BLEND_MODE.MULTIPLY)
        ops.set_opacity(_found(doc, "Base"), 0.5)
        Bench.composite(easel)
    var read: Array[Color] = []
    match act:
        "export":
            var path := SaDataRoot.path("test_d19_clip_group.exr")
            doc.invalidate_chunks(SaLayer.grid_positions(doc.canvas_size))
            easel.flush()
            assert_eq(SaExport.export_exr_texture(easel.output, path), OK, "The export writes")
            var image := Image.load_from_file(ProjectSettings.globalize_path(path))
            for x in READ_AT:
                read.append(image.get_pixel(x, ROW))
            DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
            easel.free()
            return read
        "snapshot":
            var snapshot := easel.snapshot_merged(Rect2i(0, ROW, SIZE.x, 1))
            var copied := SaExport.get_texture_image_float(snapshot.texture)
            for x in READ_AT:
                read.append(copied.get_pixelv(snapshot.local_of(Vector2i(x, ROW))))
            easel.free()
            return read
        "merge":
            doc.set_active_layer(clipped)
            assert_true(ops.merge_down(clipped), "Merge Down merges the clipped layer into its base")
            assert_null(_found(doc, "Over"), "and takes it out")
        "flatten":
            assert_true(ops.flatten(), "Flatten flattens")
    Bench.composite(easel)
    read = _row(easel)
    easel.free()
    return read
