## The OKHSV row keeps the hue it had while its colour is a grey, and the hue
## and saturation while it is black, for its own drags and for a colour shown
## from outside. A grey has no hue and black neither, and the row took
## the nought `srgb_to_okhsv` answers for them, so a blue swept to a grey came
## back red and one swept to black came back grey.
##
## The row runs detached, and its changes are echoed back into `show_color` the
## way the picker echoes them, since that echo is where a forgotten hue was
## re-derived.
extends "res://tests/test_framework.gd"

const HUE := 216.0 / 360.0
const SATURATION := 0.8
const VALUE := 0.8
const DEGREE := 1.0 / 360.0
const ONE_PER_CENT := 0.01


func _blue_row() -> SaPickerSliders:
    var row := SaPickerSliders.make(SaPickerSliders.Model.OKHSV)
    row.color_changed.connect(row.show_color)
    row.show_color(OkhsvConversions.okhsv_to_srgb(HUE, SATURATION, VALUE))
    return row


## Moves channel *index* as a drag would, by the slider's own commit.
func _move(row: SaPickerSliders, index: int, to: float) -> void:
    row.sliders[index]._commit(to)


func _hsv(color: Color) -> Vector3:
    return OkhsvConversions.srgb_to_okhsv(color)


func test_saturation_to_nought_and_back_keeps_the_hue() -> void:
    var row := _blue_row()
    assert_almost_eq(row.sliders[0].value, HUE, DEGREE, "The blue reads 216 degrees")
    _move(row, 1, 0.0)
    assert_true(OkhsvConversions.is_achromatic(row._color), "Saturation at nought is a grey")
    assert_almost_eq(row.sliders[0].value, HUE, DEGREE, "and the hue slider still reads 216 degrees at the grey")
    _move(row, 1, SATURATION)
    var back := _hsv(row._color)
    assert_almost_eq(back.x, HUE, DEGREE, "Saturation back at 80 per cent brings the blue back at 216 degrees, not red")
    assert_almost_eq(back.y, SATURATION, ONE_PER_CENT, "at 80 per cent saturation")
    assert_almost_eq(row.sliders[0].value, HUE, DEGREE, "with the hue slider reading it")
    row.free()


func test_value_to_nought_and_back_keeps_the_hue_and_the_saturation() -> void:
    var row := _blue_row()
    _move(row, 2, 0.0)
    assert_almost_eq(row._color.r + row._color.g + row._color.b, 0.0, 1e-4, "Value at nought is black")
    assert_almost_eq(row.sliders[0].value, HUE, DEGREE, "and the hue slider still reads 216 degrees at black")
    assert_almost_eq(row.sliders[1].value, SATURATION, ONE_PER_CENT, "and the saturation slider 80 per cent")
    _move(row, 2, VALUE)
    var back := _hsv(row._color)
    assert_almost_eq(back.x, HUE, DEGREE, "Value back at 80 per cent brings the blue back at 216 degrees")
    assert_almost_eq(back.y, SATURATION, ONE_PER_CENT, "and at 80 per cent saturation, not a grey")
    assert_almost_eq(back.z, VALUE, ONE_PER_CENT, "at 80 per cent value")
    row.free()


func test_a_grey_from_outside_keeps_the_hue_and_a_red_sets_it() -> void:
    var row := _blue_row()
    row.show_color(Color(0.5, 0.5, 0.5, 1.0))
    assert_almost_eq(row.sliders[0].value, HUE, DEGREE, "A grey shown after the blue leaves the hue slider at 216 degrees")
    assert_almost_eq(row.sliders[1].value, 0.0, ONE_PER_CENT, "with saturation at the grey's nought")
    var red := Color(0.9, 0.1, 0.1, 1.0)
    row.show_color(red)
    assert_almost_eq(row.sliders[0].value, _hsv(red).x, DEGREE, "and a red shown next sets the red's own hue")
    assert_almost_eq(row.sliders[1].value, _hsv(red).y, ONE_PER_CENT, "and its saturation")
    row.free()


func test_black_from_outside_keeps_the_hue_and_the_saturation() -> void:
    var row := _blue_row()
    row.show_color(Color(0.0, 0.0, 0.0, 1.0))
    assert_almost_eq(row.sliders[0].value, HUE, DEGREE, "Black shown after the blue leaves the hue at 216 degrees")
    assert_almost_eq(row.sliders[1].value, SATURATION, ONE_PER_CENT, "and the saturation at 80 per cent")
    assert_almost_eq(row.sliders[2].value, 0.0, ONE_PER_CENT, "with value at nought")
    row.free()
