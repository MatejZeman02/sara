## Invert, Desaturate and Pixelate in the Filter menu.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The Filter menu has the everyday one-click adjustments: Invert and
## Desaturate need not be reached through Hue/Saturation or Levels by hand, and
## the Pixelate section is not empty. The menu lists Invert and Desaturate under Colour and Pixelate under
## Pixelate, each opens a dialog with a preview and applies through Bake,
## Attach and Layer, each of which undoes and redoes. Invert twice returns the
## layer, Desaturate leaves equal channels and equals Hue/Saturation at
## Saturation nought texel for texel, and Pixelate at 8 makes eight pixel
## blocks that line up across a chunk border.
##
## The painting is two chunks across, the grey background hidden, and one
## layer whose every texel is a colour of its own: red runs with the column,
## green with the row, so a block that took the wrong texel shows it.
extends "res://tests/test_framework.gd"

const Teardown := preload("res://tests/fixtures/teardown.gd")
const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")
const Fixtures = preload("res://tests/fixtures.gd")
const BaseModule = preload("res://modules/sara-base-modules/base/module.gd")
const InvertFilter = preload("res://modules/sara-base-modules/base/usual/invert_filter.gd")
const DesaturateFilter = preload("res://modules/sara-base-modules/base/usual/desaturate_filter.gd")
const PixelateFilter = preload("res://modules/sara-base-modules/base/usual/pixelate_filter.gd")
const HueSaturationLightnessFilter = preload("res://modules/sara-base-modules/base/filters/hue_saturation_lightness_filter.gd")

const REQUIRES_GPU := true

const OWNER: StringName = &"sara-base-modules"
const SIZE := Vector2i(2 * SaChunk.SIZE, SaChunk.SIZE)
const LEFT := Vector2i(0, 0)
const RIGHT := Vector2i(1, 0)
## What a float document carries through one invert and back, which is the
## rounding of two subtractions.
const ROUND_TRIP := 1.0e-5

var _easel: SaEasel = null
var _doc: SaDocument = null
var _layer: SaLayer = null
var _canvas: SaCanvas = null
var _window: SaFilterDialogWindow = null
var _host: Node = null
var _registry: SaFilterRegistry = null
var _keys: Dictionary = {}
var _was_embedding: bool = false


func before_each() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    if tree != null:
        _was_embedding = tree.root.gui_embed_subwindows
        tree.root.gui_embed_subwindows = true
    _host = Node.new()
    _host.name = "S63TestHost"
    EventBus.add_child(_host)
    _open(null)


func after_each() -> void:
    # A pick is remembered for the next filter, and no suite leaves it for another.
    SaSettings.filter_way = "bake"
    _close()
    if _host != null:
        _host.free()
        _host = null
    var tree := Engine.get_main_loop() as SceneTree
    if tree != null:
        tree.root.gui_embed_subwindows = _was_embedding


## An easel of two chunks stored in *space*, the bench's float sRGB one for
## null, with the four filters this suite reads registered as the base module
## registers them, and a dialog window watching them.
func _open(space: SaColorSpace) -> void:
    _close()
    if space == null:
        _easel = Bench.easel(SIZE)
    else:
        _easel = SaEasel.create_default(SIZE, null, space)
        _easel.compositor.set_registry(Fixtures.make_registries().blend_modes)
        _easel.compositor.filter_chain.registry = SaFilterRegistry.new()
    _doc = _easel.document
    (_doc.get_node("Background") as SaLayer).visible = false
    _layer = _doc.get_node("Layer 1") as SaLayer
    _doc.set_active_layer(_layer)
    _registry = _easel.compositor.filter_chain.registry
    _keys.clear()
    for filter: SaFilter in [
        InvertFilter.new(), DesaturateFilter.new(), PixelateFilter.new(), HueSaturationLightnessFilter.new()
    ]:
        _registry.register(filter, OWNER)
        _keys[filter.title()] = SaFilterRegistry.key_for(OWNER, filter)
    _canvas = SaCanvas.new()
    _canvas.easel = _easel
    _window = SaFilterDialogWindow.new()
    _window.target_canvas = _canvas
    _window.layer_types = Fixtures.make_registries().layer_types
    _window.watch(_registry)
    _host.add_child(_window)


