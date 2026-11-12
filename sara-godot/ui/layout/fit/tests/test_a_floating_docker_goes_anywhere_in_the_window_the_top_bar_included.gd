## A floating docker goes anywhere in the window, the top bar included.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A painter may want a docker, the Navigator say, right up against the top bar.
## A drag of an embedded docker must not stop at the first row below the bar, and
## the store's reflow and restore must not put a docker back under it. The only
## limit is
## [constant SaDockerLayoutFit.STRIP_IN_REACH] of the title strip on the
## window, the window's own top row included. Dialogs, the Window menu's show
## and the shipped layouts still open under the bar. Each case is a docker
## embedded in a 1280 by 1024 host under a bar 79 rows tall, `MainDockers.below_bar`
## with the second row on. The running app is
## `scenarios/a-floating-docker-goes-anywhere-in-the-window-the-top-bar-included.json`.
extends "res://tests/test_framework.gd"

const HOST := Vector2i(1280, 1024)
const SIZE := Vector2i(300, 400)

## The first row below the bar at 1280 by 1024.
const BAR := 79

const STRIP := SaDockerLayoutFit.STRIP_IN_REACH

## Where the bar is pressed, from the docker's corner.
const PRESS := Vector2(150, 10)

## Where the painter puts the docker, over the bar.
const OVER_THE_BAR := Vector2i(400, 12)

const SCRATCH := "test_a_floating_docker_goes_anywhere.cfg"
const SECTION := "NavigatorProbe"

var _kept_inset: Callable = Callable()
var _kept_embedding: bool = true
var _root: Node = null
var _viewport: SubViewport = null


## Parented to an autoload, because the runner calls this from its own `_ready`
## and a parent mid-`_ready` rejects `add_child`.
func before_each() -> void:
    _kept_inset = SaDialogWindow.top_inset
    SaDialogWindow.top_inset = func() -> int: return BAR
    var tree := Engine.get_main_loop() as SceneTree
    _kept_embedding = tree.root.gui_embed_subwindows
    # A window added outside the screen below would map a real OS window and
    # block the run, so the root embeds as well.
    tree.root.gui_embed_subwindows = true
    _root = Node.new()
    _root.name = "AnywhereInTheWindowTestHost"
    EventBus.add_child(_root)
    _viewport = SubViewport.new()
    _viewport.size = HOST
    _viewport.gui_embed_subwindows = true
    _root.add_child(_viewport)


func after_each() -> void:
    SaDialogWindow.top_inset = _kept_inset
    DockerDragHandle.capture_pointer = null
    var tree := Engine.get_main_loop() as SceneTree
    tree.root.gui_embed_subwindows = _kept_embedding
    if _root != null and is_instance_valid(_root):
        _root.free()
    _root = null
    if FileAccess.file_exists(SaDataRoot.path(SCRATCH)):
        DirAccess.remove_absolute(SaDataRoot.path(SCRATCH))


## Dragged up from under the bar, the docker stands over it where the pointer
## let go, and dragged on past the window's top it stops at the top row, its
## whole strip still on the window.
func test_a_drag_takes_it_over_the_bar_and_stops_it_at_the_window_s_top() -> void:
    var window := _docker(Vector2i(400, 300))
    _drag(window, Vector2(0, -288))
    assert_eq(window.position, OVER_THE_BAR, "Where the pointer took it, over the bar")
    assert_true(window.position.y < BAR, "Its title strip stands over the bar")
    _drag(window, Vector2(0, -600))
    assert_eq(window.position, Vector2i(400, 0), "Dragged on past the top, it stops at the window's top row")
    assert_true(_strip_in(window), "with the whole strip still inside")


## A drag past the top and sideways at once keeps both limits of the strip.
func test_a_drag_past_the_top_left_corner_keeps_the_strip_in() -> void:
    var window := _docker(Vector2i(100, 300))
    _drag(window, Vector2(-500, -700))
    assert_eq(window.position, Vector2i(STRIP.x - SIZE.x, 0), "The strip's right end at the corner")
    assert_true(_strip_in(window), "and still in reach")


## A docker the painter put over the bar stays there through a resize of the
## window and back, through a resize that makes the store fit another docker of
## the layout, and through a restore from the file, the next start's path.
func test_a_docker_over_the_bar_stays_there_through_a_reflow_and_a_restore() -> void:
    var over := _docker(Vector2i(400, 300))
    var other := _docker(Vector2i(900, 300))
    var store := _store([over, other])
    store.save()
    over.position = OVER_THE_BAR
    store.save(true)

    _resize(store, Vector2i(1200, 900))
    assert_eq(over.position, OVER_THE_BAR, "A smaller window keeps it over the bar")
    _resize(store, HOST)
    assert_eq(over.position, OVER_THE_BAR, "and so does the window grown back")

    _resize(store, Vector2i(960, HOST.y))
    assert_true(other.position.x + STRIP.x <= 960, "The other docker was moved to keep its strip: %s" % other.position)
    assert_eq(over.position, OVER_THE_BAR, "while the fit left the one over the bar where it was put")
    _resize(store, HOST)

    over.position = Vector2i(400, 300)
    store.restore_all()
    assert_eq(over.position, OVER_THE_BAR, "The restore puts it back over the bar, where the file says")


