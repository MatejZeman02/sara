## A note taken on a menu row with the pen, under WinTab and
## with embedded subwindows off, where every menu is a window of its own.
##
## Three faults are guarded in one tap. The hover must not ask the embedded
## windows alone, or a menu of its own never has its row marked. The menu must
## not be left to close itself on losing the focus, which a window of its own
## need not do, or an open list hears the letters of the note. And the box must
## ask for its own window's focus as well as its field's. The running proof is
## `scenarios/a-note-taken-on-a-menu-row-with-the-pen.json`, and these hold
## the three answers without a display.
extends "res://tests/test_framework.gd"

var _popup: SaChoicePopup = null
var _plain: Window = null


func before_each() -> void:
    _popup = SaChoicePopup.new()
    _popup.add_row(&"welcome", "Welcome")
    _popup.add_row(&"manual", "Manual")
    _plain = Window.new()


func after_each() -> void:
    if _popup != null:
        _popup.free()
        _popup = null
    if _plain != null:
        _plain.free()
        _plain = null


func test_a_menu_of_its_own_that_has_the_pointer_is_asked() -> void:
    _popup.visible = true
    var asked := SaNoteMenu.menus_to_ask(null, _popup)
    assert_eq(asked.size(), 1, "The list the last motion went to is asked, though it is not embedded")
    assert_true(asked.has(_popup), "and it is that list")


func test_a_window_without_the_pointer_or_that_is_no_menu_is_not_asked() -> void:
    _popup.visible = true
    assert_eq(SaNoteMenu.menus_to_ask(null, null).size(), 0, "No motion yet names no window of its own")
    _plain.visible = true
    assert_eq(
        SaNoteMenu.menus_to_ask(null, _plain).size(),
        0,
        "a docker or the box has the pointer, and its stale reading is never taken for a row"
    )
    _popup.visible = false
    assert_eq(SaNoteMenu.menus_to_ask(null, _popup).size(), 0, "and a closed list is not asked either")


func test_the_note_closes_the_menu_it_photographed() -> void:
    _popup.visible = true
    var menu := SaNoteMenu.new()
    menu.take(SaNoteMenu.item_of(_popup, _popup.row_of(&"manual")))
    assert_true(menu.is_set(), "The note is on Manual")
    menu.close()
    assert_false(_popup.visible, "and the list is closed, so no letter typed for the note reaches its type-ahead")
    menu.close()
    assert_false(_popup.visible, "a second close is harmless")


func test_the_freeze_closes_the_menu_once_the_picture_is_taken() -> void:
    var source := FileAccess.get_file_as_string("res://ui/notes/sa_note_mode.gd")
    var picture := source.find("_image = picture_of(viewport)")
    var closed := source.find("menu.close()")
    assert_true(picture > 0 and closed > picture, "The menu closes after the photograph, which has to show it open")


func test_the_box_asks_for_its_windows_focus_before_its_fields() -> void:
    var source := FileAccess.get_file_as_string("res://ui/notes/sa_note_overlay.gd")
    var window_focus := source.find("box.grab_focus()")
    var field_focus := source.find("_text.grab_focus()")
    assert_true(window_focus > 0, "The box asks for the focus of the window it is")
    assert_true(field_focus > window_focus, "before its field takes the focus inside it")
