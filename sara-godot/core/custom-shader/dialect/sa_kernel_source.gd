## The pure text half of the `.gmacs` compiler: comments out, kernels found,
## one kernel's signature rewritten into GLSL's `main`, and the push constant
## block read for its std430 layout.
##
## Nothing here touches a RenderingDevice or any state, so every function is
## static and testable without a GPU. Preloaded by path from the compiler rather
## than reached through a `class_name`, because a class name resolves only after
## the editor rescans its class cache.
@tool
extends RefCounted

## Lines the assembler puts in front of every kernel: the #version and the
## local_size layout. See assemble_glsl.
const PREAMBLE_LINES: int = 2

## What the dialect calls the fields it writes to pad a block. Underscore-led
## because nothing a kernel reads is, and numbered because a block short of the
## boundary by twelve needs three. Here rather than on the dialect, which writes
## them, because this file is the one that reads a layout and the dialect already
## names it, so the spelling has one home and no file names the other back.
const PAD_FIELD_PREFIX: String = "_pad_"

## What the dialect calls the storage buffer it moves a params field into, the
## field's own name after it. A block that will not fit the push constant moves
## its widest arrays out, and the buffer is anonymous so the kernel still reads
## `weights[i]`, which leaves the block's name the one place the move shows.
## Here beside the pad's prefix for the same reason: `sa_bindings.gd` reads a
## buffer of this name as a moved field, and the dialect names it back.
const MOVED_FIELD_PREFIX: String = "SaParams_"

## std430 alignment and size, in bytes, for the types Sara's blocks use.
##
## A scalar array has a stride of 4 here, which is the whole reason the composite
## matrices are `float[9]` and not `mat3`: std430 pads every column of a matrix out
## to 16.
const STD430_TYPES := {
    "float": [4, 4],
    "vec2": [8, 8],
    "vec3": [16, 12],
    "vec4": [16, 16],
    "int": [4, 4],
    "uint": [4, 4],
    "bool": [4, 4],
}


## Remove all comments (line and block) to prevent parsing commented tags
static func remove_comments(raw_text: String) -> String:
    var comment_regex := RegEx.new()
    comment_regex.compile("/\\*[\\s\\S]*?\\*/|//.*")
    # A block comment is replaced by the newlines it spanned rather than by
    # nothing, so every line of the stripped source is still the same line of the
    # file. Collapsing them shifted everything below a header comment, and
    # composite.gmacs opens with forty lines of one, which is most of the reason
    # glslang's line numbers pointed at nothing a human could find.
    var out := ""
    var read_from := 0
    for found in comment_regex.search_all(raw_text):
        out += raw_text.substr(read_from, found.get_start(0) - read_from)
        out += "\n".repeat(found.get_string(0).count("\n"))
        read_from = found.get_end(0)
    out += raw_text.substr(read_from)
    return out


## Reads the push_constant block out of already-preprocessed source, as an Array
## of `{name, type, offset, size, length, pad}` in declaration order plus a
## closing entry whose offset is the total size.
##
## `length` is the count an array field declared and nought for a field that is
## not an array, so a reader can tell `float m[1]` from `float m` and a matrix
## from a scalar whatever its size.
##
## `pad` is true on a field the dialect wrote to reach the std430 boundary and
## false on one somebody declared. It is marked here, where the layout is read,
## so the packing side reads a flag and never learns how a pad is spelled.
##
## Comments are gone and includes are pasted by the time this runs, so the block is
## whatever is between the braces. Returns an empty Array when there is no block,
## which is not an error: a shader is allowed not to take one.
static func extract_push_constant_layout(clean_text: String) -> Array:
    var block_regex := RegEx.new()
    block_regex.compile("push_constant[^{]*\\{([^}]*)\\}")
    var found := block_regex.search(clean_text)
    if found == null:
        return []
    return block_layout(found.get_string(1))


