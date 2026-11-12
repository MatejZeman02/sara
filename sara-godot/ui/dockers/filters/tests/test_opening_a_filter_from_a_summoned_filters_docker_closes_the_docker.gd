## Opening a filter from a summoned Filters docker closes the
## docker.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Opening a filter from the filter browser closes it. Held here: the docker summoned locked through `FiltersDocker.summon`,
## wide over the canvas, and a filter opened from it by its Open button, the
## filter's dialog is open on that filter and the docker is shut, back in its
## strip at the strip's size, its summon and its lock over, with nothing written
## to the layout. A docker shown in its place and not summoned stays up where it
## stands after Open, and one that Browse Filters... summoned out of its place
## goes back to that place, shown.
##
## Built the way the Filters docker's own suite builds the docker, in a `SubViewport` of a
## capture's size with subwindows embedded, under a `MainDockers` as the app
## holds it. The running app is
## `scenarios/opening-a-filter-from-a-summoned-filters-docker-closes-the-docker.json`.
extends "res://tests/test_framework.gd"

const Teardown := preload("res://tests/fixtures/teardown.gd")
const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")

## The dialog runs the filter over the easel's layer on open.
const REQUIRES_GPU := true

const OWNER := &"suite"

## The capture's window, which the shipped layouts are fitted to.
const SCREEN := Vector2i(1920, 1048)

## Where a summon is asked for, over the middle of the canvas.
const POINT := Vector2i(960, 540)

const SECTION := "FiltersDocker"


## The layout store `MainDockers` is built with, counting what would write the
## layout or fork a preset, and with the answers that wait on a compositor or
## listen to the embedding switch stubbed, as the summon suite stubs them.
class LayoutStore:
    extends DockerLayoutStore

    var saves: int = 0
    var forks: int = 0

    func _ready() -> void:
        pass

    func save(_by_painter: bool = false) -> void:
        saves += 1

    func fork_for_painter_edit() -> String:
        forks += 1
        return ""

    func reapply_deferred(_win: Window, _section: String) -> void:
        pass

    func list_presets() -> Array[String]:
        return []

    func current_preset() -> String:
        return ""


var _kept_scale: float = 1.0
var _kept_embedding: bool = true
var _host: Node = null
var _easel: SaEasel = null
var _canvas: SaCanvas = null
var _registry: SaFilterRegistry = null
var _blur := StringName()
var _dialog: SaFilterDialogWindow = null
var _docker: FiltersDocker = null
var _store: LayoutStore = null

## Where the docker stands in the layout, the strip 160 wide the shipped
## layouts keep for it.
var _strip := Rect2i()


func before_each() -> void:
    _kept_scale = SaUI.user_scale
    SaUI.user_scale = 1.0
    var tree := Engine.get_main_loop() as SceneTree
    _kept_embedding = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    _host = Node.new()
    _host.name = "U39FiltersHost"
    EventBus.add_child(_host)
    var screen := SubViewport.new()
    screen.size = SCREEN
    screen.gui_embed_subwindows = true
    _host.add_child(screen)

    _easel = Bench.easel(Vector2i(256, 256))
    _canvas = SaCanvas.new()
    _canvas.easel = _easel
    _registry = SaFilterRegistry.new()
    _registry.register(SaGaussianBlurFilter.new(), OWNER)
    _blur = SaFilterRegistry.key_for(OWNER, SaGaussianBlurFilter.new())
    _easel.compositor.filter_chain.registry = _registry

    _dialog = SaFilterDialogWindow.new()
    _dialog.target_canvas = _canvas
    _dialog.watch(_registry)
    screen.add_child(_dialog)

    _docker = FiltersDocker.new()
    _docker.browser.watch(_registry, SaCommandRegistry.new())
    var ui := SaUIRegistry.new()
    ui.register_docker(SaDockerIds.FILTERS, "Filters", func() -> Window: return Window.new(), &"")
    ui.set_docker_node(SaDockerIds.FILTERS, _docker)
    _store = LayoutStore.new()
    var dockers := MainDockers.new(ui, _store)
    screen.add_child(dockers)
    dockers.add_child(_docker)
    _docker.size = SaUI.window_size_for(_docker, FiltersDocker.DEFAULT_SIZE)
    _docker.position = SaUI.window_size_for(_docker, FiltersDocker.DEFAULT_POSITION)
    _strip = Rect2i(_docker.position, _docker.size)


