## The Levels black and white inputs keep a gap whatever sets
## them, so a typed 80 no longer sends the picture to three times white.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The Photoshop hour dragged White down, typed 80 into the Black field, which
## holds 1 at most, and the kernel read a Black above the White, a span turned
## over, and red 0.27 came out at 3.09. Each case here sets the two inputs one
## way a painter, a scenario or a file can, the panel's field, `set_values`, the
## door's adjust step and a saved document, and reads the numbers held by
## `SaLevelsGap` and a ramp of five greys at what the formula gives for them.
## The running app's field and shot are the scenario's, under the unit's name.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

## Real dispatches into real chunks.
const REQUIRES_GPU := true

const MODULE := &"sara-base-modules"
const KEY := &"sara-base-modules.levels"

## The ramp, one flat grey a chunk, from black to white.
const RAMP: Array[float] = [0.0, 0.25, 0.5, 0.75, 1.0]

## Where on its chunk each grey is read, inside it and off its edge.
const READ_AT := Vector2i(4, 4)

var _registries: SaRegistries = null
var _paths: Array[String] = []


func before_each() -> void:
    _registries = Fixtures.make_registries()
    _registries.filters.register(SaLevelsFilter.new(), MODULE)
    _paths = []


func after_each() -> void:
    for path in _paths:
        DirAccess.remove_absolute(path)
    _registries = null


## An easel whose first layer holds the ramp, made active, the background off.
func _ramp_easel() -> SaEasel:
    var easel := SaEasel.create_default(Vector2i(SaChunk.SIZE * RAMP.size(), SaChunk.SIZE))
    easel.compositor.set_registry(_registries.blend_modes)
    easel.compositor.filter_chain.registry = _registries.filters
    (easel.document.get_node("Background") as SaLayer).visible = false
    var layer := easel.document.get_node("Layer 1") as SaLayer
    for index in RAMP.size():
        var v := RAMP[index]
        layer.get_or_create_chunk(Vector2i(index, 0)).clear(Color(v, v, v, 1.0))
    easel.document.set_active_layer(layer)
    return easel


## The ramp's greys as the layer holds them now, red alone.
func _ramp_reds(layer: SaLayer) -> Array[float]:
    var out: Array[float] = []
    for index in RAMP.size():
        var texture := layer.get_field(Vector2i(index, 0))
        @warning_ignore("static_called_on_instance")
        out.append(SaExport.get_texture_image_float(texture).get_pixel(READ_AT.x, READ_AT.y).r)
    return out


## What the Levels formula gives *x* for a black of *black* and a white of
## *white*, gamma one and the full output range, unclamped.
static func _formula(x: float, black: float, white: float) -> float:
    return (x - black) / (white - black)


## Every grey of the ramp as the layer holds it, read against the formula for
## *black* and *white* over a White of 1, so none of it past white.
func _assert_ramp_reads(easel: SaEasel, black: float, white: float, how: String) -> void:
    var reds := _ramp_reds(easel.document.get_node("Layer 1") as SaLayer)
    for index in RAMP.size():
        var want := _formula(RAMP[index], black, white)
        var near := absf(want) * 2e-3 + 2e-3
        assert_almost_eq(reds[index], want, near, "%s: grey %.2f reads %.3f" % [how, RAMP[index], want])
        assert_true(reds[index] <= 1.0 + 1e-3, "%s: grey %.2f is not past white: %.3f" % [how, RAMP[index], reds[index]])


func _field(panel: SaLevelsPanel, key: String) -> SpinBox:
    return panel.find_child(key.capitalize().replace(" ", "") + "Field", true, false) as SpinBox


## The rule itself, the numbers each way of setting them is held to.
func test_the_rule_holds_black_under_white_and_white_over_black() -> void:
    var gap := SaLevelsGap.GAP
    var black_80 := SaLevelsGap.held({"in_black": 80.0, "in_white": 1.0})
    assert_almost_eq(float(black_80["in_black"]), 1.0 - gap, 1e-6, "Black 80 over White 1 is held at White less the gap")
    assert_almost_eq(float(black_80["in_white"]), 1.0, 1e-6, "and White stays")
    var white_0 := SaLevelsGap.held({"in_black": 0.0, "in_white": 0.0}, "in_white")
    assert_almost_eq(float(white_0["in_white"]), gap, 1e-6, "White 0 over Black 0 is held at the gap")
    var neither := SaLevelsGap.held({"in_black": 0.0, "in_white": 0.0})
    assert_almost_eq(float(neither["in_white"]), gap, 1e-6, "and so it is with no field named")
    var defaults := SaLevelsGap.held({"in_black": 0.0, "in_white": 1.0, "gamma": 1.0})
    assert_eq(defaults, {"in_black": 0.0, "in_white": 1.0, "gamma": 1.0}, "The defaults are left as they are")
    var params := SaPointAdjust.params_for(SaPointAdjust.LEVELS, {"in_black": 80.0, "in_white": 1.0})
    assert_almost_eq(float(params[0]), 1.0 - gap, 1e-6, "The kernel's parameters carry the held Black")


