## The Window menu's rows say what they open, in the order a
## painter meets them.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Every docker row's tooltip says more than its own name, the rows come in an
## order a painter meets rather than the order the dockers were built, the
## layouts read as names and not file names, Minimalistic says it sets the UI
## scale to nine tenths, and Tab's focus mode has a row. The bar is
## built detached, the way `test_dockers_under_window.gd` builds it, because a
## `Window` in the tree hangs a suite, and the scenario of the same name shoots
## the assembled menu in the app.
extends "res://tests/test_framework.gd"

## The built-ins in the order the Window menu lists them: the six the default
## layout opens, as its file lists them, then the rest as they register. Brush
## Presets and the Minimap are among the leaders, because a fresh profile opens them.
const ORDER := [
    "Toolbox",
    "Tool Options",
    "Colour Picker",
    "Layers",
    "Brush Presets",
    "Minimap",
    "Info",
    "Recorder",
    "Graph",
    "Recent Presets",
    "Undo History",
    "Reference",
    "Pop-up Palette",
    # Exposure and Stats are in the base modules, so their rows come after
    # these with every module's. The Sphere is there too, and the filter
    # browser is a docker, registered last.
    "Filters",
]

## The scratch folder a painter's own layouts are written into, and removed.
static var scratch_dir: String = SaDataRoot.path("test_n47_window_menu")


## The layout store with every answer that writes or forks stubbed, and the
## layouts it lists handed in, so a case says which names the menu is given.
class StubStore:
    extends DockerLayoutStore

    var listed: Array[String] = []

    func _init(names: Array[String] = []) -> void:
        listed = names

    func save(_by_painter: bool = false) -> void:
        pass

    func fork_for_painter_edit() -> String:
        return ""

    func reapply_deferred(_win: Window, _section: String) -> void:
        pass

    func list_presets() -> Array[String]:
        return listed

    func current_preset() -> String:
        return ""


func before_each() -> void:
    SaFocusMode.active = false


func after_each() -> void:
    SaFocusMode.active = false
    var layouts := scratch_dir.path_join("layouts")
    if not DirAccess.dir_exists_absolute(layouts):
        return
    for file_name in DirAccess.get_files_at(layouts):
        DirAccess.remove_absolute(layouts.path_join(file_name))
    DirAccess.remove_absolute(layouts)
    DirAccess.remove_absolute(scratch_dir)


func _bar() -> TopMenuBar:
    var bar := TopMenuBar.new()
    bar._ready()
    bar.bind_commands(SaTestFixtures.make_menu_registries().commands)
    return bar


## The skeleton's own dockers, registered through the door and built detached,
## under a node that frees every window with it.
func _built_ins(store: DockerLayoutStore = null) -> MainDockers:
    var dockers := MainDockers.new(SaUIRegistry.new(), store if store != null else StubStore.new())
    dockers.register_builtin_dockers()
    return dockers


## Two stand-in dockers, open, the way `test_dockers_under_window.gd` makes them.
func _two_open(host: Node) -> MainDockers:
    var registry := SaUIRegistry.new()
    for entry: Array in [["StubA", "Stub A", "Holds the first stand-in."], ["StubB", "Stub B", ""]]:
        var id := StringName(entry[0])
        var win := Window.new()
        win.name = String(id)
        host.add_child(win)
        registry.register_docker(id, String(entry[1]), func() -> Window: return Window.new(), &"docker_stub", &"", entry[2])
        registry.set_docker_node(id, win)
    var dockers := MainDockers.new(registry, StubStore.new())
    host.add_child(dockers)
    return dockers


## The docker rows' labels, which follow the three window rows the bar's own
## populate drew and the Focus Mode row.
func _docker_labels(popup: SaChoicePopup, count: int) -> Array[String]:
    return popup.row_labels().slice(4, 4 + count)


