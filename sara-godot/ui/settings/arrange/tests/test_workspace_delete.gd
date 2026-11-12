## The Delete button of the layouts forgets the layout its dropdown shows. It was the Workspace page's, and is
## Layouts and dockers'.
##
## The dropdown is an `SaChoiceButton`, so a Delete handler reading
## `item_count` and `get_item_metadata(selected)` off it, which only an
## `OptionButton` answers, would be a script error and the layout would stay.
## What is here is the handler on a page in the tree, with a store it finds the way
## the running app's page does, by name from the root.
extends "res://tests/test_framework.gd"

static var scratch_layout_path: String = SaDataRoot.path("test_workspace_delete_layout.cfg")
const MINE := "mine"

var _host: Node = null
var _docker: Window = null
var _store: DockerLayoutStore = null
var _page: SaDockersPage = null
var _saved_state := ConfigFile.new()


func before_each() -> void:
    _saved_state = ConfigFile.new()
    _host = Node.new()
    _host.name = "Host"
    EventBus.add_child(_host)
    _docker = Window.new()
    _docker.visible = false
    _store = DockerLayoutStore.new()
    _store.name = "DockerLayoutStore"
    _store.path = scratch_layout_path
    _store.dockers_provider = func() -> Array: return [{"id": "ProbeDocker", "name": "Probe", "node": _docker}]
    _store.save_allowed = func() -> bool: return true
    _host.add_child(_store)
    _store.presets().capture(_saved_state)


func after_each() -> void:
    if is_instance_valid(_page):
        _page.free()
    _store.delete_preset(MINE)
    _store.presets().apply(_saved_state)
    DirAccess.remove_absolute(scratch_layout_path)
    if is_instance_valid(_docker):
        _docker.free()
    if is_instance_valid(_host):
        _host.free()


func _page_in_the_tree() -> SaDockersPage:
    _page = SaDockersPage.new()
    _host.add_child(_page)
    return _page


func test_delete_forgets_the_layout_the_dropdown_shows() -> void:
    assert_true(_store.save_preset(MINE), "a painter's layout is saved")
    var page := _page_in_the_tree()
    var dropdown := page.find_child("WorkspacePresetOpt", true, false) as SaChoiceButton
    assert_eq(String(dropdown.selected_value()), MINE, "and the dropdown shows it, as the one in use")

    assert_true(page.delete_chosen_layout(), "Delete reports the layout forgotten")
    assert_false(_store.list_presets().has(MINE), "and the store no longer lists it")
    assert_false(dropdown.choice_labels().has(MINE), "nor does the dropdown, filled again")


func test_the_button_press_is_the_same_door() -> void:
    assert_true(_store.save_preset(MINE), "a painter's layout is saved")
    var page := _page_in_the_tree()
    var button := page.find_child("WorkspacePresetDelete", true, false) as Button

    button.pressed.emit()

    assert_false(_store.list_presets().has(MINE), "a press on Delete forgets it, with no script error in the way")


## Delete on a shipped layout nobody saved over forgot nothing and
## said nothing. It is dimmed on the check `forget` makes, a file of the
## painter's under the chosen name, and a layout of the painter's lights it.
func test_delete_is_dimmed_on_a_shipped_layout_and_lit_on_the_painters() -> void:
    var page := _page_in_the_tree()
    var dropdown := page.find_child("WorkspacePresetOpt", true, false) as SaChoiceButton
    var button := page.find_child("WorkspacePresetDelete", true, false) as Button
    var shipped := ""
    for preset_name: String in _store.list_presets():
        if _store.presets().is_shipped(preset_name) and not _store.presets().can_forget(preset_name):
            shipped = preset_name
    assert_false(shipped.is_empty(), "There is a shipped layout nobody saved over")
    dropdown.pick_row(dropdown.choice_values().find(shipped))
    assert_true(button.disabled, "and choosing it offers no Delete")

    assert_true(_store.save_preset(MINE), "a painter's layout is saved")
    page.refresh_layouts()
    assert_eq(String(dropdown.selected_value()), MINE, "the dropdown shows it")
    assert_false(button.disabled, "and Delete is lit for it")
