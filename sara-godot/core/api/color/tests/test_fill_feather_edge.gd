## A feathered fill blends its own edge without a dark ring.
##
## A painter's note: "Selecting a region with laso and feather + filling the
## area via ALT + Backspace created darker parts on the edge of the filled
## region." The screenshot shows a green fill on grey with a darker green ring
## where the feather is.
##
## The ring is a straight-alpha bug and not a colour-space one. Sara stores
## straight alpha, which the compositor's `porter_duff` says by dividing by the
## output alpha, and `fill.gmacs` used to interpolate the fill and the
## destination channel by channel including alpha. Over a transparent
## destination, whose RGB is black and means nothing at zero alpha, that leaves
## the fill colour scaled by coverage at an alpha that is also coverage, so the
## edge composites as coverage squared and dips below both ends.
##
## The profile is asserted here rather than photographed, because a ring three
## hundredths deep is a real complaint and an invisible screenshot.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

## The proof is the pixels the kernel wrote, so it wants a RenderingDevice.
const REQUIRES_GPU := true

## One chunk wide is enough for the whole profile, and the second chunk is what
## the selection's edge is placed inside.
const CANVAS := Vector2i(512, 256)

## The selection's right edge, in canvas pixels, and the feather each way from
## it. Both inside the first chunk, so the profile is one texture read.
const EDGE: int = 228
const FEATHER: int = 20

## What the layer under the fill is, and what the fill is. Green on grey is the
## note's own pair.
const BACKDROP := Color(0.5, 0.5, 0.5, 1.0)
const FILL := Color(0.0, 0.6, 0.0, 1.0)

## Float textures written by a compute pass, read back as float, so this is
## rounding rather than tolerance.
const EPSILON := 0.002


## A document that size in that space, with the active layer's grid allocated.
func _surface(space: SaColorSpace) -> SaSurface:
    var surface := Fixtures.make_surface(CANVAS)
    surface.easel.document.color_space = space
    surface.easel.document.active_layer.allocate_grid(CANVAS)
    return surface


## The selection the note describes: a rectangle, feathered, so its right edge
## is a ramp rather than a step.
func _feathered(doc: SaDocument) -> void:
    doc.selection.select_rect(Rect2i(0, 0, EDGE, CANVAS.y))
    SaSelectionFilters.feather(doc.selection, FEATHER, CANVAS)


## One row of the active layer's first chunk, across the feathered edge.
func _row(doc: SaDocument) -> Array[Color]:
    var chunk: SaTexture = doc.active_layer.get_or_create_field(Vector2i(0, 0))
    var data: PackedByteArray = GlobalShaderCompiler.get_rd().texture_get_data(chunk.rid, 0)
    var out: Array[Color] = []
    for x in range(EDGE - FEATHER - 4, EDGE + FEATHER + 4):
        var at := (128 * 256 + x) * 16
        out.append(Color(data.decode_float(at), data.decode_float(at + 4), data.decode_float(at + 8), data.decode_float(at + 12)))
    return out


## What one filled texel looks like once the compositor has put it over the
## backdrop: straight-alpha source over an opaque destination, which is
## `porter_duff` with `dst.a` of one.
func _over_backdrop(texel: Color) -> float:
    return texel.g * texel.a + BACKDROP.g * (1.0 - texel.a)


func test_a_feathered_fill_on_an_empty_layer_keeps_its_colour() -> void:
    var surface := _surface(SaColorSpace.srgb())
    var doc := surface.easel.document
    _feathered(doc)
    doc.active_layer.fill(FILL)

    for texel in _row(doc):
        if texel.a > EPSILON:
            assert_almost_eq(texel.g, FILL.g, EPSILON, "every covered texel is the fill colour")
    Fixtures.teardown(surface)


## The note's own symptom, as a number. Composited over the grey the note had
## under it, no texel of the edge may read below the darker of the two ends.
func test_no_texel_of_the_edge_is_darker_than_both_ends() -> void:
    var surface := _surface(SaColorSpace.srgb())
    var doc := surface.easel.document
    _feathered(doc)
    doc.active_layer.fill(FILL)

    var floor_value := minf(BACKDROP.g, FILL.g)
    var lowest := 1.0
    for texel in _row(doc):
        lowest = minf(lowest, _over_backdrop(texel))
    assert_true(
        lowest >= floor_value - EPSILON,
        "the darkest texel of the edge is %.4f, and neither end is below %.4f" % [lowest, floor_value]
    )
    Fixtures.teardown(surface)


## The edge is a ramp and not a dip, which the floor above allows a flat line to
## pass. Alpha carries the feather and the colour does not move.
func test_the_edge_is_monotone_from_the_fill_to_the_backdrop() -> void:
    var surface := _surface(SaColorSpace.srgb())
    var doc := surface.easel.document
    _feathered(doc)
    doc.active_layer.fill(FILL)

    var row := _row(doc)
    for i in range(1, row.size()):
        assert_true(
            _over_backdrop(row[i]) <= _over_backdrop(row[i - 1]) + EPSILON,
            "texel %d does not rise again on the way out of the selection" % i
        )
    assert_almost_eq(_over_backdrop(row[0]), FILL.g, EPSILON, "the inside end is the fill")
    assert_almost_eq(_over_backdrop(row[row.size() - 1]), BACKDROP.g, EPSILON, "and the outside end is the backdrop")
    Fixtures.teardown(surface)


