## The height to normal map stores the normal as the colour it shows.
##
## The kernel handed the encoded vector to the document raw. On an RGB document
## that is the colour itself, and on an Oklab one (0.5, 0.5, 1.0) is L 0.5,
## a 0.5, b 1.0, which a painter saw as orange while an engine wanted the lilac
## of a flat normal. The filter is applied to a grey ground with
## a lighter square on it, on both kinds of document, and what the screen shows
## is read back: the lilac on the flat ground, and a red above half on the
## square's right edge, where the height falls away to the right.
##
## The lilac is the eight bit one, 128, 128, 255, and not half and half. An
## encoded half is 127.5 of 255, exactly between two counts, and the Oklab
## round trip landed the green just under it, so an export read 128, 127, 255
## and a game engine saw the flat surface lean by a count. The
## tolerance is a fortieth of a count, tight enough to tell 128 of 255 from
## 127.5, and the eight bit read of each channel is checked beside it.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const MODULE_ID := &"sara-base-modules"

const SIZE := Vector2i(256, 256)

const GROUND := Color(0.3, 0.3, 0.3, 1.0)
const SQUARE := Rect2i(96, 96, 64, 64)
const RAISED := Color(0.7, 0.7, 0.7, 1.0)

## A texel of the ground well away from the square and the chunk's edge, and
## the last column of the square, whose right neighbour is the lower ground.
const FLAT := Vector2i(40, 40)
const SLOPE := Vector2i(159, 128)

## The flat normal, +Z, encoded the eight bit way where zero is 128 of 255:
## what a painter sees and what an engine reads.
const LILAC := Color(128.0 / 255.0, 128.0 / 255.0, 1.0, 1.0)

## A fortieth of an eight bit count.
const COUNT_TOLERANCE := 1e-4

var _easel: SaEasel = null
var _doc: SaDocument = null
var _layer: SaLayer = null


func after_each() -> void:
    if _easel != null:
        _easel.free()
    _easel = null
    _doc = null
    _layer = null


func _open(space: SaColorSpace) -> void:
    _easel = SaEasel.create_default(SIZE, null, space)
    _doc = _easel.document
    _layer = _doc.active_layer
    _layer.fill(_doc.color_space.from_display(GROUND))
    _doc.selection.select_rect(SQUARE)
    _layer.fill(_doc.color_space.from_display(RAISED))
    _doc.selection.deselect()


func _apply() -> bool:
    var filter := SaNormalMapFilter.new()
    filter.set_parameters({"strength": SaNormalMapFilter.DEFAULT_STRENGTH, "flip": false})
    var ctx := SaFilterContext.new(_doc, _layer, MODULE_ID, filter.title())
    if not SaFilterApply.call_run(filter, ctx):
        return false
    return SaFilterApply.apply(ctx, filter.title())


## What the screen shows at *at*, a pixel of the one chunk.
func _shown(at: Vector2i) -> Color:
    var texture := _layer.get_field(Vector2i.ZERO)
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    return _doc.color_space.to_display(SaFieldSpec.decode_texel(bytes, texture.format, at.y * texture.size.x + at.x))


func _assert_shows_the_normal(what: String) -> void:
    assert_true(_apply(), "%s: the normal map runs" % what)
    var flat := _shown(FLAT)
    assert_almost_eq(flat.r, LILAC.r, COUNT_TOLERANCE, "%s shows a flat texel's red as 128 of 255: %s" % [what, flat])
    assert_almost_eq(flat.g, LILAC.g, COUNT_TOLERANCE, "%s shows its green as 128 of 255: %s" % [what, flat])
    assert_almost_eq(flat.b, LILAC.b, COUNT_TOLERANCE, "%s shows its blue full: %s" % [what, flat])
    assert_eq([flat.r8, flat.g8, flat.b8], [128, 128, 255], "%s reads 128, 128, 255 in eight bits: %s" % [what, flat])
    assert_almost_eq(flat.a, 1.0, 1e-4, "%s keeps the texel's alpha: %s" % [what, flat])
    var slope := _shown(SLOPE)
    assert_true(slope.r > 0.55, "%s tints the falling edge red: %s" % [what, slope])
    assert_almost_eq(slope.g, LILAC.g, COUNT_TOLERANCE, "%s leaves the edge's green at the middle: %s" % [what, slope])


func test_an_oklab_document_shows_the_lilac_of_a_flat_normal() -> void:
    _open(SaColorSpace.oklab())
    _assert_shows_the_normal("Oklab")


func test_an_rgb_document_shows_the_lilac_of_a_flat_normal() -> void:
    _open(SaColorSpace.srgb())
    _assert_shows_the_normal("sRGB")


func test_the_sentence_says_the_normal_is_stored_as_its_colour() -> void:
    assert_true(
        SaNormalMapFilter.new().sentence().contains("stored as the colour it shows"),
        "The filter's own line tells a painter what the canvas holds"
    )
