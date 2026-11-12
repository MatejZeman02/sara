## One field in a layer's schema: what it is called, how it is stored, and
## whether anything paints into it.
##
## A schema rather than a fixed colour field, so every consumer (duplicate,
## undo, fill, save, load, composite) is a loop over the schema, and a field
## such as impasto's height reaches all of them without a rewrite of each.
##
## Impasto ships `[albedo, height]`, a mixing layer ships
## `[concentrations, thickness, albedo*]` where the albedo is derived. Neither needs
## SaChunk, undo or the .sad structure to change.
@tool
class_name SaFieldSpec
extends RefCounted

## Bytes one texel occupies, per storage format.
##
## Nothing may assume 16. A document may store F16, and a single-channel height
## field is 4 bytes or 2, so every readback offset has to come from here.
const BYTES_PER_TEXEL := {
    RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT: 16,
    RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT: 8,
    RenderingDevice.DATA_FORMAT_R32_SFLOAT: 4,
    # Two channels rather than four, for an image brush tip's coverage and its
    # lightness. Here rather than in a second table, because this is the only
    # place that knows a texel's size: without the row the lookup below would
    # answer the sixteen-byte default and over-count VRAM by a factor of two
    # for every tip loaded.
    RenderingDevice.DATA_FORMAT_R32G32_SFLOAT: 8,
    RenderingDevice.DATA_FORMAT_R16_SFLOAT: 2,
}

## The field every document has and the only one the compositor reads.
const ALBEDO: StringName = &"albedo"

## What a layer hides. The spelling is `SaSelection.FIELD`'s on purpose: a mask
## and a selection are the same single-channel coverage, so a chunk of one is a
## chunk of the other and one moves across to the other by a copy.
const MASK: StringName = &"mask"

## How thick a layer's paint stands, in virtual millimetres, zero meaning bare
## paint. A layer gains it on the first height-writing dab
## through `SaHeightOps.gain`, and a chunk of it only where height is written.
const HEIGHT: StringName = &"height"

## What a height is stored at: one half float a texel, a quarter of an F16
## colour texel. A hundredth of a millimetre at the ten millimetres paint
## stacks to, which is finer than any relief shows.
const HEIGHT_FORMAT: int = RenderingDevice.DATA_FORMAT_R16_SFLOAT

## What a fresh texture of most fields is cleared to: no paint.
const NO_PAINT := Color(0, 0, 0, 0)

## What a fresh mask texture is cleared to: everything shown.
const SHOWN := Color(1, 1, 1, 1)

## Stable identifier. Persisted in `.sad`, so it must not change meaning.
var id: StringName = ALBEDO

## A `RenderingDevice.DATA_FORMAT_*` value. Must be a key of BYTES_PER_TEXEL.
var format: int = RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT

## Fields this one is computed from.
##
## Empty means authoritative: a tool paints into it and it is what undo captures.
## Non-empty means the layer's resolve hook writes it before compositing, from
## the named fields, height to normals, concentrations to RGBA.
var derived_from: Array[StringName] = []

## Whether these values are colour, and so are converted when the document's
## colour space changes. Height, thickness and concentration are not.
var is_color: bool = true

## What a freshly allocated texture of this field holds.
##
## Transparent for every field but the mask, whose blank is one. Allocation
## leaves a texture undefined, so something clears it, and a mask cleared to
## zero with the rest of its chunk would hide the first dab painted into that
## chunk. `SaChunk` reads this where it clears a chunk whole.
var blank: Color = NO_PAINT

## Whether a chunk holds this field only once something writes it.
##
## False for colour and a mask, which every chunk of the layer carries from
## the moment it is allocated. True for height, which costs a quarter more
## memory on every chunk it is in and so is allocated where a dab lands it and
## nowhere else. `SaChunk.create` leaves a lazy field out, and
## `SaLayer.get_or_create_field` is the one door that puts it in. A chunk that
## holds no texture of it reads as the blank, zero.
var lazy: bool = false


static func create(
    field_id: StringName,
    field_format: int = RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT,
    color: bool = true,
    sources: Array[StringName] = []
) -> SaFieldSpec:
    var spec := SaFieldSpec.new()
    spec.id = field_id
    spec.format = field_format
    spec.is_color = color
    spec.derived_from = sources
    return spec


