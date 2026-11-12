## One Page Edges button chooses whether the page keeps its size, grows or
## wraps, and the View menu holds it beside Environment View and Double
## Resolution, which a fresh top bar hides.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The button is stepped through its four modes by the middle of its icon, and
## each mode is read off `SaInfiniteCanvas.on` and the wrap, one undo step a
## press. The View menu's Page Edges rows tick the mode in front, dim on a
## panorama and run the same choice. A profile, a saved layout and a custom
## docker that name Infinite Canvas or Wrap load with Page Edges in its place.
extends "res://tests/test_framework.gd"

## The easel's document lives on the device.
const REQUIRES_GPU := true

const ScratchFolder := preload("res://tests/fixtures/scratch_folder.gd")

const FIXED := SaTopBarPageEdges.Mode.FIXED
const GROWS := SaTopBarPageEdges.Mode.GROWS
const SIDES := SaTopBarPageEdges.Mode.WRAPS_SIDES
const ALL := SaTopBarPageEdges.Mode.WRAPS_ALL

## Each mode as the growth and the wrap the document holds under it.
const HELD := {
    FIXED: [false, SaProjection.Wrap.NONE],
    GROWS: [true, SaProjection.Wrap.NONE],
    SIDES: [false, SaProjection.Wrap.X],
    ALL: [false, SaProjection.Wrap.XY],
}

## Each mode's row of View > Page Edges.
const ROWS := {
    FIXED: SaViewMenu.ID_PAGE_FIXED,
    GROWS: SaViewMenu.ID_PAGE_GROWS,
    SIDES: SaViewMenu.ID_PAGE_WRAPS_SIDES,
    ALL: SaViewMenu.ID_PAGE_WRAPS_ALL,
}

static var scratch_dir: String = SaDataRoot.path("test_page_edges_layouts")

var _surface: SaSurface = null
var _registries: SaRegistries = null
var _bar: TopMenuBar = null
var _menu: SaViewMenu = null
var _host: Node = null
var _was_placeable: bool = false


func before_each() -> void:
    _was_placeable = SaSettings.is_placeable(SaTopBarPageEdges.CATEGORY, SaTopBarPageEdges.ELEMENT)
    _surface = SaTestFixtures.make_surface(Vector2i(64, 64))
    _registries = SaTestFixtures.make_registries(_surface)
    if not _registries.commands.has(SaTopBarPageEdgesCommand.COMMAND):
        SaTopBarPageEdges.register_command(_registries.context.for_module(&"sara-skeleton"))
    if not _registries.commands.has(SaEnvironmentView.COMMAND):
        SaEnvironmentView.register_command(_registries.context.for_module(&"sara-skeleton"))
    if not _registries.commands.has(SaTopBarDoubleResolution.COMMAND):
        SaTopBarDoubleResolution.register_command(_registries.context.for_module(&"sara-skeleton"))
    _bar = TopMenuBar.new()
    _bar._ready()
    _menu = _bar.menu("View")
    _menu.bind_commands(_registries.commands)
    _host = Node.new()
    _host.name = "PageEdgesTestHost"
    EventBus.add_child(_host)


func after_each() -> void:
    if _was_placeable:
        SaTopBarPageEdges.register()
    else:
        SaSettings.unregister_layout_element(SaTopBarPageEdges.CATEGORY, SaTopBarPageEdges.ELEMENT)
    if _host != null:
        _host.free()
        _host = null
    _bar.free()
    _bar = null
    _menu = null
    _surface.easel.free()
    _surface = null
    _registries = null
    ScratchFolder.clear(scratch_dir)


func _document() -> SaDocument:
    return _surface.easel.document


func _button() -> Button:
    var bar := Control.new()
    _host.add_child(bar)
    return SaTopBarPageEdges.home(bar, _document)[SaTopBarPageEdges.ELEMENT] as Button


func _name(mode: SaTopBarPageEdges.Mode) -> String:
    return {FIXED: "Fixed", GROWS: "Grows", SIDES: "Wraps Sides", ALL: "Wraps All Edges"}[mode]


func _holds(mode: SaTopBarPageEdges.Mode, said: String) -> void:
    var held: Array = HELD[mode]
    assert_eq(_document().infinite_canvas.on, held[0], "%s: the page grows only under Grows" % said)
    assert_eq(_document().projection.wrapping, held[1], "%s: and the wrap is the mode's" % said)


