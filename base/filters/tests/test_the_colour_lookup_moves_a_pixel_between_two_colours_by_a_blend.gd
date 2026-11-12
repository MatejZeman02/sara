## The Colour Lookup moves a pixel between two colours by a blend, not a jump.
##
## A note on a picture of three spheres: "It
## introduces a strong color banding." The `palette` kernel sent every pixel to
## the one colour with the least distance per unit of pull times influence, so
## the two pixels either side of the line where that colour changed went to
## two different colours, and at full bands a smooth ramp became flat areas
## with a hard edge between them. It now moves a pixel towards a blend of the
## colours, each weighed by its score against the least.
##
## The ramp runs from a dark red to a cream in a straight line in Oklab, one
## texel a step, so a texel's distances to the two colours are its place on
## the ramp and the far end's. Before the blend the largest step between two
## neighbours was the whole distance between the colours, 255 times the ramp's
## own step, and it is now held under `STEP_BOUND` times that step. The other
## two tests keep what the blend must not change: a pixel on a palette colour
## stays itself, and a palette of one colour moves a pixel as it always has.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

## The two ends of the ramp, the sphere's dark red and a cream. The straight
## Oklab line between them stays inside sRGB's gamut, so no texel of it is
## changed by the kernel's net for a negative channel.
const DARK_RED := Color("#5a1a14")
const CREAM := Color("#efe2c0")

## The largest step between neighbouring texels after the pass, as a multiple
## of the ramp's own step. The blend's share of the far colour is a square
## from a third of the score ratio to one, whose steepest slope is three
## times the ramp's at the line between the colours, so three and a little
## over is what the pass gives at full bands, and four leaves room for the
## float rounding of the read and no room for a jump, which is 255.
const STEP_BOUND := 4.0

## The float rounding a texel read back through the Oklab round trip keeps, at
## the F32 the document holds.
const EPSILON := 1e-4

var _easel: SaEasel = null
var _doc: SaDocument = null
var _engine: SaPointAdjust = null


func before_each() -> void:
    _engine = SaPointAdjust.new()
    _easel = SaEasel.create_default(Vector2i(SaChunk.SIZE, SaChunk.SIZE), null, SaColorSpace.srgb())
    _doc = _easel.document
    _doc.active_layer.fill(Color(0.5, 0.5, 0.5, 1.0))


func after_each() -> void:
    _engine = null
    if _easel != null:
        _easel.free()
    _easel = null
    _doc = null


static func _lab(color: Color) -> Vector3:
    return OkhsvConversions.linear_srgb_to_oklab(OkhsvConversions.srgb_transfer_function_inv(Vector3(color.r, color.g, color.b)))


static func _encoded(lab: Vector3) -> Color:
    var rgb := OkhsvConversions.srgb_transfer_function(OkhsvConversions.oklab_to_linear_srgb(lab))
    return Color(rgb.x, rgb.y, rgb.z, 1.0)


## The chunk's texels from its first, row by row, as many as *count*.
func _texels(count: int) -> Array[Color]:
    var texture := _doc.active_layer.get_field(Vector2i.ZERO)
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    var out: Array[Color] = []
    for i in count:
        out.append(SaFieldSpec.decode_texel(bytes, texture.format, i))
    return out


## Writes *colours* from the chunk's first texel on, row by row, at F32.
func _put(colours: Array[Color]) -> void:
    var texture := _doc.active_layer.get_field(Vector2i.ZERO)
    var rd := GlobalShaderCompiler.get_rd()
    var bytes := rd.texture_get_data(texture.rid, 0)
    for i in colours.size():
        for channel in 4:
            bytes.encode_float(i * 16 + channel * 4, colours[i][channel])
    rd.texture_update(texture.rid, 0, bytes)


## The ramp from dark red to cream across the chunk's first row.
func _ramp() -> Array[Color]:
    var from := _lab(DARK_RED)
    var to := _lab(CREAM)
    var out: Array[Color] = []
    for i in SaChunk.SIZE:
        out.append(_encoded(from.lerp(to, float(i) / float(SaChunk.SIZE - 1))))
    return out


## The largest Oklab distance between neighbouring texels of *row*.
static func _largest_step(row: Array[Color]) -> float:
    var largest := 0.0
    for i in range(1, row.size()):
        largest = maxf(largest, _lab(row[i]).distance_to(_lab(row[i - 1])))
    return largest


static func _near(a: Color, b: Color) -> bool:
    return absf(a.r - b.r) < EPSILON and absf(a.g - b.g) < EPSILON and absf(a.b - b.b) < EPSILON


