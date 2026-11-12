## Backspace resets a FactorSlider to the value it was built with, over a
## hovered slider or a focused one, and leaves the text field's own Backspace
## alone. `scenarios/backspace-resets-a-slider.json` is the same proof on
## the running app, on a Colour Balance slider.
## The hover is driven with `_on_mouse_entered()`, the handler the
## mouse's own signal calls, rather than by writing `_hovered` from outside the
## slider, because a private member is written by its own class only.
extends "res://tests/test_framework.gd"


func _backspace() -> InputEventKey:
    return _key(KEY_BACKSPACE)


func _key(keycode: Key, shift: bool = false, ctrl: bool = false) -> InputEventKey:
    var key := InputEventKey.new()
    key.keycode = keycode
    key.pressed = true
    key.shift_pressed = shift
    key.ctrl_pressed = ctrl
    return key


func _press(x: float, shift: bool = false) -> InputEventMouseButton:
    var press := InputEventMouseButton.new()
    press.button_index = MOUSE_BUTTON_LEFT
    press.pressed = true
    press.position = Vector2(x, 9.0)
    press.shift_pressed = shift
    return press


func _release(x: float) -> InputEventMouseButton:
    var release := InputEventMouseButton.new()
    release.button_index = MOUSE_BUTTON_LEFT
    release.pressed = false
    release.position = Vector2(x, 9.0)
    return release


func _motion(x: float, shift: bool = false) -> InputEventMouseMotion:
    var motion := InputEventMouseMotion.new()
    motion.button_mask = MOUSE_BUTTON_MASK_LEFT
    motion.position = Vector2(x, 9.0)
    motion.shift_pressed = shift
    return motion


## A linear slider from 0 to 100 over a box of four hundred pixels, so a
## plain pixel of hand is a quarter of a unit and forty pixels are ten.
func _hundred_wide() -> FactorSlider:
    var slider := FactorSlider.new()
    slider.min_value = 0.0
    slider.max_value = 100.0
    slider.step = 0.0
    slider._ready()
    slider.size = Vector2(400.0, 18.0)
    return slider


## The Radius row as the bar builds it on a 1080-tall document: the machine's
## range, geometric, two decimals that trim, and the canvas's pixels.
func _radius_row(pixels: float) -> FactorSlider:
    var slider := FactorSlider.new()
    slider.logarithmic = true
    slider.min_value = ToolMachine.BRUSH_RADIUS_MIN
    slider.max_value = ToolMachine.BRUSH_RADIUS_MAX
    slider.soft_max_value = ToolMachine.BRUSH_RADIUS_SOFT_MAX
    slider.step = 0.001
    slider.display_value_multiplier = 1080.0
    slider.prefix = "Radius: "
    slider.suffix = "px"
    slider.decimal_places = 2
    slider.trim_trailing_zeros = true
    slider.value = pixels / 1080.0
    slider._ready()
    slider.size = Vector2(400.0, 18.0)
    return slider


## A soft ceiling stops the drag and fills the bar, a hard one stops the typed
## value. Before it the slider had one ceiling, and the Size
## row's 0.2 was the largest brush a painter could have by any route.
func test_a_drag_stops_at_the_soft_ceiling_and_typing_at_the_hard_one() -> void:
    var slider := FactorSlider.new()
    slider.min_value = 0.0
    slider.max_value = 1.0
    slider.soft_max_value = 0.5
    slider.step = 0.001
    slider._ready()
    slider.size = Vector2(200.0, 18.0)

    slider._update_from_mouse_x(200.0)
    assert_almost_eq(slider.value, 0.5, 0.0001, "The far end of the drag is the soft ceiling")
    assert_almost_eq(slider.drag_max(), 0.5, 0.0001, "and the fill reads full there")

    slider._line_edit.visible = true
    slider._line_edit.text = "0.8"
    slider._stop_editing()
    assert_almost_eq(slider.value, 0.8, 0.0001, "A typed value goes past the soft ceiling")

    slider._line_edit.visible = true
    slider._line_edit.text = "7"
    slider._stop_editing()
    assert_almost_eq(slider.value, 1.0, 0.0001, "and stops at the hard one")

    slider.soft_max_value = 0.0
    assert_almost_eq(slider.drag_max(), 1.0, 0.0001, "With no soft ceiling the drag reaches the hard one")
    slider.free()


