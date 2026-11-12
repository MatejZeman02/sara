## A UI scale or a text size let go of shows at its new size on the next frame.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Letting go of either slider on Preferences' Workspace page must not leave the
## window at the old size long enough to wonder whether the release took.
## This suite opens Preferences beside every built-in docker, the default ones
## shown, moves each preference the way the slider's release writes it, and
## times the release to the first frame drawn after it. It prints that time
## split by part, the theme, the root window, each receiver of the bus's
## announcement, the deferred calls and the draw. It fails when the wait past
## the frame is over a quarter of what it was before the cut for the text size,
## or when the scale shows later than the frame after the idle one.
##
## The wait past the frame is the time to the first frame less the time a frame
## with nothing to do takes, measured in the same run. The nested compositor
## shows a frame every 16.7 ms whatever the work, so a release that lands on
## the very next frame reads as one frame and no cut can read as less. The scale
## is held to the frame after the idle one and not to a share, because with the
## font's distance field off for sharp text a new scale shapes and rasterises
## every label again, which takes the engine's root write, layout and draw to a
## second frame that no cut of the theme can skip.
##
## The split is a second move made by hand, part by part in the order
## `SaSettingsApply` runs them, because a receiver run again after the real
## move has nothing left to do and would time nothing.
extends "res://tests/test_framework.gd"

## Release to first frame, in milliseconds, as this suite measured them on the
## tree before the cut, two runs each. The text size was 450 and 435, nearly all
## of it 22 deferred propagations of the one shared theme, one for each class
## `SaUI.refresh_font_sizes` wrote, and the scale 25 and 28. The running app
## is heavier, its main window under the same theme: 2150 and 132 there. A
## frame with nothing to do took 16.7 in the same runs.
const BEFORE_MS := {&"ui_scale": 26.0, &"ui_font_scale": 440.0}
const BEFORE_IDLE_MS := 16.7
## The share of the old wait past the frame the text size may keep.
const FONT_SHARE := 1.0 / 4.0
## The scale may wait one frame past the idle frame. Frames come whole, so a
## bound of a frame and a half passes the second frame with room for the noise
## of a median and fails the third.
const SCALE_FRAMES := 1.5
## How many moves each preference makes, out and back, the median taken, so
## one frame the machine stalled on decides nothing.
const MOVES := 5

var _host: Node = null
var _dialogs: MainDialogs = null
var _dockers: MainDockers = null
var _was_embedding := false
var _was_low_processor := false
var _kept_root_theme: Theme = null
var _kept_shared_theme: Theme = null
var _kept_scale := 1.0
var _kept_font_scale := 1.0
var _layout_path := SaDataRoot.path("test_a_ui_scale_or_text_size_let_go_of.cfg")


## Low-processor mode draws a frame only when something asks for one, and the
## settling wait below asks for none, so it is off while the suite times frames.
func before_each() -> void:
    _was_low_processor = OS.low_processor_usage_mode
    OS.low_processor_usage_mode = false
    _kept_scale = SaSettings.ui_scale
    _kept_font_scale = SaSettings.ui_font_scale
    SaSettings.ui_scale = 1.0
    SaSettings.ui_font_scale = SaSettingsValues.DEFAULT_FONT_SCALE
    var tree := Engine.get_main_loop() as SceneTree
    _was_embedding = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    # The theme the boot gives the root and every window, without which a text
    # size change re-themes nothing and costs nothing to measure.
    _kept_root_theme = tree.root.theme
    _kept_shared_theme = SaUI.shared_theme
    SaUI.init_global_theme(tree)
    _host = Node.new()
    _host.name = "TestHost"
    EventBus.add_child(_host)
    var store := DockerLayoutStore.new()
    store.path = _layout_path
    _dockers = MainDockers.new(SaUIRegistry.new(), store)
    _dockers.register_builtin_dockers()
    _host.add_child(_dockers)
    _dockers.instantiate_registered_dockers()
    for config: Dictionary in _dockers.get_docker_config():
        if MainDockers._default_opened().has(String(config["id"])):
            (config["node"] as Window).show()
    _dialogs = MainDialogs.new(null, func() -> SaCanvas: return null)
    _host.add_child(_dialogs)
    _dialogs.open_preferences("Workspace")
    for i in 30:
        await RenderingServer.frame_post_draw


