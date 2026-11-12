## One `for` header of the dialect as one GLSL `for` header: `range`,
## `range_inclusive`, the counter's type and the step.
##
## **This file owns the loop form**, which is why it has a name of its own
## rather than the parent's plus a suffix. It asks `sa_gmacs_scan.gd` for a
## range's commas directly rather than being handed the parent's splitter as a
## Callable, so it is whole on its own.
##
## **Why there are two range functions**. A kernel written in the dialect
## compiles to the same program, by its stripped SPIR-V, as the GLSL it stands
## for, so a loop has to come out as the loop that was written and not as one
## that counts the same texels. `range(a, b)` emits `i < b`, and `i < r + 1`
## and `i <= r` are two different modules. Some of the tree's `for` loops are
## written the other way:
##
## - four with an inclusive bound, `dx <= r`, in `selection.gmacs` and
##   `libs/noise.gmacs`,
## - two that count down, `x >= 0` with `x--`, in the base module's flood
##   kernel,
## - three with a `uint` counter, `i < PARADE_GROUP` from `0u`, in `graph.gmacs`.
##
## So the inclusive bound gets a function of its own rather than a rule that
## reads `range(a, b + 1)` and quietly emits `i <= b`, which would make the
## dialect's one range function mean two things. A
## counter that is not an `int` names its type where the spec already said the
## type was assumed.
##
## Static and holding no state, so every case is testable without a
## RenderingDevice, and preloaded by path for the reason every half of the
## compiler is.
@tool
extends RefCounted

## The scan, for the top-level commas of a `range`.
const GmacsScan := preload("res://core/custom-shader/dialect/sa_gmacs_scan.gd")

## The counter's type when the header does not name one, which the spec
## promises and most of the tree's loops rely on.
const DEFAULT_COUNTER_TYPE := "int"

## A step of exactly this is an increment or a decrement rather than a compound
## assignment, because that is what the tree writes and what a reader expects.
## Anything else, `4` included, is `i += step`.
const UNIT_STEPS := {"1": "++", "-1": "--"}


## One `for` header, or an empty Dictionary when *head* is not one.
##
## `for x in range(n)`, `range(a, b)`, `range(a, b, step)`, and
## `range_inclusive` beside them with the bound closed, each with an optional
## type before the counter's name: `for uint i in range(n)`.
static func header(head: String) -> Dictionary[String, Variant]:
    var regex := RegEx.new()
    regex.compile("^for\\s+(?:(\\w+)\\s+)?(\\w+)\\s+in\\s+(range|range_inclusive)\\s*\\((.+)\\)$")
    var found := regex.search(head)
    if found == null:
        return {}
    var counter_type := found.get_string(1)
    if counter_type.is_empty():
        counter_type = DEFAULT_COUNTER_TYPE
    return _loop(
        counter_type, found.get_string(2), found.get_string(3) == "range_inclusive", GmacsScan.split_args(found.get_string(4))
    )


## The header itself, once the pieces are apart.
##
## The direction is read off the step and only when the step is written as a
## literal, because a step held in a variable could be either and the answer has
## to be decided at transpile time. An unwritten or unreadable step counts up,
## which is what `range` has always done.
static func _loop(counter_type: String, variable: String, inclusive: bool, bounds: Array) -> Dictionary[String, Variant]:
    if bounds.size() == 1:
        var start := "0u" if counter_type == "uint" else "0"
        bounds = [start, bounds[0]]
    elif bounds.size() < 2 or bounds.size() > 3:
        push_error("SaDialect: range() takes one argument, two or three, not %d." % bounds.size())
        bounds = ["0", "0"]
    var step := str(bounds[2]) if bounds.size() == 3 else "1"
    var descending := inclusive and _is_negative_literal(step)
    var comparison := ">=" if descending else ("<=" if inclusive else "<")
    var advance := "%s%s" % [variable, str(UNIT_STEPS[step])] if UNIT_STEPS.has(step) else "%s += %s" % [variable, step]
    var opening := "for (%s %s = %s; " % [counter_type, variable, bounds[0]]
    var test := "%s %s %s; %s)" % [variable, comparison, bounds[1], advance]
    return {"text": opening + test, "opens": true, "open": " {", "closer": "}", "pads": false}


## Whether *step* is written as a negative number rather than as an expression.
static func _is_negative_literal(step: String) -> bool:
    var regex := RegEx.new()
    regex.compile("^-\\s*\\d+$")
    return regex.search(step.strip_edges()) != null
