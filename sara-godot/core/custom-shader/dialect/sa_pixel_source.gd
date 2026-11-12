## The text half of the pixel function door: the `uniform` lines read into
## params, the student's body prepared for the paste, and the `.gmacs` the
## wrapper writes around it.
##
## The spec's shortest door is one function, `def pixel(ivec2 at) -> vec4`, and
## everything a kernel otherwise needs is written here: the two images, the
## params block, `src` with its out-of-bounds rule, and the kernel that stores
## what the function answered. Nothing in this file touches a RenderingDevice or
## reads a file, so every function is static and the whole generation is
## testable without a GPU, the way `sa_kernel_source.gd` beside it is.
##
## Preloaded by path rather than reached through a `class_name`, because a class
## name resolves only after the editor rescans its class cache.
@tool
extends RefCounted

## The images the wrapper declares. Prefixed, because `src` is the function the
## student calls and a GLSL uniform of that name would shadow it.
const SOURCE_IMAGE: String = "sa_source"
const TARGET_IMAGE: String = "sa_target"

## The name the student's own function is given in the generated source.
##
## `pixel` is the one word the dialect adds, an `ivec2` it declares on the
## kernel's signature line, so a function of that name is shadowed inside the
## kernel and the call does not compile. The rename is on the call syntax,
## `pixel(`, so a helper of the student's that calls it is renamed with it.
const PIXEL_FUNCTION: String = "pixel_function"

## The field the wrapper declares so `src` can answer in canvas coordinates.
## `SaPushConstants.with_region()` writes it from the region the dispatch covers, so
## nothing passes it by hand.
const ORIGIN_FIELD: String = "origin"

## The two names the wrapper gives every pixel function beside `src`, so a
## stateless effect and a simulation read time the same way: `step`, the
## number of the simulation's step being taken, the first being nought, and
## `t`, a filter's time in seconds as its time row holds it. Each reads nought
## where it means nothing, a step in a filter or a notebook cell and a time in
## a simulation. Declared in the params, so a `uniform` line may not take
## either name, which [method problems] says.
const STEP_FIELD: String = "step"
const TIME_FIELD: String = "t"

## What a student's call of GLSL's `step()` is renamed to, since a field named
## `step` hides the built-in function wherever the params are in scope.
## [method _declare_step] writes it with every overload the built-in has.
const STEP_FUNCTION: String = "sa_step"

## The names the wrapper declares in every form, which no `uniform` line takes.
const PROVIDED_FIELDS: Array[String] = [ORIGIN_FIELD, STEP_FIELD, TIME_FIELD]

## The selection the pass form mixes by, at `SaSelection.BINDING`, the second
## image it declares.
const MASK_IMAGE: String = "sa_mask"

## The fields the pass form declares before the uniforms: the two places and the
## padding `SaNeighbourhoodPass.Runner` writes per dispatch, then the document's
## colour space as `SaColorSpacePushConstant` writes it, split by name the way
## `edge_detection.gmacs` declares it. A `uniform` line may name none of them
## there, which [method layered_problems] says.
const LAYERED_FIELDS: Array[String] = [
    "origin",
    "chunk",
    "halo",
    "doc_to_linear_srgb",
    "linear_srgb_to_doc",
    "transfer_slope",
    "transfer_threshold",
    "transfer_gain",
    "transfer_exponent",
    "coordinates",
]

## The params types a push constant understands, which is what a `uniform` line
## may declare. `SaKernelSource.STD430_TYPES` is the same set on the compiler's
## side, and a type outside it is a problem rather than a block the packer would
## silently mis-measure. A `bool` travels as the 32-bit word GLSL gives one in a
## block, nought or one.
const PARAM_TYPES: Array[String] = ["float", "int", "uint", "bool", "vec2", "vec3", "vec4"]

## How many floats each vector type takes, for reading a default apart.
const VECTOR_WIDTHS := {"vec2": 2, "vec3": 3, "vec4": 4}

## The one type an array `uniform` may be, which makes it a matrix: `uniform
## float weights[9]` is a grid of numbers, 3 by 3 and read row by row, for a
## convolution. Flat arrays, the way `composite.gmacs` declares its colour
## matrices, so GLSL's `mat3` is no grid.
const MATRIX_TYPE: String = "float"

## The hint that makes a slider, `hint_range(<min>, <max>[, <step>])`, and the
## types it may sit on, which are the ones a slider can hold.
const RANGE_HINT: String = "hint_range"
const RANGED_TYPES: Array[String] = ["float", "int", "uint"]

