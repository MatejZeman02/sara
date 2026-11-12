## A press on the top bar's Focus Mode button hides the open
## dockers and a second brings the same ones back, the button stays on the bar
## while they are hidden, and it follows a Tab.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The bar is built the way main builds it, at the
## width of a tablet's screen. The toggle bound to it is what
## `MainDockers.toggle_all_dockers` runs on a Tab, `SaFocusMode.toggle` over the
## docker table, since the table's store and host are a whole main window's.
## The windows are detached, as `test_focus_mode.gd`'s are and for its reason:
## a `Window` added to the tree of a headless run hangs it.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

## The bar's controls come from the tools' descriptors, and building one needs
## a machine with the built-in tools, which needs a device.
const REQUIRES_GPU := true

## The logical width of a tablet's screen, a Surface's, at the
## scale Sara opens it with.
const TABLET_WIDTH := 1368.0

## The scratch profile, absent before each test, so the bar is a fresh one.
static var scratch_profile: String = SaDataRoot.path("test_focus_button_profile.cfg")

var _saved_path: String
var _surface: SaSurface
var _machine: ToolMachine
var _host: Node
var _focus: SaFocusMode
var _table: Array = []


func before_each() -> void:
    SaFocusMode.leave()
    _saved_path = SaSettings.settings_path
    SaSettings.settings_path = ProjectSettings.globalize_path(scratch_profile)
    _remove_profile()
    SaSettings.load_settings()
    _surface = Fixtures.make_surface()
    _machine = Fixtures.make_bound_machine(_surface)
    _machine.set_active_tool(&"brush")
    # Parented to an autoload rather than to the root, because the runner calls
    # a suite from its own `_ready`.
    _host = Node.new()
    _host.name = "U834Host"
    EventBus.add_child(_host)
    _focus = SaFocusMode.new()
    _host.add_child(_focus)
    _table = []
    for state: Array in [["ColorDocker", true], ["LayersDocker", true], ["BrushPresetsDocker", false]]:
        var window := Window.new()
        window.name = state[0]
        window.visible = state[1]
        _table.append({"id": state[0], "node": window})


## The run's own profile is put back as it was, since a later suite reads the
## bar it leaves.
func after_each() -> void:
    SaFocusMode.leave()
    for config: Dictionary in _table:
        (config["node"] as Window).free()
    _table = []
    _host.free()
    Fixtures.teardown(_surface, _machine)
    _remove_profile()
    SaSettings.settings_path = _saved_path
    SaSettings.load_settings()


func _remove_profile() -> void:
    for suffix: String in ["", ".bak", ".broken"]:
        var path := ProjectSettings.globalize_path(scratch_profile) + suffix
        if FileAccess.file_exists(path):
            DirAccess.remove_absolute(path)


## Tab, as `MainDockers.toggle_all_dockers` runs it.
func _tab() -> void:
    _focus.toggle(_table)


## A bar with its tool options, the way main builds them, in the tree, *width*
## wide, and handed Tab's toggle as `bind_commands` hands it.
func _bar(width: float) -> TopMenuBar:
    var options := ToolOptionsBar.new()
    options.target_tool_machine = _machine
    options._ready()
    var bar := TopMenuBar.new()
    bar.add_tool_options(options)
    _host.add_child(bar)
    bar.set_anchor(SIDE_RIGHT, 0.0)
    bar.size.x = width
    bar.apply_layout_settings()
    bar.focus_mode_row.bind(_tab)
    return bar


func _button(bar: TopMenuBar) -> Button:
    return bar.rows.elements().get(SaTopBarFocusMode.ELEMENT) as Button


## A press as the pointer gives it: the button flips itself and says so.
func _press(button: Button) -> void:
    button.button_pressed = not button.button_pressed
    SaTopBarFocusMode.follower_of(button).sync()


func _shown() -> Dictionary:
    var out := {}
    for config: Dictionary in _table:
        out[config["id"]] = (config["node"] as Window).visible
    return out


