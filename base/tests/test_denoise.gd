## Denoise, Gaussian and mean. The filter is attached to a layer of one painted
## chunk, and the chain's answer for that chunk is read where the picture says
## something: a flat field, a lone bright texel, a hard edge and a stroke's edge
## against transparency. The attached form and the one-shot run the same pass
## (`SaNeighbourhoodPass.Runner`), so this reads both.
extends "res://tests/test_framework.gd"

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")
const DenoiseFilter = preload("res://modules/sara-base-modules/base/usual/denoise_filter.gd")

const REQUIRES_GPU := true

const OWNER := &"sara-base-modules"
const MODULE_DIR := "res://modules/sara-base-modules"
const GREY := Color(0.5, 0.5, 0.5, 1.0)
const CENTRE := Vector2i(128, 128)

var _easel: SaEasel = null
var _layer: SaLayer = null
var _key: StringName = &""
var _dir_was_set: bool = false


func before_each() -> void:
    _dir_was_set = ModuleLoader.module_dirs.has(OWNER)
    if not _dir_was_set:
        ModuleLoader.module_dirs[OWNER] = MODULE_DIR
    _easel = Bench.easel(Vector2i(SaChunk.SIZE, SaChunk.SIZE))
    var filter := DenoiseFilter.new()
    _easel.compositor.filter_chain.registry.register(filter, OWNER)
    _key = SaFilterRegistry.key_for(OWNER, filter)
    _layer = _easel.document.get_node("Background") as SaLayer


func after_each() -> void:
    _layer = null
    _easel.free()
    _easel = null
    if not _dir_was_set:
        ModuleLoader.module_dirs.erase(OWNER)


## Paints *image* into the layer's one chunk, attaches the denoise with
## *params* and answers the chain's reading of the chunk.
func _denoised(image: Image, params: Dictionary) -> Image:
    for grid_pos: Vector2i in _layer.chunks.keys():
        _layer.chunks.erase(grid_pos)
    var chunk := _layer.get_or_create_chunk(Vector2i.ZERO)
    GlobalShaderCompiler.get_rd().texture_update(chunk.field(SaFieldSpec.ALBEDO).rid, 0, image.get_data())
    for record: SaAttachedFilter in _layer.filters.duplicate():
        SaFilterOps.new(_easel.document).detach(_layer, record)
    SaFilterOps.new(_easel.document).attach(_layer, _key, params)
    Bench.composite(_easel)
    var answer := _easel.compositor.filter_chain.filtered(
        _layer, _layer.get_field(Vector2i.ZERO), Vector2i.ZERO, SaDocument.WHOLE_CHUNK
    )
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(answer.rid, 0)
    return Image.create_from_data(SaChunk.SIZE, SaChunk.SIZE, false, Image.FORMAT_RGBAF, bytes)


func _field(colour: Color) -> Image:
    var image := Image.create(SaChunk.SIZE, SaChunk.SIZE, false, Image.FORMAT_RGBAF)
    image.fill(colour)
    return image


func _distance(a: Color, b: Color) -> float:
    return maxf(maxf(absf(a.r - b.r), absf(a.g - b.g)), maxf(absf(a.b - b.b), absf(a.a - b.a)))


func test_the_filter_answers_the_numbers_it_was_handed() -> void:
    var denoise := DenoiseFilter.new()
    assert_eq(
        denoise.parameters(), {"kind": "gaussian", "radius": 3.0, "threshold": 10.0}, "With no dialog it answers its defaults"
    )
    denoise.set_parameters({"kind": "mean", "radius": 7, "threshold": 40})
    assert_eq(denoise.parameters(), {"kind": "mean", "radius": 7.0, "threshold": 40.0}, "and what it was handed")
    denoise.set_parameters({"kind": "median"})
    assert_eq(denoise.parameters()["kind"], "gaussian", "A kind it does not know reads as the default")


