## The loop guard's text half: every `while` and `for` of a door
## kernel's GLSL takes one turn of a budget per invocation, the declarations
## land on a line the kernel already has, and a loop the guard cannot read is
## refused at its line rather than left to run.
##
## Strings in and strings out, so every case runs offscreen. The step that binds
## the buffer and answers the stop is `harness/tests/`'s suite of the same unit.
## The line count is asserted wherever text changes, for the reason the
## dialect's suites give: a glslang error has to name the line the cell wrote.
extends "res://tests/test_framework.gd"

const LoopGuard := preload("res://core/custom-shader/dialect/sa_loop_guard.gd")
const Dialect := preload("res://core/custom-shader/dialect/sa_dialect.gd")
const KernelSource := preload("res://core/custom-shader/dialect/sa_kernel_source.gd")

## Lesson 00's cell 29 in the form that hung the laptop, with a `for` beside it.
const ENDLESS := """kernel endless

image src: readonly
image dst

def endless():
    float v = 0.0
    while true:
        v += 1.0
    for i in range(0, 4):
        v += float(i)
    image_store(dst, pixel, vec4(v))
"""

## The two loops GLSL has that the dialect never writes.
const GLSL_LOOPS := """#kernel spin
layout( rgba32f, set = 0, binding = 0 ) uniform image2D dst;
[numthreads( 8, 8, 1 )] void spin() {
    int n = 0;
    for (;;) { n++; }
    do { n--; } while (n > 0);
}
"""


func _glsl(source: String) -> String:
    return KernelSource.remove_comments(Dialect.to_glsl(source))


func _lines(text: String) -> int:
    return text.count("\n")


func test_a_while_and_a_for_of_the_dialect_each_spend_the_budget() -> void:
    var glsl := _glsl(ENDLESS)
    var bounded := LoopGuard.bounded(glsl)
    var text := String(bounded["text"])

    assert_eq(String(bounded["error"]), "", "both loops were read")
    assert_eq(int(bounded["loops"]), 2, "and both were bounded")
    assert_true(text.contains("while ((true) && sa_loop_go())"), "the while turns only while budget is left: %s" % text)
    assert_true(text.contains("for (int i = 0; (i < 4) && sa_loop_go(); i++)"), "and so does the for: %s" % text)
    assert_eq(_lines(text), _lines(glsl), "and no line was added")


func test_a_glsl_for_with_no_condition_and_a_do_loop_are_bounded_too() -> void:
    var bounded := LoopGuard.bounded(GLSL_LOOPS)
    var text := String(bounded["text"])

    assert_eq(int(bounded["loops"]), 2, "both loops of a GLSL kernel were bounded")
    assert_true(text.contains("for (; sa_loop_go();)"), "a for with no condition takes the guard as one: %s" % text)
    assert_true(text.contains("while ((n > 0) && sa_loop_go());"), "and a do loop is bounded at its while: %s" % text)


func test_the_declarations_land_on_the_first_top_level_line_once() -> void:
    var bounded := LoopGuard.bounded(_glsl(ENDLESS))
    var text := LoopGuard.with_prelude(String(bounded["text"]))
    var lines := text.split("\n")

    assert_eq(lines[0], "#kernel endless", "a directive line is passed over, it cannot hold a declaration")
    var counter := "int sa_loop_left = %d;" % LoopGuard.BUDGET
    assert_true(lines[2].begins_with(counter), "the first declaration takes them: %s" % lines[2])
    assert_true(lines[2].ends_with("image2D src;"), "in front of what it declared")
    assert_eq(
        text.count("int sa_loop_left"), 1, "one counter for every loop of an invocation, so nested loops cannot multiply it"
    )
    assert_true(lines[2].contains("binding = 2 ) buffer SaLoopGuard"), "the buffer takes the binding after the kernel's own two")
    assert_eq(_lines(text), _lines(_glsl(ENDLESS)), "and the kernel is as many lines as the cell sent")


func test_a_loop_word_in_a_message_is_no_loop_and_one_in_a_define_is() -> void:
    var glsl := "#error while waiting for nothing\n#define SPIN for (;;) {}\nvoid f() { SPIN }\n"
    var bounded := LoopGuard.bounded(glsl)
    var text := String(bounded["text"])

    assert_eq(int(bounded["loops"]), 1, "the define's loop is bounded and the message's words are not")
    assert_true(text.begins_with("#error while waiting for nothing\n"), "the message is as written")
    assert_true(text.contains("#define SPIN for (; sa_loop_go();)"), "the define's for is bounded where it is expanded")


func test_a_name_that_holds_a_loop_word_is_left_alone() -> void:
    var glsl := "void f() { float forward = 1.0; int for_each = 2; float awhile = 0.0; }\n"

    assert_eq(int(LoopGuard.bounded(glsl)["loops"]), 0, "forward, for_each and awhile are names")
    assert_eq(String(LoopGuard.bounded(glsl)["text"]), glsl, "and the text is untouched")


func test_a_loop_the_guard_cannot_read_is_refused_at_its_line() -> void:
    var renamed := LoopGuard.bounded("#kernel k\n\n#define FOREVER while\nvoid k() { FOREVER (true) {} }\n")
    var unclosed := LoopGuard.bounded("void k() {\n    while (true {\n}\n")

    assert_eq(int(renamed["line"]), 3, "a while with no condition after it is refused on its line: %s" % [renamed])
    assert_true(String(renamed["error"]).contains("loop guard cannot bound it"), "saying why: %s" % [renamed["error"]])
    assert_eq(int(unclosed["line"]), 2, "and so are brackets that never close: %s" % [unclosed])
    assert_true(String(unclosed["error"]).contains("never close"), "saying so")


func test_a_text_with_no_loop_is_unchanged_and_takes_no_prelude_from_the_driver() -> void:
    var glsl := "#kernel flat\nvoid flat() { int a = 1; }\n"
    var bounded := LoopGuard.bounded(glsl)

    assert_eq(int(bounded["loops"]), 0, "no loop, nothing bounded")
    assert_eq(String(bounded["text"]), glsl, "and nothing changed")


func test_the_buffer_says_whether_a_loop_was_stopped() -> void:
    assert_false(LoopGuard.tripped(PackedByteArray([0, 0, 0, 0])), "a zero says every loop ended on its own")
    assert_true(LoopGuard.tripped(PackedByteArray([1, 0, 0, 0])), "a one says the guard stopped one")
    assert_false(LoopGuard.tripped(PackedByteArray()), "and no bytes at all say nothing was stopped")
