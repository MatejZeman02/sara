## A sweep scratches the coat off under the pen however fast it goes.
##
## The old strip painted a recording by the share of two seconds spent, so a
## quick stroke painted a short band and a slow one ran past the pen. Now the
## pen's own events reach the block's `_gui_input`, and each is joined to the
## last by the round tip swept between them, so a flick of a tenth of a second
## and a sweep of three seconds both leave the block clear under every point
## the pen passed, across its whole height, and touch nothing outside it.
extends "res://tests/test_framework.gd"

## How often the pen reports, in seconds, as an Intuos streams.
const EVENT_SECONDS := 0.008

var _dialog: SaTabletSweepDialog = null


func before_each() -> void:
    _dialog = SaTabletSweepDialog.new()
    _dialog.size_strips_for_host(1080.0)


func after_each() -> void:
    _dialog.free()
    _dialog = null


## One sweep of *seconds* across strip *index*, as the pen's own motion events
## at the Intuos's rate, swaying a fifth of the block's thickness off its
## middle, from just before the dot to just past the far end. Returns where the
## pen was at each event.
func _sweep(index: int, seconds: float) -> PackedVector2Array:
    var strip: SaTabletSweepStrip = _dialog._strips[index]
    var events := maxi(int(round(seconds / EVENT_SECONDS)), 2)
    var sway := strip.size.y * 0.2
    var path := PackedVector2Array()
    for i in range(events):
        var t := float(i) / float(events - 1)
        var at := Vector2(lerpf(-4.0, strip.size.x + 4.0, t), strip.size.y * 0.5 + sin(t * TAU * 2.0) * sway)
        var motion := InputEventMouseMotion.new()
        motion.position = at
        motion.pressure = lerpf(0.05, 0.6, t)
        motion.button_mask = MOUSE_BUTTON_MASK_LEFT
        strip._gui_input(motion)
        path.append(at)
    var lift := InputEventMouseButton.new()
    lift.button_index = MOUSE_BUTTON_LEFT
    lift.pressed = false
    strip._gui_input(lift)
    return path


## The coat at every pixel of the block, and how many pixels of it are still
## whole.
func _whole(strip: SaTabletSweepStrip) -> int:
    var left := 0
    for y in range(int(strip.size.y)):
        for x in range(int(strip.size.x)):
            if strip.scratched_at(Vector2(x, y)) < 0.5:
                left += 1
    return left


func _cleared_under(strip: SaTabletSweepStrip, path: PackedVector2Array, label: String) -> void:
    var missed := 0
    for i in range(1, path.size()):
        for step in range(9):
            var at := path[i - 1].lerp(path[i], float(step) / 8.0)
            var inside := at.clamp(Vector2.ZERO, strip.size - Vector2.ONE)
            if strip.scratched_at(inside) < 0.99:
                missed += 1
    assert_eq(missed, 0, "%s: the coat is off under every point the pen passed" % label)
    assert_eq(_whole(strip), 0, "%s: and off the block's whole length and height" % label)


func test_a_flick_of_a_tenth_of_a_second_clears_the_block() -> void:
    var path := _sweep(0, 0.1)
    assert_true(path.size() <= 13, "A tenth of a second is a dozen events, %d here" % path.size())
    _cleared_under(_dialog._strips[0], path, "A tenth of a second")


func test_a_sweep_of_three_seconds_clears_the_block() -> void:
    var path := _sweep(1, 3.0)
    _cleared_under(_dialog._strips[1], path, "Three seconds")


func test_the_two_speeds_record_the_same_sweep() -> void:
    _sweep(0, 0.1)
    _sweep(1, 3.0)
    var quick: PackedVector2Array = _dialog.sweeps[0]
    var slow: PackedVector2Array = _dialog.sweeps[1]
    assert_eq(quick[0].x, 0.0, "Both start at the dot")
    assert_eq(slow[0].x, 0.0, "")
    assert_eq(quick[quick.size() - 1].x, 1.0, "and end at the far end")
    assert_eq(slow[slow.size() - 1].x, 1.0, "")
    assert_true(_dialog.counted[0] and _dialog.counted[1], "and both count, being against place and not time")


func test_nothing_outside_the_swept_block_is_touched() -> void:
    _sweep(0, 0.1)
    for index: int in [1, 2]:
        var other: SaTabletSweepStrip = _dialog._strips[index]
        assert_eq(_whole(other), int(other.size.x) * int(other.size.y), "Block %d's coat is whole" % index)
    var strip: SaTabletSweepStrip = _dialog._strips[0]
    assert_eq(strip.scratched_at(Vector2(-1.0, strip.size.y * 0.5)), -1.0, "The coat is the block's own size")
    assert_eq(strip.scratched_at(Vector2(strip.size.x + 1.0, 0.0)), -1.0, "and no wider")
    assert_eq(strip.scratched_at(Vector2(4.0, strip.size.y + 1.0)), -1.0, "nor taller")


## Pressure does not change how much coat comes off: a feather of a sweep
## clears what a hard one does.
func test_pressure_does_not_change_how_much_coat_comes_off() -> void:
    var strip: SaTabletSweepStrip = _dialog._strips[2]
    _dialog.begin_sweep(2)
    for i in range(40):
        _dialog.feed(2, float(i) / 39.0, 0.01)
    assert_eq(_whole(strip), 0, "A sweep at a hundredth of full clears the block")
