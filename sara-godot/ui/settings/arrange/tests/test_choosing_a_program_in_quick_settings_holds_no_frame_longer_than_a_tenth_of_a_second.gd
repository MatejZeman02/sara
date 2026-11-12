## Choosing a program in Quick settings holds no frame longer than a tenth of a
## second.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The row stands in the tree here, so a press is spread over frames, over a
## layout store of the suite's own on a scratch file, the way the layout suites
## build one. A frame is one emission of the tree's `process_frame`, which wakes
## the palette's slices and the layout's spread load, and then one call of the
## row's `_process`, which is what the engine calls once a frame: the runner
## cannot advance a frame, and an await drops every assertion after it. The frame timer is the time those
## two take. What a spread press ends in is read against what one call of
## `SaComingFromRow.apply` gives from the same start.
extends "res://tests/test_framework.gd"

const HOST := Vector2i(1920, 1048)
const BOUND_USEC: int = 100000
## More frames than a press can take, so a press that never ends fails rather
## than hangs.
const MOST_FRAMES: int = 2000
## The presses each test runs, the last Krita's again, which releases it and
## puts Sara's own values back.
const PROGRAMS: Array[String] = ["photoshop", "krita"]
const PRESSES: Array[String] = ["photoshop", "krita", "krita"]
static var scratch_layout_path: String = SaDataRoot.path("test_choose_program_layout.cfg")

var _root: Node = null
var _store: DockerLayoutStore = null
var _row: SaComingFromRow = null
var _saved_layout_state := ConfigFile.new()
var _saved := {}


func before_each() -> void:
    for key: String in ["shortcuts_profile", "theme_name", "color_picker_shape", "reset_zoom"]:
        _saved[key] = SaSettings.get(key)
    _fresh_start()
    _saved_layout_state = ConfigFile.new()
    _root = Node.new()
    _root.name = "TestHost"
    EventBus.add_child(_root)
    var viewport := SubViewport.new()
    viewport.size = HOST
    viewport.gui_embed_subwindows = true
    _root.add_child(viewport)
    var host := Control.new()
    host.set_anchors_preset(Control.PRESET_FULL_RECT)
    viewport.add_child(host)
    var docker := Window.new()
    docker.size = Vector2i(200, 150)
    host.add_child(docker)
    _store = DockerLayoutStore.new()
    _store.path = scratch_layout_path
    _store.dockers_provider = func() -> Array: return [{"id": "ProbeDocker", "name": "Probe", "node": docker}]
    _store.save_allowed = func() -> bool: return true
    _store.presets().capture(_saved_layout_state)
    _row = SaComingFromRow.new(_store)
    host.add_child(_row)


func after_each() -> void:
    _settle()
    _row.free()
    _store.presets().apply(_saved_layout_state)
    _store.free()
    _root.free()
    for key: String in _saved:
        SaSettings.set(key, _saved[key])
    SaTheme.use_named(SaSettings.theme_name)
    SaShortcutStore.apply_profile(SaSettings.shortcuts_profile)
    EventBus.shortcuts_changed.emit()
    DirAccess.remove_absolute(scratch_layout_path)


## A fresh folder's settings, the palette painted whole and the map applied.
func _fresh_start() -> void:
    for key: String in ["shortcuts_profile", "theme_name", "color_picker_shape", "reset_zoom"]:
        SaSettings.set(key, (SaSettingsValues as Script).get_property_default_value(key))
    SaTheme.use_named(SaSettings.theme_name)
    SaShortcutStore.apply_profile(SaSettings.shortcuts_profile)


## One harness frame, and how long it took in microseconds.
func _frame() -> int:
    var started := Time.get_ticks_usec()
    (Engine.get_main_loop() as SceneTree).process_frame.emit()
    _row._process(0.0)
    return Time.get_ticks_usec() - started


## Frames until no press and no palette slice is left, answering each frame's
## time.
func _settle() -> Array[int]:
    var times: Array[int] = []
    while (_row.pressing() or SaTheme.repainting()) and times.size() < MOST_FRAMES:
        times.append(_frame())
    return times


func _pressed() -> Array[String]:
    var out: Array[String] = []
    for program: String in _row.buttons:
        if _row.buttons[program].button_pressed:
            out.append(program)
    return out


## Everything a press sets, read from where it is in force: the settings, the
## palette SaTheme draws with, the layout, the input map's chords for every
## action, and every bound box and font colour as the palette has it.
func _reading() -> Dictionary:
    var chords := {}
    for action: StringName in InputMap.get_actions():
        if not String(action).begins_with("ui_"):
            chords[action] = SaShortcutStore.chords_for(action)
    return {
        "shortcuts": SaSettings.shortcuts_profile,
        "palette": SaSettings.theme_name,
        "theme": SaTheme.palette_id,
        "layout": _store.current_preset(),
        "picker": SaSettings.color_picker_shape,
        "chords": chords,
        "unpainted": _unpainted(),
    }


