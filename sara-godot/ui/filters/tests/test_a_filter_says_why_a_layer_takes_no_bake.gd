## A filter's dialog says why the active layer takes no bake.
##
## The fault: with an adjustment layer, a locked layer
## or a group active, Filter > Blur > Box Blur opened with a live Apply on
## Bake, and Apply closed it having written nothing, made no step and said
## nothing. Bake is now dimmed with `SaFilterApply.way_refusal`'s sentence as
## its tooltip, the toggle opens on the first way left open, and a write that
## is reached past the dialog says the same sentence in the corner. A hidden
## layer still bakes, with one line under the preview saying the canvas will
## not show it.
##
## Each case drives the dialog the way the Filter menu opens it, through the
## registry's door, and reads `describe()` beside the helper.
extends "res://tests/test_framework.gd"

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")
const Fixtures = preload("res://tests/fixtures.gd")
const BoxBlurFilter = preload("res://modules/sara-base-modules/base/usual/box_blur_filter.gd")

const REQUIRES_GPU := true

const SIZE := Vector2i(256, 256)
const PAINT := Color(0.25, 0.5, 0.75, 1.0)
const AT := Vector2i(40, 40)
const LOCKED := "This layer is locked, so the filter did nothing. Unlock it in the Layers docker."
const STORES := "'%s' stores no paint."
const HIDDEN := "This layer is hidden, so the canvas will not show the result."
const PROBLEM := "line 3: cannot return a vec3 from a vec4 function"


## A filter that cannot be attached, so over a layer that takes no bake every
## way of its dialog is dimmed. Its run shows the layer, so a dimmed Apply is
## the toggle's doing and not a run that came back with nothing.
class Broken:
    extends SaFilter

    func title() -> String:
        return "Broken"

    func build(ui: SaDialog) -> void:
        ui.title("Broken")
        ui.apply_cancel()

    func problem() -> String:
        return PROBLEM

    func run(ctx: SaFilterContext) -> void:
        ctx.show(ctx.layer_pixels(0))


var _easel: SaEasel = null
var _doc: SaDocument = null
var _canvas: SaCanvas = null
var _window: SaFilterDialogWindow = null
var _host: Node = null
var _registry: SaFilterRegistry = null
var _paint: SaLayer = null
var _blur_key: StringName = &""
var _hsl_key: StringName = &""
var _broken_key: StringName = &""
var _refused: Array[String] = []
var _was_embedding: bool = false


func before_each() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    if tree != null:
        _was_embedding = tree.root.gui_embed_subwindows
        tree.root.gui_embed_subwindows = true
    _host = Node.new()
    _host.name = "S25TestHost"
    EventBus.add_child(_host)

    _easel = Bench.easel(SIZE)
    _doc = _easel.document
    _paint = _doc.active_layer
    _doc.fill_layer(PAINT, _paint)
    _doc.history.reset()
    _doc.undo_redo.clear_history()

    # The chain's own registry, so what the dialog attaches is evaluated.
    _registry = _easel.compositor.filter_chain.registry
    ModuleLoader.module_dirs[&"sara-base-modules"] = "res://modules/sara-base-modules/base"
    var blur := BoxBlurFilter.new()
    _registry.register(blur, &"sara-base-modules")
    _blur_key = SaFilterRegistry.key_for(&"sara-base-modules", blur)
    var hsl := SaHueSaturationLightnessFilter.new()
    _registry.register(hsl, &"sara-base-modules")
    _hsl_key = SaFilterRegistry.key_for(&"sara-base-modules", hsl)
    var broken := Broken.new()
    _registry.register(broken, &"s25_suite")
    _broken_key = SaFilterRegistry.key_for(&"s25_suite", broken)

    _canvas = SaCanvas.new()
    _canvas.easel = _easel
    _window = SaFilterDialogWindow.new()
    _window.target_canvas = _canvas
    _window.layer_types = Fixtures.make_registries().layer_types
    _window.watch(_registry)
    _host.add_child(_window)

    _refused.clear()
    SaProblems.attach_sink(
        func(line: String, kind: SaProblems.Kind) -> void:
            if kind == SaProblems.Kind.REFUSAL:
                _refused.append(line)
    )