## An Oklab document stores L, a and b rather than red, green and blue, so a
## channel-by-channel mix toward a transparent texel walks toward L of zero,
## which is black. The fix is the same one because the bug never was the space:
## the note asked for both documents and both are here.
func test_an_oklab_document_has_no_ring_either() -> void:
    var surface := _surface(SaColorSpace.oklab())
    var doc := surface.easel.document
    var stored := doc.color_space.from_display(FILL)
    _feathered(doc)
    doc.active_layer.fill(stored)

    for texel in _row(doc):
        if texel.a > EPSILON:
            assert_almost_eq(texel.r, stored.r, EPSILON, "the lightness of a covered texel is the fill's")
            assert_almost_eq(texel.g, stored.g, EPSILON, "and so is its a")
            assert_almost_eq(texel.b, stored.b, EPSILON, "and its b")
    Fixtures.teardown(surface)


## Filling over paint that is already opaque was never the ring, and it must
## stay what it was: a plain interpolation of two opaque colours, which on an
## sRGB document is the encoded mix Sara has always done.
func test_an_opaque_destination_still_interpolates_the_colours() -> void:
    var surface := _surface(SaColorSpace.srgb())
    var doc := surface.easel.document
    doc.active_layer.fill(BACKDROP)
    _feathered(doc)
    doc.active_layer.fill(FILL)

    var row := _row(doc)
    for texel in row:
        assert_almost_eq(texel.a, 1.0, EPSILON, "the layer stays opaque")
        assert_true(texel.g >= BACKDROP.g - EPSILON and texel.g <= FILL.g + EPSILON, "and every texel is between the two")
    assert_almost_eq(row[0].g, FILL.g, EPSILON, "the inside end is the fill")
    assert_almost_eq(row[row.size() - 1].g, BACKDROP.g, EPSILON, "and the outside end is the backdrop")
    Fixtures.teardown(surface)


## Under a selection a transparent fill is a clear, which `fill_layer` says in
## as many words. A Porter-Duff over would have made it a no-op, so
## it is asserted rather than assumed.
func test_a_transparent_fill_under_a_selection_still_clears() -> void:
    var surface := _surface(SaColorSpace.srgb())
    var doc := surface.easel.document
    doc.active_layer.fill(BACKDROP)
    doc.selection.select_rect(Rect2i(0, 0, EDGE, CANVAS.y))
    doc.active_layer.fill(Color(0.0, 0.0, 0.0, 0.0))

    var row := _row(doc)
    assert_almost_eq(row[0].a, 0.0, EPSILON, "inside the selection the paint is gone")
    assert_almost_eq(row[row.size() - 1].a, 1.0, EPSILON, "and outside it is untouched")
    assert_almost_eq(row[row.size() - 1].g, BACKDROP.g, EPSILON, "with the colour it had")
    Fixtures.teardown(surface)


## Half a clear is half the alpha and the colour it had, not a colour walking
## toward black. The same texel, read through the feather.
func test_a_feathered_clear_takes_alpha_and_leaves_colour() -> void:
    var surface := _surface(SaColorSpace.srgb())
    var doc := surface.easel.document
    doc.active_layer.fill(BACKDROP)
    _feathered(doc)
    doc.active_layer.fill(Color(0.0, 0.0, 0.0, 0.0))

    for texel in _row(doc):
        if texel.a > EPSILON:
            assert_almost_eq(texel.g, BACKDROP.g, EPSILON, "a half-erased texel keeps its colour")
    Fixtures.teardown(surface)


## Alpha lock writes the colour and leaves alpha alone, which the premultiplied
## interpolation has to reproduce exactly: source alpha equals destination
## alpha, so the weights cancel and the result is the plain colour mix.
func test_alpha_lock_still_keeps_the_destination_alpha() -> void:
    var surface := _surface(SaColorSpace.srgb())
    var doc := surface.easel.document
    doc.active_layer.fill(Color(BACKDROP.r, BACKDROP.g, BACKDROP.b, 0.5))
    _feathered(doc)
    doc.active_layer.alpha_locked = true
    doc.active_layer.fill(FILL)
    doc.active_layer.alpha_locked = false

    var row := _row(doc)
    for texel in row:
        assert_almost_eq(texel.a, 0.5, EPSILON, "alpha is the destination's throughout")
    assert_almost_eq(row[0].g, FILL.g, EPSILON, "and the colour inside the selection is the fill's")
    assert_almost_eq(row[row.size() - 1].g, BACKDROP.g, EPSILON, "and outside it is what it was")
    Fixtures.teardown(surface)
