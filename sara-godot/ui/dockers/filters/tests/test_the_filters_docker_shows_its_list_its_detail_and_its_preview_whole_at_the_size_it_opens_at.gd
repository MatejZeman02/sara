## The Filters docker shows its list, its detail and its
## preview whole at the size it opens at.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The floating docker should look like the window it replaced, with a sidebar
## of filters. In one picture the list showed
## one and a half rows, the preview was cut to a strip and the empty
## Parameters part took half the docker. Held here: at the size a summon opens
## it at, the list is a sidebar left of the detail and taller than the detail's
## sentence, the sentence, the preview and the parameters are whole, the column
## fits the docker, and no two parts of the browser overlap. In the 160 strip
## the shipped layouts keep it in, the list stands over the detail, five rows
## tall at least, nothing overlaps either, and the docker's scroll takes the
## column taller than the docker. A summon widens the docker without a word to
## the layout file, and the borrow's end puts it back in the strip. The Window
## menu's row summons it so, locked, and its second press sends it back, the
## answer of 2026-10-09 to the question the strip asked.
##
## Built the way `test_a_question_opens_at_its_texts_height.gd` builds its
## question: a `SubViewport` of a capture's size with subwindows embedded, and
## every container sorted by hand, because a suite cannot await the frame the
## app lays out on. The running app is
## `scenarios/the-filters-docker-shows-its-list-its-detail-and-its-preview-whole-at-the-size-it-opens-at.json`.
extends "res://tests/test_framework.gd"

const OWNER := &"suite"

## The capture's window, which the shipped layouts are fitted to.
const SCREEN := Vector2i(1920, 1048)

## Where a summon is asked for, low on the canvas, so the docker opening wide
## about it has to move up to stop above the status line.
const POINT := Vector2i(960, 900)

const SECTION := "FiltersDocker"

static var scratch_layout_path: String = SaDataRoot.path("test_filters_layout.cfg")


## The layout store with the fork a painter's edit makes stubbed, as the Filters docker's own suite
## stubs it, so closing the docker writes the scratch file and no preset.
class NoForkStore:
    extends DockerLayoutStore

    func fork_for_painter_edit() -> String:
        return ""

    func list_presets() -> Array[String]:
        return []

    func current_preset() -> String:
        return ""


var _kept_scale: float = 1.0
var _kept_embedding: bool = true
var _host: Node = null
var _docker: FiltersDocker = null
var _blur := StringName()


func before_each() -> void:
    _kept_scale = SaUI.user_scale
    SaUI.user_scale = 1.0
    var tree := Engine.get_main_loop() as SceneTree
    _kept_embedding = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    _host = Node.new()
    _host.name = "U21FiltersHost"
    EventBus.add_child(_host)
    var screen := SubViewport.new()
    screen.size = SCREEN
    screen.gui_embed_subwindows = true
    _host.add_child(screen)

    var filters := SaFilterRegistry.new()
    for filter: SaFilter in [SaGaussianBlurFilter.new(), SaWrapOffsetFilter.new(), SaLevelsFilter.new()]:
        filters.register(filter, OWNER)
    _blur = SaFilterRegistry.key_for(OWNER, SaGaussianBlurFilter.new())
    _docker = FiltersDocker.new()
    _docker.browser.watch(filters, SaCommandRegistry.new())
    screen.add_child(_docker)
    _docker.show()


func after_each() -> void:
    SaUI.user_scale = _kept_scale
    (Engine.get_main_loop() as SceneTree).root.gui_embed_subwindows = _kept_embedding
    if _host != null and is_instance_valid(_host):
        _host.free()
    _host = null
    _docker = null
    if FileAccess.file_exists(scratch_layout_path):
        DirAccess.remove_absolute(ProjectSettings.globalize_path(scratch_layout_path))


func test_at_the_opening_size_the_list_is_a_sidebar_beside_the_whole_detail() -> void:
    assert_true(_docker.browser.pick(_blur), "The blur is picked")
    _sized(SaUI.window_size_for(_docker, FiltersDocker.OPEN_SIZE))
    assert_true(_docker.browser.side_by_side, "At %s the list stands beside the detail" % _docker.size)
    var parts := _parts()
    var list: Rect2 = parts["BrowserList"]
    var detail: Rect2 = parts["BrowserDetail"]
    var sentence: Rect2 = parts["BrowserSentence"]
    assert_true(list.end.x <= detail.position.x, "The list %s is left of the detail %s" % [list, detail])
    assert_true(list.size.y > sentence.size.y, "and taller than the sentence %s" % sentence)
    assert_true(list.size.y >= detail.size.y, "as tall as the detail column beside it, %s" % list)

    var browser := _docker.browser
    var asked: Dictionary = browser.describe_layout()["minimums"]
    for part: String in ["BrowserSentence", "BrowserPreview"]:
        var rect: Rect2 = parts[part]
        var wants: float = asked[part][1]
        assert_true(rect.size.y >= wants - 0.5, "%s is whole, %d tall for the %d it asks" % [part, rect.size.y, wants])
    var parameters := _docker.parameters
    var needs := parameters.get_combined_minimum_size().y
    var takes := parameters.size.y
    assert_true(takes <= needs + 0.5, "The Parameters part takes the %d its sentence needs, %d" % [needs, takes])
    var reserved := int(_docker.resizer.custom_minimum_size.y) if _docker.resizer != null else 0
    var column := DockerWindow.column_content_height(_docker) + reserved
    assert_true(column <= _docker.size.y, "and the whole column, %d, fits the docker's %d" % [column, _docker.size.y])
    _assert_apart(parts)


