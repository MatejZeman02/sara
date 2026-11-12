## The colour picker docker's numeric rows.
##
## The trap the item names is that a slider clamps, so the assertions are about
## what a channel above 1.0 does rather than about whether three sliders exist.
## Every one of them runs on a detached row: nothing here needs a tree, and a
## docker in one would put a Window in a headless run.
extends "res://tests/test_framework.gd"

const HDR := Color(3.0, 0.5, 0.2, 1.0)


func _row(model: SaPickerSliders.Model) -> SaPickerSliders:
    return SaPickerSliders.make(model)


## The row shows what it is given, and an ordinary colour needs no headroom.
func test_the_rgb_row_shows_the_channels_it_is_given() -> void:
    var row := _row(SaPickerSliders.Model.RGB)
    row.show_color(Color(0.25, 0.5, 0.75, 1.0))
    assert_almost_eq(row.sliders[0].value, 0.25, 1e-4, "Red is red")
    assert_almost_eq(row.sliders[1].value, 0.5, 1e-4, "green is green")
    assert_almost_eq(row.sliders[2].value, 0.75, 1e-4, "and blue is blue")
    assert_almost_eq(row.sliders[0].max_value, 1.0, 1e-4, "A colour inside the cube leaves the range alone")
    row.free()


## The whole item. A fixed 0 to 1 slider would have shown 1.0 here and written
## it back on the next refresh, losing an HDR colour nobody had touched.
func test_a_channel_above_one_survives_being_shown() -> void:
    assert_almost_eq(SaPickerSliders.headroom_for(Color(0.9, 0.2, 0.1)), 1.0, 1e-4, "An ordinary colour asks for no headroom")
    assert_almost_eq(SaPickerSliders.headroom_for(HDR), 3.0, 1e-4, "and one at 3.0 asks for exactly 3")
    assert_almost_eq(SaPickerSliders.headroom_for(Color(1.4, 0.0, 0.0)), 2.0, 1e-4, "1.4 rounds up to a whole number")

    var row := _row(SaPickerSliders.Model.RGB)
    row.show_color(HDR)
    assert_almost_eq(row.sliders[0].max_value, 3.0, 1e-4, "The red slider reaches what it has to show")
    assert_almost_eq(row.sliders[0].value, 3.0, 1e-4, "and shows it rather than a clamp")
    row.free()


## The other two channels come from the colour, not from the sliders beside the
## one that moved, so dragging green cannot round-trip red through a control
## that has since narrowed.
func test_dragging_one_channel_leaves_an_out_of_range_neighbour_alone() -> void:
    var row := _row(SaPickerSliders.Model.RGB)
    row.show_color(HDR)
    var seen: Array[Color] = []
    row.color_changed.connect(func(color: Color) -> void: seen.append(color))

    row.sliders[1].value_changed.emit(0.8)
    assert_eq(seen.size(), 1, "The move was announced once")
    assert_almost_eq(seen[0].r, 3.0, 1e-4, "and red is still where the eyedropper left it")
    assert_almost_eq(seen[0].g, 0.8, 1e-4, "with green where the slider was put")
    assert_almost_eq(seen[0].b, 0.2, 1e-4, "and blue untouched")
    row.free()


## The OKHSV row takes a colour apart and puts it back through the same
## conversions the wheel uses, so the two say the same thing about a hue.
func test_the_okhsv_row_round_trips_a_colour() -> void:
    var row := _row(SaPickerSliders.Model.OKHSV)
    var start := Color(0.878, 0.627, 0.251, 1.0)
    row.show_color(start)
    var wheel := OkhsvConversions.srgb_to_okhsv(start)
    assert_almost_eq(row.sliders[0].value, wheel.x, 1e-4, "The hue is the wheel's own")
    assert_almost_eq(row.sliders[1].value, wheel.y, 1e-4, "and so is the saturation")
    assert_almost_eq(row.sliders[2].value, wheel.z, 1e-4, "and the value")

    var seen: Array[Color] = []
    row.color_changed.connect(func(color: Color) -> void: seen.append(color))
    row.sliders[0].value_changed.emit(0.5)
    assert_eq(seen.size(), 1, "Moving the hue announced a colour")
    var back := OkhsvConversions.srgb_to_okhsv(seen[0])
    assert_almost_eq(back.x, 0.5, 1e-3, "which reads back at the hue that was asked for")
    assert_almost_eq(back.y, wheel.y, 1e-3, "with the saturation kept")
    row.free()


