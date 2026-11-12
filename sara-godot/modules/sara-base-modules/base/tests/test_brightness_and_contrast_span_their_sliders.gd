## Brightness and Contrast span their sliders.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Brightness at +18 must not read back 2.11 with a yellow gone white, as when
## six stops sat at the end of the slider. A dialog opens on the
## second formula in light now, 0.9 stops up and four down, and contrast's
## exponent moves half a unit either side of one. This suite reads a mid grey
## through the pass at five points of each slider and holds the records saved
## with the first formula and with none to the pictures they drew.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const GREY := Color(0.5, 0.5, 0.5, 1.0)
const POINTS: Array[float] = [-100.0, -50.0, 0.0, 50.0, 100.0]

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


## *colour* through the filter handed *record*, as one step, read back and
## undone.
func _run(colour: Color, record: Dictionary) -> Color:
    _doc.active_layer.fill(colour)
    _filter.set_parameters(record)
    var kind := SaPointAdjust.BRIGHTNESS_CONTRAST
    var applied := _engine.apply(_doc, _doc.active_layer, kind, _filter.values(), "S26")
    assert_true(applied, "The pass ran for %s" % record)
    var texture := _doc.active_layer.get_field(Vector2i.ZERO)
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    var texel := SaFieldSpec.decode_texel(bytes, texture.format, 10 * texture.size.x + 10)
    _doc.undo()
    return texel


## What a dialog opened now writes: its record names the second formula.
func _fresh(brightness: float, contrast: float) -> Dictionary:
    var host := VBoxContainer.new()
    _filter.store.reset()
    var dialog := SaDialog.for_filter(_filter)
    dialog.realize(host)
    _filter.capture_set({"brightness": brightness, "contrast": contrast})
    var record := _filter.parameters()
    host.free()
    return record


## Mid grey's encoded value at each point of *key*'s slider, the other at zero.
func _grey_along(key: String) -> Array[float]:
    var out: Array[float] = []
    for point in POINTS:
        var record := _fresh(point if key == "brightness" else 0.0, point if key == "contrast" else 0.0)
        out.append(_run(GREY, record).r)
    return out


func test_a_fresh_dialog_runs_the_second_formula() -> void:
    var record := _fresh(18.0, 0.0)
    var made: float = record[SaBrightnessContrastFilter.FORMULA_KEY]
    assert_eq(made, SaBrightnessContrastFilter.FORMULA_IN_LIGHT_2, "A dialog opened now writes the second formula")
    var lift := float(_filter.values()["brightness"])
    assert_true(lift < 1.4, "and +18 is a small lift, %.3f where six stops gave 2.11" % lift)


func test_brightness_moves_mid_grey_in_distinct_steps_across_its_slider() -> void:
    var greys := _grey_along("brightness")
    for i in range(1, greys.size()):
        var step := greys[i] - greys[i - 1]
        assert_true(step > 0.05, "Brightness %s to %s lifts grey by %.3f" % [POINTS[i - 1], POINTS[i], step])
    assert_almost_eq(greys[2], 0.5, 1e-4, "At zero grey stays")
    # About 0.9 at +100 is the aim. 0.9 stops is what keeps a yellow
    # off white to about +60 on screen, the filter's header says how, and it
    # leaves grey at about 0.67.
    assert_almost_eq(greys[4], 0.67, 0.03, "At +100 grey reaches about 0.67, read %.3f" % greys[4])
    assert_almost_eq(greys[0], 0.12, 0.03, "At -100 grey reaches about 0.12, read %.3f" % greys[0])


## Grey sits close to the fulcrum, so contrast moves it a little. What is
## asserted is that the five reads are distinct and in order.
func test_contrast_moves_mid_grey_in_distinct_steps_across_its_slider() -> void:
    var greys := _grey_along("contrast")
    for i in range(1, greys.size()):
        var step := greys[i] - greys[i - 1]
        assert_true(step > 1e-3, "Contrast %s to %s moves grey by %.4f" % [POINTS[i - 1], POINTS[i], step])
    assert_almost_eq(greys[2], 0.5, 1e-4, "At zero grey stays")
    assert_almost_eq(float(_filter.values()["contrast"]), 1.5, 1e-6, "and +100 is the exponent 1.5")


func test_a_record_with_the_first_formula_keeps_six_stops() -> void:
    var record := {"brightness": 100.0, "contrast": 0.0, "formula": SaBrightnessContrastFilter.FORMULA_IN_LIGHT}
    var out := _run(GREY, record)
    var light := OkhsvConversions.srgb_transfer_function_inv(Vector3(out.r, out.g, out.b))
    var grey := OkhsvConversions.srgb_transfer_function_inv(Vector3(0.5, 0.5, 0.5))
    assert_almost_eq(light.x / grey.x, 64.0, 0.05, "Six stops is sixty-four times the light")
    _filter.set_parameters({"brightness": 0.0, "contrast": 100.0, "formula": SaBrightnessContrastFilter.FORMULA_IN_LIGHT})
    assert_almost_eq(float(_filter.values()["contrast"]), 2.0, 1e-6, "and its contrast is still the doubled exponent")


func test_a_record_with_no_formula_still_runs_the_encoded_kernel() -> void:
    var out := _run(Color(0.25, 0.5, 0.75, 1.0), {"brightness": 30.0, "contrast": 25.0})
    assert_almost_eq(out.r, (0.25 - 0.5) * 1.25 + 0.8, 1e-4, "Red is the old offset and factor")
