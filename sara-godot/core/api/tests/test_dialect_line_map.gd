## A glslang error against a dialect kernel names the line the student wrote.
##
## This is the whole reason the transpiler counts lines. `sa_dialect.gd` puts a
## closing brace on the last line of the block it closes, empties a decorator's
## line rather than dropping it, and joins a bracket continuation onto its first
## line while leaving the lines it spanned in place, all so that the count of
## lines in is the count of lines out. If it were not so, `sa_include_processor.gd`
## would still map glslang's number back to a file and a line, and the line would
## be the wrong one, silently, for every kernel a student writes.
##
## So the cases below are the four places the count could have slipped: a line
## inside a block, a line after a `match` and the `break` the pass inserts, a line
## after a bracket continuation, and a line after a comment and the decorator
## whose own line goes out empty. Each is asked of the real line map, built by
## the real compiler over a real dialect file, and each is asked by looking the
## line up rather than by counting to it, so the test says nothing about how the
## paste is laid out.
##
## A sibling of `test_shader_compiler_source.gd`, because
## that file is at gdlint's cap of 32 public methods. These cases would have been the thirty-third.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

static var scratch_probe_path: String = SaDataRoot.path("k4_probe.gmacs")
static var scratch_broken_path: String = SaDataRoot.path("k4_broken.gmacs")
const LIBRARY := "k4_probe_lib"

## The probes: a row of two imports, one of them a library of constants alone,
## and the same row with a hole in it.
static var scratch_lists_path: String = SaDataRoot.path("k1_lists.gmacs")
static var scratch_refused_path: String = SaDataRoot.path("k1_refused.gmacs")
const CONSTANTS := "k1_constants"

## A library that names a number and does nothing else. Without one it had no
## marker line, so the paste read it as GLSL and glslang met a constant with no
## semicolon. A constant beside a `def` always crossed, the paste being the
## whole file, which `graph_histogram.gmacs` had leaned on all along.
const CONSTANTS_LIBRARY := """# the one number the probe needs
const float K1_HALF = 0.5
"""

const LISTS := """kernel k1_lists
import k4_probe_lib, k1_constants

image canvas


def k1_lists():
    imageStore(canvas, pixel, vec4(k4_helper(K1_HALF)))
"""

const REFUSED := """kernel k1_refused
import k4_probe_lib, , k1_constants

image canvas


def k1_refused():
    imageStore(canvas, pixel, vec4(1.0))
"""

## The lines this suite asks about, by what makes each of them worth asking.
const LINE_AFTER_A_COMMENT := 12
const LINE_INSIDE_A_BLOCK := 16
const LINE_AFTER_A_MATCH := 21
const LINE_AFTER_A_CONTINUATION := 22

## A dialect library, registered as a virtual include so that the import
## resolves without a second file on disk. The dialect pass runs on it at the
## paste, which is the hook in `sa_include_processor.gd`, so this is also what
## proves an imported library is transpiled at all.
const PROBE_LIBRARY := """# the helper the kernel imports
def k4_helper(float x) -> float:
    return x * 2.0
"""

## One dialect kernel carrying every shape that could have moved a line, with
## the four lines above at the numbers the constants name. Counted from 1, and
## the blank lines are load-bearing.
const PROBE := """kernel k4_probe
import k4_probe_lib

image canvas

params:
    float mode

# a comment is a line, and stays one
@workgroup_size(8, 8)
def k4_probe():
    ivec2 px = ivec2(gl_GlobalInvocationID.xy)
    float v = k4_helper(mode)
    match int(v):
        case 0:
            v = 1.0
        case _:
            v = 2.0
    vec4 c = imageLoad(canvas,
        px)
    v = v + c.r
    imageStore(canvas, px, vec4(v))
"""

## The same kernel with one undefined name on LINE_AFTER_A_MATCH, so that
## glslang produces a real message about a real line.
const BROKEN := """kernel k4_broken
import k4_probe_lib

image canvas

params:
    float mode

# a comment is a line, and stays one
@workgroup_size(8, 8)
def k4_broken():
    ivec2 px = ivec2(gl_GlobalInvocationID.xy)
    float v = k4_helper(mode)
    match int(v):
        case 0:
            v = 1.0
        case _:
            v = 2.0
    vec4 c = imageLoad(canvas,
        px)
    v = v + c.r + k4_no_such_thing
    imageStore(canvas, px, vec4(v))
"""


func before_each() -> void:
    GlobalShaderCompiler.set_virtual_include(LIBRARY, PROBE_LIBRARY)
    GlobalShaderCompiler.set_virtual_include(CONSTANTS, CONSTANTS_LIBRARY)


## The index lives on an autoload, so a probe left in it changes what every
## later compile resolves.
func after_each() -> void:
    GlobalShaderCompiler.clear_virtual_include(LIBRARY)
    GlobalShaderCompiler.clear_virtual_include(CONSTANTS)
    for path: String in [scratch_probe_path, scratch_broken_path, scratch_lists_path, scratch_refused_path]:
        var key := GlobalShaderCompiler.index.shader_key(path)
        GlobalShaderCompiler.index.shaders_by_key.erase(key)
        var bare := GlobalShaderCompiler.index.get_shader_name(path)
        GlobalShaderCompiler.index.owners_of_name.erase(bare)
        DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## *source* at *path*, compiled the way any `.gmacs` in the tree is, and the name
