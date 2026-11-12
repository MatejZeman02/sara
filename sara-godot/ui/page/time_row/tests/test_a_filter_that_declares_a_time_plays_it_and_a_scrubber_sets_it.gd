## A filter that declares a time plays it, and a scrubber sets it.
##
## The fixture filter's picture is its time: its point kernel writes the
## seconds the record holds into every texel. It is attached to a layer and its
## panel built as the tool options docker builds it, then played for a counted
## number of frames of unequal length, paused, and scrubbed. Each time the
## record's time and the composite are read against the sum of the frames.
##
## A suite cannot await a frame, so a frame here is what `_process` does with
## its duration, the scrubber's `advance`, followed by the dialog's flush, the
## frame boundary the panel's write waits for. The running app's half is
## `scenarios/a-filter-that-declares-a-time-plays-it-and-a-scrubber-sets-it.json`.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")
const Fixtures = preload("res://tests/fixtures.gd")
const TimeFilter = preload("res://tests/fixtures/modules/time-fixture/time_filter.gd")

## The fixture's folder, which the shader index files the time kernel under.
const OWNER: StringName = &"time-fixture"
const KEY: StringName = &"time-fixture.time_fixture"

## Frames as a run at sixty a second has them, with a stutter and a fast one
## among them, so the sum is not the count times one duration.
const FRAMES: Array[float] = [1.0 / 60.0, 1.0 / 60.0, 1.0 / 30.0, 1.0 / 60.0, 0.05, 1.0 / 60.0, 1.0 / 144.0]

## A texel well inside the layer.
const AT := Vector2i(20, 30)

var _easel: SaEasel = null
var _doc: SaDocument = null
var _filters: SaFilterRegistry = null
var _record: SaAttachedFilter = null
var _panel: SaFilterPanel = null


func before_each() -> void:
    _easel = SaEasel.create_default(Vector2i(128, 128))
    _easel.compositor.set_registry(Fixtures.make_registries().blend_modes)
    _filters = SaFilterRegistry.new()
    _filters.register(TimeFilter.new(), OWNER)
    _easel.compositor.filter_chain.registry = _filters
    _doc = _easel.document
    _doc.active_layer.fill(Color(0.25, 0.25, 0.25, 1.0))
    _record = SaFilterOps.new(_doc).attach(_doc.active_layer, KEY, {})
    Bench.composite(_easel)
    _panel = SaFilterPanel.new(_record, _filters.get_filter(KEY), _doc)


func after_each() -> void:
    _panel.free()
    _panel = null
    _easel.free()
    _easel = null
    _doc = null
    _record = null
    _filters = null


func _scrubber() -> SaTimeRow.Scrubber:
    return _panel.find_child(SaTimeRow.Scrubber.NODE_NAME, true, false) as SaTimeRow.Scrubber


## One frame of *seconds*, as the running app has it: the scrubber's step, then
## the frame boundary the panel writes the record at.
func _frame(scrubber: SaTimeRow.Scrubber, seconds: float) -> void:
    scrubber.advance(seconds)
    _panel.dialog.flush_rerun()


func _shown() -> float:
    Bench.composite(_easel)
    return Bench.texel(_easel.output, AT).r


## The record's time. A record attached with no values, as the layers docker's
## menu and the scenario attach one, holds no time until the panel writes one,
## and the chain reads the declaration's nought for it.
func _time() -> float:
    return SaTyped.real(_record.parameters.get(String(SaTimeRow.KEY)), 0.0)


