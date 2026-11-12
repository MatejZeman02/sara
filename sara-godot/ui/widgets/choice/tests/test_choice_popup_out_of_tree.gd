## A choice list that is not in the tree opens nothing and says nothing,
## and one that is in the tree still opens.
##
## `SaChoicePopup.open_under` asked a detached anchor for its screen position and
## then asked itself to pop up, and each call printed an engine error rather than
## returning quietly: `Condition "!is_inside_tree()" is true` twice and
## `Parameter "data.tree" is null` behind them. Two suites build an `OptionButton`
## that is never parented, which is a fair fixture, so six error lines sat at the
## end of every green gate run. They were the last ones left of sixty, and a
## reader stops looking at a list that always has something in it.
##
## The half that matters is the second test. A guard that returns early is a
## guard that can silently stop the feature working, and no suite can show a
## window opening on a screen, so
## `scenarios/choice-popup-opens-outside-the-tree.json` drives it in the
## running app as well: `PickerType opened 4 rows, marked item_0` and
## `picked row 3, Triangle, saturation up`.
extends "res://tests/test_framework.gd"

## Needs a RenderingDevice, the second test putting a real Window in the tree.
const REQUIRES_GPU := true


## The fixture the two older suites use, and the one that produced the errors.
## Everything they assert has to keep working, so the guard is a guard and not a
## removal.
##
## An `SaChoiceButton` is the fixture now, no `OptionButton` is left in the tree.
## The button carries its own list now rather than being followed into one, so
## the detached case is the same case with one object in it instead of three.
func test_a_detached_button_still_builds_marks_and_answers_its_list() -> void:
    var button := SaChoiceButton.new()
    button.set_choices([{"id": 1, "label": "First"}, {"id": 2, "label": "Second"}])
    button.select_value(2)

    button.toggle_list()
    var popup := button.popup

    assert_not_null(popup, "A detached button still builds its row list")
    assert_eq(popup.row_labels(), ["First", "Second"] as Array[String], "out of the button's own rows")
    assert_true(popup.is_marked(&"2"), "with the chosen row marked")
    assert_false(popup.visible, "and nothing is shown, there being no tree to show it in")

    popup.press_row(&"1")
    assert_eq(button.selected_value(), 1, "and a row can still be pressed")

    button.free()


## `open_under(null)` is the other way in, and it reached `popup_centered()`,
## which asks for the tree exactly as `popup()` does.
func test_the_null_anchor_path_is_guarded_as_well() -> void:
    var popup := SaChoicePopup.new()
    popup.add_row(&"only", "Only")
    popup.open_under(null)
    assert_false(popup.visible, "A list with no anchor and no tree opens nothing")
    popup.free()


## The guard has to let the real path through, and this is the only assertion in
## the suite that would catch a guard written one condition too wide.
func test_a_list_whose_anchor_is_in_the_tree_opens() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    assert_not_null(tree, "This suite needs the real scene tree to open a window in")
    if tree == null:
        return

    # Embedding forced for the reason `test_windows_open.gd` gives: a Window
    # added to a root that does not embed maps an OS window and the run blocks
    # until the watchdog fires. It is a user setting, so it is put back after.
    var previous_embedding: bool = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true

    # Not `tree.root`, which is mid-`_ready` when a suite runs. An autoload
    # finished its own long before the scene loaded.
    var host := Control.new()
    host.name = "F127ChoiceHost"
    EventBus.add_child(host)

    var button := SaChoiceButton.new()
    button.set_choices([{"id": 1, "label": "First"}, {"id": 2, "label": "Second"}])
    button.select_value(1)
    host.add_child(button)

    button.toggle_list()
    var popup := button.popup
    assert_not_null(popup, "The button in the tree builds its list")
    if popup != null:
        assert_true(popup.visible, "and the list opens, which is what the guard must not stop")
        assert_eq(popup.row_labels(), ["First", "Second"] as Array[String], "with the button's own rows in it")
        popup.hide()

    host.free()
    tree.root.gui_embed_subwindows = previous_embedding
