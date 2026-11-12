## The preset pictures fill as fast as when each asked the card on its own.
##
## A picture asks the card for its bytes and takes them two frames on,
## and asks for a frame each share so the answer comes. A share then comes once
## a drawn frame rather than once a turn of the loop, and a
## picture waiting on the card or on its tip's file would draw nothing else in its
## frames, because a share was the 4 ms sized for a loop that turned 97 times a
## second. So several pictures are under way, one stroke at a time, and a share
## is half a frame at the rate the window draws.
##
## The suite holds what that adds: a second picture is drawn while the first
## waits on the card or on its tip, only one stroke is ever part way, every
## picture is the one drawn at once, a drop lets go of every picture under way,
## and the share is sized to the frame. A suite runs in one frame, so it draws
## the frames the card answers on itself, through `RenderingServer.force_draw`,
## and turns the tip cache's frames by hand.
extends "res://tests/test_framework.gd"

const ShippedPresetsScript = preload("res://modules/sara-base-modules/stamp-brush/presets/sa_shipped_presets.gd")
const StampSettingsScript = preload("res://modules/sara-base-modules/stamp-brush/stamp_brush_settings.gd")
const StateBrushScript = preload("res://modules/sara-base-modules/stamp-brush/tools/state_brush.gd")
const SaBrushTipScript = preload("res://core/api/tip/sa_brush_tip.gd")

## A picture is a stroke on a real easel, and the answer comes from the main
## device.
const REQUIRES_GPU := true

## A share long enough for every picture of a queue to send its stroke, and one
## short enough that a stroke takes several.
const LONG_SHARE_USEC: int = 1000000
const SHORT_SHARE_USEC: int = 2000

## The most frames a suite draws for one answer.
const MOST_FRAMES: int = 8

## The preset this suite writes with a tip read from a file of its own, so the
## tip cache has it to load whatever an earlier suite left there.
const TIPPED := "Scratch Tip"

static var scratch_dir: String = SaDataRoot.path("test_d14_pictures_under_way")


func before_each() -> void:
    _clear(scratch_dir)
    SaTipCache.shared().forget()


func after_each() -> void:
    SaTipCache.shared().forget()
    _clear(scratch_dir)


## "drawing the next picture's events while the last one waits on the card":
## one share long enough for all of them sends each picture's stroke and asks
## the card, one after another, up to `MOST_UNDER_WAY`, and keeps none of them
## until the card has answered. The next share reads every answer, in the order
## the pictures were queued, and each is the picture drawn at once.
func test_a_second_picture_is_drawn_while_the_first_waits_on_the_card() -> void:
    if RenderingServer.get_rendering_device() == null:
        skip("no main rendering device, which is the only one that answers as a frame is drawn")
        return
    var store := _shipped_store()
    # A picture that needs a second pass is kept after those queued behind it
    # that were finished at their first read. The Spatter climbs the ladder, and
    # the Eraser paints nothing on the empty easel, so it is drawn again over the
    # coloured ground. The Spatter is last so its climb does not hide the rest.
    var names: Array[String] = ["Paint", "Sketch", "Eraser", "Airbrush", "Spatter"]
    var pictures := SaBrushPresetPictures.new()
    var kept: Array[String] = []
    pictures.drawn.connect(func(stored_name: String, _path: String) -> void: kept.append(stored_name))
    pictures.queue(names, store, StateBrushScript, {}, false)
    var asks := SaPresetThumbs.asks
    assert_true(pictures.draw(LONG_SHARE_USEC), "One share leaves pictures to come")
    var most := SaBrushPresetPictures.MOST_UNDER_WAY
    assert_eq(SaPresetThumbs.asks - asks, most, "and asked the card for %d pictures in it" % most)
    assert_eq(pictures._under_way.size(), most, "which are all under way at once")
    assert_true(kept.is_empty(), "and none of them is kept before the card answers")
    for under: SaBrushPresetPictures.UnderWay in pictures._under_way:
        assert_eq(under.drawing.stage, SaPresetThumbs.Drawing.Stage.CARD, "'%s' waits on the card" % under.stored_name)
    _wait_for_the_answers(pictures)
    var waited := SaPresetThumbs.reads_waited
    var at_once := SaPresetThumbs.reads_at_once
    var shares := 0
    while pictures.draw(LONG_SHARE_USEC) and shares < 1000:
        _wait_for_the_answers(pictures)
        shares += 1
    assert_true(shares < 1000, "The pictures are drawn within a thousand shares")
    var in_kept_order: Array[String] = ["Paint", "Sketch", "Airbrush", "Eraser", "Spatter"]
    assert_eq(kept, in_kept_order, "Every picture is kept, those drawn again after those drawn once")
    assert_true(SaPresetThumbs.reads_waited - waited >= most, "each read the card's answer")
    assert_eq(SaPresetThumbs.reads_at_once, at_once, "and none read at once")
    for stored_name: String in names:
        _assert_drawn_at_once(store, stored_name, false)


