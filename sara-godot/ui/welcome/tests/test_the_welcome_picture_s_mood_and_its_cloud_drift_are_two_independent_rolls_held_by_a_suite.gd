## The welcome picture's mood and its cloud drift are two rolls of their own,
## drawn one after the other at each opening, so a clear day picked by a mood
## under a half drifts across the whole strip and not only its first half.
##
## Each seed is set before a bare `WelcomePicture` is built, whose constructor
## runs `_show_now`, so a change that makes `drift` read `mood_roll` or roll from
## it shows here as two rolls tied over the seeds.
extends "res://tests/test_framework.gd"

## A folder with no pictures, so the band builds with no lights and no overlays
## and only rolls.
const NOWHERE := "res://ui/welcome/no-such-folder/"

## How many seeds the suite reads, and the fewest of them whose two rolls may
## differ. Two independent draws of `randf` are equal for none of them.
const SEEDS: int = 300
const DIFFERING: int = 290


## The mood and drift rolls of a bare band built under seed *at*.
func _rolls_at(at: int) -> Vector2:
    seed(at)
    var band := WelcomePicture.new("0.1.0", NOWHERE)
    var rolls := Vector2(band.mood_roll, band.drift)
    band.free()
    return rolls


## Runs *body* with `SARA_WELCOME_ROLL` set to *value*, or cleared when it is
## empty, and puts the variable back as it found it.
func _with_roll(value: String, body: Callable) -> void:
    var had := OS.has_environment(PictureOverlays.ROLL_VARIABLE)
    var before := OS.get_environment(PictureOverlays.ROLL_VARIABLE)
    if value.is_empty():
        OS.unset_environment(PictureOverlays.ROLL_VARIABLE)
    else:
        OS.set_environment(PictureOverlays.ROLL_VARIABLE, value)
    body.call()
    if had:
        OS.set_environment(PictureOverlays.ROLL_VARIABLE, before)
    else:
        OS.unset_environment(PictureOverlays.ROLL_VARIABLE)


func test_the_mood_and_the_drift_differ_for_most_seeds_and_the_drift_spans_its_range_in_each_half_of_the_mood() -> void:
    var had := OS.has_environment(PictureOverlays.ROLL_VARIABLE)
    var before := OS.get_environment(PictureOverlays.ROLL_VARIABLE)
    _with_roll(
        "",
        func() -> void:
            var differing := 0
            # The drift's lowest and highest, among the moods under a half and
            # among those at or over it.
            var under := Vector2(1.0, 0.0)
            var over := Vector2(1.0, 0.0)
            var under_count := 0
            for at in SEEDS:
                var rolls := _rolls_at(at)
                if not is_equal_approx(rolls.x, rolls.y):
                    differing += 1
                if rolls.x < 0.5:
                    under_count += 1
                    under = Vector2(minf(under.x, rolls.y), maxf(under.y, rolls.y))
                else:
                    over = Vector2(minf(over.x, rolls.y), maxf(over.y, rolls.y))
            var said := "the two rolls differ for %d of %d seeds, at least %d" % [differing, SEEDS, DIFFERING]
            assert_true(differing >= DIFFERING, said)
            assert_true(
                under_count > 0 and under_count < SEEDS, "the moods fall either side of a half, %d under it" % under_count
            )
            said = "a mood under a half drifts in both halves, %.3f to %.3f" % [under.x, under.y]
            assert_true(under.x < 0.5 and under.y >= 0.5, said)
            said = "a mood at or over a half drifts in both halves, %.3f to %.3f" % [over.x, over.y]
            assert_true(over.x < 0.5 and over.y >= 0.5, said)
    )
    assert_eq(OS.has_environment(PictureOverlays.ROLL_VARIABLE), had, "the roll variable is set or not as the suite found it")
    assert_eq(OS.get_environment(PictureOverlays.ROLL_VARIABLE), before, "and holds what it held")


func test_a_fixed_roll_answers_both_rolls_and_the_variable_is_left_as_found() -> void:
    if not OS.is_debug_build():
        assert_true(true, "a release build fixes no roll")
        return
    var had := OS.has_environment(PictureOverlays.ROLL_VARIABLE)
    var before := OS.get_environment(PictureOverlays.ROLL_VARIABLE)
    _with_roll(
        "0.37",
        func() -> void:
            for at: int in [1, 2, 3]:
                var rolls := _rolls_at(at)
                assert_almost_eq(rolls.x, 0.37, 0.0001, "the mood is the fixed roll under seed %d" % at)
                assert_almost_eq(rolls.y, 0.37, 0.0001, "and so is the drift")
    )
    assert_eq(OS.has_environment(PictureOverlays.ROLL_VARIABLE), had, "the roll variable is set or not as the suite found it")
    assert_eq(OS.get_environment(PictureOverlays.ROLL_VARIABLE), before, "and holds what it held")