## A record's numbers reach the rows a dialog built, and through them the control
## each row draws, which is what a painter reads the number off. The order is the
## panel's and the editor's: `build`, then `set_parameters`, then the page is
## realized.
func test_a_records_numbers_reach_the_rows_and_their_controls() -> void:
    var denoise := DenoiseFilter.new()
    var dialog := SaDialog.for_filter(denoise)
    var host := VBoxContainer.new()
    denoise.set_parameters({"kind": "mean", "radius": 7, "threshold": 40})
    dialog.realize(host)

    assert_eq(String(dialog.row(&"kind").read()), "mean", "The record's kind is on the row")
    var radius := dialog.row(&"radius")
    assert_eq(float(radius.read()), 7.0, "The record's radius is on the row")
    assert_eq((radius.custom_control as FactorSlider).value, 7.0, "and on the control it built")
    var threshold := dialog.row(&"threshold")
    assert_eq(float(threshold.read()), 40.0, "The record's threshold is on the row")
    assert_eq((threshold.custom_control as FactorSlider).value, 40.0, "and on the control it built")
    host.free()


func test_a_flat_region_is_unchanged_by_either_kind_at_any_radius() -> void:
    for kind: String in DenoiseFilter.KINDS:
        for radius: int in [1, 4, 12]:
            var out := _denoised(_field(GREY), {"kind": kind, "radius": radius, "threshold": 100})
            var got := out.get_pixelv(CENTRE)
            assert_true(_distance(got, GREY) < 1e-5, "%s at radius %d leaves flat grey grey, %s" % [kind, radius, got])


## The page's clause said Gaussian pulls further than Mean at the same radius.
## It is the other way round: a Gaussian of sigma `radius / 2` gives the centre
## texel about a fourteenth of the weight at radius 3 where Mean gives it a
## forty-ninth, so Mean pulls the lone texel further and Gaussian keeps more of
## it. Both pull it towards the field, which is the clause's point.
func test_a_lone_bright_texel_is_pulled_towards_the_field() -> void:
    var image := _field(GREY)
    image.set_pixelv(CENTRE, Color(0.7, 0.7, 0.7, 1.0))
    var pulled := {}
    for kind: String in DenoiseFilter.KINDS:
        var got := _denoised(image, {"kind": kind, "radius": 3, "threshold": 100}).get_pixelv(CENTRE)
        pulled[kind] = 0.7 - got.r
        assert_true(got.r < 0.7 - 0.01 and got.r > 0.5 - 1e-5, "%s pulls the bright texel towards grey, %s" % [kind, got])
    assert_true(pulled["mean"] > pulled["gaussian"] + 0.005, "and Mean pulls it further than Gaussian, %s" % [pulled])
    var kept := _denoised(image, {"kind": "mean", "radius": 3, "threshold": 0}).get_pixelv(CENTRE)
    assert_true(_distance(kept, Color(0.7, 0.7, 0.7, 1.0)) < 1e-5, "A threshold of zero smooths nothing, %s" % kept)


func test_a_hard_edge_above_the_threshold_keeps_both_sides() -> void:
    var image := _field(Color(0.0, 0.0, 0.0, 1.0))
    image.fill_rect(Rect2i(0, 0, CENTRE.x, SaChunk.SIZE), Color(1.0, 1.0, 1.0, 1.0))
    for kind: String in DenoiseFilter.KINDS:
        var out := _denoised(image, {"kind": kind, "radius": 3, "threshold": 10})
        for x in range(CENTRE.x - 5, CENTRE.x + 5):
            var want := Color(1.0, 1.0, 1.0, 1.0) if x < CENTRE.x else Color(0.0, 0.0, 0.0, 1.0)
            var got := out.get_pixel(x, CENTRE.y)
            assert_true(_distance(got, want) < 1e-3, "%s keeps the edge at x %d, %s" % [kind, x, got])


func test_a_stroke_edge_keeps_its_colour_and_loses_alpha() -> void:
    # Opaque red to the left, and to the right texels that are transparent but
    # store green, which a sum of straight colours would pull into the red.
    var image := _field(Color(0.0, 1.0, 0.0, 0.0))
    image.fill_rect(Rect2i(0, 0, CENTRE.x, SaChunk.SIZE), Color(1.0, 0.0, 0.0, 1.0))
    for kind: String in DenoiseFilter.KINDS:
        var got := _denoised(image, {"kind": kind, "radius": 3, "threshold": 100}).get_pixel(CENTRE.x - 1, CENTRE.y)
        assert_true(got.a < 0.95 and got.a > 0.3, "%s pulls the edge's alpha towards empty, %s" % [kind, got])
        assert_almost_eq(got.r, 1.0, 1e-4, "%s keeps the stroke red, %s" % [kind, got])
        assert_almost_eq(got.g, 0.0, 1e-4, "with no green from the empty texels, %s" % got)
