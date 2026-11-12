## What a word means in the dialect: GLSL's own spellings as snake_case, the
## word operators, and `pixel`.
##
## A dialect with two cases is two dialects. So the six built-in variables and every
## camelCase built-in a compute shader can call get snake spellings, both
## spellings compile so a line pasted out of the GLSL specification still works,
## and Sara's own kernels write snake only. `and`, `or` and `not` are the same
## question asked of three words GLSL spells with punctuation, and `pixel` is
## the one word the dialect adds that GLSL has no name for at all.
##
## **This file owns the two tables and their caches**, which is the whole of
## what the dialect knows about words, and it is why the file has its own name
## rather than the parent's plus a suffix. It asks `sa_gmacs_scan.gd` the same
## question the parent does rather than being handed an answer.
##
## Static, holding nothing but its two caches, and preloaded by path for the
## reason every part of the compiler is.
@tool
extends RefCounted

## The scan, so a rewrite can skip a string literal without a second scanner.
const GmacsScan := preload("res://core/custom-shader/dialect/sa_gmacs_scan.gd")

## The one word the dialect adds that GLSL has no name for, the pixel this run
## is for. Thirty-five of the tree's kernels open with the same
## `ivec2(gl_GlobalInvocationID.xy)`, so the transpiler declares it and the
## kernel reads `pixel` outright.
const PIXEL_NAME := "pixel"
const PIXEL_DECLARATION := "ivec2 pixel = ivec2(gl_GlobalInvocationID.xy);"

## The two name tables, GLSL spelling to snake spelling, beside this file so the
## formatter and the converter read the same one.
const NAMES_FILE := "res://core/custom-shader/gmacs_names.json"

## The file, read once. Static, because the transpiler is.
static var _names_cache: Dictionary[String, Dictionary] = {}

## The inverse of the file, snake spelling to GLSL spelling, which is the
## direction the transpiler rewrites in. Built once beside the cache.
static var _snake_cache: Dictionary[String, String] = {}


## The name tables as the file holds them, `variables` and `functions`, each
## GLSL spelling to snake spelling.
##
## That direction rather than the one the transpiler wants, because the two
## other readers want this one: `scripts/gmacs_format.py` rewrites a kernel to
## snake and `scripts/gmacs_convert.py` turns a GLSL kernel into the dialect. A
## table read backwards by one tool is cheaper than two files that come to
## disagree.
static func names() -> Dictionary[String, Dictionary]:
    if _names_cache.is_empty():
        var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(NAMES_FILE))
        if typeof(parsed) != TYPE_DICTIONARY:
            push_error("SaDialect: %s is not readable, so no snake name resolves." % NAMES_FILE)
            return {"variables": _spellings({}), "functions": _spellings({})}
        var table := SaTyped.strings(parsed)
        _names_cache = {"variables": _spellings(table.get("variables", {})), "functions": _spellings(table.get("functions", {}))}
    return _names_cache


## One half of the file as parsed, copied into a typed table, because JSON
## hands back an untyped Dictionary and every reader of the half wants names.
static func _spellings(parsed: Variant) -> Dictionary[String, String]:
    var out: Dictionary[String, String] = {}
    if parsed is Dictionary:
        var table: Dictionary = parsed
        out.assign(table)
    return out


## Snake spelling to GLSL spelling, both tables in one dictionary, which is what
## a rewrite needs and what nothing else does.
static func snake_table() -> Dictionary[String, String]:
    if _snake_cache.is_empty():
        var table := names()
        for half: String in ["variables", "functions"]:
            var pairs: Dictionary[String, String] = table[half]
            for glsl_name: String in pairs:
                _snake_cache[String(pairs[glsl_name])] = glsl_name
    return _snake_cache


## Whether the file wants `pixel` declared for it: it uses the word outside a
## string, and no line of it declares the word itself.
##
## A file that writes its own `ivec2 pixel = ...` keeps it, because a second
## declaration on the signature line would not compile, and a file that never
## says `pixel` gets no unused variable.
static func wants_pixel(spans_by_line: Array) -> bool:
    var used := RegEx.new()
    used.compile("(?<!\\.)\\b%s\\b" % PIXEL_NAME)
    var declared := RegEx.new()
    declared.compile("\\b\\w+\\s+%s\\s*=" % PIXEL_NAME)
    var wanted := false
    for spans: Array in spans_by_line:
        for span: Array in spans:
            if GmacsScan.is_quoted(span):
                continue
            var text := str(span[0])
            if declared.search(text) != null:
                return false
            if used.search(text) != null:
                wanted = true
    return wanted


## `and`, `or` and `not` as their GLSL symbols, outside string literals.
##
## Beside the snake rewrite rather than in the pass, because it is the same
## question: a word the dialect spells its own way, written the way GLSL spells
## it. The pass calls the two of them one after the other on the same line.
static func word_operators(code: String) -> String:
    var patterns := {"\\band\\b": "&&", "\\bor\\b": "||", "\\bnot\\b": "!"}
    var out := ""
    for span: Array in GmacsScan.code_spans(code):
        var text := str(span[0])
        if not GmacsScan.is_quoted(span):
            for pattern: String in patterns:
                var regex := RegEx.new()
                regex.compile(pattern)
                text = regex.sub(text, str(patterns[pattern]), true)
        out += text
    return out


## The dialect's snake names as GLSL's own, outside string literals.
##
## The one place this pass touches an expression, the one exception to the
## dialect's rule of rewriting nothing between the statement ends. Both spellings compile, so a line
## pasted out of the GLSL specification still works and only the snake form is
## rewritten.
##
## **The table's snake names are reserved**, and the rewrite is uniform: a
## params field or a struct member a file names `image_size` is renamed in its
## declaration and in every read of it, `p.image_size` included. Guarding a name
## after a dot is worse, because it renames the declaration
## and not the read, which is a file that stops compiling for a reason the
## error message does not carry. Renaming both leaves a kernel that works and a
## name the student can see was taken.
static func rewrite(spans: Array) -> String:
    var table := snake_table()
    var out := ""
    for span: Array in spans:
        var text := str(span[0])
        if not GmacsScan.is_quoted(span):
            for word: String in _words_in(text):
                if table.has(word):
                    var regex := RegEx.new()
                    regex.compile("\\b%s\\b" % word)
                    text = regex.sub(text, String(table[word]), true)
        out += text
    return out


## Every identifier in *text*, so the rewrite above runs one regex per word the
## line actually has rather than one per name in the table.
static func _words_in(text: String) -> Array:
    var regex := RegEx.new()
    regex.compile("[A-Za-z_]\\w*")
    var words := {}
    for found in regex.search_all(text):
        words[found.get_string()] = true
    return words.keys()
