## A drag in a docker speeds up with the pen and glides on after a flick.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Scrolling inside a docker without the slider needs to accelerate and not stop
## at some max speed, since sometimes one needs to get to the end of the list
## quickly. The Brush
## Presets docker is built as the app builds it, in a screen of its own, with
## [SaDragScroll] on its scroll as the boot puts it there, and a mouse press,
## motions paced by the clock and a release go into the docker's window
## through its GUI pass. A slow drag has to move the list as far as the pointer,
## a flick has to carry it on past the pointer's travel and yet leave two
## hundred presets at most a fifth of their length on, since one flick crossing
## the whole list reads as too eager, and a press
## during a glide has to stop it and pick nothing, since a painter stopping
## the list with a finger does not mean to pick what is under it.
extends "res://tests/test_framework.gd"

const ScratchFolder := preload("res://tests/fixtures/scratch_folder.gd")
const PresetsDockerScript = preload("res://ui/dockers/presets/brush_presets_docker.gd")
const BrushSettingsScript = preload("res://modules/sara-base-modules/stamp-brush/tools/brush_settings.gd")
const StateBrushScript = preload("res://modules/sara-base-modules/stamp-brush/tools/state_brush.gd")

## Thumbnails are drawn on the card.
const REQUIRES_GPU := true

const SCREEN := Vector2i(1280, 1024)
const AT := Vector2i(200, 100)

## The slow drag: 90 pixels over a second.
const SLOW_DRAG: float = 90.0
const SLOW_TIME: float = 1.0

## The flick: 150 pixels in a tenth of a second.
const FLICK: float = 150.0
const FLICK_TIME: float = 0.1

## Presets enough that the list is a long one.
const MANY: int = 200
## Presets enough to fill the docker a few times over.
const SOME: int = 40

## The longest a glide is waited for, in seconds.
const GLIDE_WAIT: float = 5.0

static var scratch_dir: String = SaDataRoot.path("test_drag_glide")

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


func _settle(frames: int = 6) -> void:
    var tree := Engine.get_main_loop() as SceneTree
    for i in frames:
        await tree.process_frame


## The Brush Presets docker at its default size over *count* presets, its scroll
## with its helper.
func _presets_docker(count: int) -> Window:
    var store := SaPresetStore.new()
    store.dir = scratch_dir
    for i in count:
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


func _scroll(docker: Window) -> ScrollContainer:
    return docker.find_child("Scroll", true, false) as ScrollContainer


func _helper(docker: Window) -> SaDragScroll:
    return _scroll(docker).get_meta(SaDragScroll.TAKEN_META) as SaDragScroll


## Where a drag starts: the middle of the list's visible face, low on it so
## a drag up has room.
func _start(docker: Window) -> Vector2:
    var face := _scroll(docker).get_global_rect()
    return Vector2(face.get_center().x, face.end.y - face.size.y * 0.15)


func test_a_slow_drag_moves_the_list_as_far_as_the_pen_and_picks_nothing() -> void:
    var docker: Window = await _presets_docker(SOME)
    var bar := _scroll(docker).get_v_scroll_bar()
    assert_true(bar.max_value > bar.page + SLOW_DRAG, "the presets run %s past a page of %s" % [bar.max_value, bar.page])
    var before := bar.value
    await _drag(docker, _start(docker), Vector2(0, -SLOW_DRAG), SLOW_TIME)
    await _glide_out(docker)
    assert_almost_eq(bar.value - before, SLOW_DRAG, 2.0, "a drag of %s over a second moved the list by as much" % SLOW_DRAG)
    assert_eq(_picked, [] as Array[String], "and picked no preset")


func test_a_flick_carries_the_list_at_least_twice_as_far_as_the_pen() -> void:
    var docker: Window = await _presets_docker(MANY)
    var bar := _scroll(docker).get_v_scroll_bar()
    var before := bar.value
    await _drag(docker, _start(docker), Vector2(0, -FLICK), FLICK_TIME)
    var on_release := bar.value - before
    assert_true(_helper(docker).glide.length() > 0.0, "the release left the list gliding")
    await _glide_out(docker)
    var moved := bar.value - before
    assert_true(moved >= FLICK * 2.0, "a flick of %s moved the list %s, %s of it at the release" % [FLICK, moved, on_release])
    assert_true(moved > on_release + FLICK, "and the glide after the release carried it on, from %s to %s" % [on_release, moved])
    assert_eq(_picked, [] as Array[String], "and picked no preset")


