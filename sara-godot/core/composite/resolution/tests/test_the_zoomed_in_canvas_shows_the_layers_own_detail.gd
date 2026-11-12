## Zoomed in past 100%, the canvas shows a double resolution
## layer's own texels, composited at twice the density with the layers at 1.0
## above and below it magnified.
##
## The document is seven chunks across. A plain layer below in Normal covers
## it, a layer at 2.0 above that holds a one-texel checker of two half
## transparent colours at grid positions 0, 1, 5 and 6, and a plain layer above
## in multiply at half opacity covers it again. The view is two Callables on
## the easel, the ones `SaCanvas` hands in, so the suite moves the window and
## the zoom without a window of its own. What a display texel should be is read
## off a reference document whose layer at 2.0 is a layer at 1.0 filled with
## that texel's colour, composited by the same walk.
##
## The suite builds its scenario's fixture under `tests/data/` and fails when
## the file this build saves differs from it. It rewrites the tracked file only
## under `SARA_REWRITE_FIXTURES=1`.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")
const ScenarioFixture = preload("res://tests/fixtures/scenario_fixture.gd")

const REQUIRES_GPU := true

const SIZE := Vector2i(1792, 256)
const ONE := Color(0.25, 0.5, 0.75, 0.5)
const TWO := Color(0.75, 0.25, 0.125, 0.5)
const MEAN := Color(0.5, 0.375, 0.4375, 0.5)
const UNDER := Color(0.125, 0.625, 0.25, 1.0)
const OVER := Color(0.5, 0.75, 1.0, 1.0)
const STROKE := Color(1.0, 0.0, 0.5, 1.0)
const FINE_AT: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(5, 0), Vector2i(6, 0)]

## What the view shows, in document pixels, and its pixels per texel, which
## the easel reads through the two Callables `_bind_view` hands it.
var _shown := Rect2(0, 0, 256, 256)
var _zoom := 4.0


## Hands *easel* the view above, read afresh on every frame.
func _bind_view(easel: SaEasel) -> void:
    easel.shown_rect = func() -> Rect2: return _shown
    easel.pixels_per_texel = func() -> float: return _zoom


func _checker(x: int, y: int) -> Color:
    return ONE if (x + y) % 2 == 0 else TWO


func _upload(texture: SaTexture, texel: Callable) -> void:
    var image := Image.create_empty(texture.size.x, texture.size.y, false, Image.FORMAT_RGBAF)
    for y in texture.size.y:
        for x in texture.size.x:
            image.set_pixel(x, y, texel.call(x, y))
    GlobalShaderCompiler.get_rd().texture_update(texture.rid, 0, image.get_data())


func _every_position() -> Array:
    var found: Array = []
    for _x in range(0, SIZE.x, SaLayer.CHUNK_SIZE):
        found.append(Vector2i(found.size(), 0))
    return found


## The document of the header. *middle* is null for the checker at 2.0, and a
## colour for a reference whose middle layer is that colour at 1.0. *active*
## picks the active layer, "under", "middle" or "over".
func _easel(middle: Variant, active: String) -> SaEasel:
    var easel := SaEasel.create_default(SIZE)
    easel.compositor.set_registry(Fixtures.make_registries().blend_modes)
    # A reference is composited whole, as a suite's easel with no view is.
    if middle == null:
        _bind_view(easel)
    var doc := easel.document
    var ops := SaLayerOps.new(doc)
    var under := doc.get_node("Layer 1") as SaLayer
    for grid_pos: Vector2i in _every_position():
        under.get_or_create_chunk(grid_pos).clear(UNDER)
    doc.set_active_layer(under)
    var fine := middle == null
    var boat := ops.add(&"", null, 2.0 if fine else 1.0)
    for grid_pos: Vector2i in FINE_AT:
        var chunk := boat.get_or_create_chunk(grid_pos)
        if fine:
            _upload(chunk.albedo(), _checker)
        else:
            chunk.clear(middle as Color)
    doc.set_active_layer(boat)
    var over := ops.add()
    for grid_pos: Vector2i in _every_position():
        over.get_or_create_chunk(grid_pos).clear(OVER)
    ops.set_blend_mode(over, &"multiply")
    over.opacity = 0.5
    doc.set_active_layer({"under": under, "middle": boat, "over": over}[active])
    doc.invalidate_chunks(_every_position())
    _composite(easel)
    return easel


