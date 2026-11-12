## The include paste and the line map, which are one reading.
##
## An include is pasted before glslang ever sees the file, so glslang counts
## lines in a document nobody wrote: the libraries are in it and the preamble is
## on top. The line map is what turns its number back into a file and a line, and
## it is only correct while every step above it preserves the line count. So the
## paste and the map are tested together, and `remove_comments` is here rather
## than beside the other transforms because the map is what it exists to protect.
##
## Split out of `test_shader_compiler_source.gd`, which found that file at
## gdlint's `max-public-methods` of thirty-two exactly, a test case being a public
## method, so no unit could add a case to it.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const KernelSource := preload("res://core/custom-shader/dialect/sa_kernel_source.gd")


## Virtual includes live on the autoload, so a test that registers one and
## leaves it there changes what every later compile sees.
func after_each() -> void:
    for name: String in ["probe_lib", "probe_outer", "probe_inner", "cyc_a", "cyc_b"]:
        GlobalShaderCompiler.clear_virtual_include(name)


# --- Includes -------------------------------------------------------------------


func test_an_include_is_replaced_by_its_source() -> void:
    GlobalShaderCompiler.set_virtual_include("probe_lib", "float helper() { return 1.0; }")

    var out := GlobalShaderCompiler.source.process_includes('#include "probe_lib"\nvoid main() {}\n', "probe.gmacs")

    assert_true("float helper()" in out, "The include's source is pasted in")
    assert_false("#include" in out, "No include directive may survive into GLSL")


## The loop re-scans after every paste, which is what makes an include inside an
## include work. linear_srgb_color_space.gmacs relies on this in production.
func test_an_include_inside_an_include_is_expanded_too() -> void:
    GlobalShaderCompiler.set_virtual_include("probe_inner", "float inner() { return 2.0; }")
    GlobalShaderCompiler.set_virtual_include("probe_outer", '#include "probe_inner"\nfloat outer() { return 3.0; }')

    var out := GlobalShaderCompiler.source.process_includes('#include "probe_outer"\n', "probe.gmacs")

    assert_true("float inner()" in out, "The nested include is expanded")
    assert_true("float outer()" in out, "And so is the one that pulled it in")


## Two libraries that include each other must not expand forever. The
## already-included set is what stops it, the same way #pragma once would.
##
## This test prints `WARNING: Import cycle: cyc_b.gmacs imports cyc_a`, with a
## backtrace. That is the guard reporting that it caught the cycle, so it is the
## pass condition rather than a regression, and the one warning this suite emits.
## The duplicate-include test below is silent, because a
## library already pasted is no fault.
func test_an_include_cycle_terminates() -> void:
    GlobalShaderCompiler.set_virtual_include("cyc_a", '#include "cyc_b"\nfloat a() { return 1.0; }')
    GlobalShaderCompiler.set_virtual_include("cyc_b", '#include "cyc_a"\nfloat b() { return 2.0; }')

    var out := GlobalShaderCompiler.source.process_includes('#include "cyc_a"\n', "probe.gmacs")

    assert_false("#include" in out, "The cycle resolves rather than expanding forever")
    assert_eq(out.count("float a()"), 1, "Each side is pasted exactly once")
    assert_eq(out.count("float b()"), 1, "Each side is pasted exactly once")


## A generated include shadows a file of the same name. The document colour
## space is the reason: its matrices depend on what the user picked at creation,
## so they cannot be a file in the repository.
func test_a_virtual_include_shadows_a_file_of_the_same_name() -> void:
    var real_include: String = GlobalShaderCompiler.index.compute_shader_file_paths[0].get_file().get_basename()
    GlobalShaderCompiler.set_virtual_include(real_include, "float generated() { return 9.0; }")

    var out := GlobalShaderCompiler.source.process_includes('#include "%s"\n' % real_include, "probe.gmacs")

    assert_true("float generated()" in out, "The generated source wins over the file on disk")
    GlobalShaderCompiler.clear_virtual_include(real_include)


