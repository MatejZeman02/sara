## What this drives: a colour above 1.0 through the Colour Picker docker, and the
## two numeric rows that can destroy it.
##
## An out-of-range value survives paint, composite and export.
## The picker is where it dies quietly instead, because a slider has ends and a
## colour model does not, so these press the rows rather than reading the
## colour back off them.
##
## The scenario behind it is `scenarios/tour-picker.json`, whose dumps
## `picker-15` to `picker-20` are the same three claims on the running app.
extends "res://tests/test_framework.gd"

var _saved_shape: String


func before_each() -> void:
    _saved_shape = SaSettings.color_picker_shape


func after_each() -> void:
    SaSettings.color_picker_shape = _saved_shape


## The RGB row's own promise: only the channel that moved is written, and the
## other two come from the colour the row was last shown rather than from the
## controls beside it, which have ends.
func test_the_rgb_row_leaves_a_channel_above_one_where_it_was() -> void:
    var row := SaPickerSliders.make(SaPickerSliders.Model.RGB)
    row.show_color(Color(3.0, 0.5, 0.2))
    assert_almost_eq(row.sliders[0].max_value, 3.0, 1e-6, "The red slider widens to hold a colour at 3.0")

    # An array rather than a local, because a lambda captures a local by value
    # and the colour written inside one never reaches the caller.
    var seen: Array[Color] = [Color.BLACK]
    row.color_changed.connect(func(col: Color) -> void: seen[0] = col)
    _move(row, 2, 0.9)

    assert_almost_eq(seen[0].b, 0.9, 1e-4, "The blue channel takes the value that was set")
    assert_almost_eq(seen[0].r, 3.0, 1e-4, "and the red channel keeps its two stops of headroom")
    row.free()


## The same gesture on the OKHSV row. Its three channels are angles and
## fractions with real ends, so the colour is rebuilt through `okhsv_to_srgb`,
## which has no answer above 1.0. The row therefore divides by the peak before
## it asks and multiplies it back on after.
func test_the_okhsv_row_leaves_a_channel_above_one_where_it_was() -> void:
    var row := SaPickerSliders.make(SaPickerSliders.Model.OKHSV)
    row.show_color(Color(3.0, 0.5, 0.2))

    var seen: Array[Color] = [Color.BLACK]
    row.color_changed.connect(func(col: Color) -> void: seen[0] = col)
    _move(row, 1, 0.6)

    assert_almost_eq(seen[0].r, 3.0, 1e-3, "The OKHSV row keeps the red channel's headroom")
    row.free()


## Why it works, asserted rather than left as a comment: dividing by the peak
## puts the colour on the gamut surface, which is where OKHSV's value is 1.0,
## and every point of that surface has a peak of 1.0 again.
func test_the_okhsv_row_shows_an_hdr_colour_at_full_value() -> void:
    var row := SaPickerSliders.make(SaPickerSliders.Model.OKHSV)
    row.show_color(Color(3.0, 0.5, 0.2))

    assert_almost_eq(row.report()["headroom"], 3.0, 1e-6, "The peak is carried beside the three channels")
    assert_almost_eq(row.sliders[2].value, 1.0, 1e-3, "and the colour divided by it sits on the gamut surface")
    assert_eq(row.sliders[2].max_value, 1.0, "The value slider keeps its real end, unlike an RGB one")
    row.free()


## A hue move is the same claim, and the one that would fail if the peak were
## rounded up to the next whole number the way an RGB slider's end is.
func test_a_hue_move_on_an_hdr_colour_keeps_the_peak() -> void:
    var row := SaPickerSliders.make(SaPickerSliders.Model.OKHSV)
    row.show_color(Color(0.2, 3.5, 0.5))

    var seen: Array[Color] = [Color.BLACK]
    row.color_changed.connect(func(col: Color) -> void: seen[0] = col)
    _move(row, 0, 0.6)

    var peak := maxf(maxf(seen[0].r, seen[0].g), seen[0].b)
    assert_almost_eq(peak, 3.5, 1e-3, "The rotated hue comes back with the peak it went in with")
    row.free()


