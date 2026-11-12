## The paper lends its height.
##
## A paper with a tooth answers a height from the same noise its colour reads,
## at the same document position, and the relief adds it whole under the
## paint, however thick. A stroke fills the tooth itself,
## by keeping the brush's height less the tooth it stands on, which the
## deposit's own suites hold. The suite reads the summed height back: against
## the noise worked out here on the CPU, at one document position before and
## after a pan, under paint thin, thick and below nought, and at a tooth of
## nought, which costs what no height costs.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")

## The paper's default tooth, and what the half float and the GPU's single
## precision may leave between the GPU's height and the one here. The
## slack grows with the tooth, and at 0.9 the widest seen was 0.0022.
const TOOTH: float = 0.9
const NEAR: float = 0.004

var _registries: SaRegistries = null
var _easel: SaEasel = null
var _doc: SaDocument = null


func before_each() -> void:
    _registries = Fixtures.make_registries()
    _easel = SaEasel.create_default(Vector2i(768, 768))
    _easel.compositor.set_registry(_registries.blend_modes)
    _doc = _easel.document
    _easel.process_pending_composite()


func after_each() -> void:
    _easel.free()
    _easel = null
    _doc = null
    _registries = null


func _texel(texture: SaTexture, at: Vector2i) -> Color:
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    return SaFieldSpec.decode_texel(bytes, texture.format, at.y * texture.size.x + at.x)


## A paper added under the active layer, which stays the active one. Its
## fibres are off, because the grain this suite works out by hand is the
## pulp's value noise alone.
func _add_paper() -> SaLayer:
    var paint := _doc.active_layer
    var paper := SaLayerOps.new(_doc).add(&"paper", _registries.layer_types)
    paper.generator_params["fibre"] = 0.0
    _doc.set_active_layer(paint)
    _easel.request_full_composite()
    _easel.process_pending_composite()
    return paper


## Gives *layer* a flat height of *mm* over the chunk at *grid_pos*.
func _raise(layer: SaLayer, grid_pos: Vector2i, mm: float) -> void:
    SaHeightOps.new(_doc).gain(layer)
    var texture := layer.get_or_create_field(grid_pos, SaFieldSpec.HEIGHT)
    var bytes := PackedByteArray()
    bytes.resize(texture.size.x * texture.size.y * 2)
    for i in texture.size.x * texture.size.y:
        bytes.encode_half(i * 2, mm)
    GlobalShaderCompiler.get_rd().texture_update(texture.rid, 0, bytes)
    _doc.invalidate_chunks([grid_pos])


## `libs/noise.gmacs`'s three octaves, worked out here, so the suite knows the
## grain the paper's colour reads without reading the colour.
static func _fbm(p: Vector2) -> float:
    var total := 0.0
    var amplitude := 0.5
    var weight := 0.0
    var at := p
    for i in 3:
        total += amplitude * _value_noise(at)
        weight += amplitude
        amplitude *= 0.5
        at *= 2.0
    return total / weight


static func _value_noise(p: Vector2) -> float:
    var floored := p.floor()
    var cell := Vector2i(floored)
    var f := p - floored
    var s := f * f * (Vector2(3.0, 3.0) - 2.0 * f)
    var a := _hash(cell)
    var b := _hash(cell + Vector2i(1, 0))
    var c := _hash(cell + Vector2i(0, 1))
    var d := _hash(cell + Vector2i(1, 1))
    return lerpf(lerpf(a, b, s.x), lerpf(c, d, s.x), s.y)


## `libs/lattice_hash.gmacs`'s `sa_lattice_hash` at a z of nought, in 32-bit
## arithmetic kept by masking GDScript's 64-bit integers.
static func _hash(corner: Vector2i) -> float:
    var h := _lowbias32(0)
    h = _lowbias32((h + corner.y) & 0xFFFFFFFF)
    h = _lowbias32((h + corner.x) & 0xFFFFFFFF)
    return float(h >> 8) / 16777216.0


static func _lowbias32(x: int) -> int:
    x = (x ^ (x >> 16)) & 0xFFFFFFFF
    x = (x * 0x7feb352d) & 0xFFFFFFFF
    x = x ^ (x >> 15)
    x = (x * 0x846ca68b) & 0xFFFFFFFF
    return x ^ (x >> 16)


## The paper's height at *pixel*: its tooth times the grain there.
func _grain(paper: SaLayer, pixel: Vector2i) -> float:
    var scale := float(paper.generator_params[SaGeneratedLayer.PARAM_SCALE])
    return SaGeneratedLayer.tooth_of(paper) * _fbm((Vector2(pixel)) / scale)


func test_a_new_paper_has_a_tooth_and_the_background_none() -> void:
    var paper := SaLayerTypeDescriptor.paper()
    assert_almost_eq(float(paper.generator_defaults["tooth"]), TOOTH, 0.0001, "A new paper stands a tooth high")
    assert_true(SaGeneratedLayer.answers_height(paper), "so the paper answers a height")
    assert_false(SaGeneratedLayer.answers_height(SaLayerTypeDescriptor.background()), "and the flat background none")
    assert_false(SaGeneratedLayer.answers_height(SaLayerTypeDescriptor.plain()), "nor a layer that stores paint")


