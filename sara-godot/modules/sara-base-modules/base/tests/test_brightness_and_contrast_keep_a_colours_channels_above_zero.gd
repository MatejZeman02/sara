## Brightness and contrast keep a colour's channels above zero.
##
## Sliding the brightness and contrast sliders far must not leave colours with
## negative coordinates, which breaks the maths. The filter works in light, a power curve on luminance
## and a factor, so this suite
## runs it over dark, saturated and above-one colours at the ends of both
## sliders and reads back that nothing positive went negative and that the hue
## held. A record saved before the row names no formula and still draws what it
## drew, and a colour that arrives negative anyway is blended through the
## safety net rather than through arithmetic that flips its sign.
extends "res://tests/test_framework.gd"

const RoundTrip = preload("res://modules/sara-base-modules/base/tests/attached_round_trip.gd")

const REQUIRES_GPU := true

const OWNER := &"sara-base-modules"

## A row of colours, encoded sRGB: two dark, two saturated, one above one and
## one mid grey.
const COLOURS: Array[Color] = [
    Color(0.05, 0.02, 0.01, 1.0),
    Color(0.02, 0.06, 0.12, 1.0),
    Color(0.9, 0.1, 0.05, 1.0),
    Color(0.1, 0.2, 0.9, 1.0),
    Color(2.5, 1.2, 0.4, 1.0),
    Color(0.5, 0.5, 0.5, 1.0),
]

## The sliders' two ends, and both at once, in the rows' own units.
const SETTINGS: Array[Dictionary] = [
    {"brightness": 0.0, "contrast": 100.0},
    {"brightness": 0.0, "contrast": -100.0},
    {"brightness": 100.0, "contrast": 0.0},
    {"brightness": -100.0, "contrast": 0.0},
    {"brightness": 100.0, "contrast": 100.0},
    {"brightness": -100.0, "contrast": 100.0},
    {"brightness": 100.0, "contrast": -100.0},
    {"brightness": -100.0, "contrast": -100.0},
]

## Colours whose red is negative, which the old contrast made and an ACEScg
## picture carries. The second has no positive part left to keep on average.
const NEGATIVES: Array[Color] = [Color(-0.8, 0.9, 0.9, 1.0), Color(-2.0, 0.9, 0.9, 1.0)]

var _easel: SaEasel = null
var _doc: SaDocument = null
var _engine: SaPointAdjust = null
var _filter: SaBrightnessContrastFilter = null


func before_each() -> void:
    _easel = SaEasel.create_default(Vector2i(256, 256))
    _doc = _easel.document
    _engine = SaPointAdjust.new()
    _filter = SaBrightnessContrastFilter.new()


func after_each() -> void:
    _filter = null
    _engine = null
    _easel.free()
    _easel = null
    _doc = null


## *colour* through the filter handed the record *record*, as one step, read
## back and undone.
func _run(colour: Color, record: Dictionary) -> Color:
    _doc.active_layer.fill(colour)
    _filter.set_parameters(record)
    var kind := SaPointAdjust.BRIGHTNESS_CONTRAST
    var applied := _engine.apply(_doc, _doc.active_layer, kind, _filter.values(), "R8")
    assert_true(applied, "The pass ran for %s" % record)
    var texel := _texel(10, 10)
    _doc.undo()
    return texel


func _texel(x: int, y: int) -> Color:
    var texture := _doc.active_layer.get_field(Vector2i.ZERO)
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    return SaFieldSpec.decode_texel(bytes, texture.format, y * texture.size.x + x)


## The Oklab hue of an encoded sRGB colour in degrees, and its chroma.
static func _hue_and_chroma(colour: Color) -> Vector2:
    var linear := OkhsvConversions.srgb_transfer_function_inv(Vector3(colour.r, colour.g, colour.b))
    var lab := OkhsvConversions.linear_srgb_to_oklab(linear)
    return Vector2(rad_to_deg(atan2(lab.z, lab.y)), Vector2(lab.y, lab.z).length())


static func _with_formula(raw: Dictionary) -> Dictionary:
    var out := raw.duplicate()
    out[SaBrightnessContrastFilter.FORMULA_KEY] = SaBrightnessContrastFilter.FORMULA_IN_LIGHT
    return out


