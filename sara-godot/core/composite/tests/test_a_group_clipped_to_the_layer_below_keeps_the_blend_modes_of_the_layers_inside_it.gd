## A group clipped to the layer below keeps the blend modes of
## the layers inside it.
##
## A painter, 2026-10-27: "When I clip a group to a layer below, the blending
## modes that the layers had stop being executed." Grouping a Multiply and a
## Hard Light layer and clipping the group to a paint layer is how a painter
## lays two blend effects on one base.
##
## The stack is rebuilt here: an opaque backdrop, a base painted over the left
## half of the first chunk, and above it a group of two layers whose modes show
## plainly. Inside the base's paint the clipped group reads what the unclipped
## group reads, for an isolated group and for a pass-through one, and outside
## it the backdrop alone.
extends "res://tests/test_framework.gd"

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")

const REQUIRES_GPU := true

const SIZE := Vector2i(256, 256)
const BACKDROP := Color(0.2, 0.3, 0.25, 1.0)
const BASE := Color(0.7, 0.5, 0.3, 1.0)
## The base covers the columns left of this one.
const BASE_TO := 128
const ROW := 64
const INSIDE: Array[int] = [8, 40, 100]
const OUTSIDE: Array[int] = [150, 200, 250]
## A few composites at the document's depth.
const TOLERANCE := 2.0e-3
## Which layer is active while the stack is read, since the walk draws the
## group from a different place for each: below it, as its base, and from
## inside it.
const ACTIVE: Array[String] = ["Layer 1", "Base", "Group", "Lower", "Upper"]
## The members, the lower first, as a painter's and then a second pair.
const PAIRS: Array[Array] = [
    [&"multiply", Color(0.6, 0.8, 0.9, 1.0), &"hard_light", Color(0.75, 0.4, 0.55, 1.0)],
    [&"screen", Color(0.3, 0.2, 0.45, 1.0), &"divide", Color(0.8, 0.9, 0.6, 1.0)],
]


func before_each() -> void:
    SaProblems.pending_refusals = PackedStringArray()


## The stack with *pair*'s members in a group above the base, isolated or
## pass-through, at *opacity*, clipped to the base or not, with the layer
## named *active* active.
func _stack(pair: Array, isolated: bool, clipped: bool, active: String = "Layer 1", opacity: float = 1.0) -> SaEasel:
    var easel := Bench.easel(SIZE)
    var doc := easel.document
    var ops := SaLayerOps.new(doc)
    (doc.get_node("Background") as SaLayer).visible = false
    var under := doc.get_node("Layer 1") as SaLayer
    doc.fill_layer(BACKDROP, under)
    doc.set_active_layer(under)
    var base := ops.add()
    base.name = "Base"
    _paint_left(doc, base)
    var lower := ops.add()
    lower.name = "Lower"
    doc.fill_layer(pair[1], lower)
    ops.set_blend_mode(lower, pair[0])
    var upper := ops.add()
    upper.name = "Upper"
    doc.fill_layer(pair[3], upper)
    ops.set_blend_mode(upper, pair[2])
    var group := ops.group_layers([lower, upper])
    group.name = "Group"
    ops.set_opacity(group, opacity)
    ops.set_isolated(group, isolated)
    if clipped:
        SaLayerStack.set_clip_to_below(doc, group, true)
        assert_true(SaLayerStack.clip_base(doc, group) == base, "The group is clipped to the base")
    doc.set_active_layer(_found(doc, active))
    Bench.composite(easel)
    return easel


## The layer named *wanted* anywhere in the tree.
static func _found(doc: SaDocument, wanted: String) -> SaLayer:
    return doc.find_child(wanted, true, false) as SaLayer


## The base's colour over the columns left of `BASE_TO`.
static func _paint_left(doc: SaDocument, base: SaLayer) -> void:
    var image := Image.create_empty(SaLayer.CHUNK_SIZE, SaLayer.CHUNK_SIZE, false, Image.FORMAT_RGBAF)
    for x in image.get_width():
        for y in image.get_height():
            image.set_pixel(x, y, BASE if x < BASE_TO else Color(0, 0, 0, 0))
    SaImageImport.upload(doc, base, image)