## The hint that makes a colour picker, `source_color`, and the types it may sit
## on. Godot's spelling and not Godot's meaning: the kernel gets the very numbers
## the picker shows, sRGB encoded the way `src()` hands a pixel, with no
## conversion to linear light, so the number a student reads off the picker is
## the number the kernel computes with.
const COLOUR_HINT: String = "source_color"
const COLOUR_TYPES: Array[String] = ["vec3", "vec4"]

## The hint that makes a drop-down, `hint_enum("<label>", ...)`, and the type it
## sits on. The kernel gets the picked entry's index, as a Godot shader does,
## and each entry is a constant of that index the body can name, which
## `sa_enum_constants.gd` forms.
const ENUM_HINT: String = "hint_enum"
const ENUM_TYPES: Array[String] = ["int"]

## The hints a `uniform` line may carry after a colon, in Godot's spelling. A
## hint outside this list is a problem rather than a word quietly dropped,
## because a misspelt `hint_rnage` would otherwise open a slider from 0 to 1
## and say nothing. The last is Sara's own, the reach `sa_pixel_neighbourhood.gd`
## reads.
const HINTS: Array[String] = [RANGE_HINT, ENUM_HINT, COLOUR_HINT, PixelNeighbourhood.REACH_HINT]

## How far a pixel function reads and the reads beside `src`, kept in a file of
## their own.
const PixelNeighbourhood := preload("res://core/custom-shader/dialect/sa_pixel_neighbourhood.gd")

## The further images a pixel function declares, lifted into the wrapper, kept
## in a file of their own.
const PixelImages := preload("res://core/custom-shader/dialect/sa_pixel_images.gd")

## The scan the transpiler reads `.gmacs` with, for a hint's colon and a
## literal's quotes.
const GmacsScan := preload("res://core/custom-shader/dialect/sa_gmacs_scan.gd")

## The named constant each `hint_enum` choice becomes, kept in a file of its own.
const EnumConstants := preload("res://core/custom-shader/dialect/sa_enum_constants.gd")


## The code half and the comment half of *line*, the comment without its hash.
##
## The transpiler's own scan, so a hash inside a quoted hint argument stays in
## the code rather than starting a comment.
static func split_comment(line: String) -> Array:
    var split := GmacsScan.split_comment(line)
    return [split[0], split[1]]


## The `uniform` lines of *raw_text*, in declaration order.
##
## Each entry is `{name, type, length, default, minimum, maximum, step, ranged,
## choices, hints, line}`. `ranged` says whether the line declared its slider's
## numbers, the way a Godot shader does as `uniform float level: hint_range(0,
## 1) = 0.5`, or as the `# range 0 1` comment that came first, which is still
## read so a saved kernel keeps its slider. The hint wins where a line has both.
## `step` is the hint's third number, and nought when it gave none, which leaves
## the slider its own. `choices` is the labels of a `hint_enum` in order, empty
## when the line has none or they are not all quoted. `hints` is every hint by
## name with its arguments as written, so [method problems] can refuse one and a
## widget can read its own. `line` is the student's own line number, so a
## problem can name it.
##
## `length` is nought for a scalar or a vector and the count an array declared
## for a matrix, -1 when its brackets hold no count this can read, and a
## matrix's `default` is its numbers row by row. A declaration whose brackets
## are still open at the end of its line goes on over the lines that close
## them, the dialect's own rule, so a 3 by 3 default may be written as the
## three rows it is.
static func uniforms(raw_text: String) -> Array:
    var declaration := RegEx.new()
    declaration.compile("^uniform\\s+(\\w+)\\s+(\\w+)\\s*(?:\\[([^\\]]*)\\])?$")
    var range_comment := RegEx.new()
    range_comment.compile("^\\s*range\\s+(\\S+)\\s+(\\S+)\\s*$")

    var out: Array = []
    var lines := raw_text.split("\n")
    var i := -1
    while i + 1 < lines.size():
        i += 1
        var halves := split_comment(lines[i])
        var code := str(halves[0]).strip_edges()
        if not code.begins_with("uniform"):
            continue
        var first := i
        i = _statement_end(lines, first)
        for more in range(first + 1, i + 1):
            code += " " + str(split_comment(lines[more])[0]).strip_edges()
        var parts := GmacsScan.declaration_parts(code)
        var found := declaration.search(str(parts[0]))
        if found == null:
            continue
        var length := 0 if found.get_start(3) < 0 else _length_of(found.get_string(3))
        var entry: Dictionary[String, Variant] = {
            "name": found.get_string(2),
            "type": found.get_string(1),
            "length": length,
            "default": _matrix_value(length, parts[2]) if length != 0 else _declared_value(found.get_string(1), parts[2]),
            "minimum": 0.0,
            "maximum": 1.0,
            "step": 0.0,
            "ranged": false,
            "choices": PackedStringArray(),
            "hints": _hints_of(parts[1]),
            "line": first + 1,
        }
        var hints: Dictionary[String, PackedStringArray] = entry["hints"]
        var hinted := _range_numbers(hints[RANGE_HINT] if hints.has(RANGE_HINT) else PackedStringArray())
        var commented := range_comment.search(str(halves[1]))
        if not hinted.is_empty():
            entry["minimum"] = hinted[0]
            entry["maximum"] = hinted[1]
            entry["step"] = hinted[2] if hinted.size() > 2 else 0.0
            entry["ranged"] = true
        elif commented != null:
            entry["minimum"] = commented.get_string(1).to_float()
            entry["maximum"] = commented.get_string(2).to_float()
            entry["ranged"] = true
        if hints.has(ENUM_HINT):
            entry["choices"] = _labels_of(hints[ENUM_HINT])
        out.append(entry)
    return out