## The bound boxes and font colours whose colour is not the palette's, which a
## palette painted whole leaves none of.
func _unpainted() -> Array[String]:
    var out: Array[String] = []
    for style_id: int in SaTheme._bound_styles:
        var style := instance_from_id(style_id) as StyleBox
        if style == null:
            continue
        var bindings: Dictionary = SaTheme._bound_styles[style_id]
        for property: String in bindings:
            if style.get(property) != SaTheme.palette.get(bindings[property]):
                out.append("%s.%s" % [style, property])
    for id: int in SaTheme._bound_fonts:
        var control := instance_from_id(id) as Control
        if control == null:
            continue
        var colours: Dictionary = SaTheme._bound_fonts[id]
        for theme_name: String in colours:
            if control.get_theme_color(theme_name) != SaTheme.palette.get(colours[theme_name]):
                out.append("%s.%s" % [control.name, theme_name])
    return out


## What one call of `apply` gives for *program* from a fresh folder.
func _applied_whole(program: String) -> Dictionary:
    _fresh_start()
    _store.load_preset("default")
    SaComingFromRow.apply(program, _store)
    return _reading()


func test_a_spread_press_ends_where_one_call_of_apply_does() -> void:
    for program: String in PROGRAMS:
        var whole := _applied_whole(program)
        _fresh_start()
        _store.load_preset("default")
        _row.press(program)
        var frames := _settle()
        assert_true(frames.size() < MOST_FRAMES, "%s's press ends (%d frames)" % [program, frames.size()])
        assert_true(frames.size() > 3, "and takes frames rather than one (%d)" % frames.size())
        var spread := _reading()
        assert_eq(spread["unpainted"], [] as Array[String], "%s: every bound colour is the palette's" % program)
        for key: String in whole:
            assert_eq(spread[key], whole[key], "%s: the %s is what one call of apply gives" % [program, key])
        assert_eq(_pressed(), [program] as Array[String], "%s's button is the one pressed" % program)
    var own := _applied_whole(SaComingFromRow.OWN)
    _fresh_start()
    _store.load_preset("default")
    _row.press("krita")
    _settle()
    _row.press("krita")
    var release_frames := _settle()
    assert_true(release_frames.size() > 3, "Krita's release takes frames rather than one (%d)" % release_frames.size())
    var released := _reading()
    assert_eq(released["unpainted"], [] as Array[String], "released: every bound colour is the palette's")
    for key: String in own:
        assert_eq(released[key], own[key], "released: the %s is Sara's own" % key)
    assert_eq(_pressed(), [] as Array[String], "and no button is pressed")


func test_no_frame_of_a_press_takes_over_a_tenth_of_a_second() -> void:
    for program: String in PRESSES:
        _row.press(program)
        var frames := _settle()
        var longest := 0
        for usec: int in frames:
            longest = maxi(longest, usec)
        assert_true(
            longest <= BOUND_USEC, "%s: the longest of %d frames took %.1f ms" % [program, frames.size(), longest / 1000.0]
        )


## The frame of the press writes nothing and shows the button pressed, and the
## next frame starts the writers.
func test_the_button_shows_pressed_before_anything_is_written() -> void:
    var before := SaSettings.shortcuts_profile
    _row.press("photoshop")
    assert_eq(_pressed(), ["photoshop"] as Array[String], "Photoshop shows pressed in the press's own frame")
    assert_eq(SaSettings.shortcuts_profile, before, "with nothing written yet")
    _frame()
    assert_eq(SaSettings.shortcuts_profile, before, "the press's own frame writes nothing")
    _frame()
    assert_eq(SaSettings.shortcuts_profile, "Photoshop", "the frame after it applies the shortcut map")
    assert_eq(_pressed(), ["photoshop"] as Array[String], "and the button stays pressed while the rest follows")


func test_a_second_press_mid_way_ends_in_the_second_programs_values() -> void:
    var krita := _applied_whole("krita")
    _fresh_start()
    _store.load_preset("default")
    _row.press("photoshop")
    for i: int in 5:
        _frame()
    assert_true(_row.pressing(), "Photoshop's press is under way")
    _row.press("krita")
    assert_eq(_pressed(), ["krita"] as Array[String], "Krita shows pressed at once")
    var applied: Array[String] = []
    _row.program_applied.connect(func(program: String) -> void: applied.append(program))
    _settle()
    assert_eq(applied, ["photoshop", "krita"] as Array[String], "the first press ends before the second starts")
    var read := _reading()
    for key: String in krita:
        assert_eq(read[key], krita[key], "the %s is Krita's" % key)
    assert_eq(_pressed(), ["krita"] as Array[String], "and Krita is the button pressed")
