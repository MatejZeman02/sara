## Layouts and dockers makes a new docker, empty or forked, and deletes one.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The idea: a user forks an existing docker, or starts an empty one.
## So the suite forks the Toolbox and reads the fork holding the Toolbox's
## tools in the Toolbox's order, forks a fixture category registered through
## the door a module uses and reads only its placeable elements, its hidden
## one hidden, makes an empty one, refuses a name a docker already has, and
## deletes one through the question, which keeps it on Cancel and forgets it on
## Delete. Last it builds the page and reads the row, the Delete on a composed
## docker's line and the search finding the row by its words.
##
## The library is the suite's own, on a file in a scratch folder of the data
## root, and its registry is too, so the app's dockers never hear of these. The
## scenario
## `layouts-and-dockers-makes-a-new-docker-empty-or-forked-and-deletes-one.json`
## is the half in the running app: the line, the Window menu and the window.
extends "res://tests/test_framework.gd"

const ScratchFolder := preload("res://tests/fixtures/scratch_folder.gd")
const CATEGORY := "ForkFixture"
const SHOWN := "Alpha"
const NO_VIEW := "Beta"
const HIDDEN := "Gamma"
## A composed docker's category the page draws a line for, past any id the
## suite's library hands out.
const LINED := "composed_9301"

static var scratch_dir: String = SaDataRoot.path("test_new_docker")
static var library_path: String = scratch_dir.path_join("composed_dockers.cfg")

var _registry: SaUIRegistry = null
var _library: SaComposedDockers = null
var _section: SaComposedDockersSection = null
var _host: Node = null
var _previous_embedding: bool = true


func before_each() -> void:
    ScratchFolder.clear(scratch_dir)
    SaSettings.register_layout_category(CATEGORY, "Fork Fixture", ["Drag Handle", "Resizer", SHOWN, NO_VIEW, HIDDEN])
    SaSettings.register_layout_element(CATEGORY, SHOWN, SHOWN, false, "", _build_view.bind(SHOWN))
    SaSettings.register_layout_element(CATEGORY, HIDDEN, HIDDEN, false, "", _build_view.bind(HIDDEN))
    SaSettings.set_element_visible(CATEGORY, HIDDEN, false)
    # The Toolbox's views, as its docker registers them when it is built, so
    # the fork reads what the app offers whether or not a suite before this
    # one built a Toolbox.
    SaToolBoxViews.register()
    _registry = SaUIRegistry.new()
    _library = SaComposedDockers.new(_registry, library_path)
    _section = SaComposedDockersSection.new(_library)


func after_each() -> void:
    if _host != null:
        _host.free()
        _host = null
        (Engine.get_main_loop() as SceneTree).root.gui_embed_subwindows = _previous_embedding
    SaSettings.unregister_layout_category(LINED)
    for element: String in [SHOWN, HIDDEN]:
        SaSettings.unregister_layout_element(CATEGORY, element)
    SaSettings.reset_layout_category(CATEGORY)
    SaSettings.unregister_layout_category(CATEGORY)
    _section = null
    _library = null
    _registry = null
    ScratchFolder.clear(scratch_dir)


func _build_view(view_name: String) -> Control:
    var view := Label.new()
    view.name = view_name
    view.text = view_name
    return view


func _names(elements: Array) -> Array:
    return elements.map(func(entry: Dictionary) -> String: return String(entry["element"]))


func test_a_fork_of_the_toolbox_holds_its_tools_in_its_order() -> void:
    var toolbox := String(SaDockerIds.TOOLBOX)
    var tools: Array = []
    for element: Variant in SaSettings.get_layout_order(toolbox):
        if not SaSettings.ELEMENT_PLACES.has(String(element)):
            tools.append(String(element))
    assert_eq(
        tools, SaToolBoxViews.tool_elements(), "the Toolbox lists a fresh profile's tools between its drag bar and its grip"
    )
    var made := _section.make("My Tools", toolbox)
    assert_true(made != &"", "the fork is made")
    var held := _library.elements_of(made)
    assert_eq(_names(held), tools, "the fork holds the Toolbox's tools in the Toolbox's order")
    for entry: Dictionary in held:
        assert_eq(String(entry["category"]), toolbox, "each from the Toolbox, as at home")
        assert_true(bool(entry["visible"]), "%s is shown, as it is in the Toolbox" % entry["element"])
    assert_true(_registry.has_docker(made), "and registered as a docker")
    var stored := ConfigFile.new()
    stored.load(library_path)
    assert_eq(_names(stored.get_value(String(made), "elements", [])), tools, "the library's file holds the same")


func test_a_fork_takes_only_placeable_elements_and_keeps_its_hidden_ones_hidden() -> void:
    var made := _section.make("Forked Fixture", CATEGORY)
    var held := _library.elements_of(made)
    assert_eq(_names(held), [SHOWN, HIDDEN], "the element with no view and the two places stay at home")
    assert_true(bool(held[0]["visible"]), "the shown one is shown")
    assert_false(bool(held[1]["visible"]), "the hidden one is hidden, as it is at home")