func test_backspace_over_a_hovered_slider_restores_the_built_value() -> void:
    var slider := FactorSlider.new()
    slider.min_value = 0.0
    slider.max_value = 100.0
    slider.value = 42.0
    slider._ready()

    slider.value = 90.0
    slider._on_mouse_entered()
    slider._unhandled_key_input(_backspace())

    assert_eq(slider.value, 42.0, "Backspace restored the value the slider was built with")
    slider.free()


## `has_focus()` answers the same question `_hovered` does here, so a slider
## that somehow does hold keyboard focus without the pointer over it is not
## left out. A `SubViewport` under `EventBus`, the live autoload, rather than
## a bare `Window`, which the offscreen runner never adds to the tree
## (adding one there hangs the run).
func test_backspace_over_a_focused_slider_restores_the_built_value() -> void:
    var host := Node.new()
    host.name = "FactorSliderFocusTestHost"
    EventBus.add_child(host)
    var viewport := SubViewport.new()
    host.add_child(viewport)

    var slider := FactorSlider.new()
    slider.value = 12.0
    slider.focus_mode = Control.FOCUS_ALL
    viewport.add_child(slider)
    slider.value = 77.0

    slider.grab_focus()
    assert_eq(viewport.gui_get_focus_owner(), slider, "the slider really holds the focus")
    slider._unhandled_key_input(_backspace())

    assert_eq(slider.value, 12.0, "a focused slider answers Backspace the same as a hovered one")
    host.free()


func test_backspace_over_an_unhovered_unfocused_slider_does_nothing() -> void:
    var slider := FactorSlider.new()
    slider.value = 10.0
    slider._ready()
    slider.value = 55.0

    slider._unhandled_key_input(_backspace())

    assert_eq(slider.value, 55.0, "neither hovered nor focused, so Backspace is somebody else's")
    slider.free()


## A brush slider on the bar is built with a range and no value, so what
## it held at `_ready()` was its range's floor and Backspace over Flow put the
## brush at nought. A default given after `_ready()` is what Backspace answers,
## and a slider nobody gave one keeps answering what it was built with.
func test_backspace_puts_back_the_default_given_after_ready_and_not_the_built_value() -> void:
    var slider := FactorSlider.new()
    slider.min_value = 0.0
    slider.max_value = 100.0
    slider.value = 0.0
    slider._ready()
    slider.default_value = 50.0

    slider.value = 80.0
    slider._on_mouse_entered()
    slider._unhandled_key_input(_backspace())
    assert_eq(slider.value, 50.0, "Backspace put back the default and not the 0 held at _ready")

    slider.default_value = 30.0
    slider.value = 10.0
    slider._unhandled_key_input(_backspace())
    assert_eq(slider.value, 30.0, "and a default given again moves what Backspace answers")
    slider.free()


func test_a_slider_with_no_default_given_still_answers_the_built_value() -> void:
    var slider := FactorSlider.new()
    slider.min_value = 0.0
    slider.max_value = 100.0
    slider.value = 42.0
    slider._ready()
    assert_true(is_nan(slider.default_value), "No caller has said what the default is")

    slider.value = 90.0
    slider._on_mouse_entered()
    slider._unhandled_key_input(_backspace())
    assert_eq(slider.value, 42.0, "so a dialog's or a settings page's slider keeps the value it was built with")
    slider.free()


func test_a_reset_to_a_given_default_announces_the_move() -> void:
    var slider := FactorSlider.new()
    slider.min_value = 0.0
    slider.max_value = 1.0
    slider.value = 0.0
    slider._ready()
    slider.default_value = 0.5
    slider.value = 0.9
    var heard: Array[float] = []
    slider.value_changed.connect(func(v: float) -> void: heard.append(v))

    slider._on_mouse_entered()
    slider._unhandled_key_input(_backspace())

    assert_eq(heard.size(), 1, "The reset says it moved once, which is what writes it to the tool")
    assert_eq(heard[0], 0.5, "and says where it moved to")
    slider.free()