func test_a_flick_moves_two_hundred_presets_at_most_a_fifth_of_their_length() -> void:
    var docker: Window = await _presets_docker(MANY)
    var bar := _scroll(docker).get_v_scroll_bar()
    var length := bar.max_value - bar.page
    assert_true(length > 20.0 * FLICK, "two hundred presets run %s past the page" % length)
    var before := bar.value
    await _drag(docker, _start(docker), Vector2(0, -FLICK), FLICK_TIME)
    await _glide_out(docker)
    var moved := bar.value - before
    assert_true(moved <= length / 5.0, "a flick of %s moved the list %s, at most a fifth of its %s" % [FLICK, moved, length])
    assert_eq(_picked, [] as Array[String], "and picked no preset")


func test_a_press_during_a_glide_stops_it_and_its_tap_picks_nothing() -> void:
    var docker: Window = await _presets_docker(MANY)
    var bar := _scroll(docker).get_v_scroll_bar()
    var at := _start(docker)
    await _drag(docker, at, Vector2(0, -FLICK), FLICK_TIME)
    await _settle(3)
    assert_true(_helper(docker).glide.length() > 0.0, "the list still glides three frames after the release")
    var tap := _scroll(docker).get_global_rect().get_center()
    _push(docker, _motion(tap, Vector2.ZERO))
    _push(docker, _button(tap, true))
    var at_press := bar.value
    await _settle(1)
    assert_eq(bar.value, at_press, "a frame after the press the list stands where the press found it")
    assert_eq(_helper(docker).glide, Vector2.ZERO, "and glides no more")
    await _settle(3)
    assert_eq(bar.value, at_press, "nor moves after it")
    var under := _preset_at(docker, tap)
    assert_true(under != "", "the tap landed on a preset")
    _push(docker, _button(tap, false))
    await _settle(2)
    assert_eq(_picked, [] as Array[String], "and its release picked nothing, not %s under it" % under)


## The name of the preset whose cell holds *at*, in the docker's pixels, or
## nothing.
func _preset_at(docker: Window, at: Vector2) -> String:
    var chooser: SaBrushPresetsChooser = docker.get("chooser")
    for cell: Node in chooser.grid.get_children():
        var control := cell as Control
        if control != null and control.visible and control.get_global_rect().has_point(at):
            return String(control.name).trim_prefix("Cell_").replace("_", " ")
    return ""


## Waits, up to `GLIDE_WAIT` seconds, for the docker's list to stop gliding.
func _glide_out(docker: Window) -> void:
    var helper := _helper(docker)
    var began := Time.get_ticks_msec()
    while helper.glide != Vector2.ZERO and Time.get_ticks_msec() - began < GLIDE_WAIT * 1000.0:
        await _settle(1)
    assert_eq(helper.glide, Vector2.ZERO, "the glide came to a stop")


## A mouse press at *start* in the window's pixels, dragged by *by* over
## *seconds* at an even pace and let go. Each frame the pointer is reported
## where the clock says it has got to, as a pen moved at a steady speed is.
func _drag(docker: Window, start: Vector2, by: Vector2, seconds: float) -> void:
    _push(docker, _motion(start, Vector2.ZERO))
    _push(docker, _button(start, true))
    var began := Time.get_ticks_usec()
    var at := start
    var done := false
    while not done:
        await _settle(1)
        var share := minf((Time.get_ticks_usec() - began) / (seconds * 1000000.0), 1.0)
        done = share >= 1.0
        var next := start + by * share
        if next != at:
            _push(docker, _motion(next, next - at))
            at = next
    _push(docker, _button(at, false))


func _motion(at: Vector2, step: Vector2) -> InputEventMouseMotion:
    var motion := InputEventMouseMotion.new()
    motion.button_mask = MOUSE_BUTTON_MASK_LEFT if step != Vector2.ZERO else 0
    motion.position = at
    motion.global_position = at
    motion.relative = step
    return motion


func _button(at: Vector2, pressed: bool) -> InputEventMouseButton:
    var button := InputEventMouseButton.new()
    button.button_index = MOUSE_BUTTON_LEFT
    button.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
    button.pressed = pressed
    button.position = at
    button.global_position = at
    return button


## *event*, whose places are the window's, pushed into the screen at the
## window's place.
func _push(docker: Window, event: InputEventMouse) -> void:
    event.position += Vector2(docker.position)
    event.global_position = event.position
    (docker.get_parent() as Viewport).push_input(event)
