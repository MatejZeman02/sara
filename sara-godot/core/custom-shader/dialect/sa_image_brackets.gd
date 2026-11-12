## An image read and written with brackets, the way Python indexes a list.
##
## GLSL cannot index an image, so a bracket after the name of an image the file
## declares means nothing else, and the dialect gives it the meaning a Python
## reader expects:
##
##     vec4 c = src[at]                vec4 c = imageLoad(src, at);
##     dst[at] = c / weight            imageStore(dst, at, c / weight);
##     dst[at] += c                    imageStore(dst, at, imageLoad(dst, at) + (c));
##
## A compound assignment reads the texel it writes, so its index is written
## twice and an index with a side effect, `dst[i++] += c`, runs it twice. The
## value goes in parentheses so `dst[at] *= a + b` multiplies by the sum.
##
## **Both ways compile.** `image_load`, `image_store` and their camelCase
## spellings are untouched, and the brackets come out as exactly the GLSL the
## old way gives, so a kernel can mix the two and a kernel written the old way
## transpiles as it always did. A bracket after a name that is not a declared
## image is GLSL's array and stays as it is.
##
## **Only a whole texel is written.** `dst[at].r = x` is not a store GLSL has,
## so it is refused with the dialect's own `#error` rather than handed on as an
## assignment to a call, which glslang would report in words the painter never
## wrote.
##
## Static, and preloaded by path for the reason every part of the compiler is.
@tool
extends RefCounted

## What a piece of text holds, reached by path the way the dialect reaches it.
const GmacsScan := preload("res://core/custom-shader/dialect/sa_gmacs_scan.gd")

## An `image` declaration, the name in its first group.
const DECLARATION: String = "^\\s*image\\s+(\\w+)\\b"

## What follows a store's closing bracket: the operator, if any, and the value.
## The lookahead keeps `dst[at] == c` a comparison.
const ASSIGNMENT: String = "^\\s*(<<|>>|[-+*/%&|^])?=(?!=)\\s*(.*)$"

## A store to one channel of a texel, `dst[at].r = x`, which GLSL has no call
## for.
const PART: String = "^\\s*\\.\\s*\\w+\\s*(<<|>>|[-+*/%&|^])?=(?!=)"

## The start of the line a refused part store becomes, which the transpiler
## hands on without the statement's semicolon.
const REFUSAL: String = "#error SaDialect: "


## The names of every image *codes* declares, wherever it declares them, so a
## function above the declaration reads with brackets too.
static func declared(codes: Array[String]) -> Array[String]:
    var declaration := RegEx.new()
    declaration.compile(DECLARATION)
    var names: Array[String] = []
    for code: String in codes:
        var found := declaration.search(code)
        if found != null and not names.has(found.get_string(1)):
            names.append(found.get_string(1))
    return names


## Whether line *code* stores to one of *images* with brackets, which the edge
## check asks when it looks for the image a kernel writes. The image's name, or
## an empty String. A one-line body after a header's colon, `if c: dst[at] = c`,
## is read too, so the store a kernel writes first is found the way
## `image_store` is.
static func stored(code: String, images: Array[String]) -> String:
    var assigned := RegEx.new()
    assigned.compile(ASSIGNMENT)
    var from := 0
    while from >= 0:
        var target := _target(code.substr(from), images)
        if not target.is_empty() and assigned.search(target["rest"]) != null:
            return target["image"]
        var colon := code.find(":", from)
        from = colon + 1 if colon >= 0 else -1
    return ""


## *statement* with its brackets on *images* as GLSL's calls: a store when the
## statement assigns to one, and a load wherever else one is read.
static func statement(text: String, images: Array[String]) -> String:
    if images.is_empty():
        return text
    var target := _target(text, images)
    if not target.is_empty():
        var assigned := RegEx.new()
        assigned.compile(ASSIGNMENT)
        var found := assigned.search(target["rest"])
        if found != null:
            var image: String = target["image"]
            var index := reads(target["index"], images)
            var value := reads(found.get_string(2), images)
            var operator := found.get_string(1)
            if not operator.is_empty():
                value = "imageLoad(%s, %s) %s (%s)" % [image, index, operator, value]
            return "imageStore(%s, %s, %s)" % [image, index, value]
        var part := RegEx.new()
        part.compile(PART)
        if part.search(target["rest"]) != null:
            return REFUSAL + "a store to one channel of %s is not a store GLSL has, write the whole texel" % target["image"]
    return reads(text, images)


## *text* with every bracket after one of *images* as an `imageLoad`, outside
## string literals, an index holding a bracket of its own included.
static func reads(text: String, images: Array[String]) -> String:
    if images.is_empty():
        return text
    var opener := RegEx.new()
    opener.compile("(?<![\\w.])(%s)\\s*\\[" % "|".join(images))
    var out := ""
    for span: Array in GmacsScan.code_spans(text):
        var piece := str(span[0])
        if GmacsScan.is_quoted(span):
            out += piece
            continue
        var at := 0
        var found := opener.search(piece, at)
        while found != null:
            var close := _closing(piece, found.get_end() - 1)
            if close < 0:
                break
            var index := reads(piece.substr(found.get_end(), close - found.get_end()).strip_edges(), images)
            out += piece.substr(at, found.get_start() - at)
            out += "imageLoad(%s, %s)" % [found.get_string(1), index]
            at = close + 1
            found = opener.search(piece, at)
        out += piece.substr(at)
    return out


## The image *text* opens with a bracket on, as `{image, index, rest}`, or an
## empty Dictionary when it opens with anything else.
static func _target(text: String, images: Array[String]) -> Dictionary[String, String]:
    var none: Dictionary[String, String] = {}
    var head := RegEx.new()
    head.compile("^\\s*(\\w+)\\s*\\[")
    var found := head.search(text)
    if found == null or not images.has(found.get_string(1)):
        return none
    var close := _closing(text, found.get_end() - 1)
    if close < 0:
        return none
    return {
        "image": found.get_string(1),
        "index": text.substr(found.get_end(), close - found.get_end()).strip_edges(),
        "rest": text.substr(close + 1),
    }


## The index of the bracket that closes the one at *open* in *text*, or -1.
static func _closing(text: String, open: int) -> int:
    var depth := 0
    for i in range(open, text.length()):
        var c := text[i]
        if c == "(" or c == "[" or c == "{":
            depth += 1
        elif c == ")" or c == "]" or c == "}":
            depth -= 1
            if depth == 0:
                return i
    return -1