func _close() -> void:
    Teardown.free_nodes([_window, _canvas, _easel])
    _window = null
    _canvas = null
    _easel = null
    _doc = null
    _layer = null
    _registry = null


## The colour the painting holds at the document pixel *at*: red with the
## column, green with the row, blue in a short cycle of both, and alpha in
## four steps when *soft*, else opaque.
static func _pattern(at: Vector2i, soft: bool) -> Color:
    var blue := float((at.x * 7 + at.y * 13) % 17) / 16.0
    var alpha := 0.25 + 0.25 * float((at.x + at.y) % 4) if soft else 1.0
    return Color(float(at.x) / SIZE.x, float(at.y) / SIZE.y, blue, alpha)


## Writes [method _pattern] into both chunks of the layer, as floats, and
## leaves the history empty so the first step a case takes is step one.
func _paint(soft: bool) -> void:
    for grid_pos: Vector2i in [LEFT, RIGHT]:
        var texture := _layer.get_or_create_chunk(grid_pos).field(SaFieldSpec.ALBEDO)
        assert_eq(texture.format, RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT, "The bench document is F32")
        var values := PackedFloat32Array()
        values.resize(texture.size.x * texture.size.y * 4)
        for y in texture.size.y:
            for x in texture.size.x:
                var colour := _pattern(grid_pos * texture.size + Vector2i(x, y), soft)
                var i := (y * texture.size.x + x) * 4
                values[i] = colour.r
                values[i + 1] = colour.g
                values[i + 2] = colour.b
                values[i + 3] = colour.a
        GlobalShaderCompiler.get_rd().texture_update(texture.rid, 0, values.to_byte_array())
    _doc.history.reset()
    _doc.undo_redo.clear_history()


## Every texel of the layer by its document pixel, read back chunk by chunk.
func _texels() -> Dictionary:
    var out := {}
    var rd := GlobalShaderCompiler.get_rd()
    for grid_pos: Vector2i in _layer.chunks.keys():
        var texture := _layer.get_field(grid_pos)
        var bytes := rd.texture_get_data(texture.rid, 0)
        for y in texture.size.y:
            for x in texture.size.x:
                out[grid_pos * texture.size + Vector2i(x, y)] = SaFieldSpec.decode_texel(
                    bytes, texture.format, y * texture.size.x + x
                )
    return out


## The composited output by its document pixel, after a full composite.
func _output() -> Callable:
    _doc.invalidate_chunks([LEFT, RIGHT])
    Bench.composite(_easel)
    var texture := _easel.output
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    return func(at: Vector2i) -> Color: return SaFieldSpec.decode_texel(bytes, texture.format, at.y * texture.size.x + at.x)


static func _apart(a: Color, b: Color) -> float:
    return maxf(maxf(absf(a.r - b.r), absf(a.g - b.g)), maxf(absf(a.b - b.b), absf(a.a - b.a)))


## The worst channel apart between two readings of the layer, with where.
static func _worst(a: Dictionary, b: Dictionary) -> Array:
    var worst := 0.0
    var where := Vector2i(-1, -1)
    for at: Vector2i in a:
        var apart := _apart(a[at], b.get(at, Color(INF, INF, INF, INF)))
        if apart > worst:
            worst = apart
            where = at
    return [worst, where]


## *title* written into the layer once, through the dialog's Bake, as the menu
## would: the door, the defaults the dialog opens on, Apply.
func _bake(title: String) -> void:
    # The way a hand last picked is where a window opens, so Bake is put back.
    SaSettings.filter_way = "bake"
    assert_true(_registry.invoke(_keys[title]), "The Filter menu's door opens %s" % title)
    assert_eq(_window.way(), &"bake", "on Bake, where the dialog opens")
    _window.apply_filter()


