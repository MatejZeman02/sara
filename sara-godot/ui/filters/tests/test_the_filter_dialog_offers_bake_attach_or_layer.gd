## The Filter dialog offers Bake, Attach or Layer, and an
## attached filter and an adjustment layer turn into each other where the
## picture allows it.
##
## The default is baking, with a three-option toggle Bake|Attach|Layer. The dialog opens on Bake
## every time, Attach puts one record on the active layer, Layer one adjustment
## layer holding it above the active layer. The root's first record and an
## isolated group's first record become an adjustment layer at the top of the
## document or of the group and back with the output unchanged, and a record on
## a paint layer or a masked adjustment layer is refused with its sentence.
##
## The painting is the filter dialog suites' bench: two chunks across, the grey background hidden, an
## opaque layer over the left chunk and a stroke at half alpha over both.
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
const RECORD := {"brightness": 30.0, "contrast": 25.0}
const TOLERANCE := 1.0e-5

var _easel: SaEasel = null
var _doc: SaDocument = null
var _canvas: SaCanvas = null
var _window: SaFilterDialogWindow = null
var _host: Node = null
var _registry: SaFilterRegistry = null
var _types: SaLayerTypeRegistry = null
var _key: StringName = &""
var _blur: StringName = &""
var _wrap: StringName = &""
var _was_embedding: bool = false


func before_each() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    if tree != null:
        _was_embedding = tree.root.gui_embed_subwindows
        tree.root.gui_embed_subwindows = true
    SaProblems.pending_refusals = PackedStringArray()
    # The refusals below are provoked on purpose, so the transcript shows the
    # assertions and not the lines they check.
    SaProblems.announce = false

    _host = Node.new()
    _host.name = "F4TestHost"
    EventBus.add_child(_host)

    _easel = _painting()
    _doc = _easel.document
    _registry = _easel.compositor.filter_chain.registry
    _key = SaFilterRegistry.key_for(&"sara-base-modules", SaBrightnessContrastFilter.new())
    _blur = SaFilterRegistry.key_for(&"sara-base-modules", SaGaussianBlurFilter.new())
    _registry.register(SaBrightnessContrastFilter.new(), &"sara-base-modules")
    _registry.register(SaGaussianBlurFilter.new(), &"sara-base-modules")
    _wrap = SaFilterRegistry.key_for(&"sara-base-modules", SaWrapOffsetFilter.new())
    _registry.register(SaWrapOffsetFilter.new(), &"sara-base-modules")
    _types = Fixtures.make_registries().layer_types

    _canvas = SaCanvas.new()
    _canvas.easel = _easel

    _window = SaFilterDialogWindow.new()
    _window.target_canvas = _canvas
    _window.layer_types = _types
    _window.watch(_registry)
    _host.add_child(_window)


func after_each() -> void:
    # A pick is remembered for the next filter, and no suite leaves it for another.
    SaSettings.filter_way = "bake"
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


## The painting of the header, with the stroke active.
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


func _layer_count() -> int:
    return SaLayerOps.new(_doc).layers().size()


func _steps() -> int:
    return _doc.undo_redo.get_history_count()


## The output as it stands after a full composite, as bytes.
func _output() -> PackedByteArray:
    _doc.invalidate_chunks([LEFT, RIGHT])
    Bench.composite(_easel)
    return GlobalShaderCompiler.get_rd().texture_get_data(_easel.output.rid, 0)


## The worst channel apart between two outputs, read every third texel.
func _worst(a: PackedByteArray, b: PackedByteArray) -> float:
    var texture := _easel.output
    var worst := 0.0
    for y in range(0, SIZE.y, 3):
        for x in range(0, SIZE.x, 3):
            var index := y * texture.size.x + x
            var one := SaFieldSpec.decode_texel(a, texture.format, index)
            var two := SaFieldSpec.decode_texel(b, texture.format, index)
            worst = maxf(
                worst, maxf(maxf(absf(one.r - two.r), absf(one.g - two.g)), maxf(absf(one.b - two.b), absf(one.a - two.a)))
            )
    return worst


func _refused(part: String) -> bool:
    for line in SaProblems.pending_refusals:
        if line.contains(part):
            return true
    return false


func test_the_filter_menus_door_opens_the_dialog_on_bake_and_apply_writes() -> void:
    var stroke := _doc.active_layer
    var before := Bench.texel(stroke.get_field(LEFT), Vector2i(10, 10))
    var layers := _layer_count()
    var steps := _steps()

    assert_true(_registry.invoke(_key), "The Filter menu's door invokes the filter")
    assert_true(_window.visible, "and the dialog opens")
    assert_not_null(_window.way_toggle, "with a toggle of four")
    var labels: Array[String] = []
    for option: Dictionary in _window.way_toggle.options:
        labels.append(option["label"])
    assert_eq(labels, ["Apply", "Attach", "Layer"] as Array[String], "Apply, Attach and Layer, in that order")
    assert_eq(_window.way(), &"bake", "on Bake")
    assert_false(_window.way_toggle.dimmed.has(&"layer"), "and Layer can be picked for a point filter")
    # A brightness a hand would move to. The dialog opens at nought and nought,
    # which is the filter's identity, and Bake there wrote each texel back as it
    # was: the case read the float noise of that round trip, which Linux's
    # driver leaves and Windows's did not.
    SaFilterDialogWindow.capture(Engine.get_main_loop() as SceneTree, {"widget": "brightness", "value": 60.0})
    _window.dialog.flush_rerun()
    _window.apply_filter()

    assert_eq(_steps(), steps + 1, "Apply on Bake is one history step")
    assert_true(stroke.filters.is_empty(), "adds no record")
    assert_eq(_layer_count(), layers, "and no layer")
    var after := Bench.texel(stroke.get_field(LEFT), Vector2i(10, 10))
    assert_true(after.r > before.r + 0.1, "and writes the layer's paint, brighter: %s from %s" % [after, before])