func _composite(easel: SaEasel) -> void:
    easel.document.update_caches()
    easel.request_full_composite()
    easel.process_pending_composite()


func _texel(texture: SaTexture, at: Vector2i) -> Color:
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    return SaFieldSpec.decode_texel(bytes, texture.format, at.y * texture.size.x + at.x)


## The output of a reference document whose middle layer is *colour* at 1.0,
## at a pixel of grid position 0, with *active* active as in the fine one.
func _reference(colour: Color, active: String) -> Color:
    var easel := _easel(colour, active)
    var found := _texel(easel.output, Vector2i(10, 10))
    easel.free()
    return found


## The layer at 2.0.
func _boat(easel: SaEasel) -> SaLayer:
    for child in easel.document.get_children():
        var layer := child as SaLayer
        if layer != null and layer.resolution_scale > 1.0:
            return layer
    return null


## A stroke chunk in Normal over the whole of grid position 0.
func _stroke(easel: SaEasel) -> void:
    easel.document.begin_stroke(1.0, SaLayer.BLEND_MODE.NORMAL)
    easel.document.stroke_layer.get_or_create_chunk(Vector2i(0, 0)).clear(STROKE)
    easel.document.invalidate_chunks([Vector2i(0, 0)])
    easel.process_pending_composite()


func _positions(easel: SaEasel) -> Array:
    var found: Array = easel.detail.chunks.keys()
    found.sort()
    return found


## Every texel of the display chunk at *grid_pos* is the composite of the
## checker's texel under it with the plain layers over and under it.
func _detail_is_the_checker(easel: SaEasel, grid_pos: Vector2i, active: String, what: String) -> void:
    var chunk: SaTexture = easel.detail.chunks.get(grid_pos, null)
    assert_true(chunk != null, "%s: a display chunk at %s" % [what, grid_pos])
    if chunk == null:
        return
    assert_eq(chunk.size, Vector2i(512, 512), "%s: the display chunk is 512 texels across" % what)
    var expected := {0: _reference(ONE, active), 1: _reference(TWO, active)}
    assert_false((expected[0] as Color).is_equal_approx(expected[1]), "%s: the two checker colours composite apart" % what)
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(chunk.rid, 0)
    for y in 512:
        for x in 512:
            var found := SaFieldSpec.decode_texel(bytes, chunk.format, y * 512 + x)
            var wanted: Color = expected[(x + y) % 2]
            if not found.is_equal_approx(wanted):
                assert_true(
                    false, "%s: display texel (%d, %d) is %s, the checker's composite is %s" % [what, x, y, found, wanted]
                )
                return
    assert_true(true, "%s: every display texel is its checker texel's composite" % what)


func before_each() -> void:
    _shown = Rect2(0, 0, 256, 256)
    _zoom = 4.0


func test_at_400_percent_a_display_chunk_holds_the_checker_composited() -> void:
    var easel := _easel(null, "over")
    assert_eq(
        _positions(easel), [Vector2i(0, 0), Vector2i(1, 0)], "The window over grid 0 grown by a chunk reaches the two fine chunks"
    )
    _detail_is_the_checker(easel, Vector2i(0, 0), "over", "Active above the layer at 2.0")
    _detail_is_the_checker(easel, Vector2i(1, 0), "over", "The second chunk, active above")
    easel.free()


func test_the_detail_shows_whichever_layer_is_active() -> void:
    for active: String in ["middle", "under"]:
        var easel := _easel(null, active)
        _detail_is_the_checker(easel, Vector2i(0, 0), active, "Active " + active)
        easel.free()


func test_at_100_percent_no_display_chunk_and_the_canvas_shows_the_mean() -> void:
    _zoom = 1.0
    var easel := _easel(null, "over")
    assert_true(easel.detail.chunks.is_empty(), "No display chunk at 100%")
    var mean := _reference(MEAN, "over")
    var found := _texel(easel.output, Vector2i(10, 10))
    assert_true(found.is_equal_approx(mean), "The canvas at 100%% is the layer's mean, %s against %s" % [found, mean])
    _zoom = 1.0 + SaDetailView.EPSILON * 0.5
    easel.process_pending_composite()
    assert_true(easel.detail.chunks.is_empty(), "Within the epsilon of 100% is still 100%")
    easel.free()


