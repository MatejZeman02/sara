## Duplicate Layer gives a layer of the kind it copies: a group
## with copies of its members, a generated layer with its generator, and every
## property the file keeps. Before, the copy was a paint layer whatever it
## copied, so a group came out empty and a generated layer drew nothing.
##
## Each case reads the composite back from VRAM with the original hidden, so
## what shows is the copy alone, and then undoes the one step and finds the
## stack as it was.
extends "res://tests/test_framework.gd"

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")
const Fixtures = preload("res://tests/fixtures.gd")
const PaintKernel = preload("res://tests/fixtures/paint_kernel.gd")

const REQUIRES_GPU := true

const RED := Color(1.0, 0.0, 0.0, 1.0)
const PALE := Color(0.5, 0.5, 1.0, 1.0)
const GREEN := Color(0.0, 1.0, 0.0, 1.0)
const ORANGE := Color(1.0, 0.5, 0.0, 1.0)
const AT := Vector2i(300, 10)
## Where the clipping base holds a dab, and a place it holds nothing.
const DAB := Vector2i(100, 100)
const BARE := Vector2i(400, 200)

## Every property `SaSadFile` writes for a layer, bar the name a copy changes
## and the members compared by their own checks.
const KEPT: Array[StringName] = [
    &"visible",
    &"opacity",
    &"is_locked",
    &"alpha_locked",
    &"clip_to_below",
    &"is_group",
    &"isolated",
    &"blend_mode",
    &"layer_type",
    &"resolution_scale",
    &"comment",
    &"generator",
    &"generator_params",
    &"module_data",
]

var _easel: SaEasel = null
var _doc: SaDocument = null
var _ops: SaLayerOps = null


func before_each() -> void:
    _easel = Bench.easel(Vector2i(512, 256))
    _doc = _easel.document
    _ops = SaLayerOps.new(_doc)


func after_each() -> void:
    _easel.free()
    _easel = null
    _doc = null
    _ops = null


func _shown(at: Vector2i) -> Color:
    Bench.composite(_easel)
    return Bench.texel(_easel.output, at)


func _assert_colour(found: Color, expected: Color, what: String) -> void:
    assert_almost_eq(found.r, expected.r, 0.02, "%s, red: %s against %s" % [what, found, expected])
    assert_almost_eq(found.g, expected.g, 0.02, "%s, green: %s against %s" % [what, found, expected])
    assert_almost_eq(found.b, expected.b, 0.02, "%s, blue: %s against %s" % [what, found, expected])
    assert_almost_eq(found.a, expected.a, 0.02, "%s, alpha: %s against %s" % [what, found, expected])


func _assert_kept(copy: SaLayer, source: SaLayer, what: String) -> void:
    assert_true(copy != source, "%s is a layer of its own" % what)
    assert_true(str(copy.name) != str(source.name), "%s is named apart" % what)
    for key in KEPT:
        assert_eq(copy.get(key), source.get(key), "%s keeps %s" % [what, key])
    assert_eq(copy.schema.size(), source.schema.size(), "%s keeps the schema" % what)
    assert_eq(copy.chunks.keys(), source.chunks.keys(), "%s keeps the chunks" % what)


func _names() -> Array[String]:
    var names: Array[String] = []
    for layer in _ops.layers():
        var parent := str(layer.group.name) if layer.group != null else ""
        names.append("%s<%s" % [layer.name, parent])
    return names


## Duplicates *source*, checks the copy shows at *at* what the source showed
## there with the source hidden, and that undo leaves the stack as before.
func _duplicate_and_compare(source: SaLayer, at: Vector2i) -> SaLayer:
    var before := _shown(at)
    var names := _names()
    var steps := _doc.undo_redo.get_history_count()
    var copy := _ops.duplicate(source)
    assert_not_null(copy, "the duplicate is made")
    assert_eq(_doc.undo_redo.get_history_count(), steps + 1, "the duplicate is one step")
    _assert_colour(_shown(at), before, "the copy above adds nothing to %s" % source.name)
    source.visible = false
    _assert_colour(_shown(at), before, "the copy of %s shows what it showed" % source.name)
    source.visible = true
    _doc.undo_redo.undo()
    assert_eq(_names(), names, "undo leaves the stack as before")
    _assert_colour(_shown(at), before, "and the picture")
    _doc.undo_redo.redo()
    return copy


