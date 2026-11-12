## A preset's picture is timed by its own events, not the wall clock.
##
## A picture's stroke read the pen clock between its events, and the clock was
## the wall's, so a brush whose curves read speed painted the pace the picture
## was drawn at. The Bristle Flat's Drift is on speed: two renders of it in one
## run differed by up to 7 levels, and two cold boots of the base kept two files
## 204 texels apart. Each event is now sent with the clock held at the event's
## place in a stroke at sixty a second, `SaPresetThumbs._send`.
##
## The suite holds the row's two asks: the Bristle Flat drawn at once, by shares
## and by shares with frames drawn between is one picture, and so is every
## shipped preset's drawn twice. The second of each pair is drawn a step a call
## with the wall clock moved between the steps, which is the pace a busy
## chooser draws at, so a picture still reading the wall would differ. And it
## holds the clock's own half, a held call reading its time over the pin.
extends "res://tests/test_framework.gd"

const NoisePresetsScript = preload("res://modules/sara-noise-brush-engine/presets/noise_presets.gd")
const NoiseSettingsScript = preload("res://modules/sara-noise-brush-engine/noise_brush_settings.gd")
const ShippedPresetsScript = preload("res://modules/sara-base-modules/stamp-brush/presets/sa_shipped_presets.gd")
const StampSettingsScript = preload("res://modules/sara-base-modules/stamp-brush/stamp_brush_settings.gd")
const StateBrushScript = preload("res://modules/sara-base-modules/stamp-brush/tools/state_brush.gd")
const StateNoiseScript = preload("res://modules/sara-noise-brush-engine/state_noise_brush.gd")

## A picture is a stroke on a real easel.
const REQUIRES_GPU := true

## A frame's share as the presets chooser gives it.
const SHARE_USEC: int = 4000

## How long the wall clock is moved between two steps of a picture drawn a step
## a call, so a picture still reading the wall reads a slower hand than the same
## picture drawn at once.
const STEP_GAP_USEC: int = 2000

## The most frames a share draws for one answer, as the sibling suite has it.
const MOST_FRAMES: int = 8

static var scratch_dir: String = SaDataRoot.path("test_d15_picture_at_any_pace")


func before_each() -> void:
    _clear(scratch_dir)
    SaPenClock.unpin()


func after_each() -> void:
    SaPenClock.unpin()
    _clear(scratch_dir)


## "draws the Bristle Flat's picture at once, by shares, and by shares with
## frames drawn between, and reads all three equal to the byte". Four ways, the
## fourth at once on a pinned clock, which is a capture's, and the same of its
## tip, which is a press and a motion that does not move.
func test_the_bristle_flat_is_one_picture_at_any_pace() -> void:
    var store := _store(NoiseSettingsScript, NoisePresetsScript, "noise")
    var settings := store.load_preset("Bristle Flat")
    assert_not_null(settings, "The Bristle Flat ships")
    if settings == null:
        return
    var at_once := SaPresetThumbs.render(StateNoiseScript, settings)
    assert_not_null(at_once, "It is drawn at once")
    if at_once == null:
        return
    assert_true(SaPresetThumbs._carries_ink(at_once, SaPresetThumbs.VISIBLE_LEVELS), "as a stroke the chooser shows")
    var shares := _in_shares(StateNoiseScript, settings, false, false)
    assert_eq(_gap(at_once, shares), "equal", "Drawn by shares, it is the picture drawn at once")
    var framed := _in_shares(StateNoiseScript, settings, false, true)
    assert_eq(_gap(at_once, framed), "equal", "and by shares with frames drawn between")
    var stepped := _a_step_a_call(StateNoiseScript, settings)
    assert_eq(_gap(at_once, stepped), "equal", "and a step a call with the wall clock moved between")
    SaPenClock.pin_to_frames()
    var pinned := SaPresetThumbs.render(StateNoiseScript, settings)
    SaPenClock.unpin()
    assert_eq(_gap(at_once, pinned), "equal", "and at once on a capture's pinned clock")
    var tip := SaPresetThumbs.render_tip(StateNoiseScript, settings)
    var tip_shares := _in_shares(StateNoiseScript, settings, true, true)
    assert_eq(_gap(tip, tip_shares), "equal", "Its tip drawn by shares with frames between is its tip drawn at once")


## "draws every shipped preset's picture twice and reads each pair equal", the
## stamp's and the noise engine's, the second a step a call with the wall clock
## moved between the steps.
func test_every_shipped_preset_is_one_picture_drawn_twice() -> void:
    var engines: Array[Array] = [
        [StateBrushScript, _store(StampSettingsScript, ShippedPresetsScript, "stamp")],
        [StateNoiseScript, _store(NoiseSettingsScript, NoisePresetsScript, "noise")],
    ]
    var drawn := 0
    var apart: Array[String] = []
    for engine: Array in engines:
        var tool_script: Script = engine[0]
        var store: SaPresetStore = engine[1]
        for preset_name: String in store.list_names():
            var settings := store.load_preset(preset_name)
            var first := SaPresetThumbs.render(tool_script, settings)
            var second := _a_step_a_call(tool_script, settings)
            drawn += 1
            var gap := _gap(first, second)
            if gap != "equal":
                apart.append("%s %s" % [preset_name, gap])
    assert_true(drawn >= 50, "Every shipped preset is drawn, %d of them" % drawn)
    assert_eq(apart, [] as Array[String], "and every one twice is one picture")


