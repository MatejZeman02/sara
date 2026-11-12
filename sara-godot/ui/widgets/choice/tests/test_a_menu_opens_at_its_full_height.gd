## A menu under the top bar opens at its full height whenever the window has
## room for it, and a dropdown keeps its cap.
##
## A shot photographed the Tools menu stopping at its Stabilizer heading at
## about y 545, with a scroll bar down its edge and more than half the window free
## below it. The cap was `SaChoicePopup.MAX_HEIGHT`, which every list took, the
## eleven the top bar builds among them. Built detached, the way
## `test_top_menu_bar.gd` builds its bar, because a popup is a `Window`.
extends "res://tests/test_framework.gd"

## The Tools menu's room on a 1080 window: the whole window, under a title about
## thirty pixels tall.
const ROOM := Rect2i(0, 0, 1920, 1080)
const TITLE := Rect2(335.0, 0.0, 40.0, 30.0)


func _fill(popup: SaChoicePopup, count: int) -> void:
    popup.clear()
    for i in count:
        popup.add_row(StringName("row_%d" % i), "Row %d" % i)


## The Tools menu's own shape: thirteen tools, the gap, the Stabilizer heading and
## its three rows, which is what stopped short in the shot.
func _fill_like_the_tools_menu(popup: SaChoicePopup) -> void:
    _fill(popup, 13)
    popup.add_gap()
    popup.add_section("Stabilizer")
    for i in 3:
        popup.add_row(StringName("stabilizer_%d" % i), "Mode %d" % i, true, i == 2)


func test_every_menu_on_the_bar_is_built_without_the_cap() -> void:
    var bar := TopMenuBar.new()
    bar._ready()
    var cap := SaUI.px(SaChoicePopup.MAX_HEIGHT)
    assert_true(bar.menus.size() > 5, "The bar builds its menus: %d" % bar.menus.size())
    for m_name: String in bar.menus:
        var popup := bar.menus[m_name] as SaChoicePopup
        _fill(popup, 40)
        var wanted := popup.wanted_size(120.0).y
        assert_true(wanted > cap, "The %s menu wants all forty rows, %d, past the dropdown's %d" % [m_name, wanted, cap])
    bar.free()


func test_a_dropdown_keeps_the_cap() -> void:
    var popup := SaChoicePopup.new()
    _fill(popup, 40)
    assert_eq(popup.wanted_size(120.0).y, SaUI.px(SaChoicePopup.MAX_HEIGHT), "A list built the default way still stops")
    popup.free()


## What the shot needed: the heading and the three rows under it inside the rect
## the menu opens at, rather than behind a scroll bar.
func test_the_tools_menu_opens_whole_under_its_title() -> void:
    var bar := TopMenuBar.new()
    bar._ready()
    var popup := bar.menus["Tools"] as SaChoicePopup
    _fill_like_the_tools_menu(popup)
    var wanted := popup.wanted_size(60.0)
    var rect := SaPopupRect.under(TITLE, wanted, ROOM)
    assert_eq(rect.size.y, wanted.y, "The menu opens at its whole height, %d" % wanted.y)
    assert_eq(rect.position.y, 30, "under its title")
    assert_true(popup.row_ids().has(&"stabilizer_2"), "and the last stabilizer row is one of the rows it holds")
    bar.free()


## The other half of "whenever the window has room": a menu taller than the window
## stops at the window's foot and scrolls, rather than running off it.
func test_a_menu_taller_than_the_window_stops_at_its_foot() -> void:
    var bar := TopMenuBar.new()
    bar._ready()
    var popup := bar.menus["Tools"] as SaChoicePopup
    _fill(popup, 80)
    var wanted := popup.wanted_size(60.0)
    assert_true(wanted.y > ROOM.size.y, "Eighty rows want more than the window: %d" % wanted.y)
    var rect := SaPopupRect.under(TITLE, wanted, ROOM)
    assert_eq(rect.end.y, ROOM.end.y, "and the menu ends at the window's foot")
    assert_eq(rect.position.y, 30, "still under its title")
    bar.free()
