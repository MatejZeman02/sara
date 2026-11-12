## The View, Layer and Window menus open shorter than a 1080 pixel screen at UI
## scale 1, with no scroll bar, their rows of one kind under a submenu each, and
## every row they held as one list still reachable under its id with its chord.
##
## The three once ran longer than a laptop's screen, so they
## scrolled and their rows were hard to find. The bar is built detached, the way
## `test_a_menu_opens_at_its_full_height.gd` builds it, because a popup is a
## `Window`, and the scenario of the same name shoots each menu open in the app.
extends "res://tests/test_framework.gd"

## Needs a RenderingDevice, for the document the Layer rows are drawn for.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")

## A 1080 pixel screen, under a title about thirty pixels tall, as the Tools menu
## suite measures it.
const ROOM := Rect2i(0, 0, 1920, 1080)
const TITLE := Rect2(335.0, 0.0, 40.0, 30.0)

## The View menu's rows that ran a command, by the id each had as one list.
const VIEW_COMMANDS := {
    3: &"view_second_row",
    10: &"view_zoom_in",
    11: &"view_zoom_out",
    12: &"view_zoom_100",
    73: &"view_actual_pixels",
    13: &"view_fit",
    71: &"view_fit_window",
    14: &"view_center",
    75: &"view_isolate_active_layer",
    15: &"view_rotate_left",
    16: &"view_rotate_right",
    17: &"view_rotate_reset",
    18: &"view_mirror_horizontal",
    19: &"view_mirror_vertical",
    70: &"view_grid",
}

## Stand-ins for a module's dockers, so the Window menu is measured holding more
## than the built-ins, as it does in the app.
const MODULE_DOCKERS := 6


## The layout store with every answer that writes or forks stubbed.
class StubStore:
    extends DockerLayoutStore

    func save(_by_painter: bool = false) -> void:
        pass

    func fork_for_painter_edit() -> String:
        return ""

    func reapply_deferred(_win: Window, _section: String) -> void:
        pass

    func list_presets() -> Array[String]:
        return ["Default", "Minimalistic", "Useful", "Full", "Krita", "Photoshop", "Procreate", "Clip Studio"]

    func current_preset() -> String:
        return "Default"


var _bar: TopMenuBar = null
var _registries: SaRegistries = null
var _canvas: SaCanvas = null
var _dockers: MainDockers = null
var _host: Node = null


func before_each() -> void:
    _registries = Fixtures.make_menu_registries()
    _canvas = SaCanvas.new()
    _canvas.canvas_size = Vector2i(256, 256)
    _canvas.easel = SaEasel.create_default(_canvas.canvas_size)
    _canvas.add_child(_canvas.easel)
    _bar = TopMenuBar.new()
    _bar._ready()
    _bar.bind_commands(_registries.commands)
    var view := _bar.menu("View") as SaViewMenu
    view.view_transforms = _registries.view_transforms
    var layer := _bar.menu("Layer") as SaLayerMenu
    layer.document = _canvas.document
    layer.layer_types = _registries.layer_types
    layer.populate()
    _host = Node.new()
    _dockers = MainDockers.new(SaUIRegistry.new(), StubStore.new())
    _host.add_child(_dockers)
    _dockers.bind_bar(_bar)
    _dockers.register_builtin_dockers()
    for i in MODULE_DOCKERS:
        var id := StringName("ModuleStub%d" % i)
        var win := Window.new()
        win.name = String(id)
        _host.add_child(win)
        _dockers.ui.register_docker(id, "Module Stub %d" % i, func() -> Window: return Window.new(), &"", &"stub")
        _dockers.ui.set_docker_node(id, win)
    var window := _bar.menu("Window")
    window.populate()
    window.add_separator()
    _dockers.append_grouped_rows(window)


func after_each() -> void:
    _bar.free()
    _host.free()
    _canvas.free()
    _registries = null


