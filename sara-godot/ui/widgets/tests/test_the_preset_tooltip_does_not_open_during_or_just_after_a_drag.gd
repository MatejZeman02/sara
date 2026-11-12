## The preset tooltip does not open during or just after a drag.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The session's check of 2026-11-07: a tooltip for the cell under the pointer
## opened during and after the drags in the Brush Presets docker and covered
## half the list. The docker is built over the stock count of presets with
## [SaDragScroll] on its scroll, the mouse goes into its window through its GUI
## pass as the suite of the flick feeds it, and every tooltip the engine builds
## is caught on its way into the tree, where `SaTooltip` catches it too.
extends "res://tests/test_framework.gd"

const ScratchFolder := preload("res://tests/fixtures/scratch_folder.gd")
const PresetsDockerScript = preload("res://ui/dockers/presets/brush_presets_docker.gd")
const BrushSettingsScript = preload("res://modules/sara-base-modules/stamp-brush/tools/brush_settings.gd")
const StateBrushScript = preload("res://modules/sara-base-modules/stamp-brush/tools/state_brush.gd")
const PresetEngineMarks := preload("res://ui/dockers/presets/preset_engine_marks.gd")

## Thumbnails are drawn on the card.
const REQUIRES_GPU := true

const SCREEN := Vector2i(1280, 2048)
const AT := Vector2i(200, 400)

## The stock presets' count.
const ROWS: int = 76

## A slow drag, well under the calm speed so it does not glide, held for over
## twice a tooltip's delay.
const SLOW: float = 200.0
const SLOW_TIME: float = 1.2

## A typical flick: 150 pixels in 60 milliseconds.
const FLICK: float = 150.0
const FLICK_TIME: float = 0.06

static var scratch_dir: String = SaDataRoot.path("test_tooltip_in_drag")

var _host: Node = null
var _kept_embedding: bool = true
## Every tooltip label the engine built while a test ran.
var _tips: Array[Label] = []
## The cells' tooltip writer, over the suite's own store, since the docker's
## own asks the tool bar for its store and a docker on its own has no bar.
var _marks: PresetEngineMarks = null


func before_each() -> void:
    var root := (Engine.get_main_loop() as SceneTree).root
    _kept_embedding = root.gui_embed_subwindows
    root.gui_embed_subwindows = true
    ScratchFolder.clear(scratch_dir)
    _tips.clear()
    _host = Node.new()
    _host.name = "Host"
    EventBus.add_child(_host)
    (Engine.get_main_loop() as SceneTree).node_added.connect(_on_node_added)


func after_each() -> void:
    (Engine.get_main_loop() as SceneTree).node_added.disconnect(_on_node_added)
    DockerDragHandle.capture_pointer = null
    if _host != null:
        _host.free()
        _host = null
    _marks = null
    (Engine.get_main_loop() as SceneTree).root.gui_embed_subwindows = _kept_embedding
    ScratchFolder.clear(scratch_dir)


func _on_node_added(node: Node) -> void:
    var label := node as Label
    if label != null and label.theme_type_variation == &"TooltipLabel":
        _tips.append(label)


