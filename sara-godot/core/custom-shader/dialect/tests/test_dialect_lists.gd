## What the dialect reads: a `kernel` or `import` line naming
## more than one thing, a docstring under a `def`, a library of constants and
## nothing else, and the refusal a list that is not a list of names gets.
##
## A sibling of `test_dialect.gd`, which keeps the single directives, because
## that file is near gdlint's cap of 32 public methods and these are a subject
## of their own. Every case asserts the count of lines in against the count
## out, the dialect's first rule, through `_lines_held`. What an import brings
## across once it is pasted, and where a refusal lands in the painter's file,
## need the compiler and a device, and are asked in `test_dialect_line_map.gd`.
extends "res://tests/test_framework.gd"

const Dialect := preload("res://core/custom-shader/dialect/sa_dialect.gd")
const KernelSource := preload("res://core/custom-shader/dialect/sa_kernel_source.gd")


## The count of lines in and out, which every case below asserts through here.
func _lines_held(source: String, message: String) -> String:
    var glsl := Dialect.transpile(source)
    assert_eq(glsl.split("\n").size(), source.split("\n").size(), message)
    return glsl


# --- Lists ----------------------------------------------------------------------


func test_an_import_row_names_every_library_on_its_line() -> void:
    var glsl := _lines_held("import transfer_curve, positive_channels,mixing/noise\n", "One row, one line")

    assert_eq(
        glsl,
        '#include "transfer_curve" #include "positive_channels" #include "mixing/noise"\n',
        "One include per name, in the order written, an owner's slash kept"
    )


## Each name is a kernel of its own, so each takes the default workgroup and
## the one that uses `pixel` gets it declared, exactly as if it had a line.
func test_a_kernel_row_declares_every_kernel_on_its_line() -> void:
    var source := "kernel first, second\n\ndef first():\n    a = pixel.x\n\ndef second():\n    a = 1\n"
    var glsl := _lines_held(source, "Seven lines in, seven out")

    assert_eq(glsl.split("\n")[0], "#kernel first #kernel second", "Both directives, on the row's own line")
    assert_eq(KernelSource.extract_kernels(glsl), ["first", "second"], "The compiler reads both, in order")
    assert_true(glsl.contains("[numthreads( 8, 8, 1 )] void first()"), "The first kernel takes the default")
    assert_true(glsl.contains("[numthreads( 8, 8, 1 )] void second()"), "and so does the second")
    assert_true(glsl.contains(" ivec2 pixel = "), "`pixel` is declared for a kernel named on a row")


## A kernel named on a row renames to `main` as one named alone does, and the
## other kernel's directive leaves the line with it.
func test_a_kernel_on_a_row_is_the_main_of_its_own_module() -> void:
    var glsl := Dialect.transpile("kernel first, second\n\ndef first():\n    a = 1\n\ndef second():\n    a = 2\n")

    var second := KernelSource.replace_kernel_signature("second", glsl)

    assert_false(second.contains("#kernel"), "No directive is left for glslang: %s" % second)
    assert_true(second.contains("void main()"), "The kernel asked for is main")


# --- The refusal ----------------------------------------------------------------


## `import a, , b` used to fall through as a statement and reach glslang with a
## semicolon after it, a syntax error in a language the painter never wrote. It
## is refused by name now, on its own line, in words the painter can act on.
func test_a_list_with_a_hole_is_refused_by_sara() -> void:
    var glsl := _lines_held("kernel paint\nimport a, , b\n", "The refusal takes the row's line and no other")

    var row := glsl.split("\n")[1]
    assert_true(row.begins_with("#error SaDialect: "), "An #error glslang reports as it stands: %s" % row)
    assert_true(row.contains("import a, , b"), "and it quotes the row: %s" % row)
    assert_false(row.contains("#include"), "Nothing on the row is pasted")


