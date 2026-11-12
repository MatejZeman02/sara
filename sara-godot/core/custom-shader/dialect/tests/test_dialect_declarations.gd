## What the dialect's four declarations become, and the spec's own example all
## the way to the front end.
##
## The other half of `test_dialect.gd`, split off when that file reached
## gdlint's cap of 32 public methods for the third time. The seam is the
## one that file's own header asks for: the shapes of the language on one side,
## what a kernel's preamble comes to on the other. Nothing was rewritten in the
## move, so the two files together assert exactly what the one did.
##
## The declarations are the half worth keeping together, because each is checked
## against a line of the dialect's own page rather than against a fixture
## written beside it, and the example at the end is the same claim made once
## more over a whole file.
extends "res://tests/test_framework.gd"

const Dialect := preload("res://core/custom-shader/dialect/sa_dialect.gd")
const KernelSource := preload("res://core/custom-shader/dialect/sa_kernel_source.gd")
const Bindings := preload("res://core/custom-shader/compiler/sa_bindings.gd")

## The spec's own example, the one the kernel language section shows. Rewritten
## with the dialect's names: `@workgroup_size`, the snake built-ins, and
## `pixel` in place of the `ivec2 at = ivec2(gl_GlobalInvocationID.xy)` line
## thirty-five of the tree's kernels open with.
const BLUR_X := """kernel blur_x
import gaussian

image src: readonly
image dst

params:
    float sigma
    int radius


@workgroup_size(8, 8)
def blur_x():
    vec4 sum = vec4(0.0)
    float weight = 0.0
    for i in range(-radius, radius + 1):
        float w = gaussian(float(i), sigma)
        sum += w * image_load(src, pixel + ivec2(i, 0))
        weight += w
    image_store(dst, pixel, sum / weight)


def luminance(vec3 c) -> float:
    return dot(c, vec3(0.2126, 0.7152, 0.0722))
"""

## What `GMACS.md`'s four declarations come out as, in the GLSL glslang is handed.
##
## `image canvas`, `sampler tip`, `buffer table: float values[]` and `params:`
## have to reach exactly this, binding for binding, which is the whole of what
## the declarations half of the pass promises. It is GLSL because that is what
## the pass produces, not because anything is written that way: `GMACS.md`
## writes the dialect and nothing else.
const GMACS_PREAMBLE := """layout( SA_STORAGE_FORMAT, set = 0, binding = 0 ) uniform image2D canvas;
layout( set = 0, binding = 1 ) uniform sampler2D tip;
layout( std430, set = 0, binding = 2 ) buffer Table { float values[]; } table;
layout( push_constant, std430 ) uniform Params
{
    vec2 offset;
    float opacity;
    float pad;
}
p;
"""

## A kernel written in GLSL, the form the compiler still reads.
##
## Nothing under `shaders/compute/` is written this way, so this is a fixture rather than a sample of the tree. What it
## holds the pass to is the promise that outlives the sweep: a file carrying a
## GLSL marker goes through untouched, byte for byte, which is what lets a
## module or a student keep writing GLSL.
const GLSL_KERNEL := """#kernel paint

layout( SA_STORAGE_FORMAT, set = 0, binding = 0 ) uniform image2D canvas;

[numthreads( 8, 8, 1 )] void paint() {
    imageStore(canvas, ivec2(gl_GlobalInvocationID.xy), vec4(1.0));
}
"""


## The count of lines in and out, which every case below asserts through here.
func _lines_held(source: String, message: String) -> String:
    var glsl := Dialect.transpile(source)
    assert_eq(glsl.split("\n").size(), source.split("\n").size(), message)
    return glsl


# --- The declarations -----------------------------------------------------------


func test_an_image_takes_the_storage_token_unless_it_names_a_format() -> void:
    var glsl := _lines_held("image canvas\n", "One line")

    assert_eq(
        glsl,
        "layout( SA_STORAGE_FORMAT, set = 0, binding = 0 ) uniform image2D canvas;\n",
        "An image that follows the document writes the token the compiler substitutes"
    )
    assert_eq(
        Dialect.transpile("image mask: r32f, readonly\n"),
        "layout( r32f, set = 0, binding = 0 ) uniform readonly image2D mask;\n",
        "A fixed format wins over the token, and the memory qualifier follows uniform"
    )


