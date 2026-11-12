## A preset's picture is read back without a frame waiting on the card.
##
## The last step of a picture committed the stroke, composited the easel and
## read it back in one call, and the read waited on the card for every dab the
## stroke sent: 0.7 to 73 ms a picture over two cold boots on a slower machine, and the
## slowest frames after Ready were that step's. The composite is now a step of
## its own, and a frame's share asks the card for the bytes in a later step and
## takes them when a drawn frame hands them back.
##
## The suite holds the two things the row asks: a picture drawn that way is the
## picture drawn at once, byte for byte, and no call both composites and reads
## back. A suite runs in one frame, so it draws the frames the card answers on
## itself, through `RenderingServer.force_draw`, as the GPU timing suites do.
extends "res://tests/test_framework.gd"

const ShippedPresetsScript = preload("res://modules/sara-base-modules/stamp-brush/presets/sa_shipped_presets.gd")
const StampSettingsScript = preload("res://modules/sara-base-modules/stamp-brush/stamp_brush_settings.gd")
const StateBrushScript = preload("res://modules/sara-base-modules/stamp-brush/tools/state_brush.gd")

## A picture is a stroke on a real easel, and the answer comes from the main
## device.
const REQUIRES_GPU := true

## A frame's share as the presets chooser gives it, and one long enough that
## a share which ran on past the composite would have the time to read too.
const SHARE_USEC: int = 4000
const LONG_SHARE_USEC: int = 1000000

## The most frames a suite draws for one answer. The card answers when the frame
## the ask went into comes round again, which is the device's frame delay.
const MOST_FRAMES: int = 8

static var scratch_dir: String = SaDataRoot.path("test_d11_picture_read_later")


func before_each() -> void:
    _clear(scratch_dir)


func after_each() -> void:
    _clear(scratch_dir)


## The shipped presets, the Spatter among them, which climbs the ladder and so
## asks the card once a rung, and the Eraser, which paints nothing.
func _shipped_store() -> SaPresetStore:
    var store := SaPresetStore.new()
    store.dir = scratch_dir.path_join("presets")
    store.install_shipped(StampSettingsScript.new(), ShippedPresetsScript)
    return store


## "a picture drawn the new way equals one drawn at once, pixel for pixel": a
## stroke, a stroke drawn again larger, an eraser's empty stroke and a tip, each
## drawn in shares with every read the card's answer, against the picture
## `render` or `render_tip` draws in one call.
func test_a_picture_drawn_in_shares_is_the_one_drawn_at_once() -> void:
    if RenderingServer.get_rendering_device() == null:
        skip("no main rendering device, which is the only one that answers as a frame is drawn")
        return
    var store := _shipped_store()
    for preset_name: String in ["Paint", "Spatter", "Eraser"]:
        var settings := store.load_preset(preset_name)
        var drawing := SaPresetThumbs.Drawing.cached(StateBrushScript, settings, false)
        var waited := SaPresetThumbs.reads_waited
        var at_once := SaPresetThumbs.reads_at_once
        _draw_in_shares(drawing)
        assert_true(drawing.done and drawing.picture != null, "'%s' is drawn in shares" % preset_name)
        if drawing.picture == null:
            continue
        var answers := SaPresetThumbs.reads_waited - waited
        assert_true(answers > 0, "with its reads the card's answers, %d" % answers)
        assert_eq(SaPresetThumbs.reads_at_once, at_once, "and none of them read at once")
        var whole := SaPresetThumbs.render(StateBrushScript, settings)
        assert_eq(drawing.picture.get_data(), whole.get_data(), "and is the picture render draws, '%s'" % preset_name)
    var tip_settings := store.load_preset("Paint")
    var tip := SaPresetThumbs.Drawing.cached(StateBrushScript, tip_settings, true)
    _draw_in_shares(tip)
    assert_true(tip.done and tip.picture != null, "A tip is drawn in shares")
    if tip.picture != null:
        var tip_whole := SaPresetThumbs.render_tip(StateBrushScript, tip_settings)
        assert_eq(tip.picture.get_data(), tip_whole.get_data(), "and is the tip render_tip draws")


## "no call both composites and reads back": over every step of a picture, read
## in shares and read at once, a step that composites neither asks the card nor
## reads, and a picture is composited once.
func test_no_step_both_composites_and_reads_back() -> void:
    var settings := _shipped_store().load_preset("Paint")
    for at_once: bool in [false, true]:
        var paint := SaPresetThumbs.Paint.new(StateBrushScript, settings, SaPresetThumbs.SIZE * SaPresetThumbs.SUPERSAMPLE, false)
        var composited := 0
        var both := 0
        var calls := 0
        var finished := false
        while not finished and calls < 200:
            var before := _counts()
            finished = paint.step(at_once)
            calls += 1
            var moved := _moved(before)
            composited += moved[0]
            if moved[0] > 0 and moved[1] + moved[2] > 0:
                both += 1
            if moved[0] > 0:
                assert_eq(paint.did, SaPresetThumbs.Paint.Did.COMPOSITE, "The step that composites says so")
                assert_null(paint.image, "and leaves no picture yet")
            if not finished and paint.did == SaPresetThumbs.Paint.Did.ASK:
                _wait_for_the_answer(paint)
        var how := "at once" if at_once else "in shares"
        assert_true(finished and paint.image != null, "A picture read %s is finished, in %d calls" % [how, calls])
        assert_eq(composited, 1, "composited once")
        assert_eq(both, 0, "and no call both composited and read")