## The document pixel the block of *block* pixels that holds *at* takes its
## colour from: its centre, the blocks laid from the document's corner, or the
## nearest pixel inside the document to a centre past its edge.
static func _centre(at: Vector2i, block: int) -> Vector2i:
    var start := Vector2i(floori(at.x / float(block)), floori(at.y / float(block))) * block
    var centre := start + Vector2i(floori(block / 2.0), floori(block / 2.0))
    return centre.clamp(Vector2i.ZERO, SIZE - Vector2i.ONE)


func test_the_filter_menu_lists_invert_and_desaturate_under_colour_and_pixelate_under_pixelate() -> void:
    var registries := SaRegistries.new()
    registries.build_context(func() -> Variant: return null, func() -> Array: return [])
    registries.register_builtins()
    SaAppCommands.register_all(registries, func(_docker_id: StringName) -> void: pass)
    var mod := BaseModule.new()
    mod.register(registries.context.for_module(mod.get_id()))
    var colour: Array[String] = []
    var pixelate: Array[String] = []
    for key: StringName in registries.filters.list_keys():
        var title := registries.filters.get_filter(key).title()
        match registries.filters.section_of(key):
            &"color":
                colour.append(title)
            &"pixelate":
                pixelate.append(title)
    var listed: Array[String] = [
        "Hue/Saturation/Lightness",
        "Colour Balance",
        "Colour Lookup",
        "Gradient Map",
        "White Point",
        "Red-eye Removal",
        "Invert",
        "Desaturate",
        "LUT",
    ]
    assert_eq(
        colour,
        listed,
        "Colour lists Invert and Desaturate after the adjustments set by hand, and F7's LUT, the last to join, after them"
    )
    assert_eq(pixelate, ["Pixelate"] as Array[String], "and Pixelate is the Pixelate section's first filter")
    for title: String in ["Invert", "Desaturate", "Pixelate"]:
        var key := SaFilterRegistry.key_for(mod.get_id(), _named(registries.filters, title))
        assert_false(registries.filters.get_filter(key).sentence().is_empty(), "%s says what it does" % title)
        assert_true(registries.filters.get_filter(key).chord().is_empty(), "and %s ships no chord" % title)
    mod.unregister(registries.context.for_module(mod.get_id()))


static func _named(filters: SaFilterRegistry, title: String) -> SaFilter:
    for key: StringName in filters.list_keys():
        if filters.get_filter(key).title() == title:
            return filters.get_filter(key)
    return null


func test_each_opens_a_dialog_with_a_preview_and_offers_all_three_ways() -> void:
    _paint(true)
    for title: String in ["Invert", "Desaturate", "Pixelate"]:
        assert_true(_registry.invoke(_keys[title]), "The door opens %s" % title)
        assert_true(_window.visible, "in the dialog")
        assert_eq(_window.filter.title(), title, "named for it")
        assert_not_null(_window.dialog.preview_control, "with the picture of the result")
        assert_not_null(_window.dialog.canvas_box, "and the Preview on canvas switch")
        assert_true(_window.ran_clean, "whose run came back clean")
        assert_true(_window.describe()["on_canvas"], "and is drawn on the canvas")
        for way: StringName in SaFilterDialogWindow.WAYS:
            assert_false(_window.way_toggle.dimmed.has(way), "%s offers %s" % [title, way])
        _window.cancel_filter()


