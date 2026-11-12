## A neighbourhood filter on a group draws past the chunks its members hold
## whichever layer is active. A scenario
## found it with: a 1024 by 768 document on a grey Background, a layer named
## Paint filled red over the one chunk at (1, 1), grouped, and the base module's
## Gaussian blur at a radius of 12 on the group. Three texels past the chunk,
## three and eight to the right and three below, read the same with Paint
## active as with Background active, and they carry the red.
##
## The same holds with the group nested in another, with a second filter on
## the group, with the member's own blur under the group's, and for a live
## stroke on the member redrawn over its dirty region alone.
extends "res://tests/test_framework.gd"

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")
const GaussianBlurFilter = preload("res://modules/sara-base-modules/base/usual/gaussian_blur_filter.gd")

const REQUIRES_GPU := true

const OWNER: StringName = &"sara-base-modules"
const SIZE := Vector2i(1024, 768)
const RADIUS := 12.0
const GREY := Color(0.5, 0.5, 0.5, 1.0)
const RED := Color(0.9, 0.1, 0.1, 1.0)
const YELLOW := Color(1.0, 0.8, 0.2, 1.0)
const HELD := Vector2i(1, 1)
## Three and eight texels past the right edge of the chunk at (1, 1), and three
## under its lower edge.
const READS: Array[Vector2i] = [Vector2i(515, 384), Vector2i(520, 384), Vector2i(384, 515)]
## One level of 255.
const LEVEL := 1.0 / 255.0

var _easel: SaEasel = null
var _doc: SaDocument = null
var _paint: SaLayer = null
var _background: SaLayer = null
var _group: SaLayer = null
var _key: StringName = &""


func before_each() -> void:
    _easel = Bench.easel(SIZE)
    _doc = _easel.document
    var blur := GaussianBlurFilter.new()
    _easel.compositor.filter_chain.registry.register(blur, OWNER)
    _key = SaFilterRegistry.key_for(OWNER, blur)
    _background = _doc.get_node("Background") as SaLayer
    for y in ceili(SIZE.y / float(SaChunk.SIZE)):
        for x in ceili(SIZE.x / float(SaChunk.SIZE)):
            _background.get_or_create_chunk(Vector2i(x, y)).clear(GREY)
    _doc.set_active_layer(_background)
    var ops := SaLayerOps.new(_doc)
    _paint = ops.add()
    _paint.name = "Paint"
    _paint.get_or_create_chunk(HELD).clear(RED)
    _group = ops.group_active()


func after_each() -> void:
    _easel.free()
    _easel = null
    _doc = null
    _paint = null
    _background = null
    _group = null


func _blur(node: SaLayer, radius: float = RADIUS) -> void:
    SaFilterOps.new(_doc).attach(node, _key, {"radius": radius})


## The three texels with *active* the active layer, after a full composite.
func _read_with(active: SaLayer) -> Array[Color]:
    _doc.set_active_layer(active)
    Bench.composite(_easel)
    var out: Array[Color] = []
    for at in READS:
        out.append(Bench.texel(_easel.output, at))
    return out


func _assert_same_spill(where: String) -> void:
    var member := _read_with(_paint)
    var outside := _read_with(_background)
    for i in READS.size():
        var gap := _gap(member[i], outside[i])
        assert_true(
            gap <= LEVEL,
            "%s: at %s Paint active reads %s and Background active %s, %.4f apart" % [where, READS[i], member[i], outside[i], gap]
        )
        assert_true(
            member[i].r - member[i].g > 2.0 * LEVEL,
            "%s: and at %s the blur carries the red past the chunk, %s" % [where, READS[i], member[i]]
        )


static func _gap(one: Color, other: Color) -> float:
    return maxf(maxf(absf(one.r - other.r), absf(one.g - other.g)), maxf(absf(one.b - other.b), absf(one.a - other.a)))


## The largest difference over every texel of two pictures, and where.
static func _worst(one: PackedByteArray, other: PackedByteArray, texture: SaTexture) -> Array:
    var worst := 0.0
    var at := -1
    for i in texture.size.x * texture.size.y:
        var gap := _gap(SaFieldSpec.decode_texel(one, texture.format, i), SaFieldSpec.decode_texel(other, texture.format, i))
        if gap > worst:
            worst = gap
            at = i
    return [worst, Vector2i(at % texture.size.x, floori(at / float(texture.size.x))) if at >= 0 else Vector2i(-1, -1)]


