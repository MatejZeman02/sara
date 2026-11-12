## Making a layer active costs no full fold of the stack until a stroke or an
## idle frame needs the caches.
##
## The Layers docker's rows are cheap, but the fold was left: a click on a row,
## an add, a drop and a delete each made a layer active, and the activation
## folded every cache at once, 65 to 76 ms on a stack of thirty layers and twice that for a
## delete. Now an activation owes the fold. The walk keeps drawing around the
## layer it was built on, a change of the stack is paid by the composite that
## draws it, and the rest by an idle frame or a stroke's press.
##
## The stack is the one the row timing suite builds: a 2160 by 720 document of thirty
## painted layers over the default two, the top four in a group. The time read
## is the whole edit and the row pictures it asks for, with nothing taken off.
extends "res://tests/test_framework.gd"

## The pictures and the caches are compute dispatches, read back here.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const BusyBound = preload("res://tests/fixtures/busy_bound.gd")

const DOC_SIZE := Vector2i(2160, 720)
const PAINT_LAYERS := 30
const MEMBERS := 4

## The ceiling the row sets on a quiet machine, in milliseconds, moved by
## `BusyBound` when the machine is busy.
const LIMIT_MS := 50.0

var _easel: SaEasel
var _doc: SaDocument
var _canvas: SaCanvas
var _docker: LayersDocker
var _fold: CountedFold


## The document's fold as it is, counting its whole rebuilds.
class CountedFold:
    extends SaLayerFold

    var rebuilds := 0

    func rebuild(document: SaDocument, compositor: SaCompositor, visible_rect: Rect2) -> void:
        rebuilds += 1
        super.rebuild(document, compositor, visible_rect)


func before_each() -> void:
    _easel = SaEasel.create_default(DOC_SIZE)
    _easel.compositor.set_registry(Fixtures.make_registries().blend_modes)
    _doc = _easel.document
    _doc.active_layer.name = "Background"
    _doc.fold.release()
    _fold = CountedFold.new()
    _fold.debt.quiet_msec = 0
    _doc.fold = _fold
    _doc.update_caches()
    var members: Array[SaLayer] = []
    for i: int in PAINT_LAYERS:
        var layer := SaLayerOps.new(_doc).add()
        layer.name = "Paint %d" % i
        _doc.fill_layer(Color(float(i) / PAINT_LAYERS, 0.4, 0.2, 1.0), layer)
        if i >= PAINT_LAYERS - MEMBERS:
            members.append(layer)
    SaLayerOps.new(_doc).group_layers(members).name = "Pictures"
    _canvas = SaCanvas.new()
    _canvas.easel = _easel
    _docker = LayersDocker.new()
    _docker.target_canvas = _canvas
    _docker.list_keeper.listen()
    _docker.sync_layer_list()
    _docker.list_keeper.select_row(_row_of("Paint 3"))
    SaLayerList.settle_thumbnails(_docker)
    _doc.update_caches()
    _truth()


func after_each() -> void:
    _docker.free()
    _canvas.free()
    _easel.free()
    _doc = null


func _row_of(layer_name: String) -> int:
    for i: int in _docker.item_list.rows.size():
        var layer: SaLayer = _docker.item_list.layer_at(i)
        if layer != null and str(layer.name) == layer_name:
            return i
    return -1


## A press on row *index* as the list answers a plain one.
func _click(index: int) -> void:
    var list := _docker.item_list
    list.item_selected.emit(list.picked.press(index, false, false, true))


## The milliseconds *act* and the row pictures it asks for take, whole.
func _whole(act: Callable) -> float:
    var start := Time.get_ticks_usec()
    act.call()
    SaLayerList.settle_thumbnails(_docker)
    return (Time.get_ticks_usec() - start) / 1000.0


## The canvas as the next frame leaves it: what is dirty composited, nothing
## asked of the whole canvas.
func _screen() -> PackedByteArray:
    _easel.process_pending_composite()
    _easel.flush()
    return GlobalShaderCompiler.get_rd().texture_get_data(_easel.output.rid, 0)


## The canvas a full `update_caches` and a composite of every chunk draw.
func _truth() -> PackedByteArray:
    _doc.update_caches()
    _easel.request_full_composite()
    return _screen()