## The text field commits its own edit on Backspace, which is what a text
## field has always done, and the slider's own reset has to stay out of it.
## The visible flag `start_editing` sets is read directly rather than called,
## because grabbing the field's real focus needs a live tree the other two
## sliders in this file do without.
func test_backspace_while_editing_the_text_field_is_left_alone() -> void:
    var slider := FactorSlider.new()
    slider.value = 5.0
    slider._ready()
    slider.value = 20.0
    slider._on_mouse_entered()
    slider._line_edit.visible = true

    slider._unhandled_key_input(_backspace())

    assert_eq(slider.value, 20.0, "the text field owns Backspace while it is open")
    slider.free()


## `sync()` in `ToolOptionControls` mirrors a tool's current setting onto a
## shared slider through `set_value_no_signal`, one node reused across every
## tool that declares the key. If that mirror moved the remembered default,
## Backspace would go silent the moment anything else refreshed the bar.
func test_set_value_no_signal_does_not_move_the_remembered_default() -> void:
    var slider := FactorSlider.new()
    slider.value = 5.0
    slider._ready()

    slider.set_value_no_signal(80.0)
    slider._on_mouse_entered()
    slider._unhandled_key_input(_backspace())

    assert_eq(slider.value, 5.0, "a mirrored value is not a rebuild, so Backspace still answers the original")
    slider.free()


## A geometric drag gives every octave of size the same room. The claim is
## that equal steps of the box are equal *ratios* of size rather than equal
## distances: on the Size row the middle of the box is the geometric mean of a
## tenth of a pixel and the whole document, not their average, and each quarter
## of the box multiplies the size by the same factor.
##
## The Size row's own range, a fraction of a 1080-tall document, from a tenth of
## a pixel to the whole of it, over a box of four hundred pixels so a quarter of
## it is a hundred.
func test_a_geometric_drag_steps_by_a_ratio_rather_than_a_distance() -> void:
    var slider := FactorSlider.new()
    slider.logarithmic = true
    slider.min_value = 0.001
    slider.max_value = 1.0
    slider.step = 0.0
    slider._ready()
    slider.size = Vector2(400.0, 18.0)

    slider._update_from_mouse_x(100.0)
    var quarter := slider.value
    slider._update_from_mouse_x(200.0)
    var half := slider.value
    slider._update_from_mouse_x(400.0)
    var top := slider.value

    # Four equal steps of the box over a factor of a thousand, so one step is
    # the fourth root of it: 1000 to the nought point two five, 5.6234.
    assert_almost_eq(
        quarter / slider.min_value,
        pow(1000.0, 0.25),
        1e-4,
        "One quarter of the box multiplies the size by a thousand's fourth root"
    )
    assert_almost_eq(half / quarter, pow(1000.0, 0.25), 1e-4, "and the next quarter multiplies it by that same factor")
    assert_almost_eq(top / slider.min_value, 1000.0, 1e-4, "The whole box is the whole factor")
    assert_almost_eq(half, sqrt(0.001 * 1.0), 1e-6, "The middle of the box is the geometric mean of the ends, not their average")
    slider.free()


## A linear slider is untouched by any of it: the same quarter and half are the
## same distances, which is what every other row in the tree still wants.
func test_a_linear_drag_is_still_the_fraction_it_was() -> void:
    var slider := FactorSlider.new()
    slider.min_value = 0.0
    slider.max_value = 1.0
    slider.step = 0.0
    slider._ready()
    slider.size = Vector2(400.0, 18.0)

    slider._update_from_mouse_x(100.0)
    assert_almost_eq(slider.value, 0.25, 1e-4, "A quarter of the box is a quarter of the range")
    slider._update_from_mouse_x(200.0)
    assert_almost_eq(slider.value, 0.5, 1e-4, "and the middle is the middle")
    slider.free()


## The fill reads the same curve the drag does, so the bar is half full at
## the box's middle on a geometric row rather than at the average value, and a
## size above the geometric mean draws past half.
func test_the_fill_follows_the_geometric_curve() -> void:
    var slider := FactorSlider.new()
    slider.logarithmic = true
    slider.min_value = 0.001
    slider.max_value = 1.0
    slider._ready()

    assert_almost_eq(slider.ratio_of_value(sqrt(0.001), 1.0), 0.5, 1e-4, "The geometric mean sits at the middle of the box")
    assert_almost_eq(slider.ratio_of_value(0.001, 1.0), 0.0, 1e-4, "the floor at the left end")
    assert_almost_eq(slider.ratio_of_value(1.0, 1.0), 1.0, 1e-4, "and the ceiling at the right")
    assert_true(slider.ratio_of_value(0.1, 1.0) > 0.5, "A size above the mean fills past half the bar")
    slider.free()


