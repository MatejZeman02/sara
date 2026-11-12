## The EXR gradient test: the tonemapper's test image, opened,
## drawn through the canvas's own material with the rolloff off and on, and read
## back against the curve's formula, then exported and opened again.
##
## The picture is the EXR gradient test image. `scripts/write_exr_gradtest.py`
## writes it with no app in the loop, three rows of red, green and blue, each
## ramping its own channel from -1 at column 0 through 0 at column 500 to +4 at
## column 1000, the right half four times as steep as the left. So every texel's expected value is known before Sara reads the
## file, and every pixel's expected colour on screen is known before the shader
## runs, which turns "judged by eye" into a number.
##
## The scenario `scenarios/the-exr-gradient-test.json` is the same file in the
## running app, with the two shots. This is what the shots cannot say: the
## stored numbers to six places, the displayed bytes against the formula, and
## both halves after a round trip through the exporter, the negative one and
## the one above one.
extends "res://tests/test_framework.gd"

const Teardown := preload("res://tests/fixtures/teardown.gd")
## The file is decoded, composited and drawn on a real device.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const TexelProbe = preload("res://harness/report/sa_texel_probe.gd")

const FIXTURE := "res://tests/data/exr_gradtest.exr"
static var scratch_round_trip: String = SaDataRoot.path("s1_exr_gradtest_round_trip.exr")

## The script's own numbers, `WIDTH`, `HEIGHT`, `MIDDLE`, `BAND` and `PEAK`.
const SIZE := Vector2i(1001, 300)
const MIDDLE := 500
const BAND := 100
const PEAK := 4.0

## The rolloff's settings, set here rather than trusted, so a preference a
## painter moved on this machine cannot move the expected colours. The knee is
## the default before it moved to white, kept because a knee under
## white takes chroma from colours inside the cube too, which is the harder case
## for the transcription below.
const KNEE := 0.5
const DESATURATION := 0.15

## The shader's slack on the gamut test in `highlight_rolloff` and `gamut_map`.
const GAMUT_EPSILON := 1e-5

## The shader's F16 slack on the gamut test, a share of the texel's largest
## channel.
const GAMUT_ROUNDING := 2e-3

## The rows of the LMS to linear sRGB matrix, one per channel.
const LMS_TO_SRGB_ROWS: Array[Vector3] = [
    Vector3(4.0767416621, -3.3077115913, 0.2309699292),
    Vector3(-1.2684380046, 2.6097574011, -0.3413193965),
    Vector3(-0.0041960863, -0.7034186147, 1.7076147010),
]

## Where along a row the suite reads: both ends, the middle and its two
## neighbours, both sides of the knee at 562 and 563, both sides of one at 625
## and 626, and both sides of every chunk edge the ramp crosses, where a reader
## that got an edge wrong shows a step.
const COLUMNS: Array[int] = [
    0,
    125,
    250,
    255,
    256,
    400,
    499,
    500,
    501,
    511,
    512,
    562,
    563,
    600,
    625,
    626,
    700,
    750,
    767,
    768,
    875,
    1000,
]

## One stored value against the next: the left half moves by 1/500 a column,
## the right half by `PEAK` times that.
const STEP := 1.0 / 500.0

## A float32 read of a value the script wrote as float32 from the same formula.
const STORED_TOLERANCE := 1e-6

## Eight-bit frame against a double-precision transcription: one step of
## rounding either side.
const BYTE_TOLERANCE := 1

var _registries: SaRegistries = null
var _easel: SaEasel = null
var _canvas: SaCanvas = null
var _saved_tonemap := false
var _saved_knee := 0.5
var _saved_desaturation := 0.15
var _saved_mapping := ""


func before_each() -> void:
    _saved_tonemap = SaSettings.tonemap_highlights
    _saved_knee = SaSettings.tonemap_knee
    _saved_desaturation = SaSettings.tonemap_desaturation
    _saved_mapping = SaSettings.gamut_mapping
    SaSettings.tonemap_highlights = false
    SaSettings.tonemap_knee = KNEE
    SaSettings.tonemap_desaturation = DESATURATION
    SaSettings.gamut_mapping = SaGamutMapping.CLIP
    _registries = Fixtures.make_registries()
    _easel = _opened(FIXTURE)
    _canvas = SaCanvas.new()
    _canvas.canvas_size = SIZE
    _canvas.easel = _easel
    _canvas.sync_tonemap()


