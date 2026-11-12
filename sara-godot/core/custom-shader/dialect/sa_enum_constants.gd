## The names a pixel function's `hint_enum` choices are given in the kernel it
## is wrapped in, one `const int` per choice equal to its index, so a body can
## write `if dither == DITHER_WHITE_NOISE:` rather than a bare number a reader
## has to count the labels for.
##
## A name is the parameter's own name and the label, upper-cased, with every run
## of characters that are not ASCII letters or digits made one underscore and
## none at either end: `"White noise"` of `dither` is `DITHER_WHITE_NOISE`. The
## parameter's name leads because a bare label meets the body's own names at
## once, a dithering kernel's `const float BAYER[16]` beside the label "Bayer"
## the first of them. A name that cannot be formed or would clash is a problem
## naming it and the uniform's line, never a quiet rename, because a renamed
## constant is one the body cannot know to write.
##
## Static and textual, as `sa_pixel_source.gd` is, which preloads it.
@tool
extends RefCounted


## The constants *fields* give, as `[name, index, line]` triples in the order the
## uniforms and their labels are written. *fields* is what
## `PixelSource.uniforms()` read, and a uniform with no choices gives none.
static func of(fields: Array) -> Array:
    var out: Array = []
    for raw: Variant in fields:
        var field: Dictionary = raw
        var labels: PackedStringArray = field.get("choices", PackedStringArray())
        var at_line: int = field.get("line", 0)
        for index in labels.size():
            out.append([name_of(str(field["name"]), labels[index]), index, at_line])
    return out


## The constant the choice *label* of the parameter *field_name* is named,
## or "" when the label holds no ASCII letter or digit to form one from.
static func name_of(field_name: String, label: String) -> String:
    var words := _words_of(label)
    if words.is_empty():
        return ""
    return "%s_%s" % [field_name.to_upper(), words]


## *label* upper-cased with every run of characters outside A to Z and 0 to 9
## made one underscore, and none left at either end.
static func _words_of(label: String) -> String:
    var runs := RegEx.new()
    runs.compile("[^A-Z0-9]+")
    var joined := runs.sub(label.to_upper(), "_", true)
    return joined.trim_prefix("_").trim_suffix("_")


## The `const int` lines of *fields*' constants, appended to *lines* with a
## blank after them, and nothing at all when no uniform has choices, so a
## kernel with no `hint_enum` is the text it was.
static func declare(lines: PackedStringArray, fields: Array) -> void:
    var constants := of(fields)
    for each: Array in constants:
        lines.append("const int %s = %d" % [each[0], each[1]])
    if not constants.is_empty():
        lines.append("")
        lines.append("")


## Every constant of *fields* that cannot be declared, as a sentence naming the
## uniform's line: a label that forms no name, two choices that form one, and a
## name *raw_text* or the wrapper already uses, another uniform, a field of
## *reserved*, or a `def` or `const` of the body. A name a library the body
## imports declares is left to the compiler's redefinition error, which names
## that file and line.
static func problems(raw_text: String, fields: Array, reserved: Array[String]) -> PackedStringArray:
    var out := PackedStringArray()
    var taken := {}
    for name: String in reserved:
        taken[name] = "a name the wrapper declares itself"
    for raw: Variant in fields:
        var field: Dictionary = raw
        var at_line: int = field.get("line", 0)
        taken[str(field["name"])] = "the uniform on line %d" % at_line
    for name: String in _declared_by(raw_text):
        taken[name] = "a name the body declares"

    var formed := {}
    for raw: Variant in fields:
        var field: Dictionary = raw
        var field_name := str(field["name"])
        var line: int = field.get("line", 0)
        var labels: PackedStringArray = field.get("choices", PackedStringArray())
        for index in labels.size():
            var name := name_of(field_name, labels[index])
            if name.is_empty():
                out.append(
                    (
                        'line %d gives `%s` the choice "%s", which has no letter or digit to name its constant by.'
                        % [line, field_name, labels[index]]
                    )
                )
                continue
            if formed.has(name):
                out.append('line %d names two choices `%s`, %s and "%s".' % [line, name, formed[name], labels[index]])
                continue
            formed[name] = '"%s"' % labels[index]
            if taken.has(name):
                out.append('line %d names the choice "%s" `%s`, which is %s.' % [line, labels[index], name, taken[name]])
    return out


## The names *raw_text* declares at its top level by `def` or `const`.
static func _declared_by(raw_text: String) -> PackedStringArray:
    var shape := RegEx.new()
    shape.compile("(?m)^(?:def\\s+(\\w+)|const\\s+\\w+\\s+(\\w+))")
    var out := PackedStringArray()
    for found in shape.search_all(raw_text):
        out.append(found.get_string(1) if found.get_start(1) >= 0 else found.get_string(2))
    return out
