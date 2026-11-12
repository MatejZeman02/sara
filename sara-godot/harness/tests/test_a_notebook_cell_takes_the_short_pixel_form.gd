## The `kernel` step takes the short pixel form, a source holding
## `def pixel(ivec2 at) -> vec4` and `uniform` lines and no `kernel` line, and
## wraps it the way a module's pixel function is wrapped.
##
## Built like the kernel read suite: the driver with no run, handed the document, and each
## pixel read back the way an export does, the one readback a test may make.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const KernelDriver := preload("res://harness/sa_kernel_driver.gd")
const SaExportScript = preload("res://core/export/sa_export.gd")

## Lesson 1's shape: two imports, two sliders, a module-level Bayer matrix and
## an ordered dither of the lightness in OKLab.
const DITHER_SHORT := """import linear_srgb_color_space
import oklab_color_space

uniform float levels = 4.0    # range 2 16
uniform float spread = 1.0    # range 0 2

const float BAYER[16] = float[16](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0)

def pixel(ivec2 at) -> vec4:
    vec4 here = src(at)
    vec3 lab = linear_srgb_to_oklab(here.rgb)
    float threshold = (BAYER[(at.y % 4) * 4 + at.x % 4] + 0.5) / 16.0 - 0.5
    float lightness = floor(lab.x * levels + threshold * spread + 0.5) / levels
    return vec4(oklab_to_linear_srgb(vec3(lightness, lab.y, lab.z)), here.a)
"""

## The same dither written whole, the way a cell wrote it before this row.
const DITHER_WHOLE := """kernel dither

image src: readonly
image dst

params:
    vec2 origin
    float levels
    float spread

import linear_srgb_color_space
import oklab_color_space

const float BAYER[16] = float[16](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0)

def dither():
    ivec2 at = pixel + ivec2(origin)
    vec4 here = image_load(src, pixel)
    vec3 lab = linear_srgb_to_oklab(here.rgb)
    float threshold = (BAYER[(at.y % 4) * 4 + at.x % 4] + 0.5) / 16.0 - 0.5
    float lightness = floor(lab.x * levels + threshold * spread + 0.5) / levels
    image_store(dst, pixel, vec4(oklab_to_linear_srgb(vec3(lightness, lab.y, lab.z)), here.a))
"""

## Every pixel takes the one five to the right and five below it, so the last
## row and column of a rectangle read past it.
const SHIFT_SHORT := """def pixel(ivec2 at) -> vec4:
    return src(at + ivec2(5, 5))
"""

const FLAT := Color(0.2, 0.4, 0.6, 1.0)
const GREY := Color(0.37, 0.37, 0.37, 1.0)

var _easel: SaEasel = null
var _doc: SaDocument = null
var _driver: KernelDriver = null


func before_each() -> void:
    _easel = SaEasel.create_default(Vector2i(512, 512))
    _doc = _easel.document
    _driver = KernelDriver.new(null)


func after_each() -> void:
    _easel.free()
    _easel = null
    _doc = null
    _driver = null


## A layer called *name*, its first chunk filled with *colour*.
func _filled(name: String, colour: Color) -> SaLayer:
    var layer := SaLayerOps.new(_doc).add(&"", null)
    layer.name = name
    layer.get_or_create_chunk(Vector2i.ZERO).clear(colour)
    return layer


## A layer called *name* with nothing in it.
func _empty(name: String) -> SaLayer:
    var layer := SaLayerOps.new(_doc).add(&"", null)
    layer.name = name
    return layer


## The texels of *layer*'s first chunk.
func _image(layer: SaLayer) -> Image:
    return SaExportScript.get_texture_image_float(layer.chunks[Vector2i.ZERO].field(SaFieldSpec.ALBEDO))


func _near(a: Color, b: Color) -> bool:
    return absf(a.r - b.r) < 1e-4 and absf(a.g - b.g) < 1e-4 and absf(a.b - b.b) < 1e-4 and absf(a.a - b.a) < 1e-4


