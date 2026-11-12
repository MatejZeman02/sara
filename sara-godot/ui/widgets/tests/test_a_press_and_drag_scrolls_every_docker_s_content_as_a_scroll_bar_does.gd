## A press and drag scrolls every docker's content as a scroll bar does.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Scrolling without the slider is allowed for all dockers by a simple click and
## drag, which once did nothing inside the presets docker. The Brush Presets docker and the Layers docker are built as
## the app builds them, in a screen of their own, with [SaDragScroll] on their
## scroll as the boot puts it on every docker's, and a mouse press, a drag and
## a release go into the docker's window through its GUI pass. The list has to
## move by the drag's length and nothing in it be picked, moved or reordered,
## and a press let go where it landed has to pick the preset, as before.
extends "res://tests/test_framework.gd"

const ScratchFolder := preload("res://tests/fixtures/scratch_folder.gd")
const Fixtures = preload("res://tests/fixtures.gd")
const PresetsDockerScript = preload("res://ui/dockers/presets/brush_presets_docker.gd")
const BrushSettingsScript = preload("res://modules/sara-base-modules/stamp-brush/tools/brush_settings.gd")
const StateBrushScript = preload("res://modules/sara-base-modules/stamp-brush/tools/state_brush.gd")

## Thumbnails and layer rows are drawn on the card.
const REQUIRES_GPU := true

const SCREEN := Vector2i(1280, 1024)
const AT := Vector2i(200, 100)
const OPENED := Vector2i(320, 360)

## How far each drag goes, in the window's pixels, well inside either list's
## travel.
const DRAG: float = 90.0

## Presets enough to fill the docker twice over.
const PRESETS: int = 40

## Layers enough to fill the docker's list twice over.
const LAYERS: int = 30

## How long apart, in seconds, a drag's reports come: 15 pixels in 0.1 s is
## half the speed past which a drag moves the list further than the pointer.
const STEP_TIME: float = 0.1

static var scratch_dir: String = SaDataRoot.path("test_drag_scroll")

var _host: Node = null
var _kept_embedding: bool = true
var _picked: Array[String] = []


func before_each() -> void:
    var root := (Engine.get_main_loop() as SceneTree).root
    _kept_embedding = root.gui_embed_subwindows
    root.gui_embed_subwindows = true
    ScratchFolder.clear(scratch_dir)
    _picked.clear()
    _host = Node.new()
    _host.name = "Host"
    EventBus.add_child(_host)
    # The docker opens at the height its presets need only while no docker
    # has been dragged, a latch that is static, and a suite that moves one,
    # the toolbox's among them, leaves it set. Its pictures then sit below
    # the scroll and a press on them lands on nothing.
    DockerWindow.forget_painter_sizing()


func after_each() -> void:
    DockerDragHandle.capture_pointer = null
    if _host != null:
        _host.free()
        _host = null
    (Engine.get_main_loop() as SceneTree).root.gui_embed_subwindows = _kept_embedding
    ScratchFolder.clear(scratch_dir)


func _screen() -> SubViewport:
    var screen := SubViewport.new()
    screen.size = SCREEN
    screen.gui_embed_subwindows = true
    _host.add_child(screen)
    return screen


func _settle(frames: int = 6) -> void:
    var tree := Engine.get_main_loop() as SceneTree
    for i in frames:
        await tree.process_frame


## The Brush Presets docker over `PRESETS` presets, its scroll with its helper.
func _presets_docker() -> Window:
    var store := SaPresetStore.new()
    store.dir = scratch_dir
    for i in PRESETS:
        store.save_preset("Preset %02d" % (i + 1), BrushSettingsScript.new())
    var docker: Window = PresetsDockerScript.new()
    docker.position = AT
    _screen().add_child(docker)
    var chooser: SaBrushPresetsChooser = docker.get("chooser")
    chooser.in_shares = false
    chooser.bind_store(store, StateBrushScript, func() -> Resource: return BrushSettingsScript.new())
    chooser.preset_chosen.connect(func(picked: String) -> void: _picked.append(picked))
    docker.show()
    docker.size = OPENED
    SaDragScroll.take(_presets_scroll(docker))
    return docker


func _presets_scroll(docker: Window) -> ScrollContainer:
    return docker.find_child("Scroll", true, false) as ScrollContainer


