## The gradient library is the app's own list.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The library is not an engine `MenuButton`, whose popup no test can point into. What is here is what a
## detached
## control can be asked: the button carries no engine menu, the list hangs from it,
## its rows are the saved names, and a row pressed loads the gradient it names.
## Opening the list is a `Window` on screen, which a test must not do, so that half is
## `scenarios/two-engine-menus-outlived-the-u-group.json`.
extends "res://tests/test_framework.gd"

const ScratchFolder := preload("res://tests/fixtures/scratch_folder.gd")

static var scratch_dir: String = SaDataRoot.path("test_d74_ramp_library")


func before_each() -> void:
    ScratchFolder.clear(scratch_dir)


func after_each() -> void:
    ScratchFolder.clear(scratch_dir)


func _store() -> SaPresetStore:
    var store := SaPresetStore.new()
    store.dir = scratch_dir
    return store


func _control() -> SaColorRampControl:
    var control := SaColorRampControl.new(_store())
    control.bind_ramp(SaColorRamp.from_pair(Color.RED, Color.BLUE))
    return control


func test_the_library_is_a_button_with_the_apps_list_under_it() -> void:
    var control := _control()

    var button := control.find_child("RampLibrary", true, false) as Button
    var list := control.find_child("RampLibraryList", true, false) as SaChoicePopup

    assert_not_null(button, "the library row still has its button")
    assert_false(button is MenuButton, "and it is not the engine's menu button")
    assert_not_null(list, "the list is the app's own")
    assert_true(list != null and list.get_parent() == button, "hung from the button, so a dump files it under RampLibrary")
    assert_eq(control.find_children("*", "PopupMenu", true, false).size(), 0, "no engine popup anywhere in the control")
    control.free()


## There is no dimmed "No saved gradients" row: the
## two stock gradients head the list on every profile, so it is never empty.
func test_an_empty_library_lists_the_two_stock_rows() -> void:
    var control := _control()
    var list := control.find_child("RampLibraryList", true, false) as SaChoicePopup

    control.fill_library()

    var labels := list.row_labels()
    assert_eq(labels.size(), 2, "two rows")
    assert_false(labels.has("No saved gradients"), "neither saying the library is empty")
    assert_true(labels.size() > 0 and not list.is_disabled(list.row_ids()[0]), "and both take a press")
    control.free()


func test_a_row_is_a_saved_gradient_and_pressing_it_loads_that_one() -> void:
    var control := _control()
    var list := control.find_child("RampLibraryList", true, false) as SaChoicePopup
    assert_eq(control.save_ramp("Sunset"), "Sunset", "a red to blue ramp is saved")
    control.ramp.set_stop_color(0, Color.GREEN)

    control.fill_library()
    var pressed := list.press_row(&"Sunset")

    var ids := list.row_ids()
    assert_eq(ids.size(), 3, "one saved gradient, one row under the two stock ones")
    assert_eq(String(ids[2]) if ids.size() > 2 else "", "Sunset", "keyed on the saved name")
    assert_true(pressed, "the row takes the press")
    assert_eq(control.ramp.color_of(0).to_html(false), Color.RED.to_html(false), "and the saved stops are back on the ramp")
    control.free()


func test_a_row_whose_gradient_was_deleted_since_the_fill_loads_nothing() -> void:
    var control := _control()
    var list := control.find_child("RampLibraryList", true, false) as SaChoicePopup
    control.save_ramp("Dusk")
    control.fill_library()
    control.ramp.set_stop_color(0, Color.GREEN)
    control.delete_ramp("Dusk")

    list.press_row(&"Dusk")

    assert_eq(control.ramp.color_of(0).to_html(false), Color.GREEN.to_html(false), "the ramp is left as it was")
    control.free()
