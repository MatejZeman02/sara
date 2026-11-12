## The woven ground at spacing 2 matches across the edge when zoomed out.
##
## made the weave beyond the document average over a pixel's footprint and
## fade toward its mean, with the fade fitted on spacings from 4 up. At the
## slider's floor, threads two texels wide, the outside read calmer than the
## document beside it: a contrast of 1.61 against 3.14 at 12 percent and 3.83
## against 5.31 at 50. The document's texels hold that contrast themselves. Two
## reads of a thread's crown add up to a tone that depends on where they fall
## across it, the bend moves the threads against the texels, and an ideal box
## over the footprint keeps as much of it as the view does. The fade is now
## wider at a spacing of 2 and the taps sit on a lattice, each in its own row
## and column. This suite draws `canvas.gdshader` into a viewport at spacing 2
## and holds its contrast in bands taken from the view, measured on a port of
## the view's filter at this strip and on the running app by the scenario.
extends "res://tests/test_framework.gd"

## The shader draws into a viewport.
const REQUIRES_GPU := true

const SHADER_PATH := "res://shaders/canvas/canvas.gdshader"

## The side of the strip drawn, in screen pixels.
const SIDE := 192

## Where the strip reads the document, away from the origin as the rect beyond
## the document is, and whole, so a pixel centre falls where the view's would.
const ORIGIN := Vector2(4000.0, 6000.0)

## The two ends of the ground's shade, so a viewport pixel over 255 is the shade.
const COLOR_A := Color(1.0, 1.0, 1.0, 1.0)
const COLOR_B := Color(0.0, 0.0, 0.0, 1.0)

## The slider's floor, threads two texels apart, and the canvas's other defaults.
const SPACING: float = 2.0
const THICKNESS: float = 0.8
const IRREGULARITY: float = 0.35


## The shader drawn into a strip, *texels_per_pixel* document pixels to a
## screen pixel, from ORIGIN.
func _strip(texels_per_pixel: float) -> Image:
    var material := ShaderMaterial.new()
    material.shader = load(SHADER_PATH)
    material.set_shader_parameter("color_a", COLOR_A)
    material.set_shader_parameter("color_b", COLOR_B)
    material.set_shader_parameter("scale", SPACING)
    material.set_shader_parameter("thickness", THICKNESS)
    material.set_shader_parameter("irregularity", IRREGULARITY)
    material.set_shader_parameter("angle", 0.0)
    material.set_shader_parameter("rect_origin", ORIGIN)
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


## The strip's contrast, the deviation of its shade, 0 to 1.
func _contrast(texels_per_pixel: float) -> float:
    var image := _strip(texels_per_pixel)
    var shades := PackedFloat32Array()
    for y in image.get_height():
        for x in image.get_width():
            shades.append(image.get_pixel(x, y).r)
    var mean := 0.0
    for shade in shades:
        mean += shade
    mean /= float(shades.size())
    var total := 0.0
    for shade in shades:
        total += (shade - mean) * (shade - mean)
    return sqrt(total / float(shades.size()))


## The view at spacing 2 leaves this much of the weave's contrast at this strip,
## on the port of its filter: 0.36 at two texels a pixel, 0.27 at four, 0.23 at
## six and 0.21 at 12 percent, where the app read 0.36 at 50 percent and 0.22 at
## 12. The bands are the figure and about a fifth either side. The fade fitted
## on spacings from 4 up read 0.26, 0.12, 0.08 and 0.09 here and fails all four.
func test_the_spacing_2_contrast_follows_the_view() -> void:
    var full := _contrast(1.0)
    assert_true(full > 0.15, "A weave at 100 percent has contrast, %.3f" % full)
    var bands := {2.0: Vector2(0.29, 0.45), 4.0: Vector2(0.22, 0.34), 6.0: Vector2(0.19, 0.29), 8.33: Vector2(0.17, 0.265)}
    for footprint: float in bands:
        var share := _contrast(footprint) / full
        var band: Vector2 = bands[footprint]
        assert_true(
            share >= band.x and share <= band.y,
            (
                "At %.2f texels a pixel the contrast is %.2f of the weave's, and the view leaves between %.2f and %.2f"
                % [footprint, share, band.x, band.y]
            )
        )


## Threads two texels wide leave the texels a tone no footprint settles, so the
## view still keeps 0.14 of the weave's contrast at 16 texels a pixel. A fade
## that takes the outside to its mean there leaves a seam, as the one fitted on
## spacings from 4 up did at 0.03.
func test_two_texel_threads_do_not_settle_to_flat() -> void:
    var full := _contrast(1.0)
    var share := _contrast(16.0) / full
    assert_true(
        share >= 0.08 and share <= 0.22,
        "At 16 texels a pixel the contrast is %.2f of the weave's, and the view leaves 0.14" % share
    )


## At seven texels a pixel, 14 percent, rows of three taps staggered along the
## row lined up with two-texel threads and read 0.55 of the weave's contrast
## under this fade where the view leaves 0.22. The lattice reads 0.32 here.
func test_the_taps_do_not_line_up_with_two_texel_threads() -> void:
    var full := _contrast(1.0)
    var share := _contrast(7.0) / full
    assert_true(
        share >= 0.15 and share <= 0.4,
        "At 7 texels a pixel the contrast is %.2f of the weave's, and the view leaves 0.22" % share
    )
