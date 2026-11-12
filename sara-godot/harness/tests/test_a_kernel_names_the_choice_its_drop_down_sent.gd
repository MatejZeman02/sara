## A notebook cell's `hint_enum` choices are constants of their index in the
## `kernel` step's kernel, so a body that branches on `DITHER_WHITE_NOISE` takes
## the branch the drop-down's index names, and the labels the drop-down draws
## are the ones written, the constants renaming nothing.
##
## Built like the matrix suite beside it: the driver with no run, handed the
## document, and each pixel read back the way an export does, the one readback
## a test may make. The names' rules and refusals are asked without a device in
## `core/custom-shader/dialect/tests/test_each_choice_of_a_hint_enum_is_a_named_constant.gd`.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const KernelDriver := preload("res://harness/sa_kernel_driver.gd")
const PixelSource := preload("res://core/custom-shader/dialect/sa_pixel_source.gd")
const SaExportScript = preload("res://core/export/sa_export.gd")

## Lesson 1's kind of switch, with a `BAYER` of the body's own beside the label
## "Bayer", which is why a constant's name leads with its parameter's.
const SWITCHED := """uniform int dither: hint_enum("Bayer", "White noise", "Off") = 0

const float BAYER[4] = float[4](0.0, 2.0, 3.0, 1.0)

def pixel(ivec2 at) -> vec4:
    vec4 here = src(at)
    if dither == DITHER_BAYER:
        return vec4(1.0, 0.0, BAYER[0], here.a)
    if dither == DITHER_WHITE_NOISE:
        return vec4(0.0, 1.0, 0.0, here.a)
    if dither == DITHER_OFF:
        return here
    return vec4(0.0, 0.0, 1.0, here.a)
"""

## A cell with no `hint_enum`, whose kernel text holds no constant.
const PLAIN := """uniform float level: hint_range(0, 1) = 0.5

def pixel(ivec2 at) -> vec4:
    return src(at) * level
"""

const PAINT := Color(0.2, 0.4, 0.6, 1.0)

var _easel: SaEasel = null
var _doc: SaDocument = null
var _driver: KernelDriver = null


func before_each() -> void:
    _easel = SaEasel.create_default(Vector2i(1024, 1024))
    _doc = _easel.document
    _driver = KernelDriver.new(null)


func after_each() -> void:
    _easel.free()
    _easel = null
    _doc = null
    _driver = null


## Each index the drop-down sends takes the branch its label's constant names,
## over a layer of one colour.
func test_each_index_takes_the_branch_of_its_named_constant() -> void:
    var paint := SaLayerOps.new(_doc).add(&"", null)
    paint.name = "Paint"
    paint.get_or_create_chunk(Vector2i(0, 0)).clear(PAINT)
    var expected: Array[Color] = [Color(1.0, 0.0, 0.0, 1.0), Color(0.0, 1.0, 0.0, 1.0), PAINT]
    for index in expected.size():
        var into := "Choice %d" % index
        var ran := _driver.run_on(
            _doc,
            {
                "source": SWITCHED,
                "name": "switched",
                "layer": "Paint",
                "into": into,
                "rect": [0, 0, 256, 256],
                "params": {"dither": index}
            }
        )
        assert_true(bool(ran["ok"]), "the cell ran with dither %d: %s" % [index, ran])
        var written := _texel(into, 100, 100)
        assert_true(written.is_equal_approx(expected[index]), "index %d writes %s, read %s" % [index, expected[index], written])


## The verdict answers `dither` as the int it was, and the labels the drop-down
## draws are read from the cell's text as written.
func test_the_drop_down_keeps_its_labels() -> void:
    var verdict := _driver.run_on(_doc, {"source": SWITCHED, "name": "switched", "run": false})
    assert_true(bool(verdict["ok"]), "the cell compiled: %s" % [verdict])
    var params: Array = verdict.get("params", [])
    var names := params.map(func(param: Dictionary) -> String: return str(param["name"]))
    assert_eq(names, ["dither"], "the one param, no constant among them")
    var dither: Dictionary = params[0]
    assert_eq([str(dither["type"]), int(dither["default"])], ["int", 0], "an int opening on its first entry")
    var choices: PackedStringArray = PixelSource.uniforms(SWITCHED)[0]["choices"]
    assert_eq(Array(choices), ["Bayer", "White noise", "Off"], "the labels as written")


## The kernel the step writes for a cell with no `hint_enum` declares no
## constant, so its text is the wrapper it was.
func test_a_cell_with_no_hint_enum_compiles_to_the_text_it_did() -> void:
    var verdict := _driver.run_on(_doc, {"source": PLAIN, "name": "plain", "run": false})
    assert_true(bool(verdict["ok"]), "the cell compiled: %s" % [verdict])
    var cell: KernelDriver.CellKernel = _driver._compiled["plain:%s" % PLAIN.md5_text()]
    var written := FileAccess.get_file_as_string(cell.path)
    assert_false(written.is_empty(), "the generated kernel was written")
    assert_false(written.contains("const "), "and declares no constant")
    var wrapped := PixelSource.wrap("plain", cell.include_name, PixelSource.uniforms(PLAIN))
    assert_eq(written.split("\n").size(), wrapped.split("\n").size(), "as many lines as the wrapper with nothing added")


## The texel at *x*, *y* of the layer called *name*, in its first chunk.
func _texel(name: String, x: int, y: int) -> Color:
    var layer := KernelDriver.layer_of(_doc, name)
    var chunk_pos := Vector2i(floori(float(x) / SaChunk.SIZE), floori(float(y) / SaChunk.SIZE))
    if layer == null or not layer.chunks.has(chunk_pos):
        return Color(0, 0, 0, 0)
    var image := SaExportScript.get_texture_image_float(layer.chunks[chunk_pos].field(SaFieldSpec.ALBEDO))
    return image.get_pixel(x % SaChunk.SIZE, y % SaChunk.SIZE)