## A held call reads its own time whatever the pin and the wall say, a hold
## inside it reads the inner time, and the clock is given back after each.
func test_a_held_call_reads_its_own_time() -> void:
    var times: Array[int] = []
    var inner := func() -> void: times.append(SaPenClock.now_usec())
    var outer := func() -> void:
        times.append(SaPenClock.now_usec())
        SaPenClock.held(SaPenClock.after_frames(7), inner)
        times.append(SaPenClock.now_usec())
    SaPenClock.held(SaPenClock.after_frames(3), outer)
    var three := SaPenClock.PINNED_ORIGIN_USEC + roundi(3.0 * SaPenClock.FRAME_MS * 1000.0)
    var seven := SaPenClock.PINNED_ORIGIN_USEC + roundi(7.0 * SaPenClock.FRAME_MS * 1000.0)
    assert_eq(times, [three, seven, three] as Array[int], "A held call reads its time, and a hold inside it the inner one's")
    var wall := SaPenClock.now_usec()
    assert_true(absi(wall - Time.get_ticks_usec()) < 1_000_000, "After it the clock is the wall's again")
    SaPenClock.pin_to_frames()
    times.clear()
    SaPenClock.held(SaPenClock.after_frames(7), inner)
    assert_eq(times, [seven] as Array[int], "A held time wins over the pin")
    assert_eq(SaPenClock.now_usec(), SaPenClock.PINNED_ORIGIN_USEC, "and the pinned clock reads its own time after")


## *settings*'s stroke, or its tip when *as_tip* is set, drawn a frame's share a
## call as the chooser draws it, the card's answer waited for by drawing frames
## when *frames* is set and read at once otherwise. With *frames* set a frame is
## drawn after every share as well.
func _in_shares(tool_script: Script, settings: Resource, as_tip: bool, frames: bool) -> Image:
    var drawing := SaPresetThumbs.Drawing.cached(tool_script, settings, as_tip)
    var shares := 0
    while not drawing.advance(SHARE_USEC) and shares < 1000:
        shares += 1
        if not frames:
            continue
        RenderingServer.force_draw(false)
        var waited := 0
        while _waits_on_the_card(drawing) and waited < MOST_FRAMES:
            RenderingServer.force_draw(false)
            waited += 1
    assert_true(drawing.done, "A picture drawn by shares is finished, in %d shares" % shares)
    return drawing.picture


## Whether *drawing* has asked the card for its picture and has no answer yet.
func _waits_on_the_card(drawing: SaPresetThumbs.Drawing) -> bool:
    var paint := drawing._paint
    return paint != null and paint.did == SaPresetThumbs.Paint.Did.ASK and not paint._answered


## *settings*'s stroke drawn one step a call, with the wall clock moved
## `STEP_GAP_USEC` between the calls.
func _a_step_a_call(tool_script: Script, settings: Resource) -> Image:
    var drawing := SaPresetThumbs.Drawing.cached(tool_script, settings, false)
    var steps := 0
    while not drawing.advance(0) and steps < 2000:
        steps += 1
        OS.delay_usec(STEP_GAP_USEC)
    assert_true(drawing.done, "A picture drawn a step a call is finished, in %d calls" % steps)
    return drawing.picture


## "equal" when *a* and *b* are the same bytes, and otherwise how many bytes
## differ and by how many levels at the most.
func _gap(a: Image, b: Image) -> String:
    if a == null or b == null:
        return "equal" if a == b else "one of the two is missing"
    var x := a.get_data()
    var y := b.get_data()
    if x == y:
        return "equal"
    if x.size() != y.size():
        return "sizes %d and %d" % [x.size(), y.size()]
    var bytes := 0
    var most := 0
    for i in x.size():
        var level := absi(int(x[i]) - int(y[i]))
        if level > 0:
            bytes += 1
            most = maxi(most, level)
    return "%d bytes apart, up to %d levels" % [bytes, most]


## A store holding the presets *recipes* ships, made from *template*'s script.
func _store(template: Script, recipes: Script, folder: String) -> SaPresetStore:
    var store := SaPresetStore.new()
    store.dir = scratch_dir.path_join(folder)
    store.install_shipped(template.new(), recipes)
    return store


func _clear(folder: String) -> void:
    if not DirAccess.dir_exists_absolute(folder):
        return
    for sub: String in DirAccess.get_directories_at(folder):
        _clear(folder.path_join(sub))
    for file_name: String in DirAccess.get_files_at(folder):
        DirAccess.remove_absolute(folder.path_join(file_name))
    DirAccess.remove_absolute(folder)
