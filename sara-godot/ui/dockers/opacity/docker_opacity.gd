## How see-through a docker's background and frame are, its menu on a right
## press of the drag bar, and the value kept in the layout file.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A docker kept floating over the canvas hides the painting behind it, and a
## painter who keeps it there wants to see through its empty parts. So each
## docker takes an opacity of its own, from a right press on its drag bar, which
## is the one part every docker has and none uses for anything else.
##
## **`self_modulate`, never the styles' colours.** The background is a `Panel`
## with no children, `DockerBackground` of `DockerUtils`, and the drag bar is a
## `PanelContainer` whose only children are its title and buttons. A node's
## `self_modulate` fades what the node draws itself and nothing it holds, so the
## background, its edge and the bar's own box go see-through while the title,
## the icons and every control stay at full. Writing the alpha into the
## styleboxes instead would be undone by the next theme switch, which sets every
## bound colour back from the palette, slice by slice over several frames.
##
## **Kept with the layout.** The value is a key of the docker's own section in
## the layout file, beside its position and size, so a named layout carries it
## and loading one puts it back. A choice is the painter changing the layout,
## and says so on `docker_layout_changed`, which is what forks a shipped
## layout. Docked or floating, a docker is the same window, so one value
## covers both.
##
## **Its own folder, and `docker_window.gd` takes no line.** `MainDockers`
## attaches it to every docker it builds, a module's as well as a built-in, as
## it attaches the edges.
class_name SaDockerOpacity
extends Node

## The key of the docker's layout section the value is stored under.
const KEY: String = "opacity"

## The steps the menu offers, in percent, the first being the plain docker.
const STEPS: Array[int] = [100, 85, 70, 50, 30]

## The least a stored value is read as, so a hand-edited file cannot make a
## docker's background vanish entirely and leave its controls floating.
const LOWEST: float = 0.2

## Named, because a suite finds the node and the menu by name.
const NODE_NAME := &"DockerOpacity"
const MENU_NAME := &"OpacityMenu"

## The opacity the docker shows now, 1 for a plain one.
var alpha: float = 1.0

## The menu a right press on the drag bar opens, built on first use.
var menu: SaChoicePopup = null

var _window: DockerWindow
var _store: DockerLayoutStore


func _init(window: DockerWindow, store: DockerLayoutStore) -> void:
    name = NODE_NAME
    _window = window
    _store = store


## Puts an opacity on *window*, read from *store*'s layout file. False for a
## window that is not a docker. A docker not ready yet is attached once it is,
## because its drag bar may be built in its own `_ready`.
static func attach(window: Window, store: DockerLayoutStore) -> bool:
    var docker := window as DockerWindow
    if docker == null:
        return false
    if not docker.is_node_ready():
        docker.ready.connect(func() -> void: attach(docker, store), CONNECT_ONE_SHOT)
        return false
    var content := docker.get_node_or_null("Control") as Control
    if content == null:
        return false
    if content.has_node(String(NODE_NAME)):
        return true
    content.add_child(SaDockerOpacity.new(docker, store))
    return true


## The opacity attached to *window*, or null for one that has none.
static func of(window: Window) -> SaDockerOpacity:
    if window == null:
        return null
    return window.get_node_or_null("Control/%s" % NODE_NAME) as SaDockerOpacity


func _ready() -> void:
    if _store != null and not _store.presets_changed.is_connected(read_back):
        _store.presets_changed.connect(read_back)
    var bar := _window.drag_handle
    if bar != null and not bar.gui_input.is_connected(_on_bar_input):
        bar.gui_input.connect(_on_bar_input)
    read_back()


## The section of the layout file this docker's geometry lives under, which is
## its registered id and the name `MainDockers` gives its window.
func section() -> String:
    return String(_window.name)


## What the layout file holds for this docker, 1 when it holds nothing.
func stored() -> float:
    if _store == null:
        return 1.0
    var held: Variant = _store.value_for(section(), KEY, 1.0)
    if not (held is float or held is int):
        return 1.0
    return clampf(float(held), LOWEST, 1.0)


## Shows what the layout file holds, after a layout was loaded over it.
func read_back() -> void:
    show_alpha(stored())


## Fades the background, its edge and the drag bar's box to *value*, and
## nothing they hold.
func show_alpha(value: float) -> void:
    alpha = clampf(value, LOWEST, 1.0)
    var background := _window.get_node_or_null("Control/DockerBackground") as CanvasItem
    if background != null:
        background.self_modulate.a = alpha
    if _window.drag_handle != null:
        _window.drag_handle.self_modulate.a = alpha


## The painter's choice: shown, written into the layout file and announced as
## a change of the layout.
func choose(value: float) -> void:
    show_alpha(value)
    if _store == null:
        return
    var cfg := ConfigFile.new()
    # A file not there yet is written fresh, as the store's own save does.
    cfg.load(_store.path)
    if is_equal_approx(alpha, 1.0):
        if cfg.has_section_key(section(), KEY):
            cfg.erase_section_key(section(), KEY)
    else:
        cfg.set_value(section(), KEY, alpha)
    DirAccess.make_dir_recursive_absolute(_store.path.get_base_dir())
    if cfg.save(_store.path) != OK:
        push_error("Failed to save a docker's opacity to %s" % _store.path)
        return
    EventBus.docker_layout_changed.emit()


## The menu filled with the steps, the one shown now marked, without opening it,
## which is the half a suite runs.
func fill_menu() -> SaChoicePopup:
    if menu == null:
        menu = SaChoicePopup.new()
        menu.name = MENU_NAME
        menu.chosen.connect(_on_step_chosen)
        add_child(menu)
    menu.clear()
    menu.add_section(tr("Background opacity"))
    var current := StringName()
    for step: int in STEPS:
        var id := StringName(str(step))
        menu.add_row(id, "%d%%" % step)
        if is_equal_approx(float(step) / 100.0, alpha):
            current = id
    if current != StringName():
        menu.set_current(current)
    return menu


func _on_step_chosen(id: StringName) -> void:
    choose(float(String(id).to_int()) / 100.0)


## A right press on the drag bar opens the menu at the pointer. The bar's own
## drag takes the left button only, so the right press is this menu's alone.
func _on_bar_input(event: InputEvent) -> void:
    var press := event as InputEventMouseButton
    if press == null or not press.pressed or press.button_index != MOUSE_BUTTON_RIGHT:
        return
    fill_menu().open_under(_window.drag_handle, Vector2(SaPopupRect.at_press(press, _window.drag_handle)))
    _window.drag_handle.accept_event()
