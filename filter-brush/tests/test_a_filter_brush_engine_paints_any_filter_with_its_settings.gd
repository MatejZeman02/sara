## The filter brush paints any
## filter with its settings.
##
## The filter brush engine takes any filter and its options. So one stroke of the Blur Filter preset across
## black and white stripes blurs the stripes under it and leaves those outside
## it alone, as one undo step, and a second stroke over the first blurs no
## further where the first had full coverage. The Kaleidoscope, which reads the
## whole layer for every pixel, is refused with a sentence, a preset saved with
## the Sharpen's parameters reads them back, and the Tool Options list every
## filter that can be a brush with the filter's own rows under the choice.
extends "res://tests/test_framework.gd"

## Chunks are real textures, so this needs a RenderingDevice.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const StateScript = preload("res://modules/sara-base-modules/filter-brush/state_filter_brush.gd")
const SettingsScript = preload("res://modules/sara-base-modules/filter-brush/filter_brush_settings.gd")
const PresetsScript = preload("res://modules/sara-base-modules/filter-brush/presets/filter_brush_presets.gd")
const StrokeScript = preload("res://modules/sara-base-modules/filter-brush/filter_brush_stroke.gd")
const ModuleScript = preload("res://modules/sara-base-modules/filter-brush/module.gd")
const KaleidoscopeScript = preload("res://modules/sara-base-modules/kaleidoscope/kaleidoscope.gd")

const OWNER: StringName = &"sara-base-modules"
const CANVAS := Vector2i(256, 256)
## The stripes' width, white then black.
const STRIPE: int = 4
## The stroke, along the middle row, and the brush's radius in pixels.
const FROM := Vector2(40.0, 128.0)
const TO := Vector2(216.0, 128.0)
const RADIUS: float = 20.0
## How far from the line the stroke's coverage is full: the preset's softness
## of 0.7 leaves the inner 6 pixels of the radius flat, and 5 keeps clear of
## the fade's first texel.
const FULL: float = 5.0
## How far from the line a second stroke's blur reads only paint the first
## blurred at full coverage: the flat 6 less the blur's reach of 4.
const CORE: float = 2.0

var _surface: SaSurface = null
var _tool: StateScript = null
var _filters: SaFilterRegistry = null
## The context the module would hand the brush, holding the registry above.
var _door: SaContext = null
var _heard: Array[String] = []
var _store: SaPresetStore = null


func before_each() -> void:
    # First, so the filters made below carry nothing into a painter's store.
    SaFilterPreset.root = SaDataRoot.path("test_filter_presets")
    _surface = Fixtures.make_surface(CANVAS)
    _filters = SaFilterRegistry.new()
    _filters.register(SaGaussianBlurFilter.new(), OWNER)
    _filters.register(SaSharpenFilter.new(), OWNER)
    _filters.register(SaDesaturateFilter.new(), OWNER)
    # The kernels' owner is the folder under modules, sara-base-modules, which
    # a filter registered by hand has to tell the loader.
    ModuleLoader.module_dirs[&"kaleidoscope"] = "res://modules/sara-base-modules/kaleidoscope"
    _filters.register(KaleidoscopeScript.new(), &"kaleidoscope")
    _tool = StateScript.new()
    _tool.surface = _surface
    _door = SaContext.new()
    _door.filters = _filters
    _tool.settings.context = _door
    _heard = []
    EventBus.paint_refused.connect(_hear)


func after_each() -> void:
    if EventBus.paint_refused.is_connected(_hear):
        EventBus.paint_refused.disconnect(_hear)
    if _store != null:
        for preset_name in _store.list_names():
            _store.delete_preset(preset_name)
        DirAccess.remove_absolute(_store.dir)
    _store = null
    _tool = null
    _filters = null
    _door = null
    Fixtures.teardown(_surface)
    _surface = null
    SaFilterPreset.root = SaFilterPreset.default_root()


func _hear(sentence: String) -> void:
    _heard.append(sentence)


static func _image_format(texture: SaTexture) -> Image.Format:
    return Image.FORMAT_RGBAH if texture.format == RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT else Image.FORMAT_RGBAF


## A fresh active layer whose chunk (0, 0) holds *painted*, a callable of a
## pixel answering its colour.
func _open(painted: Callable) -> SaLayer:
    var doc := _surface.get_document()
    var layer := SaLayerOps.new(doc).add(&"", null, 1.0)
    doc.active_layer = layer
    var chunk := layer.get_or_create_chunk(Vector2i.ZERO)
    var texture := chunk.albedo()
    var image := Image.create_empty(chunk.pixel_size(), chunk.pixel_size(), false, _image_format(texture))
    for y in chunk.pixel_size():
        for x in chunk.pixel_size():
            image.set_pixel(x, y, painted.call(x, y))
    GlobalShaderCompiler.get_rd().texture_update(texture.rid, 0, image.get_data())
    layer.mark_unresolved(Vector2i.ZERO)
    doc.invalidate_chunks([Vector2i.ZERO])
    return layer


