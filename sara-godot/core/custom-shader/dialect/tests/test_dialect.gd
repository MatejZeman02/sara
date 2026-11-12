## The Python-shaped `.gmacs` dialect on its way to GLSL: what a file is written
## in, every rewrite the pass makes, and the count of lines it must not change.
##
## `sa_dialect.gd` holds no state and touches no RenderingDevice, so all of this
## runs offscreen. It is worth its own suite because two of its promises are
## invisible until they break. One source line is one GLSL line, and a pass that
## drops or adds one moves every glslang error below it onto a line nobody wrote,
## which is the whole reason the line map exists. And a GLSL kernel must come
## back unchanged, because the tree holds both forms until the sweep is through.
##
## Cases are grouped rather than written one per assertion, because gdlint caps
## a script at 32 public methods.
## The file has a first sibling, `test_dialect_names.gd`,
## which holds the name tables, the decorator's default and `pixel`. A second sibling splits
## by subject again: this file keeps which dialect a
## file is written in, its two directives and its comments, and
## `test_dialect_statements.gd` keeps `def`, the workgroup decorator, a
## block's closing brace, the word operators, the bracket continuation and
## `range`. Nothing was rewritten in the move.
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


# --- Which dialect a file is written in ----------------------------------------


## The default matters more than the detection: a file with no marker either way
## is GLSL, so nothing in the tree changes meaning by being scanned.
func test_a_file_with_no_marker_or_a_glsl_one_is_glsl() -> void:
    assert_false(Dialect.is_dialect("float gaussian(float x) { return x; }\n"), "A library with no marker is GLSL")
    assert_false(Dialect.is_dialect(GLSL_KERNEL), "#kernel and the attribute are GLSL markers")
    assert_eq(Dialect.to_glsl(GLSL_KERNEL), GLSL_KERNEL, "A GLSL file goes through untouched, byte for byte")


## The detector against the tree rather than against a fixture. A file read as
## the wrong one of the two is rewritten into something glslang cannot parse,
## which is the one way this pass could break a kernel nobody touched.
##
## An assertion that every file in the tree is GLSL cannot hold while the tree
## is mixed, and every file in it is one or the other. So the assertion says
## the same thing another way,
## that a file is read as what it is written in. A GLSL one goes through byte
## for byte, and a dialect one comes out rewritten, line for line, and is never
## read as the dialect a second time.
func test_every_shader_in_the_tree_is_read_as_what_it_is_written_in() -> void:
    var files := _gmacs_files("res://shaders")
    files.append_array(_gmacs_files("res://modules"))
    var dialect_line := RegEx.new()
    dialect_line.compile("(?m)^\\s*(?:kernel\\s+\\w|import\\s+\\w|def\\s+\\w+\\s*\\(|@workgroup_size|params\\s*:)")

    assert_true(files.size() > 20, "The walk found the shaders, so the check below means something")
    for path: String in files:
        var raw := FileAccess.get_file_as_string(path)
        var glsl := Dialect.to_glsl(raw)
        if not Dialect.is_dialect(raw):
            assert_eq(glsl, raw, "%s is GLSL and goes through untouched" % path)
            # The misread stated the other way round, which the branch above
            # cannot see: a dialect file read as GLSL also goes through
            # untouched, and then fails to compile. The Python detector's own
            # case asks this, and the two are ports of each other.
            assert_null(dialect_line.search(raw), "%s is GLSL and writes no dialect line" % path)
            continue
        assert_true(glsl != raw, "%s is the dialect and comes out rewritten" % path)
        assert_eq(glsl.split("\n").size(), raw.split("\n").size(), "%s keeps its line count" % path)
        assert_false(Dialect.is_dialect(glsl), "%s comes out as GLSL, not as the dialect again" % path)


## Every `.gmacs` under *root*, recursively.
func _gmacs_files(root: String) -> Array:
    var found: Array = []
    for name in DirAccess.get_files_at(root):
        if name.get_extension() == "gmacs":
            found.append(root.path_join(name))
    for name in DirAccess.get_directories_at(root):
        found.append_array(_gmacs_files(root.path_join(name)))
    return found


func test_each_dialect_marker_decides_on_its_own() -> void:
    assert_true(Dialect.is_dialect(BLUR_X), "`kernel blur_x` on its own is the dialect's directive")
    assert_true(Dialect.is_dialect("import gaussian\n"), "import")
    assert_true(Dialect.is_dialect("def helper():\n    return\n"), "def")
    assert_true(Dialect.is_dialect("@workgroup_size(8, 8)\n"), "the decorator")
    assert_true(Dialect.is_dialect("image dst\n"), "a declaration with nothing after its name")
    assert_true(Dialect.is_dialect("params:\n    float sigma\n"), "the params block")


## The first marker decides. A count would let one stray line change a file's
## dialect and the last one would let an appended line do it, so a GLSL file
## whose body happens to hold a dialect-shaped word is still GLSL.
func test_the_first_marker_is_the_one_that_decides() -> void:
    assert_false(Dialect.is_dialect("#kernel paint\n\nvoid image dst;\n"), "#kernel came first")
    assert_true(Dialect.is_dialect('kernel paint\n#include "x"\n'), "the bare keyword came first")


# --- The two directives ---------------------------------------------------------


func test_the_two_directives_become_their_hash_forms() -> void:
    var glsl := _lines_held("kernel blur\nimport gaussian\n", "Two directives, two lines")

    assert_eq(glsl, '#kernel blur\n#include "gaussian"\n', "The keywords are the directives without the hash")
    assert_eq(
        Dialect.transpile("import mixing/noise\n"),
        '#include "mixing/noise"\n',
        "A name two modules provide is written with its owner and keeps the slash"
    )


# --- Comments -------------------------------------------------------------------


## The hash is a comment only outside a string, which is why the split is a scan
## rather than a find.
func test_a_hash_is_a_comment_only_outside_a_string() -> void:
    var glsl := _lines_held("# the tip\nkernel blur  # named for the tip\n", "A comment line is still a line")

    assert_eq(glsl, "// the tip\n#kernel blur  // named for the tip\n", "Both the whole line and the trailing one")
    assert_eq(Dialect.transpile('name = "#kernel"\n'), 'name = "#kernel";\n', "The literal is left exactly as written")


## A closing brace is appended to the block's last code line, so a comment line
## after it must not swallow the brace.
func test_a_comment_is_written_after_the_closing_brace() -> void:
    var glsl := _lines_held("def f():\n    a = 1\n    # done\n", "Three lines in, three out")

    assert_eq(glsl, "void f() {\n    a = 1;}\n    // done\n", "The brace is on the code line, not in the comment")
