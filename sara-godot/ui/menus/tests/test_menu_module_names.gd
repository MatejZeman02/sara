## The one answer to "what is this module called".
##
## The Modules menu and the Filter menu both group their rows by the module
## that registered them, and the six lines
## that turn an id into a name live once, in `SaMenu`, since two copies of one
## question is how two menus start to disagree about it. This suite holds every
## case both menus handle.
##
## Built detached and `_ready()`ed by hand, the way `test_menus.gd` does it: a
## PopupMenu is a Window, and one in the tree hangs a headless run.
extends "res://tests/test_framework.gd"

const LOADED_ID := &"named-fixture"
const UNLOADED_ID := &"never-loaded"


## A module that says what it is called, so a name that comes back is one this
## suite put there.
class NamedModule:
    extends SaModule

    func get_id() -> StringName:
        return &"named-fixture"

    func get_name() -> String:
        return "Named Fixture"


## A module that leaves `get_id()` at its default, which is `&""`. Loaded here
## because the guard the fold added is about exactly this one being reachable.
class AnonymousModule:
    extends SaModule

    func get_name() -> String:
        return "Anonymous Fixture"


var _menu: SaMenu = null
var _bar: TopMenuBar = null


func before_each() -> void:
    _bar = TopMenuBar.new()
    _bar._ready()
    _menu = _bar.menu("Filter")
    ModuleLoader.loaded_modules[LOADED_ID] = NamedModule.new()


func after_each() -> void:
    ModuleLoader.loaded_modules.erase(LOADED_ID)
    ModuleLoader.loaded_modules.erase(&"anonymous-folder")
    _bar.free()
    _bar = null
    _menu = null


func test_a_loaded_module_answers_with_its_own_name() -> void:
    assert_eq(_menu.module_display_name(LOADED_ID), "Named Fixture", "The module's own get_name(), not its id")


func test_a_module_that_is_not_loaded_answers_with_its_id() -> void:
    assert_eq(
        _menu.module_display_name(UNLOADED_ID),
        "never-loaded",
        "A registration whose module never loaded still names something, which is what a test fixture looks like"
    )


func test_a_registration_nobody_attributed_answers_with_the_word_it_was_given() -> void:
    assert_eq(_menu.module_display_name(&""), "", "Nothing by default, which is the empty separator the Modules menu draws")
    assert_eq(_menu.module_display_name(&"", "Filters"), "Filters", "and the caller's own word when it has one")


## The guard the fold added: `SaModule.get_id()` is `&""` by default, so an
## unattributed group walking the loaded modules would match the first one that
## never overrode it and draw that module's name over a group it has nothing to
## do with.
func test_an_unattributed_group_never_takes_an_anonymous_modules_name() -> void:
    ModuleLoader.loaded_modules[&"anonymous-folder"] = AnonymousModule.new()

    assert_eq(_menu.module_display_name(&"", "Filters"), "Filters", "The empty id is answered before the walk, not by it")
    assert_eq(_menu.module_display_name(LOADED_ID), "Named Fixture", "and a real id still finds its own module")


## Both menus reach the one implementation, which is the whole of the filing.
func test_both_menus_answer_through_the_same_method() -> void:
    for menu_name: String in ["Filter", "Modules"]:
        var menu: SaMenu = _bar.menu(menu_name)
        assert_true(menu.has_method("module_display_name"), "%s answers through SaMenu" % menu_name)
        assert_false(menu.has_method("_module_display_name"), "%s carries no copy of its own" % menu_name)
        assert_eq(menu.module_display_name(LOADED_ID), "Named Fixture", "%s reads the same name" % menu_name)