## A geometric row's step is a proportion, so a typed value below one pixel
## survives it. The Size row's floor is a tenth of a pixel and 0.5
## has to be reachable by typing: an absolute step of a thousandth
## rounds the stored fraction of a half pixel to nought, and the floor then puts
## it back at a whole pixel. The step is read as a fraction of the value instead.
func test_a_geometric_row_keeps_a_typed_value_below_one_pixel() -> void:
    var slider := FactorSlider.new()
    slider.logarithmic = true
    # The Size row's own range, the machine's floor and ceiling, so the test
    # measures the row rather than a range that merely resembles it.
    slider.min_value = ToolMachine.BRUSH_RADIUS_MIN
    slider.max_value = ToolMachine.BRUSH_RADIUS_MAX
    slider.step = 0.001
    slider.display_value_multiplier = 1080.0
    slider.prefix = "Radius: "
    slider.suffix = "px"
    slider.decimal_places = 2
    # The Size row is the one row that asks for the trim, and
    # this test is that row: without the line the half pixel reads "0.50 px".
    slider.trim_trailing_zeros = true
    slider._ready()

    # What a painter types for a half-pixel brush on a 1080-tall document.
    slider._line_edit.visible = true
    slider._line_edit.text = "0.5"
    slider._stop_editing()

    assert_almost_eq(
        slider.value * 1080.0, 0.5, 0.01, "Half a pixel typed is half a pixel stored, and not rounded up to a whole one"
    )
    assert_eq(slider._label.text, "Radius: 0.5 px", "and the row says half a pixel rather than a rounded one")

    # Under the floor, which is the smallest size that still paints a dab.
    slider._line_edit.visible = true
    slider._line_edit.text = "0.01"
    slider._stop_editing()
    assert_almost_eq(
        slider.value, ToolMachine.BRUSH_RADIUS_MIN, 1e-9, "and a size under the floor lands on it rather than on a whole pixel"
    )
    assert_true(ToolMachine.BRUSH_RADIUS_MIN * 1080.0 < 1.0, "The floor is under a pixel, so the row reaches sizes it could not")
    slider.free()


## The floor itself: a Size smaller than 1 should be allowed. It was a thousandth of the canvas, 1.08
## pixels on the default document, so the row's own minimum drew as "1 px" and
## nothing below a pixel was reachable by any route.
func test_the_floor_is_under_one_pixel_on_the_default_document() -> void:
    var pixels: float = ToolMachine.BRUSH_RADIUS_MIN * 1080.0
    var diameter: float = pixels * 2.0
    assert_true(pixels < 1.0, "A tenth of a pixel's radius is under a pixel: %.4f" % pixels)
    # The dab the floor has to clear, `StateBrush.MIN_DAB_DIAMETER`, is a
    # module's constant and a skeleton suite cannot name a class from a
    # submodule, so it is a literal with the class said here. 0.2 of a
    # pixel across is the smallest dab the walk paints at all.
    assert_true(diameter >= 0.2, "and a diameter of %.4f still paints, since the dab is dropped under 0.2" % diameter)


## The trailing noughts are the row's precision rather than a number. Two
## decimals are what let a half pixel show, and without the trim every whole
## size a painter uses would read "25.00 px".
func test_a_whole_size_still_reads_whole_under_two_decimals() -> void:
    assert_eq(FactorSlider._trim_trailing_zeros("25.00"), "25", "Two decimals on a whole number leave the number")
    assert_eq(FactorSlider._trim_trailing_zeros("0.50"), "0.5", "and one trailing nought goes with the point")
    assert_eq(FactorSlider._trim_trailing_zeros("1080.00"), "1080", "a wide whole size too")
    assert_eq(FactorSlider._trim_trailing_zeros("0.05"), "0.05", "while a significant nought is kept")
    assert_eq(FactorSlider._trim_trailing_zeros("1080"), "1080", "and a number with no point at all is left alone")


