## The Performance page, the light mode that sets it, and the three readers of
## what it sets.
##
## The two main cases are the first two here: the button writes the three and
## moving one afterwards keeps the other two, and a stroke with the frame rate at
## thirty finds the pacer capped rather than uncapped. The rest hold the pieces
## the two stand on, the stored keys, the defaults button and the thumbnails'
## wait for the pen.
##
## The frame rate's default is the display's refresh rate,
## and Uncapped a choice a profile keeps once it is stored, which the cases
## after the light mode's hold through the whole load.
extends "res://tests/test_framework.gd"

static var scratch_path: String = SaDataRoot.path("test_performance_default_scratch.cfg")

const PROPERTIES: Array[String] = [
    "painting_frame_rate",
    "half_size_view_while_moving",
    "thumbnails_while_painting",
    "history_depth",
    "filter_preview_on_canvas",
]

var _before: Dictionary = {}


func before_each() -> void:
    _before.clear()
    for property: String in PROPERTIES:
        _before[property] = SaSettings.get(property)
    SaSettingsPerformance.apply_defaults(SaSettings)


func after_each() -> void:
    for property: String in _before:
        SaSettings.set(property, _before[property])


func test_the_button_writes_the_three_and_a_row_moved_afterwards_keeps_the_others() -> void:
    var page := SaPerformancePage.new()
    page.page.row(&"light_mode").drive(null)

    assert_eq(SaSettings.painting_frame_rate, SaSettingsPerformance.REFRESH, "the frame rate is the display's refresh rate")
    assert_eq(SaSettings.thumbnails_while_painting, SaSettingsPerformance.PEN_LIFT, "the thumbnails wait for the pen")
    assert_eq(SaSettings.history_depth, SaSettingsPerformance.LIGHT_HISTORY_DEPTH, "and the undo depth is lowered")
    assert_false(SaSettings.filter_preview_on_canvas, "and a filter's preview on the canvas starts off")
    var summary := page.find_child("PerformanceSummary", true, false) as Label
    assert_true(summary != null and summary.visible, "a line says what the press changed")
    assert_true(
        summary.text.contains("Half-size view while the canvas moves: On.") and summary.text.contains("Undo steps: 6."),
        summary.text
    )
    assert_false(summary.text.contains("Frame rate"), "and not the frame rate, which a fresh profile already has")
    assert_eq(page.page.row(&"painting_frame_rate").reads(), SaSettingsPerformance.REFRESH, "the rows show it")

    # The frame rate row, moved on its own to thirty, which is its third entry.
    page.page.row(&"painting_frame_rate").drive(2)
    assert_eq(SaSettings.painting_frame_rate, SaSettingsPerformance.THIRTY, "the row moved one setting")
    assert_eq(SaSettings.thumbnails_while_painting, SaSettingsPerformance.PEN_LIFT, "and the thumbnails kept theirs")
    assert_eq(SaSettings.history_depth, SaSettingsPerformance.LIGHT_HISTORY_DEPTH, "and so did the undo depth")
    page.free()


## The undo steps are General's one row, and this page says so in a line rather
## than drawing a second slider that always reads the same.
func test_the_undo_steps_are_a_line_that_points_at_general() -> void:
    var page := SaPerformancePage.new()
    assert_null(page.page.row(&"history_depth"), "no Undo steps row of its own")
    # The sliders the page draws are Idle after and the
    # memory budget, so a third would be the undo steps drawn again.
    assert_eq(page.find_children("*", "HSlider", true, false).size(), 2, "and no slider but Idle after and the budget")
    assert_not_null(page.page.row(&"idle_after_seconds"), "which is a row of its own")
    var note := page.find_child("PerformanceUndoStepsNote", true, false) as Label
    assert_true(note != null and note.visible, "a line stands where the slider was")
    assert_true(
        note != null and note.text.begins_with("Undo steps are set in Preferences > Interface"), note.text if note else ""
    )
    var light := page.page.row(&"light_mode").explanation
    assert_true(light.contains("the frame rate while painting") and light.contains("the undo steps"), light)
    page.free()