func test_each_bakes_attaches_and_layers_and_each_undoes_and_redoes() -> void:
    _paint(true)
    var painted := _texels()
    var layers := SaLayerOps.new(_doc).layers().size()
    for title: String in ["Invert", "Desaturate", "Pixelate"]:
        var key: StringName = _keys[title]
        var filed: StringName = _keys["Hue/Saturation/Lightness"] if title == "Desaturate" else key

        _bake(title)
        var baked := _texels()
        assert_true(_worst(painted, baked)[0] > 0.01, "%s on Bake writes the layer" % title)
        assert_true(_layer.filters.is_empty(), "and attaches nothing")
        _doc.undo_redo.undo()
        assert_eq(_worst(painted, _texels())[0], 0.0, "Undo takes %s's Bake back" % title)
        _doc.undo_redo.redo()
        assert_eq(_worst(baked, _texels())[0], 0.0, "and Redo writes it again")
        _doc.undo_redo.undo()

        _registry.invoke(key)
        assert_true(_window.way_toggle.pick(&"attach"), "Attach takes the pick")
        _window.apply_filter()
        assert_eq(_layer.filters.size(), 1, "%s on Attach puts one record on the layer" % title)
        assert_eq(_layer.filters[0].key, filed, "filed under %s" % filed)
        assert_eq(_worst(painted, _texels())[0], 0.0, "and writes no paint")
        _doc.undo_redo.undo()
        assert_true(_layer.filters.is_empty(), "Undo takes the record off")
        _doc.undo_redo.redo()
        assert_eq(_layer.filters.size(), 1, "and Redo puts it back")
        _doc.undo_redo.undo()

        _registry.invoke(key)
        assert_true(_window.way_toggle.pick(&"layer"), "Layer takes the pick")
        _window.apply_filter()
        var added := _doc.active_layer
        assert_eq(SaLayerOps.new(_doc).layers().size(), layers + 1, "%s on Layer adds one layer" % title)
        assert_true(added.is_adjustment(), "an adjustment layer")
        assert_eq(added.filters.size(), 1, "holding one record")
        assert_eq(added.filters[0].key, filed, "filed under %s" % filed)
        assert_eq(String(added.name), title, "and named for %s, the filter picked" % title)
        _doc.undo_redo.undo()
        assert_eq(SaLayerOps.new(_doc).layers().size(), layers, "Undo takes the layer away")
        _doc.undo_redo.redo()
        assert_eq(SaLayerOps.new(_doc).layers().size(), layers + 1, "and Redo puts it back")
        _doc.undo_redo.undo()
        _doc.set_active_layer(_layer)
        assert_eq(_worst(painted, _texels())[0], 0.0, "and the layer is as painted after %s" % title)


func test_invert_twice_returns_the_layer() -> void:
    _paint(true)
    var painted := _texels()
    _bake("Invert")
    var once := _texels()
    var turned := 0.0
    for at: Vector2i in painted:
        var was: Color = painted[at]
        var now: Color = once[at]
        turned = maxf(turned, _apart(now, Color(1.0 - was.r, 1.0 - was.g, 1.0 - was.b, was.a)))
    assert_true(turned <= ROUND_TRIP, "One invert writes one minus every channel and keeps alpha, worst %s" % turned)
    _bake("Invert")
    var worst := _worst(painted, _texels())
    assert_true(worst[0] <= ROUND_TRIP, "and a second returns the layer, worst %s at %s" % worst)


func test_invert_on_an_oklab_document_shows_the_opposite_colour() -> void:
    _open(SaColorSpace.oklab())
    var shown := Color(0.9, 0.6, 0.1, 0.5)
    _layer.fill(_doc.color_space.from_display(shown))
    _doc.history.reset()
    _doc.undo_redo.clear_history()
    _bake("Invert")
    var texels := _texels()
    var now: Color = _doc.color_space.to_display(texels[Vector2i(300, 100)])
    var wanted := Color(1.0 - shown.r, 1.0 - shown.g, 1.0 - shown.b, shown.a)
    assert_true(_apart(now, wanted) <= 2.0e-3, "An Oklab layer inverts to the opposite colour on display, %s" % now)
    _bake("Invert")
    now = _doc.color_space.to_display(_texels()[Vector2i(300, 100)])
    assert_true(_apart(now, shown) <= 2.0e-3, "and a second invert returns it, %s" % now)


