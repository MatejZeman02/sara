## A matrix uniform: `uniform float weights[9]` is a grid of
## numbers a convolution reads row by row, `[25]` and `[49]` the bigger grids,
## and one too wide for the push constant runs from a storage buffer the
## dialect moves it into on its own.
##
## The kernels are pixel functions written to `user://`, the way
## `test_pixel_function.gd` writes its own, and each one runs over a texture
## whose every texel differs, so a weight read from the wrong entry moves a
## texel this suite reads back. The readback is the one hard rule 1 permits a
## test, and nothing the wrapper does leaves VRAM.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const PixelFunction := preload("res://core/custom-shader/compiler/sa_pixel_function.gd")
const PixelSource := preload("res://core/custom-shader/dialect/sa_pixel_source.gd")
const Dialect := preload("res://core/custom-shader/dialect/sa_dialect.gd")
const KernelSource := preload("res://core/custom-shader/dialect/sa_kernel_source.gd")
const BindingSlots := preload("res://core/custom-shader/sa_binding_slots.gd")

const F32 := RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT

## Off the canvas's corner, so `src` reading through `origin` is part of what
## the two kernels of a pair agree on.
const REGION := Rect2i(32, 16, 16, 16)

## How far two kernels that mean the same sum may differ, a weight of a ninth
## times a texel against the texel over nine.
const SAME: float = 0.00001

## A convolution of any odd side with its weights in a matrix, and the same
## box blur with its weight written as a constant. `SIDE` and `LENGTH` are
## filled in per size.
const MATRIX_SOURCE := """uniform float weights[LENGTH]

def pixel(ivec2 at) -> vec4:
    vec4 sum = vec4(0.0)
    for row in range(0, SIDE):
        for column in range(0, SIDE):
            sum += src(at + ivec2(column - SIDE / 2, row - SIDE / 2)) * weights[row * SIDE + column]
    return sum
"""
const CONSTANT_SOURCE := """def pixel(ivec2 at) -> vec4:
    vec4 sum = vec4(0.0)
    for row in range(0, SIDE):
        for column in range(0, SIDE):
            sum += src(at + ivec2(column - SIDE / 2, row - SIDE / 2)) / float(LENGTH)
    return sum
"""

## A 3 by 3 written as its three rows, Godot's braces over four lines, which
## the dialect's rule for an open bracket reads as one declaration.
const ROWS_SOURCE := """uniform float weights[9] = {
    0.0, 0.0, 0.0,
    0.0, 0.0, 2.0,
    0.0, 0.0, 0.0}

def pixel(ivec2 at) -> vec4:
    vec4 sum = vec4(0.0)
    for row in range(0, 3):
        for column in range(0, 3):
            sum += src(at + ivec2(column - 1, row - 1)) * weights[row * 3 + column]
    return sum
"""

## The function under the declaration of the refusal cases, so the only problem
## left is the declaration's.
const PIXEL_TAIL := "\ndef pixel(ivec2 at) -> vec4:\n    return src(at)\n"

# --- The declaration ---------------------------------------------------------