func test_no_channel_of_a_positive_colour_goes_below_zero_at_either_end() -> void:
    for setting: Dictionary in SETTINGS:
        for colour: Color in COLOURS:
            var out := _run(colour, _with_formula(setting))
            var lowest := minf(out.r, minf(out.g, out.b))
            assert_true(lowest >= 0.0, "%s at %s stays above zero, came out %s" % [colour, setting, out])
            assert_true(is_finite(out.r) and is_finite(out.g) and is_finite(out.b), "and finite: %s" % out)


func test_the_hue_holds_within_a_degree() -> void:
    for setting: Dictionary in SETTINGS:
        for colour: Color in COLOURS:
            var before := _hue_and_chroma(colour)
            if before.y < 0.01:
                continue
            var after := _hue_and_chroma(_run(colour, _with_formula(setting)))
            var turned := absf(wrapf(after.x - before.x, -180.0, 180.0))
            assert_true(turned < 1.0, "%s at %s keeps its hue, turned %.3f degrees" % [colour, setting, turned])


## The old formula pushed a dark channel below zero at the same setting, which
## is the fault under test.
func test_the_old_formula_made_the_negative_the_note_saw() -> void:
    var out := _run(COLOURS[2], {"brightness": 0.0, "contrast": 100.0})
    assert_true(out.g < 0.0, "The old contrast took saturated red's green below zero: %s" % out)


func test_the_sliders_at_zero_change_nothing_and_their_units_are_recorded() -> void:
    for colour: Color in COLOURS:
        var out := _run(colour, _with_formula({"brightness": 0.0, "contrast": 0.0}))
        assert_almost_eq(out.r, colour.r, 1e-4, "At zero red stays %s" % colour)
        assert_almost_eq(out.b, colour.b, 1e-4, "and blue")
    _filter.set_parameters(_with_formula({"brightness": 50.0, "contrast": -50.0}))
    var units := _filter.values()
    assert_almost_eq(float(units["brightness"]), 8.0, 1e-4, "Half the slider is three stops, a factor of eight")
    assert_almost_eq(float(units["contrast"]), 0.5, 1e-6, "and contrast the exponent, one plus a hundredth")


## Mid grey, 0.5 encoded, lifted by six stops at the top of the slider, the
## number the filter's docstring records.
func test_brightness_at_the_top_is_six_stops_of_light() -> void:
    var out := _run(COLOURS[5], _with_formula({"brightness": 100.0, "contrast": 0.0}))
    var light := OkhsvConversions.srgb_transfer_function_inv(Vector3(out.r, out.g, out.b))
    var grey := OkhsvConversions.srgb_transfer_function_inv(Vector3(0.5, 0.5, 0.5))
    assert_almost_eq(light.x / grey.x, 64.0, 0.05, "Six stops is sixty-four times the light")


func test_a_record_with_no_formula_runs_the_old_kernel() -> void:
    var old := {"brightness": 30.0, "contrast": 25.0}
    var out := _run(Color(0.25, 0.5, 0.75, 1.0), old)
    assert_almost_eq(out.r, (0.25 - 0.5) * 1.25 + 0.8, 1e-4, "Red is the old offset and factor")
    assert_almost_eq(out.b, (0.75 - 0.5) * 1.25 + 0.8, 1e-4, "and so is blue")
    assert_eq(
        _filter.parameters()[SaBrightnessContrastFilter.FORMULA_KEY],
        SaBrightnessContrastFilter.FORMULA_ENCODED,
        "and the record says so when it is written again"
    )


func test_a_fresh_dialog_writes_the_new_formula_into_its_record() -> void:
    var host := VBoxContainer.new()
    _filter.set_parameters({"brightness": 10.0, "contrast": 10.0})
    # What the one-shot window does: the defaults, whatever record ran last.
    _filter.store.reset()
    var dialog := SaDialog.for_filter(_filter)
    dialog.realize(host)
    _filter.capture_set({"brightness": 25.0})
    var made: float = _filter.parameters()[SaBrightnessContrastFilter.FORMULA_KEY]
    assert_eq(made, SaBrightnessContrastFilter.FORMULA_IN_LIGHT_2, "A dialog opened now writes the newest formula")
    # What the chain does with an old record behind the open dialog: it runs
    # the record and puts the dialog's values back.
    var shown := _filter.parameters()
    _filter.set_parameters({"brightness": 30.0, "contrast": 25.0})
    var behind := _filter.values()
    _filter.set_parameters(shown)
    assert_false(behind.has(SaBrightnessContrastFilter.FORMULA_KEY), "An old record behind the open dialog runs old")
    _filter.capture_set({"contrast": 40.0})
    var mine: float = _filter.parameters()[SaBrightnessContrastFilter.FORMULA_KEY]
    assert_eq(mine, SaBrightnessContrastFilter.FORMULA_IN_LIGHT_2, "and the dialog's own record keeps the newest one")
    host.free()