func test_every_malformed_list_is_refused() -> void:
    for row: String in ["import a,", "import , b", "kernel a b", "kernel a, b/c", 'import "a"']:
        var glsl := Dialect.transpile("def f():\n    a = 1\n" + row + "\n")
        assert_true(glsl.split("\n")[2].begins_with("#error SaDialect: "), "%s is refused: %s" % [row, glsl])
        assert_false(glsl.split("\n")[2].contains('"'), "and no quote is left to trouble the preprocessor")


# --- Docstrings -----------------------------------------------------------------


func test_a_docstring_on_one_line_becomes_a_comment() -> void:
    var glsl := _lines_held('def f() -> float:\n    """Half of one."""\n    return 0.5\n', "Three lines in, three out")

    assert_eq(glsl, "float f() {\n    // Half of one.\n    return 0.5;}\n", "The quotes go and the words stay")
    assert_eq(
        Dialect.transpile("def f():\n    'Nothing.'\n    a = 1\n"),
        "void f() {\n    // Nothing.\n    a = 1;}\n",
        "One quote closed on its line is a docstring too"
    )


## A docstring over several lines is a comment on every one of them, and what
## would be code inside it is prose: the hash is not a comment, the colon opens
## no block and the names are not rewritten.
func test_a_docstring_over_lines_is_a_comment_on_each() -> void:
    var source := (
        'def f(\n    float x\n) -> float:\n    """Twice x.\n\n    Returns: imageLoad # not a comment\n'
        + '    """\n    return x\n'
    )
    var glsl := _lines_held(source, "Nine lines in, nine out")

    var out := glsl.split("\n")
    assert_eq(out[3], "    // Twice x.", "The opening line keeps its words")
    assert_eq(out[4], "//", "A blank line of it is an empty comment")
    assert_eq(out[5], "    // Returns: imageLoad # not a comment", "The prose is left as written")
    assert_eq(out[6], "    //", "The closing quotes leave nothing")
    assert_eq(out[7], "    return x;}", "The body after it is the body, closed where it ends")


## Only the string a body opens with is a docstring, and only one that closes.
func test_a_string_elsewhere_is_not_a_docstring() -> void:
    assert_eq(Dialect.transpile('a = 1\n"""loose"""\n'), 'a = 1;\n"""loose""";\n', "Not under a def")
    assert_eq(
        Dialect.transpile('def f():\n    a = 1\n    """late"""\n'),
        'void f() {\n    a = 1;\n    """late""";}\n',
        "Not the first thing in the body"
    )
    assert_eq(
        Dialect.transpile('def f():\n    """never closes\n    a = 1\n'),
        'void f() {\n    """never closes;\n    a = 1;}\n',
        "An unclosed one is not read as prose to the end of the file"
    )


func test_a_docstring_may_be_the_whole_body() -> void:
    var glsl := _lines_held('def f():\n    """Nothing yet."""\n', "Two lines in, two out")

    assert_eq(glsl, "void f() {}\n    // Nothing yet.\n", "The brace closes on the signature and the prose follows it")


# --- Constants ------------------------------------------------------------------


## A library of constants alone has no `def` and no declaration, so it used to
## read as GLSL and reach glslang without a semicolon on any line.
func test_a_library_of_constants_is_the_dialect() -> void:
    var source := "# the limits\nconst float LIMIT = 0.5\nconst int STEPS[2] = int[2](1, 2)  # a pair\n"

    assert_true(Dialect.is_dialect(source), "A constant with no semicolon is the dialect's")
    assert_eq(
        Dialect.to_glsl(source),
        "// the limits\nconst float LIMIT = 0.5;\nconst int STEPS[2] = int[2](1, 2);  // a pair\n",
        "and each becomes GLSL's constant, on its own line"
    )


func test_a_glsl_constant_stays_glsl() -> void:
    assert_false(Dialect.is_dialect("const float LIMIT = 0.5;\n"), "The semicolon says GLSL")
    assert_false(Dialect.is_dialect("const vec3 K = vec3(\n    1.0, 2.0, 3.0);\n"), "and so does an open bracket")