## The trim is the row's to ask for rather than every row's. Applied
## to every slider, the export dialog's quality row, whose two
## decimals are the number a painter reads rather than a scale, dropped them and
## a full quality read "1" where it read "1.00".
func test_a_row_that_did_not_ask_keeps_the_decimals_it_declares() -> void:
    var slider := FactorSlider.new()
    slider.min_value = 0.0
    slider.max_value = 1.0
    slider.value = 1.0
    slider.decimal_places = 2
    slider._ready()
    assert_eq(slider._label.text, "1.00", "A two-decimal row shows two decimals when it did not ask for the trim")

    slider.trim_trailing_zeros = true
    assert_eq(slider._label.text, "1", "and drops them when it does")
    slider.free()


## A drag with Shift held moves a tenth of what a plain one moves, from where
## the drag stands, since one pixel of hand was worth three per
## cent of Size and nothing finer. Pressing Shift mid-drag does not jump the
## value to a tenth of the pointer's place, and letting go of it does not
## jump back to the pointer, so the hand can go fine and coarse in one drag.
func test_a_shift_drag_moves_a_tenth_of_a_plain_one() -> void:
    var slider := _hundred_wide()

    slider._gui_input(_press(100.0))
    assert_almost_eq(slider.value, 25.0, 1e-4, "A plain press puts the value under the pointer")
    slider._gui_input(_motion(140.0))
    var plain := slider.value - 25.0
    assert_almost_eq(plain, 10.0, 1e-4, "and forty pixels of plain drag move it ten")

    slider._gui_input(_motion(140.0, true))
    assert_almost_eq(slider.value, 35.0, 1e-4, "Shift going down where the pointer stands moves nothing")
    slider._gui_input(_motion(180.0, true))
    var fine := slider.value - 35.0
    assert_almost_eq(fine, plain * SaSliderDrag.FINE_RATE, 1e-4, "and the same forty pixels with Shift move a tenth as far")

    slider._gui_input(_motion(220.0))
    assert_almost_eq(slider.value, 46.0, 1e-4, "Letting go of Shift goes on at the plain rate from there, not from the pointer")
    slider._gui_input(_release(220.0))
    slider.free()


## A press with Shift held starts the fine drag where the value is, rather
## than jumping to the pointer first.
func test_a_press_with_shift_held_does_not_jump() -> void:
    var slider := _hundred_wide()
    slider.value = 60.0

    slider._gui_input(_press(40.0, true))
    assert_almost_eq(slider.value, 60.0, 1e-4, "A Shift press far from the value leaves it where it was")
    slider._gui_input(_motion(80.0, true))
    assert_almost_eq(slider.value, 61.0, 1e-4, "and forty pixels with Shift move it one")
    slider._gui_input(_release(80.0))
    slider.free()


## On the geometric Radius row the tenth is a tenth of the box's travel, so
## the fine drag is a tenth of the ratio a plain one multiplies the size by.
func test_a_shift_drag_on_the_radius_row_is_a_tenth_of_the_travel() -> void:
    var slider := _radius_row(25.0)
    var top := slider.drag_max()

    slider._gui_input(_press(200.0))
    var at_press := slider.ratio_of_value(slider.value, top)
    slider._gui_input(_motion(240.0))
    var plain := slider.ratio_of_value(slider.value, top) - at_press
    assert_almost_eq(plain, 0.1, 1e-4, "Forty pixels of a four hundred pixel box are a tenth of the travel")

    var before_fine := slider.ratio_of_value(slider.value, top)
    slider._gui_input(_motion(240.0, true))
    slider._gui_input(_motion(280.0, true))
    var fine := slider.ratio_of_value(slider.value, top) - before_fine
    assert_almost_eq(fine, 0.01, 1e-4, "and with Shift a hundredth of it")
    slider._gui_input(_release(280.0))
    slider.free()


