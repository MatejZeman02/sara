## A duplicated group applies its adjustment layers as the
## original does, before any save.
##
## `SaLayerDuplicate._copy` left out `input`, so an adjustment layer's copy
## composited as an empty paint layer, and only `SaLayerTypeRegistry.rebind`
## on a load put it right. The painting is a ground under a group holding a
## light, an adjustment layer brightening it, an effect layer inverting the
## light and a simulated layer. Each of the copy's members carries the fields
## its kind needs, the copy composites texel for texel as the original does
## with the original hidden, one undo takes the copy away whole, and a save and
## a load leave the copy's composite as it was.
extends "res://tests/test_framework.gd"

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")
const Fixtures = preload("res://tests/fixtures.gd")

const REQUIRES_GPU := true

const SIZE := Vector2i(512, 256)
const LEFT := Vector2i(0, 0)
const RIGHT := Vector2i(1, 0)
const GROUND := Color(0.125, 0.625, 0.25, 1.0)
const LIGHT := Color(0.75, 0.25, 0.125, 0.5)
const RECORD := {"brightness": 30.0, "contrast": 25.0}
const TOLERANCE := 1.0e-5
const COPIED_FIELDS: Array[String] = ["input", "scene", "scene_params", "folded"]

var _registries: SaRegistries
var _easels: Array[SaEasel] = []


func before_each() -> void:
    SaProblems.pending_refusals = PackedStringArray()
    _registries = Fixtures.make_registries()
    var suite := _registries.context.for_module(&"suite")
    suite.register_simulation_rule(&"shift_right", "Shift Right", "sara/simulation_test_rules", "shift_right", 1)


func after_each() -> void:
    for easel in _easels:
        easel.free()
    _easels.clear()


func _easel() -> SaEasel:
    var easel := Bench.easel(SIZE)
    easel.compositor.filter_chain.registry.register(SaBrightnessContrastFilter.new(), &"sara-base-modules")
    _easels.append(easel)
    return easel


## The painting of the header, answering the group.
func _painting(easel: SaEasel) -> SaLayer:
    var doc := easel.document
    var ops := SaLayerOps.new(doc)
    (doc.get_node("Background") as SaLayer).visible = false
    var ground := doc.get_node("Layer 1") as SaLayer
    ground.name = "Ground"
    ground.get_or_create_chunk(LEFT).clear(GROUND)
    doc.set_active_layer(ground)
    var light := ops.add()
    light.name = "Light"
    for grid_pos: Vector2i in [LEFT, RIGHT]:
        light.get_or_create_chunk(grid_pos).clear(LIGHT)
    var adjust := ops.add(SaBackdropLayer.TYPE_ID, _registries.layer_types)
    adjust.name = "Adjust"
    var key := SaFilterRegistry.key_for(&"sara-base-modules", SaBrightnessContrastFilter.new())
    assert_not_null(SaFilterOps.new(doc).attach(adjust, key, RECORD), "The brightness and contrast attaches")
    var glow := ops.add(SaEffectLayer.TYPE_ID, _registries.layer_types)
    glow.name = "Glow"
    glow.opacity = 0.25
    assert_not_null(SaFilterOps.new(doc).attach(glow, Bench.INVERT), "The invert attaches to the effect layer")
    assert_true(SaEffectLayer.read(doc, glow, light), "The effect layer reads the light")
    var sim := ops.add()
    sim.name = "Sim"
    sim.get_or_create_chunk(RIGHT).clear(Color(0.0, 0.0, 1.0, 0.25))
    var found := _registries.simulation_rules.find(&"shift_right")
    var record := SaSimulation.put_on(sim, found, {})
    assert_not_null(record, "The simulation goes on")
    record.steps = 3
    record.speed = 12.0
    record.domain = Rect2i(0, 0, 400, 200)
    var group := ops.group_layers([light, adjust, glow, sim])
    group.name = "Dawn"
    group.folded = true
    return group


func _members(group: SaLayer) -> Dictionary[String, SaLayer]:
    var found: Dictionary[String, SaLayer] = {}
    var doc := group.get_parent() as SaDocument
    for child in doc.get_children():
        var layer := child as SaLayer
        if layer != null and SaLayerStack.is_inside(layer, group):
            found[str(layer.name).trim_suffix(" Copy")] = layer
    return found


func _output(easel: SaEasel) -> PackedByteArray:
    easel.document.invalidate_chunks([LEFT, RIGHT])
    Bench.composite(easel)
    return GlobalShaderCompiler.get_rd().texture_get_data(easel.output.rid, 0)


## The composite with *shown* visible and *hidden* hidden.
func _alone(easel: SaEasel, shown: SaLayer, hidden: SaLayer) -> PackedByteArray:
    shown.visible = true
    hidden.visible = false
    return _output(easel)