func after_each() -> void:
    if _dialog != null and is_instance_valid(_dialog):
        _dialog.free()
    _dialog = null
    if _host != null and is_instance_valid(_host):
        _host.free()
    _host = null
    _docker = null
    _store = null
    Teardown.free_nodes([_canvas, _easel])
    _canvas = null
    _easel = null
    _registry = null
    SaUI.user_scale = _kept_scale
    (Engine.get_main_loop() as SceneTree).root.gui_embed_subwindows = _kept_embedding


func test_open_on_a_summoned_docker_opens_the_dialog_and_sends_the_docker_back_shut() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    assert_false(_docker.visible, "Before the summon the docker is shut, as a fresh profile keeps it")
    assert_true(FiltersDocker.summon(tree, true, POINT), "FiltersDocker.summon finds the docker and its manager")
    assert_true(_store.is_borrowed(SECTION), "The docker is out on a summon")
    assert_true(SaDockerLock.is_locked(_docker), "locked")
    assert_true(_docker.visible, "and shown")
    var wide := SaUI.window_size_for(_docker, FiltersDocker.OPEN_SIZE)
    assert_true(_docker.size.x >= wide.x and _docker.size.y >= wide.y, "wide, at %s" % _docker.size)
    var saves := _store.saves
    var forks := _store.forks

    assert_true(_docker.browser.pick(_blur), "The blur is picked")
    _docker.browser.open_button.pressed.emit()

    var dialog := _dialog.describe()
    assert_true(dialog["open"], "Open opens the filter's dialog")
    assert_eq(dialog["filter"], SaGaussianBlurFilter.new().title(), "on the blur")
    assert_false(_docker.visible, "and the docker is shut")
    assert_false(_docker.describe()["open"], "which its dump says")
    assert_false(_store.is_borrowed(SECTION), "its summon over")
    assert_false(SaDockerLock.is_locked(_docker), "and the lock gone with it")
    assert_eq(Rect2i(_docker.position, _docker.size), _strip, "back in its strip, at the strip's size")
    assert_eq(_store.saves, saves, "Nothing is written to the layout")
    assert_eq(_store.forks, forks, "and no layout is forked")


func test_open_on_a_docker_in_its_place_leaves_it_up() -> void:
    _docker.show()
    assert_false(_store.is_borrowed(SECTION), "Shown in its strip, the docker is not out on a summon")

    assert_true(_docker.browser.pick(_blur), "The blur is picked")
    _docker.browser.open_button.pressed.emit()

    assert_true(_dialog.describe()["open"], "Open opens the filter's dialog")
    assert_true(_docker.visible, "and the docker in its place is still shown")
    assert_eq(Rect2i(_docker.position, _docker.size), _strip, "where it stood")


## Browse Filters... summons the docker unlocked, and summons it out of its
## strip when the layout shows it there. Open sends it back to the strip,
## shown, rather than hiding a docker the painter keeps in the layout.
func test_open_on_a_docker_summoned_out_of_its_place_puts_it_back_shown() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    _docker.show()
    assert_true(FiltersDocker.summon(tree, false, POINT), "Browse Filters... summons the docker in its strip")
    assert_true(_store.is_borrowed(SECTION), "out on a summon")
    assert_true(Rect2i(_docker.position, _docker.size) != _strip, "away from the strip, at %s" % _docker.size)
    var saves := _store.saves

    assert_true(_docker.browser.pick(_blur), "The blur is picked")
    _docker.browser.open_button.pressed.emit()

    assert_true(_dialog.describe()["open"], "Open opens the filter's dialog")
    assert_false(_store.is_borrowed(SECTION), "and ends the summon")
    assert_true(_docker.visible, "the docker shown, as the summon found it")
    assert_eq(Rect2i(_docker.position, _docker.size), _strip, "in its strip")
    assert_eq(_store.saves, saves, "with nothing written to the layout")
