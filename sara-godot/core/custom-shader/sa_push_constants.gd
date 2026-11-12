## The push constant block of one shader: the bytes the next dispatch sends, and
## whether they are the block the kernel declared.
##
## A `.gmacs` already names everything its block takes. The compiler parses the
## declaration into `{name, type, offset, size}`, and this packs a Dictionary
## keyed by those names into exactly the bytes std430 asks for, rather than
## throwing the name away at the door: `set_push_constant_float_array()` takes a
## positional array matched to the block by eye, and a field inserted into a
## block is silent on both sides and shows up as a wrong picture.
##
## Both doors are here, because both write the same bytes and only one thing may
## write them. The block also knows what the shader declares it takes, so the
## size check sits beside the bytes rather than beside a setter.
##
## The packing itself is static and pure: it takes a layout and a Dictionary and
## answers bytes or a complaint, so the whole packer is provable without a
## RenderingDevice, which is what `core/custom-shader/tests/test_params_by_name.gd` does.
##
## A class of its own rather than statics on `sa_compute.gd`, which would take
## the compute object back. Reached by path rather than by a `class_name`, the
## way every half of the compiler is, because a class name resolves only after
## the editor rescans its class cache.
@tool
extends RefCounted

## What the end of a push constant block is rounded up to.
##
## Four, and **not sixteen**. A block of a `float` and an `int` is eight bytes,
## and sixteen gets "this compute pipeline requires (8) bytes of push constant
## data, supplied: (16)" from Vulkan. The engine takes the block at exactly the
## size the shader declares. std430 rounds the *offsets inside* a block to
## sixteen, which is what `extract_push_constant_layout()` already does and what
## `pack()` writes into, and it does not round the block itself.
##
## Four, rather than nothing, because Vulkan takes a push constant size in whole
## words. Every type in `COMPONENTS` is a multiple of four wide, so this rounds
## nothing today and is here for the type that is not.
const BLOCK_ALIGNMENT: int = 4

## How many floats, ints or uints a declared type is worth, so an array field
## and a vector field are packed by the same loop.
const COMPONENTS := {
    "float": 1,
    "vec2": 2,
    "vec3": 3,
    "vec4": 4,
    "int": 1,
    "uint": 1,
    "bool": 1,
}

## What one entry of an array field occupies, which is not always what the entry
## is worth.
##
## std430 rounds an array's stride up to the alignment of its element, and a
## `vec3` aligns to sixteen, so a `vec3[]` leaves four dead bytes after every
## entry while every other type Sara declares strides at its own size. Writing
## such an array tightly would put the second entry twelve bytes in, where the
## kernel reads nothing, and each entry after it further wrong.
##
## The parsing half of the same rule is in
## `SaKernelSource.extract_push_constant_layout()`, which sizes the whole run.
## The two are read together by `core/custom-shader/tests/test_params_by_name.gd`.
const ARRAY_STRIDES := {
    "float": 4,
    "vec2": 8,
    "vec3": 16,
    "vec4": 16,
    "int": 4,
    "uint": 4,
    "bool": 4,
}

## The bytes the next dispatch sends, empty until something fills them.
var bytes: PackedByteArray = PackedByteArray()

## The shader whose block this is, for the size check and the errors.
var _shader_name: String = ""

## Set once a size mismatch has been reported, so it is said once per instance
## rather than once per dispatch.
var _warned_size: bool = false

## The layout the plan below was read from, held by identity. A recompile files
## a new layout Array rather than writing into the old one, so a layout that is
## the same object is the same block.
var _planned: Array = []

## The names, offsets, types and sizes of the fields a caller fills, in the
## declared order, and the padded size of the whole block. Reading them once per
## layout rather than once per dispatch is most of what a filter's `set_params`
## cost: 42 µs a call of six vec4 fields read per dispatch, 6 read
## per layout.
var _names: Array[String] = []
var _offsets: PackedInt32Array = PackedInt32Array()
var _types: Array[String] = []
var _sizes: PackedInt32Array = PackedInt32Array()
var _padded: int = 0

## The size the shader declares, read with the plan rather than on every fill.
var _declared: int = 0

## The keys of the last values the layout accepted, in their order. A complaint
## reads only the keys and the layout, so the same keys against the same layout
## draw the same answer, which was none.
var _accepted: Array = []


func _init(shader_name: String) -> void:
    _shader_name = shader_name


