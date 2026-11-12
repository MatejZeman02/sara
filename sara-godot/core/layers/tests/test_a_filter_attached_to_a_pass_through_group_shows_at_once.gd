## A filter attached to a
## pass-through group shows at once.
##
## A red layer sits in a pass-through group over a grey Background. The first
## enabled filter on the group isolates it, which changes the fold's walk, and
## the walk is read as unchanged by the refold an attach ends on, so the Invert
## showed only at the next pick of a layer. Each test settles the easel without
## a build of its own and reads the texel a full `update_caches` draws. The
## debt's quiet time is a minute, so nothing pays a build behind the test's
## back, and the fold counts its builds, so an attach that does not change the
## walk is shown to build nothing.
extends "res://tests/test_framework.gd"

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")
const REQUIRES_GPU := true
const SIZE := Vector2i(512, 512)
const AT := Vector2i(100, 100)
const GREY := Color(0.5, 0.5, 0.5, 1.0)
const RED := Color(0.9, 0.1, 0.1, 1.0)


## A fold that counts its builds.
class CountedFold:
    extends SaLayerFold

    var rebuilds := 0

    func rebuild(document: SaDocument, compositor: SaCompositor, visible_rect: Rect2) -> void:
        rebuilds += 1
        super.rebuild(document, compositor, visible_rect)


var _easel: SaEasel = null
var _doc: SaDocument = null
var _fold: CountedFold = null
var _group: SaLayer = null
var _paint: SaLayer = null
var _background: SaLayer = null


func before_each() -> void:
    _easel = Bench.easel(SIZE)
    _doc = _easel.document
    _doc.fold.release()
    _fold = CountedFold.new()
    _fold.debt.quiet_msec = 60000
    _doc.fold = _fold
    _background = _doc.get_node("Background") as SaLayer
    _background.get_or_create_chunk(Vector2i.ZERO).clear(GREY)
    _doc.set_active_layer(_background)
    var ops := SaLayerOps.new(_doc)
    _paint = ops.add()
    _paint.name = "Paint"
    _paint.get_or_create_chunk(Vector2i.ZERO).clear(RED)
    _group = ops.group_active()
    _doc.set_active_layer(_background)
    Bench.composite(_easel)


func after_each() -> void:
    _easel.free()
    _easel = null


## The texel as the easel shows it once what is owed is paid, with no build.
func _settled() -> Color:
    _easel.catch_up()
    _easel.flush()
    return Bench.texel(_easel.output, AT)


## The texel a full build of the walk draws.
func _rebuilt() -> Color:
    Bench.composite(_easel)
    return Bench.texel(_easel.output, AT)


func _near(a: Color, b: Color) -> bool:
    return absf(a.r - b.r) < 0.01 and absf(a.g - b.g) < 0.01 and absf(a.b - b.b) < 0.01 and absf(a.a - b.a) < 0.01


func test_an_invert_attached_to_a_pass_through_group_shows_at_once() -> void:
    assert_false(SaLayerStack.isolates(_group), "the group starts pass-through")
    var builds := _fold.rebuilds
    SaFilterOps.new(_doc).attach(_group, Bench.INVERT, {})
    var quick := _settled()
    assert_true(_near(quick, Color(0.1, 0.9, 0.9, 1.0)), "the red reads inverted at once, read %s" % quick)
    assert_eq(_fold.rebuilds, builds + 1, "the attach builds the walk once")
    var rebuilt := _rebuilt()
    assert_true(_near(quick, rebuilt), "as a full build draws it, %s and %s" % [quick, rebuilt])


func test_the_attach_shows_at_once_with_the_member_active() -> void:
    _doc.set_active_layer(_paint)
    Bench.composite(_easel)
    SaFilterOps.new(_doc).attach(_group, Bench.INVERT, {})
    var quick := _settled()
    assert_true(_near(quick, Color(0.1, 0.9, 0.9, 1.0)), "the red reads inverted at once, read %s" % quick)
    var rebuilt := _rebuilt()
    assert_true(_near(quick, rebuilt), "as a full build draws it, %s and %s" % [quick, rebuilt])


func test_the_undo_of_the_attach_shows_at_once() -> void:
    SaFilterOps.new(_doc).attach(_group, Bench.INVERT, {})
    Bench.composite(_easel)
    _doc.undo()
    var quick := _settled()
    assert_true(_near(quick, RED), "the red reads as it was, read %s" % quick)
    var rebuilt := _rebuilt()
    assert_true(_near(quick, rebuilt), "as a full build draws it, %s and %s" % [quick, rebuilt])


## A Multiply member reads differently in a pass-through group, where it
## multiplies the grey, and an isolated one, where it lies over nothing, so a
## walk kept with the group's cache step after the detach would draw plain red.
func test_detaching_the_last_filter_draws_a_multiply_member_pass_through_at_once() -> void:
    _paint.blend_mode = SaLayer.BLEND_MODE.MULTIPLY
    var pass_through := _rebuilt()
    var ops := SaFilterOps.new(_doc)
    var record := ops.attach(_group, Bench.INVERT, {})
    Bench.composite(_easel)
    assert_true(SaLayerStack.isolates(_group), "the filter isolates the group")
    assert_true(ops.detach(_group, record), "the detach takes")
    assert_false(SaLayerStack.isolates(_group), "and the group is pass-through again")
    var quick := _settled()
    assert_false(_near(quick, RED), "the member does not read isolated, read %s" % quick)
    assert_true(_near(quick, pass_through), "it reads as before the attach, %s and %s" % [quick, pass_through])
    var rebuilt := _rebuilt()
    assert_true(_near(quick, rebuilt), "as a full build draws it, %s and %s" % [quick, rebuilt])


func test_an_attach_to_a_layer_builds_nothing_and_shows_at_once() -> void:
    var builds := _fold.rebuilds
    SaFilterOps.new(_doc).attach(_paint, Bench.INVERT, {})
    var quick := _settled()
    assert_eq(_fold.rebuilds, builds, "an attach to a layer refolds its reach and builds no walk")
    assert_true(_near(quick, Color(0.1, 0.9, 0.9, 1.0)), "the red reads inverted, read %s" % quick)
    var rebuilt := _rebuilt()
    assert_true(_near(quick, rebuilt), "as a full build draws it, %s and %s" % [quick, rebuilt])


func test_an_attach_to_an_isolated_group_builds_nothing_and_shows_at_once() -> void:
    _group.isolated = true
    Bench.composite(_easel)
    var builds := _fold.rebuilds
    SaFilterOps.new(_doc).attach(_group, Bench.INVERT, {})
    var quick := _settled()
    assert_eq(_fold.rebuilds, builds, "an attach to an isolated group refolds its reach and builds no walk")
    assert_true(_near(quick, Color(0.1, 0.9, 0.9, 1.0)), "the red reads inverted, read %s" % quick)
    var rebuilt := _rebuilt()
    assert_true(_near(quick, rebuilt), "as a full build draws it, %s and %s" % [quick, rebuilt])
