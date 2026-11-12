## A fill on a layer that refuses paint changes nothing and says why.
##
## Alt+Backspace on a paint layer under a live transform laid the colour into
## the layer's own pixels, hidden under the preview, and on a scene layer
## allocated a grid of chunks the scene paints over. Each case runs the chord
## the way its key does, through the command registry, and reads the answer,
## the line said in the corner, the layer's chunks and pixels and the history.
## A plain paint layer and the generated background still take the fill, as
## one undoable step each.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")
const SceneFixture = preload("res://tests/fixtures/modules/scene-fixture/module.gd")

const SIZE := Vector2i(256, 256)
const PAINT := Color(0.25, 0.5, 0.75, 1.0)
const FOREGROUND := Color(0.9, 0.1, 0.2, 1.0)
const AT := Vector2i(40, 40)

var _surface: SaSurface = null
var _doc: SaDocument = null
var _registries: SaRegistries = null
var _said: Array[String] = []
var _foreground := Color.BLACK
var _moved: SaLayer = null
var _machine: ToolMachine = null


## A tool that holds a change it has not written, as the transform does with
## its box dragged and not applied.
class HeldTool:
    extends ToolState

    func holds_session() -> bool:
        return true


func before_each() -> void:
    _surface = Fixtures.make_surface(SIZE)
    _surface.easel.compositor.set_registry(Fixtures.make_registries().blend_modes)
    _doc = _surface.easel.document
    _registries = Fixtures.make_registries(_surface)
    var module := SceneFixture.new()
    module.register(_registries.context.for_module(module.get_id()))
    _foreground = SaColors.foreground
    SaColors.foreground = FOREGROUND
    _said.clear()
    EventBus.paint_refused.connect(_hear)


func after_each() -> void:
    if EventBus.paint_refused.is_connected(_hear):
        EventBus.paint_refused.disconnect(_hear)
    if _moved != null and _moved.live_transform != null:
        (_moved.live_transform as SaLiveTransform).release()
        _moved.live_transform = null
    SaColors.foreground = _foreground
    _registries = null
    Fixtures.teardown(_surface, _machine)
    _machine = null
    _surface = null
    _doc = null
    _moved = null


func _hear(line: String) -> void:
    _said.append(line)


## A paint layer above the rest, active, holding *paint* when it is given,
## with the history emptied after so a case counts only its own steps.
func _paint_layer(paint: Variant) -> SaLayer:
    var layer := SaLayerOps.new(_doc).add(&"")
    _doc.set_active_layer(layer)
    if paint != null:
        _doc.fill_layer(paint as Color, layer)
    _doc.history.reset()
    _doc.undo_redo.clear_history()
    return layer


func _texel(layer: SaLayer) -> Color:
    return Bench.texel(layer.get_field(Vector2i.ZERO), AT)


func test_a_fill_under_a_live_transform_changes_nothing_and_says_why() -> void:
    _moved = _paint_layer(PAINT)
    var chunks := _moved.chunks.keys()
    var before := _texel(_moved)
    _moved.live_transform = SaLiveTransform.new(
        SaLiveTransform.composed(Vector2(30.0, 10.0), 20.0, Vector2.ONE, Vector2(128.0, 128.0))
    )
    assert_true(_moved.refuses_paint(), "The fixture's box does not take a write of the layer's own pixels")
    assert_false(_registries.commands.execute(&"fill_foreground"), "The chord answers false")
    assert_eq(_said.size(), 1, "and says one line: %s" % [_said])
    if not _said.is_empty():
        assert_true(_said[0].contains("fill did nothing"), "naming the fill: %s" % _said[0])
        assert_true(_said[0].contains("Convert to Ordinary Layer"), "and the way out, as the brush says it")
    assert_eq(_doc.history.step_count(), 0, "No step was recorded")
    assert_eq(_moved.chunks.keys(), chunks, "The layer holds the chunks it held")
    var after := _texel(_moved)
    for channel in 4:
        assert_almost_eq(after[channel], before[channel], 1.0e-6, "and its pixel channel %d is as it was" % channel)


func test_a_clear_under_a_live_transform_changes_nothing_either() -> void:
    _moved = _paint_layer(PAINT)
    var chunks := _moved.chunks.keys()
    _moved.live_transform = SaLiveTransform.new(SaLiveTransform.composed(Vector2(30.0, 10.0), 0.0, Vector2.ONE, Vector2.ZERO))
    assert_false(_registries.commands.execute(&"layer_clear"), "Clear answers false")
    assert_eq(_said.size(), 1, "and says one line: %s" % [_said])
    if not _said.is_empty():
        assert_true(_said[0].contains("clear did nothing"), "naming the clear: %s" % _said[0])
    assert_eq(_doc.history.step_count(), 0, "No step was recorded")
    assert_eq(_moved.chunks.keys(), chunks, "and the paint is kept")


