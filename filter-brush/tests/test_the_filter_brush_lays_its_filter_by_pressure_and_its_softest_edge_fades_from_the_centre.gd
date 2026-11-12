## The filter brush lays its
## filter by the pen's pressure, and its softest edge fades as a soft brush
## does.
##
## The softness slider of a blur preset was too weak and the effect too strong,
## and the pen's pressure should play a bigger part. So the Blur Filter laid at pressure 0.2 covers a third of what a full
## press does at most, a stroke whose pressure rises rises along its length in
## no step over a tenth, a dab at softness one lays a quarter of its centre's
## coverage at most halfway out while softness nought is the hard edge it was,
## and a brush saved before the row loads and lays what it laid before.
##
## The coverage is read off the stroke before its lift, the texture the
## filter's result is mixed into the layer by, so each number is the brush's
## and not a blur's of stripes.
extends "res://tests/test_framework.gd"

## Chunks are real textures, so this needs a RenderingDevice.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const StateScript = preload("res://modules/sara-base-modules/filter-brush/state_filter_brush.gd")
const SettingsScript = preload("res://modules/sara-base-modules/filter-brush/filter_brush_settings.gd")
const PresetsScript = preload("res://modules/sara-base-modules/filter-brush/presets/filter_brush_presets.gd")

const OWNER: StringName = &"sara-base-modules"
const CANVAS := Vector2i(256, 256)
## The stroke, along the middle row, and the brush's radius in pixels.
const FROM := Vector2(40.0, 128.0)
const TO := Vector2(216.0, 128.0)
const RADIUS: float = 20.0
## The samples a stroke is laid in, ticked every fifth as frames would.
const SAMPLES: int = 20

var _surface: SaSurface = null
var _tool: StateScript = null
var _door: SaContext = null
var _dir: String = SaDataRoot.path("test_filter_brush")


func before_each() -> void:
    _surface = Fixtures.make_surface(CANVAS)
    var filters := SaFilterRegistry.new()
    filters.register(SaGaussianBlurFilter.new(), OWNER)
    _tool = StateScript.new()
    _tool.surface = _surface
    _door = SaContext.new()
    _door.filters = filters
    _tool.settings.context = _door
    _stripes()


func after_each() -> void:
    if DirAccess.dir_exists_absolute(_dir):
        for file_name: String in DirAccess.get_files_at(_dir):
            DirAccess.remove_absolute(_dir.path_join(file_name))
        DirAccess.remove_absolute(_dir)
    _tool = null
    _door = null
    Fixtures.teardown(_surface)
    _surface = null


## A fresh active layer of black and white stripes four pixels wide, so the
## brush has paint to take.
func _stripes() -> void:
    var doc := _surface.get_document()
    var layer := SaLayerOps.new(doc).add(&"", null, 1.0)
    doc.active_layer = layer
    var chunk := layer.get_or_create_chunk(Vector2i.ZERO)
    var texture := chunk.albedo()
    var format := Image.FORMAT_RGBAH if texture.format == RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT else Image.FORMAT_RGBAF
    var image := Image.create_empty(chunk.pixel_size(), chunk.pixel_size(), false, format)
    for y in chunk.pixel_size():
        for x in chunk.pixel_size():
            image.set_pixel(x, y, Color.WHITE if posmod(x, 8) < 4 else Color.BLACK)
    GlobalShaderCompiler.get_rd().texture_update(texture.rid, 0, image.get_data())
    layer.mark_unresolved(Vector2i.ZERO)
    doc.invalidate_chunks([Vector2i.ZERO])


## The Blur Filter preset's recipe written onto the tool's settings, the way
## loading the preset writes it, at a radius in pixels of this canvas.
func _blur_preset() -> void:
    var recipe: Dictionary = {}
    for entry: Dictionary in PresetsScript.entries():
        if entry["name"] == "Blur Filter":
            recipe = entry
    var built := PresetsScript.build(SettingsScript, recipe)
    assert_not_null(built, "The Blur Filter recipe builds")
    SaPresetStore.copy_settings(built, _tool.settings)
    _tool.settings.radius = RADIUS / _surface.get_document().brush_side


## The coverage of a stroke along *points* at *pressures*, one a point, read
## before its lift and then lifted. A single point is a dab.
func _coverage(points: PackedVector2Array, pressures: PackedFloat32Array) -> Image:
    _tool.begin_stroke(points[0], pressures[0])
    for index in range(1, points.size()):
        _tool.add_sample(points[index], pressures[index])
        if index % 5 == 0:
            _tool.tick(0.016)
    _tool.tick(0.016)
    var texture: SaTexture = _tool._stroke.coverage[Vector2i.ZERO]
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    var read := Image.create_from_data(texture.size.x, texture.size.y, false, Image.FORMAT_RF, bytes)
    _tool.end_stroke()
    return read


## A stroke from [constant FROM] to [constant TO] whose pressure runs from
## *first* to *last*.
func _stroke(first: float, last: float) -> Image:
    var points := PackedVector2Array()
    var pressures := PackedFloat32Array()
    for step in SAMPLES + 1:
        var along := float(step) / SAMPLES
        points.append(FROM.lerp(TO, along))
        pressures.append(lerpf(first, last, along))
    return _coverage(points, pressures)


