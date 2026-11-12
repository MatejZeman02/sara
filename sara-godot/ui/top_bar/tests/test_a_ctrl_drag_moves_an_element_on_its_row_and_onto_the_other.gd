## A press and drag with Ctrl held lifts an element of the top
## bar and seats it between the two the pointer is over, on its own row or on
## the other, and the order the setting stores says so.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The element hangs under the cursor when dragged and then jumps in between
## two elements. The events are handed to the bar's
## arranger in `_input`, where the root window's input reaches it before any
## control, and the rows are sorted by hand after each, where the engine would
## sort them a frame later.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")
const RightClick = preload("res://ui/top_bar/tests/test_a_right_click_on_the_bar_hides_and_shows_an_element.gd")

const REQUIRES_GPU := true

static var scratch_profile: String = SaDataRoot.path("test_ctrl_drag.cfg")

var _saved_path: String = ""
var _saved_row: bool = true
var _surface: SaSurface = null
var _machine: ToolMachine = null
var _host: Control = null
var _kept_embedding: bool = true


func before_each() -> void:
    _saved_path = SaSettings.settings_path
    _saved_row = SaSettings.second_row
    SaSettings.settings_path = ProjectSettings.globalize_path(scratch_profile)
    _remove_profile()
    SaSettings.load_settings()
    SaSettings.second_row = true


func after_each() -> void:
    if _host != null:
        _host.free()
        _host = null
        (Engine.get_main_loop() as SceneTree).root.gui_embed_subwindows = _kept_embedding
    _remove_profile()
    SaSettings.settings_path = _saved_path
    SaSettings.load_settings()
    SaSettings.second_row = _saved_row
    Fixtures.teardown(_surface, _machine)
    _surface = null
    _machine = null


func _remove_profile() -> void:
    for suffix: String in ["", ".bak", ".broken"]:
        var path := ProjectSettings.globalize_path(scratch_profile) + suffix
        if FileAccess.file_exists(path):
            DirAccess.remove_absolute(path)


func _make() -> TopMenuBar:
    _surface = Fixtures.make_surface()
    _machine = Fixtures.make_bound_machine(_surface)
    var root := (Engine.get_main_loop() as SceneTree).root
    _kept_embedding = root.gui_embed_subwindows
    root.gui_embed_subwindows = true
    return RightClick.bar_in_tree(self)


## The point between *left* and *right*, at the height of *row*.
static func between(left: Control, right: Control, row: Control) -> Vector2:
    var x := (left.get_global_rect().end.x + right.get_global_rect().position.x) * 0.5
    return Vector2(x, row.get_global_rect().get_center().y)


func _move(bar: TopMenuBar, at: Vector2) -> void:
    var motion := InputEventMouseMotion.new()
    motion.position = at
    motion.button_mask = MOUSE_BUTTON_MASK_LEFT
    bar.arrange._input(motion)
    RightClick.lay_out(bar)


func _release(bar: TopMenuBar, at: Vector2) -> void:
    var release := InputEventMouseButton.new()
    release.button_index = MOUSE_BUTTON_LEFT
    release.pressed = false
    release.position = at
    bar.arrange._input(release)
    RightClick.lay_out(bar)


## Ctrl presses *element*, carries it to the point *aim* answers, asked again
## after each move since the row closes up and the gap opens, and lets go.
func _carry(bar: TopMenuBar, element: String, aim: Callable) -> void:
    var control := bar.arrange.control_of(element)
    RightClick.press_on(bar, control, MOUSE_BUTTON_LEFT, true)
    assert_eq(bar.arrange._armed, element, "A Ctrl press arms %s" % element)
    _move(bar, control.get_global_rect().get_center() + Vector2(0, 8))
    assert_eq(bar.arrange.lifted, element, "and a drag lifts it")
    assert_true(control.top_level, "out of its row, which closes up")
    assert_true(control.modulate.a < 1.0, "drawn faint")
    for i in 3:
        _move(bar, aim.call())
    var at: Vector2 = aim.call()
    _release(bar, at)
    assert_eq(bar.arrange.lifted, "", "The release seats it")
    assert_false(control.top_level, "back on a row")


