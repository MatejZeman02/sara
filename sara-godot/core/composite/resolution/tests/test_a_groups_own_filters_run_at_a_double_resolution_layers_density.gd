## Zoomed in, an isolated group whose own filters run shows the
## detail of the layer at 2.0 inside it, its filters run at 2.0.
##
## The document is two chunks across. A plain opaque layer covers it, and an
## isolated group above holds one layer at 2.0 painted with squares six texels
## across whose edges fall inside a document pixel, over both chunks, so the
## blur of the chunk on the left reads the chunk on the right. The group carries
## a Gaussian blur and a brightness and contrast, a point filter the app ships,
## so the scenario's fixture opens with both.
##
## The reference is the same document with the two records on the layer at 2.0
## instead of on the group, which is the road and runs at 2.0 throughout. The
## group is isolated, at full opacity and Normal, and holds the one layer, so
## its composite before its filters is the layer's and the two show the same.
## Each case runs with the layer inside the group active, which opens the
## group's scope, and with the plain layer active, where the walk composites
## the group afresh from its members in place of its cache.
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
## Half floats round a composite, and the reference takes the same steps.
const TOLERANCE := 1.0e-3
## Where the group and the reference first part when the chain brought the
## group's composite down: a blurred edge inside a document pixel.
const DETAIL := 1.0e-2
const RADIUS := 2.0
const FIXTURE := "res://tests/data/group_filters_at_density.sad"

var _zoom := 4.0


func before_each() -> void:
    _zoom = 4.0


## The squares at texel (*x*, *y*) of the layer at 2.0, counted from the
## document's corner, edges one texel into a document pixel.
static func _square(x: int, y: int) -> Color:
    @warning_ignore("integer_division")
    return ONE if ((x + 1) / 6 + (y + 1) / 6) % 2 == 0 else TWO


func _upload(texture: SaTexture, grid_pos: Vector2i) -> void:
    var image := Image.create_empty(texture.size.x, texture.size.y, false, Image.FORMAT_RGBAF)
    var corner := grid_pos * texture.size.x
    for y in texture.size.y:
        for x in texture.size.x:
            image.set_pixel(x, y, _square(corner.x + x, corner.y + y))
    image.convert(Image.FORMAT_RGBAH if texture.format == RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT else Image.FORMAT_RGBAF)
    GlobalShaderCompiler.get_rd().texture_update(texture.rid, 0, image.get_data())


## The document of the header, the records on the group when *on_group* and on
## the layer at 2.0 otherwise, that layer active when *inside*.
func _easel(on_group: bool, inside: bool) -> SaEasel:
    var easel := Bench.easel(SIZE)
    _with_filters(easel)
    easel.shown_rect = func() -> Rect2: return Rect2(Vector2.ZERO, Vector2(SIZE))
    easel.pixels_per_texel = func() -> float: return _zoom
    var doc := easel.document
    var ops := SaLayerOps.new(doc)
    var under := doc.get_node("Layer 1") as SaLayer
    doc.set_active_layer(under)
    var boat := ops.add(&"", null, 2.0)
    for x in 2:
        under.get_or_create_chunk(Vector2i(x, 0)).clear(UNDER)
        _upload(boat.get_or_create_chunk(Vector2i(x, 0)).albedo(), Vector2i(x, 0))
    doc.set_active_layer(boat)
    var group := ops.group_active()
    ops.set_isolated(group, true)
    var dressed: SaLayer = group if on_group else boat
    var filters := SaFilterOps.new(doc)
    var blur := SaFilterRegistry.key_for(&"sara-base-modules", SaGaussianBlurFilter.new())
    assert_not_null(filters.attach(dressed, blur, {"radius": RADIUS}), "The blur attaches")
    var point := SaFilterRegistry.key_for(&"sara-base-modules", SaBrightnessContrastFilter.new())
    assert_not_null(filters.attach(dressed, point, {"brightness": 30.0, "contrast": 25.0}), "The point filter attaches")
    doc.set_active_layer(boat if inside else under)
    doc.invalidate_chunks([Vector2i(0, 0), Vector2i(1, 0)])
    Bench.composite(easel)
    return easel


static func _bytes(texture: SaTexture) -> PackedByteArray:
    return GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)


static func _texel(bytes: PackedByteArray, texture: SaTexture, at: Vector2i) -> Color:
    return SaFieldSpec.decode_texel(bytes, texture.format, at.y * texture.size.x + at.x)


