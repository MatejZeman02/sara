## The manual says where the Reference docker is, for a painter
## who looked for it in the toolbox as Krita keeps it.
##
## The window page is read as text and has to name the docker's row in the
## Window menu and its chord in Sara's own shortcuts, each read from where the
## build keeps it rather than written here, so renaming the docker or moving
## its chord fails this suite until the page says so too.
extends "res://tests/test_framework.gd"

const PAGE := "res://manual/01-the-window.md"

## Registering the commands binds the live InputMap, so every test puts it back.
var _saved_events: Dictionary = {}


func before_each() -> void:
    _saved_events.clear()
    for action: StringName in InputMap.get_actions():
        _saved_events[action] = InputMap.action_get_events(action).duplicate()


func after_each() -> void:
    for action: StringName in InputMap.get_actions():
        if not _saved_events.has(action):
            InputMap.erase_action(action)
    for action: StringName in _saved_events:
        InputMap.action_erase_events(action)
        for event: InputEvent in _saved_events[action]:
            InputMap.action_add_event(action, event)


## The page as one line of words, so a sentence the editor wrapped still reads
## whole.
func _page() -> String:
    var text := FileAccess.get_file_as_string(PAGE)
    return " ".join(text.split("\n")).replace("  ", " ")


func _registries() -> SaRegistries:
    var registries := SaRegistries.new()
    registries.build_context(Callable(), Callable())
    SaAppCommands.register_all(registries, Callable())
    SaBuiltinDockers.register(registries.ui)
    return registries


func test_the_window_page_names_the_reference_row_of_the_window_menu() -> void:
    var registries := _registries()
    var entry := registries.ui.get_docker_entry(SaDockerIds.REFERENCE)
    assert_eq(StringName(entry.get("shortcut", &"")), &"docker_reference", "The Reference docker toggles on docker_reference")
    var title := String(entry.get("title", ""))
    assert_false(title.is_empty(), "and has a title the Window menu shows")
    var page := _page()
    assert_true(page.contains("Window, %s opens it" % title), "The window page says Window, %s opens the docker" % title)
    assert_true(page.contains("in the toolbox"), "and speaks to a painter who looked in the toolbox first")


func test_the_window_page_names_the_chord_docker_reference_carries() -> void:
    var registries := _registries()
    var chord := registries.commands.chord_text(&"docker_reference")
    assert_false(chord.is_empty(), "docker_reference has a chord in Sara's own shortcuts")
    assert_true(_page().contains("%s with Sara's own shortcuts" % chord), "and the window page names it, %s" % chord)


func test_the_window_page_says_what_the_docker_takes() -> void:
    var page := _page()
    for words: String in ["Open... button adds a picture from a file", "dropped on it", "Edit, Paste"]:
        assert_true(page.contains(words), "The window page says the docker takes a picture by %s" % words)


func test_the_reference_docker_is_named_on_the_window_page_alone() -> void:
    for path: String in SaManualWindow.page_files():
        if path.get_file() == PAGE.get_file():
            continue
        var text := FileAccess.get_file_as_string(path)
        assert_false(text.contains("Window, Reference"), "%s leaves where the docker is to the window page" % path.get_file())
