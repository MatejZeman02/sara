## A short form cell that declares a further layer with `image blue: readonly`
## runs, and reads both layers, `src` the first and `blue` the second.
##
## The fault was a binding clash: the wrapper's `sa_source` and the body's
## `blue` were each numbered 0, in two texts, and the layout kept `blue`. Built
## like the short form suite: the driver with no run, handed the document, and each pixel
## read back the way an export does, the one readback a test may make.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const KernelDriver := preload("res://harness/sa_kernel_driver.gd")
const PixelFunction := preload("res://core/custom-shader/compiler/sa_pixel_function.gd")
const SaExportScript = preload("res://core/export/sa_export.gd")

## Both reads in one line, the second by brackets as a written kernel reads it.
const SUM := """image blue: readonly

def pixel(ivec2 at) -> vec4:
    return src(at) + blue[at]
"""

## The second layer read by the call rather than the brackets.
const LOADED := """image blue: readonly    # the noise

def pixel(ivec2 at) -> vec4:
    return image_load(blue, at - ivec2(origin))
"""

## A pixel function a filter would record as a pass, which no further layer can
## reach.
const PASS_WITH_AN_IMAGE := """uniform float amount = 1.0

image blue: readonly

def pixel(ivec2 at) -> vec4:
    return src(at) * amount
"""

const RED := Color(0.25, 0.0, 0.0, 0.25)
const BLUE := Color(0.0, 0.0, 0.5, 0.5)

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


func _filled(name: String, colour: Color) -> SaLayer:
    var layer := SaLayerOps.new(_doc).add(&"", null)
    layer.name = name
    layer.get_or_create_chunk(Vector2i.ZERO).clear(colour)
    return layer


func _texel(layer: SaLayer, x: int, y: int) -> Color:
    var image := SaExportScript.get_texture_image_float(layer.chunks[Vector2i.ZERO].field(SaFieldSpec.ALBEDO))
    return image.get_pixel(x, y)


func _near(a: Color, b: Color) -> bool:
    return absf(a.r - b.r) < 1e-4 and absf(a.g - b.g) < 1e-4 and absf(a.b - b.b) < 1e-4 and absf(a.a - b.a) < 1e-4


func test_the_kernel_reads_both_layers_in_one_run() -> void:
    _filled("Paint", RED)
    _filled("Noise", BLUE)
    var out := _filled("Out", Color(0, 0, 0, 0))

    var verdict := _driver.run_on(
        _doc,
        {"source": SUM, "name": "pixels", "layer": "Paint", "into": "Out", "rect": [8, 8, 32, 32], "inputs": {"blue": "Noise"}}
    )

    assert_true(bool(verdict["ok"]), "the cell ran: %s" % [verdict])
    var at := _texel(out, 20, 20)
    assert_true(_near(at, RED + BLUE), "the texel holds the sum of the two layers: %s" % [at])
    assert_false(_near(at, RED * 2.0), "so the second read is not the first layer read twice")
    assert_false(_near(at, BLUE * 2.0), "and the first read is not the second layer")


func test_the_second_layer_reads_by_the_call_as_well() -> void:
    _filled("Paint", RED)
    _filled("Noise", BLUE)
    var out := _filled("Out", Color(0, 0, 0, 0))

    var verdict := _driver.run_on(
        _doc,
        {"source": LOADED, "name": "pixels", "layer": "Paint", "into": "Out", "rect": [0, 0, 16, 16], "inputs": {"blue": "Noise"}}
    )

    assert_true(bool(verdict["ok"]), "the cell ran: %s" % [verdict])
    assert_true(
        _near(_texel(out, 4, 4), BLUE), "image_load of the declared name reads the second layer: %s" % [_texel(out, 4, 4)]
    )


func test_the_three_images_sit_at_three_bindings() -> void:
    var cell := KernelDriver.CellKernel.new("pixels", SUM)

    assert_eq(cell.error, "", "the cell compiled")
    var layout := GlobalShaderCompiler.binding_layout(cell.shader_name)
    var where := {}
    for binding: int in layout:
        where[str(layout[binding].get("name", ""))] = binding
    for image: String in ["sa_source", "sa_target", "blue"]:
        assert_true(where.has(image), "the layout holds %s: %s" % [image, where])
    var bindings := {}
    for image: String in ["sa_source", "sa_target", "blue"]:
        bindings[where.get(image, -1)] = true
    assert_eq(bindings.size(), 3, "at three different bindings: %s" % [where])


func test_a_pass_that_declares_an_image_is_refused_at_its_line() -> void:
    var pass_form := PixelFunction.new("res://modules/none/pass_with_an_image.gmacs", PASS_WITH_AN_IMAGE, true)
    var named := 0
    for problem: String in pass_form.problems:
        if problem.begins_with("line 3 ") and problem.contains("blue"):
            named += 1

    assert_eq(named, 1, "the image line is a problem naming line 3: %s" % [pass_form.problems])


func test_an_image_named_as_the_wrapper_names_its_own_is_refused() -> void:
    var cell := KernelDriver.CellKernel.new(
        "pixels", "image sa_source: readonly\n\ndef pixel(ivec2 at) -> vec4:\n    return src(at)\n"
    )

    assert_true(cell.error.contains("sa_source"), "the cell is refused naming the image: %s" % cell.error)
    assert_eq(cell.line, 1, "at its own line")