func test_the_panel_shows_a_play_button_a_scrubber_and_the_loop() -> void:
    var scrubber := _scrubber()
    assert_not_null(scrubber, "The panel holds the time row's scrubber")
    if scrubber == null:
        return
    assert_not_null(scrubber.find_child("TimePlay", true, false), "with its play button")
    assert_not_null(scrubber.find_child("TimeSlider", true, false), "and the slider it scrubs with")
    assert_eq(_panel.dialog.widget_name(SaTimeRow.LOOP), "slider", "and the loop length is a slider row under it")
    assert_almost_eq(scrubber.loop_length(), 10.0, 1e-6, "ten seconds long until the painter says otherwise")
    assert_almost_eq(_time(), 0.0, 1e-6, "The time starts at nought")
    assert_almost_eq(_shown(), 0.0, 1e-4, "and the composite is the time the record was drawn at")


func test_the_filter_dialog_plays_the_same_row_into_its_preview() -> void:
    var filter := _filters.get_filter(KEY)
    var dialog := SaDialog.for_filter(filter)
    var page := VBoxContainer.new()
    dialog.realize(page)
    var reruns := [0]
    dialog.rerun.connect(func() -> void: reruns[0] += 1)
    var scrubber := page.find_child(SaTimeRow.Scrubber.NODE_NAME, true, false) as SaTimeRow.Scrubber
    assert_not_null(scrubber, "The filter's dialog holds the scrubber too")
    if scrubber != null:
        scrubber.play(true)
        for seconds: float in FRAMES:
            scrubber.advance(seconds)
            dialog.flush_rerun()
        var played := 0.0
        for seconds: float in FRAMES:
            played += seconds
        var previewed := SaTyped.real(filter.parameter(SaTimeRow.KEY))
        assert_almost_eq(previewed, played, 1e-5, "and playing moves the time the preview runs at")
        assert_eq(reruns[0], FRAMES.size(), "one preview a frame")
    page.free()


func test_playing_moves_the_time_and_the_composite_by_the_frames_duration() -> void:
    var scrubber := _scrubber()
    scrubber.play(true)
    assert_true(scrubber.playing, "The button plays")
    var played := 0.0
    for seconds: float in FRAMES:
        _frame(scrubber, seconds)
        played += seconds
    assert_eq(scrubber.frames, FRAMES.size(), "Every frame moved the time once")
    assert_true(_record.parameters.has(String(SaTimeRow.KEY)), "The record holds a time")
    assert_almost_eq(_time(), played, 1e-5, "The record's time is the frames' duration: %f" % played)
    assert_almost_eq(_shown(), played, 1e-4, "and so is the composite the chain drew it at")

    scrubber.play(false)
    for seconds: float in FRAMES:
        _frame(scrubber, seconds)
    assert_false(scrubber.playing, "Paused")
    assert_almost_eq(_time(), played, 1e-5, "the record's time holds where it stopped")
    assert_almost_eq(_shown(), played, 1e-4, "and so does the composite")


func test_scrubbing_sets_the_time() -> void:
    var scrubber := _scrubber()
    scrubber.slider.set_value_no_signal(2.0)
    scrubber.slider.value_changed.emit(2.0)
    _panel.dialog.flush_rerun()
    assert_almost_eq(scrubber.value, 2.0, 1e-6, "The scrubber holds two seconds")
    assert_almost_eq(_time(), 2.0, 1e-6, "and so does the record")
    assert_almost_eq(_shown(), 2.0, 1e-4, "and the composite reads two")
    scrubber.play(true)
    _frame(scrubber, 0.25)
    assert_almost_eq(_time(), 2.25, 1e-5, "Play goes on from where the scrubber left it")


func test_play_comes_back_round_at_the_loop_length() -> void:
    var loop_row := _panel.dialog.row(SaTimeRow.LOOP)
    loop_row.drive(1.0)
    _panel.dialog.flush_rerun()
    var scrubber := _scrubber()
    assert_almost_eq(scrubber.loop_length(), 1.0, 1e-6, "The loop is one second")
    assert_almost_eq(scrubber.slider.max_value, 1.0, 1e-6, "and the scrubber ends there")
    scrubber.play(true)
    for _frame_index in 5:
        _frame(scrubber, 0.3)
    assert_almost_eq(_time(), 0.5, 1e-5, "One and a half seconds of frames over a one second loop is half a second")
    assert_almost_eq(_shown(), 0.5, 1e-4, "on the canvas too")