func after_each() -> void:
    # A pick is remembered for the next filter, and no suite leaves it for another.
    SaSettings.filter_way = "bake"
    SaProblems.detach_sink()
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


## Opens the filter of *key* on the active layer through the Filter menu's
## door and answers what the dialog says it is.
func _open(key: StringName) -> Dictionary:
    assert_true(_registry.invoke(key), "The Filter menu's door opens %s" % key)
    return _window.describe()


## An adjustment layer holding Hue/Saturation/Lightness, made active.
func _adjustment() -> SaLayer:
    var values := _registry.get_filter(_hsl_key).parameters()
    var made := SaFilterConversion.new(_doc).add_holding(_hsl_key, values, _window.layer_types, "Hue")
    assert_not_null(made, "The adjustment layer is made")
    _doc.set_active_layer(made)
    return made


func _texel() -> Color:
    return Bench.texel(_paint.get_field(Vector2i.ZERO), AT)


func test_a_paint_layer_opens_on_bake_with_nothing_said() -> void:
    var said := _open(_blur_key)
    assert_true(said["can_bake"], "A paint layer takes the bake")
    assert_eq(said["way"], &"bake", "and the toggle opens on it")
    assert_eq(said["hidden_note"], "", "with no line under the preview")
    for way: StringName in SaFilterDialogWindow.WAYS:
        assert_eq(SaFilterApply.way_refusal(_paint, way), "", "The helper refuses it no %s" % way)


func test_an_adjustment_layer_dims_bake_and_opens_on_attach() -> void:
    var adjustment := _adjustment()
    var why := SaFilterApply.way_refusal(adjustment, &"bake")
    assert_eq(why, STORES % adjustment.name, "The helper says the layer stores no paint")
    var said := _open(_blur_key)
    assert_false(said["can_bake"], "Box Blur on an adjustment layer opens with Bake dimmed")
    assert_eq(said["dimmed"].get(&"bake", ""), why, "its tooltip reading why")
    assert_eq(said["way"], &"attach", "and the toggle on Attach")
    assert_true(said["can_attach"], "which is open")
    var steps := _doc.history.step_count()
    var records := adjustment.filters.size()
    _window.apply_filter()
    assert_eq(_doc.history.step_count(), steps + 1, "Apply is one step")
    assert_eq(adjustment.filters.size(), records + 1, "which puts the blur on the adjustment layer")
    assert_true(adjustment.chunks.is_empty(), "and no paint into it")


func test_a_locked_layer_dims_bake_with_the_unlock_sentence() -> void:
    _paint.is_locked = true
    assert_eq(SaFilterApply.way_refusal(_paint, &"bake"), LOCKED, "The helper says the layer is locked")
    assert_eq(SaFilterApply.way_refusal(_paint, &"attach"), "", "and refuses it no Attach")
    var said := _open(_blur_key)
    assert_false(said["can_bake"], "A locked layer dims Bake")
    assert_eq(said["dimmed"].get(&"bake", ""), LOCKED, "with the unlock sentence")
    assert_eq(said["way"], &"attach", "and the toggle opens on Attach")
    var picked := SaFilterDialogWindow.capture(Engine.get_main_loop() as SceneTree, {"way": "bake"})
    assert_true(picked.contains("dimmed"), "A hand cannot pick Bake: %s" % picked)
    var before := _texel()
    _window.apply_filter()
    assert_eq(_paint.filters.size(), 1, "Attach hangs the blur on the locked layer, as it did before")
    assert_almost_eq(_texel().b, before.b, 1.0e-6, "and writes no pixel")


## A group bakes into the paint layers under it, so Bake is
## dimmed on one only when none of them takes the filter, here the one paint
## layer locked, and the sentence says the group holds nothing to write.
func test_a_group_dims_bake_with_the_group_sentence_and_offers_attach() -> void:
    var group := SaLayerOps.new(_doc).group_active()
    _doc.set_active_layer(group)
    assert_eq(SaFilterApply.way_refusal(group, &"bake"), "", "A group holding a paint layer takes the bake")
    _paint.is_locked = true
    var nothing := "'%s' holds no layer the filter can write, so there is nothing to bake." % group.name
    assert_eq(SaFilterApply.way_refusal(group, &"bake"), nothing, "and one whose layers are locked says why it does not")
    var said := _open(_blur_key)
    assert_false(said["can_bake"], "That group dims Bake")
    assert_eq(said["dimmed"].get(&"bake", ""), nothing, "with the group's sentence")
    assert_true(said["can_attach"], "and offers Attach")
    assert_eq(said["way"], &"attach", "which the toggle opens on")
    _window.apply_filter()
    assert_eq(group.filters.size(), 1, "Apply hangs the blur on the group")