## The sidebar's column never asks for more than the width it starts at, so a
## docker at that width is not held wider by the layout it chose, and the two
## layouts cannot hand the docker back and forth.
func test_the_sidebar_fits_the_width_it_starts_at() -> void:
    _sized(SaUI.window_size_for(_docker, Vector2i(FiltersDocker.SIDEBAR_FROM, FiltersDocker.OPEN_SIZE.y)))
    assert_true(_docker.browser.side_by_side, "At %d the list stands beside the detail" % FiltersDocker.SIDEBAR_FROM)
    var wants := DockerWindow.column_min_width(_docker)
    assert_true(wants <= _docker.size.x, "and the column asks %d of the %d" % [wants, _docker.size.x])
    _sized(SaUI.window_size_for(_docker, Vector2i(FiltersDocker.SIDEBAR_FROM - 1, FiltersDocker.OPEN_SIZE.y)))
    assert_false(_docker.browser.side_by_side, "A unit narrower, the list stands over the detail")


func test_in_the_strip_the_list_stands_over_the_detail_and_the_docker_scrolls() -> void:
    assert_true(_docker.browser.pick(_blur), "The blur is picked")
    _sized(SaUI.window_size_for(_docker, FiltersDocker.DEFAULT_SIZE))
    assert_false(_docker.browser.side_by_side, "In the strip of %s the list stands over the detail" % _docker.size)
    var parts := _parts()
    var list: Rect2 = parts["BrowserList"]
    var detail: Rect2 = parts["BrowserDetail"]
    assert_true(list.end.y <= detail.position.y, "The list %s is over the detail %s" % [list, detail])
    assert_true(list.size.y >= SaUI.px(SaFilterBrowser.STACKED_FLOOR), "five rows tall at least, %d" % list.size.y)
    _assert_apart(parts)
    var browser := _docker.browser
    var wants := browser.get_combined_minimum_size().y
    assert_true(browser.size.y >= wants - 0.5, "The browser has the %d it asks, %d" % [wants, browser.size.y])
    assert_true(
        DockerWindow.column_content_height(_docker) > _docker.size.y,
        "and the docker's scroll takes a column taller than the docker's %d" % _docker.size.y
    )


## The summon's widening is the borrow's, so the layout file is the same byte
## for byte, and the docker goes back to the strip at the end of it.
func test_a_summon_opens_it_wide_and_its_end_puts_it_back_in_the_strip() -> void:
    _docker.hide()
    _sized(SaUI.window_size_for(_docker, FiltersDocker.DEFAULT_SIZE))
    var strip := _docker.size
    var store := DockerLayoutStore.new()
    store.path = scratch_layout_path
    var config := {"node": _docker, "id": SECTION, "name": SECTION}
    store.dockers_provider = func() -> Array: return [config]
    store.save(true)
    var on_disk := FileAccess.get_file_as_bytes(scratch_layout_path)
    var summon := DockerSummon.new(store)

    assert_true(summon.summon(_docker, SECTION, POINT, 5000, true), "The summon puts the docker out")
    _docker.open_wide(store)
    var wide := SaUI.window_size_for(_docker, FiltersDocker.OPEN_SIZE)
    assert_true(_docker.size.x >= wide.x and _docker.size.y >= wide.y, "at %s, the %s it opens at" % [_docker.size, wide])
    assert_true(Rect2i(_docker.position, _docker.size).has_point(POINT), "about the point it was summoned at")
    var line := SaDockerLayoutRefit.status_rows_in(SaUI.window_scale(_docker))
    var foot := _docker.position.y + _docker.size.y
    assert_true(foot <= SCREEN.y - line, "its foot at %d above the status line's %d rows" % [foot, line])
    assert_true(_docker.browser.side_by_side, "with the list a sidebar")
    assert_eq(FileAccess.get_file_as_bytes(scratch_layout_path), on_disk, "The layout file is what it was")

    summon.send_back(SECTION)
    assert_eq(_docker.size, strip, "Sent back, the docker is the strip again")
    assert_false(_docker.browser.side_by_side, "with the list over the detail")
    assert_false(_docker.visible, "and shut, as it was")
    assert_eq(FileAccess.get_file_as_bytes(scratch_layout_path), on_disk, "and the file is still what it was")
    summon.free()
    store.free()


