## Edge Detection, the Sobel, through the neighbourhood pass its own `run`
## records.
##
## Nothing in the tree computed a Sobel before this, so the suite is written
## against the arithmetic the row specifies rather than against an earlier
## behaviour: nine reads over the luminance of the document's RGB view, a
## magnitude of sqrt(gx*gx + gy*gy), and the strength as its factor.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const MODULE_ID := &"sara-base-modules"

const DARK := Color(0.1, 0.1, 0.1, 1.0)
const BRIGHT := Color(0.9, 0.9, 0.9, 1.0)

## The column the picture changes at, and two rows well inside one chunk's
## height so the horizontal gradient is zero where the vertical one is read.
const EDGE_X := 128
const ROW := 300

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


## A vertical edge down the canvas: dark to its left and bright to its right,
## so gx is the only gradient there is and its magnitude is known on paper.
func _vertical_edge() -> void:
    _layer.fill(DARK)
    _doc.selection.select_rect(Rect2i(EDGE_X, 0, 512 - EDGE_X, 512))
    _layer.fill(BRIGHT)
    _doc.selection.deselect()


## Runs the filter's own `run` into a context and applies what it recorded.
func _apply(strength: float) -> bool:
    var filter := SaEdgeDetectionFilter.new()
    filter.set_parameters({"strength": strength})
    var ctx := SaFilterContext.new(_doc, _layer, MODULE_ID, filter.title())
    if not SaFilterApply.call_run(filter, ctx):
        return false
    return SaFilterApply.apply(ctx, filter.title())


## The pass the filter records, without applying it.
func _record(strength: float) -> SaNeighbourhoodPass:
    var filter := SaEdgeDetectionFilter.new()
    filter.set_parameters({"strength": strength})
    var ctx := SaFilterContext.new(_doc, _layer, MODULE_ID, filter.title())
    SaFilterApply.call_run(filter, ctx)
    return ctx.point as SaNeighbourhoodPass


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


## The magnitude the suite expects on the edge: the right column at 1, 2, 1
## against the left column at -1, -2, -1, over a difference of 0.8.
const EDGE_MAGNITUDE := (1.0 + 2.0 + 1.0) * (BRIGHT.r - DARK.r)


func test_the_edge_carries_a_magnitude_and_the_flat_sides_carry_none() -> void:
    _vertical_edge()

    assert_true(_apply(1.0), "The Sobel runs")

    var on_the_edge := _texel(EDGE_X, ROW)
    assert_almost_eq(on_the_edge.r, EDGE_MAGNITUDE, 1e-3, "The bright side of the edge carries the magnitude")
    assert_almost_eq(on_the_edge.g, EDGE_MAGNITUDE, 1e-3, "in every channel, as a grey map")
    assert_almost_eq(on_the_edge.a, 1.0, 1e-3, "and keeps the source's alpha")
    assert_almost_eq(_texel(EDGE_X - 1, ROW).r, EDGE_MAGNITUDE, 1e-3, "and so does the dark side, a magnitude having no sign")
    assert_almost_eq(_texel(EDGE_X - 20, ROW).r, 0.0, 1e-4, "Twenty texels into the dark side there is no edge")
    assert_almost_eq(_texel(EDGE_X + 20, ROW).r, 0.0, 1e-4, "nor twenty into the bright one")


## The strength is a factor on the magnitude, and nothing clamps: at twice the
## strength the answer is twice as large rather than pinned at one.
func test_the_strength_doubles_the_magnitude_and_does_not_clamp() -> void:
    _vertical_edge()
    assert_true(_apply(1.0), "The Sobel runs at strength 1")
    var once := _texel(EDGE_X, ROW).r

    assert_true(_doc.undo(), "which undoes")

    assert_true(_apply(2.0), "and again at strength 2")
    var twice := _texel(EDGE_X, ROW).r

    assert_almost_eq(twice, once * 2.0, 1e-3, "Twice the strength, twice the magnitude")
    assert_true(twice > 1.0, "which is above one, where a clamping kernel would have stopped")


## It records a neighbourhood pass and not a point one, with the radius of one
## texel the row declares to the neighbourhood pass, which is what grows the
## dispatch by a halo.
func test_it_records_a_neighbourhood_pass_with_a_radius_of_one() -> void:
    _vertical_edge()

    var recorded := _record(1.0)

    assert_not_null(recorded, "The run records a pass")
    assert_eq(recorded.radius, SaEdgeDetectionFilter.RADIUS, "of the radius the filter declares")
    assert_eq(recorded.radius, 1, "which is one texel either side of the one it writes")
    assert_eq(recorded.kernel, "edge_detection", "and calls the kernel of its own file")
    assert_eq(recorded.shader, "sara-base-modules/edge_detection", "filed under the module's folder")


func test_the_strength_survives_a_record_and_a_reload() -> void:
    var filter := SaEdgeDetectionFilter.new()

    filter.set_parameters({"strength": 2.5})
    assert_eq(filter.parameters().get("strength"), 2.5, "What went in comes back out")
    filter.set_parameters({})
    assert_eq(
        filter.parameters().get("strength"),
        SaEdgeDetectionFilter.DEFAULT_STRENGTH,
        "A record that names nothing leaves the default rather than the value before it"
    )