## The std430 layout of the fields between a block's braces, *body*, in the
## shape [method extract_push_constant_layout] answers, or an empty Array when a
## field is of a type this does not understand.
##
## Public because a storage buffer the dialect moved a field into is laid out by
## the same rules, and its bytes are packed by the same packer.
static func block_layout(body: String) -> Array:
    var field_regex := RegEx.new()
    field_regex.compile("(\\w+)\\s+(\\w+)\\s*(?:\\[\\s*(\\d+)\\s*\\])?\\s*;")
    var fields: Array = []
    var offset := 0
    for entry in field_regex.search_all(body):
        var type_name := entry.get_string(1)
        if not STD430_TYPES.has(type_name):
            push_warning("GlobalShaderCompiler: push constant type '%s' is not one this understands." % type_name)
            return []
        var count_text := entry.get_string(3)
        var alignment: int = STD430_TYPES[type_name][0]
        var size: int = STD430_TYPES[type_name][1]
        if not count_text.is_empty():
            # std430 rounds an array's stride up to the alignment of its element,
            # so the run is the stride times the count and not the element's own
            # size times the count. Every type here but `vec3` strides at its own
            # size, and a `vec3` aligns to sixteen, so `vec3 tint[4]` is sixty-four
            # bytes with four dead ones after each entry rather than forty-eight
            # tight ones. Measured tightly, every field after such an array sits
            # sixteen bytes early and the kernel reads the wrong numbers without
            # anything failing. `SaPushConstants.ARRAY_STRIDES` is the packing half of
            # this rule.
            var stride: int = ceili(float(size) / float(alignment)) * alignment
            size = stride * int(count_text)
        offset = ceili(float(offset) / float(alignment)) * alignment
        var field_name := entry.get_string(2)
        var pad := field_name.begins_with(PAD_FIELD_PREFIX)
        var length := 0 if count_text.is_empty() else int(count_text)
        fields.append(_field(field_name, type_name, offset, size, length, pad))
        offset += size
    fields.append(_field("", "", offset, 0, 0, false))
    return fields


## One field of the block, built typed here because the list it goes into is
## not, and a literal handed to `append` stays untyped.
static func _field(
    field_name: String, type_name: String, offset: int, size: int, length: int, pad: bool
) -> Dictionary[String, Variant]:
    return {"name": field_name, "type": type_name, "offset": offset, "size": size, "length": length, "pad": pad}


## Extract all kernel names from shader code
static func extract_kernels(clean_text: String) -> Array:
    var kernel_regex := RegEx.new()
    kernel_regex.compile("#kernel\\s+(\\w+)")
    var kernels: Array = []
    for result in kernel_regex.search_all(clean_text):
        kernels.append(result.get_string(1))
    return kernels


## Extract numthreads values from kernel signature
static func extract_numthreads(k_name: String, code: String) -> Array:
    var func_sig_regex := RegEx.new()
    (
        func_sig_regex
        . compile(
            "\\[numthreads\\(\\s*(\\d+)\\s*,\\s*(\\d+)\\s*,\\s*(\\d+)\\s*\\)\\]\\s*void\\s+" + k_name + "\\s*\\(",
        )
    )

    var match_sig := func_sig_regex.search(code)
    if match_sig == null:
        push_error("GlobalShaderCompiler: kernel '%s' has no [numthreads(x, y, z)] on its signature." % k_name)
        return []

    return [match_sig.get_string(1), match_sig.get_string(2), match_sig.get_string(3)]


## Replace kernel signature with standard main function
static func replace_kernel_signature(k_name: String, code: String) -> String:
    var func_sig_regex := RegEx.new()
    (
        func_sig_regex
        . compile(
            "\\[numthreads\\(\\s*(\\d+)\\s*,\\s*(\\d+)\\s*,\\s*(\\d+)\\s*\\)\\]\\s*void\\s+" + k_name + "\\s*\\(",
        )
    )
    code = func_sig_regex.sub(code, "void main(")

    var kernel_regex := RegEx.new()
    kernel_regex.compile("#kernel\\s+(\\w+)")
    code = kernel_regex.sub(code, "", true)

    # Strip any remaining [numthreads(...)] attributes from other kernels so GLSL doesn't syntax error
    var remaining_threads_regex := RegEx.new()
    remaining_threads_regex.compile("\\[numthreads\\(\\s*\\d+\\s*,\\s*\\d+\\s*,\\s*\\d+\\s*\\)\\]")
    code = remaining_threads_regex.sub(code, "", true)

    return code


## Assemble final GLSL source with version and layout directives
static func assemble_glsl(numthreads: Array, code: String) -> String:
    var final_source := "#version 450\n"
    final_source += "layout(local_size_x = %s, local_size_y = %s, local_size_z = %s) in;\n" % numthreads
    final_source += code
    return final_source
