## The Python-shaped `.gmacs` dialect, rewritten into the GLSL the rest of the
## compiler already reads.
##
## `.gmacs` in its GLSL form is GLSL 450 compute with four things read before glslang sees
## the file: `#kernel`, `#include`, the `[numthreads]` attribute and the storage
## format token. The dialect writes the same
## file the way a Python user would: blocks by indentation, no braces and no
## semicolons, `def` with a return arrow, `#` for a comment, and the two
## directives as the keywords `kernel` and `import`. This file is the pass that
## turns one into the other, before any of the rewrites that already exist.
##
## Two rules govern every line of it. **The count of lines in is the count of
## lines out, always**, so glslang's line numbers stay the file's own and the
## line map in `sa_include_processor.gd` is never touched: a closing brace goes
## on the last line of the block it closes, and a bracket continuation is joined
## onto its first line while the lines it spanned stay in the output. And
## **nothing between the statement ends is rewritten**, so every parallel
## primitive is still GLSL's own and this file stays small. The two exceptions
## are a word's spelling and a bracket on a declared image, which GLSL gives no
## meaning to.
##
## **What this file owns is the pass**, the walk down the lines that decides
## what each one is and what closes it. The questions it meets on the
## way have files of their own: `sa_gmacs_scan.gd` says what a piece of text
## holds, `sa_gmacs_names.gd` says what a word means, and `sa_gmacs_loop.gd`
## turns one `for` header into one GLSL `for` header. `sa_image_brackets.gd`
## reads `src[at]` and writes `dst[at] = c`. Each owns a subject and is
## named for it, rather than being this file's name with a suffix on the end.
##
## Static and holding no state, so every case is testable without a
## RenderingDevice. Preloaded by path from the compiler rather than reached
## through a `class_name`, because a class name resolves only after the editor
## rescans its class cache.
@tool
extends RefCounted

## The placeholder an image with no format of its own writes, so the compiler
## builds one variant per document depth. Mirrored from `sa_bindings.gd`, which
## owns the substitution, for the same reason the compiler mirrors it.
const STORAGE_TOKEN := "SA_STORAGE_FORMAT"

## The qualifiers an `image name: r32f` may name. Anything else after the colon
## is a memory qualifier, `readonly` and its four siblings, which GLSL puts on
## the other side of `uniform`.
const IMAGE_FORMATS: Array[String] = ["rgba32f", "rgba16f", "r32f", "r16f", "rg32f"]

## What a decorator naming two numbers means by its third. A 2D kernel writes
## `@workgroup_size(8, 8)` and a 1D one `@workgroup_size(64)`, and GLSL wants
## three either way.
const IMPLIED_WORKGROUP: int = 1

## The std430 table and the walk over it, so the tail pad a `params:` block gets
## is measured by the same code that reads the block back. Reached by path, the
## way every part of the compiler reaches another.
const KernelSource := preload("res://core/custom-shader/dialect/sa_kernel_source.gd")

## The boundary a push constant block ends on, and the size of the field the pad
## is written in.
##
## std430 rounds a block up to its widest member's alignment, which for a block
## of floats alone is four, so a block that ends at 8 bytes is 8 bytes to
## glslang and 16 to everything in Sara that has ever written one by hand.
## `RenderingDevice` wants exactly what the SPIR-V declares, and writing the pad
## by hand is a mistake waiting for every kernel author, so the pass writes it.
const PUSH_CONSTANT_ALIGNMENT: int = 16
const PAD_FIELD_BYTES: int = 4

## The most a push constant block may hold, which is what Vulkan guarantees every
## driver. A block past it moves its widest arrays into storage buffers until the
## rest fits, see [method _moved_fields].
const PUSH_CONSTANT_LIMIT: int = 128

## What the dialect calls a buffer it moved a field into, which the layout reader
## owns for the reason the pad's prefix gives.
const MOVED_FIELD_PREFIX: String = KernelSource.MOVED_FIELD_PREFIX

## What the pad fields are called, which the layout reader owns because it is
## what marks one in a layout.
const PAD_FIELD_PREFIX: String = KernelSource.PAD_FIELD_PREFIX

## What a `def` with no decorator above it means. Fifty-six of the fifty-eight
## kernels in the tree are 8 by 8, so most files write no decorator at all and
## this is what they get. Only the kernel's own `def` takes it: a helper
## function beside it is an ordinary GLSL function, and an attribute on one
## would be an attribute `replace_kernel_signature` has to strip again.
const DEFAULT_WORKGROUP: Array[String] = ["8", "8", "1"]

## What a word means in the dialect, by path the way every part of the compiler
## reaches another.
const GmacsNames := preload("res://core/custom-shader/dialect/sa_gmacs_names.gd")

## The loop form, reached the same way.
const GmacsLoop := preload("res://core/custom-shader/dialect/sa_gmacs_loop.gd")

