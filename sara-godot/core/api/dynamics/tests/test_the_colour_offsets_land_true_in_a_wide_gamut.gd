## The Hue, Saturation and Value offsets turn the picked colour
## in the document's own gamut.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The picker speaks the document's gamut, so on a Display P3 document the
## picked triple is P3's. The suite applies each offset to a known colour for a
## Display P3, an ACEScg and a Rec.2020 space and reads Oklab lightness, chroma
## and hue off the result through that space's own matrix, with an sRGB space
## and with none answering what the shift always answered, and paints a dab
## with each brush on a Display P3 document and reads the layer.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const StateNoiseBrushScript = preload("res://modules/sara-noise-brush-engine/state_noise_brush.gd")
const StateBrushScript = preload("res://modules/sara-base-modules/stamp-brush/tools/state_brush.gd")

const PICKED: Color = Color(0.8, 0.3, 0.2, 1.0)
const TOLERANCE: float = 1e-3
const HUE: float = 0.2
const SATURATION: float = 0.15
const VALUE: float = 0.08


## A dynamics that answers what the suite dialled, so a painted dab has known
## offsets without a sensor's curve between the number and the colour.
class DialledDynamics:
    extends SaDynamics

    var dialled: SaDabParams = SaDabParams.new()

    func evaluate(info: SaStrokeInfo, base_diameter: float, base_angle: float = 0.0, flipped: bool = false) -> SaDabParams:
        var dab := super.evaluate(info, base_diameter, base_angle, flipped)
        dab.hue_shift = dialled.hue_shift
        dab.saturation_shift = dialled.saturation_shift
        dab.value_shift = dialled.value_shift
        return dab


var _surface: SaSurface = null


func before_each() -> void:
    _surface = Fixtures.make_surface()
    _surface.easel.document.color_space = SaColorSpace.display_p3()


func after_each() -> void:
    Fixtures.teardown(_surface)
    _surface = null


# --- The shift ---------------------------------------------------------------


func test_each_offset_moves_oklab_in_the_documents_own_gamut() -> void:
    var spaces: Array[SaColorSpace] = [SaColorSpace.display_p3(), SaColorSpace.acescg(), SaColorSpace.rec2020()]
    for space in spaces:
        var before := _polar(PICKED, space)
        var hue := _shifted(space, HUE, 0.0, 0.0)
        var chroma := _shifted(space, 0.0, SATURATION, 0.0)
        var value := _shifted(space, 0.0, 0.0, VALUE)
        var all := _shifted(space, HUE, SATURATION, VALUE)
        var name := String(space.id)
        var swing := SATURATION * SaColorDynamics.MAX_CHROMA_SHIFT
        assert_almost_eq(hue.x, before.x, TOLERANCE, "%s: hue leaves lightness" % name)
        assert_almost_eq(hue.y, before.y, TOLERANCE, "%s: and chroma" % name)
        var turn := wrapf(hue.z - before.z - HUE * PI, -PI, PI)
        assert_almost_eq(turn, 0.0, TOLERANCE, "%s: and turns the hue by the offset" % name)
        assert_almost_eq(chroma.x, before.x, TOLERANCE, "%s: saturation leaves lightness" % name)
        assert_almost_eq(chroma.y, before.y + swing, TOLERANCE, "%s: and moves chroma" % name)
        assert_almost_eq(wrapf(chroma.z - before.z, -PI, PI), 0.0, TOLERANCE, "%s: and leaves hue" % name)
        assert_almost_eq(value.x, before.x + VALUE, TOLERANCE, "%s: value moves lightness" % name)
        assert_almost_eq(value.y, before.y, TOLERANCE, "%s: and leaves chroma" % name)
        assert_almost_eq(all.x, before.x + VALUE, TOLERANCE, "%s: all three, lightness" % name)
        assert_almost_eq(all.y, before.y + swing, TOLERANCE, "%s: chroma" % name)
        assert_almost_eq(wrapf(all.z - before.z - HUE * PI, -PI, PI), 0.0, TOLERANCE, "%s: hue" % name)


func test_an_srgb_space_and_none_read_todays_results() -> void:
    var dab := _dab(HUE, SATURATION, VALUE)
    var none := SaColorDynamics.apply(PICKED, dab)
    var srgb := SaColorDynamics.apply(PICKED, dab, Color.BLACK, SaColorSpace.srgb())
    var curve := SaTransferFunction.srgb()
    var linear := Vector3(curve.decode(PICKED.r), curve.decode(PICKED.g), curve.decode(PICKED.b))
    var polar := SaOklab.to_polar(SaOklab.from_linear_srgb(linear))
    var moved := SaOklab.to_linear_srgb(
        SaOklab.from_polar(
            Vector3(polar.x + VALUE, maxf(polar.y + SATURATION * SaColorDynamics.MAX_CHROMA_SHIFT, 0.0), polar.z + HUE * PI)
        )
    )
    var today := Color(curve.encode(moved.x), curve.encode(moved.y), curve.encode(moved.z), PICKED.a)
    assert_true(none == srgb, "No space and an sRGB one answer the same colour to the bit, %s and %s" % [none, srgb])
    assert_true(_close(none, today, 1e-6), "and it is the sRGB reading the shift always made, %s and %s" % [none, today])
    var untouched := SaColorDynamics.apply(PICKED, SaDabParams.new(), Color.BLACK, SaColorSpace.display_p3())
    assert_true(untouched == PICKED, "and no offset leaves a wide gamut's colour untouched to the bit")


