## On Android, Sara's log and its tester notes go to
## `Documents/Sara` on the shared storage, where a file manager opens them,
## and on a desktop they stay where they were.
##
## The desktop half is read as it runs. The Android half is read through the
## two functions `SaDataRoot.shared()` and `default_log()` are made of, since
## no suite runs on Android.
##
## In tests/ because it proves SaDataRoot, SaRunLog's fallback, SaTrail and
## SaNoteFile agreeing on one folder.
extends "res://tests/test_framework.gd"


func test_android_s_documents_folder_holds_a_folder_named_sara() -> void:
    assert_eq(
        SaDataRoot.shared_under("/storage/emulated/0/Documents"),
        "/storage/emulated/0/Documents/Sara",
        "The shared folder is Sara under Documents"
    )
    assert_eq(SaDataRoot.shared_under(""), "", "No Documents folder names no shared folder")


func test_the_log_lands_in_the_shared_folder_when_there_is_one() -> void:
    assert_eq(
        SaDataRoot.log_under("/storage/emulated/0/Documents/Sara"),
        "/storage/emulated/0/Documents/Sara/godot.log",
        "The log sits in Documents/Sara itself"
    )
    assert_eq(SaDataRoot.log_under(""), SaDataRoot.ENGINE_LOG, "With no shared folder the engine's own log stands")


func test_a_desktop_run_names_no_shared_folder_and_keeps_its_log_where_it_was() -> void:
    if OS.get_name() == "Android":
        return
    assert_eq(SaDataRoot.shared(), "", "A desktop has no shared folder")
    if SaDataRoot.moved():
        assert_eq(SaDataRoot.default_log(), SaDataRoot.log_path(), "A moved root keeps the log under its flag")
    else:
        assert_eq(SaDataRoot.default_log(), SaDataRoot.ENGINE_LOG, "An unmoved desktop run keeps user://logs")


func test_a_desktop_note_still_goes_where_it_went() -> void:
    if OS.get_name() == "Android" or not OS.get_environment(SaNoteFile.NOTES_DIR_ENV).is_empty():
        return
    assert_false(
        SaNoteFile.default_notes_dir().ends_with("/Documents/Sara"), "A desktop note never lands in a Documents/Sara folder"
    )
