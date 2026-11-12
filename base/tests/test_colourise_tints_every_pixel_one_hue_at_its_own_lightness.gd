## Hue/Saturation/Lightness's Colourise check throws a
## pixel's own hue away and gives it the one hue and chroma asked for, keeping
## its L and its alpha.
##
## Run over a grey ramp, which has no hue to keep, and over a painted red,
## whose hue is not the one asked, and read in Oklab pixel by pixel. With the
## check off the pass must read what it read before the check existed, which a
## record with no `colorize` key at all is.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

## The absolute hue asked for, in degrees, a blue-green well away from red's 29.
const ASKED_HUE := 200.0
## Half of `SaPointAdjust.COLORIZE_CHROMA`.
const ASKED_SATURATION := 0.5
## The grey ramp is one grey a chunk, darkest first, over a canvas of eight.
const CHUNKS := Vector2i(4, 2)

var _easel: SaEasel = null
var _doc: SaDocument = null
var _engine: SaPointAdjust = null
var _side := 0


func before_each() -> void:
    _easel = SaEasel.create_default(Vector2i(1024, 512))
    _doc = _easel.document
    _engine = SaPointAdjust.new()
    _side = _doc.active_layer.get_or_create_chunk(Vector2i.ZERO).pixel_size()


func after_each() -> void:
    _engine = null
    _easel.free()
    _easel = null
    _doc = null


func _apply(values: Dictionary) -> bool:
    return _engine.apply(_doc, _doc.active_layer, SaPointAdjust.HUE_SATURATION_LIGHTNESS, values, "Hue/Saturation/Lightness")


func _colorize(lightness: float = 0.0) -> bool:
    return _apply({"hue": ASKED_HUE, "saturation": ASKED_SATURATION, "lightness": lightness, "colorize": true})


## Eight greys from a stored 0.05 to 0.95, one a chunk, the last three half
## transparent so the alpha is read too. Answers a pixel inside each.
func _paint_ramp() -> Array[Vector2i]:
    var probes: Array[Vector2i] = []
    var count := CHUNKS.x * CHUNKS.y
    for i in count:
        @warning_ignore("integer_division")
        var grid := Vector2i(i % CHUNKS.x, i / CHUNKS.x)
        var value := 0.05 + 0.9 * float(i) / float(count - 1)
        _doc.active_layer.get_or_create_chunk(grid).clear(Color(value, value, value, 1.0 if i < count - 3 else 0.5))
        @warning_ignore("integer_division")
        probes.append(grid * _side + Vector2i(_side / 3, _side / 2))
    var grids: Array[Vector2i] = []
    for at: Vector2i in probes:
        grids.append(Vector2i(floori(float(at.x) / _side), floori(float(at.y) / _side)))
    _doc.invalidate_chunks(grids)
    return probes


## The active layer's stored texel at *at*, a canvas pixel.
func _texel(at: Vector2i) -> Color:
    var grid := Vector2i(floori(float(at.x) / _side), floori(float(at.y) / _side))
    var texture := _doc.active_layer.get_field(grid)
    if texture == null:
        return Color.TRANSPARENT
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    var inside := at - grid * _side
    return SaFieldSpec.decode_texel(bytes, texture.format, inside.y * texture.size.x + inside.x)


## *stored* in Oklab, through the document's own space.
func _oklab(stored: Color) -> Vector3:
    var space := _doc.color_space
    if space.coordinates == SaColorSpace.Coordinates.OKLAB:
        return Vector3(stored.r, stored.g, stored.b)
    var linear := Vector3(stored.r, stored.g, stored.b)
    if not space.is_linear():
        linear = Vector3(space.transfer.decode(stored.r), space.transfer.decode(stored.g), space.transfer.decode(stored.b))
    return OkhsvConversions.linear_srgb_to_oklab(space.to_linear_srgb_matrix() * linear)


static func _hue_degrees(lab: Vector3) -> float:
    return fposmod(rad_to_deg(atan2(lab.z, lab.y)), 360.0)


