## A composed docker takes a shortcut.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A docker of one's own takes a shortcut. The suite makes
## one in a library of its own, bound to a command registry of its own, gives
## its toggle a chord, presses the chord and reads the window shown and, pressed
## again, hidden. It renames the docker and reads the chord still working and
## the new name everywhere the name is shown, deletes it and reads the command,
## its action and its chord gone, and finds the toggle among the F3 rows.
##
## The library's file is under a folder of its own in the data root, removed
## after each test, and every action the suite made leaves the InputMap with it.
extends "res://tests/test_framework.gd"

const ScratchFolder := preload("res://tests/fixtures/scratch_folder.gd")
const ComposedDocker := preload("res://ui/dockers/composed/composed_docker.gd")
const DOCKER_NAME := "Probe Docker"
const RENAMED := "Renamed Probe Docker"
const CHORD := "Ctrl+Alt+Shift+F7"

static var scratch_dir: String = SaDataRoot.path("test_composed")
static var library_path: String = scratch_dir.path_join("composed_dockers.cfg")

var _registries: SaRegistries = null
var _library: SaComposedDockers = null
var _window: Window = null
var _root: Node = null
var _actions_before: Array[StringName] = []


func before_each() -> void:
    ScratchFolder.clear(scratch_dir)
    _actions_before = InputMap.get_actions()
    _registries = SaRegistries.new()
    _registries.build_context(Callable(), Callable())
    _library = SaComposedDockers.new(_registries.ui, library_path)
    _library.bind_commands(_registries.commands, _toggle)


func after_each() -> void:
    if is_instance_valid(_root):
        _root.free()
    _root = null
    _window = null
    for docker: Dictionary in _library.list():
        SaSettings.unregister_layout_category(String(docker["id"]))
    _library = null
    _registries = null
    for action: StringName in InputMap.get_actions():
        if not _actions_before.has(action):
            InputMap.erase_action(action)
    ScratchFolder.clear(scratch_dir)


## The suite's stand-in for `MainDockers.toggle_docker_by_id`: the window the
## registry holds, shown when hidden and hidden when shown.
func _toggle(docker_id: StringName) -> void:
    var node: Variant = _registries.ui.get_docker_entry(docker_id).get("node")
    if node is Window:
        (node as Window).visible = not (node as Window).visible


## Makes the docker and builds its window as `MainDockers` would, hidden, in
## an embedding host of the suite's own.
func _make() -> StringName:
    var docker_id := _library.make(DOCKER_NAME)
    _root = Node.new()
    _root.name = "U570ComposedHost"
    EventBus.add_child(_root)
    var viewport := SubViewport.new()
    viewport.size = Vector2i(1200, 800)
    viewport.gui_embed_subwindows = true
    _root.add_child(viewport)
    _window = (_registries.ui.get_docker_entry(docker_id)["factory"] as Callable).call() as Window
    _window.name = String(docker_id)
    _window.visible = false
    viewport.add_child(_window)
    _registries.ui.set_docker_node(docker_id, _window)
    SaSettings.register_layout_category(String(docker_id), DOCKER_NAME, _window.call("layout_elements"), _window)
    return docker_id


## A press of *chord* through the registry, as the router hands it on.
func _press(chord: String) -> bool:
    var event := SaShortcutStore.parse_chord(chord)
    event.pressed = true
    return _registries.commands.try_handle_input(event)


func test_a_made_docker_has_a_toggle_that_ships_unbound() -> void:
    var docker_id := _make()
    var command_id := SaComposedDockers.command_of(docker_id)
    assert_true(_registries.commands.has(command_id), "making the docker registered its toggle")
    var descriptor := _registries.commands.get_descriptor(command_id)
    assert_eq(descriptor.shown_title(), "%s docker" % DOCKER_NAME, "the toggle is named after the docker")
    assert_eq(descriptor.category, &"docker", "it is filed with the dockers' toggles")
    assert_true(InputMap.has_action(command_id), "its action is in the InputMap for the Keyboard page")
    assert_true(SaShortcutStore.chords_for(command_id).is_empty(), "it ships with no chord")
    assert_eq(_registries.ui.get_docker_entry(docker_id)["shortcut"], command_id, "the Window menu's row names it")
    assert_true(SaShortcutRows.actions_for("docker_").has(command_id), "the Keyboard page files it under Dockers")