## The height *list* opens at under its title on a 1080 screen, failing the
## case when the room would cut it and give it a scroll bar.
func _opens_whole(menu_name: String, list: SaChoicePopup) -> int:
    var wanted := list.wanted_size(60.0)
    var rect := SaPopupRect.under(TITLE, wanted, ROOM)
    assert_eq(rect.size.y, wanted.y, "%s opens at its whole height, %d, with no scroll bar" % [menu_name, wanted.y])
    assert_true(wanted.y < 1080, "%s is shorter than a 1080 screen: %d" % [menu_name, wanted.y])
    return wanted.y


## Every submenu row of *menu*, with its list.
func _groups(menu: SaMenu) -> Dictionary:
    var out := {}
    for row_id: StringName in menu.popup.row_ids():
        var list := SaMenu.group_list(menu.popup, SaMenu.id_of(row_id))
        if list != null:
            out[menu.popup.label_button(row_id).text] = list
    return out


## *menu* and each of its submenus open whole, and it has submenus at all.
func _fits(menu_name: String) -> Dictionary:
    var menu := _bar.menu(menu_name)
    _opens_whole(menu_name, menu.popup)
    var groups := _groups(menu)
    assert_true(groups.size() >= 2, "%s groups its rows into submenus: %s" % [menu_name, groups.keys()])
    for words: String in groups:
        _opens_whole("%s > %s" % [menu_name, words], groups[words])
        assert_true(menu.popup.is_branch(SaMenu.key(_id_of_group(menu, words))), "%s opens its list beside it" % words)
    return groups


func _id_of_group(menu: SaMenu, words: String) -> int:
    for row_id: StringName in menu.popup.row_ids():
        if menu.popup.label_button(row_id).text == words:
            return SaMenu.id_of(row_id)
    return -1


## The hint *menu*'s row *item_id* shows, wherever it is.
func _hint(menu: SaMenu, item_id: int) -> String:
    var list := SaMenu.list_holding(menu.popup, SaMenu.key(item_id))
    return list.row_of(SaMenu.key(item_id)).hint_text() if list != null else "<no row>"


func test_the_view_menu_fits_a_screen_and_every_command_keeps_its_row_and_chord() -> void:
    var groups := _fits("View")
    for words: String in ["Zoom", "Rotate and Flip", "View Mode", "Display"]:
        assert_true(groups.has(words), "View has %s: %s" % [words, groups.keys()])
    var menu := _bar.menu("View")
    for item_id: int in VIEW_COMMANDS:
        assert_true(menu.has_item(item_id), "View still holds row %d" % item_id)
        assert_eq(menu.command_at(item_id), VIEW_COMMANDS[item_id], "row %d runs the command it ran" % item_id)
        assert_eq(_hint(menu, item_id), menu.chord_of(VIEW_COMMANDS[item_id]), "row %d shows its chord" % item_id)
    assert_eq(_hint(menu, SaViewMenu.ID_ZOOM_IN), "Ctrl+=", "Zoom In, under Zoom, still reads its key")
    for item_id: int in [
        SaViewMenu.ID_WINDOW_CONTROLS, SaViewMenu.ID_TOOL_OPTIONS, SaViewMenu.ID_STATUS_LINE, SaViewMenu.ID_TONEMAP
    ]:
        assert_true(menu.has_item(item_id), "View still holds row %d" % item_id)
    for transform: SaViewTransformDescriptor in _registries.view_transforms.list_modes():
        assert_true(menu.has_item(menu._transform_ids.find_key(transform.id)), "the mode %s has its row" % transform.id)


func test_the_layer_menu_fits_a_screen_and_every_row_keeps_its_number_and_chord() -> void:
    var groups := _fits("Layer")
    for words: String in ["New Layer via", "Arrange", "Mask", "Convert", "Lock", "Flip", "Smart Layer"]:
        assert_true(groups.has(words), "Layer has %s: %s" % [words, groups.keys()])
    var menu := _bar.menu("Layer") as SaLayerMenu
    var rows := SaLayerMenuRows.new(menu.document, _registries.commands, _registries.layer_types)
    var count := 0
    for row: Variant in rows.rows(false):
        if row is SaLayerMenuRows.Row:
            count += 1
            assert_true(menu.has_item(row.number), "Layer still holds %s" % row.words)
            assert_eq(
                _hint(menu, row.number),
                row.chord if not row.branch else _hint(menu, row.number),
                "%s keeps its chord" % row.words
            )
    assert_true(count > 30, "the list's rows are all counted: %d" % count)
    for item_id: int in [
        SaLayerMenu.ID_FLIP_HORIZONTAL, SaLayerMenu.ID_MAKE_SMART, SaLayerMenu.ID_LINK_FILE, SaLayerMenu.ID_CLEAR_OVERRIDE
    ]:
        assert_true(menu.has_item(item_id), "Layer still holds row %d" % item_id)
    assert_eq(_hint(menu, 400), "Ctrl+Shift+N", "New Layer stays on the menu with its key")
    assert_eq(_hint(menu, 412), "Ctrl+Shift+M", "Add Mask, under Mask, still reads its key")