func after_each() -> void:
    SaSettings.ui_scale = _kept_scale
    SaSettings.ui_font_scale = _kept_font_scale
    var window := _dialogs._settings_window
    if window != null and is_instance_valid(window):
        window.hide()
    _host.free()
    var tree := Engine.get_main_loop() as SceneTree
    tree.root.gui_embed_subwindows = _was_embedding
    tree.root.theme = _kept_root_theme
    SaUI.shared_theme = _kept_shared_theme
    OS.low_processor_usage_mode = _was_low_processor
    if FileAccess.file_exists(_layout_path):
        DirAccess.remove_absolute(_layout_path)


## Milliseconds from *write* to the first frame drawn after it.
func _release_to_frame(write: Callable) -> float:
    await RenderingServer.frame_post_draw
    var t0 := Time.get_ticks_usec()
    write.call()
    await RenderingServer.frame_post_draw
    return (Time.get_ticks_usec() - t0) / 1000.0


static func _median(values: Array[float]) -> float:
    var sorted := values.duplicate()
    sorted.sort()
    @warning_ignore("integer_division")
    return sorted[sorted.size() / 2]


## The move made by hand, a part at a time, and each part's milliseconds.
func _split(property: StringName, value: float) -> Array:
    await RenderingServer.frame_post_draw
    var parts: Array = []
    # In an array, because a lambda holds a copy of a plain local.
    var last := [Time.get_ticks_usec()]
    var mark := func(part: String) -> void:
        var now := Time.get_ticks_usec()
        parts.append([part, (now - int(last[0])) / 1000.0])
        last[0] = now
    var announce: Signal
    var argument: float
    if property == &"ui_scale":
        SaUI.user_scale = value
        SaUI.apply_to_window(_host.get_tree().root)
        mark.call("the root window")
        announce = EventBus.ui_scale_changed
        argument = SaUI.scale()
    else:
        SaUI.user_font_scale = value
        SaUI.refresh_font_sizes()
        mark.call("the theme")
        announce = EventBus.ui_font_scale_changed
        argument = value
    for connection: Dictionary in announce.get_connections():
        var receiver: Callable = connection["callable"]
        receiver.call(argument)
        var target := receiver.get_object()
        mark.call("%s.%s" % [target.name if target is Node else target.get_class(), receiver.get_method()])
    await (Engine.get_main_loop() as SceneTree).process_frame
    mark.call("the deferred calls and the next frame's process")
    await RenderingServer.frame_post_draw
    mark.call("the draw")
    return parts


func _measure(property: StringName, there: float, back: float) -> float:
    var times: Array[float] = []
    for i in MOVES:
        times.append(await _release_to_frame(func() -> void: SaSettings.set(property, there)))
        times.append(await _release_to_frame(func() -> void: SaSettings.set(property, back)))
    var median := _median(times)
    var parts: Array = await _split(property, there)
    SaSettings.set(property, back)
    var line := PackedStringArray()
    for part: Array in parts:
        if float(part[1]) >= 0.5:
            line.append("%s %.1f" % [part[0], part[1]])
    print(
        (
            "  %s, release to first frame %.1f ms against %.1f before, by part: %s"
            % [property, median, BEFORE_MS[property], ", ".join(line)]
        )
    )
    return median


## One case for both sliders, because the built-in dockers are built once a
## run: a second set built after the first was freed crashes the engine inside
## what the first left registered.
func test_each_slider_let_go_of_shows_on_the_next_frame_with_a_share_of_the_wait_it_had() -> void:
    var idle_times: Array[float] = []
    for i in MOVES * 2:
        idle_times.append(await _release_to_frame(func() -> void: pass))
    var idle_ms := _median(idle_times)
    print("  a frame with nothing to do, %.1f ms against %.1f before" % [idle_ms, BEFORE_IDLE_MS])
    var moves := [
        [&"ui_scale", 1.25, 1.0, "scale"],
        [&"ui_font_scale", 0.9, SaSettingsValues.DEFAULT_FONT_SCALE, "text size"],
    ]
    for move: Array in moves:
        var property: StringName = move[0]
        var past := await _measure(property, move[1], move[2]) - idle_ms
        var allowed := (float(BEFORE_MS[property]) - BEFORE_IDLE_MS) * FONT_SHARE
        if property == &"ui_scale":
            allowed = idle_ms * SCALE_FRAMES
        assert_true(past <= allowed, "the %s's release waits %.1f ms past the frame, %.1f is the most" % [move[3], past, allowed])