## What a piece of text says: its comment, its indentation, its brackets, its
## string literals and its top-level commas.
##
## Once private to this file, which made both halves beside it reach back in,
## the loop through a Callable this file handed down. Everything it answers is
## about the characters in front of it, so it owns them and all three ask.
const GmacsScan := preload("res://core/custom-shader/dialect/sa_gmacs_scan.gd")

## The edge check a kernel leaves out, written onto its signature's line.
const EdgeCheck := preload("res://core/custom-shader/dialect/sa_edge_check.gd")

## An image read and written with brackets, `dst[at] = src[at]`.
const ImageBrackets := preload("res://core/custom-shader/dialect/sa_image_brackets.gd")


## True when *raw_text* is written in the dialect rather than in GLSL.
##
## The first marker line in the file decides, and a file with no marker at all
## is GLSL, so a kernel written in GLSL compiles as GLSL. A marker is a line
## whose opening can only belong to one of the two forms, the bare keyword of a
## directive or a declaration on the dialect's side, the hash form of the same
## directive and the two GLSL shapes nothing in the dialect has, `layout(` and
## the `[numthreads]` attribute, on GLSL's. Counting markers instead would let
## one stray line change a file's dialect, and reading the last one would let an
## appended line do it, so the first is the only stable answer.
static func is_dialect(raw_text: String) -> bool:
    var dialect_marker := RegEx.new()
    dialect_marker.compile(
        (
            "^(?:kernel\\s+\\w+|import\\s+[\\w/]+|def\\s+\\w+\\s*\\("
            + "|@(?:workgroup_size|numthreads)\\s*\\(|(?:image|sampler|buffer)\\s+\\w+\\s*:"
            + "|params(?:\\s+\\w+)?\\s*:)"
        )
    )
    var glsl_marker := RegEx.new()
    glsl_marker.compile(
        (
            '^#(?:kernel\\s+\\w|include\\s*["<]|version\\s+\\d|define\\s+\\w'
            + "|pragma\\b|extension\\b|ifdef\\b|ifndef\\b|endif\\b|else\\b|elif\\b|if\\b|undef\\b|line\\b|error\\b)"
        )
    )
    var glsl_shape := RegEx.new()
    glsl_shape.compile("\\blayout\\s*\\(|\\[\\s*numthreads\\s*\\(")

    for line in raw_text.split("\n"):
        var body := line.strip_edges()
        if body.is_empty():
            continue
        # A declaration with nothing after its name ends where the line does,
        # which the pattern above cannot say without swallowing a body line, so
        # that one case is asked separately, and so is a constant, whose only
        # tell is the semicolon it lacks.
        if dialect_marker.search(body) != null or _is_bare_declaration(body) or _is_dialect_constant(body):
            return true
        if glsl_marker.search(body) != null or glsl_shape.search(body) != null:
            return false
    return false


## `image dst`, `sampler tip` or `buffer table` with nothing after the name.
static func _is_bare_declaration(body: String) -> bool:
    var regex := RegEx.new()
    regex.compile("^(?:image|sampler|buffer)\\s+\\w+$")
    return regex.search(body) != null


## `const float LIMIT = 0.5` with no semicolon after it, which is how a library
## of constants and nothing else says it is the dialect.
##
## A library that only names numbers has no `def` and no declaration, so without
## this it has no marker at all, reads as GLSL and reaches glslang with every
## semicolon missing. The brackets have to close on the line, because GLSL
## writes a long initialiser over several lines and its first line has no
## semicolon either.
static func _is_dialect_constant(body: String) -> bool:
    var code: String = GmacsScan.split_comment(body)[0]
    code = code.strip_edges()
    var regex := RegEx.new()
    regex.compile("^const\\s+\\w+\\s+\\w+\\s*(?:\\[[^\\]]*\\]\\s*)?=[^;]+$")
    return regex.search(code) != null and GmacsScan.bracket_delta(code) == 0


## *raw_text* as GLSL, unchanged when it is GLSL already.
##
## This is the entry point both read sites call, so a file that never met the
## dialect costs one scan and nothing else.
static func to_glsl(raw_text: String) -> String:
    return transpile(raw_text) if is_dialect(raw_text) else raw_text