## Fills the block from a float array, padding the tail out to a multiple of four
## floats so it ends on the 16-byte boundary std430 rounds a field to.
##
## That padding is the only thing this does for you. It does not reorder fields
## and it does not pack them, so the field order written in the GLSL is
## authoritative and the float array a caller builds is positional and matched to
## it by hand. The asserts in `SaColorSpace.to_push_constant()` and the comment on
## the composite Params block are what keep the two honest.
##
## An automatic packer would not buy the composite kernel anything anyway. The
## trick it would apply, ordering fields largest first, removes padding *between*
## fields, and that block has one such slot which blend_white already occupies.
## Its waste is inside each mat3, where std430 pads every column from 12 bytes to
## 16, and no permutation of fields reaches that.
func fill_from_floats(data: PackedFloat32Array) -> void:
    assert(not data.is_empty(), "Float array cannot be empty")
    # Vulkan (std430) aligns blocks according to vec4 (16 bytes = 4 floats)
    var floats_count := data.size()
    var remainder := floats_count % 4

    var aligned_data := data
    # if the data size is not a multiple of 4, pad with zeros
    if remainder != 0:
        aligned_data = data.duplicate()
        aligned_data.resize(floats_count + (4 - remainder))

    bytes = aligned_data.to_byte_array()
    _verify_size()


## Fills the block from raw bytes the caller laid out itself.
##
## Asserted here, where a dispatch asserts nothing. An empty array is not
## caught by anything downstream: a dispatch skips binding a push constant it
## finds empty, so the kernel runs against whatever was there before and the only
## symptom is a wrong picture. Every other mistake fails on the next line,
## loudly enough on its own.
func fill_from_bytes(data: PackedByteArray) -> void:
    assert(not data.is_empty(), "Byte array cannot be empty")
    bytes = data


## Fills the block from *values* by the names *layout* declares, and answers what
## was wrong with them, empty when nothing was.
##
## Nothing is written when there is a complaint, so a refused call sends nothing
## rather than something plausible. The complaint is answered rather than pushed,
## so the caller can put its own name in front of it.
##
## *values* here, in `complaint` and in `pack` is what a module handed
## `SaCompute.set_params` or `run`, which stay untyped for the reason `run` gives.
func fill_from_values(layout: Array, values: Dictionary) -> String:
    if not is_same(layout, _planned):
        _plan(layout)
    var keys := values.keys()
    if keys != _accepted:
        var problem := complaint(layout, values)
        if not problem.is_empty():
            return problem
        _accepted = keys
    bytes = _packed(values)
    if not _warned_size and _declared > 0 and _declared != bytes.size():
        _verify_size()
    return ""


## Reads *layout* into the plan `_packed` walks, once per layout.
func _plan(layout: Array) -> void:
    _planned = layout
    _accepted = []
    _names.clear()
    _types.clear()
    _offsets.clear()
    _sizes.clear()
    _padded = 0
    if not layout.is_empty():
        var last: Dictionary = layout[-1]
        var total: int = last["offset"]
        _padded = ceili(float(total) / float(BLOCK_ALIGNMENT)) * BLOCK_ALIGNMENT
    for field: Dictionary in layout:
        var name := str(field["name"])
        if name.is_empty() or _is_pad(field):
            continue
        var offset: int = field["offset"]
        var size: int = field["size"]
        _names.append(name)
        _types.append(str(field["type"]))
        _offsets.append(offset)
        _sizes.append(size)
    _declared = GlobalShaderCompiler.push_constant_bytes(_shader_name)


## The bytes `pack` would answer for *values*, from the plan, once `complaint`
## has had nothing to say about them.
##
## The common pairs, a float field given a float, a vec2 given a Vector2 and a
## vec4 given a Color or a Vector4, are written straight, and everything else
## goes through `_write_field` as before, so the bytes are the same either way.
func _packed(values: Dictionary) -> PackedByteArray:
    var packed := PackedByteArray()
    packed.resize(_padded)
    for i in range(_names.size()):
        var value: Variant = values[_names[i]]
        var type_name := _types[i]
        var at := _offsets[i]
        var kind := typeof(value)
        if type_name == "float" and kind == TYPE_FLOAT:
            var number: float = value
            packed.encode_float(at, number)
        elif type_name == "vec2" and kind == TYPE_VECTOR2:
            var pair: Vector2 = value
            packed.encode_float(at, pair.x)
            packed.encode_float(at + 4, pair.y)
        elif type_name == "vec4" and kind == TYPE_COLOR:
            var colour: Color = value
            packed.encode_float(at, colour.r)
            packed.encode_float(at + 4, colour.g)
            packed.encode_float(at + 8, colour.b)
            packed.encode_float(at + 12, colour.a)
        elif type_name == "vec4" and kind == TYPE_VECTOR4:
            var four: Vector4 = value
            packed.encode_float(at, four.x)
            packed.encode_float(at + 4, four.y)
            packed.encode_float(at + 8, four.z)
            packed.encode_float(at + 12, four.w)
        else:
            _write_field(packed, at, type_name, _sizes[i], value)
    return packed


