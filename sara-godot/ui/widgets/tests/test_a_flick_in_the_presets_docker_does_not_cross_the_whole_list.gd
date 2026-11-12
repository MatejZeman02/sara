## A flick in the presets docker does not cross the whole list.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The press and drag accelerator must not jump to the end too fast, but only
## after a longer drag. The Brush Presets docker is built over 76
## presets, the stock count, with [SaDragScroll] on its scroll as the boot puts
## it there, and a mouse press, motions paced by the clock and a release go into
## the docker's window through its GUI pass. A flick of 150 pixels in 60
## milliseconds has to leave the list at most a fifth of its length on, and a
## drag of a third of its length in 300 milliseconds has to carry it to its
## end. The screen is tall and the docker low on it, so the long drag stays on
## the screen as a painter's would.
extends "res://tests/test_framework.gd"

const ScratchFolder := preload("res://tests/fixtures/scratch_folder.gd")
const PresetsDockerScript = preload("res://ui/dockers/presets/brush_presets_docker.gd")
const BrushSettingsScript = preload("res://modules/sara-base-modules/stamp-brush/tools/brush_settings.gd")
const StateBrushScript = preload("res://modules/sara-base-modules/stamp-brush/tools/state_brush.gd")

## Thumbnails are drawn on the card.
const REQUIRES_GPU := true

const SCREEN := Vector2i(1280, 4096)
const AT := Vector2i(200, 3200)

## The stock presets' count.
const ROWS: int = 76

## A typical flick: 150 pixels in 60 milliseconds.
const FLICK: float = 150.0
const FLICK_TIME: float = 0.06

## The long drag: a third of the list in 300 milliseconds.
const LONG_TIME: float = 0.3

## The longest a glide is waited for, in seconds.
const GLIDE_WAIT: float = 5.0

static var scratch_dir: String = SaDataRoot.path("test_flick")

var _host: Node = null
var _kept_embedding: bool = true
var _kept_icon_size: int = 56


func before_each() -> void:
    _kept_icon_size = SaSettings.preset_icon_size
    var root := (Engine.get_main_loop() as SceneTree).root
    _kept_embedding = root.gui_embed_subwindows
    root.gui_embed_subwindows = true
    ScratchFolder.clear(scratch_dir)
    _host = Node.new()
    _host.name = "Host"
    EventBus.add_child(_host)


func after_each() -> void:
    SaSettings.preset_icon_size = _kept_icon_size
    DockerDragHandle.capture_pointer = null
    if _host != null:
        _host.free()
        _host = null
    (Engine.get_main_loop() as SceneTree).root.gui_embed_subwindows = _kept_embedding
    ScratchFolder.clear(scratch_dir)


func test_a_flick_of_150_pixels_moves_the_list_at_most_a_fifth_of_its_length() -> void:
    var docker: Window = await _presets_docker()
    var bar := _scroll(docker).get_v_scroll_bar()
    var length := bar.max_value - bar.page
    var before := bar.value
    await _drag(docker, _start(docker), Vector2(0, -FLICK), FLICK_TIME)
    var on_release := bar.value - before
    await _glide_out(docker)
    var moved := bar.value - before
    var said := [FLICK, FLICK_TIME, moved, length, on_release]
    print("a flick of %s in %s s moved the list %s of %s, %s of it at the release" % said)
    assert_true(moved > FLICK, "the flick carried the list on past the pointer, %s" % moved)
    assert_true(moved <= length / 5.0, "and moved it %s, at most a fifth of its %s" % [moved, length])


func test_a_flick_of_150_pixels_twice_as_fast_still_moves_the_list_at_most_a_fifth() -> void:
    var docker: Window = await _presets_docker()
    var bar := _scroll(docker).get_v_scroll_bar()
    var length := bar.max_value - bar.page
    var before := bar.value
    await _drag(docker, _start(docker), Vector2(0, -FLICK), FLICK_TIME / 2.0)
    await _glide_out(docker)
    var moved := bar.value - before
    print("a flick of %s in %s s moved the list %s of %s" % [FLICK, FLICK_TIME / 2.0, moved, length])
    assert_true(moved <= length / 5.0, "a faster flick moved it %s, at most a fifth of its %s" % [moved, length])


func test_a_drag_of_a_third_of_the_list_in_300_ms_carries_it_to_its_end() -> void:
    var docker: Window = await _presets_docker()
    var bar := _scroll(docker).get_v_scroll_bar()
    var length := bar.max_value - bar.page
    var row := length / ROWS
    await _drag(docker, _start(docker), Vector2(0, -length / 3.0), LONG_TIME)
    await _glide_out(docker)
    print("a drag of %s in %s s left the list at %s of %s" % [length / 3.0, LONG_TIME, bar.value, length])
    assert_true(bar.value >= length - row, "the list stands at %s, within a row of %s of its end %s" % [bar.value, row, length])


## The Brush Presets docker at its default size over the stock count of
## presets, its scroll with its helper.
func _presets_docker() -> Window:
    # The thumbnails at 112 pixels, as the list was long enough for the
    # glide of a flick to stay under a fifth of it. The default is 56 now and
    # 76 presets then make a list of less than 2000 pixels, which a flick of
    # 150 pixels glides across by almost half whatever the thumbnails are.
    SaSettings.preset_icon_size = 112
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