func _member(layer_name: String, colour: Color) -> SaLayer:
    var member := _ops.add()
    member.name = layer_name
    _ops.set_blend_mode(member, &"multiply")
    _doc.fill_layer(colour, member)
    return member


func _dab(pos: Vector2) -> void:
    var compute := PaintKernel.compute()
    var region := Rect2(pos.x - 12.0, pos.y - 12.0, 24.0, 24.0)
    _doc.begin_stroke(1.0, SaLayer.BLEND_MODE.NORMAL)
    var paint := SaPaintContext.for_region(_doc, region, false)
    paint.dispatch_batch(
        compute,
        "paint",
        func(target: SaPaintContext.Target) -> void:
            compute.set_texture(0, target.texture.rid)
            compute.set_push_constant_float_array(
                PaintKernel.pack_params(paint.local_point(target, pos), target.render_offset, RED, 12.0, 1.0, 1.0, 1.0)
            )
    )
    paint.commit_invalidation()
    _doc.commit_stroke()


func test_a_group_comes_back_with_its_members() -> void:
    var red := _member("Red", RED)
    var pale := _member("Pale", PALE)
    var group := _ops.group_layers([red, pale])
    _ops.set_isolated(group, true)
    var copy := _duplicate_and_compare(group, AT)
    _assert_kept(copy, group, "the group's copy")
    assert_eq(copy.get_index(), group.get_index() + 3, "on top of the block it heads")
    var inside := _ops.subtree(copy)
    assert_eq(inside.size(), 3, "holding a copy of each member")
    var red_copy: SaLayer = _doc.get_child(group.get_index() + 1)
    var pale_copy: SaLayer = _doc.get_child(group.get_index() + 2)
    assert_eq(red_copy.group, copy, "the first member's copy is inside the copy")
    assert_eq(pale_copy.group, copy, "and so is the second's")
    _assert_kept(red_copy, red, "the first member's copy")
    _assert_kept(pale_copy, pale, "the second member's copy")
    assert_eq(red.group, group, "while the originals stay in their own group")


func test_a_generated_layer_keeps_its_generator() -> void:
    var types := Fixtures.make_registries().layer_types
    var paper := _ops.add(&"paper", types)
    _doc.fill_layer(ORANGE, paper)
    assert_true(paper.is_generated(), "the paper is generated")
    var copy := _duplicate_and_compare(paper, AT)
    _assert_kept(copy, paper, "the paper's copy")
    assert_true(copy.is_generated(), "the copy evaluates the paper's generator")
    assert_true(copy.resolve_hook == paper.resolve_hook, "with the paper's resolve hook")
    copy.generator_params["color"] = GREEN
    assert_true(paper.generator_params.get("color") != GREEN, "and parameters of its own")


func test_a_clipped_layer_stays_clipped() -> void:
    var base := _ops.add()
    _dab(Vector2(DAB))
    var clipped := _ops.add()
    clipped.clip_to_below = true
    _doc.fill_layer(GREEN, clipped)
    var bare := _shown(BARE)
    var copy := _duplicate_and_compare(clipped, DAB)
    _assert_kept(copy, clipped, "the clipped layer's copy")
    _assert_colour(_shown(BARE), bare, "the copy shows nothing where the base holds nothing")
    assert_eq(base.get_index() + 2, copy.get_index(), "and sits above what it copies")


func test_a_comment_and_module_data_come_along() -> void:
    var noted := _ops.add()
    noted.comment = "the sky, redone"
    noted.module_data = {"d2-fixture": {"depth": 3, "list": [1, 2]}}
    _doc.fill_layer(PALE, noted)
    var copy := _duplicate_and_compare(noted, AT)
    _assert_kept(copy, noted, "the noted layer's copy")
    copy.module_data["d2-fixture"]["depth"] = 4
    assert_eq(noted.module_data["d2-fixture"]["depth"], 3, "and the copy's module data is its own")
