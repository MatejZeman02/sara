## The Modules menu lists the loaded modules in a submenu of their own, because
## the list can get long. What this suite reads is the menu as it is
## built: one row that opens a list, the module actions and Develop under it and
## no module's row in the menu itself, and in the list a row per loaded, refused
## and switched off module with Turn Modules On or Off… at its foot. A press on
## a module's row goes back to the menu's handler, which opens the Modules
## window on its page, and the row at the foot opens Preferences on
## the Modules page. That emit is deferred and a test that awaits
## drops every assertion after the await (a Godot trap), so the page each row leads
## to is read from `page_for`, and the frame that opens it is
## `scenarios/the-modules-menu-lists-the-loaded-modules-in-a-submenu-of-their-own.json`.
##
## Built detached and `_ready()`ed by hand: a popup is a `Window`, and a bar in
## the tree hangs a headless run.
extends "res://tests/test_framework.gd"

## A refused module and a switched off one, added for the length of a test so
## the list has one of each whatever the run's own modules folder held.
const FAILED_ID := &"refused"
const FAILED_WHY := "its module.gd does not parse"
const OFF_ID := &"switched_off"
const OFF_NAME := "Switched Off Module"

var _bar: TopMenuBar = null
var _menu: SaModulesMenu = null


func before_each() -> void:
    ModuleLoader.failed_modules[FAILED_ID] = FAILED_WHY
    ModuleLoader.off_modules[OFF_ID] = "asked off in Preferences"
    ModuleLoader.module_names[OFF_ID] = OFF_NAME
    _bar = TopMenuBar.new()
    _bar._ready()
    var note_mode := SaNoteMode.new()
    _bar.add_child(note_mode)
    _bar.bind_commands(SaTestFixtures.make_menu_registries(note_mode).commands)
    _menu = _bar.menu("Modules") as SaModulesMenu


func after_each() -> void:
    ModuleLoader.failed_modules.erase(FAILED_ID)
    ModuleLoader.off_modules.erase(OFF_ID)
    ModuleLoader.module_names.erase(OFF_ID)
    if _bar != null:
        _bar.free()
        _bar = null
    _menu = null


## The ids of *popup*'s rows, in order.
func _ids(popup: SaChoicePopup) -> Array:
    var out := []
    for row_id: StringName in popup.row_ids():
        out.append(SaMenu.id_of(row_id))
    return out


## What the loader holds, in the order the list draws it: loaded, refused, off.
func _module_count() -> int:
    return ModuleLoader.loaded_modules.size() + ModuleLoader.failed_modules.size() + ModuleLoader.off_modules.size()


func test_the_menu_holds_one_row_that_opens_the_list_and_no_module_row() -> void:
    assert_not_null(_menu, "The bar builds the Modules menu")
    if _menu == null:
        return
    var popup := _menu.popup
    var ids := _ids(popup)
    assert_eq(ids[0], SaModulesMenu.ID_ACTIVE_MODULES, "The first row is Active Modules")
    assert_eq(popup.row_labels()[0], "Active Modules", "and says so")
    assert_true(popup.is_branch(SaMenu.key(SaModulesMenu.ID_ACTIVE_MODULES)), "and opens a list rather than running")
    assert_false(popup.section_titles().has("Active Modules"), "No heading of that name is left in the menu")
    for id: int in ids:
        assert_false(SaModulesMenu.page_for(id) == SaModulesPage.TITLE, "row %d is no module's and not the switch row" % id)
    assert_true(ids.has(SaModulesMenu.ID_OPEN_USER_FOLDER), "and the Develop rows are under it")
    assert_eq(popup.section_titles()[popup.section_titles().size() - 1], "Develop", "Develop still ends the menu")


func test_the_list_holds_every_module_and_the_switch_row_at_its_foot() -> void:
    if _menu == null:
        return
    var list := _menu.show_modules()
    assert_not_null(list, "The row's list is filled without a tree")
    assert_eq(list.get_parent(), _menu.popup, "as the menu's child window")
    var ids := _ids(list)
    var count := _module_count()
    assert_eq(ids.size(), count + 1, "a row per module and one more: %s" % [list.row_labels()])
    for i in count:
        assert_eq(ids[i], SaModulesMenu.MODULE_ROW_BASE + i, "module row %d has the id it had" % i)
    assert_eq(ids[ids.size() - 1], SaModulesMenu.ID_SWITCH_MODULES, "Turn Modules On or Off... is last")
    assert_eq(list.row_labels()[ids.size() - 1], "Turn Modules On or Off...", "and says so")

    var labels := list.row_labels()
    var i := 0
    for module_id: StringName in ModuleLoader.loaded_modules:
        assert_eq(labels[i], ModuleLoader.loaded_modules[module_id].get_name(), "a loaded module by its name")
        assert_false(list.is_disabled(SaMenu.key(ids[i])), "at full strength")
        i += 1
    var failed_at := labels.find("%s: %s" % [FAILED_ID, FAILED_WHY])
    assert_true(failed_at >= 0, "the refused module with its reason: %s" % [labels])
    if failed_at >= 0:
        assert_true(list.is_disabled(SaMenu.key(ids[failed_at])), "dimmed")
    assert_true(labels.has("%s: off" % OFF_NAME), "the switched off module as it was")


## A module's row opens the Modules window on its page, and the row under the
## list opens Preferences, Modules, where the switches are.
func test_a_press_on_a_module_row_opens_its_page_and_the_last_row_preferences() -> void:
    if _menu == null:
        return
    var list := _menu.show_modules()
    assert_eq(
        _menu.module_list._press_back, Callable(_menu, "on_id_pressed"), "A press in the list goes back to the menu's handler"
    )
    for row_id: StringName in list.row_ids():
        var id := SaMenu.id_of(row_id)
        if id == SaModulesMenu.ID_SWITCH_MODULES:
            assert_eq(SaModulesMenu.page_for(id), SaModulesPage.TITLE, "The row under the list opens Preferences on Modules")
            continue
        assert_true(_menu.module_list.row_modules.has(id), "row %d stands for a module, whose page it opens" % id)
        assert_eq(SaModulesMenu.page_for(id), "", "and not Preferences")
    assert_eq(SaModulesMenu.page_for(SaModulesMenu.ID_ACTIVE_MODULES), "", "The menu's own row opens the list instead")


## Building the menu twice draws the row and the list once each.
func test_a_second_build_draws_the_list_once() -> void:
    if _menu == null:
        return
    _menu.populate()
    _menu.show_modules()
    var list := _menu.show_modules()
    assert_eq(_menu.popup.row_labels().count("Active Modules"), 1, "One Active Modules row")
    assert_eq(list.row_labels().size(), _module_count() + 1, "and one row per module in its list")