## The last line of the statement that opens on line *at* of *lines*: *at*
## itself, or the line its open brackets close on.
static func _statement_end(lines: PackedStringArray, at: int) -> int:
    var depth := GmacsScan.bracket_delta(str(split_comment(lines[at])[0]))
    var last := at
    while depth > 0 and last + 1 < lines.size():
        last += 1
        depth += GmacsScan.bracket_delta(str(split_comment(lines[last])[0]))
    return last


## The numbers of a `hint_range`'s *arguments*, `[min, max]` or `[min, max,
## step]`, or empty when they are not two or three numbers or the step is not
## above nought.
static func _range_numbers(arguments: PackedStringArray) -> Array[float]:
    var numbers: Array[float] = []
    if arguments.size() < 2 or arguments.size() > 3:
        return numbers
    for argument in arguments:
        if not argument.is_valid_float():
            numbers.clear()
            return numbers
        numbers.append(argument.to_float())
    if numbers.size() > 2 and numbers[2] <= 0.0:
        numbers.clear()
    return numbers


## The labels of a `hint_enum`'s *arguments* without their quotes, or empty when
## there are none or one is not a quoted string.
static func _labels_of(arguments: PackedStringArray) -> PackedStringArray:
    var labels := PackedStringArray()
    for argument in arguments:
        if argument.length() < 2 or not argument.begins_with('"') or not argument.ends_with('"'):
            return PackedStringArray()
        labels.append(argument.substr(1, argument.length() - 2))
    return labels


## The hints after a declaration's colon, by name, each with its arguments as
## written. *text* is null when the line has no colon, and an empty name stands
## for a colon with nothing after it, so a problem can say so.
static func _hints_of(text: Variant) -> Dictionary[String, PackedStringArray]:
    var out: Dictionary[String, PackedStringArray] = {}
    if text == null:
        return out
    var written := str(text)
    if written.is_empty():
        out[""] = PackedStringArray()
        return out
    var shape := RegEx.new()
    shape.compile("^(\\w+)\\s*(?:\\((.*)\\))?$")
    for hint: String in GmacsScan.split_args(written):
        var found := shape.search(hint)
        if found == null:
            out[hint] = PackedStringArray()
            continue
        out[found.get_string(1)] = PackedStringArray(GmacsScan.split_args(found.get_string(2)))
    return out


## The count between an array's brackets, *text*, or -1 when it is not a whole
## number above nought.
static func _length_of(text: String) -> int:
    var written := text.strip_edges()
    if not written.is_valid_int() or written.to_int() < 1:
        return -1
    return written.to_int()


## A matrix of *length* numbers as its line declared it, row by row, or null
## when *written* is a default this cannot read or the length is not a square.
##
## Godot's braces, `{1.0, 2.0, 1.0, ...}`, and GLSL's constructor, `float[9](...)`
## or `float[](...)`, are both read. With no default at all the matrix holds a
## one in the middle, which a convolution reads as the picture unchanged.
static func _matrix_value(length: int, written: Variant) -> Variant:
    if _side_of(length) < 1:
        return null
    if written == null:
        return unchanged_matrix(length)
    var text := str(written).strip_edges()
    var shape := RegEx.new()
    shape.compile("^(?:\\{(.*)\\}|%s\\s*\\[\\s*(\\d*)\\s*\\]\\s*\\((.*)\\))$" % MATRIX_TYPE)
    var found := shape.search(text)
    if found == null:
        return null
    var sized := found.get_string(2)
    if not sized.is_empty() and sized.to_int() != length:
        return null
    var listed := found.get_string(1) if found.get_start(1) >= 0 else found.get_string(3)
    var numbers: Array = []
    for part in listed.split(","):
        var number := part.strip_edges()
        if not number.is_valid_float():
            return null
        numbers.append(number.to_float())
    if numbers.size() != length:
        return null
    return numbers


