## The search picks a hidden docker's row, a tool's row and a
## menu action's row, and the loupe after Help opens it.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## One window reaches every action by a word. Here the
## doors are the app's own: `MainDockers` over a docker in the tree, a tool
## machine over the registry the tools are in, the application's commands
## registered by `SaAppCommands.register_all`, and a real `TopMenuBar`, whose
## menus say where a command lives and whose row holds the loupe. A pick is
## Enter in the field, the way a painter makes one. The list is the one search
## F3 opens as well, whose scenario
## `scenarios/f3-the-loupe-and-help-search-open-one-search.json` is what a
## painter sees.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

## The docker the search shows, one whose toggle is a command of the
## application's own, so the row that folds the two is the one asked about.
const DOCKER := SaDockerIds.BRUSH_PRESETS
const DOCKER_TOGGLE := &"docker_brush_presets"


## What `MainDockers` asks of the layout store when a docker is shown, stubbed
## so a pick writes no layout file. The docker layout suites build the same stub.
class StubStore:
    extends DockerLayoutStore

    func save(_by_painter: bool = false) -> void:
        pass

    func fork_for_painter_edit() -> String:
        return ""

    func reapply_deferred(_win: Window, _section: String) -> void:
        pass

    func list_presets() -> Array[String]:
        return []

    func current_preset() -> String:
        return ""


## A view that keeps its flip, which is what View > Flip View Horizontally
## changes. The base view answers a flip of one and drops a new one.
class ProbeView:
    extends SaView

    var flip := Vector2.ONE

    func get_flip() -> Vector2:
        return flip

    func set_flip(value: Vector2) -> void:
        flip = value


# --- The three picks ------------------------------------------------------------


## A hidden docker's row shows it, and a second pick of the row leaves it shown,
## because the door is a toggle underneath and a search never hides.
func test_a_hidden_dockers_row_shows_it_and_never_hides_it() -> void:
    var built := _build()
    var window: SaSearchWindow = built["window"]
    var docker: Window = built["docker"]
    assert_false(docker.visible, "The docker starts hidden")

    window.open()
    _type(window, "brush presets")
    var marked := window.shown[window.marked_at]
    assert_eq(marked.title, "Brush Presets", "Brush Presets is the row marked")
    assert_eq(marked.kind, SaSearchIndex.DOCKER, "and it says it is a docker")
    assert_eq(marked.place, "Window", "that lives under Window")
    assert_eq(marked.chord, "Shift+S", "on its toggle's chord")
    _enter(window)
    assert_true(docker.visible, "Enter shows the docker")
    assert_false(window.visible, "and the window closes on the pick")

    window.open()
    _type(window, "brush presets")
    _enter(window)
    assert_true(docker.visible, "A second pick leaves the docker shown")
    _tear_down(built)


## A tool's row puts the tool in the machine's hand, by the Tools menu's call.
func test_a_tools_row_puts_the_tool_in_hand() -> void:
    var built := _build()
    var window: SaSearchWindow = built["window"]
    var machine: ToolMachine = built["machine"]
    assert_eq(machine.active_tool_name, &"probe_pen", "The machine starts on the first tool")

    window.open()
    _type(window, "knife")
    var marked := window.shown[window.marked_at]
    assert_eq(marked.title, "Probe Knife", "The knife is the row marked")
    assert_eq(marked.kind, SaSearchIndex.TOOL, "and it says it is a tool")
    assert_eq(marked.place, "Tools", "that lives under Tools")
    _enter(window)
    assert_eq(machine.active_tool_name, &"probe_knife", "Enter puts the knife in hand")
    assert_eq(machine.default_tool_name, &"probe_knife", "as the tool the machine keeps")
    _tear_down(built)


## A menu action's row runs its command, and the view is flipped.
func test_a_menu_actions_row_runs_it() -> void:
    var built := _build()
    var window: SaSearchWindow = built["window"]
    var view: ProbeView = built["view"]

    window.open()
    _type(window, "flip view horizontally")
    var marked := window.shown[window.marked_at]
    assert_eq(marked.title, "Flip view horizontally", "The flip is the row marked")
    assert_eq(marked.kind, SaSearchIndex.COMMAND, "and it says it is a command")
    assert_eq(marked.place, "View", "that lives on the View menu, which draws it")
    assert_eq(marked.chord, "H", "on its chord")
    _enter(window)
    assert_true(view.flip.x < 0.0, "Enter flips the view")
    assert_false(window.visible, "and the window closes")
    _tear_down(built)


# --- The list -----------------------------------------------------------------