## A picture whose tip is still loading off the stroke takes no share, and the
## next one is begun and drawn meanwhile. Once the tip is on the card the
## waiting picture is drawn too, and is the picture drawn at once.
func test_a_picture_waiting_for_its_tip_lets_the_next_one_go() -> void:
    var store := _shipped_store()
    _write_tipped(store)
    var pictures := SaBrushPresetPictures.new()
    var kept: Array[String] = []
    pictures.drawn.connect(func(stored_name: String, _path: String) -> void: kept.append(stored_name))
    var names: Array[String] = [TIPPED, "Paint"]
    pictures.queue(names, store, StateBrushScript, {}, false)
    pictures.draw(LONG_SHARE_USEC)
    var cache := SaTipCache.shared()
    assert_eq(pictures._under_way.size(), 2, "Both pictures are under way after one share")
    var tipped: SaBrushPresetPictures.UnderWay = pictures._under_way[0]
    assert_true(cache.is_loading(tipped.tip_path), "the first waiting for its tip")
    assert_eq(tipped.drawing.stage, SaPresetThumbs.Drawing.Stage.START, "with its stroke not begun")
    assert_eq(pictures._under_way[1].drawing.stage, SaPresetThumbs.Drawing.Stage.CARD, "while the second sent its stroke")
    var deadline := Time.get_ticks_msec() + 60000
    while pictures.draw(LONG_SHARE_USEC) and Time.get_ticks_msec() < deadline:
        cache.pump()
        _wait_for_the_answers(pictures)
    var expected: Array[String] = ["Paint", TIPPED]
    assert_eq(kept, expected, "The one that waited for nothing is kept first")
    _assert_drawn_at_once(store, TIPPED, false)
    _assert_drawn_at_once(store, "Paint", false)


## "more than one picture under way" sends one stroke at a time: over a queue of
## strokes, a ladder, an eraser, a tip on a file and the tips of the chooser's
## other view, drawn in short shares with the card answering between them,
## never more than one picture has sent part of its stroke and not asked the
## card, never more than `MOST_UNDER_WAY` are under way, and a picture is under
## way while another sends its stroke. Every picture is the one drawn at once.
func test_one_stroke_at_a_time_and_every_picture_the_one_drawn_at_once() -> void:
    if RenderingServer.get_rendering_device() == null:
        skip("no main rendering device, which is the only one that answers as a frame is drawn")
        return
    var store := _shipped_store()
    _write_tipped(store)
    var names: Array[String] = [TIPPED, "Paint", "Spatter", "Sketch", "Eraser", "Airbrush"]
    var beside_a_stroke := 0
    for as_tip: bool in [false, true]:
        SaTipCache.shared().forget()
        var pictures := SaBrushPresetPictures.new()
        var kept: Array[String] = []
        pictures.drawn.connect(func(stored_name: String, _path: String) -> void: kept.append(stored_name))
        pictures.queue(names, store, StateBrushScript, {}, as_tip)
        var shares := 0
        var most_part_way := 0
        var most_under_way := 0
        var deadline := Time.get_ticks_msec() + 60000
        while pictures.draw(SHORT_SHARE_USEC) and Time.get_ticks_msec() < deadline:
            shares += 1
            var part_way := _part_way(pictures)
            most_part_way = maxi(most_part_way, part_way)
            most_under_way = maxi(most_under_way, pictures._under_way.size())
            if part_way == 1 and pictures._under_way.size() > 1:
                beside_a_stroke += 1
            SaTipCache.shared().pump()
            _wait_for_the_answers(pictures)
        var view := "tips" if as_tip else "strokes"
        assert_eq(kept.size(), names.size(), "Every picture of the %s is kept, over %d shares" % [view, shares])
        assert_eq(most_part_way, 1, "one stroke part way at a time")
        assert_true(most_under_way > 1, "%d pictures under way at the most" % most_under_way)
        assert_true(most_under_way <= SaBrushPresetPictures.MOST_UNDER_WAY, "and never past the cap")
        for stored_name: String in names:
            _assert_drawn_at_once(store, stored_name, as_tip)
    assert_true(beside_a_stroke > 0, "Another picture is under way beside a stroke in %d shares" % beside_a_stroke)