func test_the_middle_steps_the_four_modes_each_press_one_undo_step() -> void:
    var button := _button()
    var follower := SaTopBarPageEdges.follower_of(button)
    var history := _document().history
    var steps := history.step_count()
    _holds(FIXED, "A fresh document")
    var walked: Array = []
    for wanted: SaTopBarPageEdges.Mode in [GROWS, SIDES, ALL, FIXED]:
        follower.press()
        walked.append(wanted)
        _holds(wanted, "A press on the middle to %s" % _name(wanted))
        assert_eq(SaTopBarPageEdges.mode_of(_document()), wanted, "and the mode reads %s" % _name(wanted))
        assert_eq(button.button_pressed, wanted != FIXED, "the icon pressed while the edges are not Fixed")
        assert_eq(history.step_count(), steps + walked.size(), "one undo step for the press to %s" % _name(wanted))
    for at in range(walked.size() - 1, 0, -1):
        _document().undo()
        _holds(walked[at - 1], "An undo back to %s" % _name(walked[at - 1]))
    _document().undo()
    _holds(FIXED, "The last undo back to the start")
    _document().redo()
    _holds(GROWS, "A redo to Grows")


func test_choosing_the_mode_in_force_leaves_no_step() -> void:
    var steps := _document().history.step_count()
    assert_false(SaTopBarPageEdges.choose(_document(), FIXED), "Fixed on a fixed page changes nothing")
    assert_eq(_document().history.step_count(), steps, "and leaves no step")


func test_a_wrap_chosen_while_the_page_grows_changes_both_in_one_step() -> void:
    SaTopBarPageEdges.choose(_document(), GROWS)
    var steps := _document().history.step_count()
    SaTopBarPageEdges.choose(_document(), SIDES)
    _holds(SIDES, "Wraps Sides chosen while the page grows")
    assert_eq(_document().history.step_count(), steps + 1, "as one step")
    _document().undo()
    _holds(GROWS, "and one undo puts the growth back")


func test_the_element_stands_after_environment_view_hidden_on_a_fresh_bar() -> void:
    _button()
    assert_true(SaSettings.is_placeable(SaTopBarPageEdges.CATEGORY, SaTopBarPageEdges.ELEMENT), "Page Edges can be placed")
    # The order a profile with nothing stored reads, since a suite before this
    # one may have stored the bar's order, which puts what it lacks at its end.
    var order := SaSettings._layout._fresh_order(SaTopBarPageEdges.CATEGORY)
    var environment := order.find(SaTopBarEnvironment.ELEMENT)
    assert_true(environment >= 0, "The bar's order has Environment View")
    assert_eq(order.find(SaTopBarPageEdges.ELEMENT), environment + 1, "and Page Edges right after it")
    for retired: String in SaTopBarPageEdges.RETIRED:
        assert_false(order.has(retired), "%s is no element of the bar" % retired)
        assert_false(SaSettings.is_placeable(SaTopBarPageEdges.CATEGORY, retired), "nor one a docker can place")


func test_a_panorama_and_no_document_grey_the_button() -> void:
    _document().projection = SaProjection.new(SaProjection.Equirectangular.new())
    var button := _button()
    SaTopBarPageEdges.follower_of(button).sync()
    assert_true(button.disabled, "A panorama greys the button")
    assert_true(button.tooltip_text.contains("projection"), "and says the projection sets its wrap")
    assert_false(SaTopBarPageEdges.choose(_document(), GROWS), "and its page is never made to grow")
    var bar := Control.new()
    _host.add_child(bar)
    var none: Button = SaTopBarPageEdges.home(bar, func() -> SaDocument: return null)[SaTopBarPageEdges.ELEMENT]
    SaTopBarPageEdges.follower_of(none).sync()
    assert_true(none.disabled, "With no document the button is greyed")


func test_the_view_menu_ticks_the_mode_in_front_and_runs_its_choice() -> void:
    _menu.populate()
    var list := SaMenu.group_list(_menu.popup, SaViewMenu.ID_PAGE_EDGES_GROUP)
    assert_not_null(list, "View holds a Page Edges submenu")
    for mode: SaTopBarPageEdges.Mode in ROWS:
        assert_true(_menu.has_item(ROWS[mode]), "with a row for %s" % _name(mode))
    assert_true(_menu.has_item(SaViewMenu.ID_ENVIRONMENT), "Environment View is a row of View")
    assert_true(_menu.has_item(SaViewMenu.ID_DOUBLE_RESOLUTION), "and Double Resolution as well")
    for mode: SaTopBarPageEdges.Mode in [GROWS, ALL, SIDES, FIXED]:
        _menu.on_id_pressed(ROWS[mode])
        _holds(mode, "View > Page Edges > %s" % _name(mode))
        _menu.populate()
        for other: SaTopBarPageEdges.Mode in ROWS:
            assert_eq(_menu.is_item_checked(ROWS[other]), other == mode, "the menu ticks %s alone" % _name(mode))
    _menu.on_id_pressed(SaViewMenu.ID_DOUBLE_RESOLUTION)
    assert_true(_document().double_resolution.on, "Double Resolution's row turns the switch on")
    _menu.populate()
    assert_true(_menu.is_item_checked(SaViewMenu.ID_DOUBLE_RESOLUTION), "and is ticked when the menu opens again")


