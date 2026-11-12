## The canvas on a reference board composites what the window left unshown at
## most every quarter second, the minimap's rate. It flushed on every poll, so a
## fill or a stroke out of the window's reach cost a whole composite a frame
## while the Reference docker showed the canvas.
extends "res://tests/test_framework.gd"


## An easel that counts its flushes rather than compositing.
class CountingEasel:
    extends SaEasel
    var flushes: int = 0

    func flush(_area: Rect2i = Rect2i()) -> void:
        flushes += 1


func _held(easel: SaEasel) -> void:
    var regions: Dictionary[Vector2i, Rect2i] = {Vector2i(9, 9): Rect2i(0, 0, 4, 4)}
    easel.backlog.hold_outside(regions, Rect2(0.0, 0.0, 1.0, 1.0), null)


func test_two_polls_in_one_quarter_second_flush_once() -> void:
    var easel := CountingEasel.new()
    var element := ReferenceCanvasElement.new()
    _held(easel)
    element._flush_now(easel, 10000)
    element._flush_now(easel, 10100)
    assert_eq(easel.flushes, 1, "A second poll a tenth of a second later leaves the backlog held")
    element._flush_now(easel, 10300)
    assert_eq(easel.flushes, 2, "and the poll after the quarter second composites it")
    element.free()
    easel.free()


func test_an_empty_backlog_flushes_nothing() -> void:
    var easel := CountingEasel.new()
    var element := ReferenceCanvasElement.new()
    element._flush_now(easel, 10000)
    assert_eq(easel.flushes, 0, "Nothing held, nothing composited")
    element.free()
    easel.free()