func test_attach_puts_one_record_on_the_active_layer_and_adds_no_layer() -> void:
    var stroke := _doc.active_layer
    var layers := _layer_count()
    _registry.invoke(_key)
    assert_true(
        SaFilterDialogWindow.capture(Engine.get_main_loop() as SceneTree, {"way": "attach"}).contains("way attach picked"),
        "The step picks Attach"
    )
    _window.apply_filter()

    assert_eq(stroke.filters.size(), 1, "One record lands on the active layer")
    assert_eq(stroke.filters[0].key, _key, "of the open filter")
    assert_eq(_layer_count(), layers, "and no layer is added")

    _registry.invoke(_key)
    assert_eq(_window.way(), &"attach", "The dialog opened again after an Attach is on Attach, the way last picked")
    _window.cancel_filter()


func test_layer_puts_one_adjustment_layer_holding_the_record_above_the_active_layer() -> void:
    var stroke := _doc.active_layer
    var layers := _layer_count()
    var steps := _steps()
    _registry.invoke(_key)
    # Through the capture's widget step, which moves a slider by the signal a
    # hand raises, since `SaPageRow.drive` alone does not reach a slider.
    SaFilterDialogWindow.capture(Engine.get_main_loop() as SceneTree, {"widget": "brightness", "value": 30.0})
    _window.dialog.flush_rerun()
    assert_true(_window.way_toggle.pick(&"layer"), "Layer takes the pick")
    _window.apply_filter()

    assert_eq(_layer_count(), layers + 1, "Layer adds one layer")
    var added := _doc.active_layer
    assert_true(added.is_adjustment(), "an adjustment layer")
    assert_eq(added.get_index(), stroke.get_index() + 1, "directly above the active layer")
    assert_eq(added.filters.size(), 1, "holding one record")
    assert_eq(added.filters[0].key, _key, "of the open filter")
    assert_eq(float(added.filters[0].parameters.get("brightness", 0.0)), 30.0, "with the dialog's values")
    assert_true(stroke.filters.is_empty(), "and the active layer gains no record")
    assert_eq(_steps(), steps + 1, "as one history step")

    _doc.undo_redo.undo()
    assert_eq(_layer_count(), layers, "Undo takes the layer away")
    assert_eq(_doc.active_layer, stroke, "and the stroke is active again")


func test_layer_is_offered_for_a_blur() -> void:
    _registry.invoke(_blur)
    assert_false(_window.way_toggle.dimmed.has(&"layer"), "Layer is offered for a blur, which reads its neighbours")
    _window.cancel_filter()


func test_layer_is_dimmed_for_a_filter_that_reads_the_whole_layer() -> void:
    _registry.invoke(_wrap)
    assert_true(_window.way_toggle.dimmed.has(&"layer"), "Layer is dimmed for a wrap")
    assert_true(String(_window.way_toggle.dimmed[&"layer"]).contains("reads the whole layer"), "and says why")
    assert_false(_window.way_toggle.dimmed.has(&"attach"), "while Attach is not")
    assert_true(
        SaFilterDialogWindow.capture(Engine.get_main_loop() as SceneTree, {"way": "layer"}).contains("dimmed"),
        "and a step cannot pick it"
    )
    _window.cancel_filter()


func test_the_roots_first_record_converts_to_an_adjustment_layer_and_back() -> void:
    var record := SaFilterOps.new(_doc).attach(null, _key, RECORD)
    var attached := _output()
    var layers := _layer_count()
    var steps := _steps()
    var conversion := SaFilterConversion.new(_doc)

    var layer := conversion.to_layer(null, record, _types, "Brightness")
    assert_not_null(layer, "The root's first record converts")
    assert_true(layer.is_adjustment(), "into an adjustment layer")
    assert_eq(layer.get_index(), _doc.get_child_count() - 1, "at the top of the document")
    assert_eq(layer.filters, [record] as Array[SaAttachedFilter], "holding the very record")
    assert_true(_doc.root_filters.is_empty(), "which left the root")
    assert_eq(_steps(), steps + 1, "as one step")
    var worst := _worst(attached, _output())
    assert_true(worst <= TOLERANCE, "and the output is unchanged, worst %s" % worst)

    assert_true(conversion.to_record(layer), "The layer converts back")
    assert_eq(_doc.root_filters, [record] as Array[SaAttachedFilter], "and the record is on the root again")
    assert_eq(_layer_count(), layers, "with the layer gone")
    worst = _worst(attached, _output())
    assert_true(worst <= TOLERANCE, "and the output unchanged, worst %s" % worst)

    _doc.undo_redo.undo()
    assert_eq(layer.get_parent(), _doc, "Undo of the way back puts the layer back")
    assert_eq(layer.filters, [record] as Array[SaAttachedFilter], "with its record")
    _doc.undo_redo.undo()
    assert_eq(_doc.root_filters, [record] as Array[SaAttachedFilter], "and undo of the conversion puts the record on the root")
    assert_eq(_layer_count(), layers, "and takes the layer away")