func test_the_short_form_is_told_from_a_whole_kernel() -> void:
    assert_true(KernelDriver.CellKernel.is_pixel_form(DITHER_SHORT), "a def pixel with no kernel line is the short form")
    assert_false(KernelDriver.CellKernel.is_pixel_form(DITHER_WHOLE), "a source with a kernel line is a whole kernel")


func test_the_short_form_paints_what_the_whole_kernel_paints() -> void:
    _filled("Grey", GREY)
    var short_out := _empty("Short")
    var whole_out := _empty("Whole")
    var rect := [10, 20, 64, 48]
    var values := {"levels": 4.0, "spread": 1.0}

    var short := _driver.run_on(
        _doc, {"source": DITHER_SHORT, "name": "pixels", "layer": "Grey", "into": "Short", "rect": rect, "params": values}
    )
    var whole := _driver.run_on(
        _doc, {"source": DITHER_WHOLE, "name": "dither", "layer": "Grey", "into": "Whole", "rect": rect, "params": values}
    )

    assert_true(bool(short["ok"]), "the short form ran: %s" % [short])
    assert_true(bool(whole["ok"]), "the whole kernel ran: %s" % [whole])
    var short_image := _image(short_out)
    var whole_image := _image(whole_out)
    var differing := 0
    var levels_seen := {}
    for y in range(20, 68):
        for x in range(10, 74):
            if not _near(short_image.get_pixel(x, y), whole_image.get_pixel(x, y)):
                differing += 1
            levels_seen[snappedf(short_image.get_pixel(x, y).r, 0.001)] = true
    assert_eq(differing, 0, "every pixel of the rectangle agrees with the whole kernel's")
    assert_true(levels_seen.size() > 1, "and the dither made more than one value of the grey: %s" % [levels_seen.keys()])


func test_a_tap_past_the_rectangle_reads_the_canvas() -> void:
    _filled("Flat", FLAT)
    var out := _empty("Out")

    var verdict := _driver.run_on(
        _doc, {"source": SHIFT_SHORT, "name": "pixels", "layer": "Flat", "into": "Out", "rect": [100, 100, 20, 20]}
    )

    assert_true(bool(verdict["ok"]), "the short form ran: %s" % [verdict])
    var image := _image(out)
    assert_true(_near(image.get_pixel(119, 119), FLAT), "the last pixel read five past the rectangle as the canvas")
    assert_true(_near(image.get_pixel(120, 120), Color(0, 0, 0, 0)), "and nothing past the rectangle was written")


func test_the_params_open_at_the_uniforms_defaults() -> void:
    var verdict := _driver.run_on(null, {"source": DITHER_SHORT, "name": "pixels", "run": false})

    assert_true(bool(verdict["ok"]), "the short form compiled: %s" % [verdict])
    var defaults := {}
    for param: Dictionary in verdict["params"]:
        defaults[param["name"]] = param["default"]
    assert_eq(defaults, {"levels": 4.0, "spread": 1.0}, "each param opens at its uniform's default, origin left out")


func test_a_short_form_error_names_the_cells_own_line() -> void:
    var broken := SHIFT_SHORT.replace("src(at + ivec2(5, 5))", "src(at + no_such_thing)")

    var verdict := _driver.run_on(null, {"source": broken, "name": "pixels", "run": false})

    assert_false(bool(verdict["ok"]), "a body that does not compile is refused")
    assert_eq(int(verdict["line"]), 2, "on the cell's own second line: %s" % [verdict.get("error")])


func test_a_uniform_of_a_type_a_push_constant_cannot_hold_is_refused_by_line() -> void:
    var broken := "uniform mat3 weights\n\n" + SHIFT_SHORT

    var verdict := _driver.run_on(null, {"source": broken, "name": "pixels", "run": false})

    assert_false(bool(verdict["ok"]), "the source is refused before it is compiled")
    assert_eq(int(verdict["line"]), 1, "naming the uniform's line: %s" % [verdict.get("error")])