## The Window menu's row on a shut docker summons it locked and wide about the
## middle of its strip, in front, writing nothing, and the row pressed again
## sends it back to the strip, shut, which is what the layout file says of it
## then.
func test_the_window_menus_row_opens_it_wide_and_pressed_again_puts_it_back() -> void:
    _docker.hide()
    _sized(SaUI.window_size_for(_docker, FiltersDocker.DEFAULT_SIZE))
    _docker.position = SaUI.window_size_for(_docker, FiltersDocker.DEFAULT_POSITION)
    var strip := Rect2i(_docker.position, _docker.size)
    var registries := SaRegistries.new()
    registries.ui.register_docker(SaDockerIds.FILTERS, "Filters", func() -> Window: return Window.new(), &"")
    registries.ui.set_docker_node(SaDockerIds.FILTERS, _docker)
    var store := NoForkStore.new()
    store.path = scratch_layout_path
    var dockers := MainDockers.new(registries.ui, store)
    _docker.get_parent().add_child(dockers)
    # The Window menu's own call, which connects the docker's close as the app's
    # does before any row of it can be pressed.
    var menu := SaChoicePopup.new()
    dockers.append_menu_rows(menu)
    store.save(true)
    var on_disk := FileAccess.get_file_as_bytes(scratch_layout_path)

    dockers.toggle_docker(0)
    var wide := SaUI.window_size_for(_docker, FiltersDocker.OPEN_SIZE)
    assert_true(_docker.visible, "The row shows the docker")
    assert_true(store.is_borrowed(SECTION), "on a summon")
    assert_true(SaDockerLock.is_locked(_docker), "locked, so it stays while the pointer is elsewhere")
    assert_true(_docker.has_focus(), "in front with the keyboard, as a docker the row shows is")
    assert_true(_docker.size.x >= wide.x and _docker.size.y >= wide.y, "at %s, the %s it opens at" % [_docker.size, wide])
    assert_true(Rect2i(_docker.position, _docker.size).has_point(strip.get_center()), "about the middle of its strip")
    assert_true(_docker.browser.side_by_side, "with the list a sidebar")
    var foot := _docker.position.y + _docker.size.y
    var line := SaDockerLayoutRefit.status_rows_in(SaUI.window_scale(_docker))
    assert_true(foot <= SCREEN.y - line, "its foot at %d above the status line's %d rows" % [foot, line])
    assert_eq(FileAccess.get_file_as_bytes(scratch_layout_path), on_disk, "The layout file is what it was")

    dockers.toggle_docker(0)
    assert_false(_docker.visible, "Pressed again, the row shuts the docker")
    assert_false(store.is_borrowed(SECTION), "and ends the summon")
    assert_eq(Rect2i(_docker.position, _docker.size), strip, "back in its strip")
    assert_false(_docker.browser.side_by_side, "with the list over the detail")
    assert_eq(store.value_for(SECTION, "size", Vector2i()), strip.size, "and the layout says the strip still")
    menu.free()


## Gives the docker *size* and lays every container out by hand, three times
## over, since a wrapped label asks its height only once it has its width, and
## the minimum a container keeps is asked again first.
func _sized(size: Vector2i) -> void:
    _docker.size = size
    for _pass in 3:
        _sort_children(_docker)


func _sort_children(node: Node) -> void:
    for child: Node in node.get_children():
        if child is Control:
            (child as Control).update_minimum_size()
        if child is Container:
            (child as Container).notification(Container.NOTIFICATION_SORT_CHILDREN)
        _sort_children(child)


## The browser's parts by name, and the docker's parameters and looks beside
## them, as rectangles.
func _parts() -> Dictionary:
    var out: Dictionary = {}
    var listed: Dictionary = _docker.browser.describe_layout()["parts"]
    for part: String in listed:
        var rect: Array = listed[part]
        out[part] = Rect2(rect[0], rect[1], rect[2], rect[3])
    out["FilterParameters"] = _docker.parameters.get_global_rect()
    out["FilterLooks"] = _docker.looks.get_global_rect()
    return out


## No two parts overlap. The detail column holds the words, the picture, the
## buttons and the docker's two parts, so it is read against the list alone.
func _assert_apart(parts: Dictionary) -> void:
    var names: Array = parts.keys()
    names.erase("BrowserDetail")
    for i in names.size():
        for j in range(i + 1, names.size()):
            var a: Rect2 = parts[names[i]]
            var b: Rect2 = parts[names[j]]
            assert_false(a.intersects(b), "%s %s and %s %s overlap" % [names[i], a, names[j], b])
    assert_false(
        (parts["BrowserList"] as Rect2).intersects(parts["BrowserDetail"]),
        "The list %s and the detail %s overlap" % [parts["BrowserList"], parts["BrowserDetail"]]
    )
