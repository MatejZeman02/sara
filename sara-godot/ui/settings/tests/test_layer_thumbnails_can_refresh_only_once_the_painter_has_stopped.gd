## Thumbnails while painting's third mode, When I stop painting, holds every
## redraw of a layer's picture and the minimap's until the idle clock says the
## painter has stopped, and then draws once.
##
## The clock is the app's own, the autoload `SaIdle` the hold asks, turned to a
## document of the suite's and driven by `tick` so that seconds pass in a call.
## The thumbnail is a real one, counting its redraws, and its `_process` is
## handed the same seconds, which is a frame of the app with the clock ticked
## first as an autoload is.
##
## **Each of the suite's frames is an engine frame of its own.** The pictures
## share [constant SaLayerThumbnail.FRAME_BUDGET_USEC] a frame, keyed by the
## engine's frame count, and a case that never waits runs in the frame the case
## before it ran in. Every case of this suite once ran in one engine frame, so
## the draws of the earlier cases counted against the later ones: a fill drawn
## in 3.5 ms alone was 10 ms in a busy batch, the share was gone, and the seven
## draws after it were refused. So the suite waits out two
## engine frames before each frame of its own, the second because the frame
## after a spent share rests, and stops the autoload's own `_process` for the
## case, so that the frames it waits move neither the clock nor the picture.
## A profile written with each mode before this one
## loads with it unchanged, and the default and the light mode keep theirs.
extends "res://tests/test_framework.gd"

## The picture is a compute pass over the layer's chunks.
const REQUIRES_GPU := true

## One frame of the suite, a second's half, so the five seconds are ten frames.
const FRAME: float = 0.5

static var scratch_path: String = SaDataRoot.path("test_thumbnails_scratch.cfg")


## A layer's picture that counts how often it is drawn, which is what the hold
## is about.
class CountingThumbnail:
    extends SaLayerThumbnail

    var redraws: int = 0

    func refresh() -> void:
        redraws += 1
        super()


var _easel: SaEasel = null
var _thumb: CountingThumbnail = null
var _kept_mode: String = ""
var _kept_document: SaDocument = null
var _kept_seconds: float = 5.0
var _kept_process_mode: Node.ProcessMode = Node.PROCESS_MODE_INHERIT


func before_each() -> void:
    _kept_process_mode = SaIdle.process_mode
    SaIdle.process_mode = Node.PROCESS_MODE_DISABLED
    _kept_mode = SaSettings.thumbnails_while_painting
    _kept_document = SaIdle.document
    _kept_seconds = SaIdle.idle_seconds
    SaSettings.thumbnails_while_painting = SaSettingsPerformance.STOPPED
    _easel = SaEasel.create_default(Vector2i(128, 128))
    SaIdle.follow_settings = false
    SaIdle.follow_main = false
    SaIdle.idle_seconds = 5.0
    SaIdle.attach(_easel.document)
    _thumb = CountingThumbnail.new()
    _thumb.bind_layer(_easel.document.active_layer, _easel.document)


func after_each() -> void:
    SaSettings.thumbnails_while_painting = _kept_mode
    SaIdle.attach(_kept_document if is_instance_valid(_kept_document) else null)
    SaIdle.idle_seconds = _kept_seconds
    SaIdle.follow_settings = true
    SaIdle.follow_main = true
    SaIdle.process_mode = _kept_process_mode
    _thumb.free()
    _easel.free()


## *seconds* of the app, a frame at a time: the clock first, then the picture.
func _run(seconds: float) -> void:
    var left := seconds
    while left > 0.001:
        await _next_frame()
        SaIdle.tick(FRAME)
        _thumb._process(FRAME)
        left -= FRAME


## Waits until the pictures' share of a frame is whole again: one engine frame
## for a share of its own, and a second because the frame after one that spent
## the whole share rests. Counted by the engine's frames and not by the signals,
## because the first `process_frame` a case awaits can be the one of the frame
## it is already in.
func _next_frame() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    var start := Engine.get_process_frames()
    for i in 4:
        if Engine.get_process_frames() >= start + 2:
            return
        await tree.process_frame


func test_a_painted_layer_is_redrawn_once_the_clock_says_the_painter_stopped() -> void:
    await _run(FRAME)
    assert_eq(_thumb.redraws, 1, "the picture bound is drawn at once, as before")
    _easel.document.fill_layer(Color.RED)
    _thumb.mark_dirty()
    await _run(4.5)
    assert_eq(_thumb.redraws, 1, "no redraw in the four and a half seconds before the clock")
    _thumb.settle()
    assert_eq(_thumb.redraws, 1, "and a shot's settle takes none either, so it shows what the painter sees")
    await _run(FRAME)
    assert_eq(_thumb.redraws, 2, "the frame the clock speaks, the painted layer is drawn")
    await _run(10.0)
    assert_eq(_thumb.redraws, 2, "once, and nothing after while nothing moves")
    assert_not_null(_thumb.texture, "and the picture drawn holds the paint")


