## A toggle row's box says what its own list hands it, and no list's box
## says it keeps a favourite unless the list is the blend list.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## `SaChoiceRow` gave every check box it built the blend list's
## sentence, "Keep this one in the favourites at the top.", whatever the list,
## so a painter hovering the paint lock's box in the Layers docker's More menu
## read that it adds the lock to a favourites list. The words are the caller's
## now, through `add_row`, and only the blend list hands any.
##
## Read from the box's `tooltip_text` rather than from a tooltip on screen,
## because a tooltip shows under the capture harness only
## inside a dialog, and that is the property the engine draws the tooltip from.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

const FAVOURITES := "Keep this one in the favourites at the top."


func test_a_check_row_with_no_words_carries_no_favourites_text() -> void:
    var popup := SaChoicePopup.new()
    popup.clear()
    popup.add_row(&"lock_paint", "Lock Painting", true, false)
    popup.add_row(&"lock_alpha", "Lock Alpha", true, true, "", "", false)

    for id: StringName in [&"lock_paint", &"lock_alpha"]:
        var box := popup.check_box(id)
        assert_not_null(box, "%s carries a box" % id)
        assert_eq(box.tooltip_text, "", "and its box says nothing its list did not give it")
        assert_false(box.tooltip_text.contains("favourite"), "least of all that it keeps a favourite")
    popup.free()


func test_a_check_row_says_the_words_its_list_hands_it() -> void:
    var popup := SaChoicePopup.new()
    popup.clear()
    popup.add_row(&"isolate", "Isolate Group", true, false, "", "", false, "Composite the group as one")

    assert_eq(popup.check_box(&"isolate").tooltip_text, "Composite the group as one", "The box says its caller's words")
    popup.free()


func test_the_blend_lists_boxes_still_keep_a_favourite() -> void:
    var button := BlendModeButton.new()
    button.registry = Fixtures.make_registries().blend_modes
    button.refresh()

    var boxes := 0
    for id: StringName in button.popup.row_ids():
        var box := button.popup.check_box(id)
        if box == null:
            continue
        boxes += 1
        assert_eq(box.tooltip_text, tr(FAVOURITES), "The blend row %s says its box keeps a favourite" % id)
    assert_true(boxes > 10, "over every mode the registry holds, %d boxes" % boxes)
    button.free()


func test_a_menu_built_through_sa_menu_has_a_box_that_says_nothing() -> void:
    var popup := SaChoicePopup.new()
    var menu := SaMenu.new(popup)
    menu.add_check_item("Show Grid", 0, true)

    assert_eq(popup.check_box(SaMenu.key(0)).tooltip_text, "", "A top bar tick's box carries no favourites text")
    menu = null
    popup.free()