func after_each() -> void:
    Teardown.free_nodes([_canvas, _easel])
    _canvas = null
    _easel = null
    _registries = null
    SaSettings.tonemap_highlights = _saved_tonemap
    SaSettings.tonemap_knee = _saved_knee
    SaSettings.tonemap_desaturation = _saved_desaturation
    SaSettings.gamut_mapping = _saved_mapping
    if FileAccess.file_exists(scratch_round_trip):
        DirAccess.remove_absolute(ProjectSettings.globalize_path(scratch_round_trip))


## *path* opened the way File > Open opens a picture, a document of its own, and
## composited.
func _opened(path: String) -> SaEasel:
    var easel := SaEasel.create_default(SIZE)
    easel.compositor.set_registry(_registries.blend_modes)
    SaDocumentFiles.open_image_into(easel.document, path)
    # What `SaCanvas.resize_canvas` does after File > Open, without a canvas:
    # the output follows the document the open reset, and all of it composites.
    easel.resize_output(easel.document.canvas_size)
    easel.request_full_composite()
    easel.process_pending_composite()
    return easel


## The value column *x* holds in its row's channel, the script's `ramp`.
static func _ramp(x: int) -> float:
    var value := float(x - MIDDLE) / float(MIDDLE)
    return value if x <= MIDDLE else PEAK * value


## Which channel row *y* ramps, 0 red, 1 green and 2 blue from the top.
static func _channel(y: int) -> int:
    @warning_ignore("integer_division")
    return mini(y / BAND, 2)


## The linear colour the fixture stores at (*x*, *y*), alpha aside.
static func _stored(x: int, y: int) -> Vector3:
    var rgb := Vector3.ZERO
    rgb[_channel(y)] = _ramp(x)
    return rgb


## *rgb* as a save the painter asks for holds it, each channel a float32
## rounded to 12 significant bits, which an export rounds the live colour to
## first.
static func _as_saved(rgb: Vector3) -> Vector3:
    var bytes := PackedByteArray()
    bytes.resize(4)
    for i in 3:
        bytes.encode_float(0, rgb[i])
        bytes.encode_u32(0, SaSadSnapshot.round_bits(bytes.decode_u32(0)))
        rgb[i] = bytes.decode_float(0)
    return rgb


## One point read the way the `texel` step reads it.
func _probe(easel: SaEasel, x: int, y: int) -> Dictionary:
    var canvas := SaCanvas.new()
    canvas.canvas_size = SIZE
    canvas.easel = easel
    var answer := TexelProbe._read_point(easel.document, canvas, Vector2i(x, y))
    canvas.free()
    return answer


## The middle of each row, 50, 150 and 250.
static func _rows() -> Array[int]:
    var half := int(BAND * 0.5)
    return [half, BAND + half, 2 * BAND + half]


func _assert_texel(read: Variant, expected: Vector3, what: String) -> void:
    assert_not_null(read, "%s is read" % what)
    if read == null:
        return
    var got := read as Dictionary
    assert_almost_eq(float(got["r"]), expected.x, STORED_TOLERANCE, "%s: red" % what)
    assert_almost_eq(float(got["g"]), expected.y, STORED_TOLERANCE, "%s: green" % what)
    assert_almost_eq(float(got["b"]), expected.z, STORED_TOLERANCE, "%s: blue" % what)
    assert_almost_eq(float(got["a"]), 1.0, STORED_TOLERANCE, "%s: opaque" % what)


func test_the_file_opens_as_the_picture_the_spec_draws() -> void:
    var doc := _easel.document
    assert_eq(doc.canvas_size, SIZE, "The picture is the document, 1001 by 300")
    var linear := SaColorSpace.linear_srgb().id
    assert_eq(doc.color_space.id, linear, "and an EXR opens linear, so no curve sits between the file and the numbers")
    assert_eq(SaLayerOps.new(doc).layers().size(), 1, "and the picture is its only layer")
    for y: int in _rows():
        for x: int in COLUMNS:
            _assert_texel(_probe(_easel, x, y)["layer"], _stored(x, y), "the layer at %d, %d" % [x, y])


## The composite is what the view draws and what the exporter writes, so a
## clamp in the compositor would show here first.
func test_the_composite_keeps_both_halves_of_every_row() -> void:
    for y: int in _rows():
        for x: int in COLUMNS:
            _assert_texel(_probe(_easel, x, y)["composited"], _stored(x, y), "the composite at %d, %d" % [x, y])


