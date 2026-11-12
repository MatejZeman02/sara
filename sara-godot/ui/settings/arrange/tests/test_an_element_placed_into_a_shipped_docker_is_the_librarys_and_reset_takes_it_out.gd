## An element placed into a shipped docker is kept in the library under that
## docker's id and drawn after its own elements, and Reset to shipped takes it
## out.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The idea: every docker is a composition in this sense, the defaults
## included. So the suite opens the Colour Picker's Elements… page, picks the
## Toolbox's Brush Tool from Add element…, and reads the library holding it
## under `ColorPicker`, the id the page and the profile know the Colour Picker
## by, while the profile, the live layout file and a layout captured from the
## profile hold none of it. The window is a Colour Picker of the
## suite's own, built detached and registered in the suite's own registry, so
## the column of placed views it is handed is read without the running app.
## Reset to shipped on the same page takes the placement out of the library and
## the window. The scenario
## `an-element-can-be-placed-into-a-shipped-docker-and-reset-to-shipped-takes-it-out.json`
## is the half in the running app, the `default` layout loaded between.
extends "res://tests/test_framework.gd"

const ScratchFolder := preload("res://tests/fixtures/scratch_folder.gd")
const ColorDockerScript := preload("res://ui/dockers/color/color_docker.gd")
const PlacedViews := preload("res://ui/dockers/composed/placed_views.gd")
const COLOR := "ColorPicker"
const BRUSH := "Brush Tool"
const ERASER := "Eraser Tool"

static var scratch_dir: String = SaDataRoot.path("test_placed_in_shipped")
static var library_path: String = scratch_dir.path_join("composed_dockers.cfg")
static var live_layout_path: String = SaDataRoot.path(DockerLayoutStore.FILE_NAME)

var _registry: SaUIRegistry = null
var _library: SaComposedDockers = null
var _window: DockerWindow = null
var _page: SaLayoutPage = null
var _profile_changes: Array = []


func before_each() -> void:
    ScratchFolder.clear(scratch_dir)
    SaToolBoxViews.register()
    _registry = SaUIRegistry.new()
    _registry.register_docker(SaDockerIds.COLOR, "Colour Picker", ColorDockerScript.new)
    _window = ColorDockerScript.new()
    _registry.set_docker_node(SaDockerIds.COLOR, _window)
    _library = SaComposedDockers.new(_registry, library_path)
    _page = SaLayoutPage.new(COLOR, SaLayoutPage.ELEMENTS, Callable(), _library)
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
    _library = null
    _registry = null
    ScratchFolder.clear(scratch_dir)


func _heard_profile_change() -> void:
    _profile_changes.append(true)


func _placed() -> SaPlacedElements:
    return _page._placed


## Picks *element* of *category* from Add element…'s list, as the row a hand
## presses.
func _pick(category: String, element: String) -> bool:
    _placed().fill_list()
    return _placed().choices.press_row(StringName("%s/%s" % [category, element]))


## What the library's file holds under *section*, each as "element on|off".
func _filed(section: String) -> Array:
    var stored := ConfigFile.new()
    stored.load(library_path)
    return (stored.get_value(section, "elements", []) as Array).map(
        func(entry: Dictionary) -> String: return "%s %s" % [entry["element"], "on" if entry["visible"] else "off"]
    )


func _file_sections() -> PackedStringArray:
    var stored := ConfigFile.new()
    stored.load(library_path)
    return stored.get_sections()


## The names of the views *window* draws in its column of placed elements.
static func _view_names(window: DockerWindow) -> Array:
    var column := window.placed_column as PlacedViews
    if column == null:
        return []
    return column.views().map(func(view: Control) -> String: return String(view.name) if view != null else "")


func _live_layout_text() -> String:
    return FileAccess.get_file_as_string(live_layout_path) if FileAccess.file_exists(live_layout_path) else ""