## "a drop lets go of every drawing": a picture waiting for its tip, one part way
## through its stroke and two waiting on the card are all let go at a drop, each
## easel freed, and the card's answers coming after keep nothing.
func test_a_drop_lets_go_of_every_picture_under_way() -> void:
    if RenderingServer.get_rendering_device() == null:
        skip("no main rendering device, which is the only one that answers as a frame is drawn")
        return
    var store := _shipped_store()
    _write_tipped(store)
    var pictures := SaBrushPresetPictures.new()
    var kept: Array[String] = []
    pictures.drawn.connect(func(stored_name: String, _path: String) -> void: kept.append(stored_name))
    var names: Array[String] = [TIPPED, "Paint", "Sketch"]
    pictures.queue(names, store, StateBrushScript, {}, false)
    pictures.draw(0)
    pictures.draw(0)
    var stages := _stages(pictures)
    var expected := [SaPresetThumbs.Drawing.Stage.START, SaPresetThumbs.Drawing.Stage.STROKE]
    assert_eq(stages, expected, "One picture waits for its tip and one is part way through its stroke")
    _assert_dropped(pictures)

    pictures.queue(names, store, StateBrushScript, {}, false)
    pictures.draw(LONG_SHARE_USEC)
    stages = _stages(pictures)
    expected = [SaPresetThumbs.Drawing.Stage.START, SaPresetThumbs.Drawing.Stage.CARD, SaPresetThumbs.Drawing.Stage.CARD]
    assert_eq(stages, expected, "One picture waits for its tip and two on the card")
    _assert_dropped(pictures)
    for i in MOST_FRAMES:
        RenderingServer.force_draw(false)
    assert_true(kept.is_empty(), "and the card's answers coming after keep nothing")


## "a share sized to the frames actually drawn": half a frame's period at the
## display's refresh, or at the engine's cap on frames when that is lower, which
## is the rate the window draws at while it rests.
func test_a_share_is_half_a_frame_at_the_rate_the_window_draws() -> void:
    var resting := Engine.max_fps
    var hertz := SaCursorPrediction.refresh_hz()
    Engine.max_fps = 0
    var uncapped := SaBrushPresetPictures.share_usec()
    Engine.max_fps = 30
    var capped := SaBrushPresetPictures.share_usec()
    Engine.max_fps = 1000
    var above := SaBrushPresetPictures.share_usec()
    Engine.max_fps = resting
    assert_eq(uncapped, int(500000.0 / hertz), "Uncapped, a share is half a frame at the display's %.1f Hz" % hertz)
    assert_eq(capped, 16666, "capped at 30 frames a second, half of a thirtieth")
    assert_eq(above, uncapped, "and a cap above the display's rate leaves it at the display's")


## The shipped presets, the Spatter among them, which climbs the ladder and so
## asks the card once a rung, and the Eraser, which paints nothing.
func _shipped_store() -> SaPresetStore:
    var store := SaPresetStore.new()
    store.dir = scratch_dir.path_join("presets")
    store.install_shipped(StampSettingsScript.new(), ShippedPresetsScript)
    return store


