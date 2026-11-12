## The further images a pixel function declares beside the layer `src` reads,
## lifted out of its body and declared in the wrapper.
##
## A notebook cell in the short form may read a second layer the way a written
## kernel does, by declaring it and naming it on the cell's line:
##
##     image blue: readonly
##
##     def pixel(ivec2 at) -> vec4:
##         return src(at) + blue[at]
##
## The dialect numbers an image by the order it appears in the text it is
## translating, and the wrapper and the body it imports are two texts, so a
## declaration left in the body took binding 0, the one the wrapper's
## `sa_source` holds, and the layout kept only the later of the two. So the
## line is blanked in the body, as a `uniform` line is, which keeps the line
## count and the compiler's line map, the image is declared in the wrapper
## after its own pair, where the count gives it a binding of its own, and a
## bracket after its name is written as the load here, because the body does not
## declare the name the dialect's brackets look for.
##
## The pass form fixes its bindings at the source, the selection and the target,
## and nothing hands it a further layer, so there a declaration is a problem
## naming its line rather than a clash the compiler would make of it.
##
## Static, and preloaded by path for the reason every part of the compiler is.
@tool
extends RefCounted

## The brackets the dialect gives an image, reused so a read here is the GLSL a
## written kernel's read becomes.
const ImageBrackets := preload("res://core/custom-shader/dialect/sa_image_brackets.gd")

## The scan the transpiler reads `.gmacs` with, for the comment on a line.
const GmacsScan := preload("res://core/custom-shader/dialect/sa_gmacs_scan.gd")

## An `image` line as the dialect reads one, its name and its qualifiers.
const DECLARATION: String = "^image\\s+(\\w+)\\s*(?::\\s*(.+))?$"


## Each `image` line of *raw_text* as `{name, qualifiers, line}`, the line
## counted from one, in the order written.
static func declared(raw_text: String) -> Array[Dictionary]:
    var shape := RegEx.new()
    shape.compile(DECLARATION)
    var out: Array[Dictionary] = []
    var lines := raw_text.split("\n")
    for i in lines.size():
        var found := shape.search(_code(lines[i]))
        if found != null:
            out.append({"name": found.get_string(1), "qualifiers": found.get_string(2).strip_edges(), "line": i + 1})
    return out


## The names of [method declared], for the brackets.
static func names(raw_text: String) -> Array[String]:
    var out: Array[String] = []
    for image: Dictionary in declared(raw_text):
        out.append(str(image["name"]))
    return out


## Whether *code*, one line with its comment taken off, declares an image.
static func is_declaration(code: String) -> bool:
    var shape := RegEx.new()
    shape.compile(DECLARATION)
    return shape.search(code.strip_edges()) != null


## *code* with a bracket after one of *images* written as GLSL's load, or its
## store when the line assigns to one, the indent kept.
static func read(code: String, images: Array[String]) -> String:
    if images.is_empty():
        return code
    var indent := code.substr(0, code.length() - code.lstrip(" \t").length())
    return indent + ImageBrackets.statement(code.strip_edges(), images)


## An `image` line per one of *images*, appended to *lines*, with the
## qualifiers the student wrote.
static func declare(lines: PackedStringArray, images: Array) -> void:
    for image: Dictionary in images:
        var qualifiers := str(image.get("qualifiers", ""))
        lines.append("image %s%s" % [str(image["name"]), ": " + qualifiers if not qualifiers.is_empty() else ""])


## A problem per image of *raw_text* named as one of *reserved*, the names the
## wrapper declares itself.
static func problems(raw_text: String, reserved: Array[String]) -> PackedStringArray:
    var out := PackedStringArray()
    for image: Dictionary in declared(raw_text):
        if str(image["name"]) in reserved:
            out.append("line %d names an image `%s`, which the wrapper declares itself." % [image["line"], image["name"]])
    return out


## A problem per image of *raw_text*, for the pass form and the rule form,
## whose bindings are fixed and which nothing hands a further layer.
static func layered_problems(raw_text: String) -> PackedStringArray:
    var out := PackedStringArray()
    for image: Dictionary in declared(raw_text):
        out.append(
            (
                "line %d declares an image `%s`, and a filter's pass or a simulation's step reads only its own layer."
                % [image["line"], image["name"]]
            )
        )
    return out


## The code half of *line*, trimmed, its comment taken off.
static func _code(line: String) -> String:
    return str(GmacsScan.split_comment(line)[0]).strip_edges()
