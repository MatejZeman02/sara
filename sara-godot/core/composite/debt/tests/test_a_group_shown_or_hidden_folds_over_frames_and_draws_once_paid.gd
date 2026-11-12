## A group shown or hidden folds over frames and draws once paid.
##
## The eye of a group folded the whole stack in the frame of the click, 88 ms
## for the dawn picture's dusk group and 292 ms for its day group. Now the
## click owes the fold to `SaFoldDebt`, the frames after it fold it a few steps
## at a time, and the picture stands as it was until the last is paid, when it
## is drawn whole.
##
## Two easels are built alike on the stack, a 2160 by 720 document of thirty
## painted layers over the default two, the top four in a group, as the sibling
## suite builds them. The one under test is in the tree, which is what lets a
## debt wait for the frames after the click, and each of those frames is a
## call of `SaFoldDebt.frame`. Its twin is outside the tree and pays at once,
## then folds again with a full `update_caches` and composites every chunk,
## which is the true picture.
extends "res://tests/test_framework.gd"

## The pictures and the caches are compute dispatches, read back here.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const BusyBound = preload("res://tests/fixtures/busy_bound.gd")

const DOC_SIZE := Vector2i(2160, 720)
const PAINT_LAYERS := 30
const MEMBERS := 4

## The ceiling on a frame that pays, in milliseconds on a quiet
## machine, moved by `BusyBound` when the machine is busy.
const LIMIT_MS := 50.0

## More frames than any fold here takes.
const MOST_FRAMES := 64

var _easel: SaEasel
var _twin: SaEasel
## Whether the eye was an undo step when the test began.
var _eye_was: bool


static func _built() -> SaEasel:
    var easel := SaEasel.create_default(DOC_SIZE)
    easel.compositor.set_registry(Fixtures.make_registries().blend_modes)
    var doc := easel.document
    doc.active_layer.name = "Background"
    doc.fold.debt.quiet_msec = 60000
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
    _eye_was = SaSettings.visibility_in_history
    SaSettings.visibility_in_history = false
    _easel = _built()
    EventBus.add_child(_easel)
    _twin = _built()


func after_each() -> void:
    SaSettings.visibility_in_history = _eye_was
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


static func _named(doc: SaDocument, layer_name: String) -> SaLayer:
    return doc.find_child(layer_name, false, false) as SaLayer


## *act* run on both easels, its argument each one's document. The frame of
## it folds nothing and draws nothing, each frame after it pays a part under
## the ceiling and shows the picture from before, and once the last has run
## the picture is the true one and every cache the one a full fold folds.
## Answers how many frames paid.
func _step(what: String, act: Callable) -> int:
    var doc := _easel.document
    var before := _drawn(_easel)
    act.call(doc)
    act.call(_twin.document)
    var truth := _truth()
    assert_true(before != truth, "%s changes the picture" % what)
    assert_true(doc.fold.debt.is_owed(), "%s owes the fold" % what)
    assert_eq(_drawn(_easel), before, "and the frame of %s shows the picture from before it" % what)
    var frames := 0
    var longest := 0.0
    var held := true
    var bound := BusyBound.new(LIMIT_MS)
    # A lambda copies a local, so the picture a frame shows comes back in here.
    var shown := {}
    while doc.fold.debt.is_owed() and frames < MOST_FRAMES:
        var paid := func() -> void:
            doc.fold.debt.frame()
            shown[&"canvas"] = _drawn(_easel)
        longest = maxf(longest, bound.time("A frame paying the fold after %s" % what, paid))
        frames += 1
        var canvas: PackedByteArray = shown[&"canvas"]
        held = held and (canvas == before if doc.fold.debt.is_owed() else canvas == truth)
    print("probe after %s, %d frames paid the fold, the longest with its drawing %.1f ms" % [what, frames, longest])
    assert_true(bound.all_held, bound.worst)
    assert_true(held, "every frame of the unpaid fold showed the picture from before, and the last the true one")
    assert_false(doc.fold.debt.is_owed(), "Nothing is owed once the last has run")
    assert_eq(_caches(doc), _caches(_twin.document), "every cache is the one a full fold folds")
    assert_eq(_drawn(_easel), truth, "and the frame after it shows the true picture")
    return frames


func test_a_group_hidden_and_shown_again_folds_over_frames_and_draws_the_true_picture() -> void:
    var hide := func(doc: SaDocument) -> void: SaLayerOps.new(doc).set_visible(_named(doc, "Pictures"), false)
    var show := func(doc: SaDocument) -> void: SaLayerOps.new(doc).set_visible(_named(doc, "Pictures"), true)
    assert_true(_step("hiding the group", hide) > 1, "The fold of a hidden group is spread over frames")
    assert_true(_step("showing it again", show) > 1, "and so is the fold of a shown one")


func test_a_painted_layer_shown_and_hidden_folds_the_same_way() -> void:
    SaSettings.visibility_in_history = true
    _step("hiding a layer", func(doc: SaDocument) -> void: SaLayerOps.new(doc).set_visible(_named(doc, "Paint 29"), false))
    _step("its undo", func(doc: SaDocument) -> void: doc.undo())


## A press while the fold is under way pays the rest at once, so the stroke
## finds every cache folded and the picture drawn.
func test_a_press_pays_the_rest_and_draws_the_true_picture() -> void:
    var doc := _easel.document
    SaLayerOps.new(doc).set_visible(_named(doc, "Pictures"), false)
    SaLayerOps.new(_twin.document).set_visible(_named(_twin.document, "Pictures"), false)
    var truth := _truth()
    doc.fold.debt.frame()
    assert_true(doc.fold.debt.is_owed(), "The first frame after the click leaves caches unpaid")
    doc.begin_stroke(1.0, &"normal")
    doc.commit_stroke()
    assert_false(doc.fold.debt.is_owed(), "and a press pays the rest")
    assert_eq(_caches(doc), _caches(_twin.document), "with every cache the one a full fold folds")
    assert_eq(_drawn(_easel), truth, "and the picture the true one")


## A document outside the tree has no frames to wait for, and pays at once.
func test_a_document_outside_the_tree_pays_at_once() -> void:
    var doc := _twin.document
    SaLayerOps.new(doc).set_visible(_named(doc, "Pictures"), false)
    assert_false(doc.fold.debt.is_owed(), "Nothing is owed after the click")
    var drawn := _drawn(_twin)
    assert_eq(drawn, _truth(), "and the next frame draws the true picture")


## A scenario's `visible` step folds once, through the debt, and no more.
func test_visible_is_not_a_key_that_refolds() -> void:
    assert_false(SaLayerStep.REFOLDS.has("visible"), "`visible` is not in SaLayerStep.REFOLDS")