## Typed into the panel's field: 80 is held by the field at 1, and then at
## White less the gap. The painter's own case, White dragged to 0.75 first,
## is held at 0.745, not turned over.
func test_a_black_typed_into_the_field_is_held_under_white() -> void:
    # In the tree, because a field out of it announces no change.
    var panel := SaLevelsPanel.new()
    EventBus.add_child(panel)
    var black := _field(panel, "in_black")
    assert_true(black != null, "The panel has a Black field")
    black.value = 80.0
    assert_almost_eq(float(panel.values()["in_black"]), 1.0 - SaLevelsGap.GAP, 1e-6, "A typed 80 reads White less the gap")
    var easel := _ramp_easel()
    assert_true(
        SaPointAdjust.new().apply(easel.document, easel.document.active_layer, SaPointAdjust.LEVELS, panel.values(), "Levels"),
        "The pass runs"
    )
    _assert_ramp_reads(easel, 1.0 - SaLevelsGap.GAP, 1.0, "Typed 80 over White 1")
    easel.free()

    panel.set_values({"in_black": 0.0, "in_white": 0.75})
    black.value = 80.0
    assert_almost_eq(float(panel.values()["in_black"]), 0.75 - SaLevelsGap.GAP, 1e-6, "Over a dragged White it is held under it")
    easel = _ramp_easel()
    SaPointAdjust.new().apply(easel.document, easel.document.active_layer, SaPointAdjust.LEVELS, panel.values(), "Levels")
    _assert_ramp_follows_formula(easel, 0.75 - SaLevelsGap.GAP, 0.75, "Typed 80 over White 0.75")
    easel.free()

    panel.set_values({"in_black": 0.0, "in_white": 1.0})
    _field(panel, "in_white").value = 0.0
    assert_almost_eq(float(panel.values()["in_white"]), SaLevelsGap.GAP, 1e-6, "A White typed 0 over Black 0 reads the gap")
    assert_almost_eq(float(_field(panel, "in_white").value), SaLevelsGap.GAP, 1e-6, "and its field shows it")
    panel.free()


## `set_values`, the way a scenario drives the panel: Black 80 and White 1
## read Black held, and White 0 with Black 0 reads White at the gap.
func test_set_values_holds_the_gap() -> void:
    var panel := SaLevelsPanel.new()
    panel.set_values({"in_black": 80.0, "in_white": 1.0})
    assert_almost_eq(float(panel.values()["in_black"]), 1.0 - SaLevelsGap.GAP, 1e-6, "set_values holds Black 80")
    assert_almost_eq(float(_field(panel, "in_black").value), 1.0 - SaLevelsGap.GAP, 1e-6, "and the field shows it")
    panel.set_values({"in_black": 0.0})
    panel.set_values({"in_white": 0.0})
    assert_almost_eq(float(panel.values()["in_white"]), SaLevelsGap.GAP, 1e-6, "set_values holds White 0 at the gap")
    assert_almost_eq(float(panel.values()["in_black"]), 0.0, 1e-6, "and Black stays at 0")
    panel.set_parameters({"in_black": 80.0, "in_white": 1.0})
    assert_almost_eq(float(panel.values()["in_black"]), 1.0 - SaLevelsGap.GAP, 1e-6, "A record's numbers are drawn held")
    panel.free()


## The door's adjust step, `capture_apply`, takes its numbers as given and the
## kernel holds them: Black 80 over White 1, and White 0 over Black 0.
func test_the_door_s_adjust_step_is_held_by_the_kernel() -> void:
    var easel := _ramp_easel()
    assert_true(SaLevelsFilter.new().capture_apply(easel.document, {"in_black": 80.0, "in_white": 1.0}), "The step applies")
    _assert_ramp_reads(easel, 1.0 - SaLevelsGap.GAP, 1.0, "The door's Black 80")
    easel.free()

    easel = _ramp_easel()
    assert_true(SaLevelsFilter.new().capture_apply(easel.document, {"in_black": 0.0, "in_white": 0.0}), "The step applies")
    _assert_ramp_follows_formula(easel, 0.0, SaLevelsGap.GAP, "The door's White 0")
    easel.free()