static func _apart(a: Color, b: Color) -> float:
    return maxf(maxf(absf(a.r - b.r), absf(a.g - b.g)), maxf(absf(a.b - b.b), absf(a.a - b.a)))


func _what(inside: bool) -> String:
    return "the layer inside the group active" if inside else "the plain layer active"


## Every display texel of both chunks is the reference's within the tolerance,
## and the two texels of a document pixel differ where an edge crosses it.
func _shows_the_detail(inside: bool) -> void:
    var what := _what(inside)
    var easel := _easel(true, inside)
    var alike := _easel(false, inside)
    var parted := 0.0
    for grid_pos: Vector2i in [Vector2i(0, 0), Vector2i(1, 0)]:
        var chunk: SaTexture = easel.detail.chunks.get(grid_pos, null)
        var wanted: SaTexture = alike.detail.chunks.get(grid_pos, null)
        assert_true(chunk != null and wanted != null, "%s: a display chunk at %s in both" % [what, grid_pos])
        if chunk == null or wanted == null:
            continue
        var found := _bytes(chunk)
        var expected := _bytes(wanted)
        var worst := 0.0
        var worst_at := Vector2i.ZERO
        for y in chunk.size.y:
            for x in chunk.size.x:
                var at := Vector2i(x, y)
                var off := _apart(_texel(found, chunk, at), _texel(expected, wanted, at))
                if off > worst:
                    worst = off
                    worst_at = at
                if x % 2 == 0:
                    parted = maxf(parted, _apart(_texel(found, chunk, at), _texel(found, chunk, at + Vector2i(1, 0))))
        var told := "%s: chunk %s is the reference's within %s, worst %s at %s"
        assert_true(worst <= TOLERANCE, told % [what, grid_pos, TOLERANCE, worst, worst_at])
    assert_true(parted > DETAIL, "%s: the two texels of a document pixel differ where an edge crosses it, by %s" % [what, parted])
    easel.free()
    alike.free()


func test_a_filtered_group_shows_its_member_at_2_with_the_plain_layer_active() -> void:
    _shows_the_detail(false)


func test_a_filtered_group_shows_its_member_at_2_with_its_scope_open() -> void:
    _shows_the_detail(true)


## The output at 100 per cent is the one the walk at 400 per cent leaves, to
## the bit, so the display chunks' walks take nothing from it.
func test_the_output_at_100_is_untouched_by_the_detail() -> void:
    for inside: bool in [false, true]:
        _zoom = 1.0
        var flat := _easel(true, inside)
        _zoom = 4.0
        var zoomed := _easel(true, inside)
        assert_true(flat.detail.chunks.is_empty(), "%s: no display chunk at 100 per cent" % _what(inside))
        assert_eq(_bytes(zoomed.output), _bytes(flat.output), "%s: the output" % _what(inside))
        flat.free()
        zoomed.free()


## The scenario's fixture, the document of the header with the records on the
## group and the plain layer active, held against the tracked file as the is.
func test_the_scenarios_fixture_is_written_and_opens() -> void:
    var easel := _easel(true, false)
    var scratch := ProjectSettings.globalize_path(SaDataRoot.path("a1_group_filters_fixture.sad"))
    DirAccess.remove_absolute(scratch)
    ScenarioFixture.pin(easel.document)
    assert_eq(SaExport.save_sad(easel.document, scratch), OK, "The fixture saves")
    easel.free()
    var written := FileAccess.get_file_as_bytes(scratch)
    DirAccess.remove_absolute(scratch)
    assert_false(ScenarioFixture.stale(FIXTURE, written), ScenarioFixture.why(FIXTURE))
    var loaded := Bench.easel(Vector2i(64, 64))
    _with_filters(loaded)
    assert_eq(SaExport.load_sad(loaded.document, FIXTURE, loaded.compositor), OK, "and opens")
    var filtered := 0
    for child in loaded.document.get_children():
        if child is SaLayer and (child as SaLayer).filters.size() == 2:
            filtered += 1
    assert_eq(filtered, 1, "with the group carrying its two records")
    loaded.free()


## *easel*, its chain answering the blur and the brightness the app registers.
static func _with_filters(easel: SaEasel) -> void:
    easel.compositor.filter_chain.registry.register(SaGaussianBlurFilter.new(), &"sara-base-modules")
    easel.compositor.filter_chain.registry.register(SaBrightnessContrastFilter.new(), &"sara-base-modules")