func test_a_pan_follows_the_window_and_releases_what_it_left() -> void:
    var easel := _easel(null, "over")
    var first: SaTexture = easel.detail.chunks[Vector2i(0, 0)]
    _shown = Rect2(768, 0, 256, 256)
    easel.process_pending_composite()
    assert_eq(_positions(easel), [], "Over grid 3, whose window reaches 2 to 4, the layer at 2.0 holds nothing")
    _shown = Rect2(1536, 0, 256, 256)
    easel.process_pending_composite()
    assert_eq(_positions(easel), [Vector2i(5, 0), Vector2i(6, 0)], "Panned to grid 6 the display chunks are 5 and 6")
    _detail_is_the_checker(easel, Vector2i(6, 0), "over", "After the pan")
    _shown = Rect2(0, 0, 256, 256)
    easel.process_pending_composite()
    assert_eq(_positions(easel), [Vector2i(0, 0), Vector2i(1, 0)], "Back over grid 0")
    assert_true(easel.detail.chunks[Vector2i(0, 0)] != first, "A chunk left behind was released and is made afresh")
    easel.free()


func test_zooming_out_releases_every_display_chunk() -> void:
    var easel := _easel(null, "over")
    assert_false(easel.detail.chunks.is_empty(), "Zoomed in there are display chunks")
    _zoom = 0.5
    easel.process_pending_composite()
    assert_true(easel.detail.chunks.is_empty(), "Zoomed out to 50% there are none")
    _zoom = 4.0
    easel.process_pending_composite()
    assert_eq(_positions(easel), [Vector2i(0, 0), Vector2i(1, 0)], "Zoomed back in they come back")
    easel.free()


func test_no_display_chunk_without_a_visible_layer_at_2() -> void:
    var easel := _easel(null, "over")
    var boat := _boat(easel)
    boat.visible = false
    _composite(easel)
    assert_true(easel.detail.chunks.is_empty(), "A hidden layer at 2.0 draws no detail")
    boat.visible = true
    _composite(easel)
    assert_false(easel.detail.chunks.is_empty(), "Shown again it does")
    var plain := _easel(MEAN, "over")
    _bind_view(plain)
    plain.process_pending_composite()
    assert_true(plain.detail.chunks.is_empty(), "A document of layers at 1.0 draws no detail")
    plain.free()
    easel.free()


func test_a_resize_releases_the_display_chunks() -> void:
    var easel := _easel(null, "over")
    easel.resize_output(SIZE)
    assert_true(easel.detail.chunks.is_empty(), "A swap or a resize lets every display chunk go")
    easel.process_pending_composite()
    assert_eq(_positions(easel), [Vector2i(0, 0), Vector2i(1, 0)], "and the next frame makes them again")
    easel.free()


## A stroke on the plain layer above the one at 2.0 reaches the display chunk
## under it in the frame it reaches the output.
func test_a_stroke_above_reaches_the_display_chunk_in_the_same_frame() -> void:
    var easel := _easel(null, "over")
    _stroke(easel)
    var on_output := _texel(easel.output, Vector2i(10, 10))
    var chunk: SaTexture = easel.detail.chunks[Vector2i(0, 0)]
    var in_detail := [_texel(chunk, Vector2i(20, 20)), _texel(chunk, Vector2i(21, 20))]
    easel.free()
    var wanted: Array = []
    for colour: Color in [MEAN, ONE, TWO]:
        var plain := _easel(colour, "over")
        _stroke(plain)
        wanted.append(_texel(plain.output, Vector2i(10, 10)))
        plain.free()
    assert_true(on_output.is_equal_approx(wanted[0]), "The output shows the stroke, %s against %s" % [on_output, wanted[0]])
    for i in 2:
        assert_true(
            in_detail[i].is_equal_approx(wanted[i + 1]),
            "The display chunk shows it in the same frame, %s against %s" % [in_detail[i], wanted[i + 1]]
        )
    assert_false((wanted[0] as Color).is_equal_approx(_reference(MEAN, "over")), "The stroke changed the picture")


## The fold keeps a layer at 2.0 out of its caches, so the walk reads it as a
## step of its own wherever it is below the active layer.
func test_the_fold_keeps_a_layer_at_2_out_of_its_caches() -> void:
    var easel := _easel(null, "over")
    var boat := _boat(easel)
    var walked := SaLayerStack.layers(easel.document)
    assert_true(walked.has(boat), "Below the active layer the layer at 2.0 is walked itself")
    var mean := _reference(MEAN, "over")
    var found := _texel(easel.output, Vector2i(10, 10))
    assert_true(found.is_equal_approx(mean), "and the output still shows its mean, %s against %s" % [found, mean])
    easel.free()