## The ramp read against the formula alone, for a White under 1: a grey above
## White lands past white, as hard rule 5 keeps, which the inverted span of the
## Photoshop hour did to the greys below it instead.
func _assert_ramp_follows_formula(easel: SaEasel, black: float, white: float, how: String) -> void:
    var reds := _ramp_reds(easel.document.get_node("Layer 1") as SaLayer)
    for index in RAMP.size():
        var want := _formula(RAMP[index], black, white)
        assert_almost_eq(reds[index], want, absf(want) * 2e-3 + 2e-3, "%s: grey %.2f reads %.3f" % [how, RAMP[index], want])


## The defaults leave every grey as it was.
func test_the_defaults_leave_the_ramp_unchanged() -> void:
    var easel := _ramp_easel()
    var panel := SaLevelsPanel.new()
    SaPointAdjust.new().apply(easel.document, easel.document.active_layer, SaPointAdjust.LEVELS, panel.values(), "Levels")
    var reds := _ramp_reds(easel.document.get_node("Layer 1") as SaLayer)
    for index in RAMP.size():
        assert_almost_eq(reds[index], RAMP[index], 1e-3, "Grey %.2f is unchanged" % RAMP[index])
    panel.free()
    easel.free()


## Equalize's map runs before the handles: a map that sends every level to
## one sends the whole ramp to one grey, and the held handles then move that
## one grey, so every texel reads the same and none is past white.
func test_equalize_runs_before_the_held_handles() -> void:
    var easel := _ramp_easel()
    var flat: Array = []
    for i in SaPointAdjust.EQUALIZE_SAMPLES:
        flat.append(0.5)
    var values := {"in_black": 80.0, "in_white": 1.0, "equalize": flat, "equalize_channel": SaLevelsPanel.MAP_CHANNEL}
    assert_true(
        SaPointAdjust.new().apply(easel.document, easel.document.active_layer, SaPointAdjust.LEVELS, values, "Levels"),
        "The pass runs"
    )
    var reds := _ramp_reds(easel.document.get_node("Layer 1") as SaLayer)
    for index in RAMP.size():
        assert_almost_eq(reds[index], reds[0], 1e-2, "Grey %.2f lands where black does once equalized" % RAMP[index])
        assert_true(reds[index] < 0.0, "and below black, under a Black held at 0.995: %.3f" % reds[index])
    easel.free()


## A document saved with Black 80 on an adjustment layer opens and composites
## the same as one whose record says the held number.
func test_a_document_with_black_80_opens_and_reads_held() -> void:
    var easel := _ramp_easel()
    var layer := SaFilterConversion.new(easel.document).add_holding(
        KEY, {"in_black": 80.0, "in_white": 1.0}, _registries.layer_types, "Levels"
    )
    assert_true(layer != null and layer.is_adjustment(), "A Levels adjustment layer is added")
    var path := ProjectSettings.globalize_path(SaDataRoot.path("black_80.sad"))
    _paths.append(path)
    assert_eq(SaExport.save_sad(easel.document, path), OK, "and saves")
    easel.free()

    var opened := _opened(path)
    var held := _ramp_easel()
    SaFilterConversion.new(held.document).add_holding(
        KEY, {"in_black": 1.0 - SaLevelsGap.GAP, "in_white": 1.0}, _registries.layer_types, "Levels"
    )
    var read := _composite(opened)
    var want := _composite(held)
    for index in RAMP.size():
        assert_almost_eq(read[index], want[index], absf(want[index]) * 2e-3 + 2e-3, "Grey %.2f reads as held" % RAMP[index])
        assert_true(read[index] <= 1.0 + 1e-3, "and is not past white: %.3f" % read[index])
    opened.free()
    held.free()


func _opened(path: String) -> SaEasel:
    var easel := SaEasel.create_default(Vector2i(SaChunk.SIZE * RAMP.size(), SaChunk.SIZE))
    easel.compositor.set_registry(_registries.blend_modes)
    easel.compositor.filter_chain.registry = _registries.filters
    assert_eq(SaExport.load_sad(easel.document, path, easel.compositor), OK, "%s opens" % path.get_file())
    var layers: Array[SaLayer] = []
    for child in easel.document.get_children():
        if child is SaLayer:
            layers.append(child)
    _registries.layer_types.rebind(layers)
    return easel


## The composite's red at each grey of the ramp.
func _composite(easel: SaEasel) -> Array[float]:
    var cells: Array[Vector2i] = []
    for index in RAMP.size():
        cells.append(Vector2i(index, 0))
    easel.document.invalidate_chunks(cells)
    easel.document.update_caches()
    easel.request_full_composite()
    easel.process_pending_composite()
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(easel.output.rid, 0)
    var out: Array[float] = []
    for index in RAMP.size():
        var at := Vector2i(index * SaChunk.SIZE + READ_AT.x, READ_AT.y)
        out.append(SaFieldSpec.decode_texel(bytes, easel.output.format, at.y * easel.output.size.x + at.x).r)
    return out
