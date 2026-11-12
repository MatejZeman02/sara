## The woven ground beyond the document scales with the zoom.
##
## Beyond the rectangle the Canvas ground is `canvas.gdshader` on a rect a
## million pixels wide, where inside it is the kernel's texels, which the view
## draws square at 100 percent and above and averages below it. The shader read
## its weave at every screen pixel, half a texel off the kernel's corner, so
## once a pixel covered a thread or more the ground beyond the edge turned to
## coarse speckle beside a smooth document. It now reads the texel the pixel
## falls in and, below 100 percent, averages a few taps over the footprint and
## fades them toward the weave's mean. This suite draws the shader into a
## viewport and holds three things. At a texel a pixel it is the kernel's
## ground texel for texel, which `canvas.gmacs` and the copy of it in the shader
## owe each other. Its contrast falls with the footprint the way the view's own
## filter does, in bands taken from the view on the running app. And the tone it
## settles to is the tone at 100 percent, whatever the thread thickness and
## irregularity. The scenario of the same name photographs the edge.
extends "res://tests/test_framework.gd"

## The shader draws into a viewport, and the kernel into an easel.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")

const SHADER_PATH := "res://shaders/canvas/canvas.gdshader"

## The side of the strip drawn, in screen pixels.
const SIDE := 192

## Where the strip reads the document. Away from the origin, as the rect beyond
## the document is, and whole, so a pixel is a texel at one texel a pixel.
const ORIGIN := Vector2(4000.0, 6000.0)

## The two ends of the ground's shade. Black and white are the same in working
## space and in display space, so a viewport pixel over 255 is the shade itself.
const COLOR_A := Color(1.0, 1.0, 1.0, 1.0)
const COLOR_B := Color(0.0, 0.0, 0.0, 1.0)

## The canvas's defaults, which the descriptor owns.
const SPACING: float = 8.0
const THICKNESS: float = 0.36
const IRREGULARITY: float = 0.35

## How far a pixel may be from the kernel's texel, in shade, before it counts as
## differing, and the share of the strip that may. A pixel exactly on a thread's
## edge can round the other way in a shader and in a kernel, and that is all it
## may be. On the machine that took the figures none differed.
const KERNEL_SLACK: float = 0.012
const KERNEL_MAX_DIFFERING: float = 0.005

var _registries: SaRegistries = null
var _easel: SaEasel = null


func before_each() -> void:
    _registries = Fixtures.make_registries()
    _easel = SaEasel.create_default(Vector2i(SIDE + 32, SIDE + 32))
    _easel.compositor.set_registry(_registries.blend_modes)


func after_each() -> void:
    _easel.free()
    _easel = null
    _registries = null


## The shader drawn into a strip, *texels_per_pixel* document pixels to a
## screen pixel, from the document position *origin*.
func _strip(texels_per_pixel: float, params: Dictionary = {}, origin: Vector2 = ORIGIN) -> Image:
    var material := ShaderMaterial.new()
    material.shader = load(SHADER_PATH)
    material.set_shader_parameter("color_a", COLOR_A)
    material.set_shader_parameter("color_b", COLOR_B)
    material.set_shader_parameter("scale", SPACING)
    material.set_shader_parameter("thickness", THICKNESS)
    material.set_shader_parameter("irregularity", IRREGULARITY)
    material.set_shader_parameter("angle", 0.0)
    for key: String in params:
        material.set_shader_parameter(key, params[key])
    material.set_shader_parameter("rect_origin", origin)
    material.set_shader_parameter("rect_size", Vector2(SIDE, SIDE) * texels_per_pixel)
    material.set_shader_parameter("texels_per_pixel", texels_per_pixel)
    var viewport := SubViewport.new()
    viewport.size = Vector2i(SIDE, SIDE)
    viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    EventBus.add_child(viewport)
    var item := RenderingServer.canvas_item_create()
    RenderingServer.canvas_item_set_parent(item, viewport.find_world_2d().canvas)
    RenderingServer.canvas_item_set_material(item, material.get_rid())
    RenderingServer.canvas_item_add_rect(item, Rect2(Vector2.ZERO, Vector2(SIDE, SIDE)), Color.WHITE)
    RenderingServer.force_draw(false, 0.0)
    var image := viewport.get_texture().get_image()
    RenderingServer.free_rid(item)
    viewport.free()
    return image


## The strip's shade at each pixel, 0 to 1.
static func _shades(image: Image) -> PackedFloat32Array:
    var shades := PackedFloat32Array()
    shades.resize(image.get_width() * image.get_height())
    for y in image.get_height():
        for x in image.get_width():
            shades[y * image.get_width() + x] = image.get_pixel(x, y).r
    return shades


static func _mean(values: PackedFloat32Array) -> float:
    var total := 0.0
    for value in values:
        total += value
    return total / float(values.size())


static func _deviation(values: PackedFloat32Array) -> float:
    var mean := _mean(values)
    var total := 0.0
    for value in values:
        total += (value - mean) * (value - mean)
    return sqrt(total / float(values.size()))


## The contrast and the mean of a strip, in 0 to 1 of the shade.
func _measure(texels_per_pixel: float, params: Dictionary = {}) -> Vector2:
    var shades := _shades(_strip(texels_per_pixel, params))
    return Vector2(_deviation(shades), _mean(shades))


