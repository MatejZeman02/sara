## A preset deleted in this session leaves Recent Presets at once. The list was
## pruned only when its file was read at start, so the row stayed and a click on
## it loaded nothing.
extends "res://tests/test_framework.gd"

## The docker is a Window and its `_init` builds real controls.
const REQUIRES_GPU := true


func _docker() -> HistoryDocker:
    var docker := HistoryDocker.new()
    docker.path = SaDataRoot.path("test_b3_recent_presets.cfg")
    docker.entries = PackedStringArray(["Ink", "Pencil", "Wash"])
    return docker


func _rows(docker: HistoryDocker) -> Array[String]:
    var texts: Array[String] = []
    for child in docker.rows.get_children():
        var button := child as Button
        if button != null and not button.is_queued_for_deletion():
            texts.append(button.text)
    return texts


func test_a_deleted_preset_loses_its_row() -> void:
    var docker := _docker()
    docker.forget_deleted("Pencil", false)
    assert_eq(docker.entries, PackedStringArray(["Ink", "Wash"]), "The deleted preset is gone from the list")
    assert_eq(_rows(docker), ["Ink", "Wash"] as Array[String], "and from the rows a painter clicks")
    var stored := ConfigFile.new()
    stored.load(docker.path)
    assert_eq(
        stored.get_value(HistoryDocker.SECTION, HistoryDocker.KEY, PackedStringArray()),
        PackedStringArray(["Ink", "Wash"]),
        "and from the file the next start reads"
    )
    docker.free()
    DirAccess.remove_absolute(ProjectSettings.globalize_path(SaDataRoot.path("test_b3_recent_presets.cfg")))


func test_a_save_leaves_the_list_alone() -> void:
    var docker := _docker()
    docker.forget_deleted("Pencil", true)
    assert_eq(docker.entries, PackedStringArray(["Ink", "Pencil", "Wash"]), "Saving a preset is not a reason to forget it")
    docker.free()
