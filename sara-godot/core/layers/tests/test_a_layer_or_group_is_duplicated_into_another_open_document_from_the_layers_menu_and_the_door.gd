## A layer or group is duplicated into another open document,
## from the Layers menu and the door, `SaLayerDuplicateTo`.
##
## Two documents are open. The first holds a group, Season, of three paint
## layers, Sky, Hill with a mask, a Multiply blend and an opacity of 0.6, and
## Boat hidden and locked, with a Mirror Effect Layer reading Boat inside it.
## The second holds a Season of its own with one layer, Old, in it. The group
## is copied into the second with `replace`, and every texel, the mask, the
## blend, the opacity and the mirror's input there read as the first's.
extends "res://tests/test_framework.gd"

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")
const Fixtures = preload("res://tests/fixtures.gd")
const MirrorFilter = preload("res://modules/sara-base-modules/base/usual/mirror_filter.gd")

const REQUIRES_GPU := true

const OWNER: StringName = &"sara-base-modules"
const MIRROR: StringName = &"sara-base-modules.mirror"
const SIZE := Vector2i(512, 512)

var _types: SaLayerTypeRegistry
var _easels: Array[SaEasel] = []
var _from: SaDocument
var _to: SaDocument


func before_each() -> void:
    _types = Fixtures.make_registries().layer_types
    _easels = [_easel(), _easel()]
    _from = _easels[0].document
    _to = _easels[1].document


func after_each() -> void:
    for easel in _easels:
        easel.free()
    _easels.clear()


static func _easel() -> SaEasel:
    var easel := Bench.easel(SIZE)
    easel.compositor.filter_chain.registry.register(MirrorFilter.new(), OWNER)
    return easel


## The first document's Season, built as the header says, answered.
func _season() -> SaLayer:
    var ops := SaLayerOps.new(_from)
    var sky := _from.get_node("Layer 1") as SaLayer
    sky.name = "Sky"
    sky.get_or_create_chunk(Vector2i(0, 0)).clear(Color(0.2, 0.4, 2.5, 1.0))
    var hill := ops.add(&"", _types)
    hill.name = "Hill"
    hill.get_or_create_chunk(Vector2i(1, 1)).clear(Color(0.1, 0.6, 0.05, 0.75))
    hill.add_mask(1.0).get_or_create(Vector2i(1, 1)).clear(Color(0.25, 0.25, 0.25, 0.25))
    ops.set_blend_mode(hill, &"multiply")
    hill.opacity = 0.6
    var boat := ops.add(&"", _types)
    boat.name = "Boat"
    boat.get_or_create_chunk(Vector2i(0, 1)).clear(Color(1.5, 0.0, 0.0, 1.0))
    boat.visible = false
    boat.is_locked = true
    _from.set_active_layer(boat)
    var mirror := ops.add(SaEffectLayer.TYPE_ID, _types)
    mirror.name = "Mirror"
    mirror.source = boat
    assert_not_null(SaFilterOps.new(_from).attach(mirror, MIRROR, {}), "The Mirror attaches to the effect layer")
    var season := ops.group_layers([sky, hill, boat, mirror])
    season.name = "Season"
    return season


## The second document's Season, holding Old alone.
func _old_season() -> SaLayer:
    var old := _to.get_node("Layer 1") as SaLayer
    old.name = "Old"
    old.get_or_create_chunk(Vector2i(0, 0)).clear(Color(0.9, 0.9, 0.9, 1.0))
    var season := SaLayerOps.new(_to).group_layers([old])
    season.name = "Season"
    return season


func test_a_group_replaced_in_the_other_document_reads_as_the_first_s() -> void:
    var season := _season()
    _old_season()
    var steps_before := _from.history.step_count()
    var answer := SaLayerDuplicateTo.new(_from, _to).write(season, null, true)
    assert_false(answer.has("error"), "The copy is made: %s" % str(answer))
    assert_eq(answer["replaced"], "Season", "The second document's Season is the one replaced")
    assert_eq((answer["missing"] as Array).size(), 0, "Nothing the copy reads is missing")
    assert_null(_named(_to, "Old"), "Old went with the Season it was in")
    for wanted: String in ["Sky", "Hill", "Boat", "Mirror"]:
        var original := _named(_from, wanted)
        var copy := _named(_to, wanted)
        assert_not_null(copy, "%s is in the second document under its own name" % wanted)
        assert_eq(String(SaLayerStack.parent_of(copy).name), "Season", "%s is inside the copied Season" % wanted)
        _assert_same(original, copy)
    assert_true(_named(_to, "Season").is_group, "The copied Season is a group")
    assert_eq(_named(_to, "Mirror").source, _named(_to, "Boat"), "The mirror reads the copied Boat")
    assert_eq(_from.history.step_count(), steps_before, "The first document records nothing")