## The case the already-included guard exists for, and the one it used to miss.
##
## Replacing the directive rewrote every occurrence at once, so both copies were
## substituted on the first pass and the guard never saw the second. The library
## landed twice and GLSL rejected the redefinition, naming the library rather
## than the file that included it twice.
func test_the_same_include_twice_in_one_file_is_pasted_once() -> void:
    GlobalShaderCompiler.set_virtual_include("probe_lib", "float helper() { return 1.0; }")
    var source := '#include "probe_lib"\nvoid a() {}\n#include "probe_lib"\nvoid b() {}\n'

    var out := GlobalShaderCompiler.source.process_includes(source, "probe.gmacs")

    assert_eq(out.count("float helper()"), 1, "The library is pasted once, however often it is asked for")
    assert_false("#include" in out, "Both directives are consumed")
    assert_true("void a()" in out and "void b()" in out, "Nothing else in the file is disturbed")


# --- The line map ---------------------------------------------------------------


## Stripping comments must not move any line.
##
## The whole mapping below rests on it. A block comment used to collapse to
## nothing, taking its newlines with it, and composite.gmacs opens with forty lines
## of one, so every line number after it was wrong before glslang ever saw the file.
func test_removing_comments_leaves_the_line_count_alone() -> void:
    var source := "line one\n/* two\nthree\nfour */\nfive // trailing\nsix\n"
    var stripped: String = KernelSource.remove_comments(source)
    assert_eq(stripped.count("\n"), source.count("\n"), "Same number of lines in and out")
    assert_true(stripped.split("\n")[4].begins_with("five"), "and line five is still line five")
    assert_false(stripped.contains("three"), "with the comment itself gone")


## glslang's line numbers are turned back into a file and a line as written.
##
## It counts lines in what it was handed: includes pasted, two lines of preamble on
## top. So `ERROR: 0:137:` named a line in a file nobody can open, and finding the
## real one meant reconstructing the paste by hand.
func test_a_glsl_error_is_traced_back_to_the_file_it_came_from() -> void:
    var origins: Array = GlobalShaderCompiler.source.line_map("composite")
    assert_false(origins.is_empty(), "The composite shader has a line map")
    if origins.is_empty():
        return

    # Line 1 of the file, which is PREAMBLE_LINES + 1 in what glslang was given.
    var first := GlobalShaderCompiler.source.PREAMBLE_LINES + 1
    var located := GlobalShaderCompiler.source.locate_glsl_error("ERROR: 0:%d: 'x' : nope" % first, "composite")
    assert_true(located.contains("[composite.gmacs:1]"), "The first line of the file is named as line 1: %s" % located)
    assert_true(located.contains("0:%d" % first), "and glslang's own number is kept, because it is what glslang said")


## An included library is named as itself, not as the file that pasted it.
func test_an_error_inside_an_include_names_the_include() -> void:
    var origins: Array = GlobalShaderCompiler.source.line_map("composite")
    var seen: Dictionary = {}
    for origin: Array in origins:
        seen[String(origin[0]).get_file()] = true
    assert_true(seen.has("composite.gmacs"), "The map covers the shader itself")
    assert_true(seen.size() > 1, "and the libraries pasted into it, which is the case worth mapping: %s" % [seen.keys()])


## A message this cannot place is returned as it came, rather than mangled.
func test_an_unmappable_error_is_left_alone() -> void:
    var message := "ERROR: 0:9999: 'x' : off the end"
    assert_eq(
        GlobalShaderCompiler.source.locate_glsl_error(message, "composite"),
        message,
        "A line past the end of the map is not guessed at"
    )
    assert_eq(GlobalShaderCompiler.source.locate_glsl_error(message, "no_such_shader"), message, "Nor is an unknown shader")
    assert_eq(GlobalShaderCompiler.source.locate_glsl_error("", "composite"), "", "An empty message stays empty")