## The n by n matrix of *length* numbers that a convolution reads as the picture
## unchanged: nought everywhere and a one in the middle, row by row. The middle
## of an even side is the entry after it, row n / 2 and column n / 2, which is
## where a kernel centred on `n / 2` reads its own pixel. Empty when *length*
## is not a square.
static func unchanged_matrix(length: int) -> Array:
    var side := _side_of(length)
    var out: Array = []
    if side < 1:
        return out
    out.resize(length)
    out.fill(0.0)
    @warning_ignore("integer_division")
    var middle := side / 2
    out[middle * side + middle] = 1.0
    return out


## The side of a square matrix of *length* numbers, or 0 when *length* is not a
## square.
static func _side_of(length: int) -> int:
    if length < 1:
        return 0
    var side := roundi(sqrt(float(length)))
    return side if side * side == length else 0


## The value a `uniform` line declared after its equals sign, read as *type*.
## *written* is null when the line has no equals sign, which reads as zero, and
## an equals sign with nothing after it is a default this cannot read.
static func _declared_value(type_name: String, written: Variant) -> Variant:
    if written == null:
        return _value_of(type_name, "")
    var text := str(written)
    return null if text.is_empty() else _value_of(type_name, text)


## *text* read as a value of *type*, or null when it is neither a number nor a
## constructor of literals. A `uniform` with no value at all reads as zero,
## because a slider has to open somewhere.
static func _value_of(type_name: String, text: String) -> Variant:
    var written := text.strip_edges()
    if type_name == "bool":
        if written.is_empty() or written == "false":
            return false
        if written == "true":
            return true
        return null
    if type_name in ["int", "uint"]:
        if written.is_empty():
            return 0
        if not written.is_valid_int():
            return null
        return written.to_int()
    if type_name == "float":
        if written.is_empty():
            return 0.0
        if not written.is_valid_float():
            return null
        return written.to_float()
    if not VECTOR_WIDTHS.has(type_name):
        return null
    if written.is_empty():
        return _zero_of(type_name)

    var constructor := RegEx.new()
    constructor.compile("^%s\\s*\\((.*)\\)$" % type_name)
    var found := constructor.search(written)
    if found == null:
        return null
    var numbers: Array[float] = []
    for part in found.get_string(1).split(","):
        var number := part.strip_edges()
        if not number.is_valid_float():
            return null
        numbers.append(number.to_float())
    var width: int = VECTOR_WIDTHS[type_name]
    if numbers.size() == 1:
        numbers.resize(width)
        numbers.fill(numbers[0])
    if numbers.size() != width:
        return null
    if width == 2:
        return Vector2(numbers[0], numbers[1])
    if width == 3:
        return Vector3(numbers[0], numbers[1], numbers[2])
    return Vector4(numbers[0], numbers[1], numbers[2], numbers[3])


static func _zero_of(type_name: String) -> Variant:
    match type_name:
        "vec2":
            return Vector2.ZERO
        "vec3":
            return Vector3.ZERO
        "vec4":
            return Vector4.ZERO
    return 0.0


## Everything wrong with *raw_text* as a pixel function, in the order a reader
## meets it, empty when there is nothing.
##
## Read before anything is generated, because a file that declares a type the
## packer cannot measure produces a block whose size is a guess, and
## RenderingDevice reports a wrong push constant size as the constant being
## absent.
static func problems(raw_text: String, stem: String) -> PackedStringArray:
    var out := PackedStringArray()
    var name_shape := RegEx.new()
    name_shape.compile("^\\w+$")
    if name_shape.search(stem) == null:
        out.append("the file name '%s' is not a word, and the generated kernel imports it by name." % stem)

    var signature := RegEx.new()
    signature.compile("(?m)^def\\s+pixel\\s*\\(")
    if signature.search(raw_text) == null:
        out.append("no `def pixel(ivec2 at) -> vec4` in the file, which is the one function this door takes.")

    for field: Dictionary[String, Variant] in uniforms(raw_text):
        var written := str(field["type"])
        var field_name := str(field["name"])
        var length: int = field["length"]
        if length != 0:
            out.append_array(_matrix_problems(field))
        elif not written in PARAM_TYPES:
            out.append("line %d declares `%s`, and a uniform is one of %s." % [field["line"], written, ", ".join(PARAM_TYPES)])
        elif field["default"] == null:
            out.append("line %d gives `%s` a default this cannot read as a %s." % [field["line"], field_name, written])
        if field_name in PROVIDED_FIELDS:
            out.append("line %d names a uniform `%s`, which the wrapper declares itself." % [field["line"], field_name])
        out.append_array(_hint_problems(field))
    out.append_array(PixelNeighbourhood.problems(uniforms(raw_text)))
    out.append_array(EnumConstants.problems(raw_text, uniforms(raw_text), _wrapper_names()))
    out.append_array(PixelImages.problems(raw_text, [SOURCE_IMAGE, TARGET_IMAGE, MASK_IMAGE, PixelNeighbourhood.SOURCE_READ]))
    return out