## The parse a widget and the wrapper read: the length, a default as its numbers
## row by row in either spelling, and with none a one in the middle.
func test_a_matrix_reads_its_length_and_its_numbers_row_by_row() -> void:
    var bare: Dictionary = PixelSource.uniforms("uniform float weights[9]\n")[0]
    assert_eq(int(bare["length"]), 9, "the length is the count the brackets declared")
    assert_eq(bare["default"], [0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0], "with no default, a one in the middle")
    var seven: Array = PixelSource.uniforms("uniform float weights[49]\n")[0]["default"]
    assert_eq(seven.find(1.0), 24, "the middle of a 7 by 7 is the twenty-fifth entry")
    assert_eq(seven.count(1.0), 1, "and it is the only one")

    var braced: Dictionary = PixelSource.uniforms("uniform float w[4] = {1.0, 2.0, 3.0, 4.0}\n")[0]
    assert_eq(braced["default"], [1.0, 2.0, 3.0, 4.0], "Godot's braces read in the order written")
    var built: Dictionary = PixelSource.uniforms("uniform float w[4] = float[4](4.0, 3.0, 2.0, 1.0)\n")[0]
    assert_eq(built["default"], [4.0, 3.0, 2.0, 1.0], "and so does GLSL's constructor")
    assert_eq(PixelSource.uniforms("uniform float w[4] = float[](1, 1, 1, 1)\n")[0]["default"], [1.0, 1.0, 1.0, 1.0])

    var rows: Dictionary = PixelSource.uniforms(ROWS_SOURCE)[0]
    assert_eq(rows["default"], [0.0, 0.0, 0.0, 0.0, 0.0, 2.0, 0.0, 0.0, 0.0], "a default written as its rows")
    assert_eq(int(rows["line"]), 1, "names the line it opens on")
    var body := PixelSource.body(ROWS_SOURCE).split("\n")
    assert_eq(body.size(), ROWS_SOURCE.split("\n").size(), "the body keeps the file's count of lines")
    for line in 4:
        assert_eq(body[line], "", "and every line the declaration spans leaves it, line %d" % (line + 1))
    assert_eq(Array(PixelSource.problems(ROWS_SOURCE, "rows")), [], "nothing is wrong with it")
    assert_true(
        PixelSource.wrap("k", "m_pixels/k", PixelSource.uniforms(ROWS_SOURCE)).contains("    float weights[9]\n"),
        "and the wrapper declares the field with its length"
    )


## A length that is not a square is refused with its line, the way a type outside
## the list is, and so is every other matrix this door cannot draw.
func test_a_matrix_that_cannot_be_a_grid_is_refused_with_its_line() -> void:
    var refused := {
        "uniform float weights[6]": "not a square",
        "uniform int weights[9]": "a matrix of float",
        "uniform vec3 weights[9]": "a matrix of float",
        "uniform float weights[]": "a length this cannot read",
        "uniform float weights[0]": "a length this cannot read",
        "uniform float weights[9] = {1.0, 2.0}": "cannot read as 9 numbers",
        "uniform float weights[4] = float[9](1, 2, 3, 4)": "cannot read as 4 numbers",
        "uniform float weights[9]: hint_range(0, 1)": "takes none",
    }
    for line: String in refused:
        var said := PixelSource.problems("\n" + line + "\n" + PIXEL_TAIL, "refused")
        assert_eq(said.size(), 1, "one problem for `%s`: %s" % [line, said])
        if said.size() == 1:
            assert_true(said[0].contains("line 2"), "on the line it is written on: %s" % said[0])
            assert_true(said[0].contains(String(refused[line])), "saying %s: %s" % [refused[line], said[0]])


# --- The transpiler's move -----------------------------------------------------


## A block past 128 bytes gives up its widest array to a buffer the kernel still
## reads bare, the line it was declared on goes out empty, and a 3 by 3 stays.
func test_a_matrix_that_does_not_fit_moves_into_a_buffer_and_a_small_one_stays() -> void:
    var wide := "params:\n    vec2 origin\n    float weights[49]\n    float gain\n"
    var moved := Dialect.transpile(wide)
    assert_eq(moved.split("\n").size(), wide.split("\n").size(), "the count of lines holds")
    assert_eq(moved.split("\n")[2], "    ", "the matrix's own line goes out empty")
    assert_true(
        moved.contains("readonly buffer %sweights { float weights[49]; };" % KernelSource.MOVED_FIELD_PREFIX),
        "into an anonymous buffer named for it: %s" % moved
    )
    var layout := KernelSource.extract_push_constant_layout(moved)
    assert_eq(layout.map(func(field: Dictionary) -> String: return str(field["name"])), ["origin", "gain", "_pad_0", ""])
    assert_eq(int(layout[-1]["offset"]), 16, "and the block that is left is the two scalars, padded")

    var small := Dialect.transpile("params:\n    vec2 origin\n    float weights[9]\n")
    assert_false(small.contains("buffer"), "a 3 by 3 fits beside the origin and stays")
    assert_eq(int(KernelSource.extract_push_constant_layout(small)[1]["length"]), 9, "as a field of nine")

    var two := Dialect.transpile("params:\n    vec2 origin\n    float a[25]\n    float b[25]\n")
    assert_true(two.contains("buffer %sa {" % KernelSource.MOVED_FIELD_PREFIX), "of two 5 by 5s the first moves")
    assert_false(two.contains("buffer %sb {" % KernelSource.MOVED_FIELD_PREFIX), "and the second then fits")

    var alone := Dialect.transpile("image dst\nparams:\n    float weights[49]\nimage src\n")
    assert_false(alone.contains("push_constant"), "a block left with nothing goes, header and brace")
    var bindings: Array[String] = []
    for line in alone.split("\n"):
        bindings.append(line.substr(line.find("binding = ") + 10, 1) if line.contains("binding = ") else "")
    assert_eq(bindings, ["0", "", "1", "2", ""] as Array[String], "and the buffer takes the next binding in declaration order")

    var named := Dialect.transpile("params p:\n    vec2 origin\n    float weights[49]\n")
    assert_false(named.contains("buffer"), "a block with an instance name keeps its field, `p.weights` reads no buffer")