func test_the_papers_height_is_its_grain_at_the_document_position() -> void:
    var paper := _add_paper()
    var heights := _easel.relief.heights
    assert_not_null(heights, "A paper with a tooth resolves a height with no paint on it")
    if heights == null:
        return
    var spread: Array[float] = []
    for at: Vector2i in [Vector2i(3, 5), Vector2i(100, 17), Vector2i(255, 256), Vector2i(400, 611), Vector2i(767, 767)]:
        var height := _texel(heights, at).r
        spread.append(height)
        assert_almost_eq(height, _grain(paper, at), NEAR, "The height at %s is the tooth times the grain there" % at)
    assert_true(spread.max() - spread.min() > TOOTH * 0.1, "and the grain varies from place to place")
    var normal := _texel(_easel.relief.texture, Vector2i(100, 17))
    assert_true(normal.b < 1.0, "so the surface the view lights is not flat")


func test_the_papers_height_at_one_place_holds_through_a_pan() -> void:
    _easel.shown_rect = func() -> Rect2: return Rect2(0, 0, 100, 100)
    var paper := _add_paper()
    var at := Vector2i(290, 280)
    var before := _texel(_easel.relief.heights, at).r
    assert_almost_eq(before, _grain(paper, at), NEAR, "Before the pan the height is the grain at its document position")
    var far := Vector2i(700, 700)
    assert_almost_eq(_texel(_easel.relief.heights, far).r, 0.0, 0.0001, "and a place the window misses waits")

    # A pan moves the window and nothing in the document, and the full
    # composite a pan's redraw may ask for resolves the paper again.
    _easel.shown_rect = func() -> Rect2: return Rect2(260, 250, 500, 500)
    _easel.request_full_composite()
    _easel.process_pending_composite()
    assert_almost_eq(_texel(_easel.relief.heights, at).r, before, 0.0001, "After the pan the same place stands as high")
    var reached := _texel(_easel.relief.heights, far).r
    assert_almost_eq(reached, _grain(paper, far), NEAR, "and the place the pan reached is its own grain")


func test_the_tooth_stands_whole_under_paint_of_any_height() -> void:
    var paper := _add_paper()
    var layer := _doc.active_layer
    var heights_by_chunk := [0.02, 1.0, -0.05]
    for chunk: int in heights_by_chunk.size():
        _raise(layer, Vector2i(chunk, 0), heights_by_chunk[chunk])
    _easel.process_pending_composite()
    var heights := _easel.relief.heights
    for chunk: int in heights_by_chunk.size():
        for x: int in [20, 90, 170]:
            var at := Vector2i(256 * chunk + x, 40)
            var mm: float = heights_by_chunk[chunk]
            assert_almost_eq(
                _texel(heights, at).r,
                mm + _grain(paper, at),
                NEAR,
                "Paint %.2f mm high at x %d has the whole tooth under it" % [mm, at.x]
            )


func test_a_hidden_paper_or_one_with_no_tooth_lends_nothing() -> void:
    var paper := _add_paper()
    assert_not_null(_easel.relief.texture, "The paper's tooth allocates the relief")
    var at := Vector2i(100, 17)
    SaLayerOps.new(_doc).set_visible(paper, false)
    _easel.process_pending_composite()
    assert_almost_eq(_texel(_easel.relief.heights, at).r, 0.0, 0.0001, "A hidden paper lends no height")
    SaLayerOps.new(_doc).set_visible(paper, true)
    _easel.process_pending_composite()
    assert_almost_eq(_texel(_easel.relief.heights, at).r, _grain(paper, at), NEAR, "and shown again it does")

    SaGeneratedLayer.set_tooth(_doc, paper, 0.0)
    _doc.update_caches()
    _easel.process_pending_composite()
    assert_almost_eq(_texel(_easel.relief.heights, at).r, 0.0, 0.0001, "A tooth of nought is a flat paper")
    SaCompute.reset_counters()
    _doc.invalidate_all_allocated_chunks()
    _easel.request_full_composite()
    _easel.process_pending_composite()
    assert_false(SaCompute.kernel_counters().has("paper/raise_tooth"), "which costs no dispatch after it is flat")


func test_a_paper_with_no_tooth_allocates_nothing() -> void:
    var paper := SaLayerOps.new(_doc).add(&"paper", _registries.layer_types)
    SaGeneratedLayer.set_tooth(_doc, paper, 0.0)
    _easel.request_full_composite()
    _easel.process_pending_composite()
    assert_null(_easel.relief.texture, "A flat paper and no paint height allocate no relief")


func test_the_tooth_is_one_undo_step_and_clamps() -> void:
    var paper := _add_paper()
    SaGeneratedLayer.set_tooth(_doc, paper, 0.3)
    SaGeneratedLayer.set_tooth(_doc, paper, 5.0)
    assert_almost_eq(SaGeneratedLayer.tooth_of(paper), SaGeneratedLayer.TOOTH_MAX, 0.0001, "The tooth stops at its most")
    _doc.undo()
    assert_almost_eq(SaGeneratedLayer.tooth_of(paper), TOOTH, 0.0001, "and a drag undoes in one step")
    var paint := _doc.active_layer
    SaGeneratedLayer.set_tooth(_doc, paint, 0.5)
    assert_false(paint.generator_params.has(SaGeneratedLayer.PARAM_TOOTH), "A layer that stores paint takes no tooth")
