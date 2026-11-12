## A docker's Elements… page adds an element from any docker and takes a placed
## one out.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The idea: the painter arranges elements from any other docker in
## their own. So the suite opens the Elements… page of a docker of its own
## library and reads Add element…'s list, every placeable element under its
## home docker's title, the Toolbox's tools and a fixture category a module
## registered. It picks the Toolbox's Brush Tool and Eraser Tool and reads
## each placed at the end with its view built at once in the docker's window,
## moves the Eraser above the Brush, switches the Brush off and takes it out,
## and after each reads the library holding the order the page shows, while
## the profile and the live layout file hold none of it.
##
## The library is the suite's own, on a file in a scratch folder of the data
## root, and so is its registry. The window is built by the registry's factory
## and kept detached, as the suites for docker windows keep one. The scenario
## `a-docker-s-elements-page-adds-an-element-from-any-docker-and-takes-a-placed-one-out.json`
## is the half in the running app, the page driven by hand and the docker shot.
extends "res://tests/test_framework.gd"

const ScratchFolder := preload("res://tests/fixtures/scratch_folder.gd")
const ComposedDocker := preload("res://ui/dockers/composed/composed_docker.gd")
const CATEGORY := "ModuleFixture"
const VIEWED := "Probe Viewed"
const NO_VIEW := "Probe Plain"
const BRUSH := "Brush Tool"
const ERASER := "Eraser Tool"

static var scratch_dir: String = SaDataRoot.path("test_placed_elements")
static var library_path: String = scratch_dir.path_join("composed_dockers.cfg")
static var live_layout_path: String = SaDataRoot.path(DockerLayoutStore.FILE_NAME)

var _registry: SaUIRegistry = null
var _library: SaComposedDockers = null
var _docker_id: StringName = &""
var _window: ComposedDocker = null
var _page: SaLayoutPage = null
var _profile_changes: Array = []


func before_each() -> void:
    ScratchFolder.clear(scratch_dir)
    SaSettings.register_layout_category(CATEGORY, "Elements Module Fixture", ["Drag Handle", "Resizer", VIEWED, NO_VIEW])
    SaSettings.register_layout_element(CATEGORY, VIEWED, VIEWED, false, "", _build_view.bind(VIEWED))
    SaToolBoxViews.register()
    _registry = SaUIRegistry.new()
    _library = SaComposedDockers.new(_registry, library_path)
    _docker_id = _library.make("Elements Mine")
    SaSettings.register_layout_category(String(_docker_id), "Elements Mine", ["Drag Handle", "Resizer"])
    _window = _registry.get_docker_entry(_docker_id)["factory"].call()
    _registry.set_docker_node(_docker_id, _window)
    _page = SaLayoutPage.new(String(_docker_id), SaLayoutPage.ELEMENTS, Callable(), _library)
    _profile_changes.clear()
    SaSettings.profile_changed.connect(_heard_profile_change)


func after_each() -> void:
    SaSettings.profile_changed.disconnect(_heard_profile_change)
    if is_instance_valid(_page):
        _page.free()
    _page = null
    if is_instance_valid(_window):
        _window.free()
    _window = null
    SaSettings.unregister_layout_category(String(_docker_id))
    SaSettings.unregister_layout_element(CATEGORY, VIEWED)
    SaSettings.unregister_layout_category(CATEGORY)
    _library = null
    _registry = null
    ScratchFolder.clear(scratch_dir)


func _heard_profile_change() -> void:
    _profile_changes.append(true)


func _build_view(view_name: String) -> Control:
    var view := Label.new()
    view.name = view_name.replace(" ", "")
    view.text = view_name
    return view


func _placed() -> SaPlacedElements:
    return _page._placed


## Picks *element* of *category* from Add element…'s list, as the row a hand
## presses.
func _pick(category: String, element: String) -> bool:
    _placed().fill_list()
    return _placed().choices.press_row(StringName("%s/%s" % [category, element]))


