## The Filter dialog, its canvas preview and its Apply stay on one layer when
## the painter picks another layer with the dialog open, and a document that
## goes from under the dialog is never written.
##
## The dialog is not exclusive, so the Layers docker takes a click while it
## stands. It follows that click: the context is built again on the layer
## picked, the settings and the canvas switch kept, and the preview runs again,
## so what the canvas shows is what Apply writes. A tab switched or the
## document closed closes it as Cancel does.
##
## The painting is the bench of the Bake, Attach or Layer suite: two chunks
## across, the background hidden, "Layer 1" opaque over the left chunk and
## "Stroke" at half alpha over both, with "Stroke" active.
extends "res://tests/test_framework.gd"

const Teardown := preload("res://tests/fixtures/teardown.gd")
const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")
const Fixtures = preload("res://tests/fixtures.gd")

const REQUIRES_GPU := true

const SIZE := Vector2i(512, 256)
const LEFT := Vector2i(0, 0)
const RIGHT := Vector2i(1, 0)
const UNDER := Color(0.125, 0.625, 0.25, 1.0)
const HALF := Color(0.75, 0.25, 0.125, 0.5)
const AT := Vector2i(10, 10)
const TOLERANCE := 1.0e-4

var _easel: SaEasel = null
var _doc: SaDocument = null
var _canvas: SaCanvas = null
var _window: SaFilterDialogWindow = null
var _host: Node = null
var _registry: SaFilterRegistry = null
var _key: StringName = &""
var _was_embedding: bool = false
var _was_on_canvas: bool = false


func before_each() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    if tree != null:
        _was_embedding = tree.root.gui_embed_subwindows
        tree.root.gui_embed_subwindows = true
    _was_on_canvas = SaSettings.filter_preview_on_canvas
    SaSettings.filter_preview_on_canvas = true
    SaProblems.pending_refusals = PackedStringArray()
    SaProblems.announce = false

    _host = Node.new()
    _host.name = "FilterTargetTestHost"
    EventBus.add_child(_host)

    _easel = _painting()
    _doc = _easel.document
    _registry = _easel.compositor.filter_chain.registry
    _key = SaFilterRegistry.key_for(&"sara-base-modules", SaBrightnessContrastFilter.new())
    _registry.register(SaBrightnessContrastFilter.new(), &"sara-base-modules")

    _canvas = SaCanvas.new()
    _canvas.easel = _easel

    _window = SaFilterDialogWindow.new()
    _window.target_canvas = _canvas
    _window.watch(_registry)
    _host.add_child(_window)


func after_each() -> void:
    SaSettings.filter_way = "bake"
    SaSettings.filter_preview_on_canvas = _was_on_canvas
    Teardown.free_nodes([_window, _canvas, _easel])
    _window = null
    _canvas = null
    _easel = null
    _doc = null
    _registry = null
    if _host != null:
        _host.free()
        _host = null
    var tree := Engine.get_main_loop() as SceneTree
    if tree != null:
        tree.root.gui_embed_subwindows = _was_embedding
    SaProblems.announce = true


func _painting() -> SaEasel:
    var easel := Bench.easel(SIZE)
    var doc := easel.document
    (doc.get_node("Background") as SaLayer).visible = false
    var under := doc.get_node("Layer 1") as SaLayer
    doc.set_active_layer(under)
    under.get_or_create_chunk(LEFT).clear(UNDER)
    var stroke := SaLayerOps.new(doc).add()
    stroke.name = "Stroke"
    for grid_pos: Vector2i in [LEFT, RIGHT]:
        stroke.get_or_create_chunk(grid_pos).clear(HALF)
    doc.history.reset()
    doc.undo_redo.clear_history()
    return easel


func _texel(layer: SaLayer) -> Color:
    return Bench.texel(layer.get_field(LEFT), AT)


func _same(a: Color, b: Color) -> bool:
    return (
        absf(a.r - b.r) < TOLERANCE
        and absf(a.g - b.g) < TOLERANCE
        and absf(a.b - b.b) < TOLERANCE
        and absf(a.a - b.a) < TOLERANCE
    )


func _brightness(value: float) -> void:
    SaFilterDialogWindow.capture(Engine.get_main_loop() as SceneTree, {"widget": "brightness", "value": value})
    _window.dialog.flush_rerun()