## The default schema's only entry: authoritative colour, F32 unless told.
##
## The format is a parameter rather than a constant because it is the document's
## choice, not this file's. A constant here would let a document record
## `"depth": "F16"` in its header while every chunk it allocates is F32.
static func albedo(format_bits: int = RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT) -> SaFieldSpec:
    return SaFieldSpec.create(ALBEDO, format_bits)


## The mask a layer carries once it has one: single channel, never colour, at
## the selection's format whatever depth the document paints at, and one where
## nothing was painted into it.
static func mask() -> SaFieldSpec:
    var spec := SaFieldSpec.create(MASK, SaSelection.FORMAT, false)
    spec.blank = SHOWN
    return spec


## A field a chunk holds only where it has been written: never colour, zero
## where nothing was, and allocated by `SaLayer.get_or_create_field`.
static func sparse(field_id: StringName, field_format: int) -> SaFieldSpec:
    var spec := SaFieldSpec.create(field_id, field_format, false)
    spec.lazy = true
    return spec


## The height a paint layer carries once a height-writing dab has landed on it.
static func height() -> SaFieldSpec:
    return sparse(HEIGHT, HEIGHT_FORMAT)


## The schema a layer gets when nobody says otherwise.
static func default_schema(format_bits: int = RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT) -> Array[SaFieldSpec]:
    var schema: Array[SaFieldSpec] = [albedo(format_bits)]
    return schema


## The schema a plain colour layer of a document in *space* gets.
##
## The one place that turns a document's declared depth into storage. Everything
## that builds a layer for a document goes through here, so the header and the
## allocation cannot disagree.
static func schema_for_space(space: SaColorSpace) -> Array[SaFieldSpec]:
    if space == null:
        return default_schema()
    return default_schema(space.texel_format())


## True when a resolve hook writes this field rather than a tool painting it.
func is_derived() -> bool:
    return not derived_from.is_empty()


## Bytes one texel of this field occupies. Never hardcode 16.
func bytes_per_texel() -> int:
    return BYTES_PER_TEXEL.get(format, 0)


## Finds a spec by id, or null. Schemas are one to three entries, so a linear
## scan is the right shape and keeps the schema an ordered Array.
static func find(schema: Array[SaFieldSpec], field_id: StringName) -> SaFieldSpec:
    for spec in schema:
        if spec != null and spec.id == field_id:
            return spec
    return null


## One texel of *bytes*, at *format*, as a Color.
##
## The offsets and the width both come from the format, which is the whole
## point: reading an F16 texel with `decode_float` takes four bytes where the
## half occupies two, so red comes back as two halves glued together, blue reads
## past the end of a one-texel readback, and the engine logs an out-of-bounds
## decode for every sample. The eyedropper did exactly that, and returned
## (0.00003, 0.00783, 0, 0) for a pixel holding (0.25, 0.5, 0.75, 1).
##
## A single-channel field has no colour, so its one value is returned in red
## with alpha 1, which is what a heightfield preview wants.
static func decode_texel(bytes: PackedByteArray, texel_format: int, index: int = 0) -> Color:
    var width: int = BYTES_PER_TEXEL.get(texel_format, 0)
    if width == 0 or bytes.size() < (index + 1) * width:
        return Color.TRANSPARENT
    var base: int = index * width

    match texel_format:
        RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT:
            return Color(
                bytes.decode_float(base),
                bytes.decode_float(base + 4),
                bytes.decode_float(base + 8),
                bytes.decode_float(base + 12)
            )
        RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT:
            return Color(
                bytes.decode_half(base), bytes.decode_half(base + 2), bytes.decode_half(base + 4), bytes.decode_half(base + 6)
            )
        RenderingDevice.DATA_FORMAT_R32_SFLOAT:
            return Color(bytes.decode_float(base), 0.0, 0.0, 1.0)
        RenderingDevice.DATA_FORMAT_R16_SFLOAT:
            return Color(bytes.decode_half(base), 0.0, 0.0, 1.0)

    return Color.TRANSPARENT