func test_the_window_menu_fits_a_screen_with_the_dockers_by_kind() -> void:
    var groups := _fits("Window")
    for words: String in ["Painting", "Colour", "Picture", "Other"]:
        assert_true(groups.has(words), "Window has %s: %s" % [words, groups.keys()])
    var menu := _bar.menu("Window")
    var config := _dockers.get_docker_config()
    assert_eq(config.size(), SaDockerIds.ALL.size() + MODULE_DOCKERS, "every docker registered")
    for i in config.size():
        var row := StringName("docker_%d" % i)
        var list := SaMenu.list_holding(menu.popup, row)
        assert_true(list != null and list != menu.popup, "%s is under a kind" % config[i]["name"])
        if list != null:
            var chord := SaMenu.action_chord(StringName(config[i]["shortcut"]))
            assert_eq(list.row_of(row).hint_text(), chord, "%s keeps its chord" % config[i]["name"])
    var module_row := SaMenu.list_holding(menu.popup, StringName("docker_%d" % (config.size() - 1)))
    assert_eq(module_row, groups["Other"], "a module's docker is under Other")
    for item_id: int in [SaWindowMenu.ID_FULLSCREEN, SaWindowMenu.ID_NEW_SECONDARY, SaWindowMenu.ID_GATHER_DOCKERS]:
        assert_true(menu.popup.row_ids().has(SaMenu.key(item_id)), "row %d stays on the menu" % item_id)


func test_a_ticked_row_under_a_submenu_reads_and_writes_its_tick() -> void:
    var menu := _bar.menu("View")
    menu.set_item_checked(SaViewMenu.ID_WINDOW_CONTROLS, false)
    assert_false(menu.is_item_checked(SaViewMenu.ID_WINDOW_CONTROLS), "the tick under Bars goes off")
    menu.set_item_checked(SaViewMenu.ID_WINDOW_CONTROLS, true)
    assert_true(menu.is_item_checked(SaViewMenu.ID_WINDOW_CONTROLS), "and on again")
    var dockers := _bar.menu("Window").popup
    var row := StringName("docker_0")
    var list := SaMenu.list_holding(dockers, row)
    var was := list.is_checked(row)
    assert_true(list.press_row(row), "a docker row under its kind takes a press")
    assert_true(list.is_checked(row) != was, "and its tick follows the docker")
    assert_true(_dockers.get_docker_config()[0]["node"].visible != was, "which the press toggled")


func test_a_press_on_a_group_row_runs_nothing_and_its_rows_wait_in_the_list() -> void:
    var menu := _bar.menu("Layer")
    var mask := SaMenu.group_list(menu.popup, SaLayerMenu.ID_MASK_GROUP)
    assert_true(mask != null and mask.row_ids().has(SaMenu.key(412)), "Mask holds Add Mask")
    assert_false(menu.popup.row_ids().has(SaMenu.key(412)), "and the menu's own list does not")
    var before := _canvas.document.active_layer
    var steps := _canvas.document.undo_redo.get_history_count()
    menu.on_id_pressed(SaLayerMenu.ID_MASK_GROUP)
    assert_eq(_canvas.document.active_layer, before, "a press on the group's row runs no command")
    assert_eq(_canvas.document.undo_redo.get_history_count(), steps, "and writes no history step")
    assert_eq(menu.command_at(412), &"layer_mask_add", "and the row under it still runs Add Mask")
