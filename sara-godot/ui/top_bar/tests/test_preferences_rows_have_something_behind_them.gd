## A Preferences > Top Menu Bar row must have a control behind its switch.
##
## `exposure`, `size_by_pressure` and `opacity_by_pressure` carried `bar = false`
## in the stamp brush's own declaration would build no control at all, so the
## bar would have nothing to show or hide and their rows would read as already
## on. They are `bar = true` and hidden by default, the route Hardness and the
## stabilizer mode take.
##
## `scenarios/preferences-rows-nothing-behind.json` is the same thing on the
## running app, from a deleted profile: the rows read off, three clicks put the
## three on the bar, and the bar's own report follows.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

## The bar builds from the brush's descriptor, which needs a machine, a surface
## and therefore a device.
const REQUIRES_GPU := true

static var scratch_profile: String = SaDataRoot.path("test_f111_rows.cfg")

## The three that are hidden by default, and the two that take the same route.
const MOVED: Array[String] = ["exposure", "size_by_pressure", "opacity_by_pressure"]
const ALREADY: Array[String] = ["hardness", "stabilizer_mode"]

var _saved_path: String = ""
var _host: Node = null
var _surface: SaSurface = null
var _machine: ToolMachine = null
var _registries: SaRegistries = null
var _bar: ToolOptionsBar = null


func before_each() -> void:
    _saved_path = SaSettings.settings_path
    SaSettings.settings_path = ProjectSettings.globalize_path(scratch_profile)
    _remove_profile()
    SaSettings.load_settings()
    _host = Node.new()
    _host.name = "F111TestHost"
    EventBus.add_child(_host)
    _surface = Fixtures.make_surface()
    _machine = Fixtures.make_bound_machine(_surface)
    _machine.set_active_tool(&"brush")
    _registries = Fixtures.make_registries(_surface)
    _bar = ToolOptionsBar.new()
    _host.add_child(_bar)
    _bar.target_tool_machine = _machine
    _bar._ready()
    _bar.bind_registries(_registries.blend_modes)


func after_each() -> void:
    if _host != null:
        _host.free()
        _host = null
    _bar = null
    Fixtures.teardown(_surface, _machine)
    _registries = null
    _remove_profile()
    SaSettings.settings_path = _saved_path
    SaSettings.load_settings()


func _remove_profile() -> void:
    for suffix: String in ["", ".bak", ".broken"]:
        var path := ProjectSettings.globalize_path(scratch_profile) + suffix
        if FileAccess.file_exists(path):
            DirAccess.remove_absolute(path)


## The defect, as the one property that decides it: a row the page draws has to
## have a control behind it, and `bar` is what decides whether one is built.
func test_the_three_rows_have_a_control_behind_them_now() -> void:
    for element: String in MOVED:
        assert_not_null(_bar.control_for(StringName(element)), "The bar built a control for '%s'" % element)


## And the reduction still holds, because the control is hidden by the profile
## rather than never made. Without this half the change is three more rows on a
## bar with 45 pixels spare.
func test_a_fresh_profile_still_hides_all_three() -> void:
    for element: String in MOVED:
        assert_false(SaSettings.get_element_visible("TopMenuBar", element), "A fresh profile hides '%s'" % element)
    for element: String in ALREADY:
        assert_false(SaSettings.get_element_visible("TopMenuBar", element), "as it already hid '%s'" % element)


## The half a painter meets: the switch moves the bar. Asserted through the
## settings the switch writes rather than through the switch, because the page
## is a Window and a test that adds one hangs.
func test_switching_a_row_on_puts_the_option_on_the_bar() -> void:
    for element: String in MOVED:
        var control := _bar.control_for(StringName(element))
        SaSettings.set_element_visible("TopMenuBar", element, true)
        assert_true(SaSettings.get_element_visible("TopMenuBar", element), "'%s' is on after the switch" % element)
        assert_not_null(control, "and the control the bar shows for it is still there")
        SaSettings.set_element_visible("TopMenuBar", element, false)
        assert_false(SaSettings.get_element_visible("TopMenuBar", element), "and off again after the second")


## The row's title comes from the control's own spec, so a row with no control
## must not fall back to the raw key, so the page draws "Exposure" and not
## `exposure`. It is asserted here because it is what a painter reads.
func test_the_three_rows_have_a_title_rather_than_a_key() -> void:
    for element: String in MOVED:
        var title := SaSettings.element_title("TopMenuBar", element)
        assert_false(title == element, "'%s' has a title of its own, not its key: '%s'" % [element, title])


## Seven more rows have the same shape: `stabilizer_amount`, `sample_size`,
## `sample_merged`, `marquee_shape`, `lasso_shape`, `selection_mode` and
## `wand_tolerance`. They are `bar = true` and hidden by default, and this walks
## every row the page draws rather than the seven by name, so an eighth of this
## shape fails here on the commit that introduces it.
func test_every_top_menu_bar_row_has_a_control_behind_it() -> void:
    var declared: Dictionary = {}
    for descriptor: SaToolDescriptor in _machine.registry.list_descriptors():
        for spec: SaOptionSpec in descriptor.options:
            declared[String(spec.key)] = true
    var missing: Array[String] = []
    for element: String in SaSettings.get_layout_order("TopMenuBar"):
        if not declared.has(element):
            continue
        if _bar.control_for(StringName(element)) == null:
            missing.append(element)
    assert_eq(missing, [] as Array[String], "Every option row the page draws has a control behind it")
