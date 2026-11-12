## The filter brush's own
## settings are in Tool Options, its strength and radius among them.
##
## The Tool Options carry the chosen filter's own rows under the Filter
## choice, so no separate filter dialog is needed. The Gaussian's radius is what the next stroke blurs by, a second
## filter chosen and the first chosen again finds the first one's values as
## they were left, and the Opacity row says it is the stroke's strength over
## the filter's result.
##
## The rows are built and bound by the spec's own factory and binder, and their
## write goes to the spec's property path on the settings, which is what the
## Tool Options docker's write does with a module's row.
extends "res://tests/test_framework.gd"

## Chunks are real textures, so this needs a RenderingDevice.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const StateScript = preload("res://modules/sara-base-modules/filter-brush/state_filter_brush.gd")
const RowsScript = preload("res://modules/sara-base-modules/filter-brush/filter_rows.gd")
const StrokeScript = preload("res://modules/sara-base-modules/filter-brush/filter_brush_stroke.gd")
const ModuleScript = preload("res://modules/sara-base-modules/filter-brush/module.gd")

const OWNER: StringName = &"sara-base-modules"
const BLUR := "sara-base-modules.gaussian_blur"
const SHARPEN := "sara-base-modules.sharpen"
const CANVAS := Vector2i(256, 256)
## The stripes' width, white then black.
const STRIPE: int = 4
## The stroke, along the middle row, and the brush's radius in pixels.
const FROM := Vector2(40.0, 128.0)
const TO := Vector2(216.0, 128.0)
const RADIUS: float = 20.0
## How far from the line the stroke's coverage is full, at a softness of 0.6.
const FULL: float = 6.0

var _surface: SaSurface = null
var _tool: StateScript = null
var _filters: SaFilterRegistry = null
var _door: SaContext = null
var _spec: SaOptionSpec = null
var _rows: Control = null


func before_each() -> void:
    _surface = Fixtures.make_surface(CANVAS)
    _filters = SaFilterRegistry.new()
    _filters.register(SaGaussianBlurFilter.new(), OWNER)
    _filters.register(SaSharpenFilter.new(), OWNER)
    _tool = StateScript.new()
    _tool.surface = _surface
    _door = SaContext.new()
    _door.filters = _filters
    _tool.settings.context = _door
    _tool.settings.softness = 0.6
    _tool.settings.opacity = 1.0
    _tool.settings.radius = RADIUS / _surface.get_document().brush_side
    _spec = null
    for spec: SaOptionSpec in ModuleScript.options(_door):
        if spec.key == &"filter_rows":
            _spec = spec
    _rows = null


func after_each() -> void:
    if _rows != null:
        _rows.free()
    _rows = null
    _spec = null
    _tool = null
    _filters = null
    _door = null
    Fixtures.teardown(_surface)
    _surface = null


## The rows as the docker builds them: the factory handed a write to the
## spec's property path on the settings, then bound to what that path reads.
func _build_rows() -> Control:
    var path := _spec.property_path()
    var write := func(value: Variant) -> void: _tool.settings.set_indexed(path, value)
    _rows = _spec.build_control.call(_spec, write) as Control
    _bind()
    return _rows


## What the docker does on every sync: shows the rows what the settings read.
func _bind() -> void:
    _spec.bind_value.call(_rows, _tool.settings.get_indexed(_spec.property_path()))


## The page the rows draw now.
func _dialog() -> SaDialog:
    return _rows.get("dialog") as SaDialog


## Moves the row *key* of the rows' page to *value* as a hand would, and lands
## the rerun the frame boundary would.
func _move(key: StringName, value: Variant) -> void:
    var row := _dialog().row(key)
    assert_not_null(row, "The page has a %s row" % key)
    if row != null:
        row.drive(value)
    _dialog().flush_rerun()


static func _image_format(texture: SaTexture) -> Image.Format:
    return Image.FORMAT_RGBAH if texture.format == RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT else Image.FORMAT_RGBAF