func _alike(easel: SaEasel, got: PackedByteArray, want: PackedByteArray, what: String) -> void:
    var worst := 0.0
    var worst_at := Vector2i.ZERO
    var format := easel.output.format
    for y in range(0, SIZE.y, 2):
        for x in range(0, SIZE.x, 2):
            var index := y * SIZE.x + x
            var a := SaFieldSpec.decode_texel(got, format, index)
            var b := SaFieldSpec.decode_texel(want, format, index)
            var off := maxf(maxf(absf(a.r - b.r), absf(a.g - b.g)), maxf(absf(a.b - b.b), absf(a.a - b.a)))
            if off > worst:
                worst = off
                worst_at = Vector2i(x, y)
    assert_true(worst <= TOLERANCE, "%s, worst %s at %s" % [what, worst, worst_at])


func _duplicate(easel: SaEasel, group: SaLayer) -> SaLayer:
    var copy := SaLayerOps.new(easel.document).duplicate(group)
    assert_not_null(copy, "The group duplicates")
    return copy


func test_every_member_s_copy_carries_the_fields_its_kind_needs() -> void:
    var easel := _easel()
    var group := _painting(easel)
    var copy := _duplicate(easel, group)
    assert_true(copy.is_group and copy.folded, "The group's copy is a group, folded as the original is")
    var originals := _members(group)
    var copies := _members(copy)
    assert_eq(copies.size(), originals.size(), "with a copy of every member")
    for name: String in originals:
        var original := originals[name]
        var made: SaLayer = copies.get(name, null)
        assert_not_null(made, "%s has a copy" % name)
        if made == null:
            continue
        assert_true(made != original, "%s's copy is a layer of its own" % name)
        for field in COPIED_FIELDS:
            assert_eq(made.get(field), original.get(field), "%s's copy carries its %s" % [name, field])
    assert_true(copies["Adjust"].is_adjustment(), "The adjustment's copy is an adjustment layer")
    assert_true(copies["Glow"].is_effect(), "The effect's copy is an effect layer")
    assert_eq(copies["Glow"].source, copies["Light"], "reading the light's copy, the input inside its own group")
    assert_eq(originals["Glow"].source, originals["Light"], "while the original reads the original light")
    assert_null(originals["Light"].source, "A layer that reads nothing has a copy that reads nothing")
    assert_null(copies["Light"].source, "")
    var record := SaSimulation.record_of(originals["Sim"])
    var held := SaSimulation.record_of(copies["Sim"])
    assert_not_null(held, "The simulated layer's copy carries a simulation")
    if held != null:
        assert_true(held != record, "of its own")
        assert_eq(held.rule, record.rule, "with the same rule")
        assert_eq(held.module, record.module, "of the same module")
        assert_eq(held.params, record.params, "the same values")
        assert_eq(held.steps, record.steps, "the same count")
        assert_eq(held.speed, record.speed, "the same speed")
        assert_eq(held.domain, record.domain, "the same domain")
        assert_eq(held.seed_chunks.keys(), record.seed_chunks.keys(), "and a seed at the same chunks")
        for grid_pos: Vector2i in record.seed_chunks:
            assert_true(held.seed_chunks[grid_pos].rid != record.seed_chunks[grid_pos].rid, "in textures of its own")
            assert_eq(
                Bench.texel(held.seed_chunks[grid_pos], Vector2i(5, 5)),
                Bench.texel(record.seed_chunks[grid_pos], Vector2i(5, 5)),
                "holding what the source's seed holds"
            )
    assert_true(easel.document.undo(), "The duplicate is one step")
    assert_null(copy.get_parent(), "whose undo takes the group's copy out")
    for name: String in copies:
        assert_null(copies[name].get_parent(), "and %s's copy with it" % name)
    assert_eq(_members(group).size(), originals.size(), "leaving the original whole")


func test_the_copy_composites_as_the_original_does_before_any_save() -> void:
    var easel := _easel()
    var group := _painting(easel)
    var copy := _duplicate(easel, group)
    var original_alone := _alone(easel, group, copy)
    var copy_alone := _alone(easel, copy, group)
    group.visible = true
    copy.visible = false
    var bare := _alone(easel, group, group)
    assert_true(bare != original_alone, "The group changes the picture, so the comparison reads something")
    _alike(easel, copy_alone, original_alone, "The copy composites as the original, before any save")


func test_a_save_and_a_load_leave_the_copy_s_composite_as_it_was() -> void:
    var easel := _easel()
    var group := _painting(easel)
    var copy := _duplicate(easel, group)
    var before := _alone(easel, copy, group)
    var path := ProjectSettings.globalize_path(SaDataRoot.path("duplicated_group.sad"))
    assert_eq(SaExport.save_sad(easel.document, path), OK, "It saves")
    var loaded := _easel()
    assert_eq(SaExport.load_sad(loaded.document, path, loaded.compositor), OK, "It opens")
    DirAccess.remove_absolute(path)
    var layers: Array[SaLayer] = []
    for child in loaded.document.get_children():
        if child is SaLayer:
            layers.append(child)
    _registries.layer_types.rebind(layers)
    var reopened := loaded.document.get_node(str(copy.name)) as SaLayer
    var reopened_original := loaded.document.get_node(str(group.name)) as SaLayer
    assert_not_null(reopened, "The copy is in the file")
    if reopened == null or reopened_original == null:
        return
    var after := _alone(loaded, reopened, reopened_original)
    _alike(loaded, after, before, "The load leaves the copy's composite as it was")
