## Erase and alpha lock obey the painting mode.
##
## Painting straight into the active layer for every dab would be build-up
## whatever the painter had chosen: an eraser at half opacity would take two
## bites where its stroke crossed itself, and so would an alpha-locked brush. In
## wash the coverage gathers in the stroke buffer like any other stroke and
## lands once, through a composite that carves or keeps the alpha.
##
## Three claims, and each is measured rather than argued. The route table is the
## decision on its own. The two commits go through `SaDocument.commit_stroke`
## with real chunks and are read back texel by texel, because "the crossing is
## the same as the rest" is a number and a screenshot cannot tell 0.50 from 0.25.
## The scenario beside them, `scenarios/erase-and-alpha-lock-obey-the-mode.json`,
## is the same four cases painted by hand on the running app.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")
const StrokeRouteScript = preload("res://modules/sara-base-modules/stamp-brush/tools/sa_stroke_route.gd")
const DabGeometry = preload("res://core/api/dab/sa_dab_geometry.gd")

## Needs a RenderingDevice for the two commits. The runner skips this suite
## without one.
const REQUIRES_GPU := true

const SIDE: int = 256


## The route for one combination of the three answers.
func _route(erasing: bool, alpha_locked: bool, washing: bool) -> SaStrokeRoute:
    return StrokeRouteScript.decide(erasing, alpha_locked, washing)


## Build-up is what painting straight into the layer already does, so it keeps
## the direct path and pays no composite at the end.
func test_build_up_still_paints_straight_into_the_layer() -> void:
    for alpha_locked: bool in [false, true]:
        var erase := _route(true, alpha_locked, false)
        assert_true(erase.direct, "A build-up erase paints straight in")
        assert_eq(erase.buffer_mode(), &"", "and has no composite to do at the end")
        assert_eq(erase.dab_mode(), DabGeometry.PaintMode.ERASE, "and the kernel is what erases")

    var locked := _route(false, true, false)
    assert_true(locked.direct, "A build-up stroke on an alpha-locked layer paints straight in")
    assert_true(locked.dab_alpha_lock(), "and the kernel is what locks the alpha")

    var plain := _route(false, false, false)
    assert_false(plain.direct, "An ordinary stroke has always gone through the buffer")
    assert_eq(plain.dab_mode(), DabGeometry.PaintMode.OVER, "and build-up is what OVER means there")


## Wash needs the whole stroke's coverage in one place before any of it lands,
## which is the buffer, and the rule it lands under is the buffer's blend mode.
func test_wash_routes_erase_and_alpha_lock_through_the_buffer() -> void:
    var erase := _route(true, false, true)
    assert_false(erase.direct, "A wash erase goes through the buffer")
    assert_eq(erase.buffer_mode(), SaLayer.BLEND_MODE.ERASE, "and carves once at the end")
    assert_eq(erase.dab_mode(), DabGeometry.PaintMode.ALPHA_DARKEN, "The dab only lays coverage")
    assert_false(erase.dab_alpha_lock(), "and locks nothing on the way in")

    var locked := _route(false, true, true)
    assert_false(locked.direct, "A wash stroke on an alpha-locked layer goes through the buffer")
    assert_eq(locked.buffer_mode(), SaLayer.BLEND_MODE.ALPHA_LOCK, "and tints once at the end")
    assert_eq(locked.dab_mode(), DabGeometry.PaintMode.ALPHA_DARKEN, "The dab only lays coverage")
    # The buffer's own alpha starts at nothing, so a dab that read it there would
    # refuse to paint anywhere and the stroke would come out blank.
    assert_false(locked.dab_alpha_lock(), "and the lock waits for the alpha it is about")


## An eraser on an alpha-locked layer has to paint nothing, and the dab kernel is
## where that is already written, so this one pair stays direct in wash too.
func test_an_eraser_on_an_alpha_locked_layer_stays_direct() -> void:
    var route := _route(true, true, true)

    assert_true(route.direct, "The pair that cancels out needs no buffer")
    assert_eq(route.buffer_mode(), &"", "and no composite at the end")
    assert_eq(route.dab_mode(), DabGeometry.PaintMode.ERASE, "The kernel is asked to erase")
    assert_true(route.dab_alpha_lock(), "with the lock that makes it do nothing")


## A wash eraser's stroke reaches the opacity it was set to and stops.
##
## The buffer holds full coverage where the stroke crossed itself and full
## coverage everywhere else, because alpha darken never adds. One composite at
## half opacity is what the layer is left with, so the crossing reads the same as
## the rest. Build-up is the same stroke twice: 0.5 then 0.25.
func test_a_wash_eraser_carves_once_where_a_build_up_one_carves_twice() -> void:
    var washed := _erase_through_the_buffer(0.5)
    assert_almost_eq(washed, 0.5, 0.01, "A wash eraser at half opacity leaves half the alpha")

    var built := _erase_directly_twice(0.5)
    assert_almost_eq(built, 0.25, 0.01, "and a build-up one crossing itself takes a second bite")