## A display chunk is a composite of the walk into its own texture, so the
## output beside it is untouched by it: the walk's destination is placed only
## while the display chunk is composited.
func test_the_target_places_only_its_own_destination() -> void:
    var target := SaDetailView.Target.new()
    var chunk := SaTexture.new(SaDetailView.side(), RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT)
    var other := SaTexture.new(Vector2i(8, 8), RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT)
    target.begin(chunk, Vector2(512, 256), 2.0)
    var placed := target.placed(chunk, Vector2(512, 256), Rect2i(10, 20, 30, 40), 2.0)
    assert_eq(
        _fields(placed),
        [Vector2.ZERO, Rect2i(20, 40, 60, 80), 1.0],
        "Into the display chunk: from its corner, doubled, the fine source at 1"
    )
    assert_eq(target.placed(chunk, Vector2(512, 256), Rect2i(0, 0, 8, 8), 1.0).density, 0.5, "A chunk at 1.0 is read at 0.5")
    assert_eq(
        _fields(target.placed(other, Vector2(5, 6), Rect2i(1, 2, 3, 4), 2.0)),
        [Vector2(5, 6), Rect2i(1, 2, 3, 4), 2.0],
        "Any other destination is untouched"
    )
    target.end()
    assert_eq(
        target.placed(chunk, Vector2(5, 6), Rect2i(1, 2, 3, 4), 2.0).region, Rect2i(1, 2, 3, 4), "and at rest nothing moves"
    )


## What *placed* holds, in the order the assertions write it.
static func _fields(placed: SaDetailView.Placed) -> Array:
    return [placed.offset, placed.region, placed.density]


## The scenario's fixture, written here through the writer so the file the
## app opens is the document this suite checks: 512 by 256, the header's three
## layers over both grid positions, and read back at 2.0 with its checker.
const FIXTURE := "res://tests/data/double_resolution_boat.sad"


func test_the_scenarios_fixture_is_written_and_opens_at_2() -> void:
    var easel := SaEasel.create_default(Vector2i(512, 256))
    easel.compositor.set_registry(Fixtures.make_registries().blend_modes)
    var doc := easel.document
    var ops := SaLayerOps.new(doc)
    var under := doc.get_node("Layer 1") as SaLayer
    var both: Array = [Vector2i(0, 0), Vector2i(1, 0)]
    for grid_pos: Vector2i in both:
        under.get_or_create_chunk(grid_pos).clear(UNDER)
    doc.set_active_layer(under)
    var boat := ops.add(&"", null, 2.0)
    boat.name = "Boat"
    for grid_pos: Vector2i in both:
        _upload(boat.get_or_create_chunk(grid_pos).albedo(), _checker)
    var over := ops.add()
    for grid_pos: Vector2i in both:
        over.get_or_create_chunk(grid_pos).clear(OVER)
    ops.set_blend_mode(over, &"multiply")
    over.opacity = 0.5
    # Through a scratch path, because a save over a file keeps the old one as
    # `.sad1` beside it.
    var scratch := ProjectSettings.globalize_path(SaDataRoot.path("x8_fixture.sad"))
    DirAccess.remove_absolute(scratch)
    ScenarioFixture.pin(doc)
    assert_eq(SaExport.save_sad(doc, scratch), OK, "The fixture saves")
    easel.free()
    var written := FileAccess.get_file_as_bytes(scratch)
    DirAccess.remove_absolute(scratch)
    assert_false(ScenarioFixture.stale(FIXTURE, written), ScenarioFixture.why(FIXTURE))

    var loaded := SaEasel.create_default(Vector2i(64, 64))
    assert_eq(SaExport.load_sad(loaded.document, FIXTURE, loaded.compositor), OK, "and opens")
    var found: SaLayer = null
    for child in loaded.document.get_children():
        if child is SaLayer and str(child.name) == "Boat":
            found = child
    assert_true(found != null and found.resolution_scale == 2.0, "The boat opens at 2.0")
    if found != null:
        var chunk := found.get_field(Vector2i(1, 0))
        assert_eq(chunk.size, Vector2i(512, 512), "its chunk is 512 texels across")
        assert_true(_texel(chunk, Vector2i(0, 0)).is_equal_approx(ONE), "and holds the checker")
        assert_true(_texel(chunk, Vector2i(1, 0)).is_equal_approx(TWO), "texel for texel")
    loaded.free()