func _stripes() -> SaLayer:
    var doc := _surface.get_document()
    var layer := SaLayerOps.new(doc).add(&"", null, 1.0)
    doc.active_layer = layer
    var chunk := layer.get_or_create_chunk(Vector2i.ZERO)
    var texture := chunk.albedo()
    var image := Image.create_empty(chunk.pixel_size(), chunk.pixel_size(), false, _image_format(texture))
    for y in chunk.pixel_size():
        for x in chunk.pixel_size():
            image.set_pixel(x, y, Color.WHITE if posmod(x, 2 * STRIPE) < STRIPE else Color.BLACK)
    GlobalShaderCompiler.get_rd().texture_update(texture.rid, 0, image.get_data())
    layer.mark_unresolved(Vector2i.ZERO)
    doc.invalidate_chunks([Vector2i.ZERO])
    return layer


static func _read(layer: SaLayer) -> Image:
    var texture := (layer.chunks[Vector2i.ZERO] as SaChunk).albedo()
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    return Image.create_from_data(texture.size.x, texture.size.y, false, _image_format(texture), bytes)


## The largest difference of any channel between *a* and *b* over the pixels
## under the stroke's full coverage.
static func _widest_under_the_stroke(a: Image, b: Image) -> float:
    var widest := 0.0
    for y in a.get_height():
        for x in a.get_width():
            var at := Vector2(x, y) + Vector2(0.5, 0.5)
            var t := clampf((at - FROM).dot(TO - FROM) / (TO - FROM).length_squared(), 0.0, 1.0)
            if at.distance_to(FROM + (TO - FROM) * t) >= FULL:
                continue
            var one := a.get_pixel(x, y)
            var two := b.get_pixel(x, y)
            widest = maxf(widest, maxf(maxf(absf(one.r - two.r), absf(one.g - two.g)), absf(one.b - two.b)))
    return widest


## The stripes with the Gaussian Blur at *radius* applied once over a second
## layer through the Filter menu's own Apply, read back.
func _blurred_by(radius: float) -> Image:
    var doc := _surface.get_document()
    var active := doc.active_layer
    var twin := _stripes()
    var evaluated := StrokeScript.evaluate(_door, BLUR, {"radius": radius}, doc, twin)
    SaFilterApply.apply_neighbourhood(doc, twin, evaluated.recorded, evaluated.compute, evaluated.title)
    var read := _read(twin)
    doc.active_layer = active
    return read


func test_the_rows_stand_under_the_filter_choice_and_show_the_blur_s_radius() -> void:
    assert_not_null(_spec, "The brush declares the filter's rows")
    if _spec == null:
        return
    var keys: Array[StringName] = []
    for spec: SaOptionSpec in ModuleScript.options(_door):
        keys.append(spec.key)
    assert_eq(keys.find(&"filter_rows"), keys.find(&"filter_key") + 1, "Right under the Filter choice")
    assert_false(keys.has(&"filter_settings"), "And no button stands between a painter and them")
    assert_false(_spec.bar, "In the docker, not on the top bar")
    assert_eq(_spec.shown_when.get("key"), &"filter_key", "Drawn again when the choice moves")
    _tool.settings.filter_key = BLUR
    _tool.settings.filter_parameters = {"radius": 6.0}
    _build_rows()
    assert_eq(String(_rows.name), RowsScript.NODE_NAME, "The rows are found by their name")
    var radius := _dialog().row(&"radius") if _dialog() != null else null
    assert_not_null(radius, "The Gaussian's Radius is a row of its own")
    assert_true(radius != null and radius.line != null and radius.line.visible, "And shown")
    assert_almost_eq(float(radius.read()) if radius != null else 0.0, 6.0, 1e-6, "On the brush's radius")
    for declared: SaPageRow in _dialog().rows():
        if RowsScript.LEFT_OUT.has(_dialog().widget_name(declared.key)) and declared.line != null:
            assert_false(declared.line.visible, "%s is left out" % _dialog().widget_name(declared.key))


