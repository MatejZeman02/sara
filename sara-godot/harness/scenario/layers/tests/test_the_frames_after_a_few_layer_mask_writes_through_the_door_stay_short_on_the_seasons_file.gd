## A mask rewritten through the door's `layer` step redraws what the mask
## moves, as a stroke on the mask does, and builds no fold of its own.
##
## The step rebuilt the fold after every mask write, and a rebuild marks every
## chunk of the picture at no layer, so on a document with 219 effect layers
## each post redrew all of them, and 14 masks of ten posts each held
## the frames slow for three minutes. A write to a mask the layer
## already holds now goes through `SaDocument.mask_moved`, marked at the layer
## and folded again over its chunks alone, and a hidden layer's moves nothing.
## A mask added, a group's or one switched on or off still builds the fold,
## because each changes the walk and not only the chunks.
##
## A rebuild is counted in `SaLayerFold.rebuild` by a fold that counts its
## calls standing in the document's own, as the suite of the step's other
## keys counts them.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

## The steps are real uploads into a real stack, read back from the composite,
## so this needs a RenderingDevice.
const REQUIRES_GPU := true

## A texel of chunk (0, 0), the one the writes name.
const AT := Vector2i(10, 10)
const WHOLE := [[0, 0, 256, 256, 1.0]]
const NONE := [[0, 0, 256, 256, 0.0]]

var _easel: SaEasel = null
var _doc: SaDocument = null
var _fold: CountingFold = null
var _announced: bool = true


## A fold that counts the rebuilds `SaDocument.update_caches` asks of it.
class CountingFold:
    extends SaLayerFold

    var rebuilds: int = 0

    func rebuild(document: SaDocument, compositor: SaCompositor, visible_rect: Rect2) -> void:
        rebuilds += 1
        super(document, compositor, visible_rect)


## Layer 1 at the bottom, Below over it and Above on top, Above the one
## selected, so Below is folded into the bottom cache. Below is red over
## chunk (0, 0) and holds a mask of ones there, so a write that empties the
## mask shows the ground again only if the cache that baked Below folds anew.
func before_each() -> void:
    _announced = SaProblems.announce
    SaProblems.announce = false
    _easel = SaEasel.create_default(Vector2i(512, 256))
    _easel.compositor.set_registry(Fixtures.make_registries().blend_modes)
    _doc = _easel.document
    SaLayerStep.run(_doc, {"add": "Below"})
    SaLayerStep.run(_doc, {"add": "Above"})
    SaLayerStep.run(_doc, {"of": "Below", "fill": [1.0, 0.0, 0.0, 1.0], "chunks": [[0, 0]]})
    SaLayerStep.run(_doc, {"of": "Below", "mask": {"rects": WHOLE}})
    _doc.fold.release()
    _fold = CountingFold.new()
    _doc.fold = _fold
    _doc.update_caches()


func after_each() -> void:
    _easel.free()
    _easel = null
    _doc = null
    _fold = null
    SaProblems.announce = _announced


## The rebuilds *spec* run as a layer step makes, and the step's answer.
func _rebuilds_of(spec: Dictionary) -> Array:
    var before := _fold.rebuilds
    var line := SaLayerStep.run(_doc, spec)
    var said: Variant = JSON.parse_string(line.trim_prefix("SaCapture: layer "))
    assert_true(said is Dictionary and not (said as Dictionary).has("error"), "the step answers: %s" % line)
    return [_fold.rebuilds - before, said if said is Dictionary else {}]


## The composite at *at* as the caches stand, with no rebuild first.
func _shown(at: Vector2i) -> Color:
    _easel.request_full_composite()
    _easel.process_pending_composite()
    var texture := _easel.output
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    return SaFieldSpec.decode_texel(bytes, texture.format, at.y * texture.size.x + at.x)


## The composite at *at* after the fold is built again whole.
func _rebuilt(at: Vector2i) -> Color:
    _doc.update_caches()
    _doc.consume_dirty_chunks()
    return _shown(at)


func test_a_write_to_a_mask_the_layer_holds_builds_no_fold_and_the_composite_follows() -> void:
    var below := _doc.get_node("Below") as SaLayer
    var red := _shown(AT)
    assert_almost_eq(red.r, 1.0, 0.02, "Below shows red through its mask of ones: %s" % red)
    _doc.consume_dirty_chunks()

    var written := _rebuilds_of({"of": "Below", "mask": {"rects": NONE}})
    assert_eq(written[0], 0, "the write builds no fold: %s" % [written[1]])
    var dirty := _doc.consume_dirty_chunks()
    var at_below: Dictionary = _doc.moved_at.get(below.get_instance_id(), {})
    assert_true(at_below.has(Vector2i(0, 0)), "and marks chunk (0, 0) at Below, the layer that holds the mask")
    assert_eq(at_below.keys().size(), dirty.size(), "and every chunk it marks at Below: %s" % [dirty.keys()])
    assert_true(_doc.modified, "and the document is changed")

    var shown := _shown(AT)
    assert_true(shown.r < 0.75, "the cache that baked Below folded again, and red is gone: %s" % shown)
    var whole := _rebuilt(AT)
    assert_true(shown.is_equal_approx(whole), "as a whole rebuild draws it: %s and %s" % [shown, whole])


func test_a_write_to_a_hidden_layer_s_mask_marks_nothing_and_shows_once_the_layer_does() -> void:
    SaLayerStep.run(_doc, {"of": "Below", "visible": false})
    SaFoldDebt.before_reading(_doc)
    _shown(AT)
    _doc.consume_dirty_chunks()

    var written := _rebuilds_of({"of": "Below", "mask": {"rects": NONE}})
    assert_eq(written[0], 0, "the write builds no fold: %s" % [written[1]])
    assert_true(_doc.consume_dirty_chunks().is_empty(), "and marks nothing, since the picture leaves Below out")

    SaLayerStep.run(_doc, {"of": "Below", "visible": true})
    SaFoldDebt.before_reading(_doc)
    var shown := _shown(AT)
    assert_true(shown.r < 0.75, "shown again, Below draws through the mask written while it was hidden: %s" % shown)
    var whole := _rebuilt(AT)
    assert_true(shown.is_equal_approx(whole), "as a whole rebuild draws it: %s and %s" % [shown, whole])


func test_a_mask_added_or_switched_still_builds_the_fold() -> void:
    var added := _rebuilds_of({"of": "Above", "mask": {"rects": WHOLE}})
    assert_eq(added[0], 1, "a mask the layer did not hold builds the fold once: %s" % [added[1]])
    var switched := _rebuilds_of({"of": "Below", "mask": {"enabled": false}})
    assert_eq(switched[0], 1, "and so does a mask switched off: %s" % [switched[1]])
    assert_almost_eq(_shown(AT).r, 1.0, 0.02, "which shows Below whole and red")