func test_the_blur_on_the_group_spills_whichever_layer_is_active() -> void:
    _blur(_group)
    _assert_same_spill("A blur on the group")


func test_the_blur_on_a_group_nested_in_another_spills_alike() -> void:
    _blur(_group)
    var outer := SaLayerOps.new(_doc).group_layers([_group])
    assert_true(outer != null and outer != _group, "The group is nested in a second one")
    _assert_same_spill("A blur on the inner group")


func test_the_blur_on_the_outer_group_spills_alike() -> void:
    var outer := SaLayerOps.new(_doc).group_layers([_group])
    _blur(outer)
    _assert_same_spill("A blur on the outer group")


func test_a_second_filter_on_the_group_spills_alike() -> void:
    _blur(_group)
    _blur(_group, 6.0)
    _assert_same_spill("Two blurs on the group")


func test_the_members_own_blur_under_the_groups_spills_alike() -> void:
    _blur(_paint, 6.0)
    _blur(_group)
    _assert_same_spill("A blur on the member and one on the group")


func test_a_stroke_on_the_member_redrawn_alone_is_the_full_composite() -> void:
    _assert_stroke_redrawn(false)


func test_a_stroke_on_a_blurred_member_redrawn_alone_is_the_full_composite() -> void:
    _assert_stroke_redrawn(true)


## A live stroke on Paint, active, under the group's blur and, with
## *member_blur*, a blur of its own as well, redrawn over its chunk alone, and
## then the whole document composited with Paint active and with Background
## active. The three pictures are one, and the stroke spills past the chunk.
func _assert_stroke_redrawn(member_blur: bool) -> void:
    if member_blur:
        _blur(_paint, 6.0)
    _blur(_group)
    _doc.set_active_layer(_paint)
    Bench.composite(_easel)
    # A live stroke over the member's chunk, redrawn over that chunk and not the
    # document, so the ring the group's reach makes dirty is all that moves.
    _doc.stroke_layer.get_or_create_chunk(HELD).clear(YELLOW)
    _doc.stroke_layer.visible = true
    _doc.invalidate_chunk_regions({HELD: SaDocument.WHOLE_CHUNK})
    _easel.process_pending_composite()
    var rd := GlobalShaderCompiler.get_rd()
    var partial := rd.texture_get_data(_easel.output.rid, 0)
    var past := Bench.texel(_easel.output, READS[0])
    _doc.commit_stroke()
    _doc.set_active_layer(_background)
    Bench.composite(_easel)
    var whole := rd.texture_get_data(_easel.output.rid, 0)
    var worst := _worst(partial, whole, _easel.output)
    var where := "with the member's own blur" if member_blur else "under the group's blur alone"
    assert_true(
        worst[0] <= LEVEL, "%s: the stroke redrawn alone is the full composite, worst %.4f at %s" % [where, worst[0], worst[1]]
    )
    assert_true(past.g > GREY.g + 2.0 * LEVEL, "%s: and the stroke carries its spill past the chunk, %s" % [where, past])


## Rule 2: the gather grows by the ring a group's reach makes dirty and no
## further, and a group with no neighbourhood filter grows it not at all.
func test_the_gather_grows_by_the_ring_alone() -> void:
    _doc.set_active_layer(_paint)
    var held: Dictionary[Vector2i, bool] = {HELD: true}
    var chain := _easel.compositor.filter_chain
    Bench.composite(_easel)
    assert_eq(SaScopeReach.walked(chain, _doc, held).size(), 1, "A group with no filter gathers the member's chunk alone")
    SaFilterOps.new(_doc).attach(_group, Bench.INVERT)
    Bench.composite(_easel)
    assert_eq(SaScopeReach.walked(chain, _doc, held).size(), 1, "and so does one whose filter reads a texel alone")
    _blur(_group)
    Bench.composite(_easel)
    var grown := SaScopeReach.walked(chain, _doc, held)
    assert_eq(grown.size(), 9, "A blur on the group gathers the eight positions around the chunk as well")
    for grid_pos: Vector2i in grown:
        assert_true(absi(grid_pos.x - HELD.x) <= 1 and absi(grid_pos.y - HELD.y) <= 1, "and %s is one of them" % grid_pos)