## A fresh profile paints at the display's refresh rate, so the light mode
## pressed on one moves the other three and leaves the frame rate where it is.
func test_a_fresh_profile_paints_at_the_displays_refresh_rate() -> void:
    var fresh := SaSettingsValues.new()
    assert_eq(fresh.painting_frame_rate, SaSettingsPerformance.REFRESH, "a fresh profile reads the refresh rate")
    assert_eq(SaSettingsPerformance.default_values()["painting_frame_rate"], SaSettingsPerformance.REFRESH, "as the defaults do")
    var moved := SaSettingsPerformance.apply_light(fresh)
    assert_eq(
        moved,
        (
            ["half_size_view_while_moving", "thumbnails_while_painting", "history_depth", "filter_preview_on_canvas"]
            as Array[String]
        ),
        "the light mode moves four of its five on it"
    )
    fresh.free()


## Through the whole load, so the read is the one a launch makes: a profile
## that stored Uncapped keeps it, one older than the row reads the refresh rate,
## and so does one holding a word the row does not list.
func test_a_stored_uncapped_is_kept_and_anything_else_unstored_reads_the_refresh_rate() -> void:
    assert_eq(_loaded(SaSettingsPerformance.UNCAPPED), SaSettingsPerformance.UNCAPPED, "a stored uncapped is kept")
    assert_eq(_loaded(SaSettingsPerformance.THIRTY), SaSettingsPerformance.THIRTY, "and so is a stored thirty")
    assert_eq(_loaded(null), SaSettingsPerformance.REFRESH, "a profile with no key reads the refresh rate")
    assert_eq(_loaded("fast"), SaSettingsPerformance.REFRESH, "and so does one with a word the row does not list")


func test_pressed_twice_it_says_nothing_changed() -> void:
    var page := SaPerformancePage.new()
    page.press_light()
    page.press_light()
    var summary := page.find_child("PerformanceSummary", true, false) as Label
    assert_true(summary.text.begins_with("The settings for a weak GPU are already in use"), summary.text)
    page.free()


func test_defaults_puts_the_three_back() -> void:
    SaSettingsPerformance.apply_light(SaSettings)
    var page := SaPerformancePage.new()
    page.press_defaults()
    var fresh := SaSettingsValues.new()
    for property: String in PROPERTIES:
        assert_eq(SaSettings.get(property), fresh.get(property), "%s is its default" % property)
    fresh.free()
    page.free()


func test_a_stroke_at_thirty_finds_the_pacer_capped() -> void:
    var previous_fps := Engine.max_fps
    var previous_low := OS.low_processor_usage_mode
    Engine.max_fps = 100
    # Not `_ready`, which asks the window for mailbox vsync: the swapchain that
    # rebuilds loses the timestamps the next suite, `test_gpu_timing`,
    # captures. The resting cap is what `_ready` would have read.
    var pacer := SaFramePacer.new()
    pacer.resting_max_fps = 100
    pacer.resting_low_processor = previous_low

    SaSettings.painting_frame_rate = SaSettingsPerformance.THIRTY
    # A stroke to the pacer is motion frame after frame: the first event takes
    # the resting cap away and the rest keep it away.
    for _i in 20:
        pacer.note_motion()
        pacer._process(0.016)
    assert_true(pacer.is_moving(), "the hand is moving")
    assert_eq(Engine.max_fps, 30, "and the pacer capped at thirty rather than uncapped")
    for _i in SaFramePacer.IDLE_FRAMES:
        pacer._process(0.016)
    assert_eq(Engine.max_fps, 100, "the resting cap comes back when the hand stops")

    SaSettings.painting_frame_rate = SaSettingsPerformance.UNCAPPED
    pacer.note_motion()
    assert_eq(Engine.max_fps, 0, "uncapped, a strong GPU's choice, takes the cap off")
    pacer.rest()

    SaSettingsPerformance.apply_defaults(SaSettings)
    pacer.note_motion()
    var refresh := SaSettingsPerformance.painting_max_fps(SaSettingsPerformance.REFRESH)
    assert_eq(Engine.max_fps, refresh, "and the default caps at the display's refresh rate, %d here" % refresh)

    pacer.free()
    Engine.max_fps = previous_fps
    OS.low_processor_usage_mode = previous_low


