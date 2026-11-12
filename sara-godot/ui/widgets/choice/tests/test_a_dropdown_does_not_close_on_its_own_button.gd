## A second press on a menu's own title closes it.
##
## The ask, 2026-09-20: "the dropdown menu is not closed when button clicked
## again (f.e. 'Help')". Two things answer a press on a title, and both have to
## be there for the second press to read as a close. The title answers on the
## press rather than on the release, the way `SaDropdownButton` and an
## `OptionButton` do, so it answers in the frame the click outside hid the list
## in rather than after it. And the bar remembers the frame its list went away
## in, so a press that finds its own menu closed in that frame is the click that
## closed it and not a press that opens it again.
##
## Opened embedded under a host, the way
## `test_a_toggle_rows_label_keeps_the_menu_open.gd` opens a list, so
## `visible` is the list a painter sees rather than a detached window's flag.
##
## **The record is spent by the press that reads it**, which is what lets the
## last press below open the menu in the frame that closed it: a synchronous
## suite cannot advance a frame, and a record that outlived its press would hold
## the menu shut for the rest of the frame instead.
extends "res://tests/test_framework.gd"

var _bar: TopMenuBar = null
var _host: Node = null
var _was_embedding := false


func before_each() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    _was_embedding = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    _host = Node.new()
    _host.name = "Q4MenuHost"
    EventBus.add_child(_host)
    _bar = TopMenuBar.new()
    _host.add_child(_bar)
    _bar._ready()


func after_each() -> void:
    _host.free()
    _host = null
    _bar = null
    (Engine.get_main_loop() as SceneTree).root.gui_embed_subwindows = _was_embedding


## A press on a title, through the handler a painter's press reaches.
func _press(m_name: String) -> void:
    _bar._on_menu_button_pressed(m_name)


func _menu(m_name: String) -> SaChoicePopup:
    return _bar.menus[m_name] as SaChoicePopup


## The first half: a title answers on the press. Answering on the release is
## what made the second press an open, because by the release the engine had
## closed the menu the press landed outside of.
func test_a_title_answers_on_the_press() -> void:
    assert_false(_bar.menu_buttons.is_empty(), "The bar builds its titles")
    for m_name: String in _bar.menu_buttons:
        var button: Button = _bar.menu_buttons[m_name]
        assert_eq(
            button.action_mode,
            BaseButton.ACTION_MODE_BUTTON_PRESS,
            "%s answers on the press, the frame the click outside closes its list in" % m_name
        )


## The second half: the frame the list went away in. The hide stands in for the
## engine's own, which is what a click outside the list does.
func test_a_press_in_the_frame_the_list_closed_in_is_the_close() -> void:
    var popup := _menu("Help")

    _press("Help")
    assert_true(popup.visible, "A press on the closed title opens the menu")

    popup.hide()
    assert_false(popup.visible, "and a click outside it closes it")

    _press("Help")
    assert_false(popup.visible, "so a press arriving in that same frame is that close and not a reopen")

    _press("Help")
    assert_true(popup.visible, "and the press after it opens the menu, the record spent rather than latched")


## The loop above the guard: a press on another title still opens that one.
func test_a_press_on_another_title_opens_it_and_takes_the_first_down() -> void:
    var help := _menu("Help")
    var edit := _menu("Edit")

    _press("Help")
    assert_true(help.visible, "Help is up")
    _press("Edit")
    assert_true(edit.visible, "A press on Edit opens the Edit menu")
    assert_false(help.visible, "and the menu that was up goes")