## The page's rows, each as "element on|off", in the order the list draws them.
func _page_rows() -> Array:
    var out: Array = []
    for element: String in ["Drag Handle", "Resizer", BRUSH, ERASER, VIEWED]:
        var row := _page.row_for(element)
        if row != null:
            out.append([row.get_index(), "%s %s" % [element, "on" if row.check_button.button_pressed else "off"]])
    out.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
    return out.map(func(pair: Array) -> String: return pair[1])


## What the library holds, each as "element on|off", in order.
func _held(entries: Array) -> Array:
    return entries.map(
        func(entry: Dictionary) -> String: return "%s %s" % [entry["element"], "on" if entry["visible"] else "off"]
    )


## What the library's file holds for the docker, read from disk.
func _filed() -> Array:
    var stored := ConfigFile.new()
    stored.load(library_path)
    return _held(stored.get_value(String(_docker_id), "elements", []))


func _view_names() -> Array:
    return _window.views().map(func(view: Control) -> String: return String(view.name) if view != null else "")


func _live_layout_text() -> String:
    return FileAccess.get_file_as_string(live_layout_path) if FileAccess.file_exists(live_layout_path) else ""


func test_add_element_lists_every_placeable_element_under_its_home_dockers_title() -> void:
    assert_not_null(_page.page.row(SaPlacedElements.ADD_ROW), "a docker of your own's Elements… page carries Add element…")
    _placed().fill_list()
    var titles := _placed().choices.section_titles()
    assert_true(titles.has(SaDockersPage.docker_title(String(SaDockerIds.TOOLBOX))), "the Toolbox's title heads its tools")
    assert_true(titles.has("Elements Module Fixture"), "and a module's category heads its own")
    var offered := _placed().choices.row_ids()
    for home: Dictionary in SaSettings.placeable_elements():
        for element: Dictionary in home["elements"]:
            var row_id := StringName("%s/%s" % [home["id"], element["id"]])
            assert_true(offered.has(row_id), "%s of %s is offered" % [element["id"], home["title"]])
    assert_true(offered.has(StringName("%s/%s" % [CATEGORY, VIEWED])), "the module's element with a view is offered")
    assert_false(offered.has(StringName("%s/%s" % [CATEGORY, NO_VIEW])), "and its element with no view is not")
    for place: String in ["Drag Handle", "Resizer"]:
        assert_false(offered.has(StringName("%s/%s" % [SaDockerIds.TOOLBOX, place])), "nor a docker's %s" % place)


func test_a_pick_places_the_element_at_the_end_with_its_view_built_at_once() -> void:
    assert_eq(_page_rows(), ["Drag Handle on", "Resizer on"], "an empty docker's page lists its drag bar and grip")
    assert_true(_pick(String(SaDockerIds.TOOLBOX), BRUSH), "the Brush Tool row takes the press")
    assert_eq(_view_names(), ["BrushTool"], "its view is built in the docker at once")
    assert_true(_pick(String(SaDockerIds.TOOLBOX), ERASER), "the Eraser Tool row takes the press")
    assert_eq(_held(_library.elements_of(_docker_id)), ["Brush Tool on", "Eraser Tool on"], "each placed at the end")
    assert_eq(_view_names(), ["BrushTool", "EraserTool"], "and the docker holds the two in that order")
    var listed := ["Drag Handle on", "Resizer on", "Brush Tool on", "Eraser Tool on"]
    assert_eq(_page_rows(), listed, "the page lists them after the pair")
    var placed := _page.row_for(BRUSH) as SaPlacedElements.PlacedRow
    assert_not_null(placed, "a placed element's row is a placed row")
    assert_not_null(placed.take_out_button, "with a Take out")
    assert_eq(placed.home_title, SaDockersPage.docker_title(String(SaDockerIds.TOOLBOX)), "and the title of its home")
    _placed().fill_list()
    var brush_id := StringName("%s/%s" % [SaDockerIds.TOOLBOX, BRUSH])
    assert_true(_placed().choices.is_disabled(brush_id), "a placed element is dimmed in the list")
    assert_false(_pick(String(SaDockerIds.TOOLBOX), BRUSH), "and is not placed twice")
    assert_true(_pick(CATEGORY, VIEWED), "a module's element is placed the same way")
    assert_eq(_view_names(), ["BrushTool", "EraserTool", "ProbeViewed"], "with its view")


