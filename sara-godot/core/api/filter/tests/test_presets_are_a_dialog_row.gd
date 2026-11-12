## Presets are a dialog row. A fixture filter whose `build` calls
## `ui.presets()` saves its values under a name, lists them, puts them back and
## deletes them, all through `SaPresetStore` in a directory named after its id,
## and a filter whose values are its own members gets the same row. The
## kaleidoscope's two older preset forms, the `ConfigFile` and the `.tres`
## files of its own script, are read into that store once.
##
## SPDX-License-Identifier: GPL-3.0-or-later
extends "res://tests/test_framework.gd"

const Kaleidoscope = preload("res://modules/sara-base-modules/kaleidoscope/kaleidoscope.gd")


## Three value rows and the presets row, the shape a module author writes.
class Fixture:
    extends SaFilter

    func id() -> StringName:
        return &"l7_fixture"

    func build(ui: SaDialog) -> void:
        ui.slider("Strength", 0.0, 2.0, 0.5)
        ui.checkbox("Inverted", false)
        ui.dropdown("Kind", [{"id": "soft", "label": "Soft"}, {"id": "hard", "label": "Hard"}], "soft")
        ui.presets()

    func run(_ctx: SaFilterContext) -> void:
        pass


## A filter written before the store, whose value is a member it reads back and
## writes itself.
class Members:
    extends SaFilter

    var amount: float = 1.0

    func id() -> StringName:
        return &"l7_members"

    func build(ui: SaDialog) -> void:
        ui.presets()

    func parameters() -> Dictionary:
        return {"amount": amount}

    func set_parameters(values: Dictionary) -> void:
        amount = float(values.get("amount", 1.0))

    func run(_ctx: SaFilterContext) -> void:
        pass


var _root: String = ""
var _host: VBoxContainer = null


func before_each() -> void:
    _root = SaDataRoot.path("test_l7_presets_%d" % OS.get_process_id())
    SaFilterPreset.root = _root
    _host = VBoxContainer.new()


func after_each() -> void:
    _host.free()
    for id: StringName in [&"l7_fixture", &"l7_members", &"kaleidoscope"]:
        var store := SaFilterPreset.store_for(id)
        for preset_name in store.list_names():
            store.delete_preset(preset_name)
        DirAccess.remove_absolute(store.dir)
    DirAccess.remove_absolute(_root)
    SaFilterPreset.root = SaFilterPreset.default_root()


func _row(dialog: SaDialog, spec: Dictionary) -> String:
    var step := spec.duplicate()
    step["widget"] = "preset"
    return SaFilterDialogWindow._drive(dialog.row(&"preset"), step)


func test_a_preset_saves_lists_loads_and_deletes_under_the_filters_id() -> void:
    var filter := Fixture.new()
    var dialog := SaDialog.for_filter(filter)
    dialog.realize(_host)
    assert_eq(dialog.widget_name(&"preset"), "presets", "The row is the dialog's own presets widget")
    filter.set_parameters({"strength": 1.5, "inverted": true, "kind": "hard"})
    var said := _row(dialog, {"name": "Strong", "save": true})
    assert_true(said.contains("Strong"), "Save keeps the values under the name typed: %s" % said)
    var store := SaFilterPreset.store_for(&"l7_fixture")
    assert_eq(store.dir, _root.path_join("l7_fixture"), "in a directory named after the filter's id")
    assert_eq(store.list_names(), PackedStringArray(["Strong"]), "which lists it")
    assert_true(store.load_preset("Strong") is SaFilterPreset, "as a filter preset")
    _row(dialog, {"save": true})
    var again := "Saved again, the name field still holds the name and it saves over it"
    assert_eq(store.list_names(), PackedStringArray(["Strong"]), again)
    _row(dialog, {"name": "", "save": true})
    assert_eq(store.list_names(), PackedStringArray(["Preset 1", "Strong"]), "A save with no name typed finds a free one")

    filter.set_parameters({"strength": 0.25})
    _row(dialog, {"preset": "Strong"})
    assert_eq(filter.parameters(), {"strength": 1.5, "inverted": true, "kind": "hard"}, "Picking it puts every value back")
    _row(dialog, {"preset": ""})
    assert_eq(filter.parameters(), {"strength": 0.5, "inverted": false, "kind": "soft"}, "and the first entry the defaults")

    said = _row(dialog, {"delete": "Strong"})
    assert_eq(store.list_names(), PackedStringArray(["Preset 1"]), "Delete removes the file")
    assert_false(said.contains("Strong"), "and the entry")
    _row(dialog, {"delete": "Missing"})
    assert_eq(store.list_names(), PackedStringArray(["Preset 1"]), "while a name the list does not hold removes nothing")