## *raw_text* read as the dialect, whatever it is.
##
## Separate from `to_glsl` so a test can drive one rewrite on two lines without
## writing a file that would pass the detector.
static func transpile(raw_text: String) -> String:
    var lines := raw_text.split("\n")
    var codes: Array[String] = []
    var indents: Array[int] = []
    var comments := PackedStringArray()
    var code_out := PackedStringArray()
    comments.resize(lines.size())
    code_out.resize(lines.size())

    # A docstring is read before the comments are, because a hash inside one is
    # prose and not a comment, and each of its lines leaves as a comment of its
    # own so the count of lines holds.
    var docstrings := _docstrings(lines)
    for i in lines.size():
        indents.append(GmacsScan.leading_space(lines[i]))
        if docstrings.has(i):
            codes.append("")
            comments[i] = "//" + String(docstrings[i])
            continue
        var split := GmacsScan.split_comment(lines[i])
        var code: String = split[0]
        var comment: String = split[1]
        var has_comment: bool = split[2]
        codes.append(code)
        if has_comment:
            comments[i] = "//" + comment

    # One dictionary threaded through every line: the bindings numbered so far,
    # the decorator waiting for the `def` under it, the name the `kernel`
    # directive gave, whether the file wants `pixel` declared for it, and the
    # edge check each kernel that writes none of its own takes.
    var state: Dictionary[String, Variant] = {
        "bindings": 0,
        "workgroup": [],
        "kernels": [],
        "pixel": GmacsNames.wants_pixel(GmacsScan.spans_by_line(codes)),
        "edges": EdgeCheck.checks(codes, indents),
        "images": ImageBrackets.declared(codes),
    }
    # Each entry is `{indent, closer}`. The closer is appended to the last code
    # line of the block rather than written on one of its own, which is what
    # keeps one source line one GLSL line.
    var open_blocks: Array[Dictionary] = []
    var last_code := -1

    var i := 0
    while i < codes.size():
        var start := i
        var joined := codes[i]
        var depth := GmacsScan.bracket_delta(joined)
        # Python's rule: a line ending inside an open bracket continues on the
        # next. The lines it spanned stay in the output, holding their comments
        # and nothing else, so the count is untouched.
        while depth > 0 and i + 1 < codes.size():
            i += 1
            joined += " " + codes[i].strip_edges()
            depth += GmacsScan.bracket_delta(codes[i])
        i += 1

        var body := joined.strip_edges()
        if body.is_empty():
            continue

        var indent: int = indents[start]
        while not open_blocks.is_empty() and indent <= _block_indent(open_blocks[-1]):
            var ended: Dictionary[String, Variant] = open_blocks.pop_back()
            code_out = _closed(ended, code_out, last_code, indents, state)

        var in_params := not open_blocks.is_empty() and _block_pads(open_blocks[-1])
        var hinted := in_params or _match(body, "^uniform\\s") != null
        var written := _rewrite(_without_hint(body) if hinted else body, state)
        var text: String = written["text"]
        var opens: bool = written["opens"]
        if not opens and in_params:
            # A statement written directly inside a `params:` block is one of
            # its fields, and the tail pad is measured from all of them once the
            # block closes.
            var fields: Array = open_blocks[-1]["fields"]
            fields.append(text)
            var field_lines: Array = open_blocks[-1]["field_lines"]
            field_lines.append(start)
        if opens:
            # The header carries its own opener and the block remembers the
            # closer, which the last line of the block will take. A `case` is
            # the one header whose opener is nothing and whose closer is the
            # `break` the spec asks the transpiler to insert. A trailer, which
            # only the kernel's signature has, goes after the opener and stays
            # on this line, so the count of lines still holds.
            var opener: String = written["open"]
            var trailer: String = written.get("trailer", "")
            var closer: String = written["closer"]
            var pads: bool = written.get("pads", false)
            var moves: bool = written.get("moves", false)
            text += opener + trailer
            var block: Dictionary[String, Variant] = {
                "indent": indent,
                "line": start,
                "closer": closer,
                "pads": pads,
                "moves": moves,
                "fields": [],
                "field_lines": [],
            }
            open_blocks.append(block)
        if not text.is_empty():
            code_out[start] = " ".repeat(indent) + text
            last_code = start

    while not open_blocks.is_empty():
        var ended: Dictionary[String, Variant] = open_blocks.pop_back()
        code_out = _closed(ended, code_out, last_code, indents, state)

    var out: Array = []
    for line_index in lines.size():
        var line := code_out[line_index]
        if not comments[line_index].is_empty():
            line = ((" ".repeat(indents[line_index]) if line.is_empty() else line + "  ") + comments[line_index])
        out.append(line)
    return "\n".join(out)


## *code_out* with the block *closed* closed on its last code line, *last_code*.
##
## A `params:` block past PUSH_CONSTANT_LIMIT moves fields out first: each moved
## field's own line goes out empty, the buffers it moved into are declared after
## the closing brace, and a block left with no field at all goes, header and
## brace, so glslang never meets an empty one. Answered rather than written
## through, because a packed array handed to a function is the caller's only
## when it comes back.
static func _closed(
    closed: Dictionary[String, Variant],
    code_out: PackedStringArray,
    last_code: int,
    indents: Array[int],
    state: Dictionary[String, Variant]
) -> PackedStringArray:
    var moved := _moved_fields(closed)
    var field_lines: Array = closed["field_lines"]
    for at: int in moved:
        var line_index: int = field_lines[at]
        code_out[line_index] = " ".repeat(indents[line_index])
    var fields: Array = closed["fields"]
    if not moved.is_empty() and moved.size() == fields.size():
        var header: int = closed["line"]
        code_out[header] = " ".repeat(indents[header])
    if last_code >= 0:
        code_out[last_code] += _closing_text(closed, code_out[last_code], moved, state)
    return code_out


