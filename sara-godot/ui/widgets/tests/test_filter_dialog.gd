## The filter dialog: the six student-facing widgets, the preview and the rerun.
##
## Offscreen and windowless. `SaDialog` is `SaPage` plus a window, and the page
## half is what a suite can hold: the declaration, the widgets, the values, the
## dimming and the coalescing all work with no `Window` in the tree, which
## matters because a `Window` added to the tree maps a real OS window and hangs
## the runner. The window half is a scenario's.
extends "res://tests/test_framework.gd"

const DialogFilter = preload("res://tests/fixtures/modules/dialog-fixture/dialog_filter.gd")

var _dialog: SaDialog = null
var _host: VBoxContainer = null
var _filter: Variant = null


func _declare(ui: SaDialog) -> void:
    ui.title("Every widget")
    ui.preview()
    ui.slider("Radius", 1, 20, 3, {"hard_max": 200})
    ui.checkbox("Invert", false)
    ui.dropdown("Channel", ["All", "Red", "Green"], 0)
    ui.radio("Mode", ["Scale", "Add"], 0)
    ui.color("Tint", Color(1.0, 0.5, 0.25, 1.0))
    ui.button("Reset", Callable())
    ui.apply_cancel()


func _build() -> void:
    _host = VBoxContainer.new()
    _dialog = SaDialog.new(_declare)
    _dialog.declare_rows()
    _dialog.realize(_host)


func _tear_down() -> void:
    if _host != null:
        _host.free()
    _host = null
    _dialog = null


func test_a_dialog_builds_with_every_widget_kind() -> void:
    _build()
    assert_eq(_dialog.dialog_title, "Every widget", "title() names the window")
    assert_eq(_dialog.rows().size(), 9, "nine rows: the preview, its Preview box, six widgets and the two buttons")

    var widgets := {}
    for row in _dialog.rows():
        widgets[_dialog.widget_name(row.key)] = row
    for wanted: String in [
        "preview", "canvas_preview", "slider", "checkbox", "dropdown", "radio", "color", "button", "apply_cancel"
    ]:
        assert_true(widgets.has(wanted), "a %s is on the dialog" % wanted)

    assert_not_null(_dialog.preview_control, "preview() left a preview behind")
    assert_not_null(_dialog.apply_button, "apply_cancel() left an Apply button behind")
    assert_not_null(_dialog.cancel_button, "and a Cancel button")
    assert_true((widgets["slider"] as SaPageRow) is SaSlider, "the slider is the SaSlider a student declares")
    assert_true(_dialog.row(&"radius").control is FactorSlider, "and it draws Sara's own slider")
    assert_true(_dialog.row(&"invert").control is CheckButton, "a checkbox draws a CheckButton")
    assert_true(_dialog.row(&"channel").control is SaChoiceButton, "a dropdown draws Sara's own choice button")
    assert_true(_dialog.row(&"tint").control is ColorPickerButton, "a colour row draws the colour button")
    _tear_down()


func test_a_widget_is_a_member_the_filter_reads_back() -> void:
    _build()
    var radius := _dialog.row(&"radius") as SaSlider
    assert_almost_eq(float(radius.value), 3.0, 0.001, "a slider starts at its default")
    assert_eq(radius.bound_to(), "itself", "and holds its own value, because a student has no settings object")
    assert_almost_eq(radius.min_value, 1.0, 0.001, "the soft floor is the hard floor when no option says otherwise")
    assert_almost_eq(radius.max_value, 200.0, 0.001, "the option's hard_max is the hard ceiling")
    assert_almost_eq(radius.soft_max, 20.0, 0.001, "and the argument is the soft one the drag stops at")
    assert_almost_eq(radius.step_value, 1.0, 0.001, "three numbers written as integers make a whole step")
    assert_eq(radius.decimal_places, 0, "and no decimals, so a radius reads 3 rather than 3.0")

    var slider := radius.control as FactorSlider
    slider.value = 9.0
    slider.value_changed.emit(slider.value)
    assert_almost_eq(float(radius.value), 9.0, 0.001, "moving the control writes the widget the filter reads")
    _tear_down()


## The step and the decimals come from how the three numbers were
## **written**, not from whether they happen to have a fraction.
##
## `1, 20, 3` is a count and `0.0, 1.0, 1.0` is a fraction, and a typed `float`
## parameter threw the difference away at the door: a strength between nought
## and one drew a control with two positions on it, which is a checkbox
## somebody spelled as a slider.
func test_the_step_is_read_from_how_the_numbers_were_written() -> void:
    var page := SaDialog.new()
    var host := VBoxContainer.new()

    var counted := page.slider("Radius", 1, 20, 3)
    assert_almost_eq(counted.step_value, 1.0, 0.001, "integers ask for a whole step")
    assert_eq(counted.decimal_places, 0, "and for no decimals")

    var fraction := page.slider("Strength", 0.0, 1.0, 1.0)
    assert_almost_eq(fraction.step_value, SaSlider.FINE_STEP, 0.0001, "decimals ask for a fine one")
    assert_eq(fraction.decimal_places, SaSlider.FINE_DECIMALS, "and for decimals to show it")

    var mixed := page.slider("Mixed", 1, 20, 3.5)
    assert_almost_eq(mixed.step_value, SaSlider.FINE_STEP, 0.0001, "one fraction among them is a fraction")

    var told := page.slider("Told", 0.0, 1.0, 1.0, {"step": 0.05, "decimals": 2})
    assert_almost_eq(told.step_value, 0.05, 0.0001, "and the options still win over both")
    assert_eq(told.decimal_places, 2, "in the decimals as well")

    page.realize(host)
    var control := fraction.control as FactorSlider
    assert_almost_eq(control.step, SaSlider.FINE_STEP, 0.0001, "which is what the control is built with")
    host.free()