## A typed value is a colour chosen and a drag is a colour being swept, so the
## recent colours get one entry per choice rather than one per pixel of travel.
func test_a_drag_commits_once_and_a_typed_value_commits_at_once() -> void:
    var row := _row(SaPickerSliders.Model.RGB)
    row.show_color(Color(0.2, 0.2, 0.2, 1.0))
    # An array rather than an int, because a GDScript lambda captures a local
    # by value and an incremented copy never leaves the lambda.
    var commits: Array[Color] = []
    row.color_committed.connect(func(color: Color) -> void: commits.append(color))

    row.sliders[0].value_changed.emit(0.4)
    assert_eq(commits.size(), 1, "A value with no drag under way is a colour chosen")

    var press := InputEventMouseButton.new()
    press.button_index = MOUSE_BUTTON_LEFT
    press.pressed = true
    row.sliders[0].gui_input.emit(press)
    row.sliders[0].value_changed.emit(0.5)
    row.sliders[0].value_changed.emit(0.6)
    assert_eq(commits.size(), 1, "and a sweep announces changes without committing any of them")

    var release := InputEventMouseButton.new()
    release.button_index = MOUSE_BUTTON_LEFT
    release.pressed = false
    row.sliders[0].gui_input.emit(release)
    assert_eq(commits.size(), 2, "until the button comes up")
    row.free()


## What the sliders print for the mockup numbers, the ochre a painter aimed a sun
## at by its hue number and got pink. The mockup's 41 degrees, 77 and 78 per
## cent are the ochre's plain HSV and the row is OKHSV, which reads 81, 84 and 80
## of the same colour, so the OKHSV row is shown the colour those three numbers
## name and the RGB row the ochre the mockup's other three are. The values
## underneath stay fractions of one, so they are also checked raw.
func test_the_rows_print_degrees_per_cent_and_bytes() -> void:
    var ochre := Color8(200, 150, 46)
    var okhsv := _row(SaPickerSliders.Model.OKHSV)
    okhsv.show_color(OkhsvConversions.okhsv_to_srgb(41.0 / 360.0, 0.77, 0.78))
    assert_eq(okhsv.sliders[0]._label.text, "H: 41°", "The hue reads in degrees, with the sign against the number")
    assert_eq(okhsv.sliders[1]._label.text, "S: 77 %", "saturation in per cent")
    assert_eq(okhsv.sliders[2]._label.text, "V: 78 %", "and value in per cent")
    assert_almost_eq(okhsv.sliders[0].value, 41.0 / 360.0, 1e-3, "while the hue underneath is still a fraction of one")
    okhsv.free()

    var rgb := _row(SaPickerSliders.Model.RGB)
    rgb.show_color(ochre)
    assert_eq(rgb.sliders[0]._label.text, "R: 200", "Red reads 0 to 255 with no decimals")
    assert_eq(rgb.sliders[1]._label.text, "G: 150", "green too")
    assert_eq(rgb.sliders[2]._label.text, "B: 46", "and blue")
    assert_almost_eq(rgb.report()["R"], 200.0 / 255.0, 1e-4, "and the dump the harness reads is the raw fraction")
    rgb.free()


## A number typed into a slider is read in the units the slider prints, so 180 in
## the hue box is half a turn and not a hundred and eighty turns clamped to one.
func test_a_typed_number_is_read_in_the_printed_units() -> void:
    var okhsv := _row(SaPickerSliders.Model.OKHSV)
    okhsv.show_color(Color8(200, 150, 46))
    okhsv.sliders[0]._line_edit.visible = true
    okhsv.sliders[0]._line_edit.text = "180"
    okhsv.sliders[0]._stop_editing()
    assert_almost_eq(okhsv.sliders[0].value, 0.5, 1e-4, "A typed 180 degrees lands at 0.5")
    okhsv.sliders[1]._line_edit.visible = true
    okhsv.sliders[1]._line_edit.text = "25"
    okhsv.sliders[1]._stop_editing()
    assert_almost_eq(okhsv.sliders[1].value, 0.25, 1e-4, "and a typed 25 per cent lands at a quarter")
    okhsv.free()

    var rgb := _row(SaPickerSliders.Model.RGB)
    rgb.show_color(Color(0.1, 0.1, 0.1))
    rgb.sliders[0]._line_edit.visible = true
    rgb.sliders[0]._line_edit.text = "128"
    rgb.sliders[0]._stop_editing()
    assert_almost_eq(rgb.sliders[0].value, 128.0 / 255.0, 1e-3, "A typed 128 is half of 255, to the slider's step")
    rgb.free()