## The Layers docker over a document of `LAYERS` layers.
func _layers_docker() -> LayersDocker:
    var canvas := SaCanvas.new()
    canvas.canvas_size = Vector2i(64, 64)
    canvas.easel = SaEasel.create_default(canvas.canvas_size)
    canvas.add_child(canvas.easel)
    _host.add_child(canvas)
    var ops := SaLayerOps.new(canvas.easel.document)
    for i in LAYERS - 2:
        ops.add()
    var docker := LayersDocker.new()
    docker.position = AT
    docker.target_canvas = canvas
    _screen().add_child(docker)
    docker.bind_registries(Fixtures.make_registries().blend_modes)
    docker.sync_layer_list()
    docker.show()
    docker.size = OPENED
    SaDragScroll.take(docker.item_list as ScrollContainer)
    return docker


func test_a_drag_on_a_preset_s_name_scrolls_the_presets_and_picks_none() -> void:
    var docker := _presets_docker()
    await _settle()
    var scroll := _presets_scroll(docker)
    var bar := scroll.get_v_scroll_bar()
    assert_true(bar.max_value > bar.page + DRAG, "the presets run %s past a page of %s" % [bar.max_value, bar.page])
    var name_label := _cell(docker, "Preset 01").get_node("Name") as Control
    var before := bar.value
    await _drag(docker, name_label.get_global_rect().get_center(), Vector2(0, -DRAG))
    await _settle(2)
    assert_almost_eq(bar.value - before, DRAG, 0.5, "a drag up of %s scrolled the presets down by as much" % DRAG)
    assert_eq(_picked, [] as Array[String], "and picked no preset")
    # A name further down, because at 56 pixel thumbnails the first preset's
    # has scrolled out of sight by now and a press there lands on nothing.
    var lower := _cell(docker, "Preset 10").get_node("Name") as Control
    await _drag(docker, lower.get_global_rect().get_center(), Vector2(0, DRAG * 0.5))
    await _settle(2)
    assert_almost_eq(bar.value - before, DRAG * 0.5, 0.5, "and a drag back down by half scrolled half of it back")
    assert_eq(_picked, [] as Array[String], "still picking none")


func test_a_drag_on_a_preset_s_picture_scrolls_and_picks_none() -> void:
    var docker := _presets_docker()
    await _settle()
    var bar := _presets_scroll(docker).get_v_scroll_bar()
    var picture := _cell(docker, "Preset 03").get_node("Icon") as Button
    var before := bar.value
    await _drag(docker, picture.get_global_rect().get_center(), Vector2(0, -DRAG))
    await _settle(2)
    assert_almost_eq(bar.value - before, DRAG, 0.5, "a drag from a picture scrolled the presets by its length")
    assert_eq(_picked, [] as Array[String], "and its button picked nothing on the release")
    assert_false(picture.button_pressed, "nor is it left drawn pressed")


func test_a_press_let_go_where_it_landed_still_picks_the_preset() -> void:
    var docker := _presets_docker()
    await _settle()
    var bar := _presets_scroll(docker).get_v_scroll_bar()
    var name_label := _cell(docker, "Preset 02").get_node("Name") as Control
    await _drag(docker, name_label.get_global_rect().get_center(), Vector2.ZERO)
    await _settle(2)
    assert_eq(_picked, ["Preset 02"] as Array[String], "a press and release on the name picked its preset")
    assert_eq(bar.value, 0.0, "and scrolled nothing")
    var picture := _cell(docker, "Preset 04").get_node("Icon") as Control
    await _drag(docker, picture.get_global_rect().get_center(), Vector2(2, 2))
    await _settle(2)
    assert_eq(_picked, ["Preset 02", "Preset 04"] as Array[String], "and one on a picture that wobbled two pixels picked its own")
    assert_eq(bar.value, 0.0, "still scrolling nothing")


