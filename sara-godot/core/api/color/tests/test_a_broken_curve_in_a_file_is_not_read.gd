## Four transfer numbers no curve can be made of are refused on the way in
## `SaTransferFunction.from_params` built a curve from any
## four numbers a header carried, and one with a slope or an exponent of
## nought decodes every texel to an infinity or a NaN, which nothing clamps.
extends "res://tests/test_framework.gd"


func _read(transfer_id: String, params: Array) -> SaColorSpace:
    return SaColorSpace.from_header({"color_space": {"transfer": transfer_id, "transfer_params": params}})


func test_an_exponent_of_nought_falls_back_to_the_named_curve() -> void:
    var space := _read("srgb", [12.92, 0.04045, 1.055, 0.0])
    assert_true(space.transfer.matches(SaTransferFunction.srgb()), "The id's own curve is read instead")
    assert_true(is_finite(space.transfer.encode(0.5)), "and it encodes to a number")


func test_a_slope_of_nought_under_a_threshold_is_refused() -> void:
    var no_slope := SaTransferFunction.from_params(&"srgb", [0.0, 0.04045, 1.055, 2.4])
    assert_null(no_slope, "Dividing by the slope is dividing by nought")


func test_a_gain_that_sends_the_base_below_nought_is_refused() -> void:
    assert_null(SaTransferFunction.from_params(&"custom", [1.0, 0.0, 0.5, 2.0]), "The power would be taken of a negative number")


func test_a_value_that_is_not_a_number_is_refused() -> void:
    assert_null(SaTransferFunction.from_params(&"gamma", ["x", 0.0, 1.0, 2.2]), "Text is not a slope")
    assert_null(SaTransferFunction.from_params(&"gamma", [1.0, 0.0, 1.0, INF]), "nor is an infinity an exponent")


func test_an_unnamed_curve_with_no_usable_numbers_reads_as_srgb() -> void:
    var space := _read("gamma", [1.0, 0.0, 1.0, -2.2])
    assert_true(space.transfer.matches(SaTransferFunction.srgb()), "No name and no numbers is sRGB, said in the log")


func test_every_preset_still_reads_back_from_its_numbers() -> void:
    for curve in SaTransferFunction.presets():
        var back := SaTransferFunction.from_params(curve.id, Array(curve.to_params()))
        assert_not_null(back, "%s survives its own header" % curve.display_name)
    var slider := Array(SaTransferFunction.gamma(1.8).to_params())
    assert_not_null(SaTransferFunction.from_params(&"gamma", slider), "and a slider's gamma")
