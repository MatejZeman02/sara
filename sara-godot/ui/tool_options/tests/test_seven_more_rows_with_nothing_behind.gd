## Seven more Preferences > Top Menu Bar rows whose switch moved nothing.
##
## The same defect an earlier fix cured for three names, asked of every row
## the page draws. `stabilizer_amount`, `sample_size`, `sample_merged`, `marquee_shape`,
## `lasso_shape`, `selection_mode` and `wand_tolerance` carried `bar = false`,
## which means `ToolOptionControls.build_for` returns before it makes an entry,
## so the bar had nothing to show or hide. Six of the seven read on from a
## deleted profile, which is the lie in full: a tick already in a switch that
## moves nothing.
##
## They are `bar = true` and in `SaSettingsLayout.DEFAULT_HIDDEN` now, the route
## Hardness, the stabilizer and three earlier rows already took. The general form of
## the assertion lives in
## `ui/top_bar/tests/test_preferences_rows_have_something_behind_them.gd`, which walks
## the order rather than a list of names. What is here is what the seven need
## that the three did not: six of them belong to a tool other than the brush, so
## the bar shows their control only while that tool is active, and a tick in
## Preferences is one of two conditions rather than the only one.
##
## `scenarios/seven-more-rows-with-nothing-behind.json` is the same thing on
## the running app, from a deleted profile.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

## The bar builds from every registered tool's descriptor, which needs a
## machine, a surface and therefore a device.
const REQUIRES_GPU := true

static var scratch_profile: String = SaDataRoot.path("test_f129_rows.cfg")

## The seven, and the tool whose descriptor declares each. `sample_merged` was
## declared twice, by the eyedropper and by the wand, until the eyedropper was given
## a Sample row in its place, so the wand is the one to hold.
## Five are left: `marquee_shape` went with the shape row itself, the rectangle
## and the ellipse being two tools now, and `lasso_shape` the same way when the
## polygon became a tool beside the freehand lasso.
const SEVEN := {
    "stabilizer_amount": &"brush",
    "sample_size": &"eyedropper",
    "sample_merged": &"wand",
    "selection_mode": &"marquee",
    "wand_tolerance": &"wand",
}

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
    _host.name = "F129TestHost"
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


## The defect itself, named seven times rather than counted, so a failure says
## which row went back to promising nothing.
func test_all_seven_have_a_control_behind_them_now() -> void:
    for element: String in SEVEN:
        assert_not_null(_bar.control_for(StringName(element)), "The bar built a control for '%s'" % element)


## The half the filing photographed: six of the seven read on from a deleted
## profile while nothing was behind them. All seven read off now, which is what
## a reduced option is supposed to say.
func test_a_fresh_profile_hides_all_seven() -> void:
    for element: String in SEVEN:
        assert_false(SaSettings.get_element_visible("TopMenuBar", element), "A fresh profile hides '%s'" % element)


## And the reduction is a default rather than a wall: the switch writes, and the
## control it writes about is still the one the bar holds. Asserted through the
## settings the switch writes rather than through the switch, because the page
## is a Window and a test that adds one hangs.
func test_switching_a_row_on_leaves_the_control_in_place() -> void:
    for element: String in SEVEN:
        var control := _bar.control_for(StringName(element))
        SaSettings.set_element_visible("TopMenuBar", element, true)
        assert_true(SaSettings.get_element_visible("TopMenuBar", element), "'%s' is on after the switch" % element)
        assert_not_null(control, "and the control the bar shows for it is still there")
        SaSettings.set_element_visible("TopMenuBar", element, false)
        assert_false(SaSettings.get_element_visible("TopMenuBar", element), "and off again after the second")


## What the three earlier rows did not need. Six of the seven belong to a tool other
## than the brush, and the bar ANDs the profile's visibility with
## `shows_for_active_tool`, so a tick alone does not put the row on the bar. A
## fix that had only flipped the flags would pass every assertion above and
## still leave a painter clicking a switch and seeing nothing move.
func test_a_tool_row_shows_only_while_its_own_tool_is_active() -> void:
    for element: String in SEVEN:
        var owner_id: StringName = SEVEN[element]
        var control := _bar.control_for(StringName(element))
        assert_not_null(control, "'%s' has a control to ask about" % element)
        if control == null:
            continue
        _machine.set_active_tool(&"brush")
        _bar.options.binding.follow(_machine)
        var on_brush := _bar.shows_for_active_tool(control)
        _machine.set_active_tool(owner_id)
        _bar.options.binding.follow(_machine)
        assert_true(_bar.shows_for_active_tool(control), "'%s' has a place while %s is active" % [element, owner_id])
        if owner_id != &"brush":
            assert_false(on_brush, "and none while the brush is, which is why the tick is not the whole story")


## The row a painter reads has to be a name. `SaSettings.element_title` falls
## back to the key when no control answers for the element, so the same flag
## that built nothing also lost the title, and that half is easy to miss.
func test_all_seven_rows_have_a_title_rather_than_a_key() -> void:
    for element: String in SEVEN:
        var title := SaSettings.element_title("TopMenuBar", element)
        assert_false(title == element, "'%s' has a title of its own, not its key: '%s'" % [element, title])
