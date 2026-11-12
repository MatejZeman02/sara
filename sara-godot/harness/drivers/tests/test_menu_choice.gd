## The one-of groups in Sara's menus: a plain row per choice, the chosen
## one highlighted, and no radio dots left anywhere in the program.
extends "res://tests/test_framework.gd"

## **Two cases retired here, and this is the line saying why**.
## `test_the_chosen_row_is_the_one_the_menu_opens_highlighted` and
## `test_a_group_whose_value_is_not_in_the_list_highlights_nothing` covered
## `SaMenuChoice.select`, `selected` and `selected_text`, which pointed a
## `PopupMenu`'s focused item at the chosen row on every open because a
## `PopupMenu` has no per-row colour and the hover stylebox was the only mark
## it had. Every one-of group in the app is `SaChoicePopup` now and marks its
## own row, so the three methods and their cases went together. The claim they
## made is not lost: `test_choice_popup.gd` holds it against the control that
## draws the mark, and `test_no_menu_in_sara_shows_a_radio_dot` below is still
## what stops the dots coming back.


## A dropdown is a control Sara builds itself now, and the claim that stood
## here is the one this replaces: the engine's `OptionButton` opened a
## `PopupMenu` of radio items, `SaMenuChoice.follow_option` took the dots off it
## on every open, and the mark a painter read came from a second list underneath.
## The last `OptionButton` is out of the tree, so there is no popup to
## strip and no pair of lists to keep in step. What is asserted is the whole of
## what is left: the button's own list, marked on the row the caller's value
## stands for.
func test_a_dropdown_is_saras_own_list_marked_on_the_chosen_row() -> void:
    var button := SaChoiceButton.new()
    (
        button
        . set_choices(
            [
                {"id": &"srgb", "label": "sRGB"},
                {"id": &"display_p3", "label": "Display P3"},
                {"id": &"oklab", "label": "Oklab"},
            ]
        )
    )

    assert_eq(button.popup.name, SaMenuChoice.CHOICE_POPUP_NAME, "The list carries the name a capture finds it by")
    assert_eq(button.selected_value(), &"srgb", "and the button opens on the first row")

    assert_true(button.select_value(&"oklab"), "The third row takes the chosen value")
    assert_eq(String(button.popup.current), "oklab", "and the list marks it by that value, never by a position")
    assert_eq(button.text, "Oklab", "with the row's words on the button")

    assert_true(button.select_value(&"srgb"), "and back again")
    assert_eq(String(button.popup.current), "srgb", "which follows the value, not the order of the list")
    button.free()


## The rule the note asks for, held where it cannot be argued with: an empty dot
## beside every unchosen row is what a painter should never see, so a menu
## that grows one again fails the run rather than shipping.
func test_no_menu_in_sara_shows_a_radio_dot() -> void:
    var offenders: Array[String] = []
    var scripts := _production_scripts("res://ui")
    scripts.append_array(_production_scripts("res://harness"))
    assert_true(scripts.size() > 50, "The scan found only %d scripts under ui/, so it is measuring nothing" % scripts.size())
    for path: String in scripts:
        if path == "res://harness/drivers/menu_choice.gd":
            continue
        var file := FileAccess.open(path, FileAccess.READ)
        if file == null:
            continue
        var text := file.get_as_text()
        if text.contains("add_radio_check_item") or text.contains("add_icon_radio_check_item"):
            offenders.append(path)
    offenders.sort()
    assert_true(offenders.is_empty(), "A one-of group is SaMenuChoice, not a radio item: %s" % ", ".join(offenders))


func _production_scripts(root: String) -> Array[String]:
    var out: Array[String] = []
    var dir := DirAccess.open(root)
    if dir == null:
        return out
    dir.list_dir_begin()
    var entry := dir.get_next()
    while entry != "":
        var path := "%s/%s" % [root, entry]
        if dir.current_is_dir():
            if entry != "tests":
                out.append_array(_production_scripts(path))
        elif entry.ends_with(".gd"):
            out.append(path)
        entry = dir.get_next()
    dir.list_dir_end()
    return out
