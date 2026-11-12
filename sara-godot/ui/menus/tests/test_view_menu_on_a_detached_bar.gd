## Every run of the app must end without errors out of the module loader.
##
## `ModuleLoader._exit_tree` unloads every module, each unload unregisters its
## commands, each unregistration repopulates the View menu, and `sync_view_checks`
## then asked `bar.get_tree()` on a bar that was already leaving the tree:
##
##     ERROR: Parameter "data.tree" is null.
##        [0] _main_surface (res://ui/menus/view_menu.gd:318)
##        [1] sync_view_checks (res://ui/menus/view_menu.gd:348)
##        [2] _add_items (res://ui/menus/view_menu.gd:133)
##
## `_main_surface` had a guard for this and it tested the wrong thing. It read
## `var tree := bar.get_tree()` and checked the answer for null, and `get_tree()`
## on a node outside the tree prints the error *before* it answers. The question
## that costs nothing is `is_inside_tree()`, which `sa_menu.gd`'s `main_canvas()`
## asks and which never prints one.
##
## **"The run is quiet" is not assertable from inside GDScript**, which is the
## same limit `ui/main/tests/test_deferred_open.gd` records. Nothing here can read
## the runner's own log. So what this suite asserts is the decision behind the
## quiet, on a bar built the way the defect needs it, and the count of the line
## in a full run is the other half, checked by hand against the runner's log.
extends "res://tests/test_framework.gd"

## `TopMenuBar._ready()` builds every menu, and the View menu reaches for the
## registries and the canvas.
const REQUIRES_GPU := true


## A bar built the way `ui/top_bar/tests/test_window_button_style.gd` builds one and the
## way the loader leaves one at shutdown: never parented, `_ready()` by hand.
func _detached_bar() -> TopMenuBar:
    var bar := TopMenuBar.new()
    bar._ready()
    return bar


func test_a_bar_built_by_hand_is_outside_the_tree() -> void:
    var bar := _detached_bar()
    assert_false(bar.is_inside_tree(), "the fixture is the case, or the rest of this suite proves nothing")
    bar.free()


## The View menu no longer looks for a surface of its own. Its mirror ticks are
## the commands' own answers, which read the tool machine the router was handed
## and never the tree, so the question the defect asked is gone.
func test_the_view_menu_answers_that_it_is_outside_the_tree_without_asking_the_tree() -> void:
    var bar := _detached_bar()
    var menu := _view_menu(bar)
    assert_true(menu != null, "the bar built a View menu")

    assert_false(menu.in_tree(), "a detached bar's menu knows it is outside the tree")
    assert_null(menu.main_canvas(), "so it has no main canvas to offer")
    bar.free()


## The repopulation the loader triggers, run twice, because `_exit_tree`
## unregisters more than one module and each one repopulates.
func test_populating_twice_on_a_detached_bar_leaves_the_mirror_ticks_off() -> void:
    var bar := _detached_bar()
    bar.bind_commands(SaTestFixtures.make_menu_registries().commands)
    var menu := _view_menu(bar)

    menu.populate()
    menu.populate()
    menu.sync_ticks()

    assert_true(menu.has_item(SaViewMenu.ID_MIRROR_H), "the horizontal mirror row is on the menu")
    assert_true(menu.has_item(SaViewMenu.ID_MIRROR_V), "and the vertical one")
    assert_false(menu.is_item_checked(SaViewMenu.ID_MIRROR_H), "no view to read a flip from, so the tick stays off")
    assert_false(menu.is_item_checked(SaViewMenu.ID_MIRROR_V), "and the same for the vertical one")
    bar.free()


## The bar's own View menu, through the door the bar offers rather than through
## a field, and cast so a bar that fills "View" with something else fails here.
func _view_menu(bar: TopMenuBar) -> SaViewMenu:
    return bar.menu("View") as SaViewMenu
