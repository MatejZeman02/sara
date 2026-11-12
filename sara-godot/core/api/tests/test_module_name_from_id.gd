## What a module that never named itself is called.
##
## `SaModule.get_name()` answered "Unnamed Module", and the spec's template is
## `get_id()` and `register()` and nothing else, so the Filter menu drew that
## word over the one row a student went looking for. The default now reads the
## id, which is the only thing such a module did declare about itself.
##
## The menu half is built detached and `_ready()`ed by hand, the way
## `test_menu_module_names.gd` does it: a PopupMenu is a Window, and one in the
## tree hangs a headless run.
extends "res://tests/test_framework.gd"

const NAMELESS_ID := &"box_blur"


## An id and no name, which is the template's shape and the whole of the defect.
class NamelessModule:
    extends SaModule

    func get_id() -> StringName:
        return &"box_blur"


## A folder-shaped id, the spelling the two modules shipped in this tree use.
class HyphenatedModule:
    extends SaModule

    func get_id() -> StringName:
        return &"sara-base-modules"


## Both overridden, which is what every module in the tree does today and what
## the change must not touch.
class NamedModule:
    extends SaModule

    func get_id() -> StringName:
        return &"box_blur"

    func get_name() -> String:
        return "A Blur of My Own"


var _bar: TopMenuBar = null


func after_each() -> void:
    ModuleLoader.loaded_modules.erase(NAMELESS_ID)
    if _bar != null:
        _bar.free()
        _bar = null


# --- The default itself ---------------------------------------------------------------


func test_a_module_that_declares_only_an_id_is_called_after_it() -> void:
    assert_eq(NamelessModule.new().get_name(), "Box Blur", "The id in words, not a placeholder")


## A folder with no `module.gd`, such as a student's copy of the box blur, is
## the bare module the loader makes of it, named after the folder.
func test_the_box_blur_folder_names_itself() -> void:
    var module := SaModule.new(SaDataRoot.path("modules/box-blur"))

    assert_eq(module.get_id(), &"box_blur", "the folder's name, its hyphen read as an underscore")
    assert_eq(module.get_name(), "Box Blur", "and it reads as words, not as Unnamed Module")


func test_a_hyphenated_id_reads_as_words_too() -> void:
    assert_eq(HyphenatedModule.new().get_name(), "Sara Base Modules", "A hyphen separates words the way an underscore does")


func test_a_module_that_names_itself_still_wins() -> void:
    assert_eq(NamedModule.new().get_name(), "A Blur of My Own", "An override is the answer, derived or not")


## A module made of no folder, with neither id nor name, has nothing here to be
## derived from and keeps the old word. `test_sara_module_base.gd` is what says that
## word is never empty, because the Modules menu draws whatever comes back.
func test_a_module_that_declares_nothing_at_all_keeps_the_old_word() -> void:
    assert_eq(SaModule.new().get_name(), "Unnamed Module", "Nothing declared, nothing to derive")


# --- What the menus draw --------------------------------------------------------------


## The separator. Through `SaMenu.module_display_name`, which
## is the one answer both menus share, so this is the row itself.
func test_both_menus_draw_the_derived_name_over_the_modules_rows() -> void:
    _bar = TopMenuBar.new()
    _bar._ready()
    ModuleLoader.loaded_modules[NAMELESS_ID] = NamelessModule.new()

    for menu_name: String in ["Filter", "Modules"]:
        var menu: SaMenu = _bar.menu(menu_name)
        assert_eq(menu.module_display_name(NAMELESS_ID), "Box Blur", "%s heads the group with a name" % menu_name)


## The Modules menu's own list asks the module directly rather than through the
## fold, because there it holds the instance and not an id.
func test_the_active_modules_list_asks_the_module_itself() -> void:
    ModuleLoader.loaded_modules[NAMELESS_ID] = NamelessModule.new()
    var listed: SaModule = ModuleLoader.loaded_modules[NAMELESS_ID]

    assert_eq(listed.get_name(), "Box Blur", "the row the Active Modules submenu ticks")
