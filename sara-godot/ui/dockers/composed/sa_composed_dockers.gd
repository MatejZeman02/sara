## The composed dockers: the library of dockers a painter puts together out of
## elements other dockers registered, kept in a file of its own in the data
## root and registered through the same door as any docker.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Composed dockers live in a library of their own, available in every layout,
## and a layout records only whether each is shown and where. So the library is
## not a layout's: `composed_dockers.cfg`
## holds each docker's id, its name and its placed elements in order with
## their switches, and a layout preset or `docker_layout.cfg` holds the
## docker's place and shown flag as it does a built-in's and nothing of what
## is placed in it. `SaDockerLayoutPresets` skips a composed category for that
## reason, and `DockerLayoutStore.restore_all` opens a composed docker the file
## does not name closed rather than open.
##
## A placed element is a second view of the same state as at home, which is
## why an element here is three things and no more: its category, its name
## and whether it is drawn. The view is built through
## `SaSettings.build_element_view` each time the window is, and nothing about
## one placement is kept beside it.
##
## **A shipped docker takes placed elements too**, because every docker is a
## composition in this sense, the defaults included. What is placed in one is
## kept here under the id its Preferences page and its settings carry,
## `ColorPicker` for the Colour Picker, in a section of that name, and never in
## the profile or a layout, for the library's reason above. Its window draws
## the views after its own elements, in the column `DockerWindow.place_column`
## takes, and the docker's Reset to shipped takes them out with the rest of its
## edits. A switch to a shipped layout leaves them, because no layout holds
## them.
##
## **Each docker registers through `SaUIRegistry.register_docker`**, so the
## Window menu, the layout store and Preferences hear of it as of any docker
## and none of them names this class to list it. Its window registers its
## category through `MainDockers` as a module's docker does, with the drag bar
## and the grip as its own elements.
##
## **Each docker has a toggle command of its own**, `docker_composed_1` beside
## `composed_1`, registered once the boot hands the library the command
## registry through [method register_commands], and after that the moment a
## docker is made, so the Keyboard Shortcuts page, Assign Shortcut, Quick
## Favourites and the F3 chord offer it as they offer a built-in docker's toggle. It
## ships unbound. Its id is the docker's rather than its name, so a chord a
## painter gives it is kept in the profile by the docker's identity and a
## rename keeps it. A delete takes the command, its action and its chord away.
##
## **Ids are never reused.** `composed_1`, `composed_2` and on, from a counter
## the file keeps, so a layout file that still names a deleted docker never
## opens a new one in its place. The prefix is also how the layout store and
## the presets tell a composed docker from a built-in without a library to ask,
## see [method is_composed].
##
## A facade with an instance per registry and one for the app: the boot's
## [method register] keeps the app's in [member app], which the rows that make
## and delete one from Preferences read. A suite builds its own on a file of
## its own.
@tool
class_name SaComposedDockers
extends RefCounted

## The window each composed docker is, private to this folder and reached by
## path, so no editor rescan stands between a checkout and the boot.
const ComposedDocker := preload("composed_docker.gd")

## The column a shipped docker draws its placed elements in.
const PlacedViews := preload("placed_views.gd")

## The library's file, under the data root beside the painter's other data.
const FILE_NAME := "composed_dockers.cfg"

## What every composed docker's id begins with.
const ID_PREFIX := "composed_"

## The file's own section: the counter the next id is taken from and the
## dockers' order. Underscores round it, so no docker id can be it.
const LIBRARY_SECTION := "_library_"

## What a composed docker says on hover in the Window menu.
const SENTENCE := "A docker of your own, holding the elements you placed in it."

## What every toggle command's id begins with, the prefix the Keyboard
## Shortcuts page files under Dockers.
const COMMAND_PREFIX := "docker_"

## A toggle's title, the docker's name filled in, translated whole.
const COMMAND_TITLE := "%s docker"

## The module the toggles are registered for, the skeleton's, as a built-in
## docker's are.
const COMMAND_MODULE := &"sara-skeleton"

## The library the running app holds, written by the boot's [method register]
## alone, and null before the boot reached it.
static var app: SaComposedDockers = null

## Where this library is read from and written to.
var file_path: String

## The registry its dockers are registered in.
var _ui: SaUIRegistry

## The number the next new docker's id takes.
var _next: int = 1

## The dockers' ids, in the order they were made.
var _order: Array[StringName] = []

## Each docker by id: {"name": String, "elements": Array of
## {"category": String, "element": String, "visible": bool}}.
var _dockers: Dictionary[StringName, Dictionary] = {}

