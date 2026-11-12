## The idle frame that pays an owed fold takes under fifty milliseconds.
##
## put the fold of an activation off to the first idle frame, and that
## frame folded every cache and then drew the whole picture again, though a
## walk split at another layer draws the same picture. Now a debt of the active
## layer alone draws nothing, and the idle frame folds one cache and leaves the
## rest to the frames after it. A change of the stack is paid as before, by the
## composite that draws it.
##
## Two easels are built alike on the stack, a 2160 by 720 document of thirty
## painted layers over the default two, the top four in a group. The one under
## test owes its folds. Its twin folds at once with a full `update_caches` and
## composites every chunk, which is the true picture, and the canvas under test
## is read against it at every frame of the unpaid fold. The easel under test
## is in the tree, which is what lets a debt wait for the frames after the idle
## one, and each of those frames is a call of `SaFoldDebt.frame`.
extends "res://tests/test_framework.gd"

## The pictures and the caches are compute dispatches, read back here.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const BusyBound = preload("res://tests/fixtures/busy_bound.gd")

const DOC_SIZE := Vector2i(2160, 720)
const PAINT_LAYERS := 30
const MEMBERS := 4

## The ceiling the row sets on a frame that pays, in milliseconds on a quiet
## machine, moved by `BusyBound` when the machine is busy.
const LIMIT_MS := 50.0

## More frames than any fold here takes.
const MOST_FRAMES := 64

var _easel: SaEasel
var _twin: SaEasel
var _changes := 0


static func _built(owing: bool) -> SaEasel:
    var easel := SaEasel.create_default(DOC_SIZE)
    easel.compositor.set_registry(Fixtures.make_registries().blend_modes)
    var doc := easel.document
    doc.active_layer.name = "Background"
    doc.fold.debt.quiet_msec = 0 if owing else 60000
    doc.update_caches()
    var members: Array[SaLayer] = []
    for i: int in PAINT_LAYERS:
        var layer := SaLayerOps.new(doc).add()
        layer.name = "Paint %d" % i
        doc.fill_layer(Color(float(i) / PAINT_LAYERS, 0.4, 0.2, 1.0), layer)
        if i >= PAINT_LAYERS - MEMBERS:
            members.append(layer)
    SaLayerOps.new(doc).group_layers(members).name = "Pictures"
    doc.set_active_layer(doc.find_child("Paint 3", false, false) as SaLayer)
    doc.update_caches()
    easel.request_full_composite()
    _drawn(easel)
    return easel


func before_each() -> void:
    _easel = _built(true)
    EventBus.add_child(_easel)
    _twin = _built(false)
    _changes = 0
    _easel.document.document_changed.connect(func() -> void: _changes += 1)


func after_each() -> void:
    _easel.free()
    _twin.free()


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


## Every chunk of every cache of *doc*'s fold, by the cache's name.
static func _caches(doc: SaDocument) -> Dictionary:
    var out := {}
    for cache in doc.fold.caches():
        if not is_instance_valid(cache):
            continue
        var chunks := {}
        for grid_pos: Vector2i in SaTyped.positions(cache.chunks):
            chunks[grid_pos] = GlobalShaderCompiler.get_rd().texture_get_data(cache.chunks[grid_pos].albedo().rid, 0)
        out[str(cache.name)] = chunks
    return out


## *act* run on both easels, its argument each one's document. Then the frame
## after it, and the idle frame and every frame after it while the fold is
## unpaid, each canvas read against the true one, and once the last has run
## the caches folded and nothing owed. A click's frames draw nothing and tell
## nobody the document changed. Answers how many frames paid.
func _step(what: String, act: Callable, click: bool) -> int:
    var doc := _easel.document
    act.call(doc)
    act.call(_twin.document)
    var truth := _truth()
    assert_eq(_drawn(_easel), truth, "the frame after %s shows the true picture" % what)
    assert_eq(doc.fold.debt.is_owed(), click, "and %s" % ("the fold is still owed" if click else "the composite paid the fold"))
    var changes := _changes
    var frames := 0
    var longest := 0.0
    var all_true := true
    var bound := BusyBound.new(LIMIT_MS)
    # A lambda copies a local, so the picture a frame shows comes back in here.
    var shown := {}
    while doc.fold.debt.is_owed() and frames < MOST_FRAMES:
        var paid := func() -> void:
            doc.fold.debt.frame()
            shown[&"canvas"] = _drawn(_easel)
        longest = maxf(longest, bound.time("A frame paying the fold after %s" % what, paid))
        frames += 1
        all_true = all_true and shown[&"canvas"] == truth
    var line := "probe after %s, %d frames paid the fold, the longest with its drawing %.1f ms"
    print(line % [what, frames, longest])
    assert_true(bound.all_held, bound.worst)
    assert_true(all_true, "and every frame of the unpaid fold showed the true picture")
    if click:
        assert_eq(_changes, changes, "and drew nothing, since the picture did not move")
    assert_false(doc.fold.debt.is_owed(), "Nothing is owed once the last has run")
    assert_true(doc.fold.reads_as_built(doc), "the walk is built around %s" % doc.active_layer.name)
    assert_eq(_caches(doc), _caches(_twin.document), "and every cache is the one a full fold folds")
    assert_eq(_drawn(_easel), truth, "and the frame after it still shows the true picture")
    return frames


