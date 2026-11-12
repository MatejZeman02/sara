## Dockers, menu entries and settings pages contributed by modules.
##
## main.gd's `_get_docker_config()` was a hardcoded array of four dictionaries, so
## a module could not add a docker at all.
class_name SaUIRegistry
extends RefCounted

signal changed

## The settings pages have a signal of their own, because the host rebuilds the
## Dockers menu on `changed` and the skeleton's ten pages registering on the
## first request for Preferences rebuilt it ten times (forty nodes in the
## capture's auto-numbered names).
signal settings_pages_changed

## The three groups the Preferences sidebar is cut into, by what a painter is
## doing there, in the order it draws them: the interface first, because the
## first page Preferences opens holds what a painter changes in their first
## sittings, then painting, then the files and the machine. A page names one of
## these when it registers.
const SETTINGS_GROUPS: Array[StringName] = [&"interface", &"painting", &"files_and_system"]

## Where a page goes that names no group, or names one the sidebar does not
## draw. A module's page is most often about the module's own files or the
## machine it runs on, and a page about painting or the interface says so.
const DEFAULT_SETTINGS_GROUP := &"files_and_system"

## The sides of the window a docker registers to open at, when a layout does
## not name it. A docker registered with neither opens closed, where its
## factory put it, until the painter opens it from the Window menu.
const DOCKER_SIDES: Array[StringName] = [&"left", &"right"]

var _dockers: Dictionary[StringName, Dictionary] = {}  # Each entry a Dictionary[String, Variant]
var _docker_order: Array[StringName] = []

var _settings_pages: Dictionary[StringName, Dictionary] = {}  # Each entry a Dictionary[String, Variant]
var _settings_page_order: Array[StringName] = []

## (docker_id) -> void, the Window menu's toggle of a docker, which the search
## asks for a docker that is hidden when its row is picked. Bound where the app
## wires the search, and while it is not the rows are listed dimmed.
var search_pick: Callable = Callable()


## `factory` is called to build the Window when the docker is first shown, so a
## module contributes a docker without the skeleton knowing its class.
##
## *sentence* says what the docker holds, and is what its row in the Window menu
## shows on hover. Optional, and a docker registered without one has a row that
## says nothing on hover rather than its own title again, which would tell a
## painter nothing the row does not already say.
##
## *side*, one of [constant DOCKER_SIDES], and *order* are the docker's default
## place: a layout that has no section for it opens it at that side of the
## window, beside the dockers the layout puts there and under the bar, stacked
## top down with the other dockers placed on that side, the lower *order*
## higher. So a docker joins every shipped layout and every layout of the
## painter's without a line of either edited, and a layout that names it puts
## it where it says, which is where a save of a painter's layout records it.
func register_docker(
    docker_id: StringName,
    title: String,
    factory: Callable,
    shortcut_action: StringName = &"",
    module_id: StringName = &"",
    sentence: String = "",
    side: StringName = &"",
    order: int = 0
) -> bool:
    if String(docker_id).is_empty() or not factory.is_valid():
        push_error("SaUIRegistry: docker '%s' needs an id and a factory." % docker_id)
        return false
    if side != &"" and not DOCKER_SIDES.has(side):
        push_error("SaUIRegistry: docker '%s' names side '%s', which is none of %s." % [docker_id, side, DOCKER_SIDES])
        return false
    if _dockers.has(docker_id):
        push_error("SaUIRegistry: docker '%s' is already registered." % docker_id)
        return false

    var entry: Dictionary[String, Variant] = {
        "id": docker_id,
        "title": title,
        "factory": factory,
        "shortcut": shortcut_action,
        "module": module_id,
        "sentence": sentence,
        "side": side,
        "order": order,
        "node": null,
    }
    _dockers[docker_id] = entry
    _docker_order.append(docker_id)
    changed.emit()
    return true


## Removes one docker, whoever registered it, so a module can take a
## built-in away. The host rebuilds the Dockers menu on `changed`. A
## window it had already built is not freed here, because the registry
## holds the node without owning it, so a module that removes a docker
## after the layout is built does so before the windows exist, in
## `register`, or lives with the window until the next launch.
func unregister_docker(docker_id: StringName) -> void:
    if not _dockers.has(docker_id):
        return
    _dockers.erase(docker_id)
    _docker_order.erase(docker_id)
    changed.emit()


func unregister_module(module_id: StringName) -> void:
    var doomed: Array[StringName] = []
    for docker_id: StringName in _docker_order:
        if _dockers[docker_id]["module"] == module_id:
            doomed.append(docker_id)
    for docker_id in doomed:
        _dockers.erase(docker_id)
        _docker_order.erase(docker_id)
    var doomed_pages: Array[StringName] = []
    for page_id: StringName in _settings_page_order:
        if _settings_pages[page_id]["module"] == module_id:
            doomed_pages.append(page_id)
    for page_id in doomed_pages:
        _settings_pages.erase(page_id)
        _settings_page_order.erase(page_id)
    if not doomed.is_empty():
        changed.emit()
    if not doomed_pages.is_empty():
        settings_pages_changed.emit()


