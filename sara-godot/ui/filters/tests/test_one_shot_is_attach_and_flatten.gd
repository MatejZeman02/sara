## The one-shot is an attach and a flatten: Apply in a filter's
## dialog writes the texels the same filter attached and flattened writes, as
## one history step, and still honours the selection it runs under. The window
## is built and never added to the tree, because a `Window` in the tree maps an
## OS window and hangs the offscreen runner, and handed the filter and the
## context `open_filter` would have made.
extends "res://tests/test_framework.gd"

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")
const InvertFilter = preload("res://tests/fixtures/modules/point-fixture/invert_filter.gd")

const REQUIRES_GPU := true

const PAINT := Color(0.25, 0.5, 0.75, 1.0)
const INVERTED := Color(0.75, 0.5, 0.25, 1.0)

var _easel: SaEasel = null
var _doc: SaDocument = null
var _window: SaFilterDialogWindow = null


func before_each() -> void:
    _easel = Bench.easel(Vector2i(512, 512))
    _doc = _easel.document
    _doc.fill_layer(PAINT, _doc.active_layer)
    _window = SaFilterDialogWindow.new()
    Bench.composite(_easel)


func after_each() -> void:
    _window.free()
    _window = null
    _easel.free()
    _easel = null
    _doc = null


func _stored(at: Vector2i) -> Color:
    @warning_ignore("integer_division")
    var grid := Vector2i(at.x / SaChunk.SIZE, at.y / SaChunk.SIZE)
    return Bench.texel(_doc.active_layer.get_field(grid), at - grid * SaChunk.SIZE)


## Presses Apply on the invert's dialog, opened over the active layer the way
## `open_filter` opens it and run once the way it runs on open.
func _apply_through_the_dialog() -> void:
    var filter := InvertFilter.new()
    _window.filter = filter
    _window.context = SaFilterContext.new(_doc, _doc.active_layer, Bench.OWNER, filter.title(), true)
    _window.dialog = SaDialog.new()
    filter.build(_window.dialog)
    _window.dialog.realize(_window._frame.rows)
    _window.dialog.rerun.connect(_window.run_filter)
    _window.dialog.applied.connect(_window.apply_filter)
    _window.dialog.cancelled.connect(_window.cancel_filter)
    _window.run_filter()
    assert_not_null(_window.context.point, "The dialog's run recorded a point pass")
    _window.apply_filter()


func test_apply_writes_what_an_attach_and_a_flatten_write_as_one_step() -> void:
    var steps := _doc.history.step_count()
    _apply_through_the_dialog()
    assert_eq(_doc.history.step_count(), steps + 1, "Apply is one history step")
    assert_true(_doc.active_layer.filters.is_empty(), "and leaves no record behind")
    var one_shot := [_stored(Vector2i(10, 10)), _stored(Vector2i(300, 300))]
    assert_true(_doc.undo(), "which undoes")
    assert_almost_eq(_stored(Vector2i(10, 10)).r, PAINT.r, 1e-5, "back to the paint")

    var ops := SaFilterOps.new(_doc)
    var record := ops.attach(_doc.active_layer, Bench.INVERT)
    assert_true(ops.flatten(_doc.active_layer, record), "The same filter attached flattens")
    var paired := [_stored(Vector2i(10, 10)), _stored(Vector2i(300, 300))]
    for i in one_shot.size():
        var a: Color = one_shot[i]
        var b: Color = paired[i]
        assert_almost_eq(a.r, b.r, 1e-6, "The one-shot and the pair agree, red %d: %s against %s" % [i, a, b])
        assert_almost_eq(a.g, b.g, 1e-6, "green %d" % i)
        assert_almost_eq(a.b, b.b, 1e-6, "blue %d" % i)
        assert_almost_eq(a.a, b.a, 1e-6, "alpha %d" % i)
    assert_almost_eq((one_shot[0] as Color).r, INVERTED.r, 1e-3, "and both are the invert")


func test_apply_still_writes_only_inside_the_selection() -> void:
    _doc.selection.select_rect(Rect2i(0, 0, 128, 128))
    _apply_through_the_dialog()
    assert_almost_eq(_stored(Vector2i(64, 64)).r, INVERTED.r, 1e-3, "Inside the selection the layer is inverted")
    assert_almost_eq(_stored(Vector2i(200, 200)).r, PAINT.r, 1e-5, "outside it in the same chunk it is not")
    assert_almost_eq(_stored(Vector2i(300, 300)).r, PAINT.r, 1e-5, "nor in a chunk the selection leaves out")