func test_a_stroke_and_the_pause_after_it_hold_the_redraw() -> void:
    await _run(FRAME)
    _easel.document.stroke_transaction.direct_paint = true
    for i in 20:
        _thumb.mark_dirty()
        await _run(FRAME)
    assert_eq(_thumb.redraws, 1, "ten seconds of a stroke, dirty every frame, and no redraw")
    _easel.document.stroke_transaction.direct_paint = false
    await _run(4.5)
    assert_eq(_thumb.redraws, 1, "nor in the pause after it, which the pen lift would have drawn in")
    await _run(FRAME)
    assert_eq(_thumb.redraws, 2, "five seconds after the stroke it is drawn")


func test_the_pen_lift_still_draws_between_strokes() -> void:
    SaSettings.thumbnails_while_painting = SaSettingsPerformance.PEN_LIFT
    await _run(FRAME)
    _easel.document.fill_layer(Color.RED)
    _thumb.mark_dirty()
    await _run(FRAME)
    assert_eq(_thumb.redraws, 2, "no button is down, so the pen lift draws in the pause")


func test_a_picture_bound_afresh_is_drawn_while_the_hold_stands() -> void:
    await _run(FRAME)
    _easel.document.fill_layer(Color.RED)
    _thumb.mark_dirty()
    await _run(1.0)
    assert_eq(_thumb.redraws, 1, "held")
    # A rebuild of the list makes every row's picture anew, bound to the layer
    # the old one showed.
    var fresh := CountingThumbnail.new()
    fresh.bind_layer(_easel.document.active_layer, _easel.document)
    await _next_frame()
    fresh._process(FRAME)
    assert_eq(fresh.redraws, 1, "a row the list built again shows its picture rather than an empty slot")
    await _next_frame()
    fresh._process(FRAME)
    fresh.mark_dirty()
    await _next_frame()
    fresh._process(FRAME)
    assert_eq(fresh.redraws, 1, "and its next redraw is held like any other")
    fresh.free()


func test_the_hold_follows_the_clock() -> void:
    var stopped := SaSettingsPerformance.STOPPED
    assert_true(SaSettingsPerformance.holds_redraw(stopped), "the wait has just begun")
    SaIdle.tick(5.0)
    assert_false(SaSettingsPerformance.holds_redraw(stopped), "the clock said the painter stopped")
    _easel.document.stroke_transaction.direct_paint = true
    assert_true(SaSettingsPerformance.holds_redraw(stopped), "a stroke open holds before the clock ticks")
    _easel.document.stroke_transaction.direct_paint = false
    SaIdle.tick(FRAME)
    _easel.document.fill_layer(Color.RED)
    assert_true(SaSettingsPerformance.holds_redraw(stopped), "an edit holds again")
    assert_false(SaSettingsPerformance.holds_redraw(SaSettingsPerformance.QUARTER_SECOND), "the quarter never holds")
    SaIdle.attach(null)
    assert_false(SaSettingsPerformance.holds_redraw(stopped), "a clock with no document holds nothing")


func test_the_row_offers_the_mode_third() -> void:
    var page := SaPerformancePage.new()
    page.page.row(&"thumbnails_while_painting").drive(2)
    assert_eq(SaSettings.thumbnails_while_painting, SaSettingsPerformance.STOPPED, "the third entry")
    assert_eq(
        SaSettingsPerformance.label_of(SaSettingsPerformance.THUMBNAIL_MODES, SaSettingsPerformance.STOPPED),
        "When I stop painting",
        "in the painter's words"
    )
    page.free()


func test_the_default_and_the_light_mode_keep_their_modes() -> void:
    assert_eq(
        SaSettingsPerformance.default_values()["thumbnails_while_painting"],
        SaSettingsPerformance.QUARTER_SECOND,
        "a fresh profile redraws every quarter second"
    )
    assert_eq(
        SaSettingsPerformance.light_values()["thumbnails_while_painting"],
        SaSettingsPerformance.PEN_LIFT,
        "and the light mode waits for the pen"
    )


func test_a_profile_stored_with_each_mode_loads_it_unchanged() -> void:
    for mode: String in [SaSettingsPerformance.QUARTER_SECOND, SaSettingsPerformance.PEN_LIFT]:
        assert_eq(_loaded(mode), mode, "a profile stored with %s before this mode" % mode)
    assert_eq(_loaded(SaSettingsPerformance.STOPPED), SaSettingsPerformance.STOPPED, "and one stored with it")
    assert_eq(_loaded(null), SaSettingsPerformance.QUARTER_SECOND, "and one with no key is the quarter")


## The mode a profile holding *stored* loads at, or holding no key when *stored*
## is null, read from a scratch file through `SaSettings.load_settings`, with the
## runner's own file read again afterwards.
func _loaded(stored: Variant) -> String:
    var config := ConfigFile.new()
    config.set_value("meta", "version", SaSettingsMigrations.SETTINGS_VERSION)
    if stored != null:
        config.set_value("performance", "thumbnails_while_painting", stored)
    var path := ProjectSettings.globalize_path(scratch_path)
    var saved_path: String = SaSettings.settings_path
    config.save(path)
    SaSettings.settings_path = path
    SaSettings.load_settings()
    var mode: String = SaSettings.thumbnails_while_painting
    SaSettings.settings_path = saved_path
    SaSettings.load_settings()
    DirAccess.remove_absolute(path)
    return mode
