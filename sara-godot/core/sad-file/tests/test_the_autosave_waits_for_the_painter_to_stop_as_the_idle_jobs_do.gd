## An armed autosave waits the Idle After preference's seconds of quiet, the
## wait every idle job reads, and hears a change of it at the next check.
##
## A painter's answer on the painting statistics made
## the idle time "one shared setting, "idle after", five seconds by default,
## that every idle job reads", and until this row the autosave kept a second of
## its own. The clock is handed to `tick()`, so seconds pass in a call, and a
## save is read off `last_written`, which only a written copy sets.
extends "res://tests/test_framework.gd"

## The autosave writes a `.sad`, which reads every chunk back off the GPU.
const REQUIRES_GPU := true

var _easel: SaEasel = null
var _autosave: SaAutosave = null
var _kept: float = 5.0


func before_each() -> void:
    _kept = SaSettings.idle_after_seconds
    _easel = SaEasel.create_default(Vector2i(128, 128))
    _autosave = SaAutosave.new()
    _autosave.follow_settings = false
    _autosave.interval_seconds = 60.0
    _autosave.attach(_easel.document)
    _easel.add_child(_autosave)


func after_each() -> void:
    _autosave.discard_recovery()
    SaSettings.idle_after_seconds = _kept
    _easel.free()


## Paints, so the document has something to save, and arms the save: the
## whole interval passes at the moment of the last activity, so from here the
## save waits on quiet alone. Answers whether that first check wrote.
func _arm() -> bool:
    _easel.document.fill_layer(Color.RED)
    _autosave.note_activity(0)
    return _autosave.tick(60.0, 0)


func test_set_to_three_it_saves_at_three_seconds_and_not_at_two() -> void:
    SaSettings.idle_after_seconds = 3.0
    assert_false(_arm(), "armed, and the painter has only just stopped")
    assert_false(_autosave.tick(0.0, 2_000), "two seconds of quiet are not three")
    assert_eq(_autosave.last_written, "", "and nothing was written")
    assert_true(_autosave.tick(0.0, 3_000), "at three it saves")
    assert_true(SaSadFile.finish_saves(), "and the save in the background ends")
    assert_true(FileAccess.file_exists(_autosave.last_written), "onto disk")


func test_set_to_seven_it_saves_at_seven_seconds_and_not_at_two() -> void:
    SaSettings.idle_after_seconds = 7.0
    assert_false(_arm(), "armed, and the painter has only just stopped")
    assert_false(_autosave.tick(0.0, 2_000), "two seconds of quiet are not seven")
    assert_false(_autosave.tick(0.0, 6_900), "nor is a tenth short of seven")
    assert_eq(_autosave.last_written, "", "and nothing was written")
    assert_true(_autosave.tick(0.0, 7_000), "at seven it saves")
    assert_true(SaSadFile.finish_saves(), "and the save in the background ends")
    assert_true(FileAccess.file_exists(_autosave.last_written), "onto disk")


func test_a_change_of_the_preference_is_heard_at_the_next_check() -> void:
    SaSettings.idle_after_seconds = 7.0
    assert_false(_arm(), "armed, and the painter has only just stopped")
    assert_false(_autosave.tick(0.0, 3_000), "three seconds are not the seven it was set to")
    SaSettings.idle_after_seconds = 3.0
    assert_true(_autosave.tick(0.0, 3_000), "set to three, the same moment saves, with nothing mirrored first")
    assert_true(SaSadFile.finish_saves(), "and the save in the background ends")


func test_the_autosave_keeps_no_wait_of_its_own() -> void:
    var constants: Dictionary = _autosave.get_script().get_script_constant_map()
    assert_false(constants.has("QUIET_SECONDS"), "the one second constant is gone, the preference is the wait")
