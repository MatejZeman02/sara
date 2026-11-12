## A fresh bar carries what a painter uses, with Radius after Opacity.
##
## Grow, Mirror V and the environment view are off a fresh bar, the canvas's
## rotation is off on a tablet where fingers turn it, and the brush's radius
## sits on the right. Opacity follows the erase toggle and Radius follows Opacity on every brush's spec,
## `SaSettingsLayout.DEFAULT_HIDDEN` hides Mirror V and Environment View, and
## its `PLATFORM_HIDDEN` hides Rotation and Reset Rotation on Android alone.
## `scenarios/a-fresh-bar-carries-what-a-painter-uses-with-radius-after-opacity.json`
## is the same bar on the running app.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

## The bar builds from every registered tool's descriptor, which needs a
## machine, a surface and therefore a device.
const REQUIRES_GPU := true

const BAR := "TopMenuBar"

static var scratch_profile: String = SaDataRoot.path("test_fresh_bar.cfg")

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
    _host.name = "U364TestHost"
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


## A layout over a profile of its own, with *platform* taken as the one it runs
## on, which is how a desktop reads what a tablet's fresh bar shows.
func _layout_on(platform: String) -> SaSettingsLayout:
    return SaSettingsLayout.new(SaSettingsFile.new(), SaSettings, platform)


func test_a_fresh_bar_puts_radius_right_of_opacity() -> void:
    var order := SaSettings.get_layout_order(BAR)
    var opacity := order.find("opacity")
    var radius := order.find("radius")
    assert_true(opacity != -1 and radius != -1, "A fresh order names both, opacity at %d and radius at %d" % [opacity, radius])
    assert_eq(radius, opacity + 1, "and Radius stands right after Opacity")
    assert_eq(order.find("eraser_toggled") + 1, opacity, "which stands right after the erase toggle")


func test_a_fresh_bar_hides_mirror_v_and_the_environment_view_and_keeps_mirror_h() -> void:
    assert_false(SaSettings.get_element_visible(BAR, "Mirror V"), "Mirror V is off a fresh bar")
    assert_false(SaSettings.get_element_visible(BAR, "Environment View"), "and so is the environment view")
    assert_true(SaSettings.get_element_visible(BAR, "Mirror H"), "while Mirror H stays")
    assert_true(SaSettings.get_element_visible(BAR, "Radial"), "and Radial too")


func test_android_hides_the_rotation_and_linux_keeps_it() -> void:
    var android := _layout_on("Android")
    var linux := _layout_on("Linux")
    for element: String in ["Rotation", "Reset Rotation"]:
        assert_false(android.get_element_visible(BAR, element), "%s is off a fresh bar on Android" % element)
        assert_true(linux.get_element_visible(BAR, element), "and on a fresh bar on Linux")
        assert_true(android.fresh_hidden(BAR).has(element), "Android's fresh hidden list names %s" % element)
    for element: String in ["Mirror V", "Environment View"]:
        assert_false(android.get_element_visible(BAR, element), "%s is off on Android" % element)
        assert_false(linux.get_element_visible(BAR, element), "and on Linux")


func test_a_painter_who_shows_mirror_v_keeps_it_after_a_restart() -> void:
    SaSettings.set_element_visible(BAR, "Mirror V", true)
    SaSettings.load_settings()
    assert_true(SaSettings.get_element_visible(BAR, "Mirror V"), "Mirror V is still on after the profile is read again")
    SaSettings.set_element_visible(BAR, "Environment View", true)
    SaSettings.load_settings()
    assert_true(SaSettings.get_element_visible(BAR, "Environment View"), "and so is the environment view")


## The Grow that once showed beside the brush is the fill's row, which is
## `bar_own_tool`. Asked here again because a fresh bar must not carry it.
func test_grow_never_shows_beside_the_brush() -> void:
    assert_false(SaSettings.get_element_visible(BAR, "fill_grow"), "Grow is off a fresh bar")
    var grow := _bar.control_for(&"fill_grow")
    assert_not_null(grow, "The bar built the fill's Grow control to ask about")
    if grow == null:
        return
    SaSettings.set_element_visible(BAR, "fill_grow", true)
    for id: StringName in [&"brush", &"eraser"]:
        _machine.set_active_tool(id)
        _bar.options.binding.follow(_machine)
        assert_false(_bar.shows_for_active_tool(grow), "Grow has no place with %s in hand, ticked on or not" % id)