func has_docker(docker_id: StringName) -> bool:
    return _dockers.has(docker_id)


func get_docker_entry(docker_id: StringName) -> Dictionary[String, Variant]:
    if not _dockers.has(docker_id):
        return {}
    return _dockers[docker_id]


func list_dockers() -> Array:
    var out: Array = []
    for docker_id in _docker_order:
        out.append(_dockers[docker_id])
    return out


## A row of the search for every docker, in the Window menu's order, listed in
## place of the docker's chord and standing for its command when it has one.
func search_rows() -> Array[SaSearchRegistry.Row]:
    var out: Array[SaSearchRegistry.Row] = []
    for docker_id: StringName in _docker_order:
        var docker: Dictionary = _dockers[docker_id]
        var action: StringName = docker.get("shortcut", &"")
        var title: String = docker.get("title", docker_id)
        var named := tr(title)
        var said: String = docker.get("sentence", "")
        var act := _search_picked.bind(docker_id)
        var kind := SaSearchRegistry.DOCKER
        out.append(SaSearchRegistry.Row.new(kind, named, "Window", act, action, said, search_pick.is_valid(), action, action))
    return out


## Shows *docker_id* by the bound toggle, and only when it is hidden, so a pick
## never hides a docker already open.
func _search_picked(docker_id: StringName) -> void:
    var held: Variant = get_docker_entry(docker_id).get("node")
    var node: Window = held if held is Window else null
    if (node != null and node.visible) or not search_pick.is_valid():
        return
    search_pick.call(docker_id)


## Gives *docker_id* the title *title*, for a docker a painter renamed, and
## says so on `changed` so the Window menu draws it again. Its place in the
## order stays, which a second registration would not keep.
func retitle_docker(docker_id: StringName, title: String) -> void:
    if _dockers.has(docker_id):
        _dockers[docker_id]["title"] = title
        changed.emit()


## Records the built Window so the docker menu and layout store can find it.
func set_docker_node(docker_id: StringName, node: Node) -> void:
    if _dockers.has(docker_id):
        _dockers[docker_id]["node"] = node


## A Preferences page. `title` is the page's name in English, which is what the
## sidebar translates, what `show_page` is asked for and what a scenario names,
## so two pages cannot share one. `factory` is called with the Preferences
## window each time the page is opened and returns the page's Control, so a
## module contributes a page without the skeleton knowing its class, and the
## skeleton's own ten come through here the same way.
##
## *group* is one of [constant SETTINGS_GROUPS], the heading the page is listed
## under, and a page that names none is listed under
## [constant DEFAULT_SETTINGS_GROUP].
func register_settings_page(
    page_id: StringName, title: String, factory: Callable, module_id: StringName = &"", group: StringName = &""
) -> bool:
    if String(page_id).is_empty() or title.is_empty() or not factory.is_valid():
        push_error("SaUIRegistry: settings page '%s' needs an id, a title and a factory." % page_id)
        return false
    if _settings_pages.has(page_id):
        push_error("SaUIRegistry: settings page '%s' is already registered." % page_id)
        return false
    if not settings_page_titled(title).is_empty():
        push_error("SaUIRegistry: a settings page titled '%s' is already registered." % title)
        return false

    var entry: Dictionary[String, Variant] = {
        "id": page_id, "title": title, "factory": factory, "module": module_id, "group": _settings_group(page_id, group)
    }
    _settings_pages[page_id] = entry
    _settings_page_order.append(page_id)
    settings_pages_changed.emit()
    return true


## The group a page is listed under: the one it named, or the default for a
## page that named none. A name the sidebar does not draw is a slip in the
## module, said once, and the page is still listed rather than lost.
static func _settings_group(page_id: StringName, group: StringName) -> StringName:
    if group.is_empty():
        return DEFAULT_SETTINGS_GROUP
    if not SETTINGS_GROUPS.has(group):
        push_warning(
            (
                "SaUIRegistry: settings page '%s' names no group called '%s', so it goes under '%s'."
                % [page_id, group, DEFAULT_SETTINGS_GROUP]
            )
        )
        return DEFAULT_SETTINGS_GROUP
    return group


func has_settings_page(page_id: StringName) -> bool:
    return _settings_pages.has(page_id)


## The entry whose title this is, or an empty Dictionary.
func settings_page_titled(title: String) -> Dictionary[String, Variant]:
    for page_id in _settings_page_order:
        if _settings_pages[page_id]["title"] == title:
            return _settings_pages[page_id]
    return {}


## In registration order.
func list_settings_pages() -> Array:
    var out: Array = []
    for page_id in _settings_page_order:
        out.append(_settings_pages[page_id])
    return out