## How far apart two hues are around the circle, in degrees.
static func _hue_apart(a: float, b: float) -> float:
    var apart := fposmod(a - b, 360.0)
    return minf(apart, 360.0 - apart)


## Every probe of *before* read again: the asked hue, the asked chroma, and the
## L and alpha it had.
func _assert_tinted(probes: Array[Vector2i], before: Dictionary, what: String) -> void:
    var chroma := ASKED_SATURATION * SaPointAdjust.COLORIZE_CHROMA
    for at: Vector2i in probes:
        var was: Color = before[at]
        var now := _texel(at)
        var lab_was := _oklab(was)
        var lab_now := _oklab(now)
        assert_true(
            _hue_apart(_hue_degrees(lab_now), ASKED_HUE) < 1.0,
            "%s at %s takes the hue asked, %.2f" % [what, at, _hue_degrees(lab_now)]
        )
        assert_almost_eq(Vector2(lab_now.y, lab_now.z).length(), chroma, 3e-3, "%s at %s takes the chroma asked" % [what, at])
        assert_almost_eq(lab_now.x, lab_was.x, 3e-3, "%s at %s keeps its L" % [what, at])
        assert_almost_eq(now.a, was.a, 1e-3, "%s at %s keeps its alpha" % [what, at])


func _read(probes: Array[Vector2i]) -> Dictionary:
    var read := {}
    for at: Vector2i in probes:
        read[at] = _texel(at)
    return read


func test_a_grey_ramp_takes_the_one_hue_at_every_lightness() -> void:
    var probes := _paint_ramp()
    var before := _read(probes)
    assert_true(_colorize(), "Colourise applies")
    _assert_tinted(probes, before, "The grey")


func test_a_painted_red_loses_its_hue_for_the_one_asked() -> void:
    _doc.active_layer.fill(Color(1.0, 0.0, 0.0, 1.0))
    var probes: Array[Vector2i] = [Vector2i(10, 10), Vector2i(300, 40), Vector2i(128, 500)]
    var before := _read(probes)
    var red_chroma := Vector2(_oklab(before[probes[0]]).y, _oklab(before[probes[0]]).z).length()
    assert_true(red_chroma > 0.2, "Red has a hue to lose")
    assert_true(_hue_apart(_hue_degrees(_oklab(before[probes[0]])), ASKED_HUE) > 90.0, "far from the one asked")
    assert_true(_colorize(), "Colourise applies")
    _assert_tinted(probes, before, "The red")


func test_lightness_keeps_its_meaning_under_colourise() -> void:
    _doc.active_layer.fill(Color(0.5, 0.5, 0.5, 1.0))
    var was := _oklab(_texel(Vector2i(10, 10)))
    assert_true(_colorize(0.1), "Colourise with a lift applies")
    var now := _oklab(_texel(Vector2i(10, 10)))
    assert_almost_eq(now.x, was.x + 0.1, 3e-3, "The lightness slider still adds to L")
    assert_true(_hue_apart(_hue_degrees(now), ASKED_HUE) < 1.0, "and the hue is the one asked")


## Off is the pass the dialog ran before the check: the same values with
## `colorize` false and with no `colorize` at all read the same texels, over
## the greys and over a painted red.
func test_with_colourise_off_the_pass_reads_as_before() -> void:
    var probes := _paint_ramp()
    var red := Vector2i(2, 1)
    _doc.active_layer.get_or_create_chunk(red).clear(Color(0.8, 0.2, 0.1, 1.0))
    probes.append(red * _side + Vector2i(7, 9))
    var turn := {"hue": 40.0, "saturation": 1.3, "lightness": 0.05}
    assert_true(_apply(turn), "The turn without the key applies")
    var without := _read(probes)
    _doc.undo_redo.undo()
    var off := turn.duplicate()
    off["colorize"] = false
    assert_true(_apply(off), "and with the key off")
    for at: Vector2i in probes:
        assert_eq(_texel(at), without[at], "%s reads the same with Colourise off" % at)