func test_a_sampler_and_a_buffer_take_their_glsl_shapes() -> void:
    var lines := Dialect.transpile("sampler tip\nbuffer table: float values[]\n").split("\n")

    assert_eq(lines[0], "layout( set = 0, binding = 0 ) uniform sampler2D tip;", "A sampled texture carries no format")
    assert_eq(
        lines[1],
        "layout( std430, set = 0, binding = 1 ) buffer Table { float values[]; } table;",
        "A storage buffer is std430 with a block name of its own"
    )


## The binding numbers are the whole reason the GDScript side can bind by name,
## and they are the order of declaration and nothing else. The params block is
## not a binding and takes no number, which a file declaring it between two
## images would otherwise lose.
func test_bindings_are_numbered_in_declaration_order_and_params_takes_none() -> void:
    var glsl := Dialect.transpile("image src\nsampler tip\nimage dst\nbuffer table: float values[]\n")
    var around_params := Dialect.transpile("image src\nparams:\n    float sigma\nimage dst\n")

    assert_true("binding = 0 ) uniform image2D src;" in glsl, "src is first")
    assert_true("binding = 1 ) uniform sampler2D tip;" in glsl, "tip is second")
    assert_true("binding = 2 ) uniform image2D dst;" in glsl, "dst is third")
    assert_true("binding = 3 ) buffer Table" in glsl, "the buffer is fourth")
    assert_true("binding = 1 ) uniform image2D dst;" in around_params, "dst is second, not third")


## GLSL's own anonymous block, so `sigma` in the body is GLSL reading a block
## member and the pass rewrites no expression to make it work.
func test_params_becomes_an_anonymous_push_constant_block() -> void:
    var glsl := _lines_held("params:\n    float sigma\n    int radius\n", "Three lines in, three out")

    assert_eq(
        glsl,
        "layout( push_constant, std430 ) uniform Params {\n    float sigma;\n    int radius; float _pad_0; float _pad_1;};\n",
        "The block closes on its last field, the way every block here does, and the pad rides with the brace"
    )


## A field declares its slider the way a Godot shader declares a uniform's,
## `float scale: hint_range(2, 64)`, and the hint is the slider's alone. The
## block compiles to the GLSL it compiled to when the range was a `# range`
## comment, that comment aside, where the colon read as a header's had made the
## field a one-line block headed `float scale`. A value after the hint is
## left for glslang to refuse, as it is with no hint.
func test_a_params_fields_hint_compiles_to_what_its_range_comment_did() -> void:
    var hinted := _lines_held(
        "params:\n    float scale: hint_range(2, 64)\n    int seeds: hint_range(1, 32, 1)\n    vec2 centre\n",
        "Four lines in, four out"
    )
    var commented := Dialect.transpile(
        "params:\n    float scale    # range 2 64\n    int seeds    # range 1 32\n    vec2 centre\n"
    )

    assert_eq(
        hinted,
        commented.replace("  // range 2 64", "").replace("  // range 1 32", ""),
        "The hinted block is the commented one without its comments"
    )
    assert_eq(
        hinted,
        "layout( push_constant, std430 ) uniform Params {\n    float scale;\n    int seeds;\n    vec2 centre;};\n",
        "Which is each field and nothing of its hint"
    )
    assert_eq(
        KernelSource.extract_push_constant_layout(hinted),
        KernelSource.extract_push_constant_layout(commented),
        "So the block the compiler lays out is the same one"
    )
    assert_true(
        Dialect.transpile("params p:\n    float scale: hint_range(2, 64)\n").contains("    float scale;"),
        "A named block takes the hint off the same way"
    )
    assert_true(
        Dialect.transpile("params:\n    float scale: hint_range(2, 64) = 8.0\n").contains("    float scale = 8.0;"),
        "And a value written after the hint reaches glslang, which refuses it as it would without one"
    )