func test_the_record_saves_its_time_like_any_parameter() -> void:
    var scrubber := _scrubber()
    scrubber.capture_option_edit({"value": 3.5})
    _panel.dialog.flush_rerun()
    var written := SaSadFile.write_filters([_record] as Array[SaAttachedFilter], PackedByteArray(), GlobalShaderCompiler.get_rd())
    var read := SaSadFile.read_filters(JSON.parse_string(JSON.stringify(written)), PackedByteArray())
    assert_eq(read.size(), 1, "The record comes back from the file")
    var kept := SaTyped.real(read[0].parameters.get(String(SaTimeRow.KEY)), -1.0)
    assert_almost_eq(kept, 3.5, 1e-6, "holding its time")
    assert_almost_eq(SaTyped.real(read[0].parameters.get(String(SaTimeRow.LOOP)), -1.0), 10.0, 1e-6, "and its loop")


func test_flatten_takes_the_picture_at_the_time_showing() -> void:
    var scrubber := _scrubber()
    scrubber.play(true)
    for _frame_index in 3:
        _frame(scrubber, 0.5)
    scrubber.play(false)
    assert_almost_eq(_time(), 1.5, 1e-5, "Paused at one and a half seconds")
    assert_true(SaFilterOps.new(_doc).flatten(_doc.active_layer, _record), "The record flattens")
    var layer := Bench.texel(_doc.active_layer.get_field(Vector2i.ZERO), AT)
    assert_almost_eq(layer.r, 1.5, 1e-4, "and the layer holds the picture at the time showing: %s" % layer)


func test_an_undo_after_play_puts_the_time_back() -> void:
    var scrubber := _scrubber()
    scrubber.play(true)
    for seconds: float in FRAMES:
        _frame(scrubber, seconds)
    scrubber.play(false)
    _doc.undo()
    assert_almost_eq(_time(), 0.0, 1e-6, "A play is one Edit Filter step, and its undo is the time play began at")
    assert_almost_eq(_shown(), 0.0, 1e-4, "on the canvas too")


## Bake in the Filter dialog writes the picture at the time its scrubber shows:
## the dialog is opened on the fixture, played for a few frames and paused, and
## Apply on Bake, the way a fresh dialog opens on, writes that time into the
## layer's pixels with nothing attached.
func test_bake_in_the_dialog_takes_the_picture_at_the_time_showing() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    var was_embedding := tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    var host := Node.new()
    host.name = "K1BakeHost"
    EventBus.add_child(host)
    var canvas := SaCanvas.new()
    canvas.easel = _easel
    var window := SaFilterDialogWindow.new()
    window.target_canvas = canvas
    window.watch(_filters)
    host.add_child(window)

    window.open_filter(KEY)
    var scrubber := window.dialog.row(SaTimeRow.KEY).custom_control as SaTimeRow.Scrubber
    assert_not_null(scrubber, "The dialog holds the time row's scrubber")
    if scrubber != null:
        scrubber.play(true)
        for _frame_index in 3:
            scrubber.advance(0.25)
            window.dialog.flush_rerun()
        scrubber.play(false)
        assert_almost_eq(scrubber.value, 0.75, 1e-5, "Paused at three quarters of a second")
        assert_eq(window.way(), &"bake", "The dialog opens on Bake")
        window.apply_filter()
        assert_true(_doc.active_layer.filters.size() == 1, "Bake attached nothing beside the record already there")
        var layer := Bench.texel(_doc.active_layer.get_field(Vector2i.ZERO), AT)
        assert_almost_eq(layer.r, 0.75, 1e-4, "and the layer holds the picture at the time showing: %s" % layer)

    window.free()
    canvas.free()
    host.free()
    tree.root.gui_embed_subwindows = was_embedding