## What is placed in each shipped docker by its settings id, each list as a
## composed docker's elements are kept, and no key for one holding nothing.
var _shipped: Dictionary[String, Array] = {}

## The command registry the toggles are registered in, null until
## [method bind_commands], which is a library a suite built with no commands.
var _commands: SaCommandRegistry = null

## (docker_id) -> void, what shows or hides a docker, `MainDockers`' toggle in
## the app, handed in with the registry.
var _toggle: Callable = Callable()


func _init(registry: SaUIRegistry, path := SaDataRoot.path(FILE_NAME)) -> void:
    _ui = registry
    file_path = path
    _read()


## The boot's call, made once the built-ins are registered so a composed docker
## lists after them: the app's library on *ui*, read the first time, and each
## of its dockers registered. True, so the built-ins' slices can end on it.
static func register(ui: SaUIRegistry) -> bool:
    if app == null or app._ui != ui:
        app = SaComposedDockers.new(ui)
        var tree := Engine.get_main_loop() as SceneTree
        if tree != null and not tree.root.tree_exiting.is_connected(release):
            tree.root.tree_exiting.connect(release)
    app.register_each()
    # The built-ins' windows were built before this library was, and a module's
    # are built on a registration after it, so each is handed what is placed in
    # it now and after every registration. Deferred, so the windows the
    # registration builds are there.
    if not ui.changed.is_connected(app.hold_each):
        ui.changed.connect(app.hold_each, CONNECT_DEFERRED)
    app.hold_each()
    return true


## Lets go of the app's library when the root leaves the tree.
##
## **Godot 4.7 aborts at exit on a static that still holds another script's
## lambda**, and the library holds the UI registry, whose docker factories are
## lambdas `SaBuiltinDockers` and the modules made, so a run that kept it
## would end on a double free with exit -6. The root leaving is the last moment the tree still stands,
## the same moment the preset thumbnails drop their compositor.
static func release() -> void:
    app = null


## Whether *docker_id* names a composed docker, by its prefix alone, so the
## layout store and the presets can ask with no library to hand.
static func is_composed(docker_id: Variant) -> bool:
    return String(docker_id).begins_with(ID_PREFIX)


## The boot's call once the app's commands are registered: the app's library
## registers a toggle for each of its dockers in *commands*, run through
## *toggle*, and one for each docker made after. Only when the library's
## dockers are registered in *ui*, so registries a suite or a second boot built
## are never held by the app's library, and nothing before the library is read.
static func register_commands(ui: SaUIRegistry, commands: SaCommandRegistry, toggle: Callable) -> void:
    if app != null and app._ui == ui:
        app.bind_commands(commands, toggle)


## Registers a toggle in *commands* for each docker, each run through
## *toggle*, and keeps both so a docker made later gets its own.
func bind_commands(commands: SaCommandRegistry, toggle: Callable) -> void:
    _commands = commands
    _toggle = toggle
    if _commands != null:
        _commands.batch(register_each)


## The toggle command's id for *docker_id*.
static func command_of(docker_id: StringName) -> StringName:
    return StringName(COMMAND_PREFIX + String(docker_id))


## Registers every docker of the library the registry does not have yet, and
## its toggle when the commands are bound and the toggle is not there yet.
func register_each() -> void:
    for docker_id: StringName in _order:
        if not _ui.has_docker(docker_id):
            _ui.register_docker(docker_id, name_of(docker_id), _factory(docker_id), command_of(docker_id), &"", SENTENCE)
        _register_command(docker_id)


## The toggle of *docker_id*, under its name now, unbound as it ships.
func _register_command(docker_id: StringName) -> void:
    var command_id := command_of(docker_id)
    if _commands == null or _commands.has(command_id):
        return
    var named := name_of(docker_id)
    var command := SaCommandDescriptor.create(command_id, COMMAND_TITLE % named, _run_toggle.bind(_toggle, docker_id))
    command.title_pattern = COMMAND_TITLE
    command.title_value = named
    command.category = &"docker"
    command.sentence = SENTENCE
    _commands.register(command, COMMAND_MODULE)


## The handler: static, so the registry that keeps it never keeps the library.
static func _run_toggle(toggle: Callable, docker_id: StringName) -> bool:
    if not toggle.is_valid():
        return false
    toggle.call(docker_id)
    return true


## Makes a docker called *docker_name* holding *elements*, writes the library
## and registers it. Returns its id. Each element is a dictionary with
## `category` and `element`, and `visible`, true when left out.
func make(docker_name: String, elements: Array = []) -> StringName:
    var docker_id := StringName("%s%d" % [ID_PREFIX, _next])
    _next += 1
    _order.append(docker_id)
    _dockers[docker_id] = {"name": docker_name, "elements": _clean(elements)}
    _write()
    register_each()
    return docker_id


