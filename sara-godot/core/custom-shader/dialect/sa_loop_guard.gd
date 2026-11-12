## A loop in a kernel the door sends, bounded, so a `while true:` in a notebook
## cell is stopped by Sara before the driver gives the GPU up.
##
## A loop without end over the canvas makes the driver drop the device, and
## Sara would go down with the painter's unsaved work. So a kernel the
## `kernel` step compiles has every loop share one budget per invocation:
## each turn of any loop spends one, and a loop that finds none left ends, and
## says so in a buffer of its own that the step reads after the dispatch. One
## counter for the whole invocation rather than one per loop, because a budget
## per loop lets nested loops multiply it.
##
## **GLSL in and GLSL out.** The pass reads the text the dialect has already
## written, so it bounds a `while` and a `for` the dialect made, a GLSL `for`
## and a `do` loop's `while` alike, in a kernel written in either form. Only the
## door asks for it: Sara's own kernels never come through here, so each one's
## SPIR-V is what `test_spirv_manifest.gd` pins. A loop becomes
##
##     while (x) {             while ((x) && sa_loop_go()) {
##     for (a; b; c)           for (a; (b) && sa_loop_go(); c)
##
## and a `for` with no condition takes the guard as its condition. The first
## top-level declaration of the kernel's own file takes the counter, the buffer
## and the function in front of it, on the line it already stands on, so like
## every other pass of the compiler this one never adds a line and an error
## still names the line the painter wrote.
##
## **What the guard cannot read it refuses.** A loop keyword not followed by its
## condition in brackets, a `#define` that renames `while`, or brackets that
## never close, answers an error naming its line, because a loop left unguarded
## is the one this file exists to stop.
##
## Static and holding no state, so every case is testable without a
## RenderingDevice, and preloaded by path for the reason every half of the
## compiler is.
@tool
extends RefCounted

## How many turns of its loops one invocation may run, every loop of it
## together. Over a 1920 by 1080 canvas a `while true:` stops after tens of
## milliseconds of GPU time, and one that loads a texel and takes a sine and an
## exponential each turn after a few hundred, well inside the two seconds
## Windows waits before it resets the GPU. A square kernel
## of radius 89 takes 32,220 turns a pixel, its outer loop's counted, and the
## Voronoi notebook's a few dozen, so a kernel a lesson writes is never stopped.
const BUDGET: int = 32768

## The names the prelude declares. The prefix is Sara's, so a cell's own names
## do not meet them, and the buffer's instance is what the step binds.
const COUNTER: String = "sa_loop_left"
const BLOCK: String = "SaLoopGuard"
const INSTANCE: String = "sa_loop_guard"
const STEP: String = "sa_loop_go()"

## The member of the buffer the guard sets when it stops a loop.
const TRIPPED: String = "tripped"

## The two loop keywords. A `do` loop ends in a `while` and is bounded there.
const KEYWORDS: Array[String] = ["while", "for"]


## *glsl* with every loop bounded, as `{text, loops, error, line}`.
##
## *glsl* is GLSL with its comments gone, `KernelSource.remove_comments`'s
## output, so a keyword in a comment is not a loop. `loops` counts the loops
## bounded. `error` is empty, or the refusal of the first loop the guard could
## not read, with `line` its line counted from one and `text` unchanged.
static func bounded(glsl: String) -> Dictionary[String, Variant]:
    var answer: Dictionary[String, Variant] = {"text": glsl, "loops": 0, "error": "", "line": 0}
    var keyword := RegEx.new()
    keyword.compile("\\b(%s)\\b" % "|".join(KEYWORDS))
    var edits: Array = []
    for found: RegExMatch in keyword.search_all(glsl):
        var at := found.get_start(0)
        if _in_other_directive(glsl, at):
            continue
        var word := found.get_string(1)
        var open := _next_code(glsl, found.get_end(0))
        var close := _closing(glsl, open) if open >= 0 and glsl[open] == "(" else -1
        var refusal := ""
        if open < 0 or glsl[open] != "(":
            refusal = "`%s` is not followed by its condition in brackets, so the loop guard cannot bound it." % word
        elif close < 0:
            refusal = "the brackets after `%s` never close." % word
        var header := glsl.substr(open + 1, close - open - 1) if refusal.is_empty() else ""
        var replaced := _guarded_header(word, header) if refusal.is_empty() else ""
        if refusal.is_empty() and replaced.is_empty():
            refusal = "a `for` takes three parts between two semicolons, so the loop guard cannot read this one."
        if not refusal.is_empty():
            answer["error"] = refusal
            answer["line"] = glsl.substr(0, at).count("\n") + 1
            return answer
        edits.append([open + 1, close, replaced])
    var text := glsl
    for i in range(edits.size() - 1, -1, -1):
        var edit: Array = edits[i]
        var start: int = edit[0]
        var end: int = edit[1]
        text = text.substr(0, start) + str(edit[2]) + text.substr(end)
    answer["text"] = text
    answer["loops"] = edits.size()
    return answer