func test_two_filters_never_list_each_others_presets() -> void:
    var fixture := SaDialog.for_filter(Fixture.new())
    fixture.realize(_host)
    _row(fixture, {"name": "Mine", "save": true})
    var members := SaDialog.for_filter(Members.new())
    members.realize(_host)
    var said := _row(members, {})
    assert_false(said.contains("Mine"), "A second filter's row shows none of the first's: %s" % said)


func test_a_filter_that_keeps_its_own_members_gets_the_same_row() -> void:
    var filter := Members.new()
    var dialog := SaDialog.for_filter(filter)
    dialog.realize(_host)
    filter.amount = 3.0
    _row(dialog, {"name": "Three", "save": true})
    filter.amount = 7.0
    _row(dialog, {"preset": "Three"})
    assert_almost_eq(filter.amount, 3.0, 0.001, "The preset goes back through the filter's own set_parameters")
    _row(dialog, {"preset": ""})
    assert_almost_eq(filter.amount, 1.0, 0.001, "and the defaults through an empty record")


func test_a_dialog_with_no_filter_draws_the_row_with_its_buttons_off() -> void:
    var dialog := SaDialog.new()
    dialog.presets()
    dialog.realize(_host)
    var row := dialog.row(&"preset").control as SaDialog.PresetsRow
    assert_not_null(row, "The row is drawn")
    assert_true(row.save_button.disabled and row.delete_button.disabled, "with nothing to save or delete")


func test_the_old_kaleidoscope_config_file_is_read_in_once() -> void:
    var old_file := _root.path_join("kaleidoscope_presets.cfg")
    DirAccess.make_dir_recursive_absolute(_root)
    var file := ConfigFile.new()
    file.set_value("Eight", "mirrors", 8)
    file.set_value("Eight", "angle", 20.0)
    file.set_value("Eight", "centre_x", 30.0)
    file.set_value("Eight", "centre_y", 60.0)
    file.save(old_file)
    var store := SaFilterPreset.store_for(&"kaleidoscope")
    Kaleidoscope.carry_over(old_file, _root.path_join("none"), &"kaleidoscope")
    var values := SaFilterPreset.values_in(store, "Eight")
    assert_eq(int(values.get("mirrors", 0)), 8, "The section comes into the store under its name")
    assert_almost_eq(float(values.get("centre_y", 0.0)), 60.0, 0.001, "with every value it held")
    assert_false(FileAccess.file_exists(old_file), "and the old file is gone, so it is read once")


func test_the_old_kaleidoscope_preset_resources_are_read_in_once() -> void:
    var old_dir := _root.path_join("kaleidoscope_presets")
    DirAccess.make_dir_recursive_absolute(old_dir)
    var text := (
        "\n"
        . join(
            [
                '[gd_resource type="Resource" load_steps=2 format=3]',
                "",
                (
                    '[ext_resource type="Script"'
                    + ' path="res://modules/sara-base-modules/kaleidoscope/kaleidoscope_preset.gd" id="1_k"]'
                ),
                "",
                "[resource]",
                'resource_name = "12 mirrors at 34 degrees"',
                'script = ExtResource("1_k")',
                "mirrors = 12",
                "angle = 34.0",
            ]
        )
    )
    var file := FileAccess.open(old_dir.path_join("12 mirrors at 34 degrees.tres"), FileAccess.WRITE)
    file.store_string(text)
    file.close()
    var store := SaFilterPreset.store_for(&"kaleidoscope")
    Kaleidoscope.carry_over(_root.path_join("none.cfg"), old_dir, &"kaleidoscope")
    var values := SaFilterPreset.values_in(store, "12 mirrors at 34 degrees")
    assert_eq(int(values.get("mirrors", 0)), 12, "The resource comes into the store under its name")
    assert_almost_eq(float(values.get("angle", 0.0)), 34.0, 0.001, "with its angle")
    assert_almost_eq(float(values.get("centre_x", 0.0)), 50.0, 0.001, "and a value the saver left out at its default")
    assert_false(DirAccess.dir_exists_absolute(old_dir), "and the old directory is gone")