func _stripes() -> SaLayer:
    return _open(func(x: int, _y: int) -> Color: return Color.WHITE if posmod(x, 2 * STRIPE) < STRIPE else Color.BLACK)


static func _read(layer: SaLayer) -> Image:
    var texture := (layer.chunks[Vector2i.ZERO] as SaChunk).albedo()
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    return Image.create_from_data(texture.size.x, texture.size.y, false, _image_format(texture), bytes)


## How far the centre of the pixel at (*x*, *y*) is from the stroke's line.
static func _apart(x: int, y: int) -> float:
    var at := Vector2(x, y) + Vector2(0.5, 0.5)
    var t := clampf((at - FROM).dot(TO - FROM) / (TO - FROM).length_squared(), 0.0, 1.0)
    return at.distance_to(FROM + (TO - FROM) * t)


## How many pixels farther than a pixel past the brush differ from *before*.
static func _changed_outside(before: Image, after: Image) -> int:
    var changed := 0
    for y in before.get_height():
        for x in before.get_width():
            if _apart(x, y) <= RADIUS + 1.0:
                continue
            if not before.get_pixel(x, y).is_equal_approx(after.get_pixel(x, y)):
                changed += 1
    return changed


## The largest difference of any channel between *a* and *b* over pixels whose
## distance from the stroke *keep* answers true for.
static func _widest(a: Image, b: Image, keep: Callable) -> float:
    var widest := 0.0
    for y in a.get_height():
        for x in a.get_width():
            if not keep.call(_apart(x, y)):
                continue
            var one := a.get_pixel(x, y)
            var two := b.get_pixel(x, y)
            widest = maxf(
                widest, maxf(maxf(absf(one.r - two.r), absf(one.g - two.g)), maxf(absf(one.b - two.b), absf(one.a - two.a)))
            )
    return widest


## The Blur Filter preset's recipe written onto the tool's settings, the way
## loading the preset writes it.
func _blur_preset() -> void:
    var recipe: Dictionary = {}
    for entry: Dictionary in PresetsScript.entries():
        if entry["name"] == "Blur Filter":
            recipe = entry
    var built := PresetsScript.build(SettingsScript, recipe)
    assert_not_null(built, "The Blur Filter recipe builds")
    SaPresetStore.copy_settings(built, _tool.settings)
    # In pixels on this canvas rather than the recipe's fraction of a 1080 one.
    _tool.settings.radius = RADIUS / _surface.get_document().brush_side


## The stripes with the brush's filter applied *times* over the whole of a
## second layer, through the Filter menu's own Apply, read back.
func _filtered(times: int) -> Image:
    var doc := _surface.get_document()
    var active := doc.active_layer
    var twin := _stripes()
    var evaluated := StrokeScript.evaluate(_door, _tool.settings.filter_key, _tool.settings.filter_parameters, doc, twin)
    for index in times:
        SaFilterApply.apply_neighbourhood(doc, twin, evaluated.recorded, evaluated.compute, evaluated.title)
    var read := _read(twin)
    doc.active_layer = active
    return read


func _stroke(from: Vector2, to: Vector2) -> void:
    _tool.begin_stroke(from)
    for step in range(1, 21):
        _tool.add_sample(from.lerp(to, step / 20.0))
        if step % 5 == 0:
            _tool.tick(0.016)
    _tool.end_stroke()


func test_one_stroke_blurs_the_stripes_under_it_and_nothing_else_as_one_step() -> void:
    var layer := _stripes()
    var doc := _surface.get_document()
    _blur_preset()
    assert_eq(_tool.settings.filter_key, "sara-base-modules.gaussian_blur", "The preset paints the Gaussian Blur")
    var expected := _filtered(1)
    var before := _read(layer)
    var at := doc.history.position()
    _stroke(FROM, TO)
    assert_eq(_heard, [] as Array[String], "Nothing was refused")
    var after := _read(layer)
    var low := 1.0
    var high := 0.0
    for x in range(80, 176):
        low = minf(low, after.get_pixel(x, 128).r)
        high = maxf(high, after.get_pixel(x, 128).r)
    assert_true(high - low < 0.7, "The stripes under the stroke are blurred, their swing %f of the 1 they had" % (high - low))
    var full := func(apart: float) -> bool: return apart < FULL
    assert_almost_eq(_widest(expected, after, full), 0.0, 1e-5, "Under full coverage, exactly the blur applied once")
    assert_eq(_changed_outside(before, after), 0, "No pixel outside the brush moves")
    assert_almost_eq(after.get_pixel(18, 60).r, 1.0, 1e-6, "A white stripe far from the stroke stays white")
    assert_eq(doc.history.position(), at + 1, "The stroke is one history step")
    assert_true(doc.undo(), "One undo")
    assert_almost_eq(_widest(before, _read(layer), func(_d: float) -> bool: return true), 0.0, 1e-6, "Takes every pixel back")
    assert_true(doc.redo(), "And a redo")
    assert_almost_eq(_widest(after, _read(layer), func(_d: float) -> bool: return true), 0.0, 1e-6, "Puts it back")


