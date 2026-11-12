## An attached filter keeps to the selection it was attached
## under, as Bake does.
##
## The fault: a marquee over the left part of three
## strokes, Filter > Colour > Hue/Saturation/Lightness at Hue 150 and Attach,
## recoloured the whole layer while Bake kept inside the rectangle. The
## selection now becomes the new record's mask inside the one Attach Filter
## step, on the Attach way and on the Layer way alike, and with nothing
## selected the record has no mask and reaches the whole layer as before.
##
## The painting is two chunks across with the background hidden and one
## yellow layer over both, the rectangle over the left half of the left chunk.
## Each case drives the dialog the way the Filter menu opens it and reads the
## composite inside the rectangle, beside it in the same chunk and in the
## chunk the rectangle never reaches.
extends "res://tests/test_framework.gd"

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")
const Fixtures = preload("res://tests/fixtures.gd")

const REQUIRES_GPU := true

const SIZE := Vector2i(512, 256)
const LEFT := Vector2i(0, 0)
const RIGHT := Vector2i(1, 0)
const YELLOW := Color(0.85, 0.75, 0.1, 1.0)
const MARQUEE := Rect2i(0, 0, 128, 256)
const INSIDE := Vector2i(64, 128)
const BESIDE := Vector2i(200, 128)
const FAR := Vector2i(400, 128)
const SENTENCE := "The selection becomes the filter's mask."
## How far a texel the filter reached moves at the least, and how far one it
## did not reach may move at the most.
const MOVED := 0.05
const KEPT := 1.0e-4

var _easel: SaEasel = null
var _doc: SaDocument = null
var _canvas: SaCanvas = null
var _window: SaFilterDialogWindow = null
var _host: Node = null
var _registry: SaFilterRegistry = null
var _key: StringName = &""
var _paint: SaLayer = null
var _was_embedding: bool = false


func before_each() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    if tree != null:
        _was_embedding = tree.root.gui_embed_subwindows
        tree.root.gui_embed_subwindows = true
    _host = Node.new()
    _host.name = "S12TestHost"
    EventBus.add_child(_host)

    _easel = Bench.easel(SIZE)
    _doc = _easel.document
    (_doc.get_node("Background") as SaLayer).visible = false
    _paint = _doc.get_node("Layer 1") as SaLayer
    _doc.set_active_layer(_paint)
    for grid_pos: Vector2i in [LEFT, RIGHT]:
        _paint.get_or_create_chunk(grid_pos).clear(YELLOW)
    _doc.history.reset()
    _doc.undo_redo.clear_history()

    _registry = _easel.compositor.filter_chain.registry
    var hsl := SaHueSaturationLightnessFilter.new()
    _registry.register(hsl, &"sara-base-modules")
    _key = SaFilterRegistry.key_for(&"sara-base-modules", hsl)

    _canvas = SaCanvas.new()
    _canvas.easel = _easel
    _window = SaFilterDialogWindow.new()
    _window.target_canvas = _canvas
    _window.layer_types = Fixtures.make_registries().layer_types
    _window.watch(_registry)
    _host.add_child(_window)


func after_each() -> void:
    # A pick is remembered for the next filter, and no suite leaves it for another.
    SaSettings.filter_way = "bake"
    _window.free()
    _window = null
    _canvas.free()
    _canvas = null
    _easel.free()
    _easel = null
    _doc = null
    _paint = null
    _registry = null
    _host.free()
    _host = null
    var tree := Engine.get_main_loop() as SceneTree
    if tree != null:
        tree.root.gui_embed_subwindows = _was_embedding


## The output after a full composite, as bytes.
func _output() -> PackedByteArray:
    _doc.invalidate_chunks([LEFT, RIGHT])
    Bench.composite(_easel)
    return GlobalShaderCompiler.get_rd().texture_get_data(_easel.output.rid, 0)


## How far the texel at *at* lies apart in two outputs, the worst channel.
func _apart(a: PackedByteArray, b: PackedByteArray, at: Vector2i) -> float:
    var texture := _easel.output
    var index := at.y * texture.size.x + at.x
    var one := SaFieldSpec.decode_texel(a, texture.format, index)
    var two := SaFieldSpec.decode_texel(b, texture.format, index)
    return maxf(maxf(absf(one.r - two.r), absf(one.g - two.g)), maxf(absf(one.b - two.b), absf(one.a - two.a)))


## Opens Hue/Saturation/Lightness at Hue 150, picks *way* and presses Apply.
func _apply(way: String) -> void:
    var tree := Engine.get_main_loop() as SceneTree
    assert_true(_registry.invoke(_key), "The Filter menu's door opens Hue/Saturation/Lightness")
    SaFilterDialogWindow.capture(tree, {"widget": "hue", "value": 150.0})
    _window.dialog.flush_rerun()
    assert_true(SaFilterDialogWindow.capture(tree, {"way": way}).contains("way %s picked" % way), "%s is picked" % way)
    _window.apply_filter()