## Puts *elements* in *docker_id* in place of what it held, writes the library,
## and has its window, when it is built, hold them. False for a composed id the
## library does not have. Any other id is a shipped docker's settings id, and
## an empty list takes everything placed in it out, its Reset to shipped.
func change(docker_id: StringName, elements: Array) -> bool:
    var kept := _clean(elements)
    if is_composed(docker_id):
        if not _dockers.has(docker_id):
            return false
        _dockers[docker_id]["elements"] = kept
    elif String(docker_id).is_empty() or String(docker_id) == LIBRARY_SECTION:
        return false
    elif kept.is_empty():
        _shipped.erase(String(docker_id))
    else:
        _shipped[String(docker_id)] = kept
    _write()
    var window := _window_of(docker_id)
    if window != null:
        _hold(window, elements_of(docker_id))
    return true


## Hands each built window of a shipped docker what is placed in it. The boot's
## call once the built-ins are registered, and every registration's after it.
func hold_each() -> void:
    for entry: Dictionary in _ui.list_dockers():
        var window := _built(entry)
        if window == null or window is ComposedDocker:
            continue
        var held := elements_of(StringName(window.settings_category()))
        if not held.is_empty() or window.placed_column != null:
            _hold(window, held)


## Takes *docker_id* out of the library, the registry and the settings, and
## frees its window. False for an id the library does not have.
func delete(docker_id: StringName) -> bool:
    if not _dockers.has(docker_id):
        return false
    var window := _window_of(docker_id)
    _dockers.erase(docker_id)
    _order.erase(docker_id)
    _write()
    _ui.unregister_docker(docker_id)
    _forget_command(docker_id)
    SaSettings.unregister_layout_category(String(docker_id))
    if window != null:
        var parent := window.get_parent()
        if parent != null:
            parent.remove_child(window)
        window.queue_free()
    return true


## Calls *docker_id* *docker_name*: in the library's file, the Window menu, its
## window's drag bar, its line in Preferences and its toggle's title. The
## toggle keeps its id, and with it its chord. False for an id the library does
## not have or an empty name.
func rename(docker_id: StringName, docker_name: String) -> bool:
    var named := docker_name.strip_edges()
    if not _dockers.has(docker_id) or named.is_empty():
        return false
    _dockers[docker_id]["name"] = named
    _write()
    _ui.retitle_docker(docker_id, named)
    var window := _window_of(docker_id) as ComposedDocker
    if window != null:
        window.retitle(named)
        # The line was registered with the old title when the window was
        # built, and the settings keep no way to change one but to give it again.
        SaSettings.unregister_layout_category(String(docker_id))
        SaSettings.register_layout_category(String(docker_id), named, window.layout_elements(), window)
    var command_id := command_of(docker_id)
    if _commands != null and _commands.has(command_id):
        # Taken out and given again rather than its title written over, so the
        # registry says it changed and every list of commands reads the new
        # name. Its action stays in the InputMap, chord and all.
        _commands.unregister(command_id)
        _register_command(docker_id)
    return true


## Takes *docker_id*'s toggle away with its action, and its chord out of the
## painter's profile when the profile names it, so no key is left answering for
## a docker that is gone and the next launch makes no action for it again.
func _forget_command(docker_id: StringName) -> void:
    var command_id := command_of(docker_id)
    if _commands != null:
        _commands.unregister(command_id)
    if InputMap.has_action(command_id):
        InputMap.erase_action(command_id)
    var profile := SaSettings.shortcuts_profile
    if profile.is_empty() or profile == "default" or SaShortcutStore.is_shipped(profile):
        return
    if SaShortcutStore.load_profile(profile).has(String(command_id)):
        SaShortcutStore.save_profile(profile)


## The library's dockers in order, each {"id", "name", "elements"}.
func list() -> Array[Dictionary]:
    var out: Array[Dictionary] = []
    for docker_id: StringName in _order:
        out.append({"id": docker_id, "name": name_of(docker_id), "elements": elements_of(docker_id)})
    return out


func has(docker_id: StringName) -> bool:
    return _dockers.has(docker_id)


## The name *docker_id* was made with, or the empty string.
func name_of(docker_id: StringName) -> String:
    return String(_dockers.get(docker_id, {}).get("name", ""))


