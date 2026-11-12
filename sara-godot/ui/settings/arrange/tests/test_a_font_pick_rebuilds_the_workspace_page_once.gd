## A pick of the interface font asks Preferences to draw the Workspace page
## again, once.
##
## The page kept the font row's key from `build`, before `SaPage.adopt_row` had
## given the row one, so the key it matched changes against was the empty one
## and `rebuild_requested` was never sent. A rebuild is still needed: a title
## carries the bold of the face the page was built in, and without one the
## titles stayed in the old face while the hints took the new. What is held here is the pick made through the
## row's own control, the signal counted, and a press on the font already
## showing sending nothing.
extends "res://tests/test_framework.gd"

var _host: Node = null
var _page: SaWorkspacePage = null
var _saved_font: String = ""
var _rebuilds: int = 0


func before_each() -> void:
    _saved_font = SaSettings.ui_font
    SaSettings.ui_font = "inter"
    _rebuilds = 0
    _host = Node.new()
    _host.name = "FontHost"
    EventBus.add_child(_host)
    _page = SaWorkspacePage.new()
    _host.add_child(_page)
    _page.rebuild_requested.connect(_count)


func after_each() -> void:
    SaSettings.ui_font = _saved_font
    if is_instance_valid(_host):
        _host.free()
    _host = null
    _page = null


func _count() -> void:
    _rebuilds += 1


func _button() -> SaChoiceButton:
    return _page.find_child("InterfaceFontOpt", true, false) as SaChoiceButton


func test_a_font_pick_sends_one_rebuild() -> void:
    var button := _button()
    assert_not_null(button, "the page draws the font row")
    assert_true(button.pick_row(button.choice_values().find("atkinson-hyperlegible")), "the row offers Atkinson")
    assert_eq(SaSettings.ui_font, "atkinson-hyperlegible", "the pick reached the setting")
    assert_eq(_rebuilds, 1, "one rebuild for one pick")


func test_the_font_already_showing_sends_none() -> void:
    var button := _button()
    button.pick_row(button.choice_values().find("inter"))
    assert_eq(_rebuilds, 0, "nothing moved, so nothing is drawn again")


func test_another_row_sends_none() -> void:
    _page.page.row_changed.emit(&"font_size", 1.0)
    assert_eq(_rebuilds, 0, "only the font row rebuilds")
