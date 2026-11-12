## An effect applied, the layer copied, undone and pasted
## leaves both the original and the effect.
##
## A painter does an effect, then wants to keep both the effect and the
## original layer, so copies the layer, undoes and pastes. Each case paints a layer that crosses a
## chunk seam, opens a Filter menu filter through the registry's door and
## applies it with the dialog's Apply, runs Edit > Copy, undoes the way Ctrl+Z
## does, runs Edit > Paste, and reads every texel of both layers: the original
## back as it was painted, and the pasted one as the filter left it, within
## 1/255. A blur, Gaussian Blur, and a colour filter, Invert, each with no
## selection and with one, on a plain layer, on a layer carrying a height field
## and on a layer at double resolution.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")

## Two chunks side by side, so the blur reads across a seam.
const CANVAS := Vector2i(512, 256)
const TOLERANCE := 1.0 / 255.0
## Inside both chunks, its edges clear of the chunk borders.
const BOX := Rect2i(160, 48, 192, 128)
const MODULE := &"sara-base-modules"

var _surface: SaSurface = null
var _doc: SaDocument = null
var _commands: SaCommandRegistry = null
var _registry: SaFilterRegistry = null
var _window: SaFilterDialogWindow = null
var _canvas: SaCanvas = null
var _host: Node = null
var _embedding := false
var _shortcuts: SaShortcutCommands = null


func before_each() -> void:
    # Edit > Copy and Paste reach the clipboard the open documents share, the
    # run's owner's, which is made here when the run has none.
    SaTestFixtures.FrontDocuments.owner_in_the_run().clipboard.clear()
    var tree := Engine.get_main_loop() as SceneTree
    _embedding = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    _surface = Fixtures.make_surface(CANVAS)
    _surface.easel.compositor.set_registry(Fixtures.make_registries().blend_modes)
    _doc = _surface.easel.document
    _registry = SaFilterRegistry.new()
    _surface.easel.compositor.filter_chain.registry = _registry
    _registry.register(SaGaussianBlurFilter.new(), MODULE)
    _registry.register(SaInvertFilter.new(), MODULE)
    _canvas = SaCanvas.new()
    _canvas.easel = _surface.easel
    _host = Node.new()
    EventBus.add_child(_host)
    _window = SaFilterDialogWindow.new()
    _window.target_canvas = _canvas
    _window.layer_types = Fixtures.make_registries().layer_types
    _window.watch(_registry)
    _host.add_child(_window)
    var registries := Fixtures.make_registries(_surface)
    _commands = registries.commands
    _shortcuts = SaShortcutCommands.new(Callable(), func() -> SaCanvas: return _canvas, Callable(), null)
    _shortcuts.register_into(_commands)
    SaSettings.filter_way = "bake"


func after_each() -> void:
    _window.free()
    _canvas.free()
    _host.free()
    _shortcuts = null
    _commands = null
    _registry = null
    Fixtures.teardown(_surface)
    _surface = null
    _doc = null
    (Engine.get_main_loop() as SceneTree).root.gui_embed_subwindows = _embedding


## The painted picture at a document pixel: blocks of colour with hard edges
## for the blur to soften, half covered here and there, and clear elsewhere.
static func _picture_at(x: int, y: int) -> Color:
    if x < 24 or x >= CANVAS.x - 24 or y < 24 or y >= CANVAS.y - 24:
        return Color(0.0, 0.0, 0.0, 0.0)
    @warning_ignore("integer_division")
    var block := Vector2i(x / 16, y / 16)
    var alpha := 1.0 if (block.x + block.y) % 3 != 0 else 0.5
    return Color(0.15 * (block.x % 6), 0.3 * (block.y % 3), 0.9 - 0.2 * (block.x % 4), alpha)


static func _format(texture: SaTexture) -> Image.Format:
    match texture.format:
        RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT:
            return Image.FORMAT_RGBAH
        RenderingDevice.DATA_FORMAT_R16_SFLOAT:
            return Image.FORMAT_RH
        RenderingDevice.DATA_FORMAT_R32_SFLOAT:
            return Image.FORMAT_RF
    return Image.FORMAT_RGBAF


## A new active layer at *scale* holding the picture, the double resolution one
## as its nearest upscale, and with *height* a ridge field over both chunks.
func _paint(scale: float, height: bool) -> SaLayer:
    var layer := SaLayerOps.new(_doc).add(&"", null, scale)
    _doc.set_active_layer(layer)
    if height:
        SaHeightOps.new(_doc).gain(layer)
    var rd := GlobalShaderCompiler.get_rd()
    for gx: int in floori(float(CANVAS.x) / SaChunk.SIZE):
        var grid_pos := Vector2i(gx, 0)
        var chunk := layer.get_or_create_chunk(grid_pos)
        var texture := chunk.albedo()
        var image := Image.create_empty(SaChunk.SIZE, SaChunk.SIZE, false, _format(texture))
        for y in SaChunk.SIZE:
            for x in SaChunk.SIZE:
                image.set_pixel(x, y, _picture_at(gx * SaChunk.SIZE + x, y))
        if chunk.pixel_size() != SaChunk.SIZE:
            image.resize(chunk.pixel_size(), chunk.pixel_size(), Image.INTERPOLATE_NEAREST)
        rd.texture_update(texture.rid, 0, image.get_data())
        if height:
            var field := layer.get_or_create_field(grid_pos, SaFieldSpec.HEIGHT)
            var ridge := Image.create_empty(field.size.x, field.size.y, false, _format(field))
            for y in field.size.y:
                for x in field.size.x:
                    ridge.set_pixel(x, y, Color(1.5 + 0.01 * float((x + gx * field.size.x) % 97), 0.0, 0.0, 0.0))
            rd.texture_update(field.rid, 0, ridge.get_data())
        layer.mark_unresolved(grid_pos)
    _doc.invalidate_chunks(layer.chunks.keys())
    _doc.history.reset()
    _doc.undo_redo.clear_history()
    return layer