## Compares what is about to be sent against what the shader declares it takes.
##
## The float array door only pads the tail, so without this the GLSL and the
## GDScript that fills it are matched by eye. RenderingDevice does refuse a wrong
## size, but it reports it as the push constant being *absent*, which sends you
## looking for a binding bug. Saying it here names both numbers and the shader.
##
## Size only. A wrong *order* is the silent one, and the named door,
## [method complaint], is what catches it.
func _verify_size() -> void:
    if _warned_size:
        return
    var declared := GlobalShaderCompiler.push_constant_bytes(_shader_name)
    if declared <= 0 or declared == bytes.size():
        return
    _warned_size = true
    push_error(
        (
            "SaCompute('%s'): the shader declares %d bytes of push constant and %d are being sent."
            % [_shader_name, declared, bytes.size()]
        )
    )


## What is wrong with *values* against *layout*, or an empty String when nothing
## is.
##
## Two mistakes are worth telling apart. An unknown name is a typo or a field
## that was renamed in the GLSL, and packing around it would send a block the
## caller does not think it sent, so it is refused. A missing name is a field the
## caller forgot, and zero is not a safe guess for an opacity or a radius, so it
## is refused too. Both are named, because "the push constant is the wrong size"
## sends you looking at the block rather than at the one word.
##
## **The tail pad is not a field anybody declared**, so it is neither asked for
## nor accepted. A `params:` block in the dialect ends with the fields std430
## needs to reach the boundary, and to the layout they read exactly like the
## kernel author's own. Asking a caller for `_pad_0` would refuse every dialect
## kernel: nothing would be packed and the dispatch would fail with a push
## constant that is not present.
static func complaint(layout: Array, values: Dictionary) -> String:
    if layout.is_empty():
        return "there is no push constant block to fill, so set_params() has nothing to pack."

    var declared: Dictionary[String, String] = {}
    for field: Dictionary[String, Variant] in layout:
        if not str(field["name"]).is_empty() and not _is_pad(field):
            declared[str(field["name"])] = field["type"]

    var unknown: Array[String] = []
    for key: Variant in values:
        if not declared.has(str(key)):
            unknown.append(str(key))
    if not unknown.is_empty():
        return "the block declares no field named %s. It declares %s." % [_quoted(unknown), _quoted(declared.keys())]

    var missing: Array[String] = []
    for name: String in declared:
        if not values.has(name):
            missing.append(name)
    if not missing.is_empty():
        return "no value was given for %s, and a field left out would be sent as zero." % _quoted(missing)

    for name: String in declared:
        var wanted := String(declared[name])
        if not COMPONENTS.has(wanted):
            return "field '%s' is declared %s, which this packer does not know how to write." % [name, wanted]
    return ""


## Packs *values* into the block *layout* declares, at exactly the size it
## declares.
##
## The declared order and the declared offsets are what is written, so the
## Dictionary's own order does not matter and a gap std430 left between two fields
## stays zero. Returns an empty array when `complaint()` has something to say.
##
## A pad the compiler wrote is skipped rather than written, so it stays the zero
## the resize left. The block is still packed at its full declared size,
## `layout[-1]["offset"]` counting the pad the way it counts every other field,
## which is the whole point of writing the pad as fields.
static func pack(layout: Array, values: Dictionary) -> PackedByteArray:
    if not complaint(layout, values).is_empty():
        return PackedByteArray()

    var last: Dictionary = layout[-1]
    var total: int = last["offset"]
    var padded: int = ceili(float(total) / float(BLOCK_ALIGNMENT)) * BLOCK_ALIGNMENT
    var packed := PackedByteArray()
    packed.resize(padded)
    for field: Dictionary[String, Variant] in layout:
        var name := str(field["name"])
        if name.is_empty() or _is_pad(field):
            continue
        var offset: int = field["offset"]
        var size: int = field["size"]
        _write_field(packed, offset, str(field["type"]), size, values[name])
    return packed


