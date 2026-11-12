## Threshold and the edge detection write grey in the document's own terms.
##
## Both kernels read the document's RGB view and wrote their grey back raw. On an
## RGB document that is the same thing, and on an Oklab one `vec3(1.0)` is L 1,
## a 1, b 1, which a painter sees as orange: a soft yellow stroke came out of
## Threshold as a pale core with an orange rim. Every texel the
## filter wrote is read back, turned into what the screen shows, and has to have
## three equal channels, with the alpha it had before.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const MODULE_ID := &"sara-base-modules"

## The pixel function the base module registers as Threshold.
const THRESHOLD := "res://modules/sara-base-modules/base/usual/threshold.gmacs"

const SIZE := Vector2i(256, 256)

## The four strokes of the sweep, each at an alpha of its own so that a soft edge
## is in every one of them, over a ground that is already grey. The last two
## overlap, so an edge runs between two colours as well as onto the ground. One
## chunk is enough, and every texel of it is read back.
const STROKES := [
    [Rect2i(20, 20, 60, 60), Color(1.0, 0.9, 0.1, 0.35)],
    [Rect2i(120, 20, 60, 60), Color(0.1, 0.8, 0.2, 0.7)],
    [Rect2i(20, 140, 60, 60), Color(0.9, 0.1, 0.1, 0.5)],
    [Rect2i(110, 130, 60, 60), Color(0.1, 0.2, 0.9, 1.0)],
]

const GROUND := Color(0.5, 0.5, 0.5, 1.0)

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
    for stroke: Array in STROKES:
        _doc.selection.select_rect(stroke[0])
        _layer.fill(_doc.color_space.from_display(stroke[1]))
        _doc.selection.deselect()


func _apply(filter: SaFilter) -> bool:
    var ctx := SaFilterContext.new(_doc, _layer, MODULE_ID, filter.title())
    if not SaFilterApply.call_run(filter, ctx):
        return false
    return SaFilterApply.apply(ctx, filter.title())


## Every texel of the layer, read back chunk by chunk, keyed by its position.
func _texels() -> Dictionary:
    var out := {}
    var rd := GlobalShaderCompiler.get_rd()
    for grid: Vector2i in _layer.chunks.keys():
        var texture := _layer.get_field(grid)
        var bytes := rd.texture_get_data(texture.rid, 0)
        for y in texture.size.y:
            for x in texture.size.x:
                var at := grid * texture.size + Vector2i(x, y)
                out[at] = SaFieldSpec.decode_texel(bytes, texture.format, y * texture.size.x + x)
    return out


## How many texels show a colour rather than a grey, and how many lost the alpha
## they had, with the first of each named for the failure's message.
func _assert_grey(before: Dictionary, after: Dictionary, two_tones: bool, what: String) -> void:
    var tinted := 0
    var not_two := 0
    var moved := 0
    var first := ""
    for at: Vector2i in after:
        var shown: Color = _doc.color_space.to_display(after[at])
        var spread := maxf(absf(shown.r - shown.g), maxf(absf(shown.g - shown.b), absf(shown.r - shown.b)))
        if spread > 2e-3:
            tinted += 1
            if first.is_empty():
                first = "%s shows %s" % [at, shown]
        if two_tones and minf(absf(shown.r), absf(shown.r - 1.0)) > 2e-3:
            not_two += 1
        if absf(after[at].a - before[at].a) > 1e-4:
            moved += 1
    assert_true(after.size() > 0, "%s reads texels back" % what)
    assert_eq(tinted, 0, "%s writes grey in every texel %s" % [what, first])
    if two_tones:
        assert_eq(not_two, 0, "%s writes only black or white" % what)
    assert_eq(moved, 0, "%s keeps every texel's alpha" % what)


func _threshold() -> SaFilter:
    var filter := SaPixelFilter.new(THRESHOLD, "Threshold", 0, &"tone")
    filter.set_parameters({"level": 0.5})
    return filter


func _edges() -> SaFilter:
    var filter := SaEdgeDetectionFilter.new()
    filter.set_parameters({"strength": 1.0})
    return filter


func test_threshold_on_an_oklab_document_gives_black_and_white() -> void:
    _open(SaColorSpace.oklab())
    var before := _texels()
    assert_true(_apply(_threshold()), "The threshold runs")
    _assert_grey(before, _texels(), true, "Threshold on Oklab")


func test_threshold_on_an_rgb_document_gives_black_and_white() -> void:
    _open(SaColorSpace.srgb())
    var before := _texels()
    assert_true(_apply(_threshold()), "The threshold runs")
    _assert_grey(before, _texels(), true, "Threshold on sRGB")


func test_edge_detection_on_an_oklab_document_writes_a_grey_magnitude() -> void:
    _open(SaColorSpace.oklab())
    var before := _texels()
    assert_true(_apply(_edges()), "The edge detection runs")
    _assert_grey(before, _texels(), false, "Edge detection on Oklab")


func test_edge_detection_on_an_rgb_document_writes_a_grey_magnitude() -> void:
    _open(SaColorSpace.srgb())
    var before := _texels()
    assert_true(_apply(_edges()), "The edge detection runs")
    _assert_grey(before, _texels(), false, "Edge detection on sRGB")
