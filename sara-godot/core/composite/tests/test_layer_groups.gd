## Layer groups: a tree in the document, pass-through and isolated.
##
## The document stays a flat list and a layer belongs to a group through a
## reference, saved as the group's name, so an older build reads the file flat
## with the group as an empty layer. A pass-through group's members composite
## in place with its opacity multiplied in. An isolated group folds its members
## into a cache of its own and joins the stack as one step with its mode and
## opacity, and with the active layer inside it becomes a scope the compositor
## renders through a scratch, which is the fifth surface the tier model had no
## room for.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

## Needs a RenderingDevice. The runner skips this suite without one.
const REQUIRES_GPU := true

const GREY := Color(0.5, 0.5, 0.5, 1.0)
const RED := Color(1, 0, 0, 1)
const GREEN := Color(0, 1, 0, 1)


func _easel(size: Vector2i = Vector2i(256, 256)) -> SaEasel:
    var easel := SaEasel.create_default(size)
    easel.compositor.set_registry(Fixtures.make_registries().blend_modes)
    return easel


func _texel(texture: SaTexture, x: int, y: int) -> Color:
    var data: PackedByteArray = GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    var at := (y * texture.size.x + x) * 16
    return Color(data.decode_float(at), data.decode_float(at + 4), data.decode_float(at + 8), data.decode_float(at + 12))


func _composite(easel: SaEasel) -> void:
    easel.request_full_composite()
    easel.process_pending_composite()


func _layer_named(doc: SaDocument, layer_name: String) -> SaLayer:
    return doc.get_node(layer_name) as SaLayer


## Where the bottom of *group*'s block sits, which is the index its lowest
## member holds and what `place` counts from.
func _member_slot(doc: SaDocument, group: SaLayer) -> int:
    return SaLayerStack.members(doc, group)[0].get_index()


func _names(doc: SaDocument) -> Array[String]:
    var out: Array[String] = []
    for layer in SaLayerOps.new(doc).layers():
        out.append(str(layer.name))
    return out


## Background, Layer 1 active, and a Multiply layer of mid grey above it, then
## that Multiply layer wrapped in a group with Layer 1 made active again.
func _document_with_grouped_multiply(easel: SaEasel) -> SaLayer:
    var doc := easel.document
    var multiply := SaLayerOps.new(doc).add()
    multiply.name = "Multiply"
    SaLayerOps.new(doc).set_blend_mode(multiply, &"multiply")
    doc.fill_layer(GREY, multiply)
    var group := SaLayerOps.new(doc).group_active()
    doc.set_active_layer(_layer_named(doc, "Layer 1"))
    doc.fold.debt.settle(doc)
    return group


func test_grouping_wraps_the_active_layer_and_undo_unwraps_it() -> void:
    var easel := _easel()
    var doc := easel.document
    var layer := doc.active_layer
    var group := SaLayerOps.new(doc).group_active()

    assert_true(group.is_group, "A group is a layer flagged as one")
    assert_true(group.is_locked, "and reports locked, since there is nothing in it to paint on")
    assert_eq(_names(doc), ["Background", "Layer 1", "Group 1"], "placed right above its member in the order")
    assert_eq(SaLayerStack.parent_of(layer), group, "which now belongs to it")
    assert_eq(SaLayerStack.depth(layer), 1, "one level down")
    assert_true(group.chunks.is_empty(), "A group holds no paint")

    doc.undo()
    assert_eq(_names(doc), ["Background", "Layer 1"], "Undo takes the group out")
    assert_null(SaLayerStack.parent_of(layer), "and the layer is at the top level again")
    doc.redo()
    assert_eq(_names(doc), ["Background", "Layer 1", "Group 1"], "Redo puts it back")
    assert_eq(SaLayerStack.parent_of(layer), group, "with its member")

    easel.free()


## Pass-through: the Multiply inside the group multiplies the painting under
## the group, exactly as it did ungrouped.
func test_a_pass_through_group_composites_its_members_in_place() -> void:
    var easel := _easel()
    var group := _document_with_grouped_multiply(easel)
    assert_false(group.isolated, "Pass-through by default")
    assert_eq(easel.document.fold.top_stack.size(), 1, "The member is walked as one step")
    assert_eq(
        easel.document.fold.top_stack[0][SaLayerStack.LAYER], _layer_named(easel.document, "Multiply"), "from its own chunks"
    )

    _composite(easel)
    assert_almost_eq(_texel(easel.output, 10, 10).r, 0.25, 0.02, "Grey times grey, through the group")

    easel.free()


