## Ctrl+I is Invert, the base module's command.
##
## While a mask is the paint target it inverts that mask and leaves the paint,
## otherwise it inverts the picked layers' colours, and on an adjustment layer
## it inverts the layer's mask or refuses when there is none. Each case runs
## the registered command, the one Ctrl+I reaches, and undoes once.
extends "res://tests/test_framework.gd"

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")
const Fixtures = preload("res://tests/fixtures.gd")
const InvertCommand = preload("res://modules/sara-base-modules/base/invert_command.gd")
const InvertFilter = preload("res://modules/sara-base-modules/base/usual/invert_filter.gd")

## The proof is texels a kernel wrote, which needs a RenderingDevice.
const REQUIRES_GPU := true

const MODULE := &"sara-base-modules"
const SIZE := Vector2i(256, 256)
const AT := Vector2i(40, 40)
const PAINT := Color(0.2, 0.3, 0.4, 1.0)
const INVERTED := Color(0.8, 0.7, 0.6, 1.0)
## The rectangle a case selects, and a pixel outside it.
const BOX := Rect2i(20, 20, 60, 60)
const BESIDE := Vector2i(150, 150)

var _easel: SaEasel = null
var _doc: SaDocument = null
var _layer: SaLayer = null
var _registries: SaRegistries = null
var _refusals: Array[String] = []


func before_each() -> void:
    _easel = Bench.easel(SIZE)
    _doc = _easel.document
    _layer = _doc.get_node("Layer 1") as SaLayer
    _layer.get_or_create_chunk(Vector2i.ZERO).clear(PAINT)
    _registries = SaRegistries.new()
    _registries.build_context(func() -> SaEasel: return _easel, func() -> Array: return [])
    _registries.register_builtins()
    var ctx := _registries.context.for_module(MODULE)
    ctx.register_filter_section(&"color", "Colour", 200)
    ctx.register_filter(InvertFilter.new())
    # The compositor's chain resolves a pass by the key in its own registry,
    # which in the app is the one the context registers into.
    _easel.compositor.filter_chain.registry.register(InvertFilter.new(), MODULE)
    InvertCommand.register(ctx)
    _doc.history.reset()
    _doc.undo_redo.clear_history()
    _refusals.clear()
    EventBus.paint_refused.connect(_hear)


func after_each() -> void:
    EventBus.paint_refused.disconnect(_hear)
    _registries = null
    _easel.free()
    _easel = null
    _doc = null
    _layer = null


func _hear(line: String) -> void:
    _refusals.append(line)


func _paint(at: Vector2i = AT) -> Color:
    return Bench.texel(_layer.get_field(Vector2i.ZERO), at)


## The coverage *owner*'s mask holds at *at*, its rest where it holds nothing.
func _coverage(owner: SaLayer, at: Vector2i = AT) -> float:
    var texture := owner.mask.texture_for(Vector2i.ZERO)
    return owner.mask.rest if texture == null else Bench.texel(texture, at).r


func _near(a: Color, b: Color) -> bool:
    return absf(a.r - b.r) < 0.002 and absf(a.g - b.g) < 0.002 and absf(a.b - b.b) < 0.002 and absf(a.a - b.a) < 0.002


func _steps() -> int:
    return _doc.undo_redo.get_history_count()


func _ctrl_i() -> bool:
    return _registries.commands.execute(InvertCommand.COMMAND)


func test_ctrl_i_is_invert_and_the_mask_and_filter_rows_show_it() -> void:
    assert_eq(_registries.commands.chord_text(InvertCommand.COMMAND), "Ctrl+I", "Invert answers Ctrl+I")
    assert_eq(_registries.commands.get_descriptor(InvertCommand.COMMAND).owner_module, MODULE, "registered by the module")
    assert_eq(_registries.commands.shown_chord(SaMaskOps.INVERT, 1), "Ctrl+I", "Invert Mask's row shows it")
    var filter_command := SaFilterRegistry.command_for(InvertCommand.filter_key(), InvertFilter.new())
    assert_eq(_registries.commands.shown_chord(filter_command, 1), "Ctrl+I", "and so does Filter > Invert's")
    assert_eq(_registries.commands.chord_text(SaMaskOps.INVERT), "", "while Invert Mask holds no chord of its own")
    for command_id: StringName in _registries.commands.list_ids():
        if command_id != InvertCommand.COMMAND:
            assert_false(_registries.commands.chord_text(command_id).split(", ").has("Ctrl+I"), "%s holds no Ctrl+I" % command_id)