func test_the_ramp_has_no_step_at_a_chunk_edge() -> void:
    for y: int in _rows():
        var channel := _channel(y)
        for edge: int in [256, 512, 768]:
            var before := _probe(_easel, edge - 1, y)["composited"] as Dictionary
            var after := _probe(_easel, edge, y)["composited"] as Dictionary
            var key: String = ["r", "g", "b"][channel]
            var rise := float(after[key]) - float(before[key])
            var what := "Row %d rises one column's worth across the chunk edge at %d" % [channel, edge]
            var step := STEP if edge <= MIDDLE else PEAK * STEP
            assert_almost_eq(rise, step, STORED_TOLERANCE, what)


## The two things the view promises on this picture whatever the rolloff does:
## the middle column is black, a grey, and every texel of the left half shows
## as black on a display that cannot show a negative.
func test_the_middle_column_is_grey_and_the_left_half_black_either_way() -> void:
    for enabled: bool in [false, true]:
        var frame := _frame(enabled)
        for y: int in _rows():
            var middle := frame.get_pixel(MIDDLE, y)
            assert_eq(middle.r8, middle.g8, "Middle column, row %d, rolloff %s: red is green" % [_channel(y), enabled])
            assert_eq(middle.g8, middle.b8, "and green is blue")
            for x: int in [0, 125, 250, 400, 499]:
                var shown := frame.get_pixel(x, y)
                var what := "Column %d, row %d, rolloff %s is black" % [x, _channel(y), enabled]
                assert_eq([shown.r8, shown.g8, shown.b8], [0, 0, 0], what)


func test_with_the_rolloff_off_the_view_is_the_encoded_value() -> void:
    _assert_frame(_frame(false), false)


func test_with_the_rolloff_on_the_view_follows_the_curve() -> void:
    _assert_frame(_frame(true), true)


## Above the knee the rolloff gives chroma up, so the two frames part there and
## only there, which is the one difference the picture is made to show.
func test_the_two_frames_part_only_above_the_knee() -> void:
    var off := _frame(false)
    var on := _frame(true)
    for y: int in _rows():
        for x: int in COLUMNS:
            var same := off.get_pixel(x, y) == on.get_pixel(x, y)
            if _ramp(x) < KNEE:
                assert_true(same, "Column %d, row %d is under the knee, so the rolloff leaves it alone" % [x, _channel(y)])
        var right_off := off.get_pixel(SIZE.x - 1, y)
        var right_on := on.get_pixel(SIZE.x - 1, y)
        assert_true(right_off != right_on, "and at the right edge of row %d it has given chroma up" % _channel(y))


## Hard rule 5 on a file: exported as EXR, opened again, and the negative half
## is still the fixture's.
func test_the_negative_half_survives_an_exr_round_trip() -> void:
    assert_eq(SaExport.export_exr(_easel, scratch_round_trip), OK, "The composite exports as EXR")
    var again := _opened(scratch_round_trip)
    assert_eq(again.document.canvas_size, SIZE, "and opens again at its size")
    for y: int in _rows():
        for x: int in COLUMNS:
            var read: Variant = _probe(again, x, y)["layer"]
            _assert_texel(read, _as_saved(_stored(x, y)), "the round trip at %d, %d" % [x, y])
            if x < MIDDLE and read != null:
                var key: String = ["r", "g", "b"][_channel(y)]
                assert_true(float((read as Dictionary)[key]) < 0.0, "and it is negative, %f" % float((read as Dictionary)[key]))
    again.free()


## Hard rule 5 the other way: the right edge holds four, and four is what the
## layer, the composite and the export opened again read, not the one a clamp
## would leave.
func test_the_top_value_survives_an_exr_round_trip() -> void:
    var right := SIZE.x - 1
    assert_almost_eq(_ramp(right), PEAK, STORED_TOLERANCE, "The right edge is the peak")
    assert_true(PEAK >= 4.0, "and the peak is at least four")
    assert_eq(SaExport.export_exr(_easel, scratch_round_trip), OK, "The composite exports as EXR")
    var again := _opened(scratch_round_trip)
    for y: int in _rows():
        var key: String = ["r", "g", "b"][_channel(y)]
        var before := _probe(_easel, right, y)
        var after := _probe(again, right, y)
        for read: Variant in [before["layer"], before["composited"], after["layer"], after["composited"]]:
            assert_not_null(read, "Row %d's right edge is read" % _channel(y))
            if read != null:
                var value := float((read as Dictionary)[key])
                assert_almost_eq(value, PEAK, STORED_TOLERANCE, "Row %d's right edge holds %f" % [_channel(y), value])
    again.free()


