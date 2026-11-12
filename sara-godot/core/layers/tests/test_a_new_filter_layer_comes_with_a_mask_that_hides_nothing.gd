## A new filter layer comes with a mask that hides nothing.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A painter on 2026-10-16: "creating a filter layer should always bring new
## (empty) mask on it, because that will be the most common use case for the
## filter layer." Every door that makes a new adjustment or effect layer is
## pressed here, `add_holding`, the kind browser for an effect layer, the
## Filter dialog's Layer way and Filter Again, and each layer is read with a
## mask of one wherever the canvas reaches, a picture no different from the
## same layer with no mask, one history step, and an undo that takes both.
##
## The canvas is two chunks wide, so a mask that held one chunk and not the
## other would be read at both. The running app is
## `scenarios/a-new-filter-layer-comes-with-a-mask-that-hides-nothing.json`.
extends "res://tests/test_framework.gd"

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")
const Fixtures = preload("res://tests/fixtures.gd")

const REQUIRES_GPU := true

const SIZE := Vector2i(512, 256)
const PAINT := Color(0.25, 0.5, 0.75, 1.0)
const BRIGHTER := {"widget": "brightness", "value": 30.0}
## Where the picture is read, one texel in each chunk and one at their seam.
const READ_AT: Array[Vector2i] = [Vector2i(40, 40), Vector2i(255, 128), Vector2i(400, 200)]

var _easel: SaEasel = null
var _doc: SaDocument = null
var _types: SaLayerTypeRegistry = null
var _registry: SaFilterRegistry = null
var _brightness: StringName = &""
var _paint: SaLayer = null
var _host: Node = null
var _was_embedding: bool = false


func before_each() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    _was_embedding = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    _host = Node.new()
    _host.name = "U168TestHost"
    EventBus.add_child(_host)
    _easel = Bench.easel(SIZE)
    _doc = _easel.document
    _registry = _easel.compositor.filter_chain.registry
    var filter := SaBrightnessContrastFilter.new()
    _brightness = SaFilterRegistry.key_for(&"sara-base-modules", filter)
    _registry.register(filter, &"sara-base-modules")
    _types = Fixtures.make_registries().layer_types
    _paint = _doc.get_node("Layer 1") as SaLayer
    _paint.get_or_create_chunk(Vector2i.ZERO).clear(PAINT)
    _paint.get_or_create_chunk(Vector2i(1, 0)).clear(PAINT)
    _doc.set_active_layer(_paint)
    _doc.history.reset()
    _doc.undo_redo.clear_history()
    SaProblems.announce = false


func after_each() -> void:
    SaSettings.filter_way = "bake"
    SaSettings.filter_affect_all = false
    SaProblems.announce = true
    SaFilterAgain.forget(_registry)
    _easel.free()
    _easel = null
    _doc = null
    _registry = null
    _types = null
    _paint = null
    _host.free()
    _host = null
    (Engine.get_main_loop() as SceneTree).root.gui_embed_subwindows = _was_embedding


func _steps() -> int:
    return _doc.undo_redo.get_history_count()


## Every texel of *mask* the canvas reaches, as the reader takes it: a chunk the
## mask holds read texel by texel, and a position it holds none at read as its
## rest. Answers the texels that are not one, as text, empty when there are none.
func _not_one(mask: SaMask) -> String:
    var found: PackedStringArray = []
    var cells := Vector2i(ceili(SIZE.x / float(SaLayer.CHUNK_SIZE)), ceili(SIZE.y / float(SaLayer.CHUNK_SIZE)))
    for y in cells.y:
        for x in cells.x:
            var grid_pos := Vector2i(x, y)
            var held := mask.texture_for(grid_pos)
            if held == null:
                if not is_equal_approx(mask.rest, 1.0):
                    found.append("%s rests at %s" % [grid_pos, mask.rest])
                continue
            var bytes := GlobalShaderCompiler.get_rd().texture_get_data(held.rid, 0)
            for at in held.size.x * held.size.y:
                var texel := SaFieldSpec.decode_texel(bytes, held.format, at)
                if not is_equal_approx(texel.r, 1.0):
                    found.append("%s texel %d holds %s" % [grid_pos, at, texel.r])
                    break
    return ", ".join(found)


## The composite at the points of `READ_AT`.
func _picture() -> Array[Color]:
    Bench.composite(_easel)
    var read: Array[Color] = []
    for at in READ_AT:
        read.append(Bench.texel(_easel.output, at))
    return read


