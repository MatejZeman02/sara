## RAII wrapper for low-level RenderingDevice textures.
##
## Manages the lifecycle of a Vulkan texture RID. Automatically frees
## VRAM resources when the object is garbage collected.
@tool
extends RefCounted

class_name SaTexture

var rid: RID
var size: Vector2i
var rd: RenderingDevice

## Every texture Sara makes asks for the same five usage bits, whatever its
## format. The device floor probe reads this rather than a copy of its own, so
## the probe can never drift from the texture it is meant to answer for.
const USAGE_BITS: int = (
    RenderingDevice.TEXTURE_USAGE_STORAGE_BIT
    | RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
    | RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT
    | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
    | RenderingDevice.TEXTURE_USAGE_CAN_COPY_TO_BIT
)

## The RenderingDevice.DATA_FORMAT_* this texture was created with. Kept because
## a copy has to be allocated in the same format, and because a readback offset
## depends on it, a height field is 4 bytes per texel, not 16.
var format: int = RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT


## _size: Vector2i - dimensions of the texture
## format_bits: int - optional, specify the data format (default is RGBA32F)
func _init(_size: Vector2i, format_bits: int = RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT) -> void:
    assert(_size.x > 0 and _size.y > 0, "Texture size must be positive")

    size = _size
    format = format_bits
    rd = GlobalShaderCompiler.get_rd()
    if rd == null:
        return

    var fmt := RDTextureFormat.new()
    fmt.width = size.x
    fmt.height = size.y
    fmt.format = format_bits as RenderingDevice.DataFormat

    # Set all common usage flags required for compute shaders and drawing
    fmt.usage_bits = USAGE_BITS

    rid = rd.texture_create(fmt, RDTextureView.new(), [])
    if not rid.is_valid():
        # Not an assert. Those are stripped from release builds, which is where
        # a machine short of VRAM would otherwise paint into nothing silently.
        SaProblems.report("SaTexture", "could not allocate a %dx%d texture (format %d)." % [size.x, size.y, format])
    if rid.is_valid():
        bytes = size.x * size.y * SaTyped.int_at(SaFieldSpec.BYTES_PER_TEXEL, format, 16)
        allocated_bytes += bytes

    # Deliberately not cleared. Every chunk allocation immediately cleared the
    # fresh texture a second time, to transparent, so the opaque grey was a
    # full-chunk GPU clear thrown away on every allocation. "Grey" also means
    # nothing for a single-channel height or concentration field. Whoever needs a
    # known starting value asks for it.


## Fills the whole texture with one value. Call it if you need a defined starting
## state, allocation does not give you one.
func clear(color: Color) -> void:
    if rd != null and rid.is_valid():
        rd.texture_clear(rid, color, 0, 1, 0, 1)


## Automatic cleanup (Destructor)
## Bumped whenever any texture is freed, so a cache keyed on texture RIDs knows to
## drop without having to be told which entry.
##
## Coarse on purpose. Textures are never freed mid-stroke, so the hot path sees
## this stand still and pays nothing, and a rebuild after a resize or a File > New
## warms back up within a frame.
static var epoch: int = 0

## Bytes of VRAM held by every SaTexture alive.
##
## Rather than what the layers' own schemas add up to, because undo history is
## textures nobody's schema lists, two full snapshots per touched chunk per
## stroke. Counted here because this is the one place a texture is allocated and
## the one place it is freed, so the number cannot drift from the truth. One for
## every document, because the card's memory is one budget they all share.
static var allocated_bytes: int = 0

## Undo's two snapshot sites, `SaChunkDelta.capture` and `SaChunk.duplicate_chunk`,
## each call `note_copy` once per field they copy. A GPU to GPU `texture_copy`
## is invisible to SaCompute's dispatch counters, and history is the larger
## half of VRAM. Neither restore site calls it, so the count is snapshots
## taken, not every `texture_copy` in the tree.
static var copies: int = 0
static var copied_bytes: int = 0


## Records one snapshot copy of *byte_count* bytes.
static func note_copy(byte_count: int) -> void:
    copies += 1
    copied_bytes += byte_count


## This texture's own contribution, so PREDELETE gives back exactly what _init took
## rather than recomputing from fields that may have been reassigned.
## VRAM this one texture holds. Zero once it has been freed.
var bytes: int = 0


func _notification(what: int) -> void:
    if what == NOTIFICATION_PREDELETE:
        # free the RID when the object is destroyed
        if rid.is_valid() and rd != null:
            rd.free_rid(rid)
            rid = RID()  # reset RID to an invalid state
            allocated_bytes -= bytes
            bytes = 0
            # Freeing an image RID takes every uniform set that referenced it with
            # it, so any set SaCompute has cached against this texture is now a
            # dangling handle. Nothing here knows which ones, so say only that
            # something went away and let the caches drop wholesale.
            epoch += 1