## The coverage a brush saved before the softness and pressure keys laid at *apart* pixels from its
## line: flat inside the radius less the softness's share, a smoothstep to
## nought across that share at least a texel wide, times the opacity.
static func _before_the_keys(apart: float, softness: float, opacity: float) -> float:
    var inside := clampf((RADIUS - apart) / maxf(RADIUS * softness, 1.0), 0.0, 1.0)
    return inside * inside * (3.0 - 2.0 * inside) * opacity


## The largest gap between *read* and the coverage a brush saved before the softness and pressure keys
## laid along the stroke's line, over every texel the brush could reach.
static func _off_before_the_keys(read: Image, softness: float, opacity: float) -> float:
    var worst := 0.0
    for y in range(100, 157):
        for x in range(10, 247):
            var at := Vector2(x, y) + Vector2(0.5, 0.5)
            var t := clampf((at - FROM).dot(TO - FROM) / (TO - FROM).length_squared(), 0.0, 1.0)
            var expected := _before_the_keys(at.distance_to(FROM + (TO - FROM) * t), softness, opacity)
            worst = maxf(worst, absf(read.get_pixel(x, y).r - expected))
    return worst


func test_a_light_touch_lays_a_third_of_a_full_press_at_most() -> void:
    _blur_preset()
    assert_true(_tool.settings.opacity_by_pressure, "The Blur Filter takes the pen's pressure")
    var light := _stroke(0.2, 0.2).get_pixel(128, 128).r
    var hard := _stroke(1.0, 1.0).get_pixel(128, 128).r
    assert_true(hard > 0.9, "A full press lays the whole of the filter at the centre, %f" % hard)
    assert_true(light <= hard / 3.0, "Pressure 0.2 lays %f at the centre, a third of the full press's %f at most" % [light, hard])
    assert_true(light > 0.0, "And still lays some")


func test_a_rising_pressure_rises_along_the_stroke_in_no_step_over_a_tenth() -> void:
    _blur_preset()
    var read := _stroke(0.2, 1.0)
    var widest := 0.0
    var fell := 0.0
    var first := read.get_pixel(int(FROM.x), 128).r
    var last := read.get_pixel(int(TO.x) - 1, 128).r
    for x in range(int(FROM.x), int(TO.x) - 1):
        var step := read.get_pixel(x + 1, 128).r - read.get_pixel(x, 128).r
        widest = maxf(widest, absf(step))
        fell = maxf(fell, -step)
    assert_true(last - first > 0.6, "The coverage rises from %f to %f along the stroke" % [first, last])
    assert_true(fell < 1e-4, "It never falls on the way, %f at most" % fell)
    assert_true(widest <= 0.1, "No step from a texel to the next is over a tenth, %f the largest" % widest)


func test_a_dab_at_softness_one_lays_a_quarter_at_most_halfway_out() -> void:
    _blur_preset()
    _tool.settings.softness = 1.0
    var centre := Vector2(128.0, 128.0)
    var read := _coverage(PackedVector2Array([centre]), PackedFloat32Array([1.0]))
    var middle := read.get_pixel(128, 128).r
    var halfway := read.get_pixel(128 + int(RADIUS / 2.0), 128).r
    assert_true(middle > 0.9, "The centre takes the whole of the filter, %f" % middle)
    assert_true(halfway <= middle / 4.0, "At half the radius %f, a quarter of the centre's %f at most" % [halfway, middle])
    assert_true(halfway > 0.0, "And the fade has not ended there")


func test_softness_nought_is_the_hard_edge_it_was() -> void:
    _blur_preset()
    _tool.settings.softness = 0.0
    _tool.settings.opacity = 0.7
    var read := _stroke(1.0, 1.0)
    assert_true(_off_before_the_keys(read, 0.0, 0.7) < 1e-4, "The edge is the hard one an older brush laid")


func test_a_brush_saved_before_the_row_lays_the_same_coverage_as_before() -> void:
    # A file the way a brush was written before the softness and pressure keys: none of the keys the row
    # added, so each loads at its declaration.
    DirAccess.make_dir_recursive_absolute(_dir)
    var path := _dir.path_join("Old Blur.tres")
    var file := FileAccess.open(path, FileAccess.WRITE)
    (
        file
        . store_string(
            (
                "\n"
                . join(
                    [
                        '[gd_resource type="Resource" load_steps=2 format=3]',
                        "",
                        '[ext_resource type="Script" path="%s" id="1"]' % SettingsScript.resource_path,
                        "",
                        "[resource]",
                        'script = ExtResource("1")',
                        'filter_key = "sara-base-modules.gaussian_blur"',
                        'filter_parameters = {"radius": 6.0}',
                        "radius = 0.04",
                        "opacity = 0.8",
                        "softness = 0.6",
                        "",
                    ]
                )
            )
        )
    )
    file.close()
    var loaded := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
    assert_not_null(loaded, "The old file loads")
    assert_false(loaded.get("opacity_by_pressure"), "With pressure off")
    assert_eq(loaded.get("format_version"), 0, "At the older format")
    SaPresetStore.copy_settings(loaded, _tool.settings)
    _tool.settings.radius = RADIUS / _surface.get_document().brush_side
    assert_false(_tool.settings.soft_tip(), "Onto a brush that keeps the fade it was painted with")
    var read := _stroke(0.2, 0.2)
    var off := _off_before_the_keys(read, 0.6, 0.8)
    assert_true(off < 1e-4, "A light touch lays what an older brush laid, the pressure read by nothing, %f apart" % off)