## The names either wrapper declares beside the uniforms, which no constant a
## `hint_enum` choice forms may take.
static func _wrapper_names() -> Array[String]:
    var out: Array[String] = []
    out.append_array(PROVIDED_FIELDS)
    out.append_array(LAYERED_FIELDS)
    out.append_array([SOURCE_IMAGE, TARGET_IMAGE, MASK_IMAGE, PIXEL_FUNCTION, STEP_FUNCTION, "src", "luminance"])
    return out


## What [method problems] leaves to the pass form: a uniform named after a field
## of [const LAYERED_FIELDS] other than `origin`, which that form declares itself.
## Empty when there is nothing. Asked only of a file a filter records as a pass
## or a simulation steps by, so a notebook cell that calls a uniform `halo`
## keeps it.
static func layered_problems(fields: Array) -> PackedStringArray:
    var out := PackedStringArray()
    for raw: Variant in fields:
        var field: Dictionary = raw
        var field_name := str(field.get("name", ""))
        if field_name != ORIGIN_FIELD and field_name in LAYERED_FIELDS:
            out.append("line %d names a uniform `%s`, which a filter's pass declares itself." % [field["line"], field_name])
    return out


## What is wrong with one matrix uniform *field*, empty when nothing is.
##
## A length that is not a square is refused rather than drawn as one row,
## because a row of numbers is a different widget nobody asked for, and so is
## an array of anything but MATRIX_TYPE.
static func _matrix_problems(field: Dictionary[String, Variant]) -> PackedStringArray:
    var out := PackedStringArray()
    var line: int = field["line"]
    var field_name := str(field["name"])
    var written := str(field["type"])
    var length: int = field["length"]
    if written != MATRIX_TYPE:
        out.append(
            (
                "line %d declares `%s` an array of %s, and an array uniform is a matrix of %s."
                % [line, field_name, written, MATRIX_TYPE]
            )
        )
    elif length < 1:
        out.append("line %d gives `%s` a length this cannot read, and a matrix's is a count such as 9." % [line, field_name])
    elif _side_of(length) < 1:
        out.append(
            (
                "line %d gives `%s` %d numbers, which is not a square, and a matrix is n by n, such as 9, 25 or 49."
                % [line, field_name, length]
            )
        )
    elif field["default"] == null:
        out.append("line %d gives `%s` a default this cannot read as %d numbers." % [line, field_name, length])
    return out


## What is wrong with the hints of one uniform *field*, empty when nothing is.
static func _hint_problems(field: Dictionary[String, Variant]) -> PackedStringArray:
    var out := PackedStringArray()
    var line: int = field["line"]
    var field_name := str(field["name"])
    var hints: Dictionary[String, PackedStringArray] = field["hints"]
    var length: int = field["length"]
    if length != 0 and not hints.is_empty():
        out.append("line %d gives the matrix `%s` a hint, and a grid of numbers takes none." % [line, field_name])
        return out
    for hint: String in hints:
        if hint.is_empty():
            out.append("line %d has a colon after `%s` and no hint after it." % [line, field_name])
        elif not hint in HINTS:
            out.append("line %d gives `%s` the hint `%s`, and a uniform takes %s." % [line, field_name, hint, ", ".join(HINTS)])
    out.append_array(_enum_problems(field))
    var written := str(field["type"])
    if hints.has(COLOUR_HINT) and not written in COLOUR_TYPES:
        out.append(
            (
                "line %d gives the %s `%s` a %s, which only %s take."
                % [line, written, field_name, COLOUR_HINT, ", ".join(COLOUR_TYPES)]
            )
        )
    if not hints.has(RANGE_HINT):
        return out
    if not written in RANGED_TYPES:
        out.append(
            (
                "line %d gives the %s `%s` a %s, which only %s take."
                % [line, written, field_name, RANGE_HINT, ", ".join(RANGED_TYPES)]
            )
        )
    elif _range_numbers(hints[RANGE_HINT]).is_empty():
        out.append(
            (
                "line %d gives `%s` a %s this cannot read. It takes a lowest, a highest and maybe a step above nought."
                % [line, field_name, RANGE_HINT]
            )
        )
    return out