## The first clause: a press turns the mode on and hides what was open, a second
## shows the same ones and no other, and the button is held down while it is on.
func test_a_press_hides_the_open_dockers_and_a_second_brings_them_back() -> void:
    var bar := _bar(TABLET_WIDTH)
    var button := _button(bar)
    assert_not_null(button, "The bar has the Focus Mode button")
    if button == null:
        return
    assert_eq(String(button.name), SaTopBarFocusMode.NODE_NAME, "under the name a scenario's click aims at")
    SaTopBarFocusMode.follower_of(button).sync()
    assert_false(button.disabled, "A bound button can be pressed")
    assert_true(button.toggle_mode, "The button stays down while the mode is on")
    _press(button)
    assert_true(SaFocusMode.active, "A press turns focus mode on")
    assert_eq(
        _shown(),
        {"ColorDocker": false, "LayersDocker": false, "BrushPresetsDocker": false},
        "and hides the dockers that were open"
    )
    assert_true(button.button_pressed, "The button is held down while the mode is on")
    _press(button)
    assert_false(SaFocusMode.active, "A second press turns it off")
    assert_eq(
        _shown(),
        {"ColorDocker": true, "LayersDocker": true, "BrushPresetsDocker": false},
        "and shows the same ones, not the one that was closed"
    )
    assert_false(button.button_pressed, "and lets the button up")


## A Tab, or the Window menu's row, moves the button too, since it reads the
## mode rather than keeping its own copy.
func test_the_button_follows_a_tab() -> void:
    var bar := _bar(TABLET_WIDTH)
    var button := _button(bar)
    var follower := SaTopBarFocusMode.follower_of(button)
    _tab()
    follower.sync()
    assert_true(button.button_pressed, "A Tab that turns the mode on holds the button down")
    _tab()
    follower.sync()
    assert_false(button.button_pressed, "and a Tab back lets it up")


## A press with every docker closed hides nothing and the mode does not start,
## so the button the press flipped goes back up.
func test_a_press_that_hides_nothing_leaves_the_button_up() -> void:
    for config: Dictionary in _table:
        (config["node"] as Window).visible = false
    var button := _button(_bar(TABLET_WIDTH))
    _press(button)
    assert_false(SaFocusMode.active, "Nothing open, nothing to hide")
    assert_false(button.button_pressed, "and the button is up again")


## The second clause: with the mode on, the button is still on the bar, shown,
## and inside the window, so the way back is a press away on a short bar too.
func test_the_button_stays_visible_and_inside_the_window_while_the_mode_is_on() -> void:
    var bar := _bar(TABLET_WIDTH)
    var button := _button(bar)
    _press(button)
    assert_true(SaFocusMode.active, "The mode is on")
    assert_true(button.is_visible_in_tree(), "The button still shows")
    var held: Array = bar.rows.overflow.report()["held"]
    assert_false(held.has(SaTopBarFocusMode.NODE_NAME), "and not in the overflow's list: %s" % [held])
    var rect := button.get_global_rect()
    assert_true(rect.size.x > 0.0 and rect.size.y > 0.0, "It has a size: %s" % rect)
    var window := Rect2(Vector2.ZERO, Vector2(TABLET_WIDTH, bar.get_viewport_rect().size.y))
    assert_true(window.encloses(rect), "and stands inside the window: %s in %s" % [rect, window])


## It stays on a bar that has given up other controls, since `LEAVE_LAST` names it.
func test_a_short_bar_keeps_the_button() -> void:
    var bar := _bar(640.0)
    var button := _button(bar)
    assert_true(button.is_visible_in_tree(), "A bar 640 wide still shows the Focus Mode button")


## Unbound, as before main hands the toggle over, the button is dimmed.
func test_an_unbound_button_is_dimmed() -> void:
    var button := SaTopBarFocusMode.make(_host, func() -> Callable: return Callable())
    SaTopBarFocusMode.follower_of(button).sync()
    assert_true(button.disabled, "No toggle, no press")
    button.free()


## On a fresh bar as Undo is, placeable in a docker, and hidden from the bar by
## the switch Preferences' row writes.
func test_a_fresh_bar_shows_it_and_preferences_can_hide_it() -> void:
    assert_true(SaSettings.get_element_visible("TopMenuBar", SaTopBarFocusMode.ELEMENT), "A fresh profile shows Focus Mode")
    var bar := _bar(TABLET_WIDTH)
    assert_true(SaSettings.is_placeable("TopMenuBar", SaTopBarFocusMode.ELEMENT), "and a custom docker can place it")
    var button := _button(bar)
    assert_true(button.is_visible_in_tree(), "It shows on the bar")
    SaSettings.set_element_visible("TopMenuBar", SaTopBarFocusMode.ELEMENT, false)
    bar.apply_layout_settings()
    assert_false(button.is_visible_in_tree(), "and leaves it once the row is turned off")