# --- The run --------------------------------------------------------------------


## The unit's first sentence: a 3 by 3 box blur declared as `float[9]` paints
## what the same blur written with constants paints, and its nine numbers ride
## in the push constant.
func test_a_3_by_3_box_blur_in_a_matrix_equals_the_blur_written_with_constants() -> void:
    var matrix := _compiled("d70_matrix_3", _sized(MATRIX_SOURCE, 3))
    var constant := _compiled("d70_constant_3", _sized(CONSTANT_SOURCE, 3))
    var ninth := []
    ninth.resize(9)
    ninth.fill(1.0 / 9.0)
    _assert_same(_run(matrix, {"weights": ninth}), _run(constant, {}), "the matrix blur and the constant one")

    var layout := GlobalShaderCompiler.push_constant_layout(matrix.shader_name)
    var fields := layout.map(func(field: Dictionary) -> String: return str(field["name"]))
    assert_true(fields.has("weights"), "the nine numbers ride in the push constant: %s" % [fields])
    assert_eq(BindingSlots.moved_params(GlobalShaderCompiler.binding_layout(matrix.shader_name)), [], "and nothing moved")


## A 7 by 7 is 196 bytes and cannot ride there at all. It runs from a storage
## buffer, the push constant is within 128 bytes, and the blur is the constant
## one's all the same.
func test_a_7_by_7_runs_from_a_storage_buffer_and_the_push_constant_stays_within_128_bytes() -> void:
    var matrix := _compiled("d70_matrix_7", _sized(MATRIX_SOURCE, 7))
    var constant := _compiled("d70_constant_7", _sized(CONSTANT_SOURCE, 7))
    var share := []
    share.resize(49)
    share.fill(1.0 / 49.0)
    _assert_same(_run(matrix, {"weights": share}), _run(constant, {}), "the 7 by 7 from a buffer and the constant one")

    var bytes := GlobalShaderCompiler.push_constant_bytes(matrix.shader_name)
    assert_true(bytes > 0 and bytes <= 128, "the push constant is within 128 bytes: %d" % bytes)
    var layout := GlobalShaderCompiler.push_constant_layout(matrix.shader_name)
    assert_false(layout.any(func(field: Dictionary) -> bool: return field["name"] == "weights"), "and holds no weight")
    var moved := BindingSlots.moved_params(GlobalShaderCompiler.binding_layout(matrix.shader_name))
    assert_eq(moved.size(), 1, "one field moved")
    if moved.size() == 1:
        assert_eq(str(moved[0]["name"]), "weights", "the matrix")
        assert_eq(int(moved[0]["layout"][-1]["offset"]), 196, "forty-nine floats packed tight, std430's own stride")


## The order the grid writes is the order the kernel reads: a single one at row
## r and column c reads the source r and c from the middle, through the push
## constant and through the buffer alike.
func test_a_matrix_is_read_row_by_row_from_either_home() -> void:
    for side: int in [3, 7]:
        var matrix := _compiled("d70_matrix_%d" % side, _sized(MATRIX_SOURCE, side))
        var weights := []
        weights.resize(side * side)
        weights.fill(0.0)
        # Row 0, the column at the right edge: up a row by half the side and
        # across to the right by as much.
        weights[side - 1] = 1.0
        var read := _run(matrix, {"weights": weights})
        var source := _texels(_pattern())
        var reach := floori(side / 2.0)
        var at := Vector2i(8, 8)
        assert_true(
            _texel_of(read, at).is_equal_approx(_texel_of(source, at + Vector2i(reach, -reach))),
            "a %d by %d with its one at row 0 and the last column reads up and to the right" % [side, side]
        )