## The same of a frame's share: with a share long enough for the whole picture,
## the composite and the ask still end it, and a later share reads, so no frame
## both composites and reads back.
func test_no_share_both_composites_and_reads_back() -> void:
    if RenderingServer.get_rendering_device() == null:
        skip("no main rendering device, which is the only one that answers as a frame is drawn")
        return
    var drawing := SaPresetThumbs.Drawing.cached(StateBrushScript, _shipped_store().load_preset("Paint"), false)
    var shares := 0
    var both := 0
    var composited := 0
    while not drawing.done and shares < 50:
        var before := _counts()
        drawing.advance(LONG_SHARE_USEC)
        shares += 1
        var moved := _moved(before)
        composited += moved[0]
        if moved[0] > 0 and moved[2] > 0:
            both += 1
        if moved[0] > 0:
            assert_eq(moved[1], 1, "The composite's share asks the card too")
        if not drawing.done and drawing._paint.did == SaPresetThumbs.Paint.Did.ASK:
            _wait_for_the_answer(drawing._paint)
    assert_true(drawing.done and drawing.picture != null, "The picture is drawn, in %d shares" % shares)
    assert_eq(composited, 1, "composited once")
    assert_eq(both, 0, "and no share both composited and read")
    assert_true(shares >= 2, "so the strokes and the composite are one share and the read another at the least")


## A share that finds no frame drawn since it asked reads at once, so a caller
## that loops in one frame, the cold start's suite among them, finishes a
## picture rather than waiting on a frame that never comes.
func test_a_read_asked_with_no_frame_drawn_since_is_read_at_once() -> void:
    var settings := _shipped_store().load_preset("Paint")
    var drawing := SaPresetThumbs.Drawing.cached(StateBrushScript, settings, false)
    var at_once := SaPresetThumbs.reads_at_once
    var calls := 0
    while not drawing.advance(0) and calls < 200:
        calls += 1
    assert_true(drawing.done and drawing.picture != null, "The picture is finished in one frame, %d calls" % calls)
    assert_eq(SaPresetThumbs.reads_at_once, at_once + 1, "by one read at once")
    var whole := SaPresetThumbs.render(StateBrushScript, settings)
    assert_eq(drawing.picture.get_data(), whole.get_data(), "and is the picture render draws")


## A picture let go while the card holds its answer frees its easel at once,
## and the answer that comes later finds nobody to hand the bytes to.
func test_a_picture_let_go_while_the_card_answers_frees_its_easel() -> void:
    if RenderingServer.get_rendering_device() == null:
        skip("no main rendering device, which is the only one that answers as a frame is drawn")
        return
    var drawing := SaPresetThumbs.Drawing.cached(StateBrushScript, _shipped_store().load_preset("Paint"), false)
    var shares := 0
    while drawing._paint.did != SaPresetThumbs.Paint.Did.ASK and shares < 100:
        drawing.advance(SHARE_USEC)
        shares += 1
    assert_eq(drawing._paint.did, SaPresetThumbs.Paint.Did.ASK, "The card is asked")
    var easel: SaEasel = drawing._paint._easel
    var asked: WeakRef = weakref(drawing._paint)
    drawing.abandon()
    assert_false(is_instance_valid(easel), "Let go, the easel is freed")
    assert_null(asked.get_ref(), "and so is the picture")
    for i in MOST_FRAMES:
        RenderingServer.force_draw(false)
    assert_true(drawing.done and drawing.picture == null, "The answer coming changes nothing")


## Advances *drawing* a share a call, drawing frames whenever it waits on the
## card, until it is done.
func _draw_in_shares(drawing: SaPresetThumbs.Drawing) -> void:
    var shares := 0
    while not drawing.advance(SHARE_USEC) and shares < 1000:
        shares += 1
        if drawing._paint != null and drawing._paint.did == SaPresetThumbs.Paint.Did.ASK:
            _wait_for_the_answer(drawing._paint)


## Draws frames until *paint* has the card's answer. The engine counts no drawn
## frame for a forced draw, so the step after it reads at once unless the answer
## is already in.
func _wait_for_the_answer(paint: SaPresetThumbs.Paint) -> void:
    var frames := 0
    while not paint._answered and frames < MOST_FRAMES:
        RenderingServer.force_draw(false)
        frames += 1
    assert_true(paint._answered, "The card answered within %d frames" % frames)


## The composites, the asks and the reads so far.
func _counts() -> Array[int]:
    return [
        SaPresetThumbs.composites,
        SaPresetThumbs.asks,
        SaPresetThumbs.reads_waited + SaPresetThumbs.reads_at_once,
    ]


## How far each of `_counts` moved since *before*.
func _moved(before: Array[int]) -> Array[int]:
    var now := _counts()
    return [now[0] - before[0], now[1] - before[1], now[2] - before[2]]


func _clear(folder: String) -> void:
    if not DirAccess.dir_exists_absolute(folder):
        return
    for sub: String in DirAccess.get_directories_at(folder):
        _clear(folder.path_join(sub))
    for file_name: String in DirAccess.get_files_at(folder):
        DirAccess.remove_absolute(folder.path_join(file_name))
    DirAccess.remove_absolute(folder)
