## What a piece of `.gmacs` text says before anything is rewritten: where its
## comment starts, how far it is indented, how deep its brackets go, which of it
## is a string literal, where its top-level commas are, and where a
## declaration's hint and value start.
##
## Every one of these answers is about the characters in front of it and nothing
## else. None of them reads the pass's state, none of them writes any, and all
## three of the files that make up the transpiler ask them: the pass asks for the
## comment and the indentation, the names ask which spans are literals, and the
## loop asks where the arguments of a `range` are. That is why this is a file of
## its own. The pixel function's uniforms ask it too, for the hint a `uniform`
## line declares.
##
## **The literal scan is the one everything else is built on.** A hash inside a
## string is not a comment, a bracket inside one is not a bracket and a comma
## inside one is not an argument, so there is one scan that finds the literals
## and four questions asked of its answer rather than four scanners that have to
## agree.
##
## Static and holding no state, so every case is testable without a
## RenderingDevice, and preloaded by path for the reason every part of the
## compiler is: a class name resolves only after the editor rescans its class
## cache.
@tool
extends RefCounted

## A tab counts as this many spaces when a line's indentation is measured, so a
## file that mixes them still nests the way it looks.
const TAB_WIDTH: int = 4


## Splits one physical line into its code and its `#` comment, as
## `[code, comment_text, had_one]`.
##
## A hash inside a string literal is not a comment, which is the whole reason
## this is a scan rather than a `find`.
static func split_comment(line: String) -> Array:
    var quote := ""
    var i := 0
    while i < line.length():
        var c := line[i]
        if not quote.is_empty():
            if c == "\\":
                i += 2
                continue
            if c == quote:
                quote = ""
        elif c == '"' or c == "'":
            quote = c
        elif c == "#":
            return [line.substr(0, i), line.substr(i + 1), true]
        i += 1
    return [line, "", false]


## Leading whitespace of *line* in spaces, a tab counting as TAB_WIDTH.
static func leading_space(line: String) -> int:
    var width := 0
    for i in line.length():
        if line[i] == " ":
            width += 1
        elif line[i] == "\t":
            width += TAB_WIDTH
        else:
            break
    return width


## Brackets opened minus brackets closed in *code*, ignoring string literals.
static func bracket_delta(code: String) -> int:
    var depth := 0
    for span: Array in code_spans(code):
        if is_quoted(span):
            continue
        for c in str(span[0]):
            if c == "(" or c == "[" or c == "{":
                depth += 1
            elif c == ")" or c == "]" or c == "}":
                depth -= 1
    return depth


## Whether *span*, one of `code_spans`, is a string literal.
static func is_quoted(span: Array) -> bool:
    var quoted: bool = span[1]
    return quoted


## *code* as `[text, is_string_literal]` spans, so a rewrite can skip the
## literals. The transpiler never touches an expression, and a word inside a
## string is not even that.
static func code_spans(code: String) -> Array:
    var spans: Array = []
    var quote := ""
    var start := 0
    var i := 0
    while i < code.length():
        var c := code[i]
        if quote.is_empty():
            if c == '"' or c == "'":
                spans.append([code.substr(start, i - start), false])
                start = i
                quote = c
        elif c == "\\":
            i += 1
        elif c == quote:
            spans.append([code.substr(start, i - start + 1), true])
            start = i + 1
            quote = ""
        i += 1
    if start < code.length():
        spans.append([code.substr(start), not quote.is_empty()])
    return spans


## Each line of *codes* as its spans, which is what the names ask for when they
## decide whether the file wants `pixel` declared.
static func spans_by_line(codes: Array) -> Array:
    var out: Array = []
    for code: String in codes:
        out.append(code_spans(code))
    return out


## One declaration cut at its hint's colon and its value's equals sign, as
## `[declared, hint, value]`, each stripped, the last two null when the line
## has none.
##
## `uniform float level: hint_range(0, 1) = 0.5` is `uniform float level`, the
## hint and `0.5`, and a params field `float scale: hint_range(2, 64)` is the
## same cut with no value. The hint is Godot's spelling of a slider, so the
## pixel function's uniforms and the dialect's params block read it through
## this one scan. Both marks count only outside brackets and literals, so a
## hint's own arguments and a quoted label in one never cut the line, and the
## colon has to come before the equals sign to be a hint's.
static func declaration_parts(code: String) -> Array:
    var colon := -1
    var equals := -1
    var depth := 0
    var at := 0
    for span: Array in code_spans(code):
        var text := str(span[0])
        if is_quoted(span):
            at += text.length()
            continue
        for i in text.length():
            var c := text[i]
            if c == "(" or c == "[" or c == "{":
                depth += 1
            elif c == ")" or c == "]" or c == "}":
                depth -= 1
            elif depth == 0 and c == ":" and colon < 0:
                colon = at + i
            elif depth == 0 and c == "=":
                equals = at + i
                break
        if equals >= 0:
            break
        at += text.length()
    var head_end := colon if colon >= 0 else (equals if equals >= 0 else code.length())
    var hint: Variant = null
    if colon >= 0:
        hint = code.substr(colon + 1, (equals if equals >= 0 else code.length()) - colon - 1).strip_edges()
    var value: Variant = null
    if equals >= 0:
        value = code.substr(equals + 1).strip_edges()
    return [code.substr(0, head_end).strip_edges(), hint, value]


## Top-level commas in *text*, so `range(a, f(b, c))` is two arguments.
static func split_args(text: String) -> Array:
    var args: Array = []
    var depth := 0
    var current := ""
    for span: Array in code_spans(text):
        if is_quoted(span):
            current += str(span[0])
            continue
        for c in str(span[0]):
            if c == "(" or c == "[" or c == "{":
                depth += 1
            elif c == ")" or c == "]" or c == "}":
                depth -= 1
            if c == "," and depth == 0:
                args.append(current.strip_edges())
                current = ""
                continue
            current += c
    if not current.strip_edges().is_empty():
        args.append(current.strip_edges())
    return args
