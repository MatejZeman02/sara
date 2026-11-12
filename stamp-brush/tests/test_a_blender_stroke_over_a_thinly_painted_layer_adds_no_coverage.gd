extends "res://tests/test_framework.gd"

## The shipped Blender stroked many times over a thin sprinkle of paint
## raises no texel past the largest alpha the layer held, and leaves the summed
## alpha no more than a tenth above what it was, in build-up and in wash. A
## Soft Haze stroke over the same sprinkle still raises it, because Soft Haze
## lays paint of its own.
##
## Many strokes of the Blender and Soft Haze over wisps of mean alpha 0.013 must
## not turn them into flat slabs. Every blurring dab caps the alpha it lays at
## the lattice's and then lays it over the texel, and an over composite climbs
## towards one however small each share is, so twenty dabs a texel and a few
## strokes could take a thin wisp opaque.

const ScratchFolder := preload("res://tests/fixtures/scratch_folder.gd")
const StateBrushScript = preload("res://modules/sara-base-modules/stamp-brush/tools/state_brush.gd")
const SettingsScript = preload("res://modules/sara-base-modules/stamp-brush/stamp_brush_settings.gd")
const ShippedPresetsScript = preload("res://modules/sara-base-modules/stamp-brush/presets/sa_shipped_presets.gd")
const Fixtures = preload("res://tests/fixtures.gd")

const REQUIRES_GPU := true

static var scratch_dir: String = SaDataRoot.path("test_blender")

## The wisps' beige.
const WISP := Color(0.78, 0.72, 0.6)
const BLACK := Color(0.0, 0.0, 0.0, 1.0)
## The painter's wisps peaked at about 0.67.
const PEAK: float = 0.7
const DOTS: int = 900
const RADIUS: float = 16.0
const STEPS: int = 30
const STROKES: int = 12
## How far a blurred texel may stand past the layer's largest alpha before,
## which is the rounding of a half float near 0.7.
const THICKER_MOST: float = 0.002
## The summed alpha after may be this many times the sum before.
const SUM_MOST: float = 1.1

var _side: int = 0


func before_each() -> void:
    ScratchFolder.clear(scratch_dir)


func after_each() -> void:
    ScratchFolder.clear(scratch_dir)


## A shipped preset, the drawn tips among them.
func _preset(preset_name: String) -> Resource:
    var store := SaPresetStore.new()
    store.dir = scratch_dir
    store.install_shipped(SettingsScript.new(), ShippedPresetsScript)
    return store.load_preset(preset_name)


static func _format(texture: SaTexture) -> Image.Format:
    if texture.format == RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT:
        return Image.FORMAT_RGBAH
    return Image.FORMAT_RGBAF


## Two chunks side by side, the left one holding a sprinkle of small wisps
## across its middle band, of mean alpha about a hundredth and a largest of
## [constant PEAK], and the right one empty.
func _surface() -> SaSurface:
    var probe := Fixtures.make_surface(Vector2i(64, 64))
    var side := probe.get_document().active_layer.get_or_create_chunk(Vector2i(0, 0)).pixel_size()
    probe.get_document().free()
    probe.easel.free()
    _side = side
    var surface := Fixtures.make_surface(Vector2i(2 * side, side))
    var document := surface.get_document()
    var chunk := document.active_layer.get_or_create_chunk(Vector2i(0, 0))
    var texture := chunk.albedo()
    var image := Image.create_empty(side, side, false, _format(texture))
    var random := RandomNumberGenerator.new()
    random.seed = 607
    for i in DOTS:
        @warning_ignore("integer_division")
        var at := Vector2i(random.randi_range(8, side - 10), random.randi_range(side * 3 / 10, side * 7 / 10))
        var alpha := PEAK if i == 0 else random.randf_range(0.05, PEAK)
        for dy in 2:
            for dx in 2:
                image.set_pixel(at.x + dx, at.y + dy, Color(WISP, alpha))
    GlobalShaderCompiler.get_rd().texture_update(texture.rid, 0, image.get_data())
    document.active_layer.mark_unresolved(Vector2i(0, 0))
    document.invalidate_chunks([Vector2i(0, 0)])
    surface.easel.request_full_composite()
    surface.easel.process_pending_composite()
    return surface


func _stroke(surface: SaSurface, preset: Resource, mode: int, from: Vector2, to: Vector2) -> void:
    var brush := StateBrushScript.new()
    brush.surface = surface
    SaPresetStore.copy_settings(preset, brush.settings)
    brush.settings.radius = RADIUS / float(_side)
    brush.settings.color = BLACK if mode >= 0 else WISP
    if mode >= 0:
        brush.settings.painting_mode = mode as SettingsScript.PaintingMode
    var view := surface.view
    for i in range(STEPS + 1):
        view.mouse_position = from.lerp(to, float(i) / float(STEPS))
        var event: InputEvent
        if i == 0:
            var press := InputEventMouseButton.new()
            press.button_index = MOUSE_BUTTON_LEFT
            press.pressed = true
            event = press
        else:
            var motion := InputEventMouseMotion.new()
            motion.button_mask = MOUSE_BUTTON_MASK_LEFT
            motion.pressure = 1.0
            event = motion
        brush.handle_input(event)
    var release := InputEventMouseButton.new()
    release.button_index = MOUSE_BUTTON_LEFT
    release.pressed = false
    brush.handle_input(release)
    surface.get_document().commit_stroke()