## The rows are the reorder's, so the drag starts on the band under the last
## row, which the list shows at its end.
func test_a_drag_in_the_layers_docker_scrolls_and_picks_moves_and_reorders_no_layer() -> void:
    var docker := _layers_docker()
    await _settle()
    var list := docker.item_list as SaLayerList
    var bar := list.get_v_scroll_bar()
    assert_true(bar.max_value > bar.page + DRAG, "the rows run %s past a page of %s" % [bar.max_value, bar.page])
    bar.value = bar.max_value
    await _settle(2)
    var document := docker.target_canvas.document
    var order_before := _stack(document)
    var active_before := document.active_layer
    var picked_before := list.picked.selection.duplicate()
    var end := bar.value
    var last_row := list.rows[list.rows.size() - 1].get_global_rect()
    var visible_end := list.get_global_rect().end.y
    var band := Vector2(last_row.get_center().x, (last_row.end.y + visible_end) * 0.5)
    var tail := visible_end - last_row.end.y
    assert_true(tail >= 10.0, "the list ends in a band of no row, %s tall" % tail)
    await _drag(docker, band, Vector2(0, DRAG))
    await _settle(2)
    assert_almost_eq(end - bar.value, DRAG, 0.5, "a drag down of %s on it scrolled the rows up by as much" % DRAG)
    assert_eq(_stack(document), order_before, "no layer moved")
    assert_eq(document.active_layer, active_before, "the active layer is the one it was")
    assert_eq(list.picked.selection, picked_before, "and no row was picked")
    assert_false(list.dragging, "nor a row drag begun")


## A press on a row still arms its reorder and never scrolls.
func test_a_drag_on_a_layer_row_is_still_the_row_s() -> void:
    var docker := _layers_docker()
    await _settle()
    var list := docker.item_list as SaLayerList
    var bar := list.get_v_scroll_bar()
    var row := list.rows[2].get_global_rect()
    await _drag(docker, Vector2(row.get_center().x, row.get_center().y), Vector2(0, DRAG * 0.4), false)
    await _settle(2)
    assert_eq(bar.value, 0.0, "a drag on a row scrolled nothing")
    var helper := list.get_meta(SaDragScroll.TAKEN_META) as SaDragScroll
    assert_false(helper.dragging, "and the drag was never the scroll's, which leaves it to the row")
    _lift(docker, Vector2(row.get_center().x, row.get_center().y) + Vector2(0, DRAG * 0.4))


## Every layer of *document*, in its tree's order.
func _stack(document: SaDocument) -> Array[Node]:
    return document.find_children("*", "SaLayer", true, false)


func _cell(docker: Window, preset_name: String) -> Control:
    var chooser: SaBrushPresetsChooser = docker.get("chooser")
    return chooser.grid.get_node("Cell_" + preset_name.validate_node_name()) as Control


## A mouse press at *start* in the window's pixels, after a motion that brings
## the pointer there, dragged by *by* in six reports and let go unless *lift*
## is false. The reports come `STEP_TIME` apart, a pace under
## [constant SaDragScroll.CALM_SPEED], where the list follows one for one.
## Pushed into the screen the docker stands in, so the screen hands the window
## its pointer as the main window's viewport does, and a button under the
## pointer knows it is hovered.
func _drag(docker: Window, start: Vector2, by: Vector2, lift: bool = true) -> void:
    var arrive := InputEventMouseMotion.new()
    arrive.position = start
    arrive.global_position = start
    _push(docker, arrive)
    var press := InputEventMouseButton.new()
    press.button_index = MOUSE_BUTTON_LEFT
    press.button_mask = MOUSE_BUTTON_MASK_LEFT
    press.pressed = true
    press.position = start
    press.global_position = start
    _push(docker, press)
    var at := start
    if by != Vector2.ZERO:
        for i in 6:
            await (Engine.get_main_loop() as SceneTree).create_timer(STEP_TIME).timeout
            var step := by / 6.0
            at += step
            var motion := InputEventMouseMotion.new()
            motion.button_mask = MOUSE_BUTTON_MASK_LEFT
            motion.position = at
            motion.global_position = at
            motion.relative = step
            _push(docker, motion)
    if lift:
        _lift(docker, at)


func _lift(docker: Window, at: Vector2) -> void:
    var release := InputEventMouseButton.new()
    release.button_index = MOUSE_BUTTON_LEFT
    release.pressed = false
    release.position = at
    release.global_position = at
    _push(docker, release)


## *event*, whose places are the window's, pushed into the screen at the
## window's place.
func _push(docker: Window, event: InputEventMouse) -> void:
    event.position += Vector2(docker.position)
    event.global_position = event.position
    (docker.get_parent() as Viewport).push_input(event)