func test_a_hidden_layer_bakes_and_says_the_canvas_will_not_show_it() -> void:
    _paint.visible = false
    var said := _open(_blur_key)
    assert_true(said["can_bake"], "A hidden layer still takes the bake")
    assert_eq(said["way"], &"bake", "and the toggle opens on it")
    assert_eq(said["hidden_note"], HIDDEN, "with the line saying the canvas will not show it")
    var note := _window.dialog.preview_control.find_child("HiddenNote", false, false) as Label
    assert_not_null(note, "under the preview")
    _window.cancel_filter()
    _paint.visible = true
    var group := SaLayerOps.new(_doc).group_active()
    group.visible = false
    _doc.set_active_layer(_paint)
    assert_eq(_open(_blur_key)["hidden_note"], HIDDEN, "A layer inside a hidden group gets the line too")
    _window.cancel_filter()
    group.visible = true
    assert_eq(_open(_blur_key)["hidden_note"], "", "and a layer the canvas draws does not")


func test_every_write_past_the_dialog_refuses_a_locked_layer_and_says_why() -> void:
    _paint.is_locked = true
    var before := _texel()
    var steps := _doc.history.step_count()
    _open(_blur_key)
    var gather := _window.context.point as SaNeighbourhoodPass
    assert_not_null(gather, "The blur's run recorded a neighbourhood pass")
    assert_false(SaFilterOps.one_shot(_window.context, _window.filter), "The blur's one-shot writes nothing")
    var kernel := _window.context.kernel(gather.shader)
    assert_false(SaFilterApply.apply_neighbourhood(_doc, _paint, gather, kernel, "Box blur"), "nor its walk")
    _window.cancel_filter()
    _open(_hsl_key)
    var point := _window.context.point
    assert_false(SaFilterOps.one_shot(_window.context, _window.filter), "The colour filter's one-shot writes nothing")
    var walk := _window.context.kernel(point.shader)
    assert_false(SaFilterApply.apply_point(_doc, _paint, point, walk, "Hue"), "nor its walk")
    assert_eq(_refused.size(), 4, "Each of the four says so: %s" % [_refused])
    for line in _refused:
        assert_true(line.ends_with(LOCKED), "with the unlock sentence: %s" % line)
    assert_eq(_doc.history.step_count(), steps, "No step was made")
    assert_almost_eq(_texel().b, before.b, 1.0e-6, "and no pixel written")


func test_a_one_shot_on_an_adjustment_layer_allocates_nothing_and_says_why() -> void:
    var adjustment := _adjustment()
    var steps := _doc.history.step_count()
    _open(_blur_key)
    assert_false(SaFilterOps.one_shot(_window.context, _window.filter), "The blur's one-shot writes nothing")
    assert_true(adjustment.chunks.is_empty(), "and allocates no chunk on the adjustment layer")
    assert_eq(_doc.history.step_count(), steps, "with no step")
    assert_eq(_refused.size(), 1, "and one line")
    assert_true(_refused[0].ends_with(STORES % adjustment.name), "saying the layer stores no paint: %s" % [_refused])


func test_a_filter_that_cannot_be_attached_over_a_locked_layer_greys_apply_out() -> void:
    _paint.is_locked = true
    var said := _open(_broken_key)
    assert_false(said["can_bake"], "Bake is dimmed by the lock")
    assert_false(said["can_attach"], "Attach by the filter's problem")
    assert_false(said["can_layer"], "and Layer by it as well")
    assert_true(_window.dialog.apply_button.disabled, "so Apply has no way to take and is greyed out")
    _paint.is_locked = false
    _window.cancel_filter()
    said = _open(_broken_key)
    assert_true(said["can_bake"], "Unlocked, the same filter bakes")
    assert_eq(said["way"], &"bake", "on the toggle's first stop")
    assert_false(_window.dialog.apply_button.disabled, "with Apply live")