func test_every_widget_writes_its_own_value() -> void:
    _build()
    var invert := _dialog.row(&"invert")
    (invert.control as CheckButton).button_pressed = true
    assert_eq(invert.value, true, "the checkbox holds what the control wrote")

    var channel := _dialog.row(&"channel")
    assert_true((channel.control as SaChoiceButton).pick_row(2), "the third row takes a press")
    assert_eq(channel.value, 2, "the dropdown holds the id it selected")

    var mode := _dialog.row(&"mode")
    var picks := mode.control.find_children("*", "CheckBox", true, false)
    assert_eq(picks.size(), 2, "the radio drew one button per choice")
    (picks[1] as CheckBox).pressed.emit()
    assert_eq(mode.value, 1, "and pressing the second writes its id")

    var tint := _dialog.row(&"tint")
    var picker := tint.control as ColorPickerButton
    picker.color = Color("#00ff80ff")
    picker.color_changed.emit(picker.color)
    assert_eq(tint.value, Color("#00ff80ff"), "the colour row holds what was picked")
    _tear_down()


func test_two_widgets_moved_in_one_frame_cost_one_run() -> void:
    _build()
    var counted := [0]
    _dialog.rerun.connect(func() -> void: counted[0] += 1)

    (_dialog.row(&"invert").control as CheckButton).button_pressed = true
    (_dialog.row(&"channel").control as SaChoiceButton).pick_row(1)

    assert_true(_dialog.rerun_pending, "both changes asked for a rerun")
    assert_eq(counted[0], 0, "and neither ran on its own, because the frame has not ended")
    _dialog.flush_rerun()
    assert_eq(counted[0], 1, "the frame boundary runs it once")
    assert_eq(_dialog.runs, 1, "and the dialog counts one run")
    assert_false(_dialog.rerun_pending, "with nothing left pending")

    _dialog.flush_rerun()
    assert_eq(counted[0], 1, "a second flush with nothing pending runs nothing")
    _tear_down()


func test_apply_and_cancel_are_the_two_buttons_every_filter_has() -> void:
    _build()
    var seen := {"applied": 0, "cancelled": 0}
    _dialog.applied.connect(func() -> void: seen["applied"] += 1)
    _dialog.cancelled.connect(func() -> void: seen["cancelled"] += 1)
    _dialog.apply_button.pressed.emit()
    _dialog.cancel_button.pressed.emit()
    assert_eq(seen["applied"], 1, "Apply says so")
    assert_eq(seen["cancelled"], 1, "and Cancel says so")
    assert_eq(_dialog.runs, 0, "and neither is a widget, so neither asked for a rerun")
    _tear_down()


func test_the_preview_holds_the_last_texture_shown() -> void:
    _build()
    var described: Dictionary = _dialog.preview_control.describe()
    assert_eq(int(described["shows"]), 0, "a fresh preview has been shown nothing")
    assert_false(bool(described["holds_texture"]), "and holds no texture")

    _dialog.show_texture(null, Rect2i(10, 20, 30, 40))
    described = _dialog.preview_control.describe()
    assert_eq(described["rect"], [10, 20, 30, 40], "a show records the rectangle it covers")
    assert_eq(int(described["shows"]), 0, "and a null texture is not a show, it is a clear")
    _tear_down()


func test_the_dialog_says_what_it_is() -> void:
    _build()
    _dialog.flush_rerun()
    var described := _dialog.describe()
    assert_eq(String(described["title"]), "Every widget", "the description carries the title")
    assert_eq(int(described["rows"]), 9, "and the row count")
    assert_true(described.has("preview"), "and what the preview is showing")

    var by_key := {}
    for block: Dictionary in described["sections"] as Array:
        for row: Dictionary in block["rows"] as Array:
            by_key[String(row["key"])] = row
    assert_eq(String((by_key["radius"] as Dictionary)["widget"]), "slider", "a row says the widget that declared it")
    assert_eq(String((by_key["radius"] as Dictionary)["kind"]), "custom", "beside the row kind the page layer draws")
    assert_almost_eq(float((by_key["radius"] as Dictionary)["soft_max"]), 20.0, 0.001, "and a slider says its soft ceiling")
    assert_eq(String((by_key["invert"] as Dictionary)["widget"]), "checkbox", "a checkbox says so")
    assert_eq(String((by_key["invert"] as Dictionary)["kind"]), "toggle", "and is the page layer's toggle row")
    _tear_down()


func test_a_filter_written_the_way_the_spec_prints_one_builds() -> void:
    _filter = DialogFilter.new()
    _host = VBoxContainer.new()
    _dialog = SaDialog.new()
    _filter.build(_dialog)
    _dialog.realize(_host)

    assert_eq(_filter.built, 1, "the filter's build ran once")
    assert_eq(_dialog.dialog_title, "Dialog Fixture Tint", "and named the window")
    assert_not_null(_filter.amount, "the member it declared in build is there to read in run")
    assert_almost_eq(float(_filter.amount.value), 1.0, 0.001, "at the default it declared")

    _filter.reset()
    assert_almost_eq(float(_filter.amount.value), 1.0, 0.001, "and its button writes the same member")
    _tear_down()
    _filter = null


func test_a_dialog_that_declared_no_preview_shows_nothing_and_does_not_die() -> void:
    _host = VBoxContainer.new()
    _dialog = SaDialog.new()
    _dialog.slider("Radius", 1, 20, 3)
    _dialog.realize(_host)
    _dialog.show_texture(null, Rect2i())
    assert_null(_dialog.preview_control, "no preview was declared")
    assert_eq((_dialog.describe()["preview"] as Dictionary).size(), 0, "and the description says so rather than guessing")
    _tear_down()