func test_the_built_ins_come_in_the_order_the_default_layout_opens_them() -> void:
    var bar := _bar()
    var popup: SaChoicePopup = bar.menus["Window"]
    var dockers := _built_ins()
    dockers.append_menu_rows(popup)

    assert_eq(_docker_labels(popup, ORDER.size()), ORDER, "The six the default layout opens lead, then the rest")
    # The rows moved and their keys did not: a row is keyed by its docker's
    # place in the registry, which the layout store's tick and a scenario's
    # `menu_item` both press it by.
    var keys := popup.row_ids().slice(4, 7)
    assert_eq(keys, [&"docker_0", &"docker_6", &"docker_2"], "Toolbox, Tool Options and the Colour Picker keep their keys")

    assert_eq(popup.label_button(&"docker_11").text, "Brush Presets", "and the key a press finds names the docker the row says")

    dockers.free()
    bar.free()


## A docker a module registers, which the default layout knows nothing of,
## comes after every built-in rather than among them.
func test_a_docker_the_default_layout_does_not_open_comes_after() -> void:
    var order := MainDockers.menu_order(
        [{"id": "MirrorsDocker"}, {"id": String(SaDockerIds.LAYERS)}, {"id": String(SaDockerIds.TOOLBOX)}]
    )
    assert_eq(order, [2, 1, 0], "Toolbox, then Layers, then the module's own")


func test_every_built_in_row_says_what_its_docker_holds() -> void:
    var bar := _bar()
    var popup: SaChoicePopup = bar.menus["Window"]
    var dockers := _built_ins()
    dockers.append_menu_rows(popup)

    var configs := dockers.get_docker_config()
    assert_eq(configs.size(), ORDER.size(), "Every built-in has a row")
    for i in configs.size():
        var button := popup.label_button(StringName("docker_%d" % i))
        var said := button.tooltip_text if button != null else ""
        assert_false(said.is_empty(), "%s's row says something on hover" % configs[i]["name"])
        assert_true(said != (button.text if button != null else ""), "and not its own name again")
        assert_eq(said, SaBuiltinDockers.SENTENCES[StringName(configs[i]["id"])], "and what it says is its sentence")

    dockers.free()
    bar.free()


## A module's docker fills the same argument through its own door, and one that
## leaves it out has a row that says nothing on hover.
func test_a_modules_sentence_is_its_rows_tooltip_and_none_says_nothing() -> void:
    var registries := SaRegistries.new()
    registries.build_context(func() -> Variant: return null, func() -> Array: return [])
    var ctx := registries.context.for_module(&"n47-probe")
    ctx.register_docker(&"MirrorsDocker", "Mirrors", func() -> Window: return Window.new(), &"", "Draws the canvas mirrored.")
    assert_eq(
        registries.ui.get_docker_entry(&"MirrorsDocker").get("sentence"), "Draws the canvas mirrored.", "The door carries it"
    )

    var bar := _bar()
    var popup: SaChoicePopup = bar.menus["Window"]
    var host := Node.new()
    _two_open(host).append_menu_rows(popup)
    assert_eq(popup.label_button(&"docker_0").tooltip_text, "Holds the first stand-in.", "A sentence is the row's tooltip")
    assert_eq(popup.label_button(&"docker_1").tooltip_text, "", "and a docker with none says nothing rather than its name")

    host.free()
    bar.free()


func test_focus_mode_has_a_row_with_tabs_chord_that_hides_the_dockers() -> void:
    var bar := _bar()
    var popup: SaChoicePopup = bar.menus["Window"]
    var host := Node.new()
    var dockers := _two_open(host)
    dockers.dockers_menu = popup
    dockers.append_menu_rows(popup)

    var row := MainFocusTab.ROW
    assert_eq(popup.row_labels().slice(3, 6), ["Focus Mode", "Stub A", "Stub B"], "Focus Mode leads the dockers it hides")
    assert_eq(popup.row_of(row).hint_text(), "Tab", "with the key that does it at its right")
    assert_false(popup.label_button(row).tooltip_text.is_empty(), "and a sentence on hover")
    assert_false(popup.is_checked(row), "It is off while the dockers are open")

    var a: Window = dockers.registered_docker_node(&"StubA")
    var b: Window = dockers.registered_docker_node(&"StubB")
    assert_true(popup.press_row(row), "The row is there to press")
    assert_true(SaFocusMode.active, "and pressing it enters focus mode")
    assert_false(a.visible or b.visible, "with both dockers hidden")
    assert_true(popup.is_checked(row), "and its tick says so")
    assert_true(popup.press_row(row), "A second press")
    assert_false(SaFocusMode.active, "leaves it")
    assert_true(a.visible and b.visible, "and both dockers are back")
    assert_false(popup.is_checked(row), "and the tick is off again")

    host.free()
    bar.free()