## What goes on the last line of a block that has just closed: the tail pad when
## it is a `params:` block short of the boundary, then the closing brace, then a
## storage buffer for each field in *moved*.
##
## The pad is fields rather than a number, so glslang declares the block at the
## size the packer sends and the two cannot drift. It is measured by
## `extract_push_constant_layout`, which is the function that reads the block
## back, so a type it does not understand pads to nothing rather than to a guess
## and the block is the size it was written at.
static func _closing_text(
    closed: Dictionary[String, Variant], last_line: String, moved: Array[int], state: Dictionary[String, Variant]
) -> String:
    var written: String = closed["closer"]
    var closer := _closer_for(written, last_line)
    if not _block_pads(closed):
        return closer
    var fields: Array = closed["fields"]
    var kept: Array = []
    for at in fields.size():
        if not moved.has(at):
            kept.append(fields[at])
    var text := "" if kept.is_empty() else _tail_pad(kept) + closer
    for at: int in moved:
        text += " " + _moved_buffer(str(fields[at]), state)
    return text


## The fields of a closed `params:` block that move into storage buffers, by
## their index among its fields, empty when the block fits.
##
## A block past PUSH_CONSTANT_LIMIT gives up its widest array, then the next
## widest, until what is left fits with its tail pad. A 7 by 7 matrix is 196
## bytes on its own, past the limit before anything sits beside it, and a 3 by 3
## is 36 and stays. Only an array moves: the buffer is anonymous, so the kernel
## still reads `weights[i]`, and a scalar or a vector gains nothing a move could
## give. A block with an instance name keeps every field, because `p.weights`
## cannot be read out of a buffer that is not `p`, and a block that still does
## not fit with every array gone is left for the device to refuse.
static func _moved_fields(closed: Dictionary[String, Variant]) -> Array[int]:
    var moved: Array[int] = []
    var moves: bool = closed["moves"]
    if not _block_pads(closed) or not moves:
        return moved
    var fields: Array = closed["fields"]
    while _kept_bytes(fields, moved) > PUSH_CONSTANT_LIMIT:
        var widest := -1
        var widest_size := 0
        for at in fields.size():
            if moved.has(at):
                continue
            var layout := KernelSource.block_layout(str(fields[at]))
            if layout.size() < 2:
                continue
            var length: int = layout[0]["length"]
            if length == 0:
                continue
            var size: int = layout[0]["size"]
            if size > widest_size:
                widest = at
                widest_size = size
        if widest < 0:
            break
        moved.append(widest)
    return moved


## The bytes *fields* take in a push constant without the ones at *moved*,
## tail pad and all.
static func _kept_bytes(fields: Array, moved: Array[int]) -> int:
    var kept: Array = []
    for at in fields.size():
        if not moved.has(at):
            kept.append(fields[at])
    var layout := KernelSource.block_layout(" ".join(kept))
    if layout.is_empty():
        return 0
    var last: Dictionary = layout[-1]
    var size: int = last["offset"]
    return ceili(float(size) / float(PUSH_CONSTANT_ALIGNMENT)) * PUSH_CONSTANT_ALIGNMENT


## The storage buffer one moved *field* is declared in, numbered after every
## binding declared above it.
##
## Anonymous, so its one member is read bare the way a field of the anonymous
## `params:` block is, and `readonly`, because a param is the caller's to set.
## Its block name is the field's after MOVED_FIELD_PREFIX, which is how
## `sa_bindings.gd` knows it for a moved field and `SaCompute.run` fills it from
## the params it was handed.
static func _moved_buffer(field: String, state: Dictionary[String, Variant]) -> String:
    var binding: int = state["bindings"]
    state["bindings"] = binding + 1
    var layout := KernelSource.block_layout(field)
    var field_name := str(layout[0]["name"])
    return (
        "layout( std430, set = 0, binding = %d ) readonly buffer %s%s { %s };"
        % [binding, MOVED_FIELD_PREFIX, field_name, field.strip_edges()]
    )


## The indent an open block of `transpile` was opened at.
static func _block_indent(block: Dictionary) -> int:
    var indent: int = block["indent"]
    return indent


## Whether an open block of `transpile` is a `params:` block that pads its tail.
static func _block_pads(block: Dictionary) -> bool:
    var pads: bool = block["pads"]
    return pads


## Whether a line `_rewrite` wrote opens a block.
static func _opens(written: Dictionary) -> bool:
    var opens: bool = written["opens"]
    return opens