func test_the_filter_s_radius_moved_there_is_what_the_next_stroke_blurs_by() -> void:
    var layer := _stripes()
    _tool.settings.filter_key = BLUR
    _tool.settings.filter_parameters = {"radius": 6.0}
    _build_rows()
    _move(&"radius", 2.0)
    assert_almost_eq(float(_tool.settings.filter_parameters.get("radius", 0.0)), 2.0, 1e-6, "The row writes the brush")
    _tool.begin_stroke(FROM)
    for step in range(1, 21):
        _tool.add_sample(FROM.lerp(TO, step / 20.0))
        if step % 5 == 0:
            _tool.tick(0.016)
    _tool.end_stroke()
    var after := _read(layer)
    var by_two := _blurred_by(2.0)
    var by_six := _blurred_by(6.0)
    assert_true(_widest_under_the_stroke(by_two, by_six) > 0.05, "The two blurs differ, so the test can tell them apart")
    assert_almost_eq(_widest_under_the_stroke(by_two, after), 0.0, 1e-5, "The stroke lays the blur at the moved radius")


func test_a_second_filter_chosen_keeps_the_first_one_s_values_for_its_return() -> void:
    _tool.settings.filter_key = BLUR
    _tool.settings.filter_parameters = {}
    _build_rows()
    _move(&"radius", 11.0)
    _tool.settings.set_indexed(^"filter_key", SHARPEN)
    _bind()
    assert_eq(_rows.get("filter"), _filters.get_filter(StringName(SHARPEN)), "The rows follow the choice")
    var amount := _dialog().row(&"amount")
    assert_not_null(amount, "The Sharpen's own rows are drawn")
    _move(&"amount", 40.0)
    assert_almost_eq(float(_tool.settings.filter_parameters.get("amount", 0.0)), 40.0, 1e-6, "Which set the Sharpen")
    var handed := float(_tool.settings.filter_parameters.get("radius", 0.0))
    assert_false(is_equal_approx(handed, 11.0), "The blur's radius is not handed to the Sharpen")
    _tool.settings.set_indexed(^"filter_key", BLUR)
    _bind()
    assert_almost_eq(float(_tool.settings.filter_parameters.get("radius", 0.0)), 11.0, 1e-6, "The blur comes back at 11")
    assert_almost_eq(float(_dialog().row(&"radius").read()), 11.0, 1e-6, "And its row shows it")
    _tool.settings.set_indexed(^"filter_key", SHARPEN)
    assert_almost_eq(float(_tool.settings.filter_parameters.get("amount", 0.0)), 40.0, 1e-6, "The Sharpen kept its amount too")


func test_a_write_for_a_filter_no_longer_chosen_is_dropped() -> void:
    _tool.settings.filter_key = BLUR
    _tool.settings.filter_parameters = {"radius": 4.0}
    _tool.settings.filter_page = {"filter_key": SHARPEN, "parameters": {"amount": 10.0}}
    assert_eq(_tool.settings.filter_parameters, {"radius": 4.0}, "The blur's values stay as they were")


func test_a_preset_loaded_behind_the_rows_draws_them_again() -> void:
    _tool.settings.filter_key = BLUR
    _tool.settings.filter_parameters = {"radius": 4.0}
    _build_rows()
    var loaded := StateScript.FilterBrushSettingsScript.new()
    loaded.filter_key = BLUR
    loaded.filter_parameters = {"radius": 17.0}
    SaPresetStore.copy_settings(loaded, _tool.settings)
    _bind()
    assert_almost_eq(float(_dialog().row(&"radius").read()), 17.0, 1e-6, "The row reads the preset's radius")


func test_the_opacity_row_says_it_is_the_stroke_s_strength_over_the_result() -> void:
    var opacity: SaOptionSpec = null
    for spec: SaOptionSpec in ModuleScript.options(_door):
        if spec.key == &"opacity":
            opacity = spec
    assert_not_null(opacity, "An Opacity row")
    var said := opacity.tooltip if opacity != null else ""
    assert_true(said.begins_with("The stroke's strength over the filter's result"), "Whose tooltip says what it is")