## What is wrong with the `hint_enum` of one uniform *field*, empty when nothing
## is or it has none.
static func _enum_problems(field: Dictionary[String, Variant]) -> PackedStringArray:
    var out := PackedStringArray()
    var hints: Dictionary[String, PackedStringArray] = field["hints"]
    if not hints.has(ENUM_HINT):
        return out
    var line: int = field["line"]
    var field_name := str(field["name"])
    var written := str(field["type"])
    if not written in ENUM_TYPES:
        var taken := ", ".join(ENUM_TYPES)
        out.append("line %d gives the %s `%s` a %s, which only %s take." % [line, written, field_name, ENUM_HINT, taken])
    elif _labels_of(hints[ENUM_HINT]).is_empty():
        var said := "line %d gives `%s` a %s this cannot read." % [line, field_name, ENUM_HINT]
        out.append(said + " It takes one quoted label per entry.")
    return out


## Whether the function in *raw_text* reads [const TIME_FIELD], the time a
## filter's time row holds: the name stands on its own in the code, as no
## member and in no comment, and the file does not declare a `t` of its own,
## which would be the student's and not the time.
static func reads_time(raw_text: String) -> bool:
    var named := RegEx.new()
    named.compile("(?<![\\w.])%s(?!\\w)" % TIME_FIELD)
    var declared := RegEx.new()
    declared.compile("\\b(?:float|int|uint|bool|[iu]?vec[234]|mat[234])\\s+%s\\b" % TIME_FIELD)
    var read := false
    for line in raw_text.split("\n"):
        var code := str(split_comment(line)[0])
        if declared.search(code) != null:
            return false
        if not code.strip_edges().begins_with("uniform") and named.search(code) != null:
            read = true
    return read


## The libraries *raw_text* imports, by the name each `import` line gives, in
## the order written. The wrappers paste them above the params block, so a
## library that calls GLSL's `step()` reads the built-in and not the field
## of that name declared below it. The body still imports them, and the paste
## skips a file it already holds.
static func imports(raw_text: String) -> PackedStringArray:
    var line_form := RegEx.new()
    line_form.compile("^import\\s+([\\w/.-]+)$")
    var out := PackedStringArray()
    for line in raw_text.split("\n"):
        var found := line_form.search(str(split_comment(line)[0]).strip_edges())
        if found != null:
            out.append(found.get_string(1))
    return out


## The student's own text as the generated kernel imports it: the `uniform`
## lines gone, because they are declared in the params block instead, the
## `image` lines gone and a bracket on one written as its load, because
## [method wrap] declares them, the
## function renamed off the dialect's own word, and a call of GLSL's `step()`
## renamed to [const STEP_FUNCTION], off the field the wrapper declares.
##
## A line that goes is blanked rather than dropped, so the paste is the same
## count of lines as the file and the compiler's line map names the student's
## own line. That map is the whole reason this is an import and not a splice:
## `sa_include_processor.gd` already attributes a pasted line to the file it came
## from, and a generated wrapper that inlined the body would have to teach it a
## second mechanism.
static func body(raw_text: String) -> String:
    var declaration := RegEx.new()
    declaration.compile("^uniform\\s+\\w+\\s+\\w+")
    var invocation := RegEx.new()
    invocation.compile("\\bpixel\\s*\\(")
    # Not after a dot, so a member of the student's own called `step` keeps
    # its name.
    var stepped := RegEx.new()
    stepped.compile("(?<![\\w.])%s\\s*\\(" % STEP_FIELD)

    var images := PixelImages.names(raw_text)
    var out := PackedStringArray()
    var lines := raw_text.split("\n")
    var i := 0
    while i < lines.size():
        var line := lines[i]
        var halves := split_comment(line)
        var code := str(halves[0])
        if PixelImages.is_declaration(code):
            out.append("")
            i += 1
            continue
        if declaration.search(code.strip_edges()) != null:
            # Every line the declaration spans, so a matrix written as its rows
            # leaves none of them behind in the body.
            var last := _statement_end(lines, i)
            for _blank in range(i, last + 1):
                out.append("")
            i = last + 1
            continue
        var renamed := PixelImages.read(
            PixelNeighbourhood.bracketed(
                stepped.sub(invocation.sub(code, PIXEL_FUNCTION + "(", true), STEP_FUNCTION + "(", true)
            ),
            images
        )
        out.append(renamed + ("#" + str(halves[1]) if line.contains("#") else ""))
        i += 1
    return "\n".join(out)