## What a block's last line actually takes of *closer*.
##
## Only the `break` a `case` closes with is conditional: the spec has the
## transpiler insert the one each case needs, and a case whose body already
## returned or broke needs none, a second one there being unreachable code the
## file did not write. A brace is never conditional.
static func _closer_for(closer: String, last_line: String) -> String:
    if closer.strip_edges() != "break;":
        return closer
    return "" if _match(last_line.strip_edges(), "\\b(?:return|break|discard)\\b[^;{}]*;$") != null else closer


## The pad fields a block of *fields* needs to end on PUSH_CONSTANT_ALIGNMENT,
## or "" when it ends there already.
##
## **An explicit pad is still a field, and still allowed.** A kernel that writes
## its own `vec2 pad` lands on the boundary and gets nothing added, which is what
## keeps a converted kernel's SPIR-V identical to the GLSL one it came from: a
## `vec2` and two `float`s are the same eight bytes and not the same struct. The
## sweep of Sara's own kernels leans on that.
static func _tail_pad(fields: Array) -> String:
    var layout := KernelSource.extract_push_constant_layout("push_constant {%s}" % " ".join(fields))
    if layout.is_empty():
        return ""
    var last: Dictionary = layout[-1]
    var size: int = last["offset"]
    var over := size % PUSH_CONSTANT_ALIGNMENT
    if size == 0 or over == 0:
        return ""
    var text := ""
    @warning_ignore("integer_division")
    var count := (PUSH_CONSTANT_ALIGNMENT - over) / PAD_FIELD_BYTES
    for i in count:
        text += " float %s%d;" % [PAD_FIELD_PREFIX, i]
    return text


## Whether *field_name* is a pad this pass wrote rather than a field somebody
## declared.
##
## Public because the caller's side has to know the difference: a pad is the
## compiler's and `set_params()` must neither ask for one nor refuse a call that
## leaves it out.
static func is_pad_field(field_name: String) -> bool:
    return field_name.begins_with(PAD_FIELD_PREFIX)


## One logical line of the dialect as one line of GLSL, as
## `{text, opens, open, closer}`, and `pads` on the one block that is measured.
##
## *state* carries what a line cannot know on its own: how many bindings have
## been numbered, and the decorator waiting for the `def` under it. `opens` says
## the line is a block header, `open` is what the header itself takes and
## `closer` is what the block's last line takes.
static func _rewrite(body: String, state: Dictionary[String, Variant]) -> Dictionary[String, Variant]:
    var plain := GmacsNames.rewrite(GmacsScan.code_spans(GmacsNames.word_operators(body)))

    var directive := _match(plain, "^(kernel|import)\\s+(.*)$")
    if directive != null:
        return _directive(directive.get_string(1), directive.get_string(2), state)

    directive = _match(plain, "^@(?:workgroup_size|numthreads)\\s*\\(([^)]*)\\)$")
    if directive != null:
        state["workgroup"] = _workgroup_sizes(directive.get_string(1))
        # The attribute belongs on the signature, so the decorator's own line
        # goes out empty and the count of lines still holds.
        return _statement("")

    # Before the header scan, because `image mask: r32f` and `buffer table:
    # float values[]` end in a colon that opens nothing.
    var declaration := _declaration(plain, state)
    if not declaration.is_empty():
        return declaration

    # A bracket on an image is read here, after the declarations and on the
    # header's own half, because a one-line body after a colon is a statement of
    # its own and comes back through this function.
    var images: Array[String] = state["images"]
    var colon := _header_colon(plain)
    if colon >= 0:
        var head := ImageBrackets.reads(plain.substr(0, colon).strip_edges(), images)
        return _header(head, plain.substr(colon + 1).strip_edges(), state)

    var text := ImageBrackets.statement(plain, images)
    return _statement(text if text.begins_with(ImageBrackets.REFUSAL) else text + ";")


## `kernel a, b` or `import a, b` as one hash directive per name, all of them on
## this line, or Sara's own refusal of it.
##
## Both words are the dialect's keywords, so a line that opens with one is a
## directive whatever follows, and a list that is not a list of names is
## refused here rather than handed on. Handed on, `import a, , b` reached
## glslang as a statement and came back as a syntax error about a semicolon in
## a language the painter never wrote. The refusal is an `#error` line, which
## glslang reports as it stands and the line map places on the painter's own
## line, so it arrives the way every other compile error does.
##
## Two directives on one line are read the way one is, because
## `extract_kernels` searches all of a text and `process_includes` pastes each
## match where it stands.
static func _directive(keyword: String, listed: String, state: Dictionary[String, Variant]) -> Dictionary[String, Variant]:
    var name_shape := "^\\w+$" if keyword == "kernel" else "^[\\w/]+$"
    var names := PackedStringArray()
    for name in listed.split(","):
        var trimmed := name.strip_edges()
        if _match(trimmed, name_shape) == null:
            return _statement(_refusal(keyword, listed))
        names.append(trimmed)
    var written := PackedStringArray()
    for name in names:
        if keyword == "kernel":
            # Held because the default workgroup size and the `pixel`
            # declaration belong to this file's kernels and to no other
            # function in it. All of them: remembering only the last left every
            # earlier kernel without its default once the decorator stopped
            # being written.
            var kernels: Array = state["kernels"]
            kernels.append(name)
            written.append("#kernel " + name)
        else:
            written.append('#include "%s"' % name)
    return _statement(" ".join(written))