func test_a_dab_over_a_dab_filters_once_and_a_second_stroke_once_more() -> void:
    var layer := _stripes()
    var full := func(apart: float) -> bool: return apart < FULL
    _blur_preset()
    # There and back in one stroke, so every pixel of it is under twenty
    # samples' capsules and the line is crossed twice over.
    _tool.begin_stroke(FROM)
    for step in range(1, 41):
        _tool.add_sample(FROM.lerp(TO, 1.0 - absf(step / 20.0 - 1.0)))
        if step % 5 == 0:
            _tool.tick(0.016)
    _tool.end_stroke()
    var once := _read(layer)
    assert_almost_eq(_widest(_filtered(1), once, full), 0.0, 1e-5, "A stroke over itself blurs once where its coverage is full")
    _stroke(FROM, TO)
    var twice := _read(layer)
    assert_true(_widest(once, twice, full) > 0.01, "A second stroke blurs again")
    var core := func(apart: float) -> bool: return apart < CORE
    assert_almost_eq(_widest(_filtered(2), twice, core), 0.0, 1e-5, "By one stroke's worth and no more, the blur applied twice")


func test_a_point_filter_paints_a_grey_band_through_the_same_door() -> void:
    var layer := _open(func(_x: int, y: int) -> Color: return Color(0.9, 0.2, 0.1, 1.0) if y < 200 else Color(0.1, 0.3, 0.9, 1.0))
    var before := _read(layer)
    _tool.settings.filter_key = "sara-base-modules.desaturate"
    _tool.settings.filter_parameters = {}
    _tool.settings.radius = RADIUS / _surface.get_document().brush_side
    _tool.settings.softness = 0.5
    _stroke(FROM, TO)
    var after := _read(layer)
    var grey := after.get_pixel(128, 128)
    assert_almost_eq(grey.r, grey.g, 0.01, "Under the stroke the colour is grey, red against green")
    assert_almost_eq(grey.g, grey.b, 0.01, "And green against blue")
    assert_eq(_changed_outside(before, after), 0, "Nothing outside the brush moves")


func test_the_kaleidoscope_is_refused_with_a_sentence() -> void:
    var layer := _stripes()
    var doc := _surface.get_document()
    _tool.settings.filter_key = "kaleidoscope.kaleidoscope"
    var before := _read(layer)
    var at := doc.history.position()
    var note := _tool.filter_note
    # The Kaleidoscope says it cannot be a brush, so
    # the sentence is that one, said before its pass is recorded.
    assert_true(note.contains("a brush cannot paint it"), "The Tool Options' note says why: %s" % note)
    _stroke(FROM, TO)
    assert_eq(_heard.size(), 1, "The press is refused once")
    assert_eq(_heard[0] if not _heard.is_empty() else "", note, "With the note's sentence")
    assert_false(_tool.is_drawing, "And opens no stroke")
    assert_eq(doc.history.position(), at, "So the history is where it was")
    assert_almost_eq(_widest(before, _read(layer), func(_d: float) -> bool: return true), 0.0, 1e-6, "And the layer too")
    _tool.settings.filter_key = "sara-base-modules.gaussian_blur"
    assert_eq(_tool.filter_note, "", "A filter the brush can paint has no note")