## The `.gmacs` written around a pixel function: the declarations, `src`, the
## helpers the spec's own example reaches for, the import of the body and the
## kernel that stores what the function answered.
##
## *kernel_name* is the entry point, *include_name* is what the body is
## registered as so the paste carries the student's file name, and *fields* is
## what `uniforms()` read. *imported* is what [method imports] read, pasted
## above the params block, and *images* what `PixelImages.declared()` read,
## declared after the wrapper's own pair so each takes a binding of its own. The text is the dialect rather than GLSL, so a
## student who opens the generated file reads the same language they wrote.
static func wrap(
    kernel_name: String,
    include_name: String,
    fields: Array,
    imported: PackedStringArray = PackedStringArray(),
    images: Array = []
) -> String:
    var lines := PackedStringArray()
    lines.append("# Generated from %s.gmacs by core/custom-shader/dialect/sa_pixel_source.gd." % include_name.get_file())
    lines.append("# The module's author writes the pixel and its sliders, this writes the rest.")
    lines.append("")
    lines.append("kernel %s" % kernel_name)
    lines.append("")
    _hoist(lines, imported)
    lines.append("image %s: readonly" % SOURCE_IMAGE)
    lines.append("image %s" % TARGET_IMAGE)
    PixelImages.declare(lines, images)
    lines.append("")
    lines.append("params:")
    lines.append("    vec2 %s" % ORIGIN_FIELD)
    _declare_provided(lines)
    _declare_uniforms(lines, fields)
    lines.append("")
    lines.append("")
    EnumConstants.declare(lines, fields)
    lines.append("def src(ivec2 at) -> vec4:")
    lines.append("    ivec2 at_source = at - ivec2(%s)" % ORIGIN_FIELD)
    lines.append("    ivec2 source_size = image_size(%s)" % SOURCE_IMAGE)
    lines.append("    if at_source.x < 0 or at_source.y < 0 or at_source.x >= source_size.x or at_source.y >= source_size.y:")
    lines.append("        return vec4(0.0)")
    lines.append("    return image_load(%s, at_source)" % SOURCE_IMAGE)
    lines.append("")
    lines.append("")
    lines.append("def luminance(vec3 rgb) -> float:")
    lines.append("    return dot(rgb, vec3(0.2126, 0.7152, 0.0722))")
    lines.append("")
    lines.append("")
    PixelNeighbourhood.declare(lines)
    _declare_step(lines)
    lines.append("import %s" % include_name)
    lines.append("")
    lines.append("")
    lines.append("def %s():" % kernel_name)
    lines.append("    ivec2 target_size = image_size(%s)" % TARGET_IMAGE)
    lines.append("    if pixel.x >= target_size.x or pixel.y >= target_size.y:")
    lines.append("        return")
    lines.append("    image_store(%s, pixel, %s(pixel + ivec2(%s)))" % [TARGET_IMAGE, PIXEL_FUNCTION, ORIGIN_FIELD])
    lines.append("")
    return "\n".join(lines)


