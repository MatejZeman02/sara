## A statement's shape on its way to GLSL: `def` and the workgroup decorator, a
## block's closing brace, the word operators, the bracket continuation, and
## `range`.
##
## A sibling of `test_dialect.gd` rather than more of it, split off
## because that file was filling toward gdlint's cap of 32 public methods and
## the units after it still have work to file there. The split is by subject,
## the way `test_dialect_names.gd` and `test_dialect_flow.gd` were split
## before it: `test_dialect.gd` keeps which dialect a file is written in, its
## two directives and its comments, this one keeps how a statement itself is
## rewritten. Nothing was rewritten in the move.
##
## The line count is asserted on every case for the reason `test_dialect.gd`
## gives: a closing brace lives on the last line of the block it closes, so a
## form that needed a line of its own would move every glslang error under it.
extends "res://tests/test_framework.gd"

const Dialect := preload("res://core/custom-shader/dialect/sa_dialect.gd")


## The count of lines in and out, which every case below asserts through here.
func _lines_held(source: String, message: String) -> String:
    var glsl := Dialect.transpile(source)
    assert_eq(glsl.split("\n").size(), source.split("\n").size(), message)
    return glsl


# --- def, the decorator and the workgroup size ----------------------------------


func test_a_def_takes_the_return_type_its_arrow_names() -> void:
    var glsl := _lines_held("def paint():\n    a = 1\n", "Two lines")

    assert_eq(glsl, "void paint() {\n    a = 1;}\n", "GLSL wants a return type where Python wants none")
    assert_eq(
        Dialect.transpile("def luminance(vec3 c) -> float:\n    return 1.0\n"),
        "float luminance(vec3 c) {\n    return 1.0;}\n",
        "The arrow's type goes in front of the name"
    )


## The decorator is not GLSL, so it moves onto the signature and its own line
## goes out empty rather than disappearing.
func test_the_decorator_moves_onto_the_signature_line() -> void:
    var glsl := _lines_held("@workgroup_size(8, 8, 1)\ndef paint():\n    a = 1\n", "Three lines in, three out")

    assert_eq(glsl, "\n[numthreads( 8, 8, 1 )] void paint() {\n    a = 1;}\n", "The attribute sits where glslang reads it")


func test_a_decorator_may_name_fewer_than_three_numbers() -> void:
    var flat := Dialect.transpile("@workgroup_size(8, 8)\ndef paint():\n    a = 1\n")
    var rows := Dialect.transpile("@workgroup_size(64)\ndef rows():\n    a = 1\n")

    assert_true("[numthreads( 8, 8, 1 )]" in flat, "A 2D kernel names two and GLSL wants three")
    assert_true("[numthreads( 64, 1, 1 )]" in rows, "@workgroup_size(64) is the 1D form")


## The default is what a missing line means, for every kernel a file declares
## and for no helper. The pass remembered only the last
## `kernel` line, so once the converter and the formatter stopped writing the
## default, every earlier kernel of a file with several compiled without an
## attribute and fifty-one suites went red.
func test_every_declared_kernel_takes_the_default_and_a_helper_does_not() -> void:
    var glsl := Dialect.transpile(
        "kernel seed\nkernel backdrop\n\ndef helper():\n    a = 1\n\ndef seed():\n    a = 1\n\ndef backdrop():\n    a = 1\n"
    )

    assert_true("[numthreads( 8, 8, 1 )] void seed()" in glsl, "The first kernel takes the default")
    assert_true("[numthreads( 8, 8, 1 )] void backdrop()" in glsl, "and so does the last")
    assert_true("\nvoid helper()" in glsl, "A helper takes no attribute")


## The spec wrote `@numthreads(x, y, z)` before `@workgroup_size` was chosen, so both spellings are read.
func test_the_specs_numthreads_spelling_is_read_too() -> void:
    var glsl := Dialect.transpile("@numthreads(16, 4, 2)\ndef paint():\n    a = 1\n")

    assert_true("[numthreads( 16, 4, 2 )]" in glsl, "The spec's own spelling still compiles")


