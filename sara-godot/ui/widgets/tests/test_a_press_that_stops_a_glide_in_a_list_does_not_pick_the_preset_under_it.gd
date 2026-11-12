## A press that stops a glide in a list does not pick the preset under it.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A press 40 ms after a flick stopped the
## list and also picked the preset under it, and three seconds later the list
## had moved back by about a row on its own. A painter stopping a glide with a
## finger does not mean to pick what is under it. The Brush Presets docker is
## built over the stock count of presets with [SaDragScroll] on its scroll, and
## a mouse flick, a press and a still release go into the docker's window
## through its GUI pass, as the suite of the flick feeds them.
extends "res://tests/test_framework.gd"

const ScratchFolder := preload("res://tests/fixtures/scratch_folder.gd")
const PresetsDockerScript = preload("res://ui/dockers/presets/brush_presets_docker.gd")
const BrushSettingsScript = preload("res://modules/sara-base-modules/stamp-brush/tools/brush_settings.gd")
const StateBrushScript = preload("res://modules/sara-base-modules/stamp-brush/tools/state_brush.gd")

## Thumbnails are drawn on the card.
const REQUIRES_GPU := true

const SCREEN := Vector2i(1280, 2048)
const AT := Vector2i(200, 400)

## The stock presets' count.
const ROWS: int = 76

## A typical flick: 150 pixels in 60 milliseconds.
const FLICK: float = 150.0
const FLICK_TIME: float = 0.06

## How long after the flick's release the press comes, in seconds.
const PRESS_AFTER: float = 0.04

## How long the list is watched after the release, in seconds.
const WATCH: float = 3.0

static var scratch_dir: String = SaDataRoot.path("test_press_in_glide")

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


func after_each() -> void:
    DockerDragHandle.capture_pointer = null
    if _host != null:
        _host.free()
        _host = null
    (Engine.get_main_loop() as SceneTree).root.gui_embed_subwindows = _kept_embedding
    ScratchFolder.clear(scratch_dir)


func test_a_press_40_ms_after_a_flick_stops_the_list_and_picks_nothing() -> void:
    var docker: Window = await _presets_docker()
    var helper := _helper(docker)
    var bar := _scroll(docker).get_v_scroll_bar()
    var start := _start(docker)
    await _drag(docker, start, Vector2(0, -FLICK), FLICK_TIME)
    assert_true(helper.glide != Vector2.ZERO, "the flick set the list gliding")
    await (Engine.get_main_loop() as SceneTree).create_timer(PRESS_AFTER).timeout
    var tap := _face_middle(docker)
    _push(docker, _press(tap, true))
    assert_eq(helper.glide, Vector2.ZERO, "the press stopped the glide")
    await _settle(1)
    _push(docker, _press(tap, false))
    var stopped := bar.value
    var low := stopped
    var high := stopped
    var began := Time.get_ticks_msec()
    while Time.get_ticks_msec() - began < WATCH * 1000.0:
        await _settle(1)
        low = minf(low, bar.value)
        high = maxf(high, bar.value)
    print("the list stood at %s after the press and ranged %s to %s over %s s" % [stopped, low, high, WATCH])
    assert_eq(_picked, [] as Array[String], "the press that stopped the glide picked nothing")
    assert_eq(low, stopped, "the list did not move back after the glide was stopped")
    assert_eq(high, stopped, "nor on")


func test_a_still_press_with_no_glide_picks_the_preset_under_it() -> void:
    var docker: Window = await _presets_docker()
    var bar := _scroll(docker).get_v_scroll_bar()
    var tap := _face_middle(docker)
    var before := bar.value
    _push(docker, _mouse(InputEventMouseMotion.new(), tap, false))
    _push(docker, _press(tap, true))
    await _settle(1)
    _push(docker, _press(tap, false))
    await _settle()
    assert_eq(_picked.size(), 1, "a still press with no glide picked a preset, %s" % [_picked])
    assert_eq(bar.value, before, "and the list stood")


## The Brush Presets docker at its default size over the stock count of
## presets, its scroll with its helper, every pick written down.
func _presets_docker() -> Window:
    var store := SaPresetStore.new()
    store.dir = scratch_dir
    for i in ROWS:
        store.save_preset("Preset %03d" % (i + 1), BrushSettingsScript.new())
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
    chooser.preset_chosen.connect(func(picked: String) -> void: _picked.append(picked))
    docker.show()
    SaDragScroll.take(_scroll(docker))
    await _settle()
    return docker


func _settle(frames: int = 6) -> void:
    var tree := Engine.get_main_loop() as SceneTree
    for i in frames:
        await tree.process_frame


func _scroll(docker: Window) -> ScrollContainer:
    return docker.find_child("Scroll", true, false) as ScrollContainer


func _helper(docker: Window) -> SaDragScroll:
    return _scroll(docker).get_meta(SaDragScroll.TAKEN_META) as SaDragScroll


## Where the flick starts: the middle of the list's visible face, low on it.
func _start(docker: Window) -> Vector2:
    var face := _scroll(docker).get_global_rect()
    return Vector2(face.get_center().x, face.end.y - face.size.y * 0.15)


## Where the press lands: the middle of the list's visible face, over a tile.
func _face_middle(docker: Window) -> Vector2:
    return _scroll(docker).get_global_rect().get_center()


## A mouse press at *start* in the docker's pixels, dragged by *by* over
## *seconds* at an even pace and let go, the pointer reported each frame where
## the clock says it has got to.
func _drag(docker: Window, start: Vector2, by: Vector2, seconds: float) -> void:
    _push(docker, _mouse(InputEventMouseMotion.new(), start, false))
    _push(docker, _press(start, true))
    var began := Time.get_ticks_usec()
    var at := start
    var done := false
    while not done:
        await _settle(1)
        var share := minf((Time.get_ticks_usec() - began) / (seconds * 1000000.0), 1.0)
        done = share >= 1.0
        var next := start + by * share
        if next != at:
            var motion := _mouse(InputEventMouseMotion.new(), next, true) as InputEventMouseMotion
            motion.relative = next - at
            _push(docker, motion)
            at = next
    _push(docker, _press(at, false))


func _press(at: Vector2, pressed: bool) -> InputEventMouseButton:
    var button := _mouse(InputEventMouseButton.new(), at, pressed) as InputEventMouseButton
    button.button_index = MOUSE_BUTTON_LEFT
    button.pressed = pressed
    return button


func _mouse(event: InputEventMouse, at: Vector2, held: bool) -> InputEventMouse:
    event.button_mask = MOUSE_BUTTON_MASK_LEFT if held else 0
    event.position = at
    event.global_position = at
    return event


## *event*, whose places are the docker's, pushed into the screen at the
## docker's place.
func _push(docker: Window, event: InputEventMouse) -> void:
    event.position += Vector2(docker.position)
    event.global_position = event.position
    (docker.get_parent() as Viewport).push_input(event)
