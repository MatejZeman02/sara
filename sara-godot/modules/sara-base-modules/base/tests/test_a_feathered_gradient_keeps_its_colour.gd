## A gradient laid inside a feathered selection keeps its colour to the edge.
##
## A fog band laid as two ramps inside
## feathered selections: where the second ramp crossed the first one's
## feathered edge the fog went 2.5 L* darker than above and below it, and a
## white ramp over white paper dipped to 192 of 255 along its feather. It is
## the dark ring `test_fill_feather_edge.gd` holds the fill to, in the
## gradient's own kernel, which mixed the ramp and the layer channel by channel
## with straight alpha, so over a transparent texel the colour fell with the
## coverage as the alpha did and the edge composited as coverage squared.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

const REQUIRES_GPU := true

## The selection's right edge and the feather each way from it, both inside the
## first chunk.
const EDGE: int = 128
const FEATHER: int = 20

## What lies under the ramp where a test puts something there, and the ramp's
## one colour, so any change along the edge is the feather's and not the ramp's.
const BACKDROP := Color(0.5, 0.5, 0.5, 1.0)
const RAMP := Color(0.0, 0.6, 0.0, 1.0)

const EPSILON := 0.002

var _easel: SaEasel = null
var _doc: SaDocument = null


func before_each() -> void:
    _easel = SaEasel.create_default(Vector2i(512, 512))
    _doc = _easel.document


func after_each() -> void:
    _easel.free()
    _easel = null
    _doc = null


## A rectangle feathered so its right edge is a ramp of coverage, then one flat
## ramp of RAMP across it.
func _lay_feathered() -> void:
    _doc.selection.select_rect(Rect2i(0, 0, EDGE, 512))
    SaSelectionFilters.feather(_doc.selection, FEATHER, _doc.canvas_size)
    SaGradient.new(_doc).apply(
        _doc.active_layer,
        Vector2(0.5, 100.0),
        Vector2(511.5, 100.0),
        SaColorRamp.from_pair(RAMP, RAMP),
        SaGradient.Shape.LINEAR,
        SaGradient.Repeat.NONE,
        false
    )


## Row 100 of the active layer across the feathered edge.
func _row() -> Array[Color]:
    var texture := _doc.active_layer.get_field(Vector2i.ZERO)
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    var out: Array[Color] = []
    for x in range(EDGE - FEATHER - 4, EDGE + FEATHER + 4):
        out.append(SaFieldSpec.decode_texel(bytes, texture.format, 100 * texture.size.x + x))
    return out


## The texel put over the opaque backdrop the way the compositor does.
func _over_backdrop(texel: Color) -> float:
    return texel.g * texel.a + BACKDROP.g * (1.0 - texel.a)


func test_a_feathered_ramp_on_an_empty_layer_keeps_its_colour() -> void:
    _lay_feathered()
    var covered := 0
    for texel in _row():
        if texel.a > EPSILON:
            covered += 1
            assert_almost_eq(texel.g, RAMP.g, EPSILON, "every covered texel is the ramp's colour, the feather is alpha")
    assert_true(covered > FEATHER, "and the row crosses the feather")


## The symptom as the painter saw it: over a backdrop, the edge goes from the
## ramp down to the darker backdrop and never dips and rises again.
func test_the_edge_over_a_backdrop_is_monotone() -> void:
    _lay_feathered()
    var row := _row()
    for i in range(1, row.size()):
        assert_true(
            _over_backdrop(row[i]) <= _over_backdrop(row[i - 1]) + EPSILON,
            "texel %d does not rise again on the way out of the selection" % i
        )
    assert_almost_eq(_over_backdrop(row[0]), RAMP.g, EPSILON, "the inside end is the ramp")
    assert_almost_eq(_over_backdrop(row[row.size() - 1]), BACKDROP.g, EPSILON, "and the outside end is the backdrop")


## Over paint that is already opaque the edge was never wrong, and the fix
## keeps it a plain mix of the two colours.
func test_over_opaque_paint_the_edge_still_mixes_the_two() -> void:
    _doc.active_layer.fill(BACKDROP)
    _lay_feathered()
    var row := _row()
    for texel in row:
        assert_almost_eq(texel.a, 1.0, EPSILON, "the layer stays opaque")
        assert_true(texel.g >= BACKDROP.g - EPSILON and texel.g <= RAMP.g + EPSILON, "and every texel is between the two")
    assert_almost_eq(row[0].g, RAMP.g, EPSILON, "the inside end is the ramp")
    assert_almost_eq(row[row.size() - 1].g, BACKDROP.g, EPSILON, "and the outside end is the backdrop")
