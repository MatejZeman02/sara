## What a pixel function reads around its pixel: how far, and the reads that
## make an average over a neighbourhood correct.
##
## **The reach.** A pixel function that reads its neighbours declares how far,
## because the gather pads the run's rectangle by that much and `src` reads
## transparent past it. A fixed number is the margin a module hands to
## `SaPixelFilter`. A reach that follows a slider is written on the slider's own
## line, as a hint beside its range:
##
##     uniform int radius: hint_range(1, 20), hint_reach(200) = 3
##
## so the gather pads by the radius the painter picked, and the slider may be
## typed up to 200 while its drag stops at 20. `hint_reach` with no number keeps
## the range's highest as the most it reads. One uniform carries it, an `int`,
## because a reach is a whole count of pixels.
##
## **The reads.** `premultiplied` and `straight` are the neighbourhood library's
## `sa_premultiplied` and `sa_straight` under the names a pixel function reads
## them by, since Sara keeps colour as straight alpha and a mean of straight
## colour lets a transparent neighbour, black where nothing was painted, darken
## a soft edge. `src[at]` reads as `src(at)`, the bracket the dialect gives an
## image, so a student writes a read of the layer the way they write a read of
## any image.
##
## Static, and preloaded by path for the reason every part of the compiler is.
@tool
extends RefCounted

## What a piece of text holds, reached by path the way the dialect reaches it.
const GmacsScan := preload("res://core/custom-shader/dialect/sa_gmacs_scan.gd")

## The hint that makes a uniform the reach.
const REACH_HINT: String = "hint_reach"

## The type a reach is.
const REACH_TYPE: String = "int"

## The function the wrapper reads the layer through, which a bracket after its
## name calls.
const SOURCE_READ: String = "src"


## *code*, one line of a pixel function with its comment taken off, with every
## `src[...]` written as `src(...)`, outside string literals, an index holding a
## bracket of its own included.
static func bracketed(code: String) -> String:
    var opener := RegEx.new()
    opener.compile("(?<![\\w.])%s\\s*\\[" % SOURCE_READ)
    var out := ""
    for span: Array in GmacsScan.code_spans(code):
        var piece := str(span[0])
        if GmacsScan.is_quoted(span):
            out += piece
            continue
        var at := 0
        var found := opener.search(piece, at)
        while found != null:
            var close := closing(piece, found.get_end() - 1)
            if close < 0:
                break
            var index := bracketed(piece.substr(found.get_end(), close - found.get_end()).strip_edges())
            out += piece.substr(at, found.get_start() - at)
            out += "%s(%s)" % [SOURCE_READ, index]
            at = close + 1
            found = opener.search(piece, at)
        out += piece.substr(at)
    return out


## The index of the bracket that closes the one at *open* in *text*, or -1.
static func closing(text: String, open: int) -> int:
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


## `premultiplied` and `straight`, appended to *lines* of a generated wrapper.
## Written as the neighbourhood library writes them, so a pixel function's mean
## is the texel for texel mean a written kernel takes.
static func declare(lines: PackedStringArray) -> void:
    lines.append("def premultiplied(vec4 color) -> vec4:")
    lines.append("    return vec4(color.rgb * color.a, color.a)")
    lines.append("")
    lines.append("")
    lines.append("def straight(vec4 sum) -> vec4:")
    lines.append("    if sum.a == 0.0:")
    lines.append("        return vec4(0.0)")
    lines.append("    return vec4(sum.rgb / sum.a, sum.a)")
    lines.append("")
    lines.append("")


## The uniform of *fields* that carries [const REACH_HINT], or an empty
## Dictionary when none does.
static func reaching(fields: Array) -> Dictionary[String, Variant]:
    for raw: Variant in fields:
        var field := SaTyped.strings(raw)
        var hints: Dictionary = field.get("hints", {})
        if hints.has(REACH_HINT):
            return field
    var none: Dictionary[String, Variant] = {}
    return none


## The most *field*, a reaching uniform, reads: the hint's number, or the
## range's highest when it gives none, and never below the value the line
## declared. A slider of it may be typed up to this and no further.
static func ceiling(field: Dictionary[String, Variant]) -> int:
    var hints: Dictionary = field.get("hints", {})
    var given: PackedStringArray = hints.get(REACH_HINT, PackedStringArray())
    var most := roundi(SaTyped.float_at(field, "maximum", 0.0))
    if given.size() == 1 and given[0].is_valid_int():
        most = given[0].to_int()
    return maxi(most, SaTyped.int_at(field, "default", 0))


## How far a run of *field* reads, from *values*, the uniforms' values by name,
## or the value the line declared when *values* holds none, kept between nought
## and [method ceiling].
static func reach(field: Dictionary[String, Variant], values: Dictionary) -> int:
    var field_name := SaTyped.text_at(field, "name", "")
    var held: Variant = values.get(field_name, field.get("default", 0))
    var whole := roundi(SaTyped.real(held, 0.0))
    return clampi(whole, 0, ceiling(field))


## What is wrong with the reach *fields* declare, in the order a reader meets
## it, empty when nothing is.
static func problems(fields: Array) -> PackedStringArray:
    var out := PackedStringArray()
    var first := ""
    for raw: Variant in fields:
        var field := SaTyped.strings(raw)
        var hints: Dictionary = field.get("hints", {})
        if not hints.has(REACH_HINT):
            continue
        var line := SaTyped.int_at(field, "line", 0)
        var field_name := SaTyped.text_at(field, "name", "")
        var written := SaTyped.text_at(field, "type", "")
        var given: PackedStringArray = hints[REACH_HINT]
        if not first.is_empty():
            out.append(
                (
                    "line %d gives `%s` a %s, and `%s` already carries it, so a function reads one reach."
                    % [line, field_name, REACH_HINT, first]
                )
            )
            continue
        first = field_name
        if written != REACH_TYPE or SaTyped.int_at(field, "length", 0) != 0:
            out.append(
                "line %d gives the %s `%s` a %s, which only an %s takes." % [line, written, field_name, REACH_HINT, REACH_TYPE]
            )
        elif given.size() > 1 or (given.size() == 1 and (not given[0].is_valid_int() or given[0].to_int() < 1)):
            var said := "line %d gives `%s` a %s this cannot read." % [line, field_name, REACH_HINT]
            out.append(said + " It takes nothing, or the most it reads, a whole number above nought.")
    return out