## An alpha-locked wash stroke keeps the silhouette it painted into.
##
## The commit's own kernel: the colour composites over, the alpha is the
## destination's, and a texel with nothing under it is left alone.
func test_the_alpha_lock_commit_keeps_the_destination_alpha() -> void:
    var opaque := _commit_alpha_locked(Color(1.0, 1.0, 1.0, 1.0), Color(0.0, 0.0, 0.0, 1.0), 0.5)
    assert_almost_eq(opaque.a, 1.0, 0.01, "The destination's alpha is what stays")
    assert_almost_eq(opaque.r, 0.5, 0.01, "and half a black stroke over white is grey")

    var half := _commit_alpha_locked(Color(1.0, 1.0, 1.0, 0.4), Color(0.0, 0.0, 0.0, 1.0), 1.0)
    assert_almost_eq(half.a, 0.4, 0.01, "A half-covered destination keeps its own cover")

    var empty := _commit_alpha_locked(Color(1.0, 1.0, 1.0, 0.0), Color(0.0, 0.0, 0.0, 1.0), 1.0)
    assert_almost_eq(empty.a, 0.0, 0.01, "and a texel with nothing under it is not painted on")
    assert_almost_eq(empty.r, 1.0, 0.01, "so its colour is untouched as well")


## A stroke that only ever removes alpha allocates no chunk where the layer has
## none. A tile of transparent texels held for the session is hard rule 3 read
## backwards, and a history step for a stroke that changed nothing is a row a
## painter has to undo past.
func test_a_wash_eraser_over_empty_space_leaves_nothing_behind() -> void:
    var doc := _document()

    doc.active_layer.get_or_create_chunk(Vector2i(0, 0)).albedo().clear(Color(1, 1, 1, 1))
    doc.begin_stroke(0.5, SaLayer.BLEND_MODE.ERASE, SaLayer.BLEND_MODE.ERASE)
    doc.stroke_layer.get_or_create_chunk(Vector2i(1, 0)).albedo().clear(Color(1, 1, 1, 1))
    doc.commit_stroke()

    assert_false(doc.active_layer.chunks.has(Vector2i(1, 0)), "No chunk where the eraser found nothing")
    assert_false(doc.undo_redo.has_undo(), "and no history step for a stroke that changed nothing")

    doc.free()


## A document with one 256 by 256 chunk grid and a compositor of its own.
##
## The registry is not decoration here: a compositor without one resolves every
## mode to plain Normal, so an erase commit would leave the alpha where it was
## and this whole suite would pass by measuring nothing.
func _document() -> SaDocument:
    var compositor := SaCompositor.new()
    compositor.set_registry(Fixtures.make_registries().blend_modes)
    var doc := SaDocument.new()
    doc.setup_default_document(Vector2i(SIDE, SIDE), compositor)
    return doc


## The albedo of the active layer's first chunk, as a colour.
func _read(doc: SaDocument) -> Color:
    var texture: SaTexture = doc.active_layer.chunks[Vector2i(0, 0)].albedo()
    var data: PackedByteArray = GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    if data.size() < 16:
        return Color(0, 0, 0, 0)
    return Color(data.decode_float(0), data.decode_float(4), data.decode_float(8), data.decode_float(12))


## An opaque layer, a stroke buffer at full coverage, and one erase composite at
## *opacity*. The alpha it is left with.
func _erase_through_the_buffer(opacity: float) -> float:
    var doc := _document()
    doc.active_layer.get_or_create_chunk(Vector2i(0, 0)).albedo().clear(Color(1, 1, 1, 1))

    doc.begin_stroke(opacity, SaLayer.BLEND_MODE.ERASE, SaLayer.BLEND_MODE.ERASE)
    assert_eq(doc.stroke_layer.blend_mode, SaLayer.BLEND_MODE.ERASE, "The buffer carries the rule the commit applies")
    doc.stroke_layer.get_or_create_chunk(Vector2i(0, 0)).albedo().clear(Color(1, 1, 1, 1))
    doc.commit_stroke()

    var alpha := _read(doc).a
    doc.free()
    return alpha


## The same coverage laid twice straight into the layer, which is what build-up
## does where a stroke crosses itself.
func _erase_directly_twice(opacity: float) -> float:
    var doc := _document()
    var chunk := doc.active_layer.get_or_create_chunk(Vector2i(0, 0))
    chunk.albedo().clear(Color(1, 1, 1, 1))

    var compositor: SaCompositor = doc.injected_compositor()
    var carve := SaTexture.new(Vector2i(SIDE, SIDE))
    carve.clear(Color(1, 1, 1, 1))
    for _pass: int in 2:
        compositor.composite_chunk(chunk.albedo(), carve, SaLayer.BLEND_MODE.ERASE, opacity)

    var alpha := _read(doc).a
    doc.free()
    return alpha


## *under* in the layer, *over* in the buffer, one alpha lock composite at
## *opacity*, and what the layer is left holding.
func _commit_alpha_locked(under: Color, over: Color, opacity: float) -> Color:
    var doc := _document()
    doc.active_layer.get_or_create_chunk(Vector2i(0, 0)).albedo().clear(under)

    doc.begin_stroke(opacity, SaLayer.BLEND_MODE.NORMAL, SaLayer.BLEND_MODE.ALPHA_LOCK)
    doc.stroke_layer.get_or_create_chunk(Vector2i(0, 0)).albedo().clear(over)
    doc.commit_stroke()

    var out := _read(doc)
    doc.free()
    return out