## Every docker once: its toggle command is the docker's row and not a second
## one. The search's own command is a row, which says the chord that opens it.
func test_a_docker_is_listed_once_and_the_search_with_its_chord() -> void:
    var built := _build()
    var window: SaSearchWindow = built["window"]
    window.open()
    var dockers := 0
    var toggles := 0
    var itself: Array[SaSearchIndex.Entry] = []
    var kinds := {}
    for entry: SaSearchIndex.Entry in window.entries:
        kinds[entry.kind] = true
        if entry.title == "Brush Presets" and entry.kind != SaSearchIndex.SETTING:
            dockers += 1
        if entry.title == "Brush Presets docker" and entry.kind != SaSearchIndex.SETTING:
            toggles += 1
        if entry.title == "Search every action":
            itself.append(entry)
    assert_eq(dockers, 1, "Brush Presets is one row")
    assert_eq(toggles, 0, "and its toggle command is not a second")
    assert_eq(itself.size(), 1, "The search lists its own command once")
    assert_eq(itself[0].chord, "", "with no chord, F3 being Search Commands'...")
    assert_eq(itself[0].place, "Keyboard Shortcuts > Help", "where its chord is set, since no menu draws it")
    for kind: String in [SaSearchIndex.TOOL, SaSearchIndex.DOCKER, SaSearchIndex.COMMAND]:
        assert_true(kinds.has(kind), "A %s row is listed" % kind)
    _tear_down(built)


## Typing narrows by the start of a word: "flip" finds the two flips, "lip"
## finds neither, and an empty field shows every row.
func test_typing_narrows_by_the_start_of_a_word() -> void:
    var built := _build()
    var window: SaSearchWindow = built["window"]
    window.open()
    assert_eq(window.shown.size() - window.recent_count, window.entries.size(), "An empty field shows every row")
    _type(window, "flip")
    var titles: Array[String] = []
    for entry: SaSearchIndex.Entry in window.shown:
        titles.append(entry.title)
    assert_true(titles.has("Flip view horizontally") and titles.has("Flip view vertically"), "flip finds both flips")
    _type(window, "lip")
    for entry: SaSearchIndex.Entry in window.shown:
        assert_false(entry.title.begins_with("Flip"), "lip starts no word of %s" % entry.title)
    _tear_down(built)


## The arrows move the mark, over the rows that can be picked, and Up from the
## first goes round to the last, as every list of Sara's does.
func test_the_arrows_move_the_mark() -> void:
    var built := _build()
    var window: SaSearchWindow = built["window"]
    window.open()
    _type(window, "flip view")
    assert_eq(window.marked_at, 0, "The first row is marked")
    _arrow(window, KEY_DOWN)
    assert_eq(window.marked_at, 1, "Down marks the next")
    _arrow(window, KEY_UP)
    assert_eq(window.marked_at, 0, "and Up the one before")
    _arrow(window, KEY_UP)
    assert_eq(window.marked_at, window.shown.size() - 1, "and Up from the top goes round to the last")
    _tear_down(built)


## A command that says it cannot run now is dimmed, is never marked, and a
## pick of its row leaves the window up and runs nothing.
func test_a_disabled_command_is_dimmed_and_takes_no_pick() -> void:
    var built := _build()
    var window: SaSearchWindow = built["window"]
    var registries: SaRegistries = built["registries"]
    var runs: Array[int] = [0]
    var locked := SaCommandDescriptor.create(
        &"edit_probe_locked",
        "Probe Locked",
        func() -> bool:
            runs[0] += 1
            return true
    )
    locked.enabled = func() -> bool: return false
    registries.commands.register(locked, &"sara-skeleton")

    window.open()
    _type(window, "probe locked")
    assert_eq(window.shown.size(), 1, "The locked command is found")
    var entry := window.shown[0]
    assert_false(entry.enabled, "and says it cannot run")
    assert_eq(window.marked_at, -1, "so nothing is marked")
    assert_true(window.find_child("Row*", true, false) != null, "and its row is drawn")
    _enter(window)
    window.pick(entry)
    assert_eq(runs[0], 0, "Neither Enter nor a pick runs it")
    assert_true(window.visible, "and the window stays")
    _tear_down(built)


## The command has no chord by default, F3 being Search Commands'..., which
## opens the same list, and the command is the registry's, so a binding on
## Keyboard Shortcuts gives it one.
func test_the_search_has_no_chord_of_its_own() -> void:
    var built := _build()
    var registries: SaRegistries = built["registries"]
    assert_eq(registries.commands.chord_text(SaSearchWindow.COMMAND), "", "The search leaves F3 to Search Commands...")
    var descriptor := registries.commands.get_descriptor(SaSearchWindow.COMMAND)
    assert_eq(descriptor.owner_module, &"sara-skeleton", "registered through the context as the app's own")
    _tear_down(built)


# --- The loupe -----------------------------------------------------------------