## Isolated: the members composite together first, over transparent, so the
## Multiply has nothing under it inside the group and comes out as its own
## grey, and that result is what the canvas sees with the group's mode.
func test_an_isolated_group_composites_its_members_together_first() -> void:
    var easel := _easel()
    var doc := easel.document
    var group := _document_with_grouped_multiply(easel)
    SaLayerOps.new(doc).set_isolated(group, true)
    doc.fold.debt.settle(doc)

    assert_eq(doc.fold.top_stack.size(), 1, "The group is one step")
    assert_true(doc.fold.top_stack[0][SaLayerStack.LAYER] != _layer_named(doc, "Multiply"), "through a cache of its own")
    _composite(easel)
    assert_almost_eq(_texel(easel.output, 10, 10).r, 0.5, 0.02, "Grey over transparent is grey, then Normal over the painting")

    doc.undo()
    assert_false(group.isolated, "Isolation is a step")
    _composite(easel)
    assert_almost_eq(_texel(easel.output, 10, 10).r, 0.25, 0.02, "and undoing it multiplies again")

    easel.free()


## The group's own opacity and mode apply to the folded result.
func test_an_isolated_group_has_opacity_and_a_mode_of_its_own() -> void:
    var easel := _easel()
    var doc := easel.document
    var red := SaLayerOps.new(doc).add()
    doc.fill_layer(RED, red)
    var group := SaLayerOps.new(doc).group_active()
    SaLayerOps.new(doc).set_opacity(group, 0.5)
    SaLayerOps.new(doc).set_isolated(group, true)
    doc.set_active_layer(_layer_named(doc, "Layer 1"))
    doc.fold.debt.settle(doc)
    _composite(easel)
    var texel := _texel(easel.output, 10, 10)
    assert_almost_eq(texel.r, 0.75, 0.02, "Red at half over grey")
    assert_almost_eq(texel.g, 0.25, 0.02, "which is what the group's opacity means")

    SaLayerOps.new(doc).set_blend_mode(group, &"multiply")
    SaLayerOps.new(doc).set_opacity(group, 1.0)
    # A slider's rebuild is folded to the end of the frame, so ask for it.
    doc.update_caches()
    _composite(easel)
    assert_almost_eq(_texel(easel.output, 10, 10).g, 0.0, 0.02, "and Multiply on the group multiplies the whole of it")

    easel.free()


## A pass-through group's opacity multiplies into each member's.
func test_a_pass_through_group_opacity_multiplies_into_its_members() -> void:
    var easel := _easel()
    var doc := easel.document
    var red := SaLayerOps.new(doc).add()
    doc.fill_layer(RED, red)
    var group := SaLayerOps.new(doc).group_active()
    SaLayerOps.new(doc).set_opacity(group, 0.5)
    doc.set_active_layer(_layer_named(doc, "Layer 1"))
    doc.fold.debt.settle(doc)
    assert_almost_eq(doc.fold.top_stack[0][SaLayerStack.OPACITY], 0.5, 0.001, "The member's step carries the group's opacity")
    _composite(easel)
    assert_almost_eq(_texel(easel.output, 10, 10).r, 0.75, 0.02, "Red at half over grey")

    easel.free()


## Painting inside an isolated group: the active layer and the live stroke
## composite into the group's scratch with the members around them, and the
## group's opacity applies to the whole, stroke included.
func test_the_active_layer_inside_an_isolated_group_is_a_scope() -> void:
    var easel := _easel()
    var doc := easel.document
    var painted := SaLayerOps.new(doc).add()
    var group := SaLayerOps.new(doc).group_active()
    SaLayerOps.new(doc).set_isolated(group, true)
    SaLayerOps.new(doc).set_opacity(group, 0.5)
    var above := SaLayerOps.new(doc).add()
    above.get_or_create_chunk(Vector2i(0, 0))
    doc.set_active_layer(painted)
    doc.fold.debt.settle(doc)

    assert_eq(doc.fold.active_scopes.size(), 1, "One isolated group around the active layer")
    assert_eq(doc.fold.active_scopes[0][SaLayerStack.GROUP], group, "that one")
    assert_eq(doc.fold.active_scopes[0][SaLayerStack.TOP].size(), 1, "with the layer above inside it")
    assert_true(doc.fold.top_stack.is_empty(), "and nothing above the group at the top level")

    doc.stroke_layer.get_or_create_chunk(Vector2i(0, 0)).clear(RED)
    _composite(easel)
    var texel := _texel(easel.output, 10, 10)
    assert_almost_eq(texel.r, 0.75, 0.02, "The stroke at the group's half over grey")
    assert_almost_eq(texel.g, 0.25, 0.02, "not at full")
    doc.stroke_layer.chunks.clear()

    easel.free()


