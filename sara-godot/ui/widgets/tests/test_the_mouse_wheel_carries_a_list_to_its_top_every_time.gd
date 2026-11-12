## The mouse wheel carries a list to its top every time.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The session's check of 2026-11-07: 200 notches of the wheel upwards stopped
## at Broken Chalk once, short of the top of the presets list. The Brush Presets
## docker is built over 76 presets, the stock count, with [SaDragScroll] on its
## scroll as the boot puts it there. A flick throws the list down and 200
## notches of the wheel upwards go into the docker's window straight after,
## while the list still glides, a burst in one frame as a door's step sends
## them and one a frame as a hand turns the wheel. Each has to leave the list at
## its top once everything has stopped, and so do 200 notches over a list at
## rest.
extends "res://tests/test_framework.gd"

const ScratchFolder := preload("res://tests/fixtures/scratch_folder.gd")
const PresetsDockerScript = preload("res://ui/dockers/presets/brush_presets_docker.gd")
const BrushSettingsScript = preload("res://modules/sara-base-modules/stamp-brush/tools/brush_settings.gd")
const StateBrushScript = preload("res://modules/sara-base-modules/stamp-brush/tools/state_brush.gd")

## Thumbnails are drawn on the card.
const REQUIRES_GPU := true

const SCREEN := Vector2i(1280, 1600)
const AT := Vector2i(200, 600)

## The stock presets' count.
const ROWS: int = 76

## The notches of the session's check.
const NOTCHES: int = 200

## A flick of 300 pixels in 60 milliseconds, which glides on after the release.
const FLICK: float = 300.0
const FLICK_TIME: float = 0.06

## The longest a glide is waited for, in seconds.
const GLIDE_WAIT: float = 5.0

static var scratch_dir: String = SaDataRoot.path("test_wheel")

var _host: Node = null
var _kept_embedding: bool = true


func before_each() -> void:
    var root := (Engine.get_main_loop() as SceneTree).root
    _kept_embedding = root.gui_embed_subwindows
    root.gui_embed_subwindows = true
    ScratchFolder.clear(scratch_dir)
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


func test_200_notches_in_one_burst_straight_after_a_flick_reach_the_top() -> void:
    var docker: Window = await _presets_docker()
    var bar := _scroll(docker).get_v_scroll_bar()
    await _drag(docker, _start(docker), Vector2(0, -FLICK), FLICK_TIME)
    assert_true(_helper(docker).glide != Vector2.ZERO, "the flick set the list gliding")
    for i in NOTCHES:
        _wheel(docker, _start(docker))
    await _glide_out(docker)
    await _settle()
    print("a burst of %s notches after a flick left the list at %s" % [NOTCHES, bar.value])
    assert_eq(bar.value, 0.0, "the list stands at its top")


func test_200_notches_one_a_frame_straight_after_a_flick_reach_the_top() -> void:
    var docker: Window = await _presets_docker()
    var bar := _scroll(docker).get_v_scroll_bar()
    await _drag(docker, _start(docker), Vector2(0, -FLICK), FLICK_TIME)
    assert_true(_helper(docker).glide != Vector2.ZERO, "the flick set the list gliding")
    for i in NOTCHES:
        _wheel(docker, _start(docker))
        await _settle(1)
    await _glide_out(docker)
    await _settle()
    print("%s notches one a frame after a flick left the list at %s" % [NOTCHES, bar.value])
    assert_eq(bar.value, 0.0, "the list stands at its top")


func test_200_notches_over_a_list_at_rest_reach_the_top() -> void:
    var docker: Window = await _presets_docker()
    var bar := _scroll(docker).get_v_scroll_bar()
    bar.value = bar.max_value
    await _settle()
    assert_true(bar.value > 0.0, "the list stands at its end, %s" % bar.value)
    for i in NOTCHES:
        _wheel(docker, _start(docker))
    await _settle()
    print("%s notches at rest left the list at %s" % [NOTCHES, bar.value])
    assert_eq(bar.value, 0.0, "the list stands at its top")


## One notch of the wheel upwards at *at*, its press and its release, as a
## wheel reports one.
func _wheel(docker: Window, at: Vector2) -> void:
    for pressed: bool in [true, false]:
        var notch := _mouse(InputEventMouseButton.new(), at, false) as InputEventMouseButton
        notch.button_index = MOUSE_BUTTON_WHEEL_UP
        notch.pressed = pressed
        notch.factor = 1.0
        _push(docker, notch)


## The Brush Presets docker at its default size over the stock count of
## presets, its scroll with its helper.
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


## Where a drag starts: the middle of the list's visible face, low on it.
func _start(docker: Window) -> Vector2:
    var face := _scroll(docker).get_global_rect()
    return Vector2(face.get_center().x, face.end.y - face.size.y * 0.15)


## Waits, up to `GLIDE_WAIT` seconds, for the docker's list to stop gliding.
func _glide_out(docker: Window) -> void:
    var helper := _helper(docker)
    var began := Time.get_ticks_msec()
    while helper.glide != Vector2.ZERO and Time.get_ticks_msec() - began < GLIDE_WAIT * 1000.0:
        await _settle(1)
    assert_eq(helper.glide, Vector2.ZERO, "the glide came to a stop")


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
