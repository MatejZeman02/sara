## Zoomed in, a layer at 2.0 shows its own detail inside an
## isolated group that is not active, and when it is masked, clipped or
## filtered.
##
## The document is two chunks across. A plain opaque layer covers it, and a
## layer at 2.0 above holds a one-texel checker of two colours at grid
## position 0, one opaque and one mostly clear, so a clip onto it shows its
## alpha. Each case dresses that layer, and a display texel should be what a
## reference document dressed the same way shows at 1.0 with the layer filled
## by the checker's colour under that texel, the way the sibling suite reads it. Every
## case runs with the layer at 2.0 active and with the plain layer active,
## since the two reach it through different paths of the walk.
##
## The suite builds its scenario's fixture under `tests/data/` and fails when
## the file this build saves differs from it. It rewrites the tracked file only
## under `SARA_REWRITE_FIXTURES=1`.
extends "res://tests/test_framework.gd"

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")
const ScenarioFixture = preload("res://tests/fixtures/scenario_fixture.gd")

const REQUIRES_GPU := true

const SIZE := Vector2i(512, 256)
const ONE := Color(0.25, 0.5, 0.75, 1.0)
const TWO := Color(0.75, 0.25, 0.125, 0.25)
const UNDER := Color(0.125, 0.625, 0.25, 1.0)
const BASE := Color(0.875, 0.75, 0.125, 0.5)
const OVER := Color(0.5, 0.75, 1.0, 1.0)
const AT := Vector2i(0, 0)
## Half floats round a composite, and the reference takes the same steps.
const TOLERANCE := 1.0e-3
const FIXTURE := "res://tests/data/every_composite_path.sad"
## The fixture's four cases, in document pixels around the chunk's centre.
const QUADRANTS: Array[Rect2i] = [
    Rect2i(88, 98, 38, 28), Rect2i(130, 98, 38, 28), Rect2i(88, 130, 38, 28), Rect2i(130, 130, 38, 28)
]

## What the view shows, in document pixels, and its pixels per texel.
var _shown := Rect2(0, 0, 256, 256)
var _zoom := 4.0


func before_each() -> void:
    _shown = Rect2(0, 0, 256, 256)
    _zoom = 4.0


func _checker(x: int, y: int) -> Color:
    return ONE if (x + y) % 2 == 0 else TWO


func _upload(texture: SaTexture, texel: Callable) -> void:
    var image := Image.create_empty(texture.size.x, texture.size.y, false, Image.FORMAT_RGBAF)
    for y in texture.size.y:
        for x in texture.size.x:
            image.set_pixel(x, y, texel.call(x, y))
    image.convert(Image.FORMAT_RGBAH if texture.format == RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT else Image.FORMAT_RGBAF)
    GlobalShaderCompiler.get_rd().texture_update(texture.rid, 0, image.get_data())


## The document of the header dressed as *dress* says: "plain", "masked",
## "unmasked" with a mask of ones, "clipped" onto a half clear base,
## "clipped_onto" with a layer at 1.0 clipped onto it, "filtered" with the
## fixture invert, and "grouped" inside an isolated group at half opacity.
## *colour* is null for the checker at 2.0 and a colour for a reference at 1.0.
## *active* is true for the layer at 2.0, false for the plain one.
func _easel(dress: String, colour: Variant, active: bool) -> SaEasel:
    var easel := Bench.easel(SIZE)
    if colour == null:
        easel.shown_rect = func() -> Rect2: return _shown
        easel.pixels_per_texel = func() -> float: return _zoom
    var doc := easel.document
    var ops := SaLayerOps.new(doc)
    var under := doc.get_node("Layer 1") as SaLayer
    for x in range(0, SIZE.x, SaChunk.SIZE).size():
        under.get_or_create_chunk(Vector2i(x, 0)).clear(UNDER)
    doc.set_active_layer(under)
    if dress == "clipped":
        ops.add().get_or_create_chunk(AT).clear(BASE)
    var boat := ops.add(&"", null, 2.0 if colour == null else 1.0)
    var chunk := boat.get_or_create_chunk(AT)
    if colour == null:
        _upload(chunk.albedo(), _checker)
    else:
        chunk.clear(colour as Color)
    doc.set_active_layer(boat)
    match dress:
        "masked":
            boat.add_mask(0.5)
        "unmasked":
            boat.add_mask(1.0)
        "clipped":
            SaLayerStack.set_clip_to_below(doc, boat, true)
        "clipped_onto":
            var over := ops.add()
            over.get_or_create_chunk(AT).clear(OVER)
            SaLayerStack.set_clip_to_below(doc, over, true)
            doc.set_active_layer(boat)
        "filtered":
            assert_not_null(SaFilterOps.new(doc).attach(boat, Bench.INVERT), "The invert attaches")
        "grouped":
            var group := ops.group_active()
            ops.set_isolated(group, true)
            group.opacity = 0.5
            doc.set_active_layer(boat)
    doc.set_active_layer(boat if active else under)
    doc.invalidate_chunks([AT, Vector2i(1, 0)])
    _composite(easel)
    return easel