## it is known by afterwards.
func _compiled(path: String, source: String) -> String:
    var file := FileAccess.open(path, FileAccess.WRITE)
    file.store_string(source)
    file.close()
    GlobalShaderCompiler.compile_compute_shader(path)
    return GlobalShaderCompiler.index.get_shader_name(path)


## Every report made while *source* at *path* compiles, and the kernel's name.
##
## `SaProblems.attach_sink` hands a new sink every report no sink has taken yet,
## so what arrives here is the backlog of whatever suite ran before as well as
## what this compile says. Read the list through `_glsl_errors_of`.
func _reports_of_compiling(path: String, source: String) -> Array:
    var reported: PackedStringArray = PackedStringArray()
    var announced := SaProblems.announce
    SaProblems.announce = false
    SaProblems.attach_sink(func(line: String, _kind: SaProblems.Kind) -> void: reported.append(line))

    var name := _compiled(path, source)

    SaProblems.detach_sink()
    SaProblems.announce = announced
    return [name, reported]


## The GLSL errors in *reported* that name the kernel *name*, and no other.
##
## Counting every GLSL error would count the broken kernel a suite earlier
## compiled on purpose, which waits in the sink until the first test to attach
## one. Naming the kernel is what makes the count the same whichever suite ran
## before, and a kernel that reports no error or two still fails it.
func _glsl_errors_of(name: String, reported: PackedStringArray) -> PackedStringArray:
    var own := PackedStringArray()
    for line: String in reported:
        if line.contains("GLSL error in kernel '%s'" % name):
            own.append(line)
    return own


## The number glslang would print for *line* of *file*, or -1 when the map does
## not carry it.
##
## Looked up rather than counted, because the paste puts the library's lines
## where the `import` was and the point of the test is the mapping, not the
## arithmetic.
func _glslang_line_for(shader: String, file: String, line: int) -> int:
    var origins: Array = GlobalShaderCompiler.source.line_map(shader)
    for i in origins.size():
        var origin: Array = origins[i]
        if String(origin[0]).get_file() == file and int(origin[1]) == line:
            return GlobalShaderCompiler.source.PREAMBLE_LINES + 1 + i
    return -1


## What `locate_glsl_error` makes of an error against *line* of *file*.
func _located(shader: String, file: String, line: int) -> String:
    var at := _glslang_line_for(shader, file, line)
    assert_true(at > 0, "%s:%d is in the map at all" % [file, line])
    return GlobalShaderCompiler.source.locate_glsl_error("ERROR: 0:%d: 'x' : undeclared identifier" % at, shader)


# --- The four places a line could have moved -----------------------------------


func test_a_line_inside_a_block_is_named_as_itself() -> void:
    var name := _compiled(scratch_probe_path, PROBE)

    var located := _located(name, "k4_probe.gmacs", LINE_INSIDE_A_BLOCK)

    assert_true(
        located.contains("[k4_probe.gmacs:%d]" % LINE_INSIDE_A_BLOCK),
        "A line two blocks deep is still its own line: %s" % located
    )


## The `match` is where the count is most at risk: `case` takes no brace, the
## `break` the pass inserts shares the case's last line, and the `switch` closes
## on the last case. Every one of those is a line that could have been added.
func test_a_line_after_a_match_is_named_as_itself() -> void:
    var name := _compiled(scratch_probe_path, PROBE)

    var located := _located(name, "k4_probe.gmacs", LINE_AFTER_A_MATCH)

    assert_true(
        located.contains("[k4_probe.gmacs:%d]" % LINE_AFTER_A_MATCH),
        "The inserted breaks and the closing brace took no line of their own: %s" % located
    )


## A continuation is joined onto its first line, and the line it spanned stays
## in the output holding nothing. Dropping it would move everything under it up
## by one.
func test_a_line_after_a_bracket_continuation_is_named_as_itself() -> void:
    var name := _compiled(scratch_probe_path, PROBE)

    var located := _located(name, "k4_probe.gmacs", LINE_AFTER_A_CONTINUATION)

    assert_true(
        located.contains("[k4_probe.gmacs:%d]" % LINE_AFTER_A_CONTINUATION),
        "The line the continuation spanned is still a line: %s" % located
    )


## A comment line stays a line, and so does the decorator's, which goes out
## empty because its attribute moved onto the signature.
func test_a_line_after_a_comment_and_a_decorator_is_named_as_itself() -> void:
    var name := _compiled(scratch_probe_path, PROBE)

    var located := _located(name, "k4_probe.gmacs", LINE_AFTER_A_COMMENT)

    assert_true(
        located.contains("[k4_probe.gmacs:%d]" % LINE_AFTER_A_COMMENT),
        "Neither the comment nor the emptied decorator moved anything: %s" % located
    )