## Whether the filter reached inside the rectangle and nowhere else, read
## against *before*.
func _assert_inside_alone(before: PackedByteArray, what: String) -> void:
    var after := _output()
    var inside := _apart(before, after, INSIDE)
    assert_true(inside > MOVED, "%s: inside the rectangle the yellow turns, by %s" % [what, inside])
    assert_almost_eq(_apart(before, after, BESIDE), 0.0, KEPT, "%s: beside it in the same chunk it is kept" % what)
    assert_almost_eq(_apart(before, after, FAR), 0.0, KEPT, "%s: in the chunk it never reaches it is kept" % what)


func _tooltip(way: StringName) -> String:
    for option: Dictionary in _window.way_toggle.options:
        if option["id"] == way:
            return String(option["tooltip"])
    return ""


func test_attach_under_a_marquee_recolours_inside_it_alone_and_undoes_in_one_step() -> void:
    var before := _output()
    _doc.selection.select_rect(MARQUEE)
    var steps := _doc.undo_redo.get_history_count()
    var kept := _doc.history.total_layer_bytes()
    _apply("attach")

    assert_eq(_paint.filters.size(), 1, "One record lands on the layer")
    var record := _paint.filters[0]
    assert_not_null(record.mask, "with a mask")
    assert_true(record.mask.is_own(), "of its own chunks")
    assert_eq(record.mask.grid_positions(), [LEFT] as Array[Vector2i], "held only where the selection holds a chunk")
    assert_eq(_doc.undo_redo.get_history_count(), steps + 1, "Attach under a selection is one history step")
    assert_eq(_doc.undo_redo.get_current_action_name(), "Attach Filter", "named Attach Filter")
    assert_true(record.byte_size() > 0, "The mask holds VRAM")
    assert_eq(_doc.history.total_layer_bytes(), kept + record.byte_size(), "which the step is charged with")
    _assert_inside_alone(before, "Attached")

    assert_true(_doc.undo(), "Ctrl+Z")
    assert_true(_paint.filters.is_empty(), "takes the record off")
    assert_almost_eq(_apart(before, _output(), INSIDE), 0.0, KEPT, "and the inside is yellow again")
    assert_true(_doc.redo(), "Redo")
    assert_eq(_paint.filters, [record] as Array[SaAttachedFilter], "brings the very record back")
    assert_not_null(record.mask, "mask and all")
    _assert_inside_alone(before, "Redone")


func test_attach_with_nothing_selected_has_no_mask_and_reaches_the_whole_layer() -> void:
    var before := _output()
    _apply("attach")

    assert_eq(_paint.filters.size(), 1, "One record lands on the layer")
    assert_null(_paint.filters[0].mask, "with no mask")
    var after := _output()
    for at: Vector2i in [INSIDE, BESIDE, FAR]:
        assert_true(_apart(before, after, at) > MOVED, "and the yellow turns everywhere, at %s" % at)


func test_the_layer_way_under_a_marquee_adjusts_inside_it_alone() -> void:
    var before := _output()
    _doc.selection.select_rect(MARQUEE)
    var layers := SaLayerOps.new(_doc).layers().size()
    _apply("layer")

    var added := _doc.active_layer
    assert_true(added.is_adjustment(), "Layer adds an adjustment layer")
    assert_eq(added.filters.size(), 1, "holding one record")
    assert_not_null(added.filters[0].mask, "whose mask is the selection")
    assert_true(
        SaFilterConversion.hides_nothing(added.mask),
        "and the layer's own mask, which every new layer has, hides nothing, so it can become an attached filter again"
    )
    assert_true(_paint.filters.is_empty(), "The painted layer gains no record")
    _assert_inside_alone(before, "Adjusted")

    assert_true(_doc.undo(), "Ctrl+Z")
    assert_eq(SaLayerOps.new(_doc).layers().size(), layers, "takes the layer away")
    assert_almost_eq(_apart(before, _output(), INSIDE), 0.0, KEPT, "and the inside is yellow again")


func test_attach_and_layer_say_the_selection_becomes_the_mask_only_while_there_is_one() -> void:
    _registry.invoke(_key)
    for way: StringName in [&"attach", &"layer"]:
        assert_false(_tooltip(way).contains(SENTENCE), "With nothing selected %s's tooltip says nothing of a mask" % way)
    _window.cancel_filter()

    _doc.selection.select_rect(MARQUEE)
    _registry.invoke(_key)
    for way: StringName in [&"attach", &"layer"]:
        assert_true(_tooltip(way).contains(SENTENCE), "Under a selection %s's tooltip says it becomes the mask" % way)
    assert_false(_tooltip(&"bake").contains(SENTENCE), "and Bake's does not, which keeps to it by writing inside it")
    _window.cancel_filter()


func test_the_mask_step_from_the_selection_is_unchanged() -> void:
    _doc.selection.select_rect(MARQUEE)
    var bare := SaAttachedFilter.new(_key, {})
    var steps := _doc.undo_redo.get_history_count()
    assert_true(SaMaskOps.new(_doc).add_from_selection(bare), "Add Mask from Selection still runs")
    assert_eq(_doc.undo_redo.get_history_count(), steps + 1, "as one step of its own")
    assert_eq(bare.mask.grid_positions(), [LEFT] as Array[Vector2i], "holding the chunks the selection holds")
