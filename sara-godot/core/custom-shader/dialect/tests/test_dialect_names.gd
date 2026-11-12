## The dialect's names: the two tables of `gmacs_names.json`, the workgroup
## decorator's default, and `pixel`.
##
## A sibling of `test_dialect.gd` rather than four more cases in it, because that
## file reached gdlint's cap of 32 public methods on this unit and the units
## after it still have `if`, `while`, `match` and `struct` to prove. The split is
## by subject, as the front end's own test files are: this one
## is what a name is, that one is what a line becomes.
##
## Nothing here needs a RenderingDevice either. The tables are a file the
## transpiler, the formatter and the converter all read, so the cases are
## driven by the file rather than by a list written here: a table the tests do
## not read is a table that comes to disagree with the code.
extends "res://tests/test_framework.gd"

const Dialect := preload("res://core/custom-shader/dialect/sa_dialect.gd")
const GmacsNames := preload("res://core/custom-shader/dialect/sa_gmacs_names.gd")


## The count of lines in and out, which `pixel` must not change either.
func _lines_held(source: String, message: String) -> String:
    var glsl := Dialect.transpile(source)
    assert_eq(glsl.split("\n").size(), source.split("\n").size(), message)
    return glsl


## Every name in `gmacs_names.json`, both ways, driven by the file rather than by
## a list written here: a table the tests do not read is a table that comes to
## disagree with the transpiler, and the formatter and the converter read the
## same file.
##
## Both spellings compile, so
## each name is asserted twice, and the last three assertions are the other half
## of the table's promise: a word it does not have is a word the pass leaves
## alone, which is what keeps the exception to "never touch an expression" as
## narrow as the rule says.
func test_every_name_in_the_table_compiles_in_both_spellings() -> void:
    var table := GmacsNames.names()

    assert_eq(table["variables"].size(), 6, "The six built-in variables a compute shader has")
    assert_true(table["functions"].size() > 60, "Every camelCase built-in, not the ten the tree happens to call")

    for half: String in ["variables", "functions"]:
        var pairs: Dictionary = table[half]
        for glsl_name: String in pairs:
            var snake := String(pairs[glsl_name])
            var args := "(x)" if half == "functions" else ""
            var written := Dialect.transpile("def f():\n    a = %s%s\n" % [snake, args])
            var pasted := Dialect.transpile("def f():\n    a = %s%s\n" % [glsl_name, args])

            assert_true(glsl_name in written, "%s writes %s" % [snake, glsl_name])
            assert_false(snake in written, "and nothing of %s is left" % snake)
            assert_true(glsl_name in pasted, "%s pasted out of the GLSL specification still compiles" % glsl_name)

    var mine := Dialect.transpile("def f():\n    float group_weight = local_sum + 1.0\n")
    var reserved := Dialect.transpile("params p:\n    int image_size\n\ndef f():\n    a = p.image_size\n")
    var quoted := Dialect.transpile('def f():\n    a = "image_load"\n')

    assert_true("float group_weight = local_sum + 1.0;" in mine, "A variable that shadows no name is untouched")
    assert_true("int imageSize;" in reserved, "A table name is reserved, so a field that takes one is renamed")
    assert_true("a = p.imageSize;" in reserved, "and renamed in every read of it, so the file still compiles")
    assert_true('"image_load"' in quoted, "A name inside a string is not an identifier")


## The two things that belong to the kernel's own `def` and to no other function
## in the file: the workgroup size when no decorator named one, and `pixel`.
##
## `pixel` is declared inside the brace on the signature's own line, so the
## count of lines still holds, and the file that declares its own keeps it.
func test_the_kernels_own_def_takes_the_default_size_and_pixel() -> void:
    var bare := Dialect.transpile("kernel paint\ndef paint():\n    a = 1\n")
    var rows := Dialect.transpile("kernel rows\n@workgroup_size(64)\ndef rows():\n    a = 1\n")
    var used := _lines_held("kernel paint\ndef paint():\n    a = pixel.x\n", "Three lines in, three out")
    var own := Dialect.transpile("kernel paint\ndef paint():\n    ivec2 pixel = ivec2(1, 2)\n    a = pixel.x\n")
    var helper := Dialect.transpile("kernel paint\ndef paint():\n    a = pixel.x\ndef helper():\n    b = pixel.y\n")

    assert_true("[numthreads( 8, 8, 1 )] void paint()" in bare, "No decorator is the 8 by 8 every kernel but two wants")
    assert_true("[numthreads( 64, 1, 1 )] void rows()" in rows, "A named size still wins, and 1D still fills the two")
    assert_false("ivec2 pixel" in bare, "A file that never says pixel gets no unused variable")
    assert_true("void paint() { ivec2 pixel = ivec2(gl_GlobalInvocationID.xy);" in used, "Declared where GLSL sees it")
    assert_eq(own.count("ivec2 pixel"), 1, "A file that declares its own keeps it, and does not get a second")
    assert_eq(helper.count("[numthreads"), 1, "The default belongs to the kernel, not to every function beside it")
    assert_false("void helper() { ivec2 pixel" in helper, "And a helper takes the word from the kernel's scope")