func test_the_layouts_sara_ships_read_in_title_case_and_a_painters_as_written() -> void:
    var presets := SaDockerLayoutPresets.new(scratch_dir.path_join("docker_layout.cfg"))
    for shipped: String in SaDockerLayoutPresets.SHIPPED:
        assert_eq(presets.title(shipped), shipped.capitalize(), "%s reads in title case" % shipped)
    assert_eq(presets.title("minimalistic"), "Minimalistic", "Minimalistic among them")
    assert_eq(presets.title("default (custom)"), "Default (Custom)", "and so does a fork of one")
    assert_eq(presets.title("iPad sketch"), "iPad sketch", "A painter's own name reads as they wrote it")
    assert_eq(presets.title("layout-fixture/desk"), "layout-fixture/desk", "and so does a module's")


## Minimalistic's rows read 0.9 of the scale, which nothing said until it was
## loaded. A painter's own layout at another scale says so too, and one at 1
## says nothing. No shipped layout carries a scale, so
## Minimalistic keeps the painter's and says nothing either.
func test_a_layout_whose_scale_is_not_one_says_it_on_hover() -> void:
    DirAccess.make_dir_recursive_absolute(scratch_dir.path_join("layouts"))
    for entry: Array in [["big", 1.5], ["plain", 1.0]]:
        var cfg := ConfigFile.new()
        cfg.set_value(SaDockerLayoutPresets.UI_SECTION, "ui_scale", entry[1])
        cfg.save(scratch_dir.path_join("layouts").path_join(String(entry[0]) + ".cfg"))
    var store := StubStore.new(["default", "minimalistic", "big", "plain"] as Array[String])
    store.path = scratch_dir.path_join("docker_layout.cfg")

    var bar := _bar()
    var popup: SaChoicePopup = bar.menus["Window"]
    var dockers := MainDockers.new(SaUIRegistry.new(), store)
    dockers.append_menu_rows(popup)

    assert_true(popup.section_titles().has("Layouts"), "The layouts keep their heading")
    assert_eq(popup.row_labels().slice(4), ["Default", "Minimalistic", "big", "plain"], "listed under the names they read as")
    var says := func(index: int) -> String: return popup.label_button(StringName("layout_%d" % index)).tooltip_text
    assert_eq(says.call(0), "", "Default is at 1 and says nothing on hover")
    assert_eq(says.call(1), "", "Minimalistic sets no scale and says nothing")
    assert_eq(says.call(2), "Places its dockers and sets the UI scale to 150%.", "and so does a painter's own")
    assert_eq(says.call(3), "", "and one at 1 says nothing")

    dockers.free()
    bar.free()


## A layout's scale is kept between opens rather than parsing every file
## before every open, and a file that changed on disk since is read again: here
## it is gone, and the next open's hover says nothing of the scale it had.
func test_a_layout_file_changed_since_the_last_open_is_read_again() -> void:
    DirAccess.make_dir_recursive_absolute(scratch_dir.path_join("layouts"))
    var file := scratch_dir.path_join("layouts").path_join("big.cfg")
    var cfg := ConfigFile.new()
    cfg.set_value(SaDockerLayoutPresets.UI_SECTION, "ui_scale", 1.5)
    cfg.save(file)
    var store := StubStore.new(["big"] as Array[String])
    store.path = scratch_dir.path_join("docker_layout.cfg")
    var rows := MainLayoutRows.new(store)

    var bar := _bar()
    var popup: SaChoicePopup = bar.menus["Window"]
    var big := "Places its dockers and sets the UI scale to 150%."
    rows.add_to(popup)
    assert_eq(popup.label_button(&"layout_0").tooltip_text, big, "The first open reads the file")
    popup.clear()
    rows.add_to(popup)
    assert_eq(popup.label_button(&"layout_0").tooltip_text, big, "and the next keeps it")

    DirAccess.remove_absolute(file)
    popup.clear()
    rows.add_to(popup)
    assert_eq(popup.label_button(&"layout_0").tooltip_text, "", "A file gone since is read again, and names no scale")

    bar.free()
    store.free()