func test_with_the_mask_the_target_it_flips_the_mask_and_leaves_the_paint() -> void:
    var ops := SaMaskOps.new(_doc)
    ops.add(_layer)
    _doc.mask_target = _layer.mask
    _doc.history.reset()
    _doc.undo_redo.clear_history()
    var steps := _steps()

    assert_true(_ctrl_i(), "Ctrl+I runs with the mask the target")
    assert_almost_eq(_coverage(_layer), 0.0, 0.001, "the mask that showed everything hides it")
    assert_almost_eq(_layer.mask.rest, 0.0, 0.001, "and its rest is flipped too")
    assert_true(_near(_paint(), PAINT), "the layer's paint is what it was")
    assert_eq(_steps(), steps + 1, "in one step")
    assert_eq(_doc.undo_redo.get_current_action_name(), "Invert Mask", "named as the menu row's")

    assert_true(_doc.undo(), "one undo")
    assert_almost_eq(_coverage(_layer), 1.0, 0.001, "gives the mask back")


func test_with_the_layer_the_target_it_inverts_the_colours() -> void:
    var steps := _steps()
    assert_true(_ctrl_i(), "Ctrl+I runs on the layer")
    assert_true(_near(_paint(), INVERTED), "the paint is inverted, %s" % _paint())
    assert_eq(_steps(), steps + 1, "in one step")
    assert_eq(_doc.undo_redo.get_current_action_name(), "Invert", "named as Filter > Invert's")
    assert_true(_doc.undo(), "one undo")
    assert_true(_near(_paint(), PAINT), "puts the paint back")


func test_a_layer_with_a_mask_it_is_not_painting_has_its_colours_inverted() -> void:
    SaMaskOps.new(_doc).add(_layer)
    _doc.mask_target = null
    assert_true(_ctrl_i(), "Ctrl+I runs on the layer")
    assert_true(_near(_paint(), INVERTED), "the paint is inverted")
    assert_almost_eq(_coverage(_layer), 1.0, 0.001, "and the mask is left as it was")


func test_inside_a_selection_only_the_selected_paint_is_inverted() -> void:
    _doc.selection.select_rect(BOX)
    assert_true(_ctrl_i(), "Ctrl+I runs under a selection")
    assert_true(_near(_paint(), INVERTED), "inside the selection the paint is inverted")
    assert_true(_near(_paint(BESIDE), PAINT), "and outside it the paint is what it was")


func test_every_picked_layer_is_inverted_in_one_step() -> void:
    var other := SaLayerOps.new(_doc).add()
    other.get_or_create_chunk(Vector2i.ZERO).clear(PAINT)
    _doc.picked.pick([_layer, other] as Array[SaLayer])
    _doc.set_active_layer(other)
    _doc.history.reset()
    _doc.undo_redo.clear_history()
    var steps := _steps()
    assert_true(_ctrl_i(), "Ctrl+I runs on the picked pair")
    assert_true(_near(_paint(), INVERTED), "the first is inverted")
    assert_true(_near(Bench.texel(other.get_field(Vector2i.ZERO), AT), INVERTED), "and the second")
    assert_eq(_steps(), steps + 1, "in one step")
    assert_true(_doc.undo(), "one undo")
    assert_true(_near(_paint(), PAINT), "puts both back")


func test_an_adjustment_layer_with_a_mask_has_its_mask_flipped() -> void:
    var adjustment := _adjustment()
    if not SaMaskOps.can(SaMaskOps.INVERT, adjustment):
        SaMaskOps.new(_doc).add(adjustment)
    _doc.mask_target = null
    _doc.set_active_layer(adjustment)
    var before := _coverage(adjustment)
    assert_true(_ctrl_i(), "Ctrl+I runs on the adjustment")
    assert_almost_eq(_coverage(adjustment), 1.0 - before, 0.001, "its mask is flipped")
    assert_true(_near(_paint(), PAINT), "and the paint below is untouched")
    assert_eq(_doc.undo_redo.get_current_action_name(), "Invert Mask", "named as the menu row's")


func test_an_adjustment_layer_with_no_mask_refuses_with_a_reason() -> void:
    var adjustment := _adjustment()
    if adjustment.mask != null:
        SaMaskOps.new(_doc).remove(adjustment)
    _doc.mask_target = null
    _doc.set_active_layer(adjustment)
    var steps := _steps()
    assert_false(_ctrl_i(), "Ctrl+I refuses")
    assert_eq(_steps(), steps, "and records nothing")
    assert_eq(_refusals.size(), 1, "with one line in the corner")
    assert_true(_refusals.size() == 1 and _refusals[0].contains(adjustment.name), "naming the layer")
    assert_true(_near(_paint(), PAINT), "and the paint below is untouched")


## An adjustment layer above the paint, holding the Invert filter.
func _adjustment() -> SaLayer:
    var made := SaFilterConversion.new(_doc).add_holding(InvertCommand.filter_key(), {}, _registries.layer_types, "Invert")
    assert_true(made != null and made.is_adjustment(), "an adjustment layer is made")
    _doc.history.reset()
    _doc.undo_redo.clear_history()
    return made