## Saves `TIPPED` into *store*: the Paint preset with its tip a picture written
## into the scratch folder, a disc softening to its edge.
func _write_tipped(store: SaPresetStore) -> void:
    var side := 48
    var disc := Image.create_empty(side, side, false, Image.FORMAT_L8)
    var centre := Vector2(side, side) * 0.5
    for y in side:
        for x in side:
            var reach := 1.0 - Vector2(x + 0.5, y + 0.5).distance_to(centre) / (side * 0.5)
            disc.set_pixel(x, y, Color(clampf(reach, 0.0, 1.0), 0.0, 0.0))
    var path := scratch_dir.path_join("disc.png")
    DirAccess.make_dir_recursive_absolute(scratch_dir)
    disc.save_png(path)
    var settings := store.load_preset("Paint").duplicate(true) as Resource
    var tip: SaBrushTipScript = settings.get("tip")
    tip.image_path = path
    tip.kind = SaBrushTipScript.Kind.IMAGE
    tip.generator = SaDabGeometry.Generator.IMAGE
    assert_eq(store.save_preset(TIPPED, settings), TIPPED, "The preset with a tip of its own is saved")


## Asserts the picture kept of *stored_name* is the one drawn at once, the stroke
## `render` draws or the tip `render_tip` draws when *as_tip* is set.
func _assert_drawn_at_once(store: SaPresetStore, stored_name: String, as_tip: bool) -> void:
    var path := SaPresetThumbs.path_for(store.dir, stored_name, as_tip)
    var kept := Image.load_from_file(path) if FileAccess.file_exists(path) else null
    var settings := store.load_preset(stored_name)
    var whole := (
        SaPresetThumbs.render_tip(StateBrushScript, settings) if as_tip else SaPresetThumbs.render(StateBrushScript, settings)
    )
    assert_true(kept != null and whole != null, "'%s' is kept and drawn at once" % stored_name)
    if kept != null and whole != null:
        assert_eq(kept.get_data(), whole.get_data(), "and the two are one picture, '%s'" % stored_name)


## How many pictures under way have sent part of their stroke and not asked the
## card for it.
func _part_way(pictures: SaBrushPresetPictures) -> int:
    var count := 0
    for under: SaBrushPresetPictures.UnderWay in pictures._under_way:
        var paint := under.drawing._paint
        if paint != null and paint._sent > 0 and paint._asked_at < 0:
            count += 1
    return count


## Where each picture under way stands, oldest first.
func _stages(pictures: SaBrushPresetPictures) -> Array:
    return pictures._under_way.map(func(under: SaBrushPresetPictures.UnderWay) -> int: return under.drawing.stage)


## Drops *pictures* and asserts every easel its pictures under way held is freed.
func _assert_dropped(pictures: SaBrushPresetPictures) -> void:
    var easels: Array[SaEasel] = []
    for under: SaBrushPresetPictures.UnderWay in pictures._under_way:
        easels.append(under.drawing._paint._easel)
    pictures.drop()
    assert_eq(pictures.waiting(), 0, "Dropped, nothing waits")
    for easel: SaEasel in easels:
        assert_false(is_instance_valid(easel), "and every easel under way is freed")
    assert_false(pictures.draw(LONG_SHARE_USEC), "and nothing is drawn")


## Draws frames until every picture under way that asked the card has its answer.
func _wait_for_the_answers(pictures: SaBrushPresetPictures) -> void:
    var frames := 0
    while frames < MOST_FRAMES and _unanswered(pictures) > 0:
        RenderingServer.force_draw(false)
        frames += 1
    assert_eq(_unanswered(pictures), 0, "The card answered within %d frames" % frames)


func _unanswered(pictures: SaBrushPresetPictures) -> int:
    var count := 0
    for under: SaBrushPresetPictures.UnderWay in pictures._under_way:
        var paint := under.drawing._paint
        if paint != null and paint._asked_at >= 0 and not paint._answered:
            count += 1
    return count


func _clear(folder: String) -> void:
    if not DirAccess.dir_exists_absolute(folder):
        return
    for sub: String in DirAccess.get_directories_at(folder):
        _clear(folder.path_join(sub))
    for file_name: String in DirAccess.get_files_at(folder):
        DirAccess.remove_absolute(folder.path_join(file_name))
    DirAccess.remove_absolute(folder)