func test_the_chord_shows_and_hides_the_docker() -> void:
    var docker_id := _make()
    SaShortcutStore.set_chords(SaComposedDockers.command_of(docker_id), [CHORD])
    assert_true(_press(CHORD), "the chord is answered")
    assert_true(_window.visible, "the first press shows the docker")
    assert_true(_press(CHORD), "the chord is answered again")
    assert_false(_window.visible, "the second press hides it")


func test_a_rename_keeps_the_chord_and_shows_the_new_name() -> void:
    var docker_id := _make()
    var command_id := SaComposedDockers.command_of(docker_id)
    SaShortcutStore.set_chords(command_id, [CHORD])
    assert_true(_library.rename(docker_id, RENAMED), "the rename is taken")
    assert_true(_registries.commands.has(command_id), "the toggle keeps its id")
    assert_eq(SaShortcutStore.chords_for(command_id), [CHORD] as Array[String], "and its chord")
    assert_true(_press(CHORD), "the chord is answered after the rename")
    assert_true(_window.visible, "and shows the docker")
    var descriptor := _registries.commands.get_descriptor(command_id)
    assert_eq(descriptor.shown_title(), "%s docker" % RENAMED, "the toggle reads the new name")
    assert_eq(_registries.ui.get_docker_entry(docker_id)["title"], RENAMED, "so does the Window menu")
    assert_eq(_window.title, RENAMED, "and the window")
    var line := SaSettings.reorderable_categories().filter(
        func(entry: Dictionary) -> bool: return entry["id"] == String(docker_id)
    )
    assert_eq(line.size(), 1, "the docker keeps one line in Preferences")
    assert_eq(String(line[0]["title"]) if not line.is_empty() else "", RENAMED, "under the new name")
    var reread := SaComposedDockers.new(SaUIRegistry.new(), library_path)
    assert_eq(reread.name_of(docker_id), RENAMED, "the library's file holds the new name")
    assert_false(_library.rename(docker_id, "  "), "an empty name is refused")
    assert_false(_library.rename(&"composed_999", RENAMED), "an id the library has not is refused")


func test_a_delete_takes_the_command_and_its_chord() -> void:
    var docker_id := _make()
    var command_id := SaComposedDockers.command_of(docker_id)
    SaShortcutStore.set_chords(command_id, [CHORD])
    assert_true(_library.delete(docker_id), "the delete is taken")
    _window = null
    assert_false(_registries.commands.has(command_id), "the toggle is gone")
    assert_false(InputMap.has_action(command_id), "its action is gone")
    assert_true(SaShortcutStore.holders(CHORD).is_empty(), "and no action answers its chord")
    assert_false(_press(CHORD), "a press of the chord runs nothing")


func test_f3_finds_the_toggle() -> void:
    var docker_id := _make()
    var command_id := SaComposedDockers.command_of(docker_id)
    var found: Array = []
    for entry: SaSearchIndex.Entry in SaSearchIndex.new(_registries.context).entries():
        if entry.command == command_id:
            found.append(entry)
    assert_eq(found.size(), 1, "F3 lists the docker once, standing for its toggle")
    assert_eq(found[0].title if not found.is_empty() else "", DOCKER_NAME, "under the docker's name")


func test_a_docker_read_from_the_file_gets_its_toggle_when_the_commands_are_bound() -> void:
    var docker_id := _library.make(DOCKER_NAME)
    var registries := SaRegistries.new()
    var reread := SaComposedDockers.new(registries.ui, library_path)
    reread.register_each()
    assert_false(registries.commands.has(SaComposedDockers.command_of(docker_id)), "no toggle before the commands")
    reread.bind_commands(registries.commands, _toggle)
    assert_true(registries.commands.has(SaComposedDockers.command_of(docker_id)), "binding registers the toggle")