func test_desaturate_leaves_equal_channels_and_is_hue_saturation_at_nought() -> void:
    _paint(true)
    var painted := _texels()
    _bake("Desaturate")
    var desaturated := _texels()
    var spread := 0.0
    var alpha := 0.0
    for at: Vector2i in desaturated:
        var shown: Color = _doc.color_space.to_display(desaturated[at])
        spread = maxf(spread, maxf(absf(shown.r - shown.g), maxf(absf(shown.g - shown.b), absf(shown.r - shown.b))))
        alpha = maxf(alpha, absf(desaturated[at].a - painted[at].a))
    assert_true(spread <= 1.0e-4, "Desaturate leaves three equal channels on display, worst %s" % spread)
    assert_eq(alpha, 0.0, "and every alpha where it was")
    _doc.undo_redo.undo()

    var hue_saturation := _registry.get_filter(_keys["Hue/Saturation/Lightness"])
    var ctx := SaFilterContext.new(_doc, _layer, OWNER, hue_saturation.title())
    hue_saturation.set_parameters(SaDesaturateFilter.FILED)
    assert_true(SaFilterApply.call_run(hue_saturation, ctx), "Hue/Saturation at Saturation nought runs")
    assert_true(SaFilterApply.apply(ctx, hue_saturation.title()), "and applies")
    var worst := _worst(desaturated, _texels())
    assert_eq(worst[0], 0.0, "and equals Desaturate texel for texel, worst %s at %s" % worst)


func test_pixelate_at_8_makes_blocks_that_line_up_across_a_chunk_border() -> void:
    _paint(false)
    var painted := _texels()
    _registry.invoke(_keys["Pixelate"])
    assert_eq(float(_window.filter.parameter(&"block_size")), 8.0, "The dialog opens at a block of 8")
    _window.apply_filter()
    var baked := _texels()
    _assert_blocks(painted, baked, 8, "Baked at 8")
    var left: Color = baked[Vector2i(SaChunk.SIZE - 1, 3)]
    var right: Color = baked[Vector2i(SaChunk.SIZE, 3)]
    assert_true(_apart(left, right) > 0.0, "and the chunk border falls between two blocks, as 8 divides 256")
    _doc.undo_redo.undo()

    var pixelate := _registry.get_filter(_keys["Pixelate"])
    pixelate.set_parameters({"block_size": 8})
    SaFilterOps.new(_doc).attach(_layer, _keys["Pixelate"], pixelate.parameters())
    var output := _output()
    var shown := {}
    for at: Vector2i in painted:
        shown[at] = output.call(at)
    _assert_blocks(painted, shown, 8, "Attached at 8")


## A block that 256 does not divide straddles the border, 252 to 263 at 12,
## and is one block on both sides of it.
func test_a_block_across_the_chunk_border_is_one_block_on_both_sides() -> void:
    _paint(false)
    var painted := _texels()
    var pixelate := _registry.get_filter(_keys["Pixelate"])
    pixelate.set_parameters({"block_size": 12})
    var ctx := SaFilterContext.new(_doc, _layer, OWNER, pixelate.title())
    assert_true(SaFilterApply.call_run(pixelate, ctx), "Pixelate at 12 runs")
    var gather := ctx.point as SaNeighbourhoodPass
    assert_eq(gather.radius if gather != null else -1, 12, "as a neighbourhood pass declaring a radius of the block size")
    assert_true(SaFilterApply.apply(ctx, pixelate.title()), "and applies")
    var after := _texels()
    _assert_blocks(painted, after, 12, "Baked at 12")
    var across: Color = after[Vector2i(252, 40)]
    for x in range(252, 264):
        assert_eq(_apart(after[Vector2i(x, 40)], across), 0.0, "Column %d is the straddling block's colour" % x)
    assert_eq(_apart(across, painted[Vector2i(258, 42)]), 0.0, "which is the right chunk's texel at the centre")