## The default with no number given: the one in the middle, which leaves the
## picture as it was, for the small matrix and for the moved one.
func test_with_no_default_a_matrix_leaves_the_picture_unchanged() -> void:
    for side: int in [3, 7]:
        var matrix := _compiled("d70_matrix_%d" % side, _sized(MATRIX_SOURCE, side))
        _assert_same(_run(matrix, {}), _texels(_pattern()), "a %d by %d at its default" % [side, side])


## The rows a file wrote are the numbers the kernel gets: a two at row 1 and
## column 2 doubles the texel to the right.
func test_a_default_written_as_its_rows_reaches_the_kernel() -> void:
    var rows := _compiled("d70_rows", ROWS_SOURCE)
    var read := _run(rows, {})
    var source := _texels(_pattern())
    var at := Vector2i(5, 9)
    assert_true(_texel_of(read, at).is_equal_approx(_texel_of(source, at + Vector2i(1, 0)) * 2.0), "twice the texel to the right")


# --- Helpers ---------------------------------------------------------------------


## *template* with its side and length written in.
func _sized(template: String, side: int) -> String:
    return template.replace("LENGTH", str(side * side)).replace("SIDE", str(side))


## *source* written to `user://` as *stem* and compiled. Untyped at the call for
## the reason `test_pixel_function.gd` gives.
func _compiled(stem: String, source: String) -> PixelFunction:
    var path := SaDataRoot.path(stem + ".gmacs")
    var file := FileAccess.open(path, FileAccess.WRITE)
    file.store_string(source)
    file.close()
    var written := PixelFunction.new(path)
    assert_eq(Array(written.problems), [], "%s has nothing wrong with it" % stem)
    assert_true(written.compile(), "%s compiled: %s" % [stem, written.first_error()])
    return written


## The source every run reads: each texel a different colour, so a weight taken
## from the wrong entry takes a different texel.
func _pattern() -> SaTexture:
    var texels := PackedFloat32Array()
    texels.resize(REGION.size.x * REGION.size.y * 4)
    for y in REGION.size.y:
        for x in REGION.size.x:
            var at := (y * REGION.size.x + x) * 4
            texels[at] = float(x) / float(REGION.size.x)
            texels[at + 1] = float(y) / float(REGION.size.y)
            texels[at + 2] = float((x * 7 + y * 3) % 11) / 11.0
            texels[at + 3] = 1.0
    var source := SaTexture.new(REGION.size, F32)
    GlobalShaderCompiler.get_rd().texture_update(source.rid, 0, texels.to_byte_array())
    return source


## What *written* paints over the pattern with *values*, read back whole.
func _run(written: PixelFunction, values: Dictionary) -> PackedFloat32Array:
    var target := SaTexture.new(REGION.size, F32)
    target.clear(Color(1, 0, 1, 1))
    written.run(_pattern(), target, REGION, values)
    return _texels(target)


func _texels(texture: SaTexture) -> PackedFloat32Array:
    return GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0).to_float32_array()


func _texel_of(texels: PackedFloat32Array, at: Vector2i) -> Color:
    var base := (at.y * REGION.size.x + at.x) * 4
    return Color(texels[base], texels[base + 1], texels[base + 2], texels[base + 3])


## Every texel of *a* within SAME of *b*'s, said once with the first that is not.
func _assert_same(a: PackedFloat32Array, b: PackedFloat32Array, what: String) -> void:
    assert_eq(a.size(), b.size(), "%s cover the same texels" % what)
    for i in mini(a.size(), b.size()):
        if absf(a[i] - b[i]) > SAME:
            assert_true(false, "%s differ at float %d: %f against %f" % [what, i, a[i], b[i]])
            return
    assert_true(true, "%s paint the same picture" % what)