func _assert_frame(frame: Image, rolled: bool) -> void:
    for y: int in _rows():
        for x: int in COLUMNS:
            var shown := frame.get_pixel(x, y)
            var expected := _displayed(_stored(x, y), rolled)
            var got := [shown.r8, shown.g8, shown.b8]
            var close := true
            for i in 3:
                close = close and absi(int(got[i]) - int(expected[i])) <= BYTE_TOLERANCE
            var where := [x, _channel(y), rolled, got, expected]
            var what := "Column %d, row %d, rolloff %s shows %s against the formula's %s" % where
            assert_true(close, what)


## The easel's output drawn one texel a pixel through the canvas's own material
## into a viewport, and read back, with the rolloff *enabled* or not.
func _frame(enabled: bool) -> Image:
    SaSettings.tonemap_highlights = enabled
    _canvas.sync_tonemap()
    var viewport := SubViewport.new()
    viewport.size = SIZE
    viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    EventBus.add_child(viewport)
    var output := Texture2DRD.new()
    output.texture_rd_rid = _easel.output.rid
    var item := RenderingServer.canvas_item_create()
    RenderingServer.canvas_item_set_parent(item, viewport.find_world_2d().canvas)
    RenderingServer.canvas_item_set_material(item, _canvas.material.get_rid())
    RenderingServer.canvas_item_set_default_texture_filter(item, RenderingServer.CANVAS_ITEM_TEXTURE_FILTER_NEAREST)
    RenderingServer.canvas_item_add_texture_rect(item, Rect2(Vector2.ZERO, Vector2(SIZE)), output.get_rid())
    RenderingServer.force_draw(false, 0.0)
    var image := viewport.get_texture().get_image()
    RenderingServer.free_rid(item)
    viewport.free()
    return image


## The bytes the view should show for a stored linear *stored*, the shader's
## path for a linear sRGB document at unit exposure on an sRGB display with the
## gamut clipped: the rolloff when *rolled*, then the sRGB encode, then the
## frame's own clamp to 0 and 1.
static func _displayed(stored: Vector3, rolled: bool) -> Array:
    var linear := _rolloff(stored) if rolled else stored
    var out := []
    for i in 3:
        var value := clampf(linear[i], 0.0, 1.0)
        out.append(int(round(SaTransferFunction.srgb().encode(value) * 255.0)))
    return out


## A transcription of `highlight_rolloff` in `shaders/canvas/tonemap.gdshader`,
## the fifth copy after `SaCurvePlot`'s and the export kernel, and the one that
## keeps the shader's own closed form of the gamut map at its end.
static func _rolloff(c: Vector3) -> Vector3:
    var peak := maxf(c.x, maxf(c.y, c.z))
    var low := minf(c.x, minf(c.y, c.z))
    if peak <= KNEE and low >= -GAMUT_EPSILON:
        return c
    if peak <= KNEE:
        return _gamut_map(SaOklab.from_linear_srgb(c))
    var new_peak := minf(peak, 1.0)
    var scaled := c * (new_peak / peak)
    var lab := SaOklab.from_linear_srgb(scaled)
    var g := 1.0 - 1.0 / (DESATURATION * SaCurvePlot.pulled_by_the_shoulder(peak, KNEE) + 1.0)
    var neutral_l := SaOklab.from_linear_srgb(Vector3(new_peak, new_peak, new_peak)).x
    lab = Vector3(lerpf(lab.x, neutral_l, g), lab.y * (1.0 - g), lab.z * (1.0 - g))
    if low >= -GAMUT_EPSILON:
        lab = _within_half_the_slack(lab)
    return _gamut_map(lab)


## `within_half_the_slack` in the same shader: a colour outside half the gamut
## test's slack has its chroma brought down to where it first leaves the cube
## widened by half the slack, so the rolloff's step to white never carries a
## colour from the cube's face across blue's or yellow's fold.
static func _within_half_the_slack(lab: Vector3) -> Vector3:
    var chroma := Vector2(lab.y, lab.z).length()
    if lab.x <= 0.0 or lab.x >= 1.0 or chroma <= 0.0:
        return lab
    var linear := SaOklab.to_linear_srgb(lab)
    var slack := 0.5 * maxf(GAMUT_EPSILON, GAMUT_ROUNDING * maxf(absf(linear.x), maxf(absf(linear.y), absf(linear.z))))
    if _inside(linear, slack):
        return lab
    var hue := Vector2(lab.y, lab.z) / chroma
    var k := _slopes(hue)
    var s := chroma / lab.x
    for row: Vector3 in LMS_TO_SRGB_ROWS:
        s = minf(s, _widened_exit(row, k, lab.x * lab.x * lab.x, slack))
    var scale := s * lab.x / chroma
    return Vector3(lab.x, lab.y * scale, lab.z * scale)