## Desaturate's record is
## Hue/Saturation's own, at Saturation nought, whether the dialog attaches it,
## the dialog adds a layer of it or the Add Adjustment Layer browser does, and a
## double click on it, which is `SaFilterEditWindow.open_in` on the record,
## opens Hue/Saturation where a painter can take it part of the way.
func test_desaturate_is_filed_as_hue_saturation_and_a_double_click_opens_it() -> void:
    _paint(true)
    var hue_key: StringName = _keys["Hue/Saturation/Lightness"]
    var noughts := {"hue": 0.0, "saturation": 0.0, "lightness": 0.0, "saturation_model": SaPointAdjust.SATURATION_IN_CAM16}
    var edit := SaFilterEditWindow.new()
    edit.watch(_registry)
    _host.add_child(edit)
    var browser := SaLayerKindBrowser.new()
    browser.browser.target_canvas = _canvas
    browser.browser.watch(_registry, SaCommandRegistry.new())
    _host.add_child(browser)

    _registry.invoke(_keys["Desaturate"])
    _window.way_toggle.pick(&"attach")
    _window.apply_filter()
    var attached: SaAttachedFilter = _layer.filters[0]
    assert_eq(attached.key, hue_key, "Desaturate attached is a Hue/Saturation record")
    assert_eq(attached.parameters, noughts, "at Saturation nought in its own units")
    _doc.undo_redo.undo()
    assert_true(_layer.filters.is_empty(), "Undo takes it off")
    _doc.undo_redo.redo()
    assert_true(SaFilterEditWindow.open_in(_host.get_tree(), _doc, _layer.filters[0]), "A double click on it opens a window")
    assert_true(edit.filter is SaHueSaturationLightnessFilter, "on Hue/Saturation/Lightness")
    assert_eq(float(edit.filter.parameter(&"saturation")), 0.0, "with its Saturation at nought")
    assert_true(edit.title.begins_with("Hue/Saturation/Lightness"), "and titled for it, %s" % edit.title)
    edit.cancel()
    _doc.undo_redo.undo()

    _registry.invoke(_keys["Desaturate"])
    _window.way_toggle.pick(&"layer")
    _window.apply_filter()
    var added := _doc.active_layer
    assert_eq(String(added.name), "Desaturate", "Desaturate on Layer adds a layer named Desaturate")
    assert_eq(added.filters[0].key, hue_key, "holding a Hue/Saturation record")
    assert_eq(added.filters[0].parameters, noughts, "at Saturation nought")
    _doc.undo_redo.undo()
    _doc.set_active_layer(_layer)

    browser.open_for(_doc, _window.layer_types.get_descriptor(SaBackdropLayer.TYPE_ID), _window.layer_types)
    browser.browser.pick(_keys["Desaturate"])
    browser.open_selected()
    var made := browser.made
    assert_not_null(made, "The Add Adjustment Layer browser adds Desaturate")
    if made != null:
        assert_eq(String(made.name), "Desaturate", "named Desaturate")
        assert_eq(made.filters[0].key, hue_key, "holding a Hue/Saturation record")
        assert_eq(made.filters[0].parameters, noughts, "at Saturation nought")
        assert_true(edit.visible and edit.record == made.filters[0], "and its settings open on that record")
        assert_true(edit.filter is SaHueSaturationLightnessFilter, "in Hue/Saturation/Lightness")
        edit.cancel()
        assert_true(made.get_parent() == null, "whose Cancel leaves no layer")

    for title: String in ["Invert", "Pixelate"]:
        var own := _registry.get_filter(_keys[title])
        var filed := own.filed_as(_keys[title])
        assert_eq(filed.key, _keys[title], "%s is filed under its own key" % title)
        assert_eq(filed.parameters, own.parameters(), "with its own values")
    browser.free()
    edit.free()


## Every texel of *after* is the texel of *painted* at the centre of its block.
func _assert_blocks(painted: Dictionary, after: Dictionary, block: int, what: String) -> void:
    var wrong := 0
    var first := ""
    for at: Vector2i in painted:
        var wanted: Color = painted[_centre(at, block)]
        if _apart(after[at], wanted) > 1.0e-6:
            wrong += 1
            if first.is_empty():
                first = " first at %s, %s for %s" % [at, after[at], wanted]
    assert_eq(wrong, 0, "%s, every texel is its block's centre%s" % [what, first])