func test_an_isolated_groups_first_record_converts_and_back() -> void:
    var ops := SaLayerOps.new(_doc)
    var group := ops.group_active()
    ops.set_isolated(group, true)
    var record := SaFilterOps.new(_doc).attach(group, _key, RECORD)
    var attached := _output()
    var conversion := SaFilterConversion.new(_doc)

    var layer := conversion.to_layer(group, record, _types)
    assert_not_null(layer, "An isolated group's first record converts")
    assert_eq(SaLayerStack.parent_of(layer), group, "into a member of the group")
    assert_eq(layer.get_index(), group.get_index() - 1, "at its top")
    assert_true(group.filters.is_empty(), "and the record left the group")
    var worst := _worst(attached, _output())
    assert_true(worst <= TOLERANCE, "with the output unchanged, worst %s" % worst)

    assert_true(conversion.to_record(layer), "The layer converts back")
    assert_eq(group.filters, [record] as Array[SaAttachedFilter], "onto the group")
    worst = _worst(attached, _output())
    assert_true(worst <= TOLERANCE, "with the output unchanged, worst %s" % worst)


func test_a_record_on_a_paint_layer_is_refused_and_nothing_moves() -> void:
    var stroke := _doc.active_layer
    var record := SaFilterOps.new(_doc).attach(stroke, _key, RECORD)
    var layers := _layer_count()
    var steps := _steps()

    assert_null(SaFilterConversion.new(_doc).to_layer(stroke, record, _types), "A record on a paint layer is refused")
    assert_true(_refused("works on that layer alone"), "with its sentence")
    assert_eq(stroke.filters, [record] as Array[SaAttachedFilter], "and the record stays")
    assert_eq(_layer_count(), layers, "no layer is added")
    assert_eq(_steps(), steps, "and no step taken")


func test_a_second_record_and_a_pass_through_group_are_refused() -> void:
    var ops := SaLayerOps.new(_doc)
    var group := ops.group_active()
    var filters := SaFilterOps.new(_doc)
    var first := filters.attach(group, _key, RECORD)
    var conversion := SaFilterConversion.new(_doc)
    assert_null(conversion.to_layer(group, first, _types), "A pass-through group isolated only by the record is refused")
    assert_true(_refused("blends on its own only because of this filter"), "with its sentence")
    var second := filters.attach(group, _key, RECORD)
    assert_null(conversion.to_layer(group, second, _types), "A record that is not the first is refused")
    assert_true(_refused("Only the first filter"), "with its sentence")
    assert_eq(group.filters, [first, second] as Array[SaAttachedFilter], "and nothing moves")


func test_a_masked_adjustment_layer_is_refused_and_nothing_moves() -> void:
    var layer := SaLayerOps.new(_doc).add(SaBackdropLayer.TYPE_ID, _types)
    var record := SaFilterOps.new(_doc).attach(layer, _key, RECORD)
    # A mask that hides everything, since one hiding nothing converts.
    layer.add_mask(0.0).rest = 0.0
    var layers := _layer_count()
    var steps := _steps()

    assert_false(SaFilterConversion.new(_doc).to_record(layer), "A masked adjustment layer is refused")
    assert_true(_refused("has a mask of its own"), "with its sentence")
    assert_eq(layer.filters, [record] as Array[SaAttachedFilter], "and its record stays")
    assert_true(_doc.root_filters.is_empty(), "nothing lands on the root")
    assert_eq(_layer_count(), layers, "the layer stays")
    assert_eq(_steps(), steps, "and no step is taken")


func test_a_faded_or_other_mode_adjustment_layer_is_refused() -> void:
    var layer := SaLayerOps.new(_doc).add(SaBackdropLayer.TYPE_ID, _types)
    SaFilterOps.new(_doc).attach(layer, _key, RECORD)
    var conversion := SaFilterConversion.new(_doc)
    layer.opacity = 0.5
    assert_true(conversion.record_refusal(layer).contains("has 50% opacity"), "A faded one says so")
    layer.opacity = 1.0
    layer.blend_mode = SaLayer.BLEND_MODE.MULTIPLY
    assert_true(conversion.record_refusal(layer).contains("Normal"), "and one in another mode says so")
    layer.blend_mode = SaLayer.BLEND_MODE.NORMAL
    assert_eq(conversion.record_refusal(layer), "", "and at Normal and full opacity at the top it converts")