## The pass form of [method wrap], the kernel a filter records rather than runs,
## so its pixel function previews on the canvas, applies, attaches and becomes
## an adjustment layer the way every built-in filter does.
##
## It keeps the contract on `SaNeighbourhoodPass`: the padded source at binding
## 0, the selection at binding 1, mixed by, and the chunk-sized target at
## binding 2, written at the chunk-local pixel. `src` reads the padded source
## in canvas coordinates through `chunk` and `halo`, and a position past the
## padding reads transparent, so a function that reads a neighbourhood declares
## the margin it reads within and the gather pads by it. Beside `src`,
## `luminance`, `premultiplied` and `straight` it offers the document's colour views the composite kernels
## read, `document_to_rgb` and `rgb_to_document` among them, over the colour
## space fields that follow the places in its params. On a document stored in
## RGB both are the identity, and on an Oklab one they keep a black or white
## from being written as orange. The arguments are [method wrap]'s.
##
## *in_place* writes the point form instead, the contract on `SaPointPass`
## every built-in point filter keeps: the chunk at binding 0, read and
## rewritten in place, and the selection at binding 1, with no halo. A filter
## with no margin records it, so a function that reads `at` alone is a point
## filter in every way a written one is, flattened on the document as well.
##
## Without *coloured* it writes the rule form, a simulation's step, which
## keeps the same contract with the halo the rule's reach declares, `src`
## reading the previous state, and no colour space. The step is handed no
## document, so the colour views are not offered, and the block it leaves to
## the uniforms is wider by what their fields took.
static func wrap_layered(
    kernel_name: String,
    include_name: String,
    fields: Array,
    in_place: bool = false,
    coloured: bool = true,
    imported: PackedStringArray = PackedStringArray()
) -> String:
    var read := TARGET_IMAGE if in_place else SOURCE_IMAGE
    var padded := "" if in_place else " + ivec2(halo)"
    var lines := PackedStringArray()
    lines.append("# Generated from %s.gmacs by core/custom-shader/dialect/sa_pixel_source.gd." % include_name.get_file())
    if coloured:
        lines.append("# The pass form: it reads the chunk, with a halo unless it runs in place, and")
        lines.append("# writes what the pixel function answered, mixed by the selection.")
    else:
        lines.append("# The rule form: it reads the previous state with the halo of the rule's reach,")
        lines.append("# and writes what the pixel function answered as the next.")
    lines.append("")
    lines.append("kernel %s" % kernel_name)
    lines.append("")
    if coloured:
        lines.append("import linear_srgb_color_space")
        lines.append("import transfer_curve")
        lines.append("")
    _hoist(lines, imported)
    if not in_place:
        lines.append("image %s: readonly" % SOURCE_IMAGE)
    else:
        lines.append("image %s" % TARGET_IMAGE)
    lines.append("image %s: r32f, readonly" % MASK_IMAGE)
    if not in_place:
        lines.append("image %s" % TARGET_IMAGE)
    lines.append("")
    lines.append("params:")
    lines.append("    vec2 origin")
    lines.append("    vec2 chunk")
    if not in_place:
        lines.append("    int halo")
    _declare_provided(lines)
    if coloured:
        lines.append("    float doc_to_linear_srgb[9]")
        lines.append("    float linear_srgb_to_doc[9]")
        for scalar: String in LAYERED_FIELDS.slice(5):
            lines.append("    float %s" % scalar)
    _declare_uniforms(lines, fields)
    lines.append("")
    if coloured:
        lines.append("import composite_color_space")
        lines.append("")
    lines.append("")
    EnumConstants.declare(lines, fields)
    lines.append("def src(ivec2 at) -> vec4:")
    lines.append("    ivec2 at_source = at - ivec2(chunk)%s" % padded)
    lines.append("    ivec2 source_size = image_size(%s)" % read)
    lines.append("    if at_source.x < 0 or at_source.y < 0 or at_source.x >= source_size.x or at_source.y >= source_size.y:")
    lines.append("        return vec4(0.0)")
    lines.append("    return image_load(%s, at_source)" % read)
    lines.append("")
    lines.append("")
    lines.append("def luminance(vec3 rgb) -> float:")
    lines.append("    return dot(rgb, vec3(0.2126, 0.7152, 0.0722))")
    lines.append("")
    lines.append("")
    PixelNeighbourhood.declare(lines)
    _declare_step(lines)
    lines.append("import %s" % include_name)
    lines.append("")
    lines.append("")
    lines.append("def %s():" % kernel_name)
    lines.append("    ivec2 at = pixel + ivec2(origin)")
    lines.append("    ivec2 target_size = image_size(%s)" % TARGET_IMAGE)
    lines.append("    if at.x >= target_size.x or at.y >= target_size.y:")
    lines.append("        return")
    lines.append("    vec4 kept = image_load(%s, at%s)" % [read, padded])
    lines.append("    float coverage = image_load(%s, min(at, image_size(%s) - 1)).r" % [MASK_IMAGE, MASK_IMAGE])
    lines.append("    image_store(%s, at, mix(kept, %s(ivec2(chunk) + at), coverage))" % [TARGET_IMAGE, PIXEL_FUNCTION])
    lines.append("")
    return "\n".join(lines)


## The params lines of [const STEP_FIELD] and [const TIME_FIELD], appended to
## *lines*.
static func _declare_provided(lines: PackedStringArray) -> void:
    lines.append("    int %s" % STEP_FIELD)
    lines.append("    float %s" % TIME_FIELD)


## An `import` line per name of *imported*, and a blank after them when there
## were any.
static func _hoist(lines: PackedStringArray, imported: PackedStringArray) -> void:
    for each: String in imported:
        lines.append("import %s" % each)
    if not imported.is_empty():
        lines.append("")


## [const STEP_FUNCTION], appended to *lines*: GLSL's `step()` with every
## overload it has, nought where *x* is below *edge* and one elsewhere. Written
## as the comparison rather than through the built-in, which the field named
## `step` hides here.
static func _declare_step(lines: PackedStringArray) -> void:
    lines.append("def %s(float edge, float x) -> float:" % STEP_FUNCTION)
    lines.append("    return 1.0 - float(x < edge)")
    for width: String in VECTOR_WIDTHS:
        for edge: String in [width, "float"]:
            lines.append("")
            lines.append("")
            lines.append("def %s(%s edge, %s x) -> %s:" % [STEP_FUNCTION, edge, width, width])
            lines.append("    return %s(1.0) - %s(lessThan(x, %s(edge)))" % [width, width, width])
    lines.append("")
    lines.append("")


## The params lines *fields* declare, appended to *lines*, a matrix with its
## count.
static func _declare_uniforms(lines: PackedStringArray, fields: Array) -> void:
    for field: Dictionary[String, Variant] in fields:
        var length: int = field.get("length", 0)
        var count := "[%d]" % length if length > 0 else ""
        lines.append("    %s %s%s" % [str(field["type"]), str(field["name"]), count])