## The `#error` line a malformed `kernel` or `import` list becomes.
##
## The list is quoted without its quote marks and backslashes, because an
## `#error` line is read by glslang's preprocessor and a stray quote there is an
## error about the error.
static func _refusal(keyword: String, listed: String) -> String:
    var shown := listed.strip_edges().replace('"', "").replace("'", "").replace("\\", "")
    var one := "kernel name" if keyword == "kernel" else "file name"
    return "#error SaDialect: %s %s is not a list of names, write one %s between each pair of commas" % [keyword, shown, one]


## The lines of every function's docstring, by index, each as the text of the
## comment it becomes.
##
## A docstring is the string a `def` opens its body with, as Python has it:
## three quotes over as many lines as it likes, or one quote closed on its own
## line. GLSL has no strings, so without this it would reach glslang as a
## statement and be a syntax error. It becomes a comment instead, one per line
## it spans, which keeps the count of lines. A string anywhere else is left for
## glslang to refuse, and so is a docstring that never closes, because reading the rest
## of the file as prose would hide every line after it.
static func _docstrings(lines: PackedStringArray) -> Dictionary[int, String]:
    var found: Dictionary[int, String] = {}
    var i := 0
    while i < lines.size():
        var code := str(GmacsScan.split_comment(lines[i])[0])
        if _match(code, "^\\s*def\\s+\\w+\\s*\\(") == null:
            i += 1
            continue
        # The signature may run over several lines, and it ends where its
        # brackets close. Only a signature that ends on its colon has a body
        # below it: `def f(): return x` has written its body already.
        var depth := GmacsScan.bracket_delta(code)
        while depth > 0 and i + 1 < lines.size():
            i += 1
            code = str(GmacsScan.split_comment(lines[i])[0])
            depth += GmacsScan.bracket_delta(code)
        i += 1
        if not code.strip_edges().ends_with(":"):
            continue
        while i < lines.size() and lines[i].strip_edges().is_empty():
            i += 1
        i = _docstring_from(lines, i, found)
    return found


## Reads the docstring that starts on line *at*, if one does, into *found*, and
## returns the line to go on from.
static func _docstring_from(lines: PackedStringArray, at: int, found: Dictionary[int, String]) -> int:
    if at >= lines.size():
        return at
    var body := lines[at].strip_edges()
    for fence: String in ['"""', "'''"]:
        if not body.begins_with(fence):
            continue
        var close := body.find(fence, fence.length())
        if close >= 0:
            if not body.substr(close + fence.length()).strip_edges().is_empty():
                return at
            found[at] = _docstring_text(body.substr(fence.length(), close - fence.length()))
            return at + 1
        for end in range(at + 1, lines.size()):
            var last := lines[end].strip_edges()
            close = last.find(fence)
            if close < 0:
                continue
            if not last.substr(close + fence.length()).strip_edges().is_empty():
                return at
            found[at] = _docstring_text(body.substr(fence.length()))
            for inner in range(at + 1, end):
                found[inner] = _docstring_text(lines[inner].strip_edges())
            found[end] = _docstring_text(last.substr(0, close))
            return end + 1
        return at
    # One quote, closed on its own line and followed by nothing. The scan hands
    # back an empty span in front of a line that opens on a quote, which is not
    # a second piece of the line.
    var pieces: Array = []
    for span: Array in GmacsScan.code_spans(body):
        if not str(span[0]).is_empty():
            pieces.append(span)
    var one_quoted := false
    if pieces.size() == 1:
        one_quoted = pieces[0][1]
    if one_quoted and body.length() >= 2 and body[-1] == body[0]:
        found[at] = _docstring_text(body.substr(1, body.length() - 2))
        return at + 1
    return at


## One line of a docstring as comment text, spaced the way `# text` becomes
## `// text`.
static func _docstring_text(text: String) -> String:
    var trimmed := text.strip_edges()
    return "" if trimmed.is_empty() else " " + trimmed


## A `params:` field or a `uniform` line without its hint, which is the
## slider's and not GLSL's.
##
## `float scale: hint_range(2, 64)` declares a field and the numbers its slider
## takes, the way a Godot shader declares a uniform. Nothing opens a block inside
## a `params:` block, and a `uniform` line opens none either, so a colon in one
## is a hint's and never a header's. Read by `_header_colon`, the field would be
## a one-line block headed `float scale`. A value after the hint stays, so glslang
## refuses it in a block the way it refuses one written with no hint.
##
## The `uniform` lines are a pixel function's, which the wrapper blanks before
## its import is compiled. The shader walk still reads every `.gmacs` in the
## tree at boot, the shipped patterns among them, and a hinted line there would
## come out as a header this pass does not know.
static func _without_hint(field: String) -> String:
    var parts := GmacsScan.declaration_parts(field)
    if parts[1] == null:
        return field
    var declared := str(parts[0])
    return declared if parts[2] == null else "%s = %s" % [declared, str(parts[2])]