## The checks every door shares: *made* carries an enabled mask of one
## everywhere, the picture is the one the same layer makes with no mask, the
## add was one step of *steps_before*, and one undo takes the layer and its mask
## while one redo brings both back.
func _carries_a_bare_mask(made: SaLayer, steps_before: int, door: String) -> void:
    assert_not_null(made, "%s makes a layer" % door)
    if made == null:
        return
    assert_true(made.is_adjustment() or made.is_effect(), "%s makes a filter layer" % door)
    var mask := made.mask
    assert_not_null(mask, "%s gives the layer a mask" % door)
    if mask == null:
        return
    assert_true(mask.enabled, "the mask is on")
    assert_eq(_not_one(mask), "", "and every texel of it the canvas reaches is 1.0")
    assert_eq(_steps(), steps_before + 1, "%s is one history step, the mask in it" % door)

    var masked := _picture()
    made.drop_mask()
    _doc.invalidate_all_allocated_chunks()
    var bare := _picture()
    for at in READ_AT.size():
        var said := "%s at %s: masked %s, without %s" % [door, READ_AT[at], masked[at], bare[at]]
        assert_true(masked[at].is_equal_approx(bare[at]), said)
    made.mask = mask
    _doc.invalidate_all_allocated_chunks()

    _doc.undo_redo.undo()
    assert_eq(_steps(), steps_before + 1, "the step stays to redo")
    assert_true(made.get_parent() != _doc, "One undo after %s leaves no layer" % door)
    var masks_left := 0
    for layer in SaLayerOps.new(_doc).layers():
        if layer.mask == mask:
            masks_left += 1
    assert_eq(masks_left, 0, "and its mask on no layer the document holds")
    _doc.undo_redo.redo()
    assert_eq(made.get_parent(), _doc, "One redo brings the layer back")
    assert_eq(made.mask, mask, "with the same mask")
    assert_eq(_not_one(made.mask), "", "still hiding nothing")


func test_add_holding_gives_an_adjustment_layer_a_mask_that_hides_nothing() -> void:
    var steps := _steps()
    var made := SaFilterConversion.new(_doc).add_holding(Bench.INVERT, {}, _types, "Invert")
    _carries_a_bare_mask(made, steps, "add_holding")


func test_the_kind_browser_gives_an_effect_layer_a_mask_that_hides_nothing() -> void:
    var browser := SaLayerKindBrowser.new()
    browser.browser.watch(_registry, SaCommandRegistry.new())
    var steps := _steps()
    browser.open_for(_doc, _types.get_descriptor(SaEffectLayer.TYPE_ID), _types)
    assert_true(browser.browser.pick(Bench.INVERT), "The browser offers the invert for an effect layer")
    browser.open_selected()
    var made := browser.made
    browser.free()
    assert_true(made != null and made.is_effect(), "The pick makes an effect layer")
    _carries_a_bare_mask(made, steps, "the kind browser's effect layer")


func test_the_kind_browser_gives_an_adjustment_layer_a_mask_that_hides_nothing() -> void:
    var browser := SaLayerKindBrowser.new()
    browser.browser.watch(_registry, SaCommandRegistry.new())
    var steps := _steps()
    browser.open_for(_doc, _types.get_descriptor(SaBackdropLayer.TYPE_ID), _types)
    assert_true(browser.browser.pick(Bench.INVERT), "The browser offers the invert for an adjustment layer")
    browser.open_selected()
    var made := browser.made
    browser.free()
    _carries_a_bare_mask(made, steps, "the kind browser's adjustment layer")


## The Filter dialog's Layer way, and Filter Again after it, each a new layer
## with its mask.
func test_the_dialog_s_layer_way_and_filter_again_give_the_mask() -> void:
    var canvas := SaCanvas.new()
    canvas.easel = _easel
    var window := SaFilterDialogWindow.new()
    window.target_canvas = canvas
    window.layer_types = _types
    window.watch(_registry)
    _host.add_child(window)
    var tree := Engine.get_main_loop() as SceneTree
    assert_true(_registry.invoke(_brightness), "The Filter menu's door opens Brightness/Contrast")
    SaFilterDialogWindow.capture(tree, BRIGHTER)
    SaFilterDialogWindow.capture(tree, {"way": "layer"})
    window.dialog.flush_rerun()
    var steps := _steps()
    window.apply_filter()
    var made := _doc.active_layer
    assert_true(made != _paint, "The Layer way makes a layer above the paint")
    _carries_a_bare_mask(made, steps, "the Filter dialog's Layer way")

    _doc.set_active_layer(_paint)
    steps = _steps()
    assert_true(SaFilterAgain.run(_doc, _registry, _types), "Filter Again runs the Layer way once more")
    var again := _doc.active_layer
    assert_true(again != made and again != _paint, "and makes a second layer")
    _carries_a_bare_mask(again, steps, "Filter Again")
    window.free()
    canvas.free()


## A layer made by converting an attached filter is not a new one and takes no
## mask, and a new layer whose mask hides nothing still goes back to records.
func test_a_conversion_takes_no_mask_and_a_bare_mask_converts_back() -> void:
    var record := SaFilterOps.new(_doc).attach(null, Bench.INVERT)
    var conversion := SaFilterConversion.new(_doc)
    var converted := conversion.to_layer(null, record, _types, "Invert")
    assert_not_null(converted, "The document's record becomes a layer")
    if converted != null:
        assert_null(converted.mask, "with no mask, since it is not a new one")
    var made := conversion.add_holding(Bench.INVERT, {}, _types, "Invert")
    _doc.move_child(made, _doc.get_child_count() - 1)
    assert_eq(conversion.record_refusal(made), "", "A mask that hides nothing refuses no way back")
    assert_true(conversion.to_record(made), "and the layer becomes a record")
    _doc.undo_redo.undo()
    assert_eq(made.get_parent(), _doc, "Undo brings the layer back")
    assert_not_null(made.mask, "with its mask")
