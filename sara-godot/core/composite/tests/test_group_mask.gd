## A group carries a mask: the mask hides the group's composite,
## after its members are folded and before its own mode and opacity apply, and a
## pass-through group isolates while it carries one, because a mask hides a
## composite and a pass-through group has none. `SaLayerStack.isolates` is the
## one place that says so, and the `isolated` flag is never written for it.
##
## Every case runs twice, once with the group folded into a cache and once with
## the active layer inside it, where the group is a scope the compositor renders
## through a scratch. Those are the two places a group's composite is made.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

## Needs a RenderingDevice. The runner skips this suite without one.
const REQUIRES_GPU := true

const RED := Color(1, 0, 0, 1)
const GREY := Color(0.5, 0.5, 0.5, 1)

## The three columns of the first chunk the painted mask holds, and a texel in
## each: shown, hidden, half.
const SHOWN_AT := Vector2i(40, 10)
const HIDDEN_AT := Vector2i(120, 10)
const HALF_AT := Vector2i(200, 10)
## A texel of the second chunk, where the mask was never painted.
const UNPAINTED_AT := Vector2i(300, 10)


func _easel() -> SaEasel:
    var easel := SaEasel.create_default(Vector2i(512, 256))
    easel.compositor.set_registry(Fixtures.make_registries().blend_modes)
    return easel


func _texel(texture: SaTexture, at: Vector2i) -> Color:
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    return SaFieldSpec.decode_texel(bytes, texture.format, at.y * texture.size.x + at.x)


func _composite(easel: SaEasel) -> void:
    easel.document.update_caches()
    easel.request_full_composite()
    easel.process_pending_composite()


func _assert_colour(actual: Color, expected: Color, what: String) -> void:
    assert_almost_eq(actual.r, expected.r, 0.02, what + ", red")
    assert_almost_eq(actual.g, expected.g, 0.02, what + ", green")
    assert_almost_eq(actual.b, expected.b, 0.02, what + ", blue")


## Gives *group* a mask and writes the three columns into it at the first chunk:
## one up to x 85, zero up to 170, a half beyond.
func _paint_mask(group: SaLayer) -> void:
    var texture := group.add_mask().get_or_create(Vector2i(0, 0))
    var values := PackedFloat32Array()
    values.resize(texture.size.x * texture.size.y)
    for y in texture.size.y:
        for x in texture.size.x:
            values[y * texture.size.x + x] = 1.0 if x < 85 else (0.0 if x < 170 else 0.5)
    GlobalShaderCompiler.get_rd().texture_update(texture.rid, 0, values.to_byte_array())


## A layer called *layer_name* filled with *colour* in *mode*, wrapped in a
## group of its own. Answers the group.
func _grouped(doc: SaDocument, layer_name: String, colour: Color, mode: StringName) -> SaLayer:
    var ops := SaLayerOps.new(doc)
    var member := ops.add()
    member.name = layer_name
    ops.set_blend_mode(member, mode)
    doc.fill_layer(colour, member)
    return ops.group_active()


## Makes the member active when *inside*, so the group is a scope, and Layer 1
## below it otherwise, so the group folds into a cache.
func _activate(doc: SaDocument, member: String, inside: bool) -> String:
    doc.set_active_layer(doc.get_node(member if inside else "Layer 1") as SaLayer)
    return " (scope)" if inside else " (folded)"


func _check_the_mask_hides_the_members(inside: bool) -> void:
    var easel := _easel()
    var doc := easel.document
    var group := _grouped(doc, "Red", RED, &"normal")
    _paint_mask(group)
    var where := _activate(doc, "Red", inside)
    _composite(easel)

    _assert_colour(_texel(easel.output, SHOWN_AT), RED, "Where the group's mask is one its members show" + where)
    _assert_colour(_texel(easel.output, HIDDEN_AT), GREY, "Where it is zero the background shows" + where)
    _assert_colour(_texel(easel.output, HALF_AT), Color(0.75, 0.25, 0.25), "Where it is a half, half the members" + where)
    _assert_colour(_texel(easel.output, UNPAINTED_AT), RED, "A chunk the mask never held shows whole" + where)
    assert_false(group.isolated, "The mask isolates the group without writing its flag" + where)

    group.mask.enabled = false
    _composite(easel)
    for at: Vector2i in [SHOWN_AT, HIDDEN_AT, HALF_AT]:
        _assert_colour(_texel(easel.output, at), RED, "A group mask switched off reads as one at %s%s" % [at, where])
    easel.free()