## The colon that ends a block header, or -1 when the line has none.
##
## A colon inside brackets belongs to something else, and a colon that answers a
## `?` is a ternary, which is GLSL's and stays. So the first colon at bracket
## depth zero with no `?` waiting on it is the header's, which is what tells
## `if x: y = a ? b : c` apart from `x = a ? b : c`.
static func _header_colon(code: String) -> int:
    var depth := 0
    var pending := 0
    var at := 0
    for span: Array in GmacsScan.code_spans(code):
        var text := str(span[0])
        var quoted: bool = span[1]
        if quoted:
            at += text.length()
            continue
        for i in text.length():
            var c := text[i]
            if c == "(" or c == "[" or c == "{":
                depth += 1
            elif c == ")" or c == "]" or c == "}":
                depth -= 1
            elif c == "?":
                pending += 1
            elif c == ":" and depth == 0:
                if pending == 0:
                    return at + i
                pending -= 1
        at += text.length()
    return -1


## One block header, with *tail* the one-line body written after the colon, or
## an empty String when the block is indented under it.
##
## A one-line body is closed on the spot rather than opening a block, which is
## the spec's `if x >= size.x: return` and the reason this is one function
## rather than a branch in the caller.
static func _header(head: String, tail: String, state: Dictionary[String, Variant]) -> Dictionary[String, Variant]:
    var opened := _block_header(head, state)
    if tail.is_empty() or not _opens(opened):
        return opened
    var inner := _rewrite(tail, state)
    if _opens(inner):
        push_error("SaDialect: '%s' opens a block after a colon, which has nowhere to go." % tail)
        return opened
    var closer := str(opened["closer"]).strip_edges()
    var joined := "%s%s %s %s" % [opened["text"], opened["open"], inner["text"], closer]
    return _statement(joined.strip_edges())


## The header itself, without whatever was written after its colon.
static func _block_header(head: String, state: Dictionary[String, Variant]) -> Dictionary[String, Variant]:
    var found := _match(head, "^def\\s+(\\w+)\\s*\\((.*)\\)\\s*(?:->\\s*(\\w+)\\s*)?$")
    if found != null:
        return _signature(found, state)

    var loop := GmacsLoop.header(head)
    if not loop.is_empty():
        return loop

    found = _match(head, "^(if|elif|while)\\s+(.+)$")
    if found != null:
        var keyword := "else if" if found.get_string(1) == "elif" else found.get_string(1)
        return _block("%s (%s)" % [keyword, found.get_string(2)], " {", "}")

    if head == "else":
        return _block("else", " {", "}")

    found = _match(head, "^match\\s+(.+)$")
    if found != null:
        return _block("switch (%s)" % found.get_string(1), " {", "}")

    found = _match(head, "^case\\s+(.+)$")
    if found != null:
        # A `case` label needs no braces in GLSL, so its opener is nothing and
        # its closer is the `break` the spec asks the transpiler to insert.
        var label := found.get_string(1).strip_edges()
        return _block("default:" if label == "_" else "case %s:" % label, "", " break;")

    found = _match(head, "^struct\\s+(\\w+)$")
    if found != null:
        return _block("struct %s" % found.get_string(1), " {", "};")

    found = _match(head, "^params(?:\\s+(\\w+))?$")
    if found != null:
        return _params_block(found.get_string(1))

    push_error("SaDialect: '%s' is a block header this pass does not know." % head)
    return _block(head, " {", "}")


## A line that opens no block.
static func _statement(text: String) -> Dictionary[String, Variant]:
    return {"text": text, "opens": false, "open": "", "closer": "", "pads": false}


## A line that opens one, taking *open* itself and leaving *closer* for the
## block's last line.
static func _block(text: String, open: String, closer: String) -> Dictionary[String, Variant]:
    return {"text": text, "opens": true, "open": open, "closer": closer, "pads": false}


## The three numbers a `@workgroup_size` or `@numthreads` decorator means, the
## missing ones written as IMPLIED_WORKGROUP.
static func _workgroup_sizes(args: String) -> Array:
    var sizes: Array = []
    for arg: String in GmacsScan.split_args(args):
        sizes.append(arg.strip_edges())
    while sizes.size() < 3:
        sizes.append(str(IMPLIED_WORKGROUP))
    return sizes.slice(0, 3)