## A pixel function's `uniform` line loses its hint the same way. The wrapper
## blanks the line before its import is compiled, but the shader walk reads
## every `.gmacs` in the tree at boot, the shipped patterns among them, and the
## hinted line there was a header this pass did not know.
func test_a_uniform_lines_hint_never_reaches_glsl() -> void:
    var hinted := _lines_held(
        "uniform float tile: hint_range(1, 4096) = 256.0\ndef pixel(ivec2 at) -> vec4:\n    return vec4(tile)\n", "Three lines"
    )
    var commented := Dialect.transpile(
        "uniform float tile = 256.0   # range 1 4096\ndef pixel(ivec2 at) -> vec4:\n    return vec4(tile)\n"
    )

    assert_eq(hinted.split("\n")[0], "uniform float tile = 256.0;", "The line is what it was with the comment")
    assert_eq(hinted, commented.replace("  // range 1 4096", ""), "And so is the rest of the file")


func test_params_with_a_name_keeps_the_instance() -> void:
    var glsl := Dialect.transpile("params p:\n    float sigma\n")

    assert_true(
        glsl.ends_with("    float sigma; float _pad_0; float _pad_1; float _pad_2;} p;\n"),
        "A file that wants the p. prefix declares the instance, and is padded like any other"
    )


## The four declarations against the four `layout(...)` lines
## `GMACS.md`'s "What a kernel can be handed" documents, which is the contract
## the dialect is a shorter spelling of and not a new one. Numbered 0, 1 and 2
## there, so the dialect that must produce them declares them in that order.
##
## The last half is what makes them a contract rather than three strings: the
## same `extract_layout` the compiler runs on a hand-written preamble reads the
## transpiled one to the same Dictionary, kind, name, format and the buffer's
## two names, so `SaCompute` refuses a wrong bind by name either way.
func test_the_four_declarations_are_the_lines_gmacs_documents() -> void:
    var glsl := Dialect.transpile(
        "image canvas\nsampler tip\nbuffer table: float values[]\nparams p:\n    vec2 offset\n    float opacity\n"
    )
    var lines := glsl.split("\n")

    assert_eq(lines[0], "layout( SA_STORAGE_FORMAT, set = 0, binding = 0 ) uniform image2D canvas;", "The storage image")
    assert_eq(lines[1], "layout( set = 0, binding = 1 ) uniform sampler2D tip;", "The sampled texture")
    assert_eq(lines[2], "layout( std430, set = 0, binding = 2 ) buffer Table { float values[]; } table;", "The storage buffer")
    assert_eq(lines[3], "layout( push_constant, std430 ) uniform Params {", "The push constant, opened")

    assert_eq(
        Bindings.extract_layout(glsl), Bindings.extract_layout(GMACS_PREAMBLE), "The compiler reads both preambles the same way"
    )
    var type_and_offset := func(f: Dictionary) -> Array: return [f["type"], f["offset"]]
    assert_eq(
        KernelSource.extract_push_constant_layout(glsl).map(type_and_offset),
        KernelSource.extract_push_constant_layout(GMACS_PREAMBLE).map(type_and_offset),
        "And lays the block out the same way, the pad being a name apart"
    )


## The tail pad, which is the maintainers' decision that a student never writes one.
##
## std430 rounds a block up to its widest member's alignment, so a block of two
## floats is eight bytes to glslang while `GMACS.md` and every kernel in the
## tree end on sixteen. The pass writes the difference as fields, so the size
## `RenderingDevice` demands and the size the packer sends are the same number
## by construction.
##
## **A block already on the boundary gets nothing**, an explicit `vec2 pad`
## included, and that is deliberate: a `vec2` and two `float`s are the same
## eight bytes and not the same struct, so a converted kernel that kept its own
## pad keeps its SPIR-V. The sweep leans on it.
func test_a_params_block_is_padded_to_the_boundary_and_no_further() -> void:
    var short_block := _lines_held("params:\n    float sigma\n", "The pad adds no line")
    var explicit := Dialect.transpile("params:\n    vec2 offset\n    vec2 region_origin\n    vec2 region_size\n    vec2 pad\n")
    var exact := Dialect.transpile("params:\n    vec4 tint\n")

    assert_true(short_block.ends_with("    float sigma; float _pad_0; float _pad_1; float _pad_2;};\n"), "Four bytes want twelve")
    assert_eq(int(KernelSource.extract_push_constant_layout(short_block)[-1]["offset"]), 16, "And land on the boundary")
    assert_true(explicit.ends_with("    vec2 pad;};\n"), "clear.gmacs's own block, converted, keeps its bytes and gains nothing")
    assert_true(exact.ends_with("    vec4 tint;};\n"), "Sixteen already is sixteen")
    assert_eq(int(KernelSource.extract_push_constant_layout(explicit)[-1]["offset"]), 32, "Four vec2 is two boundaries")
    assert_true(Dialect.is_pad_field("_pad_0"), "A pad is nameable, because the packing side has to skip it")
    assert_false(Dialect.is_pad_field("padding"), "And a field of somebody's own that merely reads like one is not")