## A copy of what *docker_id* holds, in order, so a caller's edit is not the
## library's until it goes through [method change]. A shipped docker's id
## answers what is placed in it after its own elements.
func elements_of(docker_id: StringName) -> Array:
    if not is_composed(docker_id):
        return (_shipped.get(String(docker_id), []) as Array).duplicate(true)
    return (_dockers.get(docker_id, {}).get("elements", []) as Array).duplicate(true)


## What builds *docker_id*'s window: what the library holds when the window is
## built, rather than when the docker was registered.
func _factory(docker_id: StringName) -> Callable:
    return _factory_over(weakref(self), docker_id)


## The factory itself, made in a static function so it holds the library weakly:
## the registry keeps the factory and the library keeps the registry, and a
## lambda that held the library would keep all three alive between them.
static func _factory_over(library: WeakRef, docker_id: StringName) -> Callable:
    return func() -> Window:
        var held: SaComposedDockers = library.get_ref()
        if held == null:
            return null
        return ComposedDocker.new(docker_id, held.name_of(docker_id), held.elements_of(docker_id))


## The window `MainDockers` built for the docker whose settings id is
## *docker_id*, or null before it did. By the settings id rather than the
## registry's, because the Colour Picker's two differ and its page knows the first.
func _window_of(docker_id: StringName) -> DockerWindow:
    for entry: Dictionary in _ui.list_dockers():
        var window := _built(entry)
        if window != null and window.settings_category() == String(docker_id):
            return window
    return null


## The window a registry *entry* holds, or null when none is built or it was
## freed. Read before the cast, because a cast of a freed window is an error
## rather than a null.
static func _built(entry: Dictionary) -> DockerWindow:
    var node: Variant = entry.get("node")
    if node == null or not is_instance_valid(node):
        return null
    return node as DockerWindow


## Has *window* draw *elements*, building its column of placed views the first
## time something is placed in it.
static func _hold(window: DockerWindow, elements: Array) -> void:
    var views := window.placed_column as PlacedViews
    if views == null:
        if elements.is_empty():
            return
        views = PlacedViews.new()
        if not window.place_column(views):
            views.free()
            return
    views.hold(elements)


## *elements* as the library keeps them: the three keys, typed, and an entry
## with no category or element dropped.
static func _clean(elements: Array) -> Array:
    var out: Array = []
    for entry: Variant in elements:
        if not entry is Dictionary:
            continue
        var category := String(entry.get("category", ""))
        var element := String(entry.get("element", ""))
        if category.is_empty() or element.is_empty():
            continue
        # A docker that placed one of the two elements Page Edges replaced
        # holds Page Edges in its place, once.
        if category == SaTopBarPageEdges.CATEGORY and SaTopBarPageEdges.RETIRED.has(element):
            element = SaTopBarPageEdges.ELEMENT
            if out.any(func(held: Dictionary) -> bool: return held["category"] == category and held["element"] == element):
                continue
        out.append({"category": category, "element": element, "visible": bool(entry.get("visible", true))})
    return out


func _read() -> void:
    var config := ConfigFile.new()
    if config.load(file_path) != OK:
        return
    _next = maxi(1, int(config.get_value(LIBRARY_SECTION, "next", 1)))
    for id_text: Variant in config.get_value(LIBRARY_SECTION, "order", []):
        var docker_id := StringName(String(id_text))
        if not is_composed(docker_id) or not config.has_section(String(docker_id)) or _dockers.has(docker_id):
            continue
        var section := String(docker_id)
        # A file written by hand may name an id past its counter, and the next
        # docker made must not take it.
        _next = maxi(_next, int(section.trim_prefix(ID_PREFIX)) + 1)
        _order.append(docker_id)
        _dockers[docker_id] = {
            "name": String(config.get_value(section, "name", "")),
            "elements": _clean(config.get_value(section, "elements", [])),
        }
    for section: String in config.get_sections():
        if section != LIBRARY_SECTION and not is_composed(section):
            var placed := _clean(config.get_value(section, "elements", []))
            if not placed.is_empty():
                _shipped[section] = placed


func _write() -> void:
    var config := ConfigFile.new()
    config.set_value(LIBRARY_SECTION, "next", _next)
    config.set_value(LIBRARY_SECTION, "order", _order.map(func(docker_id: StringName) -> String: return String(docker_id)))
    for docker_id: StringName in _order:
        config.set_value(String(docker_id), "name", name_of(docker_id))
        config.set_value(String(docker_id), "elements", elements_of(docker_id))
    for shipped_id: String in _shipped:
        config.set_value(shipped_id, "elements", _shipped[shipped_id])
    DirAccess.make_dir_recursive_absolute(file_path.get_base_dir())
    if config.save(file_path) != OK:
        push_error("SaComposedDockers: could not write the library to '%s'." % file_path)