func test_a_ramp_between_two_colours_passes_from_one_to_the_other_with_no_jump() -> void:
    var ramp_step := _lab(DARK_RED).distance_to(_lab(CREAM)) / float(SaChunk.SIZE - 1)
    for amount: float in [1.0, 0.5]:
        _put(_ramp())
        var values := {"palette": [DARK_RED, CREAM], "shadows": amount, "midtones": amount, "highlights": amount}
        assert_true(_engine.apply(_doc, _doc.active_layer, SaPointAdjust.PALETTE, values, "N10"), "the lookup ran")
        var row := _texels(SaChunk.SIZE)
        var ratio := _largest_step(row) / ramp_step
        print("at bands of %s the largest step is %.3f times the ramp's own" % [amount, ratio])
        assert_true(
            ratio <= STEP_BOUND,
            "at bands of %s no neighbouring texels are more than %s ramp steps apart, read %.3f" % [amount, STEP_BOUND, ratio]
        )
        _doc.undo()
    # At full bands the ends are flat at their colours over the quarter the
    # blend leaves alone, and the middle is halfway.
    _put(_ramp())
    var full := {"palette": [DARK_RED, CREAM], "shadows": 1.0, "midtones": 1.0, "highlights": 1.0}
    assert_true(_engine.apply(_doc, _doc.active_layer, SaPointAdjust.PALETTE, full, "N10"), "the lookup ran")
    var applied := _texels(SaChunk.SIZE)
    for i: int in [0, 30, 60]:
        var red_said := "texel %d, inside the dark red's side, is the dark red, read %s" % [i, applied[i]]
        assert_true(_near(applied[i], DARK_RED), red_said)
        var mirror := SaChunk.SIZE - 1 - i
        var cream_said := "texel %d, inside the cream's side, is the cream, read %s" % [mirror, applied[mirror]]
        assert_true(_near(applied[mirror], CREAM), cream_said)
    var half := SaChunk.SIZE >> 1
    var middle := _lab(applied[half - 1]).lerp(_lab(applied[half]), 0.5)
    var halfway := _lab(DARK_RED).lerp(_lab(CREAM), 0.5)
    assert_true(middle.distance_to(halfway) < ramp_step, "the ramp's middle is halfway between the colours, read %s" % middle)


func test_a_pixel_on_a_palette_colour_stays_itself_at_full_bands() -> void:
    var palette: Array[Color] = [DARK_RED, CREAM, Color("#2a4fa0")]
    _put(palette)
    var values := {"palette": palette, "shadows": 1.0, "midtones": 1.0, "highlights": 1.0, "influence": 2.0}
    assert_true(_engine.apply(_doc, _doc.active_layer, SaPointAdjust.PALETTE, values, "N10"), "the lookup ran")
    var row := _texels(palette.size())
    for i in palette.size():
        assert_true(_near(row[i], palette[i]), "%s on the palette stays itself, read %s" % [palette[i].to_html(false), row[i]])


func test_a_palette_of_one_colour_moves_a_pixel_by_its_pull_as_before() -> void:
    var colours: Array[Color] = [
        Color(0.05, 0.04, 0.08, 1.0),
        Color(0.3, 0.2, 0.1, 1.0),
        Color(0.5, 0.5, 0.5, 1.0),
        Color(0.2, 0.7, 0.4, 1.0),
        Color(0.85, 0.9, 0.95, 1.0),
        DARK_RED,
        CREAM,
    ]
    var target := Color("#3c6e46")
    var bands := Vector3(0.25, 0.5, 1.0)
    _put(colours)
    var values := {"palette": [target], "shadows": bands.x, "midtones": bands.y, "highlights": bands.z, "influence": 1.5}
    assert_true(_engine.apply(_doc, _doc.active_layer, SaPointAdjust.PALETTE, values, "N10"), "the lookup ran")
    var row := _texels(colours.size())
    for i in colours.size():
        var lab := _lab(colours[i])
        var l := clampf(lab.x, 0.0, 1.0)
        var shadows := _smoothstep(0.5, 0.0, l)
        var highlights := _smoothstep(0.5, 1.0, l)
        var pull := shadows * bands.x + (1.0 - shadows - highlights) * bands.y + highlights * bands.z
        var wanted := _encoded(lab.lerp(_lab(target), pull))
        var said := "%s moves %.3f of the way to the one colour, wanted %s and read %s" % [colours[i], pull, wanted, row[i]]
        assert_true(_near(row[i], wanted), said)


## GLSL's smoothstep, written out so the edges may run either way.
static func _smoothstep(from: float, to: float, x: float) -> float:
    var t := clampf((x - from) / (to - from), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)