func _composite(easel: SaEasel) -> void:
    Bench.composite(easel)


func _display(easel: SaEasel) -> SaTexture:
    return easel.detail.chunks.get(AT, null)


## The output of the reference for *dress* whose layer is *colour* at 1.0.
func _reference(dress: String, colour: Color, active: bool) -> Color:
    var easel := _easel(dress, colour, active)
    var found := Bench.texel(easel.output, Vector2i(10, 10))
    easel.free()
    return found


static func _near(a: Color, b: Color) -> bool:
    return (
        absf(a.r - b.r) <= TOLERANCE
        and absf(a.g - b.g) <= TOLERANCE
        and absf(a.b - b.b) <= TOLERANCE
        and absf(a.a - b.a) <= TOLERANCE
    )


## Every display texel of the checker's chunk is its checker colour's
## reference, and the two references differ, so the detail shows.
func _shows_the_detail(dress: String, active: bool) -> void:
    var what := "%s, %s active" % [dress, "the layer at 2.0" if active else "the plain layer"]
    var easel := _easel(dress, null, active)
    var chunk := _display(easel)
    assert_not_null(chunk, "%s: a display chunk over the layer at 2.0" % what)
    if chunk == null:
        easel.free()
        return
    var expected := [_reference(dress, ONE, active), _reference(dress, TWO, active)]
    assert_false(_near(expected[0], expected[1]), "%s: the two checker colours show apart" % what)
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(chunk.rid, 0)
    for y in chunk.size.y:
        for x in chunk.size.x:
            var found := SaFieldSpec.decode_texel(bytes, chunk.format, y * chunk.size.x + x)
            var wanted: Color = expected[(x + y) % 2]
            if not _near(found, wanted):
                assert_true(false, "%s: display texel (%d, %d) is %s, its checker colour shows %s" % [what, x, y, found, wanted])
                easel.free()
                return
    assert_true(true, "%s: every display texel is its own checker texel's" % what)
    easel.free()


func test_a_masked_layer_shows_its_detail() -> void:
    _shows_the_detail("masked", true)
    _shows_the_detail("masked", false)


func test_a_layer_clipped_to_a_base_shows_its_detail() -> void:
    _shows_the_detail("clipped", true)
    _shows_the_detail("clipped", false)


func test_a_layer_clipped_onto_it_shows_the_detail_of_its_alpha() -> void:
    _shows_the_detail("clipped_onto", true)
    _shows_the_detail("clipped_onto", false)


func test_a_filtered_layer_shows_its_detail() -> void:
    _shows_the_detail("filtered", true)
    _shows_the_detail("filtered", false)


func test_inside_an_isolated_group_the_layer_shows_its_detail() -> void:
    _shows_the_detail("grouped", false)
    _shows_the_detail("grouped", true)


func test_a_plain_layer_shows_its_detail_as_before() -> void:
    _shows_the_detail("plain", true)
    _shows_the_detail("plain", false)


## A mask of ones hides nothing, and the display chunk and the output are the
## unmasked ones to the bit.
func test_a_mask_of_ones_matches_the_unmasked_case_at_tolerance_0() -> void:
    for active: bool in [true, false]:
        var plain := _easel("plain", null, active)
        var ones := _easel("unmasked", null, active)
        var rd := GlobalShaderCompiler.get_rd()
        var what := "the layer at 2.0 active" if active else "the plain layer active"
        assert_true(_display(plain) != null and _display(ones) != null, "%s: both show a display chunk" % what)
        if _display(plain) != null and _display(ones) != null:
            assert_eq(
                rd.texture_get_data(_display(ones).rid, 0),
                rd.texture_get_data(_display(plain).rid, 0),
                "%s: the display chunk" % what
            )
        assert_eq(rd.texture_get_data(ones.output.rid, 0), rd.texture_get_data(plain.output.rid, 0), "%s: the output" % what)
        plain.free()
        ones.free()


## A mask stored at 2.0 hides at its own texels: columns of one and zero
## leave every other display texel the layer and every other the one under.
func test_a_mask_at_2_hides_at_its_own_texels() -> void:
    var easel := _easel("plain", null, false)
    var fine := func(n: Node) -> bool: return n is SaLayer and n.resolution_scale > 1.0
    var boat: SaLayer = easel.document.get_children().filter(fine)[0]
    var coverage := boat.add_mask(1.0).get_or_create(AT)
    assert_eq(coverage.size, Vector2i(512, 512), "The mask of a layer at 2.0 is stored at 2.0")
    var values := PackedFloat32Array()
    values.resize(coverage.size.x * coverage.size.y)
    for y in coverage.size.y:
        for x in coverage.size.x:
            values[y * coverage.size.x + x] = 1.0 if x % 2 == 0 else 0.0
    GlobalShaderCompiler.get_rd().texture_update(coverage.rid, 0, values.to_byte_array())
    easel.document.invalidate_chunks([AT])
    _composite(easel)
    var chunk := _display(easel)
    assert_not_null(chunk, "A display chunk over the masked layer")
    if chunk != null:
        assert_true(_near(Bench.texel(chunk, Vector2i(1, 0)), UNDER), "Column 1 is masked away to the layer under")
        assert_true(_near(Bench.texel(chunk, Vector2i(3, 2)), UNDER), "and so is column 3")
        assert_false(_near(Bench.texel(chunk, Vector2i(0, 0)), UNDER), "Column 0 shows the layer")
    easel.free()