## Left and Right step the value by one displayed unit over a hovered slider,
## ten with Shift: a per cent on an Opacity row.
func test_an_arrow_over_the_slider_steps_one_displayed_unit() -> void:
    var slider := FactorSlider.new()
    slider.min_value = 0.0
    slider.max_value = 1.0
    slider.step = 0.01
    slider.normalized_display = true
    slider.decimal_places = 0
    slider.suffix = "%"
    slider.value = 0.5
    slider._ready()
    slider._on_mouse_entered()

    slider._unhandled_key_input(_key(KEY_RIGHT))
    assert_almost_eq(slider.value, 0.51, 1e-6, "Right over Opacity is one per cent more")
    slider._unhandled_key_input(_key(KEY_LEFT))
    slider._unhandled_key_input(_key(KEY_LEFT))
    assert_almost_eq(slider.value, 0.49, 1e-6, "and Left one per cent less")
    slider._unhandled_key_input(_key(KEY_RIGHT, true))
    assert_almost_eq(slider.value, 0.59, 1e-6, "Shift and Right are ten per cent")
    assert_eq(slider._label.text, "59 %", "and the label says so")
    slider.free()


## On the Radius row the unit is a pixel of the document, though the row
## shows two decimals, because its decimals are a scale rather than a
## precision. A hundredth of a pixel a press would be no step a painter sees.
func test_an_arrow_over_the_radius_row_steps_a_pixel() -> void:
    var slider := _radius_row(25.0)
    slider._on_mouse_entered()

    slider._unhandled_key_input(_key(KEY_RIGHT))
    assert_almost_eq(slider.value * 1080.0, 26.0, 1e-3, "Right over Radius is one pixel more")
    assert_eq(slider._label.text, "Radius: 26 px", "and reads as a whole pixel")
    slider._unhandled_key_input(_key(KEY_LEFT, true))
    assert_almost_eq(slider.value * 1080.0, 16.0, 1e-3, "Shift and Left are ten pixels less")
    slider.free()


## With the pointer elsewhere an arrow is somebody else's: the canvas's, a
## list's, a text field's.
func test_an_arrow_with_the_pointer_elsewhere_moves_nothing() -> void:
    var slider := _hundred_wide()
    slider.value = 50.0

    slider._unhandled_key_input(_key(KEY_RIGHT))
    assert_almost_eq(slider.value, 50.0, 1e-6, "An arrow over nothing leaves the slider alone")
    slider._on_mouse_entered()
    slider._on_mouse_exited()
    slider._unhandled_key_input(_key(KEY_LEFT, true))
    assert_almost_eq(slider.value, 50.0, 1e-6, "and so does one after the pointer has left it")
    slider.free()


## An arrow with Ctrl is a chord, left for a shortcut, and an arrow while the
## field is open moves the field's caret rather than the value.
func test_a_chord_and_an_open_field_keep_their_arrows() -> void:
    var slider := _hundred_wide()
    slider.value = 50.0
    slider._on_mouse_entered()

    slider._unhandled_key_input(_key(KEY_RIGHT, false, true))
    assert_almost_eq(slider.value, 50.0, 1e-6, "Ctrl and Right are not a step")
    slider._line_edit.visible = true
    slider._unhandled_key_input(_key(KEY_RIGHT))
    assert_almost_eq(slider.value, 50.0, 1e-6, "and an open field keeps its arrows")
    slider.free()


## The ends: an arrow stops at the hard ones as a typed number does, and a row
## that wraps comes round. A linear row with a step coarser than its last
## digit steps by the step, or the rounding would put every press back.
func test_an_arrow_stops_at_the_ends_wraps_where_the_row_wraps_and_keeps_the_step() -> void:
    var slider := _hundred_wide()
    slider.value = 99.5
    slider.decimal_places = 0
    slider._on_mouse_entered()
    slider._unhandled_key_input(_key(KEY_RIGHT, true))
    assert_almost_eq(slider.value, 100.0, 1e-6, "Ten more from 99.5 stops at the end")
    slider.free()

    var angle := FactorSlider.new()
    angle.min_value = -180.0
    angle.max_value = 180.0
    angle.step = 1.0
    angle.decimal_places = 0
    angle.wraps = true
    angle.value = 180.0
    angle._ready()
    angle._on_mouse_entered()
    angle._unhandled_key_input(_key(KEY_RIGHT))
    assert_almost_eq(angle.value, -179.0, 1e-6, "Right at 180 degrees comes round to -179")
    angle.free()

    var coarse := FactorSlider.new()
    coarse.min_value = 0.5
    coarse.max_value = 2.0
    coarse.step = 0.05
    coarse.decimal_places = 2
    coarse.value = 1.0
    coarse._ready()
    coarse._on_mouse_entered()
    coarse._unhandled_key_input(_key(KEY_RIGHT))
    assert_almost_eq(coarse.value, 1.05, 1e-6, "A row whose step is five hundredths steps by five hundredths")
    coarse.free()