func test_the_view_menu_dims_page_edges_on_a_panorama() -> void:
    _document().projection = SaProjection.new(SaProjection.Equirectangular.new())
    _menu.populate()
    var list := SaMenu.group_list(_menu.popup, SaViewMenu.ID_PAGE_EDGES_GROUP)
    for mode: SaTopBarPageEdges.Mode in ROWS:
        assert_true(list.label_button(SaMenu.key(ROWS[mode])).disabled, "%s is dimmed on a panorama" % _name(mode))


func test_a_profile_that_placed_the_old_elements_shows_page_edges_in_their_place() -> void:
    var config := ConfigFile.new()
    config.set_value("profile_order", "TopMenuBar", ["Environment View", "Infinite Canvas", "Wrap", "Double Resolution"])
    config.set_value("profile_visibility", "TopMenuBar_Infinite Canvas", false)
    config.set_value("profile_visibility", "TopMenuBar_Wrap", true)
    SaSettingsMigrations.apply(config, SaSettingsMigrations.SETTINGS_VERSION - 1)
    assert_eq(
        config.get_value("profile_order", "TopMenuBar"),
        ["Environment View", "Page Edges", "Double Resolution"],
        "Page Edges takes the place of the first, and the other goes",
    )
    assert_true(config.get_value("profile_visibility", "TopMenuBar_Page Edges"), "shown, since Wrap was")
    assert_false(config.has_section_key("profile_visibility", "TopMenuBar_Wrap"), "and the old keys are gone")
    @warning_ignore("static_called_on_instance")
    assert_eq(SaSettings.page_edges_order(["Wrap", "A"]), ["Page Edges", "A"], "Wrap alone becomes Page Edges")


func test_a_custom_docker_that_placed_infinite_canvas_holds_page_edges() -> void:
    DirAccess.make_dir_recursive_absolute(scratch_dir)
    var path := scratch_dir.path_join("composed_dockers.cfg")
    var docker_id := SaComposedDockers.ID_PREFIX + "1"
    var written := ConfigFile.new()
    written.set_value(SaComposedDockers.LIBRARY_SECTION, "order", [docker_id])
    written.set_value(SaComposedDockers.LIBRARY_SECTION, "next", 2)
    written.set_value(docker_id, "name", "Mine")
    var placed := [
        {"category": "TopMenuBar", "element": "Infinite Canvas", "visible": true},
        {"category": "TopMenuBar", "element": "Wrap", "visible": true},
        {"category": "TopMenuBar", "element": "Environment View", "visible": true},
    ]
    written.set_value(docker_id, "elements", placed)
    written.save(path)
    var library := SaComposedDockers.new(SaUIRegistry.new(), path)
    var held: Array = library.elements_of(StringName(docker_id))
    var names: Array = held.map(func(entry: Dictionary) -> String: return entry["element"])
    assert_eq(names, ["Page Edges", "Environment View"], "the docker holds Page Edges once, in the first one's place")


func test_a_saved_layout_that_names_wrap_loads_with_page_edges() -> void:
    _button()
    var kept_order := SaSettings.get_layout_order(SaTopBarPageEdges.CATEGORY)
    var kept_shown := SaSettings.get_element_visible(SaTopBarPageEdges.CATEGORY, SaTopBarPageEdges.ELEMENT)
    var layout := ConfigFile.new()
    var order := kept_order.duplicate()
    order[order.find(SaTopBarPageEdges.ELEMENT)] = "Wrap"
    layout.set_value(SaDockerLayoutPresets.ORDER_SECTION, SaTopBarPageEdges.CATEGORY, order)
    layout.set_value(SaDockerLayoutPresets.VISIBILITY_SECTION, "TopMenuBar/Wrap", true)
    SaDockerLayoutPresets.new(scratch_dir.path_join("layout.cfg")).apply(layout)
    var loaded := SaSettings.get_layout_order(SaTopBarPageEdges.CATEGORY)
    var shown := SaSettings.get_element_visible(SaTopBarPageEdges.CATEGORY, SaTopBarPageEdges.ELEMENT)
    var category := SaTopBarPageEdges.CATEGORY
    var element := SaTopBarPageEdges.ELEMENT
    SaSettings.set_layout_many({category: kept_order}, [[category, element, kept_shown]])
    assert_eq(loaded.find(element), kept_order.find(element), "Page Edges stands where Wrap stood")
    assert_false(loaded.has("Wrap"), "and Wrap is gone")
    assert_true(shown, "shown, since the layout showed Wrap")