## Selecting the group in the docker makes it the active layer, and nothing
## paints on it, so its members composite as if a neighbour were active.
func test_an_active_group_still_composites_its_members() -> void:
    var easel := _easel()
    var doc := easel.document
    var group := _document_with_grouped_multiply(easel)
    doc.set_active_layer(group)
    doc.fold.debt.settle(doc)
    assert_true(doc.fold.active_scopes.is_empty(), "No scope, since there is no live tier inside the group")
    _composite(easel)
    assert_almost_eq(_texel(easel.output, 10, 10).r, 0.25, 0.02, "The Multiply inside still multiplies")
    SaLayerOps.new(doc).set_isolated(group, true)
    _composite(easel)
    assert_almost_eq(_texel(easel.output, 10, 10).r, 0.5, 0.02, "and isolated it covers")
    easel.free()


func test_a_hidden_group_hides_its_members() -> void:
    var easel := _easel()
    var doc := easel.document
    var group := _document_with_grouped_multiply(easel)
    SaLayerOps.new(doc).set_visible(group, false)
    assert_true(doc.fold.top_stack.is_empty(), "Nothing above the active layer is walked")
    _composite(easel)
    assert_almost_eq(_texel(easel.output, 10, 10).r, 0.5, 0.02, "and the background shows")
    easel.free()


func test_ungroup_returns_the_members_to_the_parent_and_undo_regroups() -> void:
    var easel := _easel()
    var doc := easel.document
    var group := _document_with_grouped_multiply(easel)
    var member := _layer_named(doc, "Multiply")
    assert_true(SaLayerOps.new(doc).ungroup(group), "Ungrouped")
    assert_null(SaLayerStack.parent_of(member), "The member is at the top level")
    assert_eq(_names(doc), ["Background", "Layer 1", "Multiply"], "and the group is gone")
    doc.undo()
    assert_eq(SaLayerStack.parent_of(member), group, "Undo groups it again")
    easel.free()


func test_deleting_a_group_takes_its_members_and_undo_brings_them_back_grouped() -> void:
    var easel := _easel()
    var doc := easel.document
    var group := _document_with_grouped_multiply(easel)
    var member := _layer_named(doc, "Multiply")
    assert_true(SaLayerOps.new(doc).remove_group(group), "Deleted")
    assert_eq(_names(doc), ["Background", "Layer 1"], "with everything inside it")
    _composite(easel)
    assert_almost_eq(_texel(easel.output, 10, 10).r, 0.5, 0.02, "and nothing multiplies any more")
    doc.undo()
    assert_eq(_names(doc), ["Background", "Layer 1", "Multiply", "Group 1"], "Undo brings the whole subtree back")
    assert_eq(SaLayerStack.parent_of(member), group, "still grouped")
    easel.free()


## A drag in the docker is a placement: into a group, at an index, with the
## subtree following a group as a block.
func test_placing_a_group_moves_its_subtree_as_a_block() -> void:
    var easel := _easel()
    var doc := easel.document
    var group := _document_with_grouped_multiply(easel)
    var top := SaLayerOps.new(doc).add()
    top.name = "Top"
    doc.set_active_layer(_layer_named(doc, "Layer 1"))
    doc.fold.debt.settle(doc)
    assert_eq(_names(doc), ["Background", "Layer 1", "Top", "Multiply", "Group 1"], "Top sits between Layer 1 and the group")

    assert_false(SaLayerOps.new(doc).place(group, null, 4), "The group asked up is refused")
    assert_eq(
        _names(doc), ["Background", "Layer 1", "Top", "Multiply", "Group 1"], "past nothing, since it was already at the top"
    )
    assert_true(SaLayerOps.new(doc).place(group, null, 1), "and down")
    assert_eq(_names(doc), ["Background", "Multiply", "Group 1", "Layer 1", "Top"], "with its member still under it")
    doc.undo()
    assert_eq(_names(doc), ["Background", "Layer 1", "Top", "Multiply", "Group 1"], "and undo restores every index")

    # The group's block starts at Multiply, and Top comes from under it, so
    # taking Top out leaves that block one lower than it reads now.
    assert_true(SaLayerOps.new(doc).place(top, group, _member_slot(doc, group) - 1), "A layer placed into the group")
    assert_eq(SaLayerStack.parent_of(top), group, "belongs to it")
    assert_eq(_names(doc), ["Background", "Layer 1", "Top", "Multiply", "Group 1"], "as its bottom member")
    assert_false(SaLayerOps.new(doc).place(group, group, 0), "A group cannot be placed inside itself")

    easel.free()