## `def name(args) -> type:` as the GLSL signature, with the workgroup
## decorator's attribute in front of it when one is waiting.
##
## The attribute is what `SaKernelSource.extract_numthreads` reads and what
## `replace_kernel_signature` strips, so it is written in that function's shape,
## `void` and all: a kernel returns nothing.
##
## Two things belong to the kernel's own `def` and to no other. The decorator is
## optional, so the kernel takes DEFAULT_WORKGROUP when no line above it named a
## size, which is what fifty-six of the tree's fifty-eight kernels would write.
## And `pixel` is declared here, inside the brace and on this same line, when
## the file uses the word. A helper function takes neither: an attribute on one
## would be a second attribute to strip, and a `pixel` in one would shadow
## whatever the helper was handed. The edge check `sa_edge_check.gd` writes for
## a kernel that leaves its own out goes on the same line after it.
static func _signature(found: RegExMatch, state: Dictionary[String, Variant]) -> Dictionary[String, Variant]:
    var name := found.get_string(1)
    var args := found.get_string(2).strip_edges()
    var return_type := found.get_string(3)
    if return_type.is_empty():
        return_type = "void"
    var kernels: Array = state["kernels"]
    var is_kernel := kernels.has(name)
    var workgroup: Array = state["workgroup"]
    if workgroup.is_empty() and is_kernel:
        workgroup = DEFAULT_WORKGROUP
    var attribute := ""
    if not workgroup.is_empty():
        attribute = "[numthreads( %s, %s, %s )] " % [workgroup[0], workgroup[1], workgroup[2]]
    state["workgroup"] = []
    var signature := _block("%s%s %s(%s)" % [attribute, return_type, name, args], " {", "}")
    var wants_pixel: bool = state["pixel"]
    if is_kernel and wants_pixel:
        signature["trailer"] = " " + GmacsNames.PIXEL_DECLARATION
    var edges: Dictionary = state["edges"]
    if is_kernel and edges.has(name):
        signature["trailer"] = str(signature.get("trailer", "")) + str(edges[name])
    return signature


## The four declarations, as GLSL's own `layout(...)` lines, or an
## empty Dictionary when *plain* is not one.
##
## Bindings are numbered in the order they are declared, which is what lets the
## GDScript side bind by name. `params:` is read as a header rather than here,
## because it opens a block, and it is a push constant rather than a binding so
## it takes no number.
static func _declaration(plain: String, state: Dictionary[String, Variant]) -> Dictionary[String, Variant]:
    var found := _match(plain, "^image\\s+(\\w+)\\s*(?::\\s*(.+))?$")
    if found != null:
        return _statement(_image(found.get_string(1), found.get_string(2), state))

    found = _match(plain, "^sampler\\s+(\\w+)$")
    if found != null:
        var binding: int = state["bindings"]
        state["bindings"] = binding + 1
        return _statement("layout( set = 0, binding = %d ) uniform sampler2D %s;" % [binding, found.get_string(1)])

    found = _match(plain, "^buffer\\s+(\\w+)\\s*:\\s*(.+)$")
    if found != null:
        var binding: int = state["bindings"]
        state["bindings"] = binding + 1
        var name := found.get_string(1)
        var members := found.get_string(2).strip_edges()
        return _statement(
            "layout( std430, set = 0, binding = %d ) buffer %s { %s; } %s;" % [binding, name.to_pascal_case(), members, name]
        )

    return {}


## `params:` and `params p:`, as GLSL's own push constant block.
##
## Anonymous, so a field read bare in the body is GLSL reading a block member and
## no expression is rewritten. A file that writes `params p:` keeps the instance
## name and the `p.` prefix with it. `pads` is what makes the block the one whose
## fields are collected and measured when it closes, and `moves` is what lets an
## anonymous one move an array that does not fit into a buffer.
static func _params_block(instance: String) -> Dictionary[String, Variant]:
    var closer := "} %s;" % instance if not instance.is_empty() else "};"
    var opened := _block("layout( push_constant, std430 ) uniform Params", " {", closer)
    opened["pads"] = true
    opened["moves"] = instance.is_empty()
    return opened


## One `image` declaration, with the storage token when it named no format.
static func _image(name: String, qualifiers: String, state: Dictionary[String, Variant]) -> String:
    var binding: int = state["bindings"]
    state["bindings"] = binding + 1
    var format := STORAGE_TOKEN
    var memory: Array = []
    for qualifier: String in GmacsScan.split_args(qualifiers):
        if qualifier in IMAGE_FORMATS:
            format = qualifier
        else:
            memory.append(qualifier)
    var prefix := " ".join(memory) + " " if not memory.is_empty() else ""
    return "layout( %s, set = 0, binding = %d ) uniform %simage2D %s;" % [format, binding, prefix, name]


## *pattern* against *text*, or null. The patterns are written once per call the
## way the rest of the compiler's text half writes them.
static func _match(text: String, pattern: String) -> RegExMatch:
    var regex := RegEx.new()
    regex.compile(pattern)
    return regex.search(text)