func _before(order: Array, a: String, b: String) -> bool:
    return order.find(a) >= 0 and order.find(a) < order.find(b)


func test_a_menu_title_moves_between_two_others() -> void:
    var bar := _make()
    var file: Button = bar.menu_buttons["File"]
    var edit: Button = bar.menu_buttons["Edit"]
    _carry(bar, "Help", func() -> Vector2: return between(file, edit, bar.rows.main_row))
    var order := SaSettings.get_layout_order("TopMenuBar")
    assert_eq(order.slice(0, 3), ["File", "Help", "Edit"], "Help is stored between File and Edit")
    assert_eq(bar.menu_bar.get_child(1), bar.menu_buttons["Help"], "and the bar draws it there")


func test_a_control_moves_between_two_others_on_its_row() -> void:
    var bar := _make()
    var row := bar.rows.second_options_row
    var held := bar.arrange._elements_in(row)
    assert_true(held.size() > 3, "The second row holds the tool controls")
    var names := bar.arrange._names_of()
    var first: String = names[held[0]]
    var second: String = names[held[1]]
    var third: String = names[held[2]]
    _carry(bar, third, func() -> Vector2: return between(held[0], held[1], bar.rows.second_row))
    var order := SaSettings.get_layout_order("TopMenuBar")
    assert_true(
        _before(order, first, third) and _before(order, third, second), "%s is stored between %s and %s" % [third, first, second]
    )
    assert_true(_before(order, SaSettings.ROW_SENTINEL, third), "and stays on the second row")


func test_a_control_dropped_on_the_first_row_goes_before_the_sentinel() -> void:
    var bar := _make()
    var held := bar.arrange._elements_in(bar.rows.second_options_row)
    var element: String = bar.arrange._names_of()[held[1]]
    var slot := bar.rows.brush_options_slot
    _carry(bar, element, func() -> Vector2: return slot.get_global_rect().get_center() + Vector2(0, 0))
    var order := SaSettings.get_layout_order("TopMenuBar")
    assert_true(_before(order, element, SaSettings.ROW_SENTINEL), "%s is stored before the sentinel" % element)
    assert_true(_before(order, "Help", element), "and after the menus")
    assert_eq(bar.arrange.control_of(element).get_parent(), bar.rows.row_container(1), "and the bar puts it on the first row")


func test_escape_puts_a_lifted_element_back() -> void:
    var bar := _make()
    var before := SaSettings.get_layout_order("TopMenuBar")
    var control := bar.arrange.control_of("View")
    bar.arrange.lift("View", control.get_global_rect().get_center(), false)
    _move(bar, between(bar.menu_buttons["File"], bar.menu_buttons["Edit"], bar.rows.main_row))
    assert_true(bar.arrange.report()["gap_on_bar"], "Move opens a gap")
    var key := InputEventKey.new()
    key.keycode = KEY_ESCAPE
    key.pressed = true
    bar.arrange._input(key)
    assert_eq(bar.arrange.lifted, "", "Escape lets go")
    assert_eq(SaSettings.get_layout_order("TopMenuBar"), before, "and the order is as it was")


func test_a_release_off_the_bar_puts_a_lifted_element_back() -> void:
    var bar := _make()
    var before := SaSettings.get_layout_order("TopMenuBar")
    var control := bar.arrange.control_of("Help")
    RightClick.press_on(bar, control, MOUSE_BUTTON_LEFT, true)
    _move(bar, control.get_global_rect().get_center() + Vector2(0, 8))
    assert_eq(bar.arrange.lifted, "Help", "A Ctrl drag lifts Help")
    var off := Vector2(control.get_global_rect().get_center().x, bar.get_global_rect().end.y + 200.0)
    _move(bar, off)
    assert_false(bar.arrange.report()["gap_on_bar"], "Off the bar there is no gap")
    _release(bar, off)
    assert_eq(bar.arrange.lifted, "", "The release lets go")
    assert_false(control.top_level, "and Help is back on its row")
    assert_eq(SaSettings.get_layout_order("TopMenuBar"), before, "with the order as it was")