## Every field of every chunk of *layer* read back as an image, by grid
## position and then field id.
func _read(layer: SaLayer) -> Dictionary:
    var rd := GlobalShaderCompiler.get_rd()
    var out := {}
    for grid_pos: Vector2i in layer.chunks:
        var fields := {}
        var chunk: SaChunk = layer.chunks[grid_pos]
        for field_id: StringName in chunk.fields:
            var texture: SaTexture = chunk.fields[field_id]
            if texture == null:
                continue
            var bytes := rd.texture_get_data(texture.rid, 0)
            fields[field_id] = Image.create_from_data(texture.size.x, texture.size.y, false, _format(texture), bytes)
        out[grid_pos] = fields
    return out


## The largest difference between *got* and *want* over every texel of every
## field *want* holds. A texel outside *only*, a document rectangle, is wanted
## clear rather than as *want* has it, and a field or chunk *got* lacks reads
## as clear.
func _largest_difference(got: Dictionary, want: Dictionary, only: Rect2i = Rect2i()) -> float:
    var worst := 0.0
    for grid_pos: Vector2i in want:
        var wanted: Dictionary = want[grid_pos]
        var held: Dictionary = got.get(grid_pos, {})
        for field_id: StringName in wanted:
            var a: Image = wanted[field_id]
            var b: Image = held.get(field_id, null)
            var side := a.get_width()
            var step := float(SaChunk.SIZE) / side
            for y in a.get_height():
                for x in side:
                    var pixel := Vector2i(grid_pos.x * SaChunk.SIZE + floori(x * step), floori(y * step))
                    var expected := a.get_pixel(x, y)
                    if only.has_area() and not only.has_point(pixel):
                        expected = Color(0.0, 0.0, 0.0, 0.0)
                    var actual := b.get_pixel(x, y) if b != null else Color(0.0, 0.0, 0.0, 0.0)
                    worst = maxf(worst, _channel_gap(expected, actual))
    return worst


## The largest of the four channels' differences between *a* and *b*.
static func _channel_gap(a: Color, b: Color) -> float:
    return maxf(maxf(absf(a.r - b.r), absf(a.g - b.g)), maxf(absf(a.b - b.b), absf(a.a - b.a)))


## The round trip: paint, *filter* through the menu's door and Apply, Copy,
## undo, Paste, then both layers read against what they should hold.
func _round_trip(filter: SaFilter, scale: float, height: bool, selected: bool) -> void:
    var layer := _paint(scale, height)
    if selected:
        _doc.selection.select_rect(BOX)
    var painted := _read(layer)
    assert_true(_registry.invoke(SaFilterRegistry.key_for(MODULE, filter)), "the Filter menu's door opens %s" % filter.title())
    _window.run_filter()
    _window.apply_filter()
    var filtered := _read(layer)
    assert_true(_largest_difference(filtered, painted) > 0.05, "%s changed the layer" % filter.title())
    assert_eq(_doc.history.step_count(), 1, "the filter is one step")

    assert_true(_commands.execute(&"edit_copy"), "Edit > Copy ran")
    assert_true(_doc.undo(), "the filter is undone, as Ctrl+Z does")
    assert_true(_commands.execute(&"edit_paste"), "Edit > Paste ran")

    var pasted := _doc.active_layer
    assert_true(pasted != null and pasted != layer, "the paste made a layer of its own")
    if pasted == null or pasted == layer:
        return
    assert_almost_eq(pasted.resolution_scale, scale, 1.0e-6, "at the copied layer's resolution")
    assert_eq(pasted.carries_height(), height, "carrying height where the copy did")
    var original := _largest_difference(_read(layer), painted)
    assert_true(original < TOLERANCE, "the original reads as painted before %s, %f off" % [filter.title(), original])
    var effect := _largest_difference(_read(pasted), filtered, BOX if selected else Rect2i())
    assert_true(effect < TOLERANCE, "the pasted layer reads as %s left it, %f off" % [filter.title(), effect])


func test_a_blur_copied_undone_and_pasted_keeps_both() -> void:
    _round_trip(SaGaussianBlurFilter.new(), 1.0, false, false)


func test_a_colour_filter_copied_undone_and_pasted_keeps_both() -> void:
    _round_trip(SaInvertFilter.new(), 1.0, false, false)


func test_a_blur_under_a_selection_pastes_only_the_selected_part() -> void:
    _round_trip(SaGaussianBlurFilter.new(), 1.0, false, true)


func test_a_colour_filter_under_a_selection_pastes_only_the_selected_part() -> void:
    _round_trip(SaInvertFilter.new(), 1.0, false, true)


func test_a_blur_on_a_layer_with_height_keeps_both() -> void:
    _round_trip(SaGaussianBlurFilter.new(), 1.0, true, false)


func test_a_colour_filter_on_a_layer_with_height_keeps_both() -> void:
    _round_trip(SaInvertFilter.new(), 1.0, true, false)


func test_a_blur_on_a_double_resolution_layer_keeps_both() -> void:
    _round_trip(SaGaussianBlurFilter.new(), 2.0, false, false)


func test_a_colour_filter_on_a_double_resolution_layer_keeps_both() -> void:
    _round_trip(SaInvertFilter.new(), 2.0, false, false)
