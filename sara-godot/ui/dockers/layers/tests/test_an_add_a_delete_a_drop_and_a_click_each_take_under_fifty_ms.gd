## An add, a delete, a drop and a click on a row each take under fifty
## milliseconds on a stack of thirty layers.
##
## A fold timed on a document of this kind shows the rest: a layer
## added or deleted, a drop of a row and an undo that reorders built every row
## of the stack again, about 2.7 ms a row, and a click on a row folded the
## composite caches over the whole canvas. The rows now go through
## `SaLayerRowReuse`, which builds only a new layer's row, and the activation
## folds only the caches whose layers it moves.
##
## The time read is the operation and the pictures it asks for, which is what
## the frame after it draws, on this stack: a 2160 by 720 document of thirty
## painted layers over the default two, the top four in a group. What
## `SaDocument.update_caches` spends in `SaLayerFold.rebuild` is timed apart
## and taken off, because the fold's own cost per activation is the active-layer suite's, and
## the ceiling here is the rows' share.
extends "res://tests/test_framework.gd"

## The pictures and the caches are compute dispatches, read back here to say
## the rows draw what a rebuild would.
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
var _fold: TimedFold


## The document's fold as it is, which also counts the microseconds each of its
## whole rebuilds takes, so a suite reads the rows' share apart from it.
class TimedFold:
    extends SaLayerFold

    var spent_usec := 0

    func rebuild(document: SaDocument, compositor: SaCompositor, visible_rect: Rect2) -> void:
        var start := Time.get_ticks_usec()
        super.rebuild(document, compositor, visible_rect)
        spent_usec += Time.get_ticks_usec() - start


func before_each() -> void:
    _easel = SaEasel.create_default(DOC_SIZE)
    _easel.compositor.set_registry(Fixtures.make_registries().blend_modes)
    _doc = _easel.document
    _doc.active_layer.name = "Background"
    _doc.fold.release()
    _fold = TimedFold.new()
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


## *act* and the pictures it asks for, less what the fold's whole rebuilds took
## inside it, timed three times and each held to the line. *undo* puts the
## stack back between runs. Answers the bound with its readings.
func _worst(what: String, act: Callable, undo: Callable = Callable()) -> BusyBound:
    var bound := BusyBound.new(LIMIT_MS)
    for _run: int in 3:
        bound.time(what, func() -> float: return _rows_share(act))
        if undo.is_valid():
            undo.call()
            SaLayerList.settle_thumbnails(_docker)
    return bound


## The milliseconds *act* and the pictures it asks for take, less the fold's.
func _rows_share(act: Callable) -> float:
    var folded := _fold.spent_usec
    var start := Time.get_ticks_usec()
    act.call()
    SaLayerList.settle_thumbnails(_docker)
    var spent := Time.get_ticks_usec() - start
    var fold_usec := _fold.spent_usec - folded
    print("probe fold %.1f ms of %.1f ms" % [fold_usec / 1000.0, spent / 1000.0])
    return (spent - fold_usec) / 1000.0


## How many of the list's rows were built since *before*, the rows it held then.
func _built_since(before: Array[SaRowFrame]) -> int:
    var built := 0
    for row: SaRowFrame in _docker.item_list.rows:
        if not before.has(row):
            built += 1
    return built


## A press on row *index* as the list answers a plain one.
func _click(index: int) -> void:
    var list := _docker.item_list
    list.item_selected.emit(list.picked.press(index, false, false, true))


## Every row as the painter sees it, top first: its name, its indent, whether it
## is lit, its place in the list and its picture's texels.
static func _rows(list: SaLayerList) -> Array:
    var out: Array = []
    for i: int in list.rows.size():
        var row: SaRowFrame = list.rows[i]
        var texels := PackedByteArray()
        if row.thumb != null and row.thumb._texture != null:
            texels = GlobalShaderCompiler.get_rd().texture_get_data(row.thumb._texture.rid, 0)
        out.append([row.lbl.text, row.indent_depth, row.lit, row.row_index, row.get_index(), texels])
    return out


static func _pick(list: SaLayerList) -> Array:
    return [list.picked.selected_indices(), list.picked.selected_idx, list.selected_layers()]


