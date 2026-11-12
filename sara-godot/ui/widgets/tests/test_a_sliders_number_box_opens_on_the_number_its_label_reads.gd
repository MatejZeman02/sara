## A slider's number box opens on the number its label reads.
##
## A double-click on R in the colour picker opened the box on
## `200.000003278255` and on H on `81.3417702913284`, while the labels said
## `R: 200` and `H: 81°`. A picker channel is a float32, and `str()` of it
## times the multiplier printed the noise. The box now opens on the fewest
## places that name the value within `FactorSlider.COMMIT_TOLERANCE`, and a box
## closed as it opened commits nothing.
##
## The sliders here are built the way `SaPickerSliders.make` builds a channel,
## a thousandth's step and a multiplier, with the value read out of a `Color`
## so it carries the float32 noise the picker's does. The picker itself on the
## running app is
## `scenarios/a-sliders-number-box-opens-on-the-number-its-label-reads.json`.
extends "res://tests/test_framework.gd"

## An ochre whose R is 200.
const OCHRE := Color8(200, 150, 46)
## The hue a probe printed, in degrees.
const ASKS_HUE_DEGREES := 81.3417702913284

var _host: Node = null


func before_each() -> void:
    _host = Node.new()
    _host.name = "D1NumberBoxHost"
    # A `LineEdit` refuses `grab_focus` outside a tree and `start_editing`
    # grabs, so every slider here is in one.
    EventBus.add_child(_host)


func after_each() -> void:
    if _host != null:
        _host.free()
        _host = null


## A picker channel: 0 to 1 by a thousandth, printed at *multiplier* with no
## decimals, holding *raw*.
func _channel(multiplier: float, raw: float) -> FactorSlider:
    var slider := FactorSlider.new()
    _host.add_child(slider)
    slider.min_value = 0.0
    slider.max_value = 1.0
    slider.step = 0.001
    slider.display_value_multiplier = multiplier
    slider.decimal_places = 0
    slider.value = raw
    return slider


## A slider with no multiplier, 0 to 100 by a hundredth, holding *raw*.
func _plain(raw: float) -> FactorSlider:
    var slider := FactorSlider.new()
    _host.add_child(slider)
    slider.min_value = 0.0
    slider.max_value = 100.0
    slider.step = 0.01
    slider.value = raw
    return slider


## What a painter does to leave a number alone: double-click, then Enter.
## Answers the text the box opened on.
func _open_and_enter(slider: FactorSlider) -> String:
    slider.start_editing()
    var opened := slider._line_edit.text
    slider._on_line_edit_submitted(opened)
    return opened


## The R of 200, whole: the channel opens on 200 and Enter leaves it where it
## was. The box once read `200.000003278255`, and Enter then moved the
## value onto the thousandth's grid, 0.784, since 200 of 255 is not on it.
func test_a_channel_at_200_of_255_opens_on_200() -> void:
    var slider := _channel(255.0, OCHRE.r)
    var held := slider.value
    assert_eq(str(held * 255.0), "200.000003278255", "The case still carries the noise the ask was filed for")
    assert_eq(slider._label.text, "200", "The label reads 200")
    assert_eq(_open_and_enter(slider), "200", "and the box opens on 200")
    assert_eq(slider.value, held, "and Enter on it leaves the value exactly where it was")
    assert_false(slider._line_edit.visible, "with the box closed")

    var exact := _channel(255.0, 200.0 / 255.0)
    held = exact.value
    assert_eq(_open_and_enter(exact), "200", "A double that is 200 of 255 exactly opens on 200 as well")
    assert_eq(exact.value, held, "and stays")


## The ask's H: three places, because a thousandth of a degree is what the
## tolerance can tell apart at 360 to the turn, and the label's whole degree
## would move the hue by a third of one on Enter.
func test_a_hue_opens_on_the_places_the_tolerance_needs() -> void:
    var slider := _channel(360.0, ASKS_HUE_DEGREES / 360.0)
    var held := slider.value
    assert_eq(_open_and_enter(slider), "81.342", "The hue opens on 81.342 rather than 81.3417702913284")
    assert_eq(slider.value, held, "and Enter leaves it where it was")


## A small display needs more places than a large one, since the tolerance is
## in the value's units and not a share of the number.
func test_a_small_display_keeps_the_places_it_needs() -> void:
    var slider := _channel(255.0, Color(0.00123, 0.0, 0.0).r)
    var held := slider.value
    var opened := _open_and_enter(slider)
    assert_eq(opened, "0.3137", "A channel at a third of a byte opens on four places")
    assert_true(absf(opened.to_float() / 255.0 - held) <= FactorSlider.COMMIT_TOLERANCE, "which name it within the tolerance")
    assert_eq(slider.value, held, "and Enter leaves it where it was")


