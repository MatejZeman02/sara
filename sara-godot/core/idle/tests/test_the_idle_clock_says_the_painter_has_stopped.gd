## The idle clock fires once, the Idle After preference's seconds after the last
## edit, and for nothing a pan or a zoom does.
##
## The clock's time is handed to `tick()`, so seconds pass in a
## call. The document is a real one: a fill is an edit through the history, and
## a zoom is what the zoom tool does to it, `invalidate_all_allocated_chunks`,
## which announces `chunks_invalidated` and is not an edit.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

var _easel: SaEasel = null
var _clock: SaIdleClock = null
var _heard: int = 0
var _kept: float = 5.0


func before_each() -> void:
    _kept = SaSettings.idle_after_seconds
    _easel = SaEasel.create_default(Vector2i(128, 128))
    _clock = SaIdleClock.new()
    _clock.follow_settings = false
    _clock.follow_main = false
    _clock.idle_seconds = 5.0
    _clock.attach(_easel.document)
    _heard = 0
    _clock.stopped.connect(func() -> void: _heard += 1)


func after_each() -> void:
    SaSettings.idle_after_seconds = _kept
    _clock.free()
    _easel.free()


func test_it_fires_once_the_seconds_after_the_last_edit() -> void:
    assert_false(_clock.tick(4.9), "not before the seconds")
    assert_true(_clock.tick(0.1), "at five seconds, it says so")
    assert_eq(_heard, 1, "and it was heard once")


func test_it_is_not_said_again_until_the_next_edit() -> void:
    _clock.tick(5.0)
    assert_false(_clock.tick(60.0), "a minute more says nothing")
    assert_eq(_heard, 1, "still one")
    _easel.document.fill_layer(Color.RED)
    assert_false(_clock.tick(4.0), "the edit starts the wait again")
    assert_true(_clock.tick(1.0), "and five seconds later it is said again")
    assert_eq(_heard, 2, "twice in all")


func test_edits_closer_together_than_the_seconds_never_fire_it() -> void:
    for i in 20:
        _easel.document.fill_layer(Color(float(i) / 20.0, 0.0, 0.0))
        assert_false(_clock.tick(4.0), "an edit every four seconds, edit %d" % i)
    assert_eq(_heard, 0, "never heard")


func test_a_zoom_and_a_pan_are_not_edits() -> void:
    _clock.tick(3.0)
    _easel.document.invalidate_all_allocated_chunks()
    assert_true(_clock.tick(2.0), "a zoom does not restart the wait, so it fires at five seconds in all")
    assert_eq(_heard, 1, "once")


func test_a_stroke_open_holds_it_off() -> void:
    _easel.document.stroke_transaction.direct_paint = true
    assert_false(_clock.tick(30.0), "no matter how long the stroke is down")
    _easel.document.stroke_transaction.direct_paint = false
    assert_false(_clock.tick(4.0), "and the wait starts from the stroke's end")
    assert_true(_clock.tick(1.0), "then fires")


func test_an_undo_is_an_edit() -> void:
    _easel.document.fill_layer(Color.RED)
    _clock.tick(1.0)
    _easel.document.undo()
    assert_false(_clock.tick(4.0), "an undo restarts the wait")
    assert_true(_clock.tick(1.0), "and it fires five seconds after it")


func test_the_preference_sets_the_seconds() -> void:
    _clock.follow_settings = true
    SaSettings.idle_after_seconds = 2.0
    _clock._process(1.9)
    assert_eq(_heard, 0, "with the preference at 2 s it has not fired at 1.9")
    _clock._process(0.1)
    assert_eq(_heard, 1, "and fires at 2 s")


func test_the_preference_defaults_to_five_and_stays_between_its_bounds() -> void:
    var bare := SaSettingsValues.new()
    assert_eq(bare.idle_after_seconds, 5.0, "five seconds by default")
    bare.idle_after_seconds = 0.0
    assert_eq(bare.idle_after_seconds, SaSettingsIdle.MIN_IDLE_SECONDS, "never under the least")
    bare.idle_after_seconds = 9000.0
    assert_eq(bare.idle_after_seconds, SaSettingsIdle.MAX_IDLE_SECONDS, "never over the most")
    bare.free()