func test_the_refresh_rate_resolves_to_a_cap() -> void:
    var fps := SaSettingsPerformance.painting_max_fps(SaSettingsPerformance.REFRESH)
    assert_true(fps > 0, "the display's rate, or sixty where it cannot say, and never uncapped: %d" % fps)
    assert_eq(SaSettingsPerformance.painting_max_fps(SaSettingsPerformance.UNCAPPED), 0, "uncapped is 0")


func test_the_settings_are_stored_and_refuse_what_they_do_not_list() -> void:
    assert_eq(SaSettingsKeys.place_of(&"painting_frame_rate"), ["performance", "painting_frame_rate"], "under performance")
    assert_eq(SaSettingsKeys.place_of(&"thumbnails_while_painting"), ["performance", "thumbnails_while_painting"], "beside it")
    SaSettings.painting_frame_rate = "fast"
    assert_eq(SaSettings.painting_frame_rate, SaSettingsPerformance.REFRESH, "a rate the row does not list is the refresh rate")
    SaSettings.thumbnails_while_painting = "never"
    assert_eq(SaSettings.thumbnails_while_painting, SaSettingsPerformance.QUARTER_SECOND, "and a mode is the quarter")


func test_a_thumbnail_waits_for_the_pen_only_when_asked() -> void:
    assert_false(SaSettingsPerformance.holds_redraw(SaSettingsPerformance.PEN_LIFT), "no button is down, so nothing waits")
    Input.parse_input_event(_button(true))
    Input.flush_buffered_events()
    assert_true(SaSettingsPerformance.holds_redraw(SaSettingsPerformance.PEN_LIFT), "the pen is down and the row asks")
    assert_false(SaSettingsPerformance.holds_redraw(SaSettingsPerformance.QUARTER_SECOND), "the quarter never waits")
    Input.parse_input_event(_button(false))
    Input.flush_buffered_events()
    assert_false(SaSettingsPerformance.holds_redraw(SaSettingsPerformance.PEN_LIFT), "and the lift lets it go")


## Performance sits between Files and Recorder, the Timelapse page that was,
## in the group about the files and the machine.
func test_the_page_is_registered_between_files_and_the_recorder() -> void:
    var at := SaSettingsWindow.FIXED_PAGES.find("Performance")
    assert_eq(SaSettingsWindow.FIXED_PAGES[at - 1], "Files", "Performance follows Files")
    assert_eq(SaSettingsWindow.FIXED_PAGES[at + 1], "Recorder", "and comes before the Recorder")


## The frame rate a profile holding *stored* loads at, or holding no key when
## *stored* is null, read from a scratch file through `SaSettings.load_settings`.
## The runner's own file is read again afterwards, so every other value the
## scratch profile loaded is the runner's once more.
func _loaded(stored: Variant) -> String:
    var config := ConfigFile.new()
    config.set_value("meta", "version", SaSettingsMigrations.SETTINGS_VERSION)
    if stored != null:
        config.set_value("performance", "painting_frame_rate", stored)
    var path := ProjectSettings.globalize_path(scratch_path)
    var saved_path: String = SaSettings.settings_path
    config.save(path)
    SaSettings.settings_path = path
    SaSettings.load_settings()
    var rate: String = SaSettings.painting_frame_rate
    SaSettings.settings_path = saved_path
    SaSettings.load_settings()
    DirAccess.remove_absolute(path)
    return rate


func _button(pressed: bool) -> InputEventMouseButton:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = pressed
    event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
    return event