## A ground of the *canvas* type under the paint, in white and black, resolved
## through the easel, and the shade the kernel wrote at each pixel of the strip.
func _kernel_shades() -> PackedFloat32Array:
    var doc := _easel.document
    var paint := doc.active_layer
    var ground := SaLayerOps.new(doc).add(&"canvas", _registries.layer_types)
    ground.generator_params["color"] = COLOR_A
    ground.generator_params["second"] = COLOR_B
    doc.set_active_layer(paint)
    doc.update_caches()
    _easel.request_full_composite()
    _easel.process_pending_composite()
    var output := _easel.output
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(output.rid, 0)
    var shades := PackedFloat32Array()
    shades.resize(SIDE * SIDE)
    for y in SIDE:
        for x in SIDE:
            shades[y * SIDE + x] = SaFieldSpec.decode_texel(bytes, output.format, y * output.size.x + x).r
    return shades


## At 100 percent the ground beyond the document is the ground inside it, texel
## for texel, which is what `canvas.gdshader`'s header says and nothing held. The
## pixel centre falls half a texel in, so a shader that reads the weave there and
## not at the texel it falls in is half a texel out and fails this.
func test_at_a_texel_a_pixel_the_shader_is_the_kernels_ground() -> void:
    var kernel := _kernel_shades()
    var drawn := _shades(_strip(1.0, {}, Vector2.ZERO))
    assert_eq(drawn.size(), kernel.size(), "The strip and the kernel's region are the same size")
    var differing := 0
    for index in range(mini(drawn.size(), kernel.size())):
        if absf(drawn[index] - kernel[index]) > KERNEL_SLACK:
            differing += 1
    var share := float(differing) / float(kernel.size())
    assert_true(
        share <= KERNEL_MAX_DIFFERING,
        "%.2f percent of the pixels differ from the kernel's texel by over a hundredth" % (share * 100.0)
    )
    assert_true(_deviation(kernel) > 0.1, "and the ground read is a weave, not a flat colour")


## A pixel centre sits half a texel into its texel, so moving the rect by under
## a texel moves no pixel to another texel, and a shader that reads at the centre
## and not the texel does move them.
func test_a_shift_of_under_a_texel_changes_nothing() -> void:
    var at := _shades(_strip(1.0, {}, ORIGIN))
    var shifted := _shades(_strip(1.0, {}, ORIGIN + Vector2(0.3, 0.3)))
    var differing := 0
    for index in range(at.size()):
        if absf(at[index] - shifted[index]) > 0.002:
            differing += 1
    assert_eq(differing, 0, "Every pixel is the texel it falls in, however far in")


## The view's filter leaves this much of the weave's contrast at the default
## spacing, measured on the running app by the scenario and on a port of the
## filter: 0.87 at two texels a pixel, 0.68 at four, 0.42 at six and 0.16 at
## 12 percent. The bands are the figure and a tenth or two either side.
func test_the_contrast_falls_as_the_view_averages() -> void:
    var full := _measure(1.0).x
    assert_true(full > 0.15, "A weave at 100 percent has contrast, %.3f" % full)
    var bands := {2.0: Vector2(0.72, 1.0), 4.0: Vector2(0.52, 0.84), 6.0: Vector2(0.27, 0.57), 8.33: Vector2(0.05, 0.30)}
    for footprint: float in bands:
        var share := _measure(footprint).x / full
        var band: Vector2 = bands[footprint]
        assert_true(
            share >= band.x and share <= band.y,
            (
                "At %.2f texels a pixel the contrast is %.2f of the weave's, and the view leaves between %.2f and %.2f"
                % [footprint, share, band.x, band.y]
            )
        )


## Past a few spacings the ground is nearly flat, as the average over a
## footprint of many threads is, and it does not come back as moire.
func test_far_out_the_ground_is_nearly_flat() -> void:
    var full := _measure(1.0).x
    for footprint: float in [16.0, 33.0, 66.0]:
        var share := _measure(footprint).x / full
        assert_true(share < 0.3, "At %.0f texels a pixel the contrast is %.2f of the weave's" % [footprint, share])


## The shade the weave settles to depends on how thick the threads are and how
## far they wander, and the fade pulls toward it, so a wrong figure shows as a
## step in tone across the document's edge. The tone at a footprint of many
## threads is the tone at a texel a pixel, to a few hundredths of a shade.
func test_the_tone_it_settles_to_is_the_tone_at_100_percent() -> void:
    var cases: Array[Dictionary] = [
        {"thickness": THICKNESS, "irregularity": IRREGULARITY},
        {"thickness": 0.4, "irregularity": 0.8},
        {"thickness": 1.0, "irregularity": 0.25},
        {"thickness": 0.6, "irregularity": 0.5},
    ]
    for params in cases:
        var near := _measure(1.0, params).y
        for footprint: float in [16.0, 33.0]:
            var far := _measure(footprint, params).y
            assert_almost_eq(
                far,
                near,
                0.02,
                (
                    "Thickness %.1f and irregularity %.2f at %.0f texels a pixel settle to the tone at one"
                    % [params.thickness, params.irregularity, footprint]
                )
            )