func test_the_library_holds_the_order_the_page_shows_and_the_profile_and_layout_none_of_it() -> void:
    var profile_before := SaSettings.config.encode_to_text()
    var layout_before := _live_layout_text()
    var toolbox := String(SaDockerIds.TOOLBOX)
    var toolbox_order := SaSettings.get_layout_order(toolbox)
    _pick(toolbox, BRUSH)
    _pick(toolbox, ERASER)

    # The drag: the Eraser's row carried above the Brush's, and the drop's write.
    var eraser := _page.row_for(ERASER)
    eraser.get_parent().move_child(eraser, _page.row_for(BRUSH).get_index())
    assert_true(_placed().write(), "the drop writes the library")
    var shown := ["Drag Handle on", "Resizer on", "Eraser Tool on", "Brush Tool on"]
    assert_eq(_page_rows(), shown, "the page shows the Eraser first")
    assert_eq(_held(_library.elements_of(_docker_id)), ["Eraser Tool on", "Brush Tool on"], "the library holds that order")
    assert_eq(_filed(), ["Eraser Tool on", "Brush Tool on"], "and so does its file")
    assert_eq(_view_names(), ["EraserTool", "BrushTool"], "and the docker draws it")

    # The switch, a hand's toggle of the Brush's row.
    _page.row_for(BRUSH).check_button.button_pressed = false
    assert_eq(_page_rows(), ["Drag Handle on", "Resizer on", "Eraser Tool on", "Brush Tool off"], "the page shows the Brush off")
    assert_eq(_filed(), ["Eraser Tool on", "Brush Tool off"], "and the library's file holds it off")
    assert_false(_window.placed.get_child(1).visible, "the docker hides the Brush's view")
    assert_true(SaSettings.get_element_visible(toolbox, BRUSH), "while the Toolbox still draws its Brush")

    assert_eq(SaSettings.config.encode_to_text(), profile_before, "the profile holds none of it")
    assert_false(SaSettings.config.has_section_key("profile_order", String(_docker_id)), "no order of the docker")
    assert_eq(SaSettings.get_layout_order(String(_docker_id)), ["Drag Handle", "Resizer"], "its own list is the pair alone")
    assert_eq(SaSettings.get_layout_order(toolbox), toolbox_order, "the Toolbox's order is untouched")
    assert_eq(_profile_changes.size(), 0, "and no profile_changed, so no shipped layout is forked")
    assert_eq(_live_layout_text(), layout_before, "the live layout file holds none of it")


func test_take_out_leaves_the_one_row_and_the_one_view() -> void:
    var toolbox := String(SaDockerIds.TOOLBOX)
    _pick(toolbox, BRUSH)
    _pick(toolbox, ERASER)
    var brush := _page.row_for(BRUSH) as SaPlacedElements.PlacedRow
    assert_true(_placed().take_out(brush), "the Brush is taken out")
    assert_eq(_page_rows(), ["Drag Handle on", "Resizer on", "Eraser Tool on"], "the page reads the one row left")
    assert_eq(_held(_library.elements_of(_docker_id)), ["Eraser Tool on"], "the library holds the Eraser alone")
    assert_eq(_filed(), ["Eraser Tool on"], "and so does its file")
    assert_eq(_view_names(), ["EraserTool"], "the docker holds the one view")
    assert_true(SaSettings.get_layout_order(toolbox).has(BRUSH), "and the Brush stays at home")
    _placed().fill_list()
    assert_false(_placed().choices.is_disabled(StringName("%s/%s" % [toolbox, BRUSH])), "it is offered again")


func test_the_gesture_refuses_a_pick_while_the_list_is_closed() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    var said := _page.drive_gesture(tree, Vector2.ZERO, {"pick": BRUSH, "from": "Toolbox"})
    assert_true(said.contains("closed"), "a pick needs the list open, as a hand's does: %s" % said)
    assert_eq(_library.elements_of(_docker_id), [], "and placed nothing")
    said = _page.drive_gesture(tree, Vector2.ZERO, {"take_out": BRUSH})
    assert_true(said.contains("no placed row"), "a take out of nothing placed says so: %s" % said)
