## A shown or hidden layer is drawn when its fold is paid, whichever build
## pays it.
##
## A click on a layer's eye owes its fold and holds the picture until the last
## of it is paid, when `SaFoldDebt` draws it. A build of the fold the debt did
## not start, a refold that finds the walk moved for instance, paid the debt
## and left the picture held. Nothing drew it then, and the next press, which
## settles the debt, drew every chunk the walk reads.
##
## Two easels are built alike, a 1024 by 512 document of twelve layers
## painted at half cover, so hiding one shows.
## The one under test is in the tree, which is what lets a debt wait for the
## frames after the click, and each of those frames is a call of
## `SaFoldDebt.frame`. Its twin is outside the tree, given the same acts, then
## folded again whole and composited at every chunk, which is the true picture.
extends "res://tests/test_framework.gd"

## The pictures and the caches are compute dispatches, read back here.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")

const DOC_SIZE := Vector2i(1024, 512)
const PAINT_LAYERS := 12

## More frames than any fold here takes.
const MOST_FRAMES := 64

var _easel: SaEasel
var _twin: SaEasel
var _marked: Dictionary[Vector2i, bool] = {}


static func _built() -> SaEasel:
    var easel := SaEasel.create_default(DOC_SIZE)
    easel.compositor.set_registry(Fixtures.make_registries().blend_modes)
    var doc := easel.document
    doc.active_layer.name = "Background"
    doc.fold.debt.quiet_msec = 60000
    doc.fold.debt.steps_per_frame = 1
    doc.update_caches()
    for i: int in PAINT_LAYERS:
        var layer := SaLayerOps.new(doc).add()
        layer.name = "Paint %d" % i
        doc.fill_layer(Color(float(i) / PAINT_LAYERS, 0.4, 0.2, 0.5), layer)
    SaLayerOps.new(doc).add().name = "Empty"
    doc.set_active_layer(_named(doc, "Paint 3"))
    doc.update_caches()
    easel.request_full_composite()
    _drawn(easel)
    return easel


func before_each() -> void:
    _easel = _built()
    EventBus.add_child(_easel)
    _twin = _built()
    _marked = {}


func after_each() -> void:
    _easel.free()
    _twin.free()


static func _named(doc: SaDocument, layer_name: String) -> SaLayer:
    return doc.find_child(layer_name, false, false) as SaLayer


## The canvas of *easel* as the next frame leaves it: what is dirty
## composited, nothing asked of the whole canvas.
static func _drawn(easel: SaEasel) -> PackedByteArray:
    easel.process_pending_composite()
    easel.flush()
    return GlobalShaderCompiler.get_rd().texture_get_data(easel.output.rid, 0)


## The twin's canvas after a full `update_caches` and a composite of every
## chunk.
func _truth() -> PackedByteArray:
    _twin.document.update_caches()
    _twin.request_full_composite()
    return _drawn(_twin)


func _mark(grid_positions: Array) -> void:
    for grid_pos: Vector2i in grid_positions:
        _marked[grid_pos] = true


## The eye of a layer clicked on both easels, one frame of its fold paid on
## the one under test, then *between* run on both, then frames until nothing is
## owed and the frame the tree runs after them, where a deferred draw lands.
## No frame is idle, as for a painter who clicks a row and paints at once. The
## canvas then is the true one with no stroke pressed, read by a composite
## that marks no chunk the build left unmarked, and a press after it marks no
## chunk, since an empty press touches none.
func _case(what: String, between: Callable) -> void:
    var doc := _easel.document
    var before := _drawn(_easel)
    for each: SaDocument in [doc, _twin.document]:
        SaLayerOps.new(each).set_visible(_named(each, "Paint 7"), false)
    doc.fold.debt.frame()
    assert_true(doc.fold.debt.is_owed(), "%s: the first frame after the eye leaves its fold unpaid" % what)
    assert_true(_drawn(_easel) == before, "%s: and shows the picture from before the eye" % what)
    for each: SaDocument in [doc, _twin.document]:
        between.call(each)
    var frames := 0
    while doc.fold.debt.is_owed() and frames < MOST_FRAMES:
        doc.fold.debt.frame()
        frames += 1
    await _easel.get_tree().process_frame
    var truth := _truth()
    assert_true(truth != before, "%s: hiding the layer changes the picture" % what)
    doc.chunks_invalidated.connect(_mark)
    var shown := _drawn(_easel)
    var by_the_composite := _marked.size()
    doc.begin_stroke(1.0, &"normal")
    doc.chunks_invalidated.disconnect(_mark)
    doc.commit_stroke()
    var by_the_press := _marked.size() - by_the_composite
    var line := "probe %s: %d frames paid the fold, the composite marked %d chunks, the press %d"
    print(line % [what, frames, by_the_composite, by_the_press])
    assert_false(doc.fold.debt.is_owed(), "%s: nothing is owed before the press" % what)
    assert_true(shown == truth, "%s: before any stroke the canvas is drawn with the layer hidden" % what)
    assert_eq(by_the_composite, 0, "%s: the composite that shows it marks no chunk of its own" % what)
    assert_eq(by_the_press, 0, "%s: the press marks no chunk outside its dirty rect" % what)


func test_a_click_on_another_row_before_the_eyes_fold_is_paid() -> void:
    await _case("a click on a row", func(each: SaDocument) -> void: each.set_active_layer(_named(each, "Paint 10")))


## An opacity written after the click flushes through `filter_moved`, whose
## refold builds the fold again when the walk moved, and pays the debt.
func test_a_refold_after_the_click_pays_the_eyes_debt() -> void:
    var refold := func(each: SaDocument) -> void:
        each.set_active_layer(_named(each, "Paint 10"))
        var layer := _named(each, "Empty")
        each.filter_moved(layer, func() -> void: layer.opacity = 0.5)
    await _case("a refold", refold)


## A whole `update_caches`, which a file's load and a scenario's layer step
## ask for, builds the fold and pays the debt as well.
func test_a_whole_update_after_the_click_pays_the_eyes_debt() -> void:
    await _case("a whole update", func(each: SaDocument) -> void: each.update_caches())