## The loupe sits after the overflow title, off the titles row, and a press of
## it opens the search.
func test_the_loupe_after_help_opens_the_search() -> void:
    var built := _build()
    var window: SaSearchWindow = built["window"]
    var bar: TopMenuBar = built["bar"]
    var loupe := bar.find_child("SearchLoupe", true, false) as Button
    assert_not_null(loupe, "The bar draws the loupe")
    assert_eq(loupe.get_parent(), bar.menu_overflow.get_parent(), "beside the overflow title")
    assert_eq(loupe.get_index(), bar.menu_overflow.get_index() + 1, "and after it")
    assert_false(loupe.get_parent() == bar.menu_bar, "and not on the titles row")
    assert_not_null(loupe.icon, "drawn with its icon")

    assert_false(window.visible, "The search starts hidden")
    loupe.pressed.emit()
    assert_true(window.visible, "A press of the loupe opens it")
    assert_eq(window.field.text, "", "with an empty field")
    _tear_down(built)


## The room `fit` is handed is taken less the loupe: a room just wide enough
## for every title folds one, and the same room with the loupe's width added
## folds none.
func test_fit_leaves_the_loupe_its_room() -> void:
    var built := _build()
    var bar: TopMenuBar = built["bar"]
    var loupe := bar.find_child("SearchLoupe", true, false) as Button
    var titles := 0.0
    var count := 0
    for child in bar.menu_bar.get_children():
        var title := child as Button
        if title != null and SaSettings.get_element_visible("TopMenuBar", String(title.name)):
            titles += title.get_combined_minimum_size().x
            count += 1
    titles += float(bar.menu_bar.get_theme_constant("separation")) * float(count - 1)
    var cost := loupe.get_combined_minimum_size().x + float(loupe.get_parent().get_theme_constant("separation"))
    print("The loupe costs %.0f of the room at scale %.2f" % [cost, SaUI.scale()])

    bar.menu_overflow.fit(titles)
    assert_false(bar.menu_overflow.folded.is_empty(), "Room for the titles alone folds one for the loupe")
    bar.menu_overflow.fit(titles + cost)
    assert_true(bar.menu_overflow.folded.is_empty(), "and the loupe's width more folds none")
    _tear_down(built)


# --- Helpers ------------------------------------------------------------------


## What the control step does to a field: sets the text and says it changed.
func _type(window: SaSearchWindow, text: String) -> void:
    window.field.text = text
    window.field.text_changed.emit(text)


func _enter(window: SaSearchWindow) -> void:
    window.field.text_submitted.emit(window.field.text)


## An arrow key given to the open list, which reads it before its field does.
func _arrow(window: SaSearchWindow, keycode: Key) -> void:
    var key := InputEventKey.new()
    key.keycode = keycode
    key.pressed = true
    window.push_input(key)


## A docker in the tree under `MainDockers`, two tools in a machine over the
## context's tool registry, the application's commands, a bar bound to them,
## and the search over it all, under an autoload: the runner calls a test from
## its own `_ready`, and a parent mid-`_ready` rejects `add_child`
## (a known engine limit).
func _build() -> Dictionary:
    var tree := Engine.get_main_loop() as SceneTree
    var embedded: bool = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    var host := Node.new()
    host.name = "F1SearchHost"
    EventBus.add_child(host)

    var docker := Window.new()
    docker.name = "ProbeDocker"
    host.add_child(docker)
    docker.hide()

    var registries := Fixtures.make_registries()
    registries.ui.register_docker(DOCKER, "Brush Presets", func() -> Window: return Window.new(), DOCKER_TOGGLE)
    registries.ui.set_docker_node(DOCKER, docker)
    for tool: Array in [[&"probe_pen", "Probe Pen"], [&"probe_knife", "Probe Knife"]]:
        var descriptor := Fixtures.make_tool_descriptor(tool[0])
        descriptor.display_name = tool[1]
        registries.tools.register(descriptor)

    var view := ProbeView.new()
    var machine := ToolMachine.new()
    machine.name = "ToolMachine"
    machine.bind(SaSurface.create(&"search", null, view), registries.tools)
    var provider := func() -> ToolMachine: return machine

    var dockers := MainDockers.new(registries.ui, StubStore.new())
    host.add_child(dockers)
    SaAppCommands.register_all(registries, dockers.toggle_docker_by_id, provider)

    var bar := TopMenuBar.new()
    host.add_child(bar)
    bar.bind_commands(registries.commands)

    var window := SaSearchWindow.new(SaSearchIndex.new(registries.context))
    host.add_child(window)

    return {
        "tree": tree,
        "embedded": embedded,
        "host": host,
        "docker": docker,
        "registries": registries,
        "machine": machine,
        "view": view,
        "bar": bar,
        "window": window,
    }


func _tear_down(built: Dictionary) -> void:
    Fixtures.teardown(null, built["machine"])
    (built["host"] as Node).free()
    (built["tree"] as SceneTree).root.gui_embed_subwindows = bool(built["embedded"])