## A slider at the bottom of its range draws a tick at the start of its
## track, so zero reads as a value and not as a slider switched off, and the tick
## goes once the value is above it and the fill says it instead, because Hardness at 0 read as dimmed.
func test_a_slider_at_zero_draws_a_tick_that_goes_above_it() -> void:
    var slider := _hundred_wide()
    slider.value = 0.0
    var tick := slider.zero_tick()
    assert_true(tick.has_area(), "A slider at zero draws its tick")
    assert_true(tick.position.x < slider.size.x * 0.05, "at the start of the track, x %s" % tick.position.x)
    assert_almost_eq(tick.size.x, float(DockerUtils.px(FactorSlider.ZERO_TICK_WIDTH)), 1e-6, "and a tick wide, not a fill")
    assert_true(tick.end.y < slider.size.y, "short of the box's full height")
    slider.value = 10.0
    assert_false(slider.zero_tick().has_area(), "None once the value is above zero, where the fill says it")
    slider.free()


## The label is edged in the palette's dark rather than shadowed, so white
## holds on the fill and on the track alike, and the edge follows a switch to a
## palette whose text is dark and whose edge is light.
func test_the_label_is_outlined_rather_than_shadowed() -> void:
    var saved := SaTheme.palette_id
    var slider := _hundred_wide()
    var settings := slider._label.label_settings
    assert_true(settings.outline_size > 0, "The label has an outline, %d" % settings.outline_size)
    assert_eq(settings.outline_color, SaTheme.palette.text_shadow, "in the palette's shadow colour")
    assert_eq(settings.shadow_color.a, 0.0, "and no shadow beside it")
    SaTheme.use_named("paper")
    assert_eq(settings.outline_color, SaTheme.palette.text_shadow, "The edge follows a switch to Paper White")
    SaTheme.use_named(saved)
    slider.free()


## A slider given a track gradient draws a thin marker at its value in place
## of the fill, and no zero tick, since the marker says zero as well.
func test_a_track_gradient_trades_the_fill_for_a_marker() -> void:
    var slider := _hundred_wide()
    slider.track_gradient = Gradient.new()
    slider.value = 25.0
    var marker := slider.marker_rect()
    assert_almost_eq(marker.get_center().x, 100.0, 1e-4, "The marker stands at the value, a quarter of the box")
    assert_almost_eq(marker.size.x, float(DockerUtils.px(FactorSlider.MARKER_WIDTH)), 1e-6, "and is thin rather than a fill")
    slider.value = 0.0
    assert_false(slider.zero_tick().has_area(), "A slider with a track draws no tick at zero")
    assert_almost_eq(slider.marker_rect().position.x, 0.0, 1e-6, "and its marker is held inside the box at the start")
    slider.track_gradient = null
    assert_true(slider.zero_tick().has_area(), "Without the track the tick is back")
    slider.free()


## A geometric Size row that shows whole numbers is dragged and clicked onto
## whole numbers. A double click's first click set 39.374103 from the click's
## place on the track, and the number field opened on that.
func test_a_geometric_row_with_no_decimals_lands_on_a_whole_number() -> void:
    var slider := FactorSlider.new()
    slider.logarithmic = true
    slider.min_value = 4.0
    slider.max_value = 2000.0
    slider.step = 1.0
    slider.decimal_places = 0
    slider._ready()
    slider.size = Vector2(400.0, 18.0)
    for x: float in [37.0, 101.0, 163.0, 250.0, 391.0]:
        slider._update_from_mouse_x(x)
        assert_eq(slider.value, roundf(slider.value), "A drag to %s lands on a whole number" % x)
        slider.start_editing()
        assert_eq(
            slider._line_edit.text.to_float(), slider.value, "and the number field opens on it, '%s'" % slider._line_edit.text
        )
        assert_true(slider._line_edit.text.length() - slider._line_edit.text.find(".") <= 2, "with at most one decimal")
        slider._cancel_editing()
    slider.free()