## Every slider with a multiplier of one keeps the text it opens on today,
## the ".0" of a whole number included, which is what the ask's second case
## holds at 0.8.
func test_a_slider_with_no_multiplier_keeps_its_text() -> void:
    var cases := {0.8: "0.8", 25.0: "25.0", 0.37: "0.37", 12.5: "12.5"}
    for raw: float in cases:
        var slider := _plain(raw)
        var held := slider.value
        assert_eq(_open_and_enter(slider), cases[raw], "%s opens on the text str() writes" % cases[raw])
        assert_eq(slider.value, held, "and Enter leaves %s where it was" % cases[raw])

    var opacity := FactorSlider.new()
    _host.add_child(opacity)
    opacity.min_value = 0.0
    opacity.max_value = 1.0
    opacity.step = 0.01
    opacity.normalized_display = true
    opacity.value = 0.8
    assert_eq(_open_and_enter(opacity), "80.0", "A per cent row with no multiplier keeps its text too")
    assert_almost_eq(opacity.value, 0.8, 0.0, "and its value")


## The one place a multiplier of one does not keep its text: a float32 value
## printed whole. The HDR channel at 1.2 read `1.20000004768372`, which is the
## ask's noise at a multiplier of one, so it is cut the same way.
func test_an_hdr_channel_drops_its_float32_noise() -> void:
    var hdr := Color(1.2, 0.5, 0.2).r
    assert_eq(str(hdr), "1.20000004768372", "The float32 channel carries the noise")
    var slider := FactorSlider.new()
    _host.add_child(slider)
    slider.min_value = 0.0
    slider.max_value = 2.0
    slider.step = 0.001
    slider.decimal_places = 3
    slider.value = hdr
    assert_eq(_open_and_enter(slider), "1.2", "and the box opens on 1.2")
    assert_eq(slider.value, hdr, "and Enter leaves the channel where it was")

    # A geometric row is not quantized, so a drag lands wherever the pointer
    # stopped and str() printed every digit of it.
    var dragged := _plain(3.4729103847)
    assert_eq(_open_and_enter(dragged), "3.47291", "A dragged 3.4729103847 opens on the five places a millionth needs")
    assert_eq(dragged.value, 3.4729103847, "and stays")


## A number the painter did type still commits, rounded to the step, and one
## typed back to what the box opened on is the same as leaving it alone.
func test_a_typed_number_still_commits() -> void:
    var slider := _channel(255.0, OCHRE.r)
    var committed: Array[float] = []
    slider.value_changed.connect(func(v: float) -> void: committed.append(v))
    slider.start_editing()
    slider._line_edit.text = "128"
    slider._on_line_edit_submitted("128")
    assert_almost_eq(slider.value, 0.502, 1e-9, "A typed 128 lands on the thousandth nearest 128 of 255")
    assert_eq(committed.size(), 1, "and says so once")

    var held := slider.value
    slider.start_editing()
    var opened := slider._line_edit.text
    slider._line_edit.text = " %s " % opened
    slider._on_line_edit_submitted(slider._line_edit.text)
    assert_eq(slider.value, held, "The opening text typed back, spaces and all, leaves the value")
    assert_eq(committed.size(), 1, "and says nothing")


## Escape shuts the box without the text it opened on staying behind, so a
## field typed into later by other means is read as typed.
func test_a_cancel_forgets_the_opening_text() -> void:
    var slider := _channel(255.0, OCHRE.r)
    slider.start_editing()
    slider._cancel_editing()
    assert_eq(slider._opened_text, "", "A cancelled box keeps no opening text")
    slider._line_edit.visible = true
    slider._line_edit.text = "200"
    slider._stop_editing()
    assert_almost_eq(slider.value, 0.784, 1e-9, "so a 200 typed into the field afterwards commits, to the step")


## The radius row, where the multiplier is the document's height: a whole
## pixel opens without the ".0" it had, and a geometric drag's tail is cut to
## what a millionth of the canvas is in pixels.
func test_the_radius_row_opens_on_its_pixels() -> void:
    var slider := FactorSlider.new()
    _host.add_child(slider)
    slider.logarithmic = true
    slider.min_value = 0.0001
    slider.max_value = 1.0
    slider.step = 0.001
    slider.display_value_multiplier = 1080.0
    slider.decimal_places = 2
    slider.trim_trailing_zeros = true
    slider.value = 30.0 / 1080.0
    var held := slider.value
    assert_eq(_open_and_enter(slider), "30", "30 px opens on 30")
    assert_eq(slider.value, held, "and stays")

    slider.value = 40.3123456789 / 1080.0
    held = slider.value
    assert_eq(_open_and_enter(slider), "40.312", "A dragged 40.3123456789 px opens on 40.312")
    assert_eq(slider.value, held, "and stays")