## A clip never reaches out of its group: the base is a sibling.
func test_a_clip_base_is_a_sibling_inside_the_same_group() -> void:
    var easel := _easel()
    var doc := easel.document
    var group := _document_with_grouped_multiply(easel)
    var member := _layer_named(doc, "Multiply")
    SaLayerStack.set_clip_to_below(doc, member, true)
    assert_null(SaLayerStack.clip_base(doc, member), "Nothing sits below the member inside its group")
    var top := SaLayerOps.new(doc).add()
    SaLayerOps.new(doc).place(top, group, _member_slot(doc, group) - 1)
    assert_eq(SaLayerStack.clip_base(doc, member), top, "A sibling below it is the base")
    easel.free()


## The header carries the parent's name, additively, and the join happens
## after every layer exists, so the order of the two in the file cannot matter.
func test_groups_round_trip_through_the_file() -> void:
    var easel := _easel()
    var doc := easel.document
    var group := _document_with_grouped_multiply(easel)
    SaLayerOps.new(doc).set_isolated(group, true)
    var path := SaDataRoot.path("test_groups_round_trip.sad")
    assert_eq(SaExport.save_sad(doc, path), OK, "Saved")

    var loaded := SaDocument.new()
    assert_eq(SaExport.load_sad(loaded, path, SaCompositor.new()), OK, "and loaded")
    var loaded_group := _layer_named(loaded, "Group 1")
    assert_true(loaded_group.is_group, "The group is a group")
    assert_true(loaded_group.isolated, "and isolated")
    assert_eq(SaLayerStack.parent_of(_layer_named(loaded, "Multiply")), loaded_group, "with its member joined to it")
    assert_null(SaLayerStack.parent_of(_layer_named(loaded, "Layer 1")), "and the rest at the top level")

    loaded.free()
    easel.free()
    DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## The docker draws one row per child from the highest index down, so the
## group's own row is above its members only when its index is above theirs.
func test_a_new_group_sits_above_every_layer_it_wrapped() -> void:
    var easel := _easel()
    var doc := easel.document
    var lower := doc.active_layer
    var upper := SaLayerOps.new(doc).add()
    upper.name = "Upper"
    var spare := SaLayerOps.new(doc).add()
    spare.name = "Spare"

    var group := SaLayerOps.new(doc).group_layers([lower, upper])
    assert_eq(_names(doc), ["Background", "Layer 1", "Upper", "Group 1", "Spare"], "The group closes the run it collected")
    for member: SaLayer in SaLayerStack.members(doc, group):
        assert_true(group.get_index() > member.get_index(), "and outranks %s, so its row draws above it" % member.name)
    var kept: Array[String] = []
    for member: SaLayer in SaLayerStack.members(doc, group):
        kept.append(str(member.name))
    assert_eq(kept, ["Layer 1", "Upper"], "The members keep the order they were in")

    doc.undo()
    assert_eq(_names(doc), ["Background", "Layer 1", "Upper", "Spare"], "Undo puts the run back as it was")
    doc.redo()
    assert_eq(_names(doc), ["Background", "Layer 1", "Upper", "Group 1", "Spare"], "and redo wraps it again")

    easel.free()


## The order is the file's, not something the loader derives, so a `.sad`
## written by a build that put the group under its members opens with the
## group still under them. Nothing migrates: an old document is left as its
## author saved it, and only a new group is wrapped the new way.
func test_a_file_saved_with_the_group_below_its_members_opens_unchanged() -> void:
    var easel := _easel()
    var doc := easel.document
    var group := _document_with_grouped_multiply(easel)
    # What 0.4.0 wrote: the group first, then everything it holds.
    doc.move_child(group, SaLayerStack.members(doc, group)[0].get_index())
    assert_eq(_names(doc), ["Background", "Layer 1", "Group 1", "Multiply"], "The old arrangement, by hand")

    var path := SaDataRoot.path("test_groups_legacy_order.sad")
    assert_eq(SaExport.save_sad(doc, path), OK, "Saved")
    var loaded := SaDocument.new()
    assert_eq(SaExport.load_sad(loaded, path, SaCompositor.new()), OK, "and loaded")
    assert_eq(_names(loaded), ["Background", "Layer 1", "Group 1", "Multiply"], "opens in the order it was written")
    assert_eq(
        SaLayerStack.parent_of(_layer_named(loaded, "Multiply")),
        _layer_named(loaded, "Group 1"),
        "with its member still joined to it"
    )

    loaded.free()
    easel.free()
    DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