## *glsl* with the counter, the buffer and the function the bounded loops call,
## in front of its first top-level declaration and on that line.
##
## The buffer takes the binding after the highest *glsl* declares, so it meets
## none of the kernel's own. A text with no top-level declaration has no
## function to hold a loop either, and comes back as it was.
static func with_prelude(glsl: String) -> String:
    var at := _first_declaration(glsl)
    if at < 0:
        return glsl
    return glsl.substr(0, at) + prelude(_next_binding(glsl)) + " " + glsl.substr(at)


## The declarations a bounded loop needs, on one line, the buffer at *binding*.
static func prelude(binding: int) -> String:
    return (
        (
            "int %s = %d; layout( std430, set = 0, binding = %d ) buffer %s { uint %s; } %s;"
            + " bool %s { if (%s <= 0) { %s.%s = 1u; return false; } %s -= 1; return true; }"
        )
        % [COUNTER, BUDGET, binding, BLOCK, TRIPPED, INSTANCE, STEP, COUNTER, INSTANCE, TRIPPED, COUNTER]
    )


## Whether the four bytes a guard's buffer holds after a dispatch say a loop
## was stopped.
static func tripped(bytes: PackedByteArray) -> bool:
    return bytes.size() >= 4 and bytes.decode_u32(0) != 0


## The header between a loop's brackets with the guard in it, or "" for a
## `for` whose header is not three parts.
static func _guarded_header(word: String, header: String) -> String:
    if word == "while":
        return "(%s) && %s" % [header, STEP]
    var parts := _top_level_split(header, ";")
    if parts.size() != 3:
        return ""
    var condition := parts[1].strip_edges()
    var guarded := STEP if condition.is_empty() else "(%s) && %s" % [condition, STEP]
    return "%s; %s;%s" % [parts[0], guarded, parts[2]]


## Whether *at* stands on a preprocessor line other than a `#define`, whose
## `while` and `for` are words of a message rather than loops. A `#define`'s
## body is read, so a loop written in one is bounded where it is expanded.
static func _in_other_directive(glsl: String, at: int) -> bool:
    var line_start := glsl.rfind("\n", at - 1) + 1 if at > 0 else 0
    var line := glsl.substr(line_start, at - line_start).strip_edges(true, false)
    return line.begins_with("#") and not line.begins_with("#define")


## The index of the first character at or after *from* that is not white space,
## or -1.
static func _next_code(glsl: String, from: int) -> int:
    for i in range(from, glsl.length()):
        if glsl[i] not in [" ", "\t", "\n", "\r"]:
            return i
    return -1


## The index of the bracket that closes the one at *open*, or -1 when none does.
static func _closing(glsl: String, open: int) -> int:
    var depth := 0
    for i in range(open, glsl.length()):
        var c := glsl[i]
        if c == "(":
            depth += 1
        elif c == ")":
            depth -= 1
            if depth == 0:
                return i
    return -1


## *text* split at each *separator* outside brackets.
static func _top_level_split(text: String, separator: String) -> PackedStringArray:
    var parts := PackedStringArray()
    var depth := 0
    var from := 0
    for i in text.length():
        var c := text[i]
        if c == "(" or c == "[" or c == "{":
            depth += 1
        elif c == ")" or c == "]" or c == "}":
            depth -= 1
        elif c == separator and depth == 0:
            parts.append(text.substr(from, i - from))
            from = i + 1
    parts.append(text.substr(from))
    return parts


## Where the first declaration at the top level of *glsl* starts, past its
## indentation, or -1.
##
## The first line that is not empty and is not a preprocessor line or the
## continuation of one. Nothing above it opens a bracket, so it stands at the top
## level, and every function, the ones that hold loops among them, comes after
## it. A `#define` that writes a loop is expanded inside a function, after it too.
static func _first_declaration(glsl: String) -> int:
    var continued := false
    var offset := 0
    for line in glsl.split("\n"):
        var body := line.strip_edges()
        var directive := continued or body.begins_with("#")
        continued = directive and body.ends_with("\\")
        if not directive and not body.is_empty():
            return offset + line.length() - line.strip_edges(true, false).length()
        offset += line.length() + 1
    return -1


## One more than the highest binding *glsl* declares, 0 when it declares none.
static func _next_binding(glsl: String) -> int:
    var binding := RegEx.new()
    binding.compile("\\bbinding\\s*=\\s*(\\d+)")
    var next := 0
    for found: RegExMatch in binding.search_all(glsl):
        next = maxi(next, int(found.get_string(1)) + 1)
    return next