# --- The spec's example, all the way to the front end ---------------------------


## What the whole pass is for. The spec's `blur_x` is transpiled and then handed
## to the fixtures `test_shader_compiler_source.gd` covers, the pure-text front
## end of the compiler, which is where a kernel becomes something glslang can
## read. None of it needs a GPU.
##
## The last assertion is the line map's: a pass that changed the count would move
## every glslang error under it onto a line nobody wrote.
func test_the_spec_example_transpiles_to_the_glsl_the_front_end_reads() -> void:
    var glsl := _lines_held(BLUR_X, "The example keeps every line it was written with")
    var clean := KernelSource.remove_comments(glsl)

    assert_eq(KernelSource.extract_kernels(clean), ["blur_x"], "The kernel keyword became the directive")
    assert_true('#include "gaussian"' in clean, "The import became the include the paste reads")
    assert_eq(KernelSource.extract_numthreads("blur_x", clean), ["8", "8", "1"], "The decorator became the attribute")
    assert_eq(clean.split("\n").size(), BLUR_X.split("\n").size(), "Source line, GLSL line, stripped line, all one")


func test_the_spec_examples_bindings_are_what_gdscript_binds_by_name() -> void:
    var clean := KernelSource.remove_comments(Dialect.transpile(BLUR_X))

    var layout := Bindings.extract_layout(clean)

    assert_eq(layout.size(), 2, "Two images and nothing else")
    assert_eq(layout[0], {"kind": "image", "name": "src", "format": "SA_STORAGE_FORMAT"}, "src is binding 0")
    assert_eq(layout[1], {"kind": "image", "name": "dst", "format": "SA_STORAGE_FORMAT"}, "dst is binding 1")


## The padding the maintainers' decision takes off the student: the compiler reads
## the block the pass wrote, so `push_constant_bytes` is the number
## RenderingDevice demands exactly.
func test_the_spec_examples_params_block_is_read_back_by_the_compiler() -> void:
    var clean := KernelSource.remove_comments(Dialect.transpile(BLUR_X))

    var layout := KernelSource.extract_push_constant_layout(clean)

    assert_eq(layout.size(), 5, "Two fields, the two the pad added, and the closing entry that carries the total")
    assert_eq(layout[0], {"name": "sigma", "type": "float", "offset": 0, "size": 4, "length": 0, "pad": false}, "sigma first")
    assert_eq(layout[1], {"name": "radius", "type": "int", "offset": 4, "size": 4, "length": 0, "pad": false}, "radius second")
    assert_eq(int(layout[4]["offset"]), 16, "Sixteen bytes, which is what the packer must send")


func test_the_spec_examples_kernel_becomes_main_and_its_helper_survives() -> void:
    var clean := KernelSource.remove_comments(Dialect.transpile(BLUR_X))

    var rewritten := KernelSource.replace_kernel_signature("blur_x", clean)

    assert_true("void main(" in rewritten, "glslang wants an entry point called main")
    assert_false("#kernel" in rewritten, "The directive is not GLSL")
    assert_false("[numthreads" in rewritten, "Nor is the attribute")
    assert_true("float luminance(vec3 c) {" in rewritten, "The helper is an ordinary GLSL function")