func test_a_fill_on_a_scene_layer_allocates_nothing_and_says_why() -> void:
    var layer := SaLayerOps.new(_doc).add(SceneFixture.TYPE, _registries.layer_types)
    assert_true(layer.is_scene() and _doc.active_layer == layer, "The fixture's scene layer is the active layer")
    _doc.history.reset()
    _doc.undo_redo.clear_history()
    var chunks := layer.chunks.size()
    assert_false(_registries.commands.execute(&"fill_foreground"), "The chord answers false")
    assert_eq(layer.chunks.size(), chunks, "No chunk was allocated on the scene layer")
    assert_eq(_doc.history.step_count(), 0, "No step was recorded")
    assert_eq(_said.size(), 1, "and one line was said: %s" % [_said])
    _doc.fill_layer(FOREGROUND, layer)
    assert_eq(layer.chunks.size(), chunks, "A direct fill of the document allocates none either")
    assert_eq(_doc.history.step_count(), 0, "nor records a step")


func test_a_plain_paint_layer_still_takes_the_fill_as_one_step() -> void:
    var layer := _paint_layer(null)
    assert_true(_registries.commands.execute(&"fill_foreground"), "The chord answers true")
    assert_true(_said.is_empty(), "and refuses nothing: %s" % [_said])
    assert_eq(_doc.history.step_count(), 1, "One step was recorded")
    assert_almost_eq(_texel(layer).a, 1.0, 1.0e-6, "and the layer is covered")
    assert_true(_doc.undo(), "One undo")
    assert_eq(layer.chunks.size(), 0, "takes the fill away again")


func test_the_generated_background_still_takes_the_fill_as_one_step() -> void:
    var choice := {
        SaDocumentBackground.KIND: SaDocumentBackground.COLOUR,
        SaDocumentBackground.COLOR: Color.WHITE,
        SaDocumentBackground.GROUND: &"paper",
    }
    _doc.reset_to_default(SIZE, SaColorSpace.srgb(), SaDocument.DEFAULT_DPI, choice, _registries.layer_types)
    var paper := _doc.get_node("Background") as SaLayer
    assert_true(paper != null and paper.is_generated(), "The ground is a generated layer called Background")
    if paper == null:
        return
    _doc.set_active_layer(paper)
    _doc.history.reset()
    _doc.undo_redo.clear_history()
    var before: Color = paper.generator_params.get(SaGeneratedLayer.PARAM_COLOR, Color.WHITE)
    assert_true(_registries.commands.execute(&"fill_foreground"), "The chord answers true")
    assert_true(_said.is_empty(), "and refuses nothing: %s" % [_said])
    assert_eq(_doc.history.step_count(), 1, "One step was recorded")
    var filled: Color = paper.generator_params.get(SaGeneratedLayer.PARAM_COLOR, Color.WHITE)
    assert_true(not filled.is_equal_approx(before), "and the ground took a new colour")
    assert_true(_doc.undo(), "One undo")
    var undone: Color = paper.generator_params.get(SaGeneratedLayer.PARAM_COLOR, Color.WHITE)
    assert_true(undone.is_equal_approx(before), "gives the ground its colour back")


## The Edit menu's row with the transform's box in the air: the fill would land
## in the layer's pixels under the lift, hidden, so it is refused while any
## tool of the machine holds a session, the active one or not, since Alt of
## Alt+Backspace hands the canvas to the eyedropper while the chord is down.
func test_a_fill_while_a_tool_holds_a_change_changes_nothing_and_says_why() -> void:
    var layer := _paint_layer(PAINT)
    var before := _texel(layer)
    _machine = Fixtures.make_bound_machine(_surface)
    _machine.registered_tools[&"held-probe"] = HeldTool.new()
    assert_false(_registries.commands.execute(&"fill_foreground"), "The chord answers false")
    assert_eq(_said.size(), 1, "and says one line: %s" % [_said])
    if not _said.is_empty():
        assert_true(_said[0].contains("not applied, so the fill did nothing"), "naming the fill: %s" % _said[0])
    assert_eq(_doc.history.step_count(), 0, "No step was recorded")
    assert_almost_eq(_texel(layer).b, before.b, 1.0e-6, "and the paint is as it was")