## A second docker on the same canvas builds every row whole, which is what the
## rows drawn through the reuse have to read as.
func _assert_as_a_rebuild_draws(what: String) -> void:
    var fresh := LayersDocker.new()
    fresh.target_canvas = _canvas
    fresh.list_keeper.listen()
    fresh.sync_layer_list()
    SaLayerList.settle_thumbnails(fresh)
    SaLayerList.settle_thumbnails(_docker)
    var kept := _rows(_docker.item_list)
    var built := _rows(fresh.item_list)
    assert_eq(kept.size(), built.size(), "after %s, as many rows as a rebuild draws" % what)
    for i: int in mini(kept.size(), built.size()):
        assert_eq(kept[i], built[i], "after %s, row %d reads %s as a rebuild draws it" % [what, i, built[i][0]])
    assert_eq(_pick(_docker.item_list), _pick(fresh.item_list), "after %s, the pick is a rebuild's" % what)
    fresh.free()


func test_an_add_takes_under_fifty_milliseconds() -> void:
    var bound := _worst("An add", func() -> void: SaLayerOps.new(_doc).add(), func() -> void: _doc.undo())
    assert_true(bound.all_held, bound.worst)
    var before: Array[SaRowFrame] = _docker.item_list.rows.duplicate()
    SaLayerOps.new(_doc).add()
    assert_eq(_built_since(before), 1, "an add builds the new layer's row and no other")
    _assert_as_a_rebuild_draws("an add")


func test_a_delete_takes_under_fifty_milliseconds() -> void:
    var bound := _worst(
        "A delete",
        func() -> void: SaLayerOps.new(_doc).remove(_doc.find_child("Paint 10", false, false) as SaLayer),
        func() -> void: _doc.undo()
    )
    assert_true(bound.all_held, bound.worst)
    var before: Array[SaRowFrame] = _docker.item_list.rows.duplicate()
    SaLayerOps.new(_doc).remove(_doc.find_child("Paint 10", false, false) as SaLayer)
    assert_eq(_built_since(before), 0, "a delete builds no row")
    assert_eq(_docker.item_list.rows.size(), before.size() - 1, "and takes the deleted layer's away")
    _assert_as_a_rebuild_draws("a delete")


func test_a_drop_takes_under_fifty_milliseconds() -> void:
    var bound := _worst(
        "A drop",
        func() -> void: _docker.list_keeper.drop(_row_of("Paint 5"), _row_of("Paint 20"), SaLayerList.Drop.ABOVE),
        func() -> void: _doc.undo()
    )
    assert_true(bound.all_held, bound.worst)
    var before: Array[SaRowFrame] = _docker.item_list.rows.duplicate()
    _docker.list_keeper.drop(_row_of("Paint 5"), _row_of("Paint 20"), SaLayerList.Drop.ABOVE)
    assert_eq(_built_since(before), 0, "a drop builds no row")
    assert_eq(_row_of("Paint 5"), _row_of("Paint 20") - 1, "the dropped row stands over its target")
    _assert_as_a_rebuild_draws("a drop")
    _docker.list_keeper.drop(_row_of("Paint 8"), _row_of("Pictures"), SaLayerList.Drop.INTO)
    assert_eq(_docker.item_list.rows[_row_of("Paint 8")].indent_depth, 1, "a row dropped into the group is indented")
    _assert_as_a_rebuild_draws("a drop into a group")


func test_a_click_on_a_row_takes_under_fifty_milliseconds() -> void:
    var names: Array[String] = ["Paint 12", "Paint 2", "Paint 21"]
    var bound := BusyBound.new(LIMIT_MS)
    for layer_name in names:
        var index := _row_of(layer_name)
        bound.time("A click", func() -> float: return _rows_share(func() -> void: _click(index)))
        assert_eq(str(_doc.active_layer.name), layer_name, "the click makes %s active" % layer_name)
    assert_true(bound.all_held, bound.worst)
    _assert_as_a_rebuild_draws("a click")


## The click folds only the caches it moves, and the picture is what a fold of
## every cache draws.
func test_a_click_leaves_the_picture_as_a_whole_rebuild_draws_it() -> void:
    _click(_row_of("Paint 12"))
    _click(_row_of("Paint 25"))
    _click(_row_of("Paint 1"))
    var after_clicks := _picture()
    _doc.update_caches()
    assert_eq(after_clicks, _picture(), "the picture after three clicks is the one a whole rebuild draws")


## The composite's texels, every chunk drawn again from the caches.
func _picture() -> PackedByteArray:
    _easel.request_full_composite()
    _easel.process_pending_composite()
    _easel.flush()
    return GlobalShaderCompiler.get_rd().texture_get_data(_easel.output.rid, 0)
