## The stabilizer's quick toggle on the tool options bar.
##
## The item is small and the two things worth asserting are not the button: that
## the toggle puts back the mode the painter last had rather than the default,
## and that the dropdown being off the bar is a profile default a painter can
## reverse rather than a false compiled into the base module.
##
## Built detached and `_ready()`ed by hand, the way `test_top_bar_rows.gd` does.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

## The bar builds its controls from the tools' descriptors, and a machine with
## the built-in tools needs a surface, which needs a device.
const REQUIRES_GPU := true

var _surface: SaSurface = null
var _machine: ToolMachine = null


func after_each() -> void:
    if _machine != null:
        Fixtures.teardown(_surface, _machine)
        _surface = null
        _machine = null


func _bar() -> ToolOptionsBar:
    if _machine == null:
        _surface = Fixtures.make_surface()
        _machine = Fixtures.make_bound_machine(_surface)
    var bar := ToolOptionsBar.new()
    bar.target_tool_machine = _machine
    bar._ready()
    return bar


## The toggle exists, is a layout element of its own, and starts where the
## brush's own value is.
func test_the_toggle_is_a_row_of_its_own_and_starts_off() -> void:
    var bar := _bar()
    assert_not_null(bar.stabilizer_btn, "The bar carries a stabilizer toggle")
    assert_true(bar.layout_elements().has(ToolOptionsBar.ELEMENT_STABILIZER), "as a layout element of its own")
    assert_false(bar.stabilizer_btn.button_pressed, "and it starts off, because the brush does")
    var order: Array = SaSettings.get_layout_order("TopMenuBar")
    var sentinel := order.find(SaSettings.ROW_SENTINEL)
    assert_true(order.find(ToolOptionsBar.ELEMENT_STABILIZER) > sentinel, "It sits after the sentinel, beside the symmetry three")
    bar.free()


## Off is No Stabilizer and on is whichever mode was last chosen, so a toggle
## cannot silently turn Rope into Average.
func test_the_toggle_puts_back_the_mode_that_was_last_on() -> void:
    var bar := _bar()
    var settings: Resource = bar._get_active_brush_settings()
    assert_not_null(settings, "The brush has settings to write")

    bar.stabilizer_btn.toggled.emit(true)
    assert_eq(
        int(settings.stabilizer_mode), ToolOptionsBar.DEFAULT_STABILIZER_MODE, "With no choice made yet it turns on Average"
    )
    bar.stabilizer_btn.toggled.emit(false)
    assert_eq(int(settings.stabilizer_mode), 0, "and off is No Stabilizer")

    # The other surface chose Rope, which reaches the bar as a written option.
    bar.show_written_option(&"stabilizer_mode", 2)
    assert_true(bar.stabilizer_btn.button_pressed, "A mode written elsewhere presses the toggle")
    bar.stabilizer_btn.toggled.emit(false)
    bar.stabilizer_btn.toggled.emit(true)
    assert_eq(int(settings.stabilizer_mode), 2, "and turning it off and on again puts Rope back rather than Average")
    bar.free()


## The dropdown is off a fresh bar by a profile default rather than by
## `bar = false` in the base module, where a false
## there means the control is never built, so Preferences has nothing to offer.
func test_the_dropdown_is_hidden_by_a_setting_rather_than_absent() -> void:
    var bar := _bar()
    assert_true(bar.layout_elements().has(&"stabilizer_mode"), "The dropdown is built on the bar")
    assert_false(SaSettings.get_element_visible("TopMenuBar", "stabilizer_mode"), "and a fresh profile hides it")
    assert_false(
        SaSettings.get_element_visible("TopMenuBar", "stabilizer_amount"),
        "with Smoothing beside it, since one without the other says half a thing"
    )

    SaSettings.set_element_visible("TopMenuBar", "stabilizer_mode", true)
    assert_true(SaSettings.get_element_visible("TopMenuBar", "stabilizer_mode"), "and one tick in Preferences shows it")
    SaSettings.set_element_visible("TopMenuBar", "stabilizer_mode", false)
    bar.free()