## The attribute belongs to the `def` under the decorator and to no other, which
## is what `extract_numthreads` assumes when it matches by kernel name.
func test_the_decorator_lands_on_the_next_def_only() -> void:
    var source := "@workgroup_size(8, 8)\ndef paint():\n    a = 1\n\n\ndef helper():\n    b = 2\n"

    var glsl := _lines_held(source, "Seven lines in, seven out")

    assert_eq(glsl.count("[numthreads"), 1, "One decorator is one attribute")
    assert_true("void helper() {" in glsl, "The function after it is an ordinary one")


# --- Blocks, statements and the word operators ----------------------------------


func test_a_closing_brace_goes_on_the_blocks_last_line() -> void:
    var source := "def f():\n    head = 1\n    tail = 2\nafter = 3\n"

    var glsl := _lines_held(source, "Four lines in, four out")

    assert_eq(glsl, "void f() {\n    head = 1;\n    tail = 2;}\nafter = 3;\n", "No brace of its own anywhere")


func test_nested_blocks_close_innermost_first_and_at_the_end_of_the_file() -> void:
    var stepped := _lines_held("def f():\n    for i in range(0, 4):\n        a = i\n    b = 1\n", "Four in, four out")
    var open_at_eof := _lines_held("def f():\n    for i in range(0, 4):\n        a = i\n", "Three in, three out")

    assert_true(stepped.ends_with("        a = i;}\n    b = 1;}\n"), "The loop closes on its body, the function on b")
    assert_true(open_at_eof.ends_with("        a = i;}}\n"), "Both braces land on the last line there is")


func test_the_three_word_operators_become_their_symbols() -> void:
    var glsl := _lines_held("ok = a and b or not c\n", "One line")

    assert_eq(glsl, "ok = a && b || ! c;\n", "The words are the operators the dialect writes")


func test_a_word_operator_is_a_whole_word_and_never_one_inside_a_string() -> void:
    assert_eq(Dialect.transpile("random = band + nothing\n"), "random = band + nothing;\n", "Only whole words")
    assert_eq(Dialect.transpile('label = "a and b"\n'), 'label = "a and b";\n', "Never inside a literal")


# --- The bracket continuation ---------------------------------------------------


## Python's rule, and the one case where a statement is not on one line. The
## lines it spanned stay in the output so the count still holds and the line map
## still points at a line the file has.
func test_a_bracket_continuation_is_joined_onto_its_first_line() -> void:
    var source := "sum += imageLoad(src,\n    at + ivec2(1, 0))\ntail = 1\n"

    var glsl := _lines_held(source, "Three lines in, three out")

    assert_eq(glsl, "sum += imageLoad(src, at + ivec2(1, 0));\n\ntail = 1;\n", "One statement, and the line it spanned")


func test_a_continuation_carries_its_comment_to_its_own_line() -> void:
    var glsl := _lines_held("sum += f(a,\n    b)  # the second\n", "Two lines in, two out")

    assert_eq(glsl, "sum += f(a, b);\n    // the second\n", "The comment stays on the line it was written on")


# --- range ----------------------------------------------------------------------


func test_a_range_loop_assumes_int() -> void:
    var glsl := _lines_held("for i in range(0, 4):\n    a = i\n", "Two lines")

    assert_eq(glsl, "for (int i = 0; i < 4; i++) {\n    a = i;}\n", "Two arguments are a start and a bound")


func test_a_range_takes_a_step_and_leaves_an_expression_alone() -> void:
    var stepped := Dialect.transpile("for i in range(0, 16, 4):\n    a = i\n")
    var computed := Dialect.transpile("for dy in range(-radius, radius + 1):\n    a = dy\n")

    assert_true(stepped.begins_with("for (int i = 0; i < 16; i += 4) {"), "The third argument is the step")
    assert_true(
        computed.begins_with("for (int dy = -radius; dy < radius + 1; dy++) {"), "Nothing between the commas is rewritten"
    )
