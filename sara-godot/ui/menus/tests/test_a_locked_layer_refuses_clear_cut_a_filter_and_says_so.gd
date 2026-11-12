## A command that would write a locked layer's paint is
## refused at its start and says so, with its own word.
##
## Each command warns when run on a fully locked layer, so Ctrl+X on a locked
## layer never reads as a key that never arrived. Each case paints the layer, locks it, runs the
## command the way the menu does and reads the line said, no step, and paint
## that stayed. A filter's bake already said the lock's line and is held here
## with them. A paste writes no layer's paint, as it puts a new layer down above
## the active one, so it is not refused, and the case reads that the locked
## layer kept its paint and the pasted pixels went to a layer of their own.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")

const PAINT := Color(0.25, 0.5, 0.75, 1.0)
const AT := Vector2i(40, 40)

var _surface: SaSurface = null
var _doc: SaDocument = null
var _registries: SaRegistries = null
var _said: Array[String] = []


func before_each() -> void:
    _surface = Fixtures.make_surface(Vector2i(256, 256))
    _surface.easel.compositor.set_registry(Fixtures.make_registries().blend_modes)
    _doc = _surface.easel.document
    _registries = Fixtures.make_registries(_surface)
    var layer := SaLayerOps.new(_doc).add(&"")
    _doc.set_active_layer(layer)
    _doc.fill_layer(PAINT, layer)
    _doc.history.reset()
    _doc.undo_redo.clear_history()
    _said.clear()
    # What an earlier suite refused waits for the next sink, and is not ours.
    SaProblems.pending_refusals = PackedStringArray()
    EventBus.paint_refused.connect(_hear)
    SaProblems.attach_sink(
        func(line: String, kind: SaProblems.Kind) -> void:
            if kind == SaProblems.Kind.REFUSAL:
                _said.append(line)
    )


func after_each() -> void:
    SaProblems.detach_sink()
    if EventBus.paint_refused.is_connected(_hear):
        EventBus.paint_refused.disconnect(_hear)
    _registries = null
    Fixtures.teardown(_surface)
    _surface = null
    _doc = null


func _hear(line: String) -> void:
    _said.append(line)


func _texel() -> Color:
    return Bench.texel(_doc.active_layer.get_field(Vector2i.ZERO), AT)


func _locked(gesture: String) -> String:
    return "This layer is locked, so the %s did nothing. Unlock it in the Layers docker." % gesture


## Reads one refusal of *gesture*, no step and the paint as it was.
func _check_refused(gesture: String, before: Color) -> void:
    assert_eq(_said, [_locked(gesture)] as Array[String], "the %s said the lock once" % gesture)
    assert_eq(_doc.history.step_count(), 0, "the %s made no step" % gesture)
    assert_almost_eq(_texel().b, before.b, 1.0e-6, "and the paint stayed")
    assert_almost_eq(_texel().a, before.a, 1.0e-6, "its coverage too")


func test_clear_on_a_locked_layer_is_refused_and_says_so() -> void:
    var before := _texel()
    _doc.active_layer.is_locked = true
    assert_false(_registries.commands.execute(&"layer_clear"), "Clear is declined")
    _check_refused("clear", before)


func test_a_fill_on_a_locked_layer_names_the_fill() -> void:
    var before := _texel()
    _doc.active_layer.is_locked = true
    assert_false(_registries.commands.execute(&"fill_foreground"), "the fill is declined")
    _check_refused("fill", before)


func test_cut_on_a_locked_layer_is_refused_and_says_so() -> void:
    var before := _texel()
    _doc.selection.select_rect(Rect2i(20, 20, 60, 60))
    var steps := _doc.history.step_count()
    _doc.active_layer.is_locked = true
    assert_false(SaClipboard.new().cut(_doc, _doc.active_layer), "the cut is declined")
    assert_eq(_said, [_locked("cut")] as Array[String], "the cut said the lock once")
    assert_eq(_doc.history.step_count(), steps, "the cut made no step")
    assert_almost_eq(_texel().a, before.a, 1.0e-6, "and the paint stayed")


## A paste puts a new layer down, so the locked layer keeps its paint and the
## paste is not a write the lock turns away.
func test_a_paste_over_a_locked_layer_leaves_its_paint_and_lands_on_a_layer_of_its_own() -> void:
    var locked := _doc.active_layer
    var before := _texel()
    _doc.selection.select_rect(Rect2i(20, 20, 60, 60))
    var clipboard := SaClipboard.new()
    assert_true(clipboard.copy(_doc, locked) > 0, "the copy took the paint")
    locked.is_locked = true
    var pasted := clipboard.paste(_doc)
    assert_not_null(pasted, "the paste made a layer")
    assert_true(pasted != locked, "and not the locked one")
    assert_almost_eq(Bench.texel(locked.get_field(Vector2i.ZERO), AT).b, before.b, 1.0e-6, "the locked layer kept its paint")
    assert_true(_said.is_empty(), "nothing was refused: %s" % [_said])


## A filter's bake through the dialog, Filter > Adjust > Hue/Saturation as the
## menu opens it, writes nothing on a locked layer and says the lock's line.
func test_a_filter_on_a_locked_layer_is_refused_and_says_so() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    var embedding := tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    var host := Node.new()
    EventBus.add_child(host)
    var registry := SaFilterRegistry.new()
    _surface.easel.compositor.filter_chain.registry = registry
    var hsl := SaHueSaturationLightnessFilter.new()
    registry.register(hsl, &"sara-base-modules")
    var canvas := SaCanvas.new()
    canvas.easel = _surface.easel
    var window := SaFilterDialogWindow.new()
    window.target_canvas = canvas
    window.layer_types = Fixtures.make_registries().layer_types
    window.watch(registry)
    host.add_child(window)

    var before := _texel()
    _doc.active_layer.is_locked = true
    assert_true(registry.invoke(SaFilterRegistry.key_for(&"sara-base-modules", hsl)), "the Filter menu's door opens it")
    assert_false(SaFilterOps.one_shot(window.context, window.filter), "the bake writes nothing")
    window.cancel_filter()
    assert_eq(_said.size(), 1, "the filter said one line: %s" % [_said])
    assert_true(_said[0].ends_with(_locked("filter")) if _said.size() > 0 else false, "the lock's: %s" % [_said])
    assert_eq(_doc.history.step_count(), 0, "no step was made")
    assert_almost_eq(_texel().b, before.b, 1.0e-6, "and the paint stayed")

    SaSettings.filter_way = "bake"
    window.free()
    canvas.free()
    host.free()
    tree.root.gui_embed_subwindows = embedding