## What a layout saved now would hold, captured from the profile the way
## Save layout does.
func _captured_layout() -> String:
    var cfg := ConfigFile.new()
    SaDockerLayoutPresets.new(live_layout_path).capture(cfg)
    return cfg.encode_to_text()


## The first element of the Colour Picker's own that has a view, which Add
## element… offers elsewhere and has to refuse here.
func _own_placeable() -> String:
    for home: Dictionary in SaSettings.placeable_elements():
        if String(home["id"]) == COLOR and not (home["elements"] as Array).is_empty():
            return String(home["elements"][0]["id"])
    return ""


func test_the_colour_pickers_page_offers_add_element_with_its_own_elements_dimmed() -> void:
    assert_not_null(_page.page.row(SaPlacedElements.ADD_ROW), "a shipped docker's Elements… page carries Add element…")
    var own := _own_placeable()
    assert_false(own.is_empty(), "the Colour Picker has an element with a view")
    _placed().fill_list()
    var own_id := StringName("%s/%s" % [COLOR, own])
    assert_true(_placed().choices.row_ids().has(own_id), "its own element is listed under its title")
    assert_true(_placed().choices.is_disabled(own_id), "and dimmed")
    assert_false(_placed().add(COLOR, own), "and a docker is not placed into itself")
    assert_false(_placed().choices.is_disabled(StringName("%s/%s" % [SaDockerIds.TOOLBOX, BRUSH])), "the Brush Tool is offered")
    var bar := SaLayoutPage.new("TopMenuBar", SaLayoutPage.ELEMENTS, Callable(), _library)
    assert_null(bar._placed, "the top bar, being no docker, has no Add element…")
    bar.free()


func test_a_pick_is_kept_in_the_library_under_the_colour_pickers_id_and_drawn_after_its_own() -> void:
    var own_order := SaSettings.get_layout_order(COLOR)
    assert_true(_pick(String(SaDockerIds.TOOLBOX), BRUSH), "the Brush Tool row takes the press")
    assert_eq(_filed(COLOR), ["Brush Tool on"], "the library's file holds it under the Colour Picker's id")
    assert_eq(_library.elements_of(StringName(COLOR)).size(), 1, "and so does the library")
    assert_false(SaComposedDockers.is_composed(COLOR), "while the Colour Picker stays a shipped docker")
    assert_eq(_view_names(_window), ["BrushTool"], "the window draws its view at once")
    var column := _window.placed_column
    assert_eq(column.get_parent(), _window.content_column(), "in the docker's own column")
    assert_eq(column.get_index(), _window.content_column().get_child_count() - 1, "after its own elements")
    var listed: Array = own_order.map(func(element: String) -> int: return _page.row_for(element).get_index())
    var brush := _page.row_for(BRUSH) as SaPlacedElements.PlacedRow
    assert_not_null(brush, "the page lists the Brush Tool as a placed row")
    assert_true(brush.get_index() > int(listed.max()), "after every row of the docker's own")
    assert_not_null(brush.check_button, "with a switch")

    # The band a drag keeps each kind of row in: what is placed stays after
    # the docker's own rows, and an own row stays above it.
    var own_count: int = own_order.size()
    assert_eq(_page.drop_band(brush), Vector2i(own_count, own_count), "a placed row stays below the own rows")
    var last_own := _page.row_for(own_order[own_count - 1])
    assert_eq(_page.drop_band(last_own).y, own_count - 1, "and an own row above the placed one")

    _page.row_for(BRUSH).check_button.button_pressed = false
    assert_eq(_filed(COLOR), ["Brush Tool off"], "the switch is the library's too")
    assert_false(_window.placed_column.get_child(0).visible, "and hides the view")
    assert_true(SaSettings.get_element_visible(String(SaDockerIds.TOOLBOX), BRUSH), "while the Toolbox still draws it")