## A record attached and saved before the formula key existed, with no formula key, through a save
## and a load, draws the old result.
func test_an_old_record_saved_and_loaded_reads_the_old_result() -> void:
    var trip := RoundTrip.new(SaBrightnessContrastFilter.new(), OWNER)
    var old := {"brightness": 30.0, "contrast": 25.0}
    SaFilterOps.new(trip.easel.document).attach(trip.layer, trip.key, old)
    var loaded := trip.round_trip({"brightness": -80.0, "contrast": 90.0, "formula": 1.0})
    assert_false(loaded.has(SaBrightnessContrastFilter.FORMULA_KEY), "The loaded record still names no formula")
    var after := trip.texels()
    for index in RoundTrip.COLOURS.size():
        var colour: Color = RoundTrip.COLOURS[index]
        var drawn: Color = after[index]
        assert_almost_eq(drawn.r, (colour.r - 0.5) * 1.25 + 0.8, 1e-3, "Chunk %d draws the old red" % index)
        assert_almost_eq(drawn.b, (colour.b - 0.5) * 1.25 + 0.8, 1e-3, "and the old blue")
    trip.release()


## What the composite kernel draws for *kernel* with *src* over *dst*, on an
## sRGB document.
func _blend(kernel: String, src: Color, dst: Color) -> Color:
    var space := SaColorSpace.srgb()
    var texel := space.texel_format()
    var canvas := SaTexture.new(Vector2i(8, 8), texel)
    var chunk := SaTexture.new(Vector2i(8, 8), texel)
    canvas.clear(dst)
    chunk.clear(src)
    var compute := SaCompute.new("composite")
    compute.use_storage_format(texel)
    compute.set_texture(0, canvas.rid)
    compute.set_texture(1, chunk.rid)
    compute.set_push_constant_float_array(SaCompute.pack_composite_params(Vector2.ZERO, 1.0, space))
    compute.dispatch(GlobalShaderCompiler.get_kernel_index("composite", kernel), 1, 1, 1)
    return SaFieldSpec.decode_texel(GlobalShaderCompiler.get_rd().texture_get_data(canvas.rid, 0), texel)


static func _positive_part(colour: Color) -> Color:
    return Color(maxf(colour.r, 0.0), maxf(colour.g, 0.0), maxf(colour.b, 0.0), colour.a)


## The negative channel's answer is finite and on the same side of mid grey as
## the answer for the same colour with that channel at zero, the positive part
## a display shows. Multiply takes the negative on both sides, which the old
## kernel turned into a bright red, and soft light takes it in the backdrop,
## where a dark source flipped it bright past grey.
func test_a_negative_channel_blends_to_the_side_its_positive_part_does() -> void:
    for negative: Color in NEGATIVES:
        var cases := [
            ["multiply", negative, negative],
            ["soft_light", Color(0.1, 0.1, 0.1, 1.0), negative],
            ["soft_light", Color(0.9, 0.9, 0.9, 1.0), negative],
            ["multiply", Color(0.8, 0.8, 0.8, 1.0), negative],
        ]
        for case: Array in cases:
            var kernel: String = case[0]
            var src: Color = case[1]
            var dst: Color = case[2]
            var out := _blend(kernel, src, dst)
            var shown := _blend(kernel, _positive_part(src), _positive_part(dst))
            for channel in 3:
                assert_true(is_finite(out[channel]), "%s of %s over %s is finite: %s" % [kernel, src, dst, out])
            var said := "%s of %s over %s lands %s against its positive part's %s" % [kernel, src, dst, out.r, shown.r]
            assert_eq(out.r > 0.5, shown.r > 0.5, said)
