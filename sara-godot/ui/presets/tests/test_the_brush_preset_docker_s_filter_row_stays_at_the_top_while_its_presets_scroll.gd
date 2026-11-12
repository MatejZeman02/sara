## The brush preset docker's filter row stays at the top while its presets
## scroll.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The row holding the tag filter, the star, the Tip list and the
## sort is pinned when scrolling. The docker is built as the
## app builds it, in a screen of its own, over more presets than it shows. Its
## scroll is taken to the end, and the two rows above the grid have to stand
## where they stood before the scroll, outside it, and a press on the search
## field and on the Tip list has to reach each there.
extends "res://tests/test_framework.gd"

const ScratchFolder := preload("res://tests/fixtures/scratch_folder.gd")
const PresetsDockerScript = preload("res://ui/dockers/presets/brush_presets_docker.gd")
const BrushSettingsScript = preload("res://modules/sara-base-modules/stamp-brush/tools/brush_settings.gd")
const StateBrushScript = preload("res://modules/sara-base-modules/stamp-brush/tools/state_brush.gd")

## Thumbnails are drawn on the card.
const REQUIRES_GPU := true

const SCREEN := Vector2i(1280, 1024)
const AT := Vector2i(200, 100)
const OPENED := Vector2i(320, 360)

## Presets enough to fill the docker twice over.
const PRESETS: int = 40

static var scratch_dir: String = SaDataRoot.path("test_filter_row_pinned")

var _host: Node = null
var _kept_embedding: bool = true


func before_each() -> void:
    var root := (Engine.get_main_loop() as SceneTree).root
    _kept_embedding = root.gui_embed_subwindows
    root.gui_embed_subwindows = true
    ScratchFolder.clear(scratch_dir)
    _host = Node.new()
    _host.name = "FilterRowHost"
    EventBus.add_child(_host)


func after_each() -> void:
    if is_instance_valid(_host):
        _host.free()
        _host = null
    (Engine.get_main_loop() as SceneTree).root.gui_embed_subwindows = _kept_embedding
    ScratchFolder.clear(scratch_dir)


func _settle(frames: int = 6) -> void:
    var tree := Engine.get_main_loop() as SceneTree
    for i in frames:
        await tree.process_frame


func _docker() -> Window:
    var store := SaPresetStore.new()
    store.dir = scratch_dir
    for i in PRESETS:
        store.save_preset("Preset %02d" % (i + 1), BrushSettingsScript.new())
    var screen := SubViewport.new()
    screen.size = SCREEN
    screen.gui_embed_subwindows = true
    _host.add_child(screen)
    var docker: Window = PresetsDockerScript.new()
    docker.position = AT
    screen.add_child(docker)
    var chooser: SaBrushPresetsChooser = docker.get("chooser")
    chooser.in_shares = false
    chooser.bind_store(store, StateBrushScript, func() -> Resource: return BrushSettingsScript.new())
    docker.show()
    docker.size = OPENED
    return docker


func test_the_filter_row_stands_where_it_stood_with_the_presets_scrolled_to_their_end() -> void:
    var docker := _docker()
    await _settle()
    var chooser: SaBrushPresetsChooser = docker.get("chooser")
    var scroll := docker.find_child("Scroll", true, false) as ScrollContainer
    var bar := scroll.get_v_scroll_bar()
    assert_true(bar.max_value > bar.page, "the presets run %s past a page of %s" % [bar.max_value, bar.page])
    var filter_row := chooser.tag_option.get_parent() as Control
    var search_row := chooser.search_field.get_parent() as Control
    assert_false(scroll.is_ancestor_of(filter_row), "the filter row is outside the scroll")
    assert_false(scroll.is_ancestor_of(search_row), "and so is the search row with the size slider")
    assert_true(chooser.size_slider.get_parent() == search_row, "which still holds the size slider")
    var filter_before := filter_row.get_global_rect()
    var search_before := search_row.get_global_rect()
    var first_cell := chooser.grid.get_child(0) as Control
    var cell_before := first_cell.get_global_rect().position
    assert_true(filter_before.end.y <= scroll.get_global_rect().position.y, "the filter row stands above the scroll")

    bar.value = bar.max_value
    await _settle(2)
    assert_true(bar.value > 0.0, "the scroll went to its end, %s" % bar.value)
    assert_true(first_cell.get_global_rect().position.y < cell_before.y, "and the first preset moved up with it")
    assert_eq(filter_row.get_global_rect(), filter_before, "the filter row is where it was before the scroll")
    assert_eq(search_row.get_global_rect(), search_before, "and so is the search row")
    assert_true(filter_row.is_visible_in_tree(), "still shown")
    var end := bar.value

    var field := chooser.search_field
    assert_false(field.has_focus(), "the search field starts without the keyboard")
    _press(docker, field.get_global_rect().get_center())
    await _settle(2)
    assert_true(field.has_focus(), "a press on the search field at the end of the scroll reaches it")
    assert_eq(bar.value, end, "and leaves the scroll at its end")
    var downs: Array[int] = [0]
    chooser.thumb_option.button_down.connect(func() -> void: downs[0] += 1)
    _press(docker, chooser.thumb_option.get_global_rect().get_center())
    await _settle(2)
    assert_eq(downs[0], 1, "and a press on the filter row's Tip list reaches that")


## A press and release at *at* in the window's pixels, pushed into the screen
## the docker stands in as the main window's viewport hands it the pointer.
func _press(docker: Window, at: Vector2) -> void:
    for pressed: bool in [true, false]:
        var event := InputEventMouseButton.new()
        event.button_index = MOUSE_BUTTON_LEFT
        event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
        event.pressed = pressed
        event.position = at + Vector2(docker.position)
        event.global_position = event.position
        (docker.get_parent() as Viewport).push_input(event)
