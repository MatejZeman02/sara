## A press on a filter's row in a section's list beside the
## Filter menu reaches the row, and the bar puts neither list away.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The bar closes every menu on a press outside every list, and the lists it
## asks are the ones the window walk from the root finds. The walk stops at a
## window, and a section's list is a child of the Filter menu's, so a press on
## it must not be judged outside and close both lists before the row hears it.
##
## **The whole route, the way the engine hands a press over**, as the suite for a press that closes a menu
## does it: each event is emitted on the root window's `window_input` and then
## pushed into it, so the bar hears it first and the list only if the bar left
## it up. The bar stands in the real root with embedding forced, the way the
## other embedded-window suites stand it, with the Filter menu open and a section's list
## beside it. Everything is asked in one frame, since a test that awaits drops
## every assertion after the await. The running app's proof is
## `scenarios/a-docker-s-row-in-the-window-menu-opens-the-docker-again.json`.
@tool
extends "res://tests/test_framework.gd"

## Real windows go in the tree.
const REQUIRES_GPU := true


## A filter with a title and a section of the suite's choosing. Public members,
## written in `_init` alone.
class SortedFilter:
    extends SaFilter
    var entry_title: String
    var entry_section: StringName

    func _init(text: String, section_id: StringName) -> void:
        entry_title = text
        entry_section = section_id

    func title() -> String:
        return entry_title

    func family() -> StringName:
        return entry_section

    func run(_ctx: SaFilterContext) -> void:
        pass


## The registries outlive the test, because the menu hands a pressed filter to
## the registry a frame later and the frame comes after `after_each`.
static var kept_registries: SaRegistries = null

var _host: Control = null
var _was_embedding: bool = false
var _bar: TopMenuBar = null
var _menu: SaFilterMenu = null
## The row ids the section's list answered, in order.
var _chosen: Array[StringName] = []
## The registry's key for the Streak filter, whose row the press aims at.
var _streak_key: StringName = &""


func before_each() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    _was_embedding = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    _chosen.clear()


func after_each() -> void:
    if _host != null:
        _host.free()
    _host = null
    _bar = null
    _menu = null
    var tree := Engine.get_main_loop() as SceneTree
    tree.root.gui_embed_subwindows = _was_embedding


func test_the_middle_of_the_list_beside_the_menu_is_in_a_list() -> void:
    if DisplayServer.get_name() == "headless":
        return
    var list := _open_list()
    assert_true(list.visible and list.is_embedded(), "The Blur list is open beside Filter and embedded in the root")
    var popup: SaChoicePopup = _bar.menus["Filter"]
    var middle := Rect2(Vector2(list.position), Vector2(list.size)).get_center()
    assert_false(
        Rect2(Vector2(popup.position), Vector2(popup.size)).has_point(middle), "Its middle is beside the menu rather than on it"
    )
    assert_true(_bar._list_at(middle), "and the bar counts it as in a list")


func test_a_press_on_a_filters_row_reaches_the_row_and_closes_nothing_first() -> void:
    if DisplayServer.get_name() == "headless":
        return
    var list := _open_list()
    var popup: SaChoicePopup = _bar.menus["Filter"]
    var row_id := SaMenu.key(int(_menu._filter_ids.find_key(_streak_key)))
    var at := _row_at(list, row_id)
    assert_true(Rect2(Vector2(list.position), Vector2(list.size)).has_point(at), "Streak's row is inside the list")

    var press := _press(at)
    assert_true(SaPutAway._spent != press.get_instance_id(), "The bar names the press as no window's put-away")
    assert_true(popup.visible and list.visible, "and both lists are still up when the row hears it")
    _release(at)
    assert_eq(_chosen, [row_id], "The release presses Streak's row, which is the filter asked for")


func test_a_press_beside_both_lists_still_closes_them() -> void:
    if DisplayServer.get_name() == "headless":
        return
    var list := _open_list()
    var popup: SaChoicePopup = _bar.menus["Filter"]
    var past := Vector2(list.position) + Vector2(list.size) + Vector2(40.0, 40.0)
    assert_false(_bar._list_at(past), "A point past the list's corner is in no list")
    var press := _press(past)
    assert_false(popup.visible or list.visible, "and a press there closes the menu and the list beside it")
    assert_eq(SaPutAway._spent, press.get_instance_id(), "and names it as the press that put them away")
    _release(past)
    assert_eq(_chosen, [], "No row was pressed")


# --- Helpers --------------------------------------------------------------------


## The bar in the real root, the Filter menu open and the Blur section's list
## beside it, laid out as the engine would a frame on so a row has the rectangle
## a press lands on.
func _open_list() -> SaChoicePopup:
    var registries := SaRegistries.new()
    registries.build_context(func() -> Variant: return null, func() -> Array: return [])
    registries.register_builtins()
    SaAppCommands.register_all(registries, func(_docker_id: StringName) -> void: pass)
    SaShortcutCommands.new(Callable(), Callable(), Callable(), null).register_into(registries.commands)
    var alpha := registries.context.for_module(&"alpha")
    alpha.register_filter_section(&"blur", "Blur", 400)
    alpha.register_filter(SortedFilter.new("Smear", &"blur"))
    var streak := SortedFilter.new("Streak", &"blur")
    alpha.register_filter(streak)
    _streak_key = SaFilterRegistry.key_for(&"alpha", streak)
    kept_registries = registries
    # Parented to an autoload, because the runner calls this from its own
    # `_ready` and a parent mid-`_ready` rejects `add_child`.
    _host = Control.new()
    _host.name = "B18ListBesideTheMenuHost"
    _host.mouse_filter = Control.MOUSE_FILTER_IGNORE
    EventBus.add_child(_host)
    _bar = TopMenuBar.new()
    _host.add_child(_bar)
    _bar.bind_commands(registries.commands)
    _menu = _bar.menu("Filter") as SaFilterMenu
    _menu.filters = registries.filters
    _bar._on_menu_button_pressed("Filter")
    var list := _menu.show_section(_menu.section_item(&"blur"))
    for container: Node in list.find_children("*", "Container", true, false):
        (container as Container).notification(Container.NOTIFICATION_SORT_CHILDREN)
    list.chosen.connect(_chosen.append)
    return list


## The middle of *row_id*'s label in *list*, in the main window's space, where
## an embedded list is placed.
func _row_at(list: SaChoicePopup, row_id: StringName) -> Vector2:
    var label := list.row_of(row_id).get_node("Label") as Control
    return Vector2(list.position) + list.get_final_transform() * label.get_global_rect().get_center()


func _press(at: Vector2) -> InputEventMouseButton:
    return _send(at, true)


func _release(at: Vector2) -> InputEventMouseButton:
    return _send(at, false)


## A left press or release at *at*, in the main window's logical space, handed
## to the root the way `Window` hands an event the display server delivered: its
## input signal first, in the window's own space, then into the viewport.
func _send(at: Vector2, pressed: bool) -> InputEventMouseButton:
    var root := (Engine.get_main_loop() as SceneTree).root
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = pressed
    event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
    event.position = root.get_final_transform() * at
    event.global_position = event.position
    root.window_input.emit(event)
    root.push_input(event)
    return event