## The statement the four cases above rest on, made once and without a round
## trip: every line of the file is in the map, once, in order.
##
## Asking `locate_glsl_error` about a line it was just told about would prove
## only that the lookup is its own inverse. This counts instead. The kernel's
## own lines are 1 to N, every one: the `import` on line 2 is replaced by the
## library's lines, and the line after the library's last newline is what was
## left of line 2, which goes back to the kernel so a second name on the row
## resolves from the kernel. Anything the pass dropped or added shows up here
## as a gap or a repeat.
func test_the_map_carries_every_line_of_the_file_once_and_in_order() -> void:
    var name := _compiled(scratch_probe_path, PROBE)

    var mine: Array = []
    for origin: Array in GlobalShaderCompiler.source.line_map(name):
        if String(origin[0]).get_file() == "k4_probe.gmacs":
            mine.append(int(origin[1]))

    # The trailing newline leaves an empty last line, and an empty line is a
    # line: `_origins_for` counts it and so does the file.
    var written := PROBE.split("\n").size()
    var expected: Array = []
    for line in range(1, written + 1):
        expected.append(line)
    assert_eq(mine, expected, "One source line, one GLSL line, in the order they were written")


# --- An imported dialect library -------------------------------------------------


## An error inside a library names the library, not the kernel that pasted it.
## The library is written in the dialect too, so this is also what says the pass
## runs at the paste as well as at the read.
func test_an_error_inside_an_imported_dialect_library_names_the_library() -> void:
    var name := _compiled(scratch_probe_path, PROBE)

    var located := _located(name, "%s.gmacs" % LIBRARY, 3)

    assert_true(located.contains("[%s.gmacs:3]" % LIBRARY), "The helper's own third line, not a line of the kernel: %s" % located)


# --- The message a student actually reads ----------------------------------------


## The whole chain, from a name nobody declared to the line in the file the
## student has open. glslang is given the real kernel, and what it says goes
## through the real reporting path, so what is asserted here is the text on the
## screen rather than a mapping in the middle.
func test_the_message_a_student_reads_names_their_own_line() -> void:
    var compiled := _reports_of_compiling(scratch_broken_path, BROKEN)
    var reported: PackedStringArray = compiled[1]

    var glsl_errors := _glsl_errors_of(compiled[0], reported)

    assert_eq(glsl_errors.size(), 1, "One kernel, one report: %s" % [reported])
    if glsl_errors.is_empty():
        return
    assert_true(
        glsl_errors[0].contains("[k4_broken.gmacs:%d]" % LINE_AFTER_A_MATCH),
        "The undeclared name is on line %d of the file the student wrote: %s" % [LINE_AFTER_A_MATCH, glsl_errors[0]]
    )
    assert_true(glsl_errors[0].contains("k4_no_such_thing"), "and the name itself is in the message")


# --- A row of imports ------------------------------------------------------------


## Both libraries on the row are pasted and the kernel compiles, the constant
## included: the measurement that settles it.
func test_a_row_of_imports_brings_a_constant_across() -> void:
    var name := _compiled(scratch_lists_path, LISTS)

    assert_eq(GlobalShaderCompiler.compile_error(name), "", "The helper and the constant both arrived")
    var files: Array = []
    for origin: Array in GlobalShaderCompiler.source.line_map(name):
        if not files.has(String(origin[0]).get_file()):
            files.append(String(origin[0]).get_file())
    assert_true(files.has("%s.gmacs" % LIBRARY), "The first library is in the map: %s" % [files])
    assert_true(files.has("%s.gmacs" % CONSTANTS), "and so is the second: %s" % [files])


## The second include on a row is found on a line the first library's paste
## ends, and that line is the rest of the row, so the map gives it to the
## kernel. That is also the file the second name is resolved from, which is
## what lets a module import Sara's library and then its own of the same name.
func test_the_rest_of_a_row_belongs_to_the_row() -> void:
    var name := _compiled(scratch_lists_path, LISTS)

    var rows := 0
    for origin: Array in GlobalShaderCompiler.source.line_map(name):
        if String(origin[0]).get_file() == "k1_lists.gmacs" and int(origin[1]) == 2:
            rows += 1
    assert_eq(rows, 1, "Line 2 of the kernel is in the map once, where the second paste began")


## `import a, , b` is Sara's refusal on the painter's own line, not glslang's
## complaint about a statement it could not parse.
func test_a_row_with_a_hole_is_refused_on_its_own_line() -> void:
    var compiled := _reports_of_compiling(scratch_refused_path, REFUSED)
    var reported: PackedStringArray = compiled[1]

    var glsl_errors := _glsl_errors_of(compiled[0], reported)

    assert_eq(glsl_errors.size(), 1, "One kernel, one report: %s" % [reported])
    if glsl_errors.is_empty():
        return
    # glslang hands an `#error` back token by token, so the colon and the
    # commas arrive with a space in front of each.
    assert_true(glsl_errors[0].contains("is not a list of names"), "The words are Sara's: %s" % glsl_errors[0].c_escape())
    assert_true(glsl_errors[0].contains("[k1_refused.gmacs:2]"), "and they name the row: %s" % glsl_errors[0])