# --- Painted -----------------------------------------------------------------


func test_a_noise_dab_on_a_display_p3_document_is_the_colour_computed() -> void:
    var brush := StateNoiseBrushScript.new()
    var dialled := DialledDynamics.new()
    dialled.dialled = _dab(HUE, SATURATION, VALUE)
    brush.dynamics = dialled
    brush.surface = _surface
    brush.stroke_seed = 7
    brush.settings.color = PICKED
    brush.settings.opacity = 1.0
    brush.settings.hardness = 1.0
    brush.settings.strength = 0.0
    brush.settings.strength_option.enabled = false
    brush.settings.radius = 6.0 / 256.0
    brush.begin_stroke(Vector2(100, 100), 1.0)
    brush.end_stroke()
    _read_painted(Vector2i(100, 100), "The noise brush")


func test_a_stamp_dab_on_a_display_p3_document_is_the_colour_computed() -> void:
    var stamp := StateBrushScript.new()
    var dialled := DialledDynamics.new()
    dialled.dialled = _dab(HUE, SATURATION, VALUE)
    stamp.dynamics = dialled
    stamp.surface = _surface
    stamp.settings.color = PICKED
    stamp.settings.radius = 6.0 / 256.0
    stamp.settings.hardness = GammaFloat.new(1.0, 1.0)
    stamp.settings.opacity_by_pressure = false
    var view := _surface.view
    view.mouse_position = Vector2(100, 100)
    var press := InputEventMouseButton.new()
    press.button_index = MOUSE_BUTTON_LEFT
    press.pressed = true
    stamp.handle_input(press)
    for step in range(1, 9):
        view.mouse_position = Vector2(100 + 4 * step, 100)
        var motion := InputEventMouseMotion.new()
        motion.button_mask = MOUSE_BUTTON_MASK_LEFT
        motion.pressure = 1.0
        stamp.handle_input(motion)
    var release := InputEventMouseButton.new()
    release.button_index = MOUSE_BUTTON_LEFT
    release.pressed = false
    stamp.handle_input(release)
    _read_painted(Vector2i(112, 100), "The stamp")


# --- Helpers -----------------------------------------------------------------


func _dab(hue: float, saturation: float, value: float) -> SaDabParams:
    var dab := SaDabParams.new()
    dab.hue_shift = hue
    dab.saturation_shift = saturation
    dab.value_shift = value
    return dab


## Oklab lightness, chroma and hue of the picker's *color* in *space*, carried
## through that space's own matrix into linear sRGB.
func _polar(color: Color, space: SaColorSpace) -> Vector3:
    var curve := SaTransferFunction.srgb()
    var linear := Vector3(curve.decode(color.r), curve.decode(color.g), curve.decode(color.b))
    return SaOklab.to_polar(SaOklab.from_linear_srgb(space.to_linear_srgb_matrix() * linear))


func _shifted(space: SaColorSpace, hue: float, saturation: float, value: float) -> Vector3:
    return _polar(SaColorDynamics.apply(PICKED, _dab(hue, saturation, value), Color.BLACK, space), space)


func _close(a: Color, b: Color, tolerance: float) -> bool:
    return absf(a.r - b.r) < tolerance and absf(a.g - b.g) < tolerance and absf(a.b - b.b) < tolerance


## The layer's stored texel at *pixel* against the colour the document stores
## for the picked colour shifted in its own gamut, and against what the sRGB
## reading would have stored, which it must not be.
func _read_painted(pixel: Vector2i, label: String) -> void:
    var document := _surface.easel.document
    var space := document.color_space
    var dab := _dab(HUE, SATURATION, VALUE)
    var expected := space.from_display(SaColorDynamics.apply(PICKED, dab, Color.BLACK, space))
    var srgb_way := space.from_display(SaColorDynamics.apply(PICKED, dab))
    var layer := document.active_layer
    var stored := Color(0, 0, 0, 0)
    for grid: Vector2i in layer.chunks:
        var side := (layer.chunks[grid] as SaChunk).pixel_size()
        var here := Vector2i(floori(float(pixel.x) / side), floori(float(pixel.y) / side))
        if layer.chunks.has(here):
            @warning_ignore("static_called_on_instance")
            var image: Image = SaExport.get_texture_image_float(layer.get_field(here))
            stored = image.get_pixelv(pixel - here * side)
        break
    assert_true(stored.a > 0.9, "%s painted, alpha %.3f" % [label, stored.a])
    var said := "%s paints the colour computed in the gamut, %s for %s" % [label, stored, expected]
    assert_true(_close(stored, expected, TOLERANCE), said)
    assert_false(_close(stored, srgb_way, TOLERANCE), "and not the sRGB reading of it, %s" % srgb_way)