static func _read(easel: SaEasel, columns: Array[int]) -> Array[Color]:
    var read: Array[Color] = []
    for x in columns:
        read.append(Bench.texel(easel.output, Vector2i(x, ROW)))
    return read


func _assert_colour(actual: Color, expected: Color, what: String) -> void:
    assert_almost_eq(actual.r, expected.r, TOLERANCE, "%s, red, %s against %s" % [what, actual, expected])
    assert_almost_eq(actual.g, expected.g, TOLERANCE, "%s, green" % what)
    assert_almost_eq(actual.b, expected.b, TOLERANCE, "%s, blue" % what)


func test_a_clipped_group_reads_inside_the_base_what_the_unclipped_group_reads() -> void:
    for pair in PAIRS:
        for isolated: bool in [true, false]:
            for active in ACTIVE:
                for opacity: float in [1.0, 0.6]:
                    var how := "isolated" if isolated else "pass-through"
                    var what := "%s and %s, %s at %.1f, %s active" % [pair[0], pair[2], how, opacity, active]
                    var loose := _stack(pair, isolated, false, active, opacity)
                    var expected := _read(loose, INSIDE)
                    loose.free()
                    var held := _stack(pair, isolated, true, active, opacity)
                    var read := _read(held, INSIDE)
                    for i in INSIDE.size():
                        _assert_colour(read[i], expected[i], "Clipped at x %d (%s)" % [INSIDE[i], what])
                    var outside := _read(held, OUTSIDE)
                    for i in OUTSIDE.size():
                        var past := "Past the base at x %d, the backdrop alone (%s)" % [OUTSIDE[i], what]
                        _assert_colour(outside[i], BACKDROP, past)
                    held.free()


## The members' modes are seen at all: a painter's pair over the base reads
## the product and the hard light, not the upper colour laid flat.
func test_a_painter_s_pair_multiplies_and_hard_lights_the_base() -> void:
    var pair: Array = PAIRS[0]
    var lower: Color = pair[1]
    var upper: Color = pair[3]
    var product := Color(BASE.r * lower.r, BASE.g * lower.g, BASE.b * lower.b, 1.0)
    for isolated: bool in [false]:
        var easel := _stack(pair, isolated, true)
        var read := _read(easel, INSIDE)[0]
        var lit := [_hard_light(product.r, upper.r), _hard_light(product.g, upper.g), _hard_light(product.b, upper.b)]
        var expected := Color(lit[0], lit[1], lit[2], 1.0)
        _assert_colour(read, expected, "The base multiplied and hard lit, pass-through")
        easel.free()


static func _hard_light(backdrop: float, source: float) -> float:
    if source <= 0.5:
        return backdrop * 2.0 * source
    var screen := 2.0 * source - 1.0
    return backdrop + screen - backdrop * screen


## Merge Down of the clipped group into its base leaves the canvas as it was,
## inside the base and past it, read first with a member active and the group
## at 0.6.
func test_merging_the_clipped_group_down_keeps_the_pixels() -> void:
    for pair in PAIRS:
        for isolated: bool in [true, false]:
            var what := "%s and %s, %s" % [pair[0], pair[2], "isolated" if isolated else "pass-through"]
            var easel := _stack(pair, isolated, true, "Upper", 0.6)
            var columns: Array[int] = []
            columns.append_array(INSIDE)
            columns.append_array(OUTSIDE)
            var before := _read(easel, columns)
            var doc := easel.document
            var group := _found(doc, "Group")
            doc.set_active_layer(group)
            assert_true(SaLayerOps.new(doc).merge_down(group), "The clipped group merges down (%s)" % what)
            assert_null(_found(doc, "Group"), "and is gone (%s)" % what)
            Bench.composite(easel)
            var after := _read(easel, columns)
            for i in columns.size():
                _assert_colour(after[i], before[i], "Merged at x %d (%s)" % [columns[i], what])
            easel.free()