## *act* under fifty milliseconds whole on a quiet machine, the fold owed after it and paid by
## one idle frame, and the canvas that frame draws the one a full
## `update_caches` draws.
func _step(what: String, act: Callable) -> void:
    var folds := _fold.rebuilds
    var bound := BusyBound.new(LIMIT_MS)
    bound.time(what, func() -> float: return _whole(act))
    assert_true(bound.all_held, bound.worst)
    assert_eq(_fold.rebuilds, folds, "%s folds nothing" % what)
    assert_true(_fold.debt.is_owed(), "and leaves the caches stale")
    _fold.debt.frame()
    assert_false(_fold.debt.is_owed(), "one idle frame after %s pays the fold" % what)
    assert_true(_fold.reads_as_built(_doc), "and the walk is built around %s" % _doc.active_layer.name)
    assert_eq(_fold.rebuilds, folds + 1, "once")
    var shown := _screen()
    assert_eq(shown, _truth(), "after %s the canvas is the one a full update_caches draws" % what)


func test_a_click_an_add_a_drop_and_a_delete_each_fold_nothing_until_an_idle_frame() -> void:
    _step("a click", func() -> void: _click(_row_of("Paint 12")))
    _step("an add", func() -> void: SaLayerOps.new(_doc).add())
    _step("a drop", func() -> void: _docker.list_keeper.drop(_row_of("Paint 5"), _row_of("Paint 20"), SaLayerList.Drop.ABOVE))
    _step("a delete", func() -> void: SaLayerOps.new(_doc).remove(_doc.find_child("Paint 10", false, false) as SaLayer))
    _step("a delete of the active layer", func() -> void: SaLayerOps.new(_doc).remove(_doc.active_layer))


## A click changes nothing on the canvas, so the frame after it composites
## nothing and folds nothing, and the canvas it leaves is the true one.
func test_the_frame_after_a_click_draws_nothing_and_shows_the_true_picture() -> void:
    var folds := _fold.rebuilds
    _click(_row_of("Paint 12"))
    _click(_row_of("Paint 25"))
    _click(_row_of("Paint 1"))
    var shown := _screen()
    assert_eq(_fold.rebuilds, folds, "three clicks and their frame fold nothing")
    assert_true(_fold.debt.is_owed(), "and the fold is still owed")
    assert_eq(shown, _truth(), "and the canvas is the one a full update_caches draws")


## A second activation before the fold only moves the mark, and a click back
## to the layer the walk was built on owes nothing at all.
func test_a_second_activation_moves_the_mark_and_a_click_back_pays_nothing() -> void:
    var folds := _fold.rebuilds
    _click(_row_of("Paint 12"))
    _click(_row_of("Paint 25"))
    _fold.debt.frame()
    assert_eq(_fold.rebuilds, folds + 1, "two clicks and an idle frame fold once")
    _click(_row_of("Paint 3"))
    _click(_row_of("Paint 25"))
    _fold.debt.frame()
    assert_eq(_fold.rebuilds, folds + 1, "a click away and back folds nothing")


## The composite that draws a changed stack pays the fold when no idle frame
## came first, and a delete of the active layer folds once, where it folded
## twice.
func test_a_delete_folds_once_at_the_composite_that_draws_it() -> void:
    var folds := _fold.rebuilds
    SaLayerOps.new(_doc).remove(_doc.active_layer)
    SaLayerList.settle_thumbnails(_docker)
    assert_eq(_fold.rebuilds, folds, "the delete folds nothing")
    var start := Time.get_ticks_usec()
    var shown := _screen()
    print("probe the composite after a delete, its fold in it, %.1f ms" % ((Time.get_ticks_usec() - start) / 1000.0))
    assert_eq(_fold.rebuilds, folds + 1, "the composite after it folds once")
    _fold.debt.frame()
    assert_eq(_fold.rebuilds, folds + 1, "and the idle frame has nothing left to pay")
    assert_eq(shown, _truth(), "and the canvas is the one a full update_caches draws")


## A frame with a button held, or before the quiet time is up, is no idle frame.
func test_a_frame_is_idle_only_after_the_quiet_time() -> void:
    _fold.debt.quiet_msec = 60000
    _click(_row_of("Paint 12"))
    assert_false(_fold.debt.idle_now(), "a frame straight after the click is not idle")
    _fold.debt.quiet_msec = 0
    assert_true(_fold.debt.idle_now(), "and one past the quiet time is")