func test_one_undo_in_the_target_puts_back_what_was_replaced() -> void:
    var season := _season()
    var old_season := _old_season()
    SaLayerDuplicateTo.new(_from, _to).write(season, null, true)
    assert_true(_to.undo(), "One step undoes the copy")
    assert_null(_named(_to, "Sky"), "The copies left together")
    assert_eq(_named(_to, "Season"), old_season, "The old Season is back")
    assert_eq(SaLayerStack.parent_of(_named(_to, "Old")), old_season, "Old is back inside it")
    assert_true(_to.redo(), "And redo brings the copy back")
    assert_not_null(_named(_to, "Sky"), "Sky is back")
    assert_null(_named(_to, "Old"), "Old went again")


func test_an_input_the_target_lacks_is_named_in_the_answer() -> void:
    var season := _season()
    var outside := SaLayerOps.new(_from).add(SaEffectLayer.TYPE_ID, _types)
    outside.name = "Echo"
    outside.source = season
    var answer := SaLayerDuplicateTo.new(_from, _to).write(outside)
    assert_eq((answer["missing"] as Array).size(), 1, "One input is missing: %s" % str(answer))
    assert_true(String(answer["missing"][0]).contains("Season"), "The missing input is named")
    assert_null(_named(_to, "Echo").source, "The copy reads nothing rather than the first document's group")
    _old_season()
    var again := SaLayerDuplicateTo.new(_from, _to).write(outside, null, true)
    assert_eq((again["missing"] as Array).size(), 0, "A Season of the target's own is read by name")
    assert_eq(_named(_to, "Echo").source, _named(_to, "Season"), "The input is the target's Season")


func test_a_copy_under_a_group_lands_on_top_of_its_members() -> void:
    var season := _season()
    var old_season := _old_season()
    var answer := SaLayerDuplicateTo.new(_from, _to).write(_named(_from, "Hill"), old_season)
    assert_eq(answer["copied"], ["Hill"], "Hill is copied alone")
    var hill := _named(_to, "Hill")
    assert_eq(SaLayerStack.parent_of(hill), old_season, "It sits in the named group")
    assert_eq(hill.get_index(), old_season.get_index() - 1, "On top of the group's members")
    assert_not_null(season, "The source is untouched")
    var refused := SaLayerDuplicateTo.new(_from, _from).write(season)
    assert_true(refused.has("error"), "A copy into its own document is refused")


func _assert_same(original: SaLayer, copy: SaLayer) -> void:
    var what := String(original.name)
    assert_eq(copy.blend_mode, original.blend_mode, "%s blends as the first's" % what)
    assert_eq(copy.opacity, original.opacity, "%s's opacity is the first's" % what)
    assert_eq(copy.visible, original.visible, "%s's visibility is the first's" % what)
    assert_eq(copy.is_locked, original.is_locked, "%s's lock is the first's" % what)
    assert_eq(copy.layer_type, original.layer_type, "%s is the same kind" % what)
    assert_eq(copy.filters.size(), original.filters.size(), "%s carries the same filters" % what)
    for i in original.filters.size():
        assert_eq(copy.filters[i].key, original.filters[i].key, "%s's filter %d is the same" % [what, i])
        assert_eq(copy.filters[i].parameters, original.filters[i].parameters, "%s's filter %d has its values" % [what, i])
    assert_eq(copy.chunks.keys(), original.chunks.keys(), "%s holds the same chunks" % what)
    for grid_pos: Vector2i in original.chunks:
        var a: SaChunk = original.chunks[grid_pos]
        var b: SaChunk = copy.chunks[grid_pos]
        assert_false(a == b, "%s's chunk is a copy and not the same object" % what)
        for field: StringName in a.field_ids():
            assert_eq(_bytes(b.field(field)), _bytes(a.field(field)), "%s's %s texels are the first's" % [what, field])
    assert_eq(copy.mask != null, original.mask != null, "%s has a mask where the first's has" % what)
    if original.mask == null:
        return
    assert_eq(copy.mask.rest, original.mask.rest, "%s's mask rests where the first's does" % what)
    assert_eq(copy.mask.grid_positions(), original.mask.grid_positions(), "%s's mask holds the same chunks" % what)
    for grid_pos in original.mask.grid_positions():
        var a_mask := original.mask.get_or_create(grid_pos)
        var b_mask := copy.mask.get_or_create(grid_pos)
        assert_eq(_bytes(b_mask), _bytes(a_mask), "%s's mask texels are the first's" % what)


static func _bytes(texture: SaTexture) -> PackedByteArray:
    return GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)


static func _named(doc: SaDocument, wanted: String) -> SaLayer:
    for child in doc.get_children():
        if child is SaLayer and String(child.name) == wanted:
            return child
    return null