func test_a_layer_picked_with_the_dialog_open_is_the_layer_apply_writes() -> void:
    var stroke := _doc.get_node("Stroke") as SaLayer
    var under := _doc.get_node("Layer 1") as SaLayer
    assert_eq(_doc.active_layer, stroke, "The dialog opens on the stroke")
    assert_true(_registry.invoke(_key), "Brightness/Contrast opens")
    _brightness(30.0)
    assert_true(_window.describe()["on_canvas"], "with its pass on the canvas")
    var stroke_before := _texel(stroke)
    var under_before := _texel(under)

    _doc.set_active_layer(under)
    assert_true(_window.visible, "A layer picked in the docker leaves the dialog open")
    assert_eq(_window.context.layer, under, "and its context is built on the layer picked")
    assert_true(_window.describe()["on_canvas"], "with the canvas preview still drawn")
    assert_true(_window.dialog.canvas_box.button_pressed, "and its switch kept")
    assert_eq(float(_window.filter.parameters()["brightness"]), 30.0, "The setting the painter had is kept")
    _brightness(60.0)
    var steps := _doc.undo_redo.get_history_count()
    _window.apply_filter()

    assert_eq(_doc.undo_redo.get_history_count(), steps + 1, "Apply is one history step")
    var under_after := _texel(under)
    assert_true(under_after.r > under_before.r + 0.02, "The layer picked is written: %s from %s" % [under_after, under_before])
    assert_true(_same(_texel(stroke), stroke_before), "and the layer the dialog opened on is unchanged: %s" % _texel(stroke))
    assert_false(_window.visible, "and the dialog closes")


func test_settings_kept_across_a_switch_reach_apply_without_another_move() -> void:
    var under := _doc.get_node("Layer 1") as SaLayer
    _registry.invoke(_key)
    _brightness(60.0)
    var before := _texel(under)
    _doc.set_active_layer(under)
    _window.apply_filter()
    assert_true(_texel(under).r > before.r + 0.02, "The brightness set before the switch is what Apply writes")


func test_a_switch_to_a_locked_layer_dims_bake_with_its_reason() -> void:
    var under := _doc.get_node("Layer 1") as SaLayer
    under.is_locked = true
    _registry.invoke(_key)
    assert_false(_window.way_toggle.dimmed.has(&"bake"), "Bake is open on the stroke")
    _doc.set_active_layer(under)
    assert_true(_window.visible, "A locked layer picked leaves the dialog open, as an open on it would")
    assert_true(_window.way_toggle.dimmed.has(&"bake"), "with Bake dimmed")
    assert_false(String(_window.way_toggle.dimmed[&"bake"]).is_empty(), "and the reason in its tooltip")
    _window.cancel_filter()
    under.is_locked = false


func test_a_tab_switched_with_the_dialog_open_closes_it_and_writes_nothing() -> void:
    var stroke := _doc.get_node("Stroke") as SaLayer
    var before := _texel(stroke)
    _registry.invoke(_key)
    _brightness(60.0)
    var steps := _doc.undo_redo.get_history_count()

    var other := Bench.easel(SIZE)
    var elsewhere := SaCanvas.new()
    elsewhere.easel = other
    _window.target_canvas = elsewhere
    EventBus.active_document_changed.emit(null)

    assert_false(_window.visible, "Another document in front closes the dialog")
    assert_null(_window.context, "and drops its context")
    assert_false(_window.describe()["on_canvas"], "and takes its preview off")
    assert_eq(_doc.undo_redo.get_history_count(), steps, "with no history step")
    assert_true(_same(_texel(stroke), before), "and no write into the document it opened on")
    _window.target_canvas = _canvas
    Teardown.free_nodes([elsewhere, other])


func test_a_document_let_go_with_the_dialog_open_closes_it_and_writes_nothing() -> void:
    var stroke := _doc.get_node("Stroke") as SaLayer
    var before := _texel(stroke)
    _registry.invoke(_key)
    _brightness(60.0)
    var steps := _doc.undo_redo.get_history_count()

    # What letting a closed document go says, `SaSadLettingGo`'s last word.
    _doc.active_layer_changed.emit(null)

    assert_false(_window.visible, "A document closing closes the dialog")
    assert_null(_window.context, "and drops its context")
    assert_eq(_doc.undo_redo.get_history_count(), steps, "with no history step")
    assert_true(_same(_texel(stroke), before), "and no write")


func test_a_dialog_with_no_switch_applies_as_before() -> void:
    var stroke := _doc.get_node("Stroke") as SaLayer
    var under := _doc.get_node("Layer 1") as SaLayer
    var under_before := _texel(under)
    var before := _texel(stroke)
    _registry.invoke(_key)
    _brightness(60.0)
    _window.apply_filter()
    assert_true(_texel(stroke).r > before.r + 0.1, "The layer it opened on is written")
    assert_true(_same(_texel(under), under_before), "and no other")


func test_a_layer_added_by_apply_is_not_followed() -> void:
    _window.layer_types = Fixtures.make_registries().layer_types
    var layers := SaLayerOps.new(_doc).layers().size()
    _registry.invoke(_key)
    _brightness(30.0)
    SaFilterDialogWindow.capture(Engine.get_main_loop() as SceneTree, {"way": "layer"})
    var steps := _doc.undo_redo.get_history_count()
    _window.apply_filter()
    assert_eq(SaLayerOps.new(_doc).layers().size(), layers + 1, "Layer's Apply adds one adjustment layer")
    assert_eq(_doc.undo_redo.get_history_count(), steps + 1, "as one history step")
    assert_false(_window.visible, "and the dialog closes, rather than opening again on the layer it made")