func test_a_preset_keeps_another_filters_parameters() -> void:
    _store = SaPresetStore.new()
    _store.dir = SaDataRoot.path("test_filter_brush_presets")
    var sharpen := {"kind": "unsharp_mask", "radius": 3.0, "amount": 150.0, "threshold": 5.0}
    var settings := SettingsScript.new()
    settings.filter_key = "sara-base-modules.sharpen"
    settings.filter_parameters = sharpen
    settings.radius = 0.03
    settings.softness = 0.25
    assert_eq(_store.save_preset("Brush Sharpen", settings), "Brush Sharpen", "The preset is saved")
    assert_eq(_store.engine_for("Brush Sharpen"), SettingsScript.PRESET_ENGINE, "Under the filter engine")
    var loaded := _store.load_preset("Brush Sharpen")
    assert_eq(loaded.get("filter_key"), "sara-base-modules.sharpen", "It reads back the filter")
    assert_eq(loaded.get("filter_parameters"), sharpen, "And its parameters")
    assert_true(_store.apply_preset("Brush Sharpen", _tool.settings), "It loads onto the brush")
    assert_eq(_tool.settings.filter_parameters, sharpen, "Which paints with them")
    assert_almost_eq(_tool.settings.softness, 0.25, 1e-6, "At the preset's softness")
    _tool.settings.filter_parameters["amount"] = 10.0
    assert_eq(loaded.get("filter_parameters")["amount"], 150.0, "A brush that moves a parameter leaves the preset alone")


func test_every_shipped_preset_paints_a_filter_the_brush_can_paint() -> void:
    _filters.register(SaAddNoiseFilter.new(), OWNER)
    var names: Array[String] = []
    for entry: Dictionary in PresetsScript.entries():
        names.append(entry["name"])
        var built := PresetsScript.build(SettingsScript, entry)
        assert_not_null(built, "%s builds" % entry["name"])
        if built == null:
            continue
        var evaluated := StrokeScript.evaluate(_door, built.filter_key, built.filter_parameters, _surface.get_document(), null)
        assert_eq(evaluated.refusal, "", "%s paints %s" % [entry["name"], built.filter_key])
    assert_eq(names, ["Blur Filter", "Sharpen Filter", "Desaturate Filter", "Grain Filter"], "The four the unit asked for")


func test_the_tool_options_choose_the_filter_from_the_registry_and_show_its_rows() -> void:
    var rows: Dictionary = {}
    for spec: SaOptionSpec in ModuleScript.options(_door):
        rows[spec.key] = spec
    var filter: SaOptionSpec = rows.get(&"filter_key", null)
    assert_not_null(filter, "A Filter row")
    var ids: Array = []
    var labels: Array = []
    for choice: Dictionary in filter.choices if filter != null else []:
        ids.append(choice["id"])
        labels.append(choice["label"])
    # Every filter that can be a brush, which is the
    # filter's own answer, so the Kaleidoscope is left off.
    assert_eq(ids.size(), _filters.list_keys().size() - 1, "Listing every filter the registry holds that can be a brush")
    assert_false(ids.has("kaleidoscope.kaleidoscope"), "And not the one that cannot")
    assert_true(labels.has("Gaussian Blur"), "Each by its title")
    # The rows are in Tool Options and not behind a button, which
    # `test_the_filter_brush_s_own_settings_are_in_tool_options.gd` reads.
    var own: SaOptionSpec = rows.get(&"filter_rows", null)
    assert_true(own != null and own.kind == SaOptionSpec.Kind.CUSTOM, "The filter's own rows")
    var note: SaOptionSpec = rows.get(&"filter_note", null)
    assert_true(note != null and note.kind == SaOptionSpec.Kind.CUSTOM, "And a row for the refusal's sentence")
    assert_true(note != null and note.shown_when.get("key") == &"filter_note", "Shown only while there is one")
    # A row takes its first child that is not a label for the control, so a bare
    # label was laid out a letter wide in the running app.
    var built: Control = note.build_control.call(note, func(_value: Variant) -> void: pass) if note != null else null
    assert_true(built != null and not built is Label, "The note's control is not a bare label")
    if built != null:
        note.bind_value.call(built, "A sentence.")
        var label := built.get_node_or_null("FilterNote") as Label
        assert_eq(label.text if label != null else "", "A sentence.", "And shows the sentence it is bound to")
        built.free()


## A full run of the suites ended on five pen reader threads left running when
## the settings held the module's own context: it holds the tool registry, which
## holds the settings through the descriptor, a cycle no reference count frees,
## and every registry of a booted module set stayed alive with it.
func test_a_registered_module_and_its_context_are_let_go_whole() -> void:
    var tools := SaToolRegistry.new()
    var watched: WeakRef = weakref(tools)
    var ctx := SaContext.create(
        tools, SaBlendModeRegistry.new(), SaCommandRegistry.new(), SaLayerTypeRegistry.new(), SaUIRegistry.new()
    )
    ctx.filters = _filters
    ctx.roles = SaRoleRegistry.new()
    var module: SaModule = ModuleScript.new()
    module.register(ctx.for_module(module.get_id()))
    assert_true(tools.has(ModuleScript.TOOL_ID), "The brush registered")
    module = null
    ctx = null
    tools = null
    assert_null(watched.get_ref(), "And the tool registry goes with the module and its context")