static func _named(doc: SaDocument, layer_name: String) -> SaLayer:
    return doc.find_child(layer_name, false, false) as SaLayer


func test_a_click_an_add_a_drop_and_a_delete_each_show_the_true_picture_at_every_frame() -> void:
    var frames := _step("a click", func(doc: SaDocument) -> void: doc.set_active_layer(_named(doc, "Paint 12")), true)
    assert_true(frames > 1, "The fold of a click is spread over %d frames" % frames)
    _step("a click into the group", func(doc: SaDocument) -> void: doc.set_active_layer(_named(doc, "Paint 27")), true)
    _step("an add", func(doc: SaDocument) -> void: SaLayerOps.new(doc).add().name = "Added", false)
    _step("a drop", func(doc: SaDocument) -> void: SaLayerOps.new(doc).place(_named(doc, "Paint 5"), null, 20), false)
    _step("a delete", func(doc: SaDocument) -> void: SaLayerOps.new(doc).remove(_named(doc, "Paint 10")), false)
    _step("a click after them", func(doc: SaDocument) -> void: doc.set_active_layer(_named(doc, "Paint 1")), true)


## Two clicks before the idle frame owe one fold, paid the same way.
func test_two_clicks_and_one_idle_frame_fold_once_and_draw_nothing() -> void:
    var doc := _easel.document
    doc.set_active_layer(_named(doc, "Paint 20"))
    _twin.document.set_active_layer(_named(_twin.document, "Paint 20"))
    _step("a second click", func(each: SaDocument) -> void: each.set_active_layer(_named(each, "Paint 8")), true)


## A press while a fold over frames is under way pays the rest at once, and so
## does a frame that draws, so the stroke finds every cache folded.
func test_a_press_and_a_drawing_pay_the_rest_at_once() -> void:
    var doc := _easel.document
    for target: String in ["Paint 22", "Paint 6"]:
        doc.set_active_layer(_named(doc, target))
        _twin.document.set_active_layer(_named(_twin.document, target))
        var truth := _truth()
        doc.fold.debt.frame()
        assert_true(doc.fold.debt.is_owed(), "The idle frame after a click on %s leaves caches unpaid" % target)
        if target == "Paint 22":
            doc.begin_stroke(1.0, &"normal")
            doc.commit_stroke()
            assert_false(doc.fold.debt.is_owed(), "and a press pays the rest")
        else:
            doc.invalidate_all_allocated_chunks()
            assert_eq(_drawn(_easel), truth, "and a frame that draws everything shows the true picture")
            assert_false(doc.fold.debt.is_owed(), "having paid the rest")
        assert_eq(_caches(doc), _caches(_twin.document), "with every cache the one a full fold folds")


## A press straight after a click pays the fold the same way, so the stroke
## finds the caches built around the layer it paints.
func test_a_press_pays_a_click_by_the_fold_alone() -> void:
    var doc := _easel.document
    doc.fold.debt.quiet_msec = 60000
    doc.set_active_layer(_named(doc, "Paint 15"))
    _twin.document.set_active_layer(_named(_twin.document, "Paint 15"))
    var truth := _truth()
    assert_true(doc.fold.debt.is_owed(), "The click owes the fold")
    var changes := _changes
    doc.fold.debt.settle(doc)
    assert_false(doc.fold.debt.is_owed(), "and the press pays it")
    assert_eq(_changes, changes, "drawing nothing")
    assert_eq(_caches(doc), _caches(_twin.document), "with every cache the one a full fold folds")
    assert_eq(_drawn(_easel), truth, "and the picture the true one")