## `gamut_map` in the same shader: chroma brought down to where the colour
## first meets the display's cube, lightness and hue held, black for a
## lightness at or below black and the neutral at or above white. The place is
## the shader's closed form, one cubic per channel and edge in u = L / C.
static func _gamut_map(lab: Vector3) -> Vector3:
    var linear := SaOklab.to_linear_srgb(lab)
    if _in_gamut(linear):
        return linear
    if lab.x <= 0.0:
        return Vector3.ZERO
    var chroma := Vector2(lab.y, lab.z).length()
    if lab.x >= 1.0 or chroma <= 0.0:
        return SaOklab.to_linear_srgb(Vector3(lab.x, 0.0, 0.0))
    var hue := Vector2(lab.y, lab.z) / chroma
    var k := _slopes(hue)
    var s := chroma / lab.x
    for row: Vector3 in LMS_TO_SRGB_ROWS:
        s = minf(s, _widened_exit(row, k, lab.x * lab.x * lab.x, 0.0))
    var scale := s * lab.x / chroma
    return SaOklab.to_linear_srgb(Vector3(lab.x, lab.y * scale, lab.z * scale))


## The Oklab to LMS slopes along the hue whose unit (a, b) is *hue*.
static func _slopes(hue: Vector2) -> Vector3:
    return Vector3(
        0.3963377774 * hue.x + 0.2158037573 * hue.y,
        -0.1055613458 * hue.x - 0.0638541728 * hue.y,
        -0.0894841775 * hue.x - 1.2914855480 * hue.y
    )


## `channel_exit` in the shader at a *slack* of nothing, and `widened_exit` at
## any other: the first saturation C / L at which the channel of row *w* passes
## *slack* below black or *slack* above one along the hue whose slopes are *k*,
## at a lightness whose cube is *l3*.
static func _widened_exit(w: Vector3, k: Vector3, l3: float, slack: float) -> float:
    var d2 := 3.0 * w.dot(k)
    var d1 := 3.0 * w.dot(k * k)
    var d0 := w.dot(k * k * k)
    var s := 1e30
    var to_below := _largest_cubic_root(1.0 + slack / l3, d2, d1, d0)
    if to_below > 0.0:
        s = 1.0 / to_below
    var to_above := _largest_cubic_root(minf(1.0 - (1.0 + slack) / l3, -1e-6), d2, d1, d0)
    if to_above > 0.0:
        s = minf(s, 1.0 / to_above)
    return s


## `largest_cubic_root` in the shader, Cardano's formula or the trigonometric
## form.
static func _largest_cubic_root(d3: float, d2: float, d1: float, d0: float) -> float:
    var a := d2 / d3
    var b := d1 / d3
    var c := d0 / d3
    var p := b - a * a / 3.0
    var q := 2.0 * a * a * a / 27.0 - a * b / 3.0 + c
    var disc := 0.25 * q * q + p * p * p / 27.0
    if disc > 0.0:
        var root := sqrt(disc)
        return _signed_cbrt(-0.5 * q + root) + _signed_cbrt(-0.5 * q - root) - a / 3.0
    if p >= 0.0:
        return -a / 3.0
    var r := sqrt(-p / 3.0)
    var angle := acos(clampf(1.5 * q / (p * r), -1.0, 1.0))
    return 2.0 * r * cos(angle / 3.0) - a / 3.0


static func _signed_cbrt(x: float) -> float:
    return signf(x) * pow(absf(x), 1.0 / 3.0)


static func _in_gamut(linear: Vector3) -> bool:
    return _inside(linear, maxf(GAMUT_EPSILON, GAMUT_ROUNDING * maxf(absf(linear.x), maxf(absf(linear.y), absf(linear.z)))))


## Whether *linear* is inside the cube widened by *slack* on both sides.
static func _inside(linear: Vector3, slack: float) -> bool:
    for i in 3:
        if linear[i] < -slack or linear[i] > 1.0 + slack:
            return false
    return true