## The layer's texels over alpha 0.5, its mean alpha over the two chunks, its
## largest alpha and its summed alpha, and how many texels held a NaN.
func _reading(layer: SaLayer) -> Dictionary:
    var over := 0
    var total := 0.0
    var largest := 0.0
    var broken := 0
    var count := 0
    for grid_pos: Vector2i in [Vector2i(0, 0), Vector2i(1, 0)]:
        count += _side * _side
        var chunk: SaChunk = layer.chunks.get(grid_pos)
        if chunk == null:
            continue
        var texture := chunk.albedo()
        var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
        var image := Image.create_from_data(_side, _side, false, _format(texture), bytes)
        for y in _side:
            for x in _side:
                var a := image.get_pixel(x, y).a
                if is_nan(a):
                    broken += 1
                    continue
                total += a
                largest = maxf(largest, a)
                if a > 0.5:
                    over += 1
    return {"over": over, "mean": total / float(count), "largest": largest, "sum": total, "broken": broken}


static func _said(reading: Dictionary) -> String:
    return "%d over 0.5, mean %.5f, largest %.4f" % [reading["over"], reading["mean"], reading["largest"]]


## Strokes across the sprinkled band, at heights that cross the band evenly,
## each running from the left chunk's margin onto the right chunk.
func _strokes(surface: SaSurface, preset: Resource, mode: int, count: int) -> void:
    for i in count:
        var y := float(_side) * (0.32 + 0.36 * float(i % 6) / 5.0)
        _stroke(surface, preset, mode, Vector2(12.0, y), Vector2(float(_side) + 20.0, y))


func _check_blender(mode: int, mode_name: String) -> void:
    var preset := _preset("Blender")
    assert_not_null(preset, "The fresh store holds a Blender")
    if preset == null:
        return
    var surface := _surface()
    var document := surface.get_document()
    var before := _reading(document.active_layer)
    _strokes(surface, preset, mode, STROKES)
    var after := _reading(document.active_layer)
    print(
        (
            "  Blender in %s, before: %s, after %d strokes: %s, sum %.2f to %.2f"
            % [mode_name, _said(before), STROKES, _said(after), before["sum"], after["sum"]]
        )
    )
    assert_eq(after["broken"], 0, "In %s no texel holds a NaN" % mode_name)
    assert_true(
        after["largest"] <= before["largest"] + THICKER_MOST,
        (
            "In %s no texel stands above the layer's largest alpha before, %.4f against %.4f"
            % [mode_name, after["largest"], before["largest"]]
        )
    )
    assert_true(
        after["sum"] <= SUM_MOST * before["sum"],
        "and the summed alpha is at most %.1f times what it was, %.2f against %.2f" % [SUM_MOST, after["sum"], before["sum"]]
    )
    assert_true(after["sum"] > 0.5 * before["sum"], "and the strokes moved the paint rather than wiping it")
    document.free()
    surface.easel.free()


func test_many_blender_strokes_in_build_up_add_no_coverage() -> void:
    _check_blender(SettingsScript.PaintingMode.BUILD_UP, "build-up")


func test_many_blender_strokes_in_wash_add_no_coverage() -> void:
    _check_blender(SettingsScript.PaintingMode.WASH, "wash")


## A blur now paints straight into the layer, so its undo is the direct route's
## and has to take back a chunk the stroke made as well as the ones it moved.
func test_a_blender_stroke_onto_an_empty_chunk_undoes_whole() -> void:
    var preset := _preset("Blender")
    if preset == null:
        return
    var surface := _surface()
    var document := surface.get_document()
    var before := _reading(document.active_layer)
    _strokes(surface, preset, SettingsScript.PaintingMode.BUILD_UP, 1)
    var moved := _reading(document.active_layer)
    assert_true(document.active_layer.chunks.has(Vector2i(1, 0)), "The blur carried paint onto the empty chunk")
    assert_true(absf(moved["sum"] - before["sum"]) > 0.01, "and moved the paint it crossed")
    assert_true(document.undo(), "Undo takes the stroke back")
    var undone := _reading(document.active_layer)
    assert_eq(undone["over"], before["over"], "and the texels over 0.5 are as they were")
    var said := "and so is the sum, %.3f against %.3f" % [undone["sum"], before["sum"]]
    assert_true(absf(undone["sum"] - before["sum"]) < 0.01, said)
    document.free()
    surface.easel.free()


func test_a_soft_haze_stroke_over_the_same_layer_still_raises_it() -> void:
    var preset := _preset("Soft Haze")
    assert_not_null(preset, "The fresh store holds Soft Haze")
    if preset == null:
        return
    var surface := _surface()
    var document := surface.get_document()
    var before := _reading(document.active_layer)
    _strokes(surface, preset, -1, 2)
    var after := _reading(document.active_layer)
    print(
        (
            "  Soft Haze, before: %s, after 2 strokes: %s, sum %.2f to %.2f"
            % [_said(before), _said(after), before["sum"], after["sum"]]
        )
    )
    assert_true(
        after["sum"] > SUM_MOST * before["sum"],
        "Soft Haze lays paint of its own, the sum %.2f against %.2f" % [after["sum"], before["sum"]]
    )
    document.free()
    surface.easel.free()