## Whether *field* is a pad the layout added, which no caller fills.
static func _is_pad(field: Dictionary) -> bool:
    var pad: bool = field.get("pad", false)
    return pad


## *params* with the region written into `origin` and `extent`, for the fields
## the block declares and the caller left out.
##
## A kernel that dispatches over one rectangle and reads another needs to know
## which rectangle it is on, and this spares every caller passing it by hand. A caller who
## passes `origin` or `extent` wins, because that is the case the rule exists for.
## The Dictionary is copied rather than written through, so a caller's own is not
## changed under it.
static func with_region(layout: Array, params: Dictionary, region: Rect2i) -> Dictionary[String, Variant]:
    # The caller's params arrive untyped from a module, and are copied into a
    # typed Dictionary here, where they enter. Each key goes through `str`, so
    # a key that names no field is still refused by name in `complaint`.
    var out: Dictionary[String, Variant] = {}
    for key: Variant in params:
        out[str(key)] = params[key]
    var from_region: Dictionary[String, Vector2] = {"origin": Vector2(region.position), "extent": Vector2(region.size)}
    for field: Dictionary[String, Variant] in layout:
        var name := str(field["name"])
        if from_region.has(name) and not out.has(name):
            out[name] = from_region[name]
    return out


## One field written at its declared offset.
##
## A vector arrives as its Vector type, an array as a packed array, and a scalar
## as a number, which is what a caller has in hand at the call site. An array
## field's size is the whole run of it, and `float[9]` under std430 has a stride of
## four, which is the reason the composite matrices are declared that way rather
## than as `mat3`, whose columns std430 pads to sixteen bytes.
##
## The entries are walked by the stride `ARRAY_STRIDES` gives the type and the
## components inside one entry four bytes apart, which is the same arithmetic for
## every type Sara declares: only a `vec3[]` has a stride wider than its entry, and
## a field that is not an array is one entry.
static func _write_field(into: PackedByteArray, offset: int, type_name: String, size: int, value: Variant) -> void:
    var components: int = COMPONENTS[type_name]
    var stride: int = ARRAY_STRIDES[type_name]
    # Exact, not truncated: a field's size is its stride times its array length,
    # which is where this number comes back from. A field that is not an array is
    # narrower than one stride when it is a `vec3`, so it counts as one entry.
    @warning_ignore("integer_division")
    var count: int = maxi(size / stride, 1)
    var numbers := _as_numbers(value)
    var slots: int = mini(numbers.size(), components * count)
    for i in range(slots):
        @warning_ignore("integer_division")
        var entry: int = i / components
        var at := offset + entry * stride + (i % components) * 4
        if type_name == "bool":
            # GLSL keeps a `bool` in a block as a 32-bit word, nought for false
            # and one for true, so a ticked box and a 1 from a notebook both
            # arrive as the same true.
            into.encode_u32(at, 1 if numbers[i] else 0)
        elif type_name == "int" or type_name == "uint":
            var whole: int = numbers[i]
            if type_name == "int":
                into.encode_s32(at, whole)
            else:
                into.encode_u32(at, whole)
        else:
            var number: float = numbers[i]
            into.encode_float(at, number)


## Whatever the caller handed over, as a flat array of numbers.
##
## The vector types are here because a caller who has a Vector2 should not have to
## spell it out as two floats, and Color is here because an RGBA value is what a
## `vec4` in a Sara kernel almost always is.
static func _as_numbers(value: Variant) -> Array:
    match typeof(value):
        TYPE_VECTOR2:
            return [value.x, value.y]
        TYPE_VECTOR2I:
            return [value.x, value.y]
        TYPE_VECTOR3:
            return [value.x, value.y, value.z]
        TYPE_VECTOR3I:
            return [value.x, value.y, value.z]
        TYPE_VECTOR4:
            return [value.x, value.y, value.z, value.w]
        TYPE_VECTOR4I:
            return [value.x, value.y, value.z, value.w]
        TYPE_COLOR:
            return [value.r, value.g, value.b, value.a]
        TYPE_ARRAY:
            return value
        TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY:
            var entries: Array = value
            return entries
        _:
            return [value]


## Field names in quotes and separated by commas, for a message that has to say
## which. The declared bindings keep their own copy of this, because the two
## classes name different things and neither should reach into the other for five
## lines of string join.
static func _quoted(names: Array) -> String:
    var out: Array[String] = []
    for name: Variant in names:
        out.append("'%s'" % str(name))
    return ", ".join(out)
