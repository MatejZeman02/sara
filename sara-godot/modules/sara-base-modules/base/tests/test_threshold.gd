## Threshold, through the pass its own `run` records.
##
## Read back texel by texel, because the kernel is arithmetic on stored values
## and the two things under test are that the level splits them and that alpha is
## never what it touches. The filter had shipped nowhere before this, so there is
## no earlier behaviour to keep: the arithmetic is the scripting guide's own
## example filter, promoted from a fixture into a filter of the base module.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

## The module the context is built under, so the shader index resolves
## `threshold` to the base module's own file.
const MODULE_ID := &"sara-base-modules"

## The pixel function the base module registers as Threshold, and the level its `uniform` declares.
const THRESHOLD := "res://modules/sara-base-modules/base/usual/threshold.gmacs"
const DEFAULT_LEVEL := 0.5

const DARK := Color(0.1, 0.1, 0.1, 1.0)
const BRIGHT := Color(0.9, 0.9, 0.9, 1.0)
const HALF := Color(0.9, 0.9, 0.9, 0.5)
const NOTHING := Color(0.0, 0.0, 0.0, 0.0)

## One texel of each square, all of them well inside one chunk.
const DARK_AT := Vector2i(110, 110)
const BRIGHT_AT := Vector2i(210, 210)
const HALF_AT := Vector2i(310, 310)
const CLEAR_AT := Vector2i(410, 410)

var _easel: SaEasel = null
var _doc: SaDocument = null
var _layer: SaLayer = null


func before_each() -> void:
    _easel = SaEasel.create_default(Vector2i(512, 512))
    _doc = _easel.document
    _layer = _doc.active_layer


func after_each() -> void:
    _easel.free()
    _easel = null
    _doc = null
    _layer = null


## An opaque canvas with one square under the level, one over it, one at half
## alpha and one transparent. Each square is written through a selection, and the
## canvas itself is filled first so the fill never walks a transparent one:
## `fill.gmacs` premultiplies, and over a destination whose alpha is zero the
## colour divides back out of nothing (`fill.gmacs:45-47`), so a masked fill over
## a transparent canvas would leave every texel it walked black.
func _four_squares() -> void:
    _layer.fill(BRIGHT)
    _paint(Rect2i(100, 100, 20, 20), DARK)
    _paint(Rect2i(200, 200, 20, 20), BRIGHT)
    _paint(Rect2i(300, 300, 20, 20), HALF)
    _paint(Rect2i(400, 400, 20, 20), NOTHING)


## One square written through a selection, which is the masked fill kernel.
func _paint(rect: Rect2i, color: Color) -> void:
    _doc.selection.select_rect(rect)
    _layer.fill(color)
    _doc.selection.deselect()


## Runs the filter's own `run` into a context and applies what it recorded, the
## way the dialog does. Answers whether pixels were written.
func _apply(level: float) -> bool:
    var filter := _threshold()
    filter.set_parameters({"level": level})
    var ctx := SaFilterContext.new(_doc, _layer, MODULE_ID, filter.title())
    if not SaFilterApply.call_run(filter, ctx):
        return false
    return SaFilterApply.apply(ctx, filter.title())


## Threshold as the base module registers it.
func _threshold() -> SaPixelFilter:
    return SaPixelFilter.new(THRESHOLD, "Threshold", 0, &"tone")


func _texel(x: int, y: int) -> Color:
    @warning_ignore("integer_division")
    var grid := Vector2i(x / SaChunk.SIZE, y / SaChunk.SIZE)
    var texture := _layer.get_field(grid)
    if texture == null:
        return Color.TRANSPARENT
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    return SaFieldSpec.decode_texel(
        bytes, texture.format, (y - grid.y * SaChunk.SIZE) * texture.size.x + (x - grid.x * SaChunk.SIZE)
    )


func test_a_texel_below_the_level_goes_black_and_one_above_it_white() -> void:
    _four_squares()

    assert_true(_apply(0.5), "The threshold runs")

    var below := _texel(DARK_AT.x, DARK_AT.y)
    assert_almost_eq(below.r, 0.0, 1e-4, "A texel below the level is black")
    assert_almost_eq(below.g, 0.0, 1e-4, "in every channel")
    assert_almost_eq(below.a, 1.0, 1e-4, "and keeps the alpha it had")
    var above := _texel(BRIGHT_AT.x, BRIGHT_AT.y)
    assert_almost_eq(above.r, 1.0, 1e-4, "A texel above the level is white")
    assert_almost_eq(above.b, 1.0, 1e-4, "in every channel")
    assert_almost_eq(above.a, 1.0, 1e-4, "and keeps the alpha it had")


## The level is a comparison and not a threshold on alpha: a texel at half alpha
## has its colour rewritten and its alpha left exactly where it was, and a fully
## transparent one stays transparent rather than being made opaque by the write.
func test_alpha_is_not_what_the_threshold_writes() -> void:
    _four_squares()
    assert_almost_eq(_texel(HALF_AT.x, HALF_AT.y).a, 0.5, 1e-4, "The half-alpha square starts at half")
    assert_almost_eq(_texel(CLEAR_AT.x, CLEAR_AT.y).a, 0.0, 1e-4, "and the transparent one at nothing")

    assert_true(_apply(0.5), "The threshold runs")

    var half := _texel(HALF_AT.x, HALF_AT.y)
    assert_almost_eq(half.r, 1.0, 1e-4, "The half-alpha texel is above the level, so its colour goes white")
    assert_almost_eq(half.a, 0.5, 1e-4, "and its alpha is exactly what it was")
    assert_almost_eq(_texel(CLEAR_AT.x, CLEAR_AT.y).a, 0.0, 1e-6, "The transparent texel is still transparent")


## A level of one is the honest reading of the slider's top: nothing is above it,
## so nothing is left white.
func test_a_level_of_one_leaves_nothing_white() -> void:
    _four_squares()

    assert_true(_apply(1.0), "The threshold runs")

    assert_almost_eq(_texel(BRIGHT_AT.x, BRIGHT_AT.y).r, 0.0, 1e-4, "A texel at the level is not above it")
    assert_almost_eq(_texel(DARK_AT.x, DARK_AT.y).r, 0.0, 1e-4, "nor is one below")


## The filter's records are what an attached threshold keeps, and the one
## instance the registry holds is handed a record before every run.
func test_the_level_survives_a_record_and_a_reload() -> void:
    var filter := _threshold()
    var ctx := SaFilterContext.new(_doc, _layer, MODULE_ID, filter.title())

    filter.set_parameters({"level": 0.25})
    assert_eq(filter.parameters().get("level"), 0.25, "What went in comes back out")
    filter.set_parameters({"level": 0.75})
    assert_eq(filter.parameters().get("level"), 0.75, "and the next record replaces it rather than merging")
    filter.set_parameters({})
    assert_eq(filter.parameters().get("level"), DEFAULT_LEVEL, "A record that names no level leaves the default")

    assert_true(SaFilterApply.call_run(filter, ctx), "and it still runs with no dialog ever built")
    assert_true(ctx.point is SaPointPass, "as a point pass, which is what a filter of one texel is")


## It registers through the door a stranger's filter uses, under the id its own
## title spells.
func test_it_registers_under_the_module_with_its_own_key() -> void:
    var filters := SaFilterRegistry.new()

    assert_true(filters.register(_threshold(), MODULE_ID), "Threshold registers")

    var key := SaFilterRegistry.key_for(MODULE_ID, _threshold())
    assert_true(filters.has(key), "keyed as %s" % key)
    assert_eq(String(key), "sara-base-modules.threshold", "the module's id and the title's own slug")