## The Window menu's show still opens a docker whole and under the bar, and so
## does a dialog, which keeps its own rule.
func test_the_window_menu_s_show_and_a_dialog_open_under_the_bar() -> void:
    var cfg := ConfigFile.new()
    cfg.set_value(SECTION, "position", OVER_THE_BAR)
    cfg.set_value(SECTION, "size", SIZE)
    cfg.set_value(SECTION, "visible", false)
    cfg.save(SaDataRoot.path(SCRATCH))
    var window := _docker(OVER_THE_BAR)
    window.name = SECTION
    window.visible = false
    var registries := SaRegistries.new()
    registries.ui.register_docker(&"NavigatorProbe", "Navigator", func() -> Window: return Window.new(), &"docker_stub")
    registries.ui.set_docker_node(&"NavigatorProbe", window)
    var store := NoForkStore.new()
    store.path = SaDataRoot.path(SCRATCH)
    var dockers := MainDockers.new(registries.ui, store)
    _root.add_child(Node.new())
    _root.get_child(-1).add_child(dockers)
    dockers.toggle_docker(0)
    assert_true(window.visible, "The row's toggle showed the docker")
    assert_eq(window.position, Vector2i(OVER_THE_BAR.x, dockers.below_bar()), "under the bar, moved down and no further")

    var dialog := SaRadiusDialog.new()
    _viewport.add_child(dialog)
    dialog.configure("Feather", 4)
    dialog.position = OVER_THE_BAR
    dialog.popup_centered()
    dialog.fit_opening_size()
    dialog.position = OVER_THE_BAR
    dialog.fit_opening_size()
    assert_true(dialog.position.y >= BAR, "A dialog asked to open over the bar opens under it, at %d" % dialog.position.y)


## The layout store with the answers that fork a preset stubbed, as the Window
## menu's own suite stubs them.
class NoForkStore:
    extends DockerLayoutStore

    func fork_for_painter_edit() -> String:
        return ""

    func list_presets() -> Array[String]:
        return []

    func current_preset() -> String:
        return ""


## An embedded docker of [constant SIZE] at *at*.
func _docker(at: Vector2i) -> Window:
    var window := Window.new()
    window.min_size = Vector2i(80, 60)
    window.size = SIZE
    _viewport.add_child(window)
    window.position = at
    return window


## A store over *windows*, its bar the suite's.
func _store(windows: Array[Window]) -> DockerLayoutStore:
    var store := DockerLayoutStore.new()
    store.path = SaDataRoot.path(SCRATCH)
    store.top_inset = func() -> int: return BAR
    store.dockers_provider = func() -> Array:
        var out: Array = []
        for i in windows.size():
            out.append({"name": "Probe%d" % i, "node": windows[i]})
        return out
    store.save_allowed = func() -> bool: return true
    _root.add_child(store)
    return store


func _resize(store: DockerLayoutStore, to: Vector2i) -> void:
    _viewport.size = to
    store.reflow_to_host()


## Presses *window*'s bar, moves the pointer by *by* and lets go, through the
## bar's `gui_input` as a hand does it.
func _drag(window: Window, by: Vector2) -> void:
    var bar := Control.new()
    _root.add_child(bar)
    var handle := DockerDragHandle.new(true)
    _root.add_child(handle)
    handle.bind(window, bar)
    var press := Vector2(window.position) + PRESS
    DockerDragHandle.capture_pointer = press
    bar.gui_input.emit(_button(true))
    DockerDragHandle.capture_pointer = press + by
    bar.gui_input.emit(InputEventMouseMotion.new())
    bar.gui_input.emit(_button(false))
    handle.free()
    bar.free()


## Whether at least [constant STRIP] of *window*'s title strip, or all of a
## narrower one, stands on the window, its bar included.
func _strip_in(window: Window) -> bool:
    var strip := Rect2i(window.position, Vector2i(window.size.x, STRIP.y))
    var on := strip.intersection(Rect2i(Vector2i(), HOST))
    return on.size.x >= mini(STRIP.x, window.size.x) and on.size.y == STRIP.y


static func _button(down: bool) -> InputEventMouseButton:
    var button := InputEventMouseButton.new()
    button.button_index = MOUSE_BUTTON_LEFT
    button.pressed = down
    return button