func test_the_profile_and_the_layout_file_hold_none_of_it() -> void:
    var profile_before := SaSettings.config.encode_to_text()
    var layout_before := _live_layout_text()
    var captured_before := _captured_layout()
    var own_order := SaSettings.get_layout_order(COLOR)
    _pick(String(SaDockerIds.TOOLBOX), BRUSH)
    _pick(String(SaDockerIds.TOOLBOX), ERASER)
    assert_eq(_filed(COLOR), ["Brush Tool on", "Eraser Tool on"], "the library holds both")
    assert_eq(_live_layout_text(), layout_before, "the live layout file holds none of it")
    assert_eq(_captured_layout(), captured_before, "nor does a layout saved now")
    var cfg := ConfigFile.new()
    cfg.parse(_captured_layout())
    assert_false((cfg.get_value(SaDockerLayoutPresets.ORDER_SECTION, COLOR, []) as Array).has(BRUSH), "no Brush in its order")
    var key := "%s/%s" % [COLOR, BRUSH]
    assert_false(cfg.has_section_key(SaDockerLayoutPresets.VISIBILITY_SECTION, key), "nor a switch of it")
    assert_eq(SaSettings.config.encode_to_text(), profile_before, "the profile holds none of it")
    assert_eq(SaSettings.get_layout_order(COLOR), own_order, "the Colour Picker's own order is untouched")
    assert_eq(_profile_changes.size(), 0, "and no profile_changed, so no shipped layout is forked")


func test_a_library_read_again_hands_the_placement_to_a_window_built_later() -> void:
    _pick(String(SaDockerIds.TOOLBOX), BRUSH)
    var later: DockerWindow = ColorDockerScript.new()
    _registry.set_docker_node(SaDockerIds.COLOR, later)
    var again := SaComposedDockers.new(_registry, library_path)
    assert_eq(again.elements_of(StringName(COLOR)).size(), 1, "the library read from its file holds the placement")
    again.hold_each()
    assert_eq(_view_names(later), ["BrushTool"], "and hands it to the window the boot built")
    again.hold_each()
    assert_eq(_view_names(later), ["BrushTool"], "a second hand builds no second view")
    later.free()


func test_reset_to_shipped_takes_the_placement_out() -> void:
    _pick(String(SaDockerIds.TOOLBOX), BRUSH)
    var reset := _page.page.row(&"reset")
    assert_not_null(reset, "the Colour Picker's page carries Reset to shipped")
    if reset == null:
        return
    # The reset forgets what the run's profile stores of the Colour Picker, so
    # that is put back after, for the suites that run later.
    var stored: Array = []
    if SaSettings.config.has_section_key("profile_order", COLOR):
        stored = SaSettings.config.get_value("profile_order", COLOR)
    var switched: Dictionary[String, bool] = {}
    for element: String in SaSettings.get_layout_order(COLOR):
        if SaSettings.config.has_section_key("profile_visibility", COLOR + "_" + element):
            switched[element] = SaSettings.get_element_visible(COLOR, element)
    (reset.control as Button).pressed.emit()
    _reads_the_colour_picker_without_the_brush()
    if not stored.is_empty():
        SaSettings.set_layout_order(COLOR, stored)
    for element: String in switched:
        SaSettings.set_element_visible(COLOR, element, switched[element])


func _reads_the_colour_picker_without_the_brush() -> void:
    assert_false(_file_sections().has(COLOR), "the library's file holds no section of the Colour Picker")
    assert_eq(_library.elements_of(StringName(COLOR)), [], "nor does the library")
    assert_eq(_view_names(_window), [], "the window draws no placed view")
    assert_null(_page.row_for(BRUSH), "and the page lists the Colour Picker's own rows alone")
    assert_false(SaSettings.config.has_section_key("profile_order", COLOR), "in the order it shipped in")
    _placed().fill_list()
    assert_false(
        _placed().choices.is_disabled(StringName("%s/%s" % [SaDockerIds.TOOLBOX, BRUSH])), "and the Brush is offered again"
    )