func test_no_tooltip_opens_while_a_drag_lasts_nor_while_its_glide_runs() -> void:
    var docker: Window = await _presets_docker()
    var helper := _helper(docker)
    var marks := _marks
    var delay := float(ProjectSettings.get_setting("gui/timers/tooltip_delay_sec", 0.5))
    var start := _start(docker)
    # Where the pen hovers between the drags, on the list's face whatever size
    # the docker was given, so its tooltip is a cell's and not the bar's above.
    var face := _face_middle(docker)
    await _drag(docker, start, Vector2(0, -SLOW), SLOW_TIME)
    assert_eq(helper.glide, Vector2.ZERO, "the slow drag let go without a glide")
    assert_eq(_tips.size(), 0, "no tooltip opened while the slow drag of %s s lasted" % SLOW_TIME)
    await _hover_for(docker, face, delay * 0.9)
    assert_eq(_tips.size(), 0, "nor within a tooltip's delay after it, under a pen hovering on")
    await _drag(docker, start, Vector2(0, -FLICK), FLICK_TIME)
    assert_true(helper.glide != Vector2.ZERO, "the flick set the list gliding")
    assert_true(marks.hushed, "the tooltips are held back while the list glides")
    var began := Time.get_ticks_msec()
    var jitter := 1.0
    while helper.glide != Vector2.ZERO:
        jitter = -jitter
        _push(docker, _mouse(InputEventMouseMotion.new(), face + Vector2(jitter, 0), false))
        await _settle(1)
    var glided := (Time.get_ticks_msec() - began) / 1000.0
    print("the glide ran %.2f s under a hovering pen" % glided)
    assert_true(glided > delay * 2.0, "the glide ran more than twice a tooltip's delay, %.2f s" % glided)
    assert_eq(_tips.size(), 0, "no tooltip opened while the glide ran, %s" % [_texts()])
    await _hover_for(docker, face, delay * 0.9)
    assert_eq(_tips.size(), 0, "nor within a tooltip's delay after the list stood")
    await _hover_for(docker, face, delay * 0.2)
    assert_false(marks.hushed, "the tooltips are back once the list has stood a tooltip's delay")
    # The engine starts a tooltip's timer on a pointer that enters a control or
    # moves more than five pixels, so a fresh hover is a move of the pen.
    await _hover_for(docker, face + Vector2(24, 0), delay * 2.0)
    assert_eq(_tips.size(), 1, "and a fresh hover opens one tooltip")


func test_a_cell_hovered_at_rest_shows_its_tooltip_as_before() -> void:
    var docker: Window = await _presets_docker()
    var marks := _marks
    var delay := float(ProjectSettings.get_setting("gui/timers/tooltip_delay_sec", 0.5))
    var at := _face_middle(docker)
    _push(docker, _mouse(InputEventMouseMotion.new(), at, false))
    await _wait(delay * 0.5)
    assert_eq(_tips.size(), 0, "no tooltip before its delay")
    await _wait(delay * 1.5)
    await _wait(delay * 1.5)
    assert_eq(_tips.size(), 1, "one tooltip opened over the cell at rest")
    if _tips.is_empty():
        return
    var shown := _tips[0].text
    var cells: Dictionary = marks.report()["cells"]
    var named: Array = cells.keys().filter(func(name: String) -> bool: return shown.begins_with(name + ", a "))
    assert_eq(named.size(), 1, "the tooltip names one preset, '%s'" % shown)
    if named.size() == 1:
        assert_eq(shown, String(cells[named[0]]["tooltip"]), "and reads as that cell's tooltip")


## A pen hovering at *at* for *seconds*, reporting a pixel either side of it
## each frame as a hand held over a tablet does, the button up.
func _hover_for(docker: Window, at: Vector2, seconds: float) -> void:
    var began := Time.get_ticks_msec()
    var jitter := 1.0
    while Time.get_ticks_msec() - began < seconds * 1000.0:
        jitter = -jitter
        _push(docker, _mouse(InputEventMouseMotion.new(), at + Vector2(jitter, 0), false))
        await _settle(1)


## The text of each tooltip the engine built, for a failing line to name.
func _texts() -> Array:
    return _tips.map(func(tip: Label) -> String: return tip.text if is_instance_valid(tip) else "")


func _wait(seconds: float) -> void:
    await (Engine.get_main_loop() as SceneTree).create_timer(seconds).timeout


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
    # The helper before the cells, as the boot gives it to the scroll as the
    # scroll enters the tree.
    SaDragScroll.take(_scroll(docker))
    var chooser: SaBrushPresetsChooser = docker.get("chooser")
    _marks = PresetEngineMarks.new(chooser, func() -> SaPresetStore: return store, func() -> StringName: return &"stamp")
    chooser.in_shares = false
    chooser.bind_store(store, StateBrushScript, func() -> Resource: return BrushSettingsScript.new())
    docker.show()
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
