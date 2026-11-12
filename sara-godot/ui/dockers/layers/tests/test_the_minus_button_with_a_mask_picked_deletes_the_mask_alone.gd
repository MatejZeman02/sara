## The minus under the Layers docker's list, pressed with a mask picked, takes
## the mask off and leaves its layer, as one undo step, and says so on its
## hover. With the layer's picture picked it deletes the layer as it always did.
##
## Selecting a mask pinned to a layer and hitting the minus button to delete it
## deletes only the mask.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")

const OWNER := &"sara-base-modules"
const PAINT := Color(0.25, 0.5, 0.75, 1.0)
const CURVES_VALUES := {"curves": {"master": [[0.0, 0.0], [0.375, 0.75], [1.0, 1.0]]}}

var _easel: SaEasel = null
var _doc: SaDocument = null
var _painted: SaLayer = null
var _registries: SaRegistries = null
var _registry: SaFilterRegistry = null
var _canvas: SaCanvas = null
var _docker: LayersDocker = null


func before_each() -> void:
    _easel = Bench.easel(Vector2i(256, 256))
    _doc = _easel.document
    _registries = Fixtures.make_registries()
    _registry = _easel.compositor.filter_chain.registry
    _registry.register(SaCurvesFilter.new(), OWNER)
    _painted = SaLayerOps.new(_doc).add()
    _doc.fill_layer(PAINT, _painted)
    _canvas = SaCanvas.new()
    _canvas.easel = _easel
    _docker = LayersDocker.new()
    _docker.filter_registry = _registry
    _docker.target_canvas = _canvas
    _docker.sync_layer_list()


func after_each() -> void:
    _docker.free()
    _canvas.free()
    _easel.free()
    _docker = null
    _canvas = null
    _easel = null
    _doc = null
    _painted = null
    _registries = null
    _registry = null


func _layers() -> Array[SaLayer]:
    var found: Array[SaLayer] = []
    for child in _doc.get_children():
        if child is SaLayer:
            found.append(child as SaLayer)
    return found


## A mask on *layer*, and a press on the mask's picture of its row, which is
## what makes the mask the document's `mask_target`.
func _pick_mask_of(layer: SaLayer) -> void:
    # A new filter layer carries one already.
    assert_true(layer.mask != null or SaMaskOps.new(_doc).add(layer), "%s takes a mask" % layer.name)
    _doc.set_active_layer(layer)
    _docker.sync_layer_list()
    SaLayerRowView.aim_brush(_doc, layer, &"mask")
    assert_eq(_doc.mask_target, layer.mask, "and its mask is picked")


## The minus with *layer*'s mask picked: the layer stays without its mask, the
## hover said mask before the press, and one undo puts the mask back.
func _assert_mask_alone(layer: SaLayer) -> void:
    _pick_mask_of(layer)
    assert_eq(_docker.actions.del_btn.tooltip_text, SaLayerMinus.DELETE_MASK_HINT, "The minus's hover says it deletes the mask")
    var layers := _layers()
    var steps := _doc.history.step_count()
    _docker.actions.del_btn.pressed.emit()
    assert_eq(_layers(), layers, "The minus keeps every layer, %s included" % layer.name)
    assert_null(layer.mask, "and takes %s's mask off" % layer.name)
    assert_null(_doc.mask_target, "so nothing is picked to paint as a mask")
    assert_eq(_doc.history.step_count(), steps + 1, "as one step")
    assert_eq(_doc.undo_redo.get_current_action_name(), "Delete Mask", "named Delete Mask")
    assert_eq(_docker.actions.del_btn.tooltip_text, SaLayerMinus.DELETE_LAYER_HINT, "and the hover goes back to the layer")
    assert_true(_doc.undo(), "One undo runs")
    # A painted layer's mask is rebuilt from the step's shape, so the undo puts
    # a mask back and not always the same object.
    assert_not_null(layer.mask, "and puts the mask back on %s" % layer.name)
    assert_eq(_layers(), layers, "with the layers as they were")


func test_a_painted_layers_mask_goes_alone() -> void:
    _assert_mask_alone(_painted)


func test_a_curves_layers_mask_goes_alone() -> void:
    var key := SaFilterRegistry.key_for(OWNER, SaCurvesFilter.new())
    var curves := SaFilterConversion.new(_doc).add_holding(key, CURVES_VALUES, _registries.layer_types, "Curves")
    assert_true(curves != null and curves.is_adjustment(), "A Curves adjustment layer is added")
    _assert_mask_alone(curves)


func test_with_the_layers_picture_picked_the_minus_deletes_the_layer() -> void:
    _pick_mask_of(_painted)
    SaLayerRowView.aim_brush(_doc, _painted, &"layer")
    assert_null(_doc.mask_target, "A press on the layer's picture gives the brush back to the paint")
    assert_eq(_docker.actions.del_btn.tooltip_text, SaLayerMinus.DELETE_LAYER_HINT, "The hover says it deletes the layer")
    var count := _layers().size()
    _docker.actions.del_btn.pressed.emit()
    assert_eq(_layers().size(), count - 1, "and the minus deletes it, as it always did")
    assert_false(_layers().has(_painted), "the painted layer being the one gone")
