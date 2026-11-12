## The Modules menu draws a loaded module at full strength.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Every loaded row was once built with `disabled` true, which dims it, so
## four working modules read as four refusals told apart only by the tick. A
## loaded row is enabled now and a refusal is still dimmed, and a press on the
## loaded one still does nothing: no command runs.
##
## No module row carries a tick box. Each row was ticked
## and its tip said unticking unloaded the module, and the box only went back
## on a press, so the tick lied. A row says at its right where the module came
## from instead: "Built in", or the name of its folder for one the painter put
## in their own modules folder.
##
## The module rows are a list the Active Modules row opens beside the menu,
## and this suite reads that list.
##
## The bar is built detached and `_ready()`ed by hand, the way `test_menus.gd`
## does it, because a list in the tree is a Window and hangs a headless run. A
## loaded module, one from the painter's folder and a refused one are put into
## the loader for the length of each test and taken out again, so the rows
## asserted on are known whatever the run itself happened to load. The pictures
## are `scenarios/the-modules-menu-dims-every-module-that-loaded.json` and
## `scenarios/a-shipped-modules-row-says-what-unticking-does-and-does-it.json`.
extends "res://tests/test_framework.gd"

const LOADED_ID := &"loaded-probe"
const REFUSED_ID := &"d75-refused"
const USER_ID := &"folder-probe"
const USER_DIR := "/probe/modules/folder-probe"


class LoadedModule:
    extends SaModule

    func get_id() -> StringName:
        return &"loaded-probe"

    func get_name() -> String:
        return "Loaded Probe"


class UserModule:
    extends SaModule

    func get_id() -> StringName:
        return &"folder-probe"

    func get_name() -> String:
        return "Folder Probe"


func before_each() -> void:
    ModuleLoader.loaded_modules[LOADED_ID] = LoadedModule.new()
    ModuleLoader.failed_modules[REFUSED_ID] = "module.gd does not extend SaModule"
    ModuleLoader.loaded_modules[USER_ID] = UserModule.new()
    ModuleLoader.origins[USER_ID] = "user"
    ModuleLoader.module_dirs[USER_ID] = USER_DIR


func after_each() -> void:
    ModuleLoader.loaded_modules.erase(LOADED_ID)
    ModuleLoader.failed_modules.erase(REFUSED_ID)
    ModuleLoader.loaded_modules.erase(USER_ID)
    ModuleLoader.origins.erase(USER_ID)
    ModuleLoader.module_dirs.erase(USER_ID)


func _make_bar() -> TopMenuBar:
    var bar := TopMenuBar.new()
    bar._ready()
    return bar


## The list Active Modules opens beside the Modules menu, where the module rows
## stand, apart from the menu itself.
func _module_list(bar: TopMenuBar) -> SaChoicePopup:
    return (bar.menu("Modules") as SaModulesMenu).show_modules()


## The row id the menu gave the row whose label is *label*, or "".
func _row_labelled(popup: SaChoicePopup, label: String) -> StringName:
    var at := popup.row_labels().find(label)
    return popup.row_ids()[at] if at >= 0 else &""


func test_a_loaded_row_is_enabled_and_a_refused_row_is_dimmed() -> void:
    var bar := _make_bar()
    var popup := _module_list(bar)
    var loaded := _row_labelled(popup, "Loaded Probe")
    var refused := _row_labelled(popup, "%s: %s" % [REFUSED_ID, ModuleLoader.failed_modules[REFUSED_ID]])
    assert_false(loaded.is_empty(), "The loaded module has a row")
    assert_false(refused.is_empty(), "and so does the refused one")

    assert_false(popup.is_disabled(loaded), "A loaded row is not disabled, so it is not dimmed")
    var loaded_alpha := popup.row_of(loaded).label_button().modulate.a
    var full := is_equal_approx(loaded_alpha, SaChoicePopup.PLAIN_ALPHA)
    assert_true(full, "and its label is drawn at full strength: %s" % loaded_alpha)

    assert_true(popup.is_disabled(refused), "A refused row is still disabled")
    var refused_alpha := popup.row_of(refused).label_button().modulate.a
    var dimmed := is_equal_approx(refused_alpha, SaChoicePopup.DISABLED_ALPHA)
    assert_true(dimmed, "and drawn dimmed: %s" % refused_alpha)

    # Every module the run itself loaded is built the same way as the fake one.
    for module_id: StringName in ModuleLoader.loaded_modules:
        var title: String = (ModuleLoader.loaded_modules[module_id] as SaModule).get_name()
        var row := _row_labelled(popup, title)
        assert_false(popup.is_disabled(row), "%s is not dimmed" % title)
    bar.free()


## No module row has a box to tick, loaded, from the painter's folder or
## refused, so there is no tick to move and nothing promises an unload.
func test_no_module_row_carries_a_tick_box() -> void:
    var bar := _make_bar()
    var popup := _module_list(bar)
    var titles: Array[String] = ["%s: %s" % [REFUSED_ID, ModuleLoader.failed_modules[REFUSED_ID]]]
    for module_id: StringName in ModuleLoader.loaded_modules:
        titles.append((ModuleLoader.loaded_modules[module_id] as SaModule).get_name())
    for title in titles:
        var row := _row_labelled(popup, title)
        assert_false(row.is_empty(), "%s has a row" % title)
        assert_null(popup.check_box(row), "and no tick box: %s" % title)
        var tip := popup.label_button(row).tooltip_text
        assert_false(tip.containsn("untick"), "and its tip promises no unload: %s" % tip)
    bar.free()


## A shipped module says "Built in" at its right, one from the painter's folder
## says that folder's name, and its tip the whole path.
func test_a_row_says_where_its_module_came_from() -> void:
    var bar := _make_bar()
    var popup := _module_list(bar)
    var shipped := _row_labelled(popup, "Loaded Probe")
    assert_eq(popup.row_of(shipped).hint_text(), "Built in", "A shipped module's row says it is built in")
    assert_eq(popup.label_button(shipped).tooltip_text, "Built into Sara.", "and so does its tip")

    var user := _row_labelled(popup, "Folder Probe")
    assert_eq(popup.row_of(user).hint_text(), "folder-probe", "A module from the painter's folder names its folder")
    var tip := popup.label_button(user).tooltip_text
    assert_eq(tip, "From the folder %s" % USER_DIR, "and its tip gives the whole path")
    bar.free()


## Enabled, but still quiet: a press on the label runs no command of the
## module's and leaves the row as it was. It opens the Modules
## window on the module's page.
func test_a_press_on_a_loaded_row_changes_nothing() -> void:
    var bar := _make_bar()
    var popup := _module_list(bar)
    var loaded := _row_labelled(popup, "Loaded Probe")

    var rows: Dictionary = (bar.menu("Modules") as SaModulesMenu).module_list.row_modules
    assert_true(rows.values().has(LOADED_ID), "A module's row leads to the Modules window on its page")
    assert_true(popup.press_row(loaded), "The label takes a press now that it is enabled")
    assert_false(popup.is_disabled(loaded), "and the row is as it was after it")
    assert_null(popup.check_box(loaded), "with no box for the press to have flipped")
    bar.free()
