## A layer-wide change redraws the region that layer drew in, not the region
## the compositor is about to read.
##
## Hiding a layer left it on the canvas . The three property
## changes that alter what a layer contributes, visibility, opacity and blend
## mode, marked nothing dirty of their own and leaned on the cache rebuild,
## which walks `SaLayerStack.layers()`. That walk is what the compositor reads,
## so the rebuild had already dropped the layer being hidden and its chunks
## kept the composite they had. A hidden background stayed grey everywhere the
## layer above it was empty, and the minimap, which shows the same output
## texture, stayed grey with it.
extends "res://tests/test_framework.gd"

## Real chunk textures and a real composite, so this needs a RenderingDevice.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")

## Two chunks wide and one tall, so "the chunks the layer covered" is a set
## small enough to name.
const CANVAS := Vector2i(512, 256)
const PAINTED := Color(1.0, 0.0, 0.0, 1.0)

## Whether the eye was an undo step when the test began.
var _eye_was: bool


## The eye is a step only while Preferences asks, which a test here
## turns on. Off for each test, and what the suite found restored after it, so
## a run leaves the default as it stood.
func before_each() -> void:
    _eye_was = SaSettings.visibility_in_history
    SaSettings.visibility_in_history = false


func after_each() -> void:
    SaSettings.visibility_in_history = _eye_was


func _easel() -> SaEasel:
    var easel := SaEasel.create_default(CANVAS)
    easel.compositor.set_registry(Fixtures.make_registries().blend_modes)
    return easel


func _texel(texture: SaTexture, x: int, y: int) -> Color:
    var data: PackedByteArray = GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    var at := (y * texture.size.x + x) * 16
    return Color(data.decode_float(at), data.decode_float(at + 4), data.decode_float(at + 8), data.decode_float(at + 12))


## Composites through the dirty set, the way a frame does, rather than through
## `request_full_composite()`, which would redraw everything and prove nothing.
func _composite_dirty(easel: SaEasel) -> void:
    easel.request_composite()
    easel.process_pending_composite()


## The default document, with the paint layer holding one chunk of red over a
## background that holds both. Returns background, paint.
func _painted(easel: SaEasel) -> Array[SaLayer]:
    var doc := easel.document
    var stack := SaLayerOps.new(doc).layers()
    var paint: SaLayer = stack[1]
    paint.get_or_create_chunk(Vector2i(0, 0)).clear(PAINTED)
    doc.update_caches()
    _composite_dirty(easel)
    doc.consume_dirty_chunks()
    return [stack[0], paint]


func test_hiding_a_layer_marks_every_chunk_it_covered() -> void:
    var easel := _easel()
    var doc := easel.document
    var pair := _painted(easel)

    SaLayerOps.new(doc).set_visible(pair[0], false)
    var dirty := doc.consume_dirty_chunks()
    assert_true(dirty.has(Vector2i(0, 0)), "The chunk under the paint is dirty")
    assert_true(dirty.has(Vector2i(1, 0)), "and so is the one the hidden background had to itself")
    assert_eq(dirty[Vector2i(1, 0)], SaDocument.WHOLE_CHUNK, "all of it, because a layer-wide change is not a dab")
    easel.free()


## The requirement: the chequerboard shows everywhere the upper layer is
## empty. The chequerboard is what the view draws behind a transparent output,
## so what the composite has to produce there is alpha zero.
func test_hiding_the_lower_layer_clears_the_canvas_under_it() -> void:
    var easel := _easel()
    var doc := easel.document
    var pair := _painted(easel)
    assert_almost_eq(_texel(easel.output, 400, 128).a, 1.0, 1e-4, "The background is opaque before the hide")

    SaLayerOps.new(doc).set_visible(pair[0], false)
    _composite_dirty(easel)

    assert_almost_eq(_texel(easel.output, 400, 128).a, 0.0, 1e-4, "Hidden, it leaves nothing where the paint is not")
    var kept := _texel(easel.output, 64, 128)
    assert_almost_eq(kept.r, PAINTED.r, 0.02, "and the layer above keeps its paint")
    assert_almost_eq(kept.a, 1.0, 1e-4, "at full alpha")

    SaLayerOps.new(doc).set_visible(pair[0], true)
    _composite_dirty(easel)
    assert_almost_eq(_texel(easel.output, 400, 128).a, 1.0, 1e-4, "Shown again, it comes back")
    easel.free()


## Showing a layer again was never the broken direction: the rebuild puts it
## back in the walk and the walk marks its chunks. This is here so the round
## trip stays whole, since the fix is on the path both directions take.
func test_undoing_a_hide_brings_the_layer_back_on_the_canvas() -> void:
    SaSettings.visibility_in_history = true
    var easel := _easel()
    var doc := easel.document
    var pair := _painted(easel)
    SaLayerOps.new(doc).set_visible(pair[0], false)
    _composite_dirty(easel)

    assert_true(doc.undo(), "The hide is one history step")
    _composite_dirty(easel)
    assert_almost_eq(_texel(easel.output, 400, 128).a, 1.0, 1e-4, "and undoing it redraws where the layer draws")
    easel.free()


## Opacity and blend mode change what a layer contributes without moving a
## pixel of it, so they were missing the mark the same way. Opacity is
## deferred, so the composite waits for the queued rebuild.
func test_opacity_and_blend_mode_mark_the_layer_too() -> void:
    var easel := _easel()
    var doc := easel.document
    var pair := _painted(easel)

    SaLayerOps.new(doc).set_opacity(pair[0], 0.5)
    var dirty := doc.consume_dirty_chunks()
    assert_true(dirty.has(Vector2i(1, 0)), "An opacity change marks the chunk nothing else covers")

    SaLayerOps.new(doc).set_blend_mode(pair[0], &"multiply")
    dirty = doc.consume_dirty_chunks()
    assert_true(dirty.has(Vector2i(1, 0)), "and so does a blend mode change")
    easel.free()


## A group's eye hides everything inside it, and the members are siblings in
## the document rather than children of the group node, so asking the group
## for its children would have found nothing to mark.
##
## The background goes first, or it covers both chunks and marks the member's
## one for free, which would let this pass on a group that marked nothing.
func test_hiding_a_group_marks_what_is_inside_it() -> void:
    var easel := _easel()
    var doc := easel.document
    var pair := _painted(easel)
    doc.set_active_layer(pair[1])
    var group := SaLayerOps.new(doc).group_active()
    assert_not_null(group, "The paint layer is wrapped in a group")
    SaLayerOps.new(doc).set_visible(pair[0], false)
    doc.consume_dirty_chunks()

    SaLayerOps.new(doc).set_visible(group, false)
    var dirty := doc.consume_dirty_chunks()
    assert_true(dirty.has(Vector2i(0, 0)), "Hiding the group marks the chunk its member painted")
    easel.free()