## The group's layer is not in the walk, its cache is, and the detail view
## still finds the chunk the layer at 2.0 holds inside it.
func test_the_detail_view_counts_a_layer_inside_a_group_the_walk_sets_aside() -> void:
    var easel := _easel("grouped", null, false)
    assert_eq(easel.detail.chunks.keys(), [AT], "One display chunk, over the layer inside the group")
    easel.free()


## The scenario's fixture, one chunk with a quadrant a case around its centre,
## so the four show at 400 per cent in one shot: masked at the top left,
## clipped to a half clear base at the top right, filtered by brightness and
## contrast at the bottom left, and inside an isolated group at the bottom
## right. Held against the tracked file, as the is.
func test_the_scenarios_fixture_is_written_and_opens_with_every_case() -> void:
    var easel := _with_brightness(Bench.easel(Vector2i(256, 256)))
    var doc := easel.document
    var ops := SaLayerOps.new(doc)
    var under := doc.get_node("Layer 1") as SaLayer
    under.get_or_create_chunk(AT).clear(UNDER)
    doc.set_active_layer(under)
    var masked := _quadrant(ops, "Masked", QUADRANTS[0])
    masked.add_mask(0.5)
    var base := ops.add()
    base.name = "Base"
    _upload(
        base.get_or_create_chunk(AT).albedo(),
        func(x: int, y: int) -> Color: return BASE if QUADRANTS[1].has_point(Vector2i(x, y)) else Color(0, 0, 0, 0)
    )
    var clipped := _quadrant(ops, "Clipped", QUADRANTS[1])
    SaLayerStack.set_clip_to_below(doc, clipped, true)
    var filtered := _quadrant(ops, "Filtered", QUADRANTS[2])
    var key := SaFilterRegistry.key_for(&"sara-base-modules", SaBrightnessContrastFilter.new())
    assert_not_null(SaFilterOps.new(doc).attach(filtered, key, {"brightness": 30.0, "contrast": 25.0}), "The filter attaches")
    doc.set_active_layer(_quadrant(ops, "Grouped", QUADRANTS[3]))
    var group := ops.group_active()
    group.name = "Group"
    ops.set_isolated(group, true)
    group.opacity = 0.75
    doc.set_active_layer(under)
    var scratch := ProjectSettings.globalize_path(SaDataRoot.path("a6_fixture.sad"))
    DirAccess.remove_absolute(scratch)
    ScenarioFixture.pin(doc)
    assert_eq(SaExport.save_sad(doc, scratch), OK, "The fixture saves")
    easel.free()
    var written := FileAccess.get_file_as_bytes(scratch)
    DirAccess.remove_absolute(scratch)
    assert_false(ScenarioFixture.stale(FIXTURE, written), ScenarioFixture.why(FIXTURE))

    var loaded := _with_brightness(Bench.easel(Vector2i(64, 64)))
    assert_eq(SaExport.load_sad(loaded.document, FIXTURE, loaded.compositor), OK, "and opens")
    var names: Array = []
    for child in loaded.document.get_children():
        if child is SaLayer and child.resolution_scale == 2.0:
            names.append(str(child.name))
    names.sort()
    assert_eq(names, ["Clipped", "Filtered", "Grouped", "Masked"], "with the four layers at 2.0")
    loaded.free()


## *easel*, its chain answering the brightness and contrast the app registers.
func _with_brightness(easel: SaEasel) -> SaEasel:
    easel.compositor.filter_chain.registry.register(SaBrightnessContrastFilter.new(), &"sara-base-modules")
    return easel


## A layer at 2.0 called *layer_name* holding the checker over *quadrant*, in
## document pixels, and nothing elsewhere.
func _quadrant(ops: SaLayerOps, layer_name: String, quadrant: Rect2i) -> SaLayer:
    var layer := ops.add(&"", null, 2.0)
    layer.name = layer_name
    var inside := func(x: int, y: int) -> Color:
        @warning_ignore("integer_division")
        return _checker(x, y) if quadrant.has_point(Vector2i(x / 2, y / 2)) else Color(0, 0, 0, 0)
    _upload(layer.get_or_create_chunk(AT).albedo(), inside)
    return layer