## The value slider is the one channel that is meant to move the peak, and the
## row must not drag it back to 1.0 when the picker echoes the change straight
## back through `show_color`.
func test_the_value_slider_dims_an_hdr_colour_and_stays_where_it_was_put() -> void:
    var row := SaPickerSliders.make(SaPickerSliders.Model.OKHSV)
    row.show_color(Color(3.0, 0.5, 0.2))

    var seen: Array[Color] = [Color.BLACK]
    row.color_changed.connect(func(col: Color) -> void: seen[0] = col)
    var hue := row.sliders[0].value
    var sat := row.sliders[1].value
    _move(row, 2, 0.5)

    # Against the model rather than against 1.5. OKHSV's value is not the peak
    # channel scaled linearly, because of the toe: a value of 0.5 on this hue
    # measures 0.49606 of the way down, so the colour lands at 1.48819 and not
    # at 1.5. What the row owes is the model's own answer times the peak.
    var dimmed := OkhsvConversions.okhsv_to_srgb(hue, sat, 0.5)
    assert_almost_eq(seen[0].r, dimmed.r * 3.0, 1e-4, "The dimmed colour is the model's own, with the peak on it")
    assert_true(seen[0].r < 3.0 and seen[0].r > 1.4, "and it really did dim, to 1.48819 on this hue")
    # What the picker does on every change: adopt the colour and show it back.
    row.show_color(seen[0])
    assert_almost_eq(row.sliders[2].value, 0.5, 1e-3, "and the slider is still where the drag left it")
    assert_almost_eq(row.report()["headroom"], 3.0, 1e-6, "because the echo does not re-derive the peak")
    row.free()


## A colour inside the cube divides by 1.0, so nothing about the headroom reaches an SDR
## picker, which is every picker most of the time.
func test_an_sdr_colour_is_untouched_by_the_headroom() -> void:
    var row := SaPickerSliders.make(SaPickerSliders.Model.OKHSV)
    row.show_color(Color(0.6, 0.3, 0.2))

    assert_almost_eq(row.report()["headroom"], 1.0, 1e-6, "An in-gamut colour has no peak to carry")
    var seen: Array[Color] = [Color.BLACK]
    row.color_changed.connect(func(col: Color) -> void: seen[0] = col)
    _move(row, 1, 0.4)

    var built := OkhsvConversions.okhsv_to_srgb(row.sliders[0].value, 0.4, row.sliders[2].value)
    assert_almost_eq(seen[0].r, built.r, 1e-5, "and the colour is what OKHSV alone says it is")
    assert_almost_eq(seen[0].g, built.g, 1e-5, "on the green channel too")
    row.free()


## Every shape in the Type dropdown, with an HDR colour held. The shape reads
## its axes from a colour it can draw, so the picker keeps the colour itself
## and never re-derives it from the shape.
func test_the_type_dropdown_carries_a_colour_above_one_through_every_shape() -> void:
    var picker := SaColorPicker.new()
    picker.color = (Color(3.0, 0.5, 0.2))
    for kind in SaPickerShape.KIND_KEYS.size():
        picker.set_shape_kind(kind)
        var held := picker.color
        assert_almost_eq(held.r, 3.0, 1e-4, "The %s keeps the red channel at 3.0" % SaPickerShape.KIND_KEYS[kind])
        assert_almost_eq(held.g, 0.5, 1e-4, "and the green channel where it was")
    picker.free()


## A drag on one channel, delivered the way a real one is: writing `value`
## alone runs nothing connected to `value_changed`, which is why every page in
## this repository is driven by the pair.
func _move(row: SaPickerSliders, index: int, value: float) -> void:
    row.sliders[index].set_value_no_signal(value)
    row.sliders[index].value_changed.emit(value)
