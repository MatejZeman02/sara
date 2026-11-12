## Enter in the New Module dialog's name field does what Create does.
##
## `text_submitted` hands the text, and `_on_confirmed` takes none, so bound
## bare the call failed and Enter did nothing at all. An empty name is the case
## driven here, because its answer is on the dialog and writes no folder.
extends "res://tests/test_framework.gd"


func test_enter_on_an_empty_name_says_to_type_one() -> void:
    var dialog := NewModuleDialog.new()
    var field := dialog.find_child("NameField", true, false) as LineEdit
    var status := dialog.find_child("StatusLabel", true, false) as Label
    field.text_submitted.emit("")
    assert_true(status.visible, "Enter answered")
    assert_eq(status.text, dialog.tr("Type a name first."), "with what Create says to an empty name")
    dialog.free()