## A channel past 1.0 is not on the scale of 255, and the display range is no
## ceiling (colours are never clamped), so an HDR row prints the floats it holds and a row that
## comes back inside the cube prints bytes again.
func test_an_hdr_channel_prints_as_a_float() -> void:
    var row := _row(SaPickerSliders.Model.RGB)
    row.show_color(HDR)
    assert_eq(row.sliders[0]._label.text, "R: 3.000", "Red past one prints as it is, to three places")
    assert_eq(row.sliders[1]._label.text, "G: 0.500", "and so do its neighbours, so a row never mixes two scales")
    assert_eq(row.sliders[2]._label.text, "B: 0.200", "whatever they hold")
    row.show_color(Color8(200, 150, 46))
    assert_eq(row.sliders[0]._label.text, "R: 200", "A colour back inside the cube reads in bytes again")
    row.free()


## Both rows are in the default order, so Preferences > Colour Picker offers
## them, and a stored profile written before them gets them appended.
func test_both_rows_are_layout_elements() -> void:
    var order: Array = SaSettings.DEFAULT_ORDERS["ColorPicker"]
    assert_true(order.has(SaPickerSliders.ELEMENT_RGB), "The RGB row is a layout element")
    assert_true(order.has(SaPickerSliders.ELEMENT_OKHSV), "and so is the OKHSV row")


## Each channel draws the colours that channel alone reaches, for the
## ochre, rather than one orange fill for all six, which made every value an
## orange bar and R show no red. R runs from no
## red to full red at the ochre's green and blue, and so on round.
func test_each_rgb_channel_draws_its_own_ramp() -> void:
    var ochre := Color8(200, 150, 46)
    var row := _row(SaPickerSliders.Model.RGB)
    row.show_color(ochre)
    for i in 3:
        var gradient := row.sliders[i].track_gradient
        assert_not_null(gradient, "%s has a track" % SaPickerSliders.RGB_LABELS[i])
        var low := ochre
        low[i] = 0.0
        var high := ochre
        high[i] = 1.0
        _assert_color(gradient.sample(0.0), low, "%s starts with none of itself" % SaPickerSliders.RGB_LABELS[i])
        _assert_color(gradient.sample(1.0), high, "and ends with all of it")

    # A colour past 1.0 widens the slider, and the track reaches as far as it.
    row.show_color(HDR)
    _assert_color(row.sliders[0].track_gradient.sample(1.0), Color(3.0, 0.5, 0.2), "R's track reaches 3.0, not a clamp")
    _assert_color(row.sliders[1].track_gradient.sample(1.0), Color(3.0, 3.0, 0.2), "and G's as far, carrying that red")
    row.free()


## H is the ring the wheel draws, S runs from the ochre's grey to its most
## saturated, and V from black to its brightest.
func test_each_okhsv_channel_draws_its_own_ramp() -> void:
    var ochre := Color8(200, 150, 46)
    var row := _row(SaPickerSliders.Model.OKHSV)
    row.show_color(ochre)
    var hsv := OkhsvConversions.srgb_to_okhsv(ochre)
    var hue := row.sliders[0].track_gradient
    _assert_color(hue.sample(0.0), OkhsvConversions.okhsv_to_srgb(0.0, 1.0, 1.0), "H starts on the ring's red")
    _assert_color(hue.sample(1.0), hue.sample(0.0), "and comes round to it")
    _assert_color(hue.sample(0.5), OkhsvConversions.okhsv_to_srgb(0.5, 1.0, 1.0), "with the opposite hue halfway")
    var saturation := row.sliders[1].track_gradient
    var gray := saturation.sample(0.0)
    assert_true(absf(gray.r - gray.g) < 2e-3 and absf(gray.g - gray.b) < 2e-3, "S starts on a grey, %s" % gray)
    _assert_color(gray, OkhsvConversions.okhsv_to_srgb(hsv.x, 0.0, hsv.z), "the ochre's own")
    _assert_color(saturation.sample(1.0), OkhsvConversions.okhsv_to_srgb(hsv.x, 1.0, hsv.z), "and ends at its most saturated")
    var value := row.sliders[2].track_gradient
    _assert_color(value.sample(0.0), Color.BLACK, "V starts on black")
    _assert_color(value.sample(1.0), OkhsvConversions.okhsv_to_srgb(hsv.x, hsv.y, 1.0), "and ends at the ochre's brightest")
    row.free()


func _assert_color(actual: Color, expected: Color, message: String) -> void:
    var close := absf(actual.r - expected.r) < 2e-3 and absf(actual.g - expected.g) < 2e-3 and absf(actual.b - expected.b) < 2e-3
    assert_true(close, "%s: %s against %s" % [message, actual, expected])