func test_a_masked_groups_members_composite_through_the_mask_folded() -> void:
    _check_the_mask_hides_the_members(false)


func test_a_masked_groups_members_composite_through_the_mask_as_a_scope() -> void:
    _check_the_mask_hides_the_members(true)


## A grey Multiply inside a group over the grey background. Pass-through it
## multiplies the painting under the group, 0.25. Isolated, it has nothing under
## it inside the group and comes out as its own grey, 0.5. A mask that hides
## nothing has to give the isolated reading, and dropping it the pass-through.
func _check_a_mask_isolates_a_pass_through_group(inside: bool) -> void:
    var easel := _easel()
    var doc := easel.document
    var group := _grouped(doc, "Multiply", GREY, &"multiply")
    var where := _activate(doc, "Multiply", inside)
    _composite(easel)
    var pass_through := _texel(easel.output, SHOWN_AT).r
    assert_almost_eq(pass_through, 0.25, 0.02, "Pass-through, grey times grey" + where)
    assert_false(SaLayerStack.isolates(group), "A plain group passes through" + where)

    SaLayerOps.new(doc).set_isolated(group, true)
    _composite(easel)
    var isolated := _texel(easel.output, SHOWN_AT).r
    assert_almost_eq(isolated, 0.5, 0.02, "Isolated, the Multiply has nothing under it" + where)
    doc.undo()
    assert_false(group.isolated, "The flag is back off" + where)

    group.add_mask()
    assert_true(SaLayerStack.isolates(group), "A group with a mask isolates" + where)
    _composite(easel)
    assert_almost_eq(_texel(easel.output, SHOWN_AT).r, isolated, 0.02, "and reads as the isolated group does" + where)
    assert_false(group.isolated, "with the flag never written" + where)

    group.mask.enabled = false
    _composite(easel)
    assert_almost_eq(_texel(easel.output, SHOWN_AT).r, isolated, 0.02, "Switching the mask off keeps the isolation" + where)

    group.drop_mask()
    assert_false(SaLayerStack.isolates(group), "Dropping the mask gives the pass-through back" + where)
    _composite(easel)
    assert_almost_eq(_texel(easel.output, SHOWN_AT).r, pass_through, 0.02, "and the Multiply reaches the painting again" + where)
    assert_false(group.isolated, "The flag was false throughout" + where)
    easel.free()


func test_a_mask_isolates_a_pass_through_group_folded() -> void:
    _check_a_mask_isolates_a_pass_through_group(false)


func test_a_mask_isolates_a_pass_through_group_as_a_scope() -> void:
    _check_a_mask_isolates_a_pass_through_group(true)


## A group's mask holds chunks of its own, so a group still stores no paint and
## gains no field its schema would allocate an albedo for.
func test_a_groups_mask_keeps_chunks_of_its_own() -> void:
    var easel := _easel()
    var doc := easel.document
    var group := _grouped(doc, "Red", RED, &"normal")
    _paint_mask(group)
    assert_true(group.mask.is_own(), "A group's mask is the own form")
    assert_null(SaFieldSpec.find(group.schema, SaFieldSpec.MASK), "and not a field of the group's schema")
    assert_true(group.chunks.is_empty(), "The group still holds no paint")
    assert_eq(group.mask.grid_positions().size(), 1, "The mask holds the one chunk it was painted at")
    easel.free()


## An isolated group around the active layer is a scope and must not also fold
## into a cache beside it. It did both, which an opaque member cannot show and a
## half-covered one reads as twice its cover (flag and mask alike).
func test_a_scope_is_composited_once() -> void:
    var easel := _easel()
    var doc := easel.document
    var group := _grouped(doc, "Red", RED, &"normal")
    SaLayerOps.new(doc).set_opacity(doc.get_node("Red") as SaLayer, 0.5)
    SaLayerOps.new(doc).set_isolated(group, true)
    _activate(doc, "Red", true)
    _composite(easel)
    _assert_colour(_texel(easel.output, SHOWN_AT), Color(0.75, 0.25, 0.25), "Half a red over grey, once")
    assert_eq(doc.fold.top_stack.size(), 0, "Nothing above the scope at the top level")
    easel.free()