func test_a_fork_of_a_docker_of_your_own_holds_what_it_holds() -> void:
    var first := _section.make("First", CATEGORY)
    var second := _section.make("Second", String(first))
    assert_eq(_library.elements_of(second), _library.elements_of(first), "the same elements and switches")


func test_an_empty_docker_holds_nothing_and_is_registered() -> void:
    var made := _section.make("  Mine  ", SaComposedDockersSection.EMPTY)
    assert_eq(_library.name_of(made), "Mine", "named by the field, its edges trimmed")
    assert_eq(_library.elements_of(made), [], "an empty docker holds nothing")
    assert_true(_registry.has_docker(made), "and is registered as any docker")


func test_a_name_a_docker_already_has_is_refused() -> void:
    var toolbox_title := SaDockersPage.docker_title(String(SaDockerIds.TOOLBOX))
    assert_false(toolbox_title.is_empty(), "the Toolbox has a title")
    assert_eq(_section.make(toolbox_title, SaComposedDockersSection.EMPTY), &"", "a built-in's name is refused")
    assert_true(_section.make("Mine", SaComposedDockersSection.EMPTY) != &"", "a new name is taken")
    assert_eq(_section.make("mine", SaComposedDockersSection.EMPTY), &"", "a name of your own in another case too")
    assert_eq(_section.make("   ", SaComposedDockersSection.EMPTY), &"", "and an empty one")
    assert_eq(_library.list().size(), 1, "one docker was made")


func test_a_delete_asks_and_only_its_yes_forgets_the_docker() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    _previous_embedding = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    _host = Node.new()
    _host.name = "QuestionHost"
    EventBus.add_child(_host)
    var made := _section.make("Mine", SaComposedDockersSection.EMPTY)
    var heard: Array = []
    _section.changed.connect(func() -> void: heard.append(true))

    var asked := _section.ask_to_delete(_host, made)
    assert_not_null(asked, "Delete puts a question up")
    assert_true(asked.title.contains("Mine"), "naming the docker")
    assert_eq(asked.buttons.size(), 2, "Cancel and Delete")
    assert_eq(asked.buttons[SaComposedDockersSection.ANSWER_CANCEL].text, "Cancel", "Cancel first")
    asked.buttons[SaComposedDockersSection.ANSWER_CANCEL].pressed.emit()
    assert_true(_library.has(made), "Cancel keeps the docker")
    assert_true(_registry.has_docker(made), "registered still")
    assert_eq(heard.size(), 0, "and the page is not drawn again")

    asked = _section.ask_to_delete(_host, made)
    asked.buttons[SaComposedDockersSection.ANSWER_DELETE].pressed.emit()
    assert_false(_library.has(made), "Delete forgets it")
    assert_false(_registry.has_docker(made), "and the registry no longer has it")
    var stored := ConfigFile.new()
    stored.load(library_path)
    assert_false(stored.has_section(String(made)), "nor the library's file")
    assert_eq(heard.size(), 1, "and the page is drawn again")


func test_the_page_offers_the_row_and_a_delete_on_a_composed_line() -> void:
    SaSettings.register_layout_category(LINED, "Lined Docker", ["Drag Handle", "Resizer"])
    var page := SaDockersPage.new()
    var line: Dictionary = page._lines[SaDockersPage.line_key(LINED)]
    assert_not_null(line["delete"], "a composed docker's line carries Delete")
    assert_null(line["options"], "and no Options…")
    var toolbox_line: Dictionary = page._lines[SaDockersPage.line_key(String(SaDockerIds.TOOLBOX))]
    assert_null(toolbox_line["delete"], "a built-in's line has no Delete")
    for node_name: String in ["NewDockerName", "NewDockerStart", "NewDockerMake"]:
        assert_not_null(page.find_child(node_name, true, false), "the row has %s" % node_name)
    var start := page.find_child("NewDockerStart", true, false) as SaChoiceButton
    var labels := start.choice_labels()
    assert_eq(labels[0], "Empty", "Empty is the first start")
    assert_true(labels.has(SaDockersPage.docker_title(String(SaDockerIds.TOOLBOX))), "the Toolbox is a start")
    assert_true(labels.has("Lined Docker"), "and so is a docker of your own")
    var found := false
    for landing: Control in SaSettingsSearch.landings(page):
        if SaSettingsSearch.landing_title(landing) == "New docker":
            var words := SaSettingsSearch.row_haystack(landing)
            found = SaSettingsSearch.matches(words, "fork") and SaSettingsSearch.matches(words, "empty")
    assert_true(found, "the search finds the row by fork and by empty")
    page.free()
