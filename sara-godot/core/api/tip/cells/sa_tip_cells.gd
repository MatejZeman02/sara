## A pipe's cells made on the card from their own bytes.
##
## `SaTipCache` reads a pipe's cells as the file holds them, one byte a texel
## for a grey pipe and four for a colour one, and hands them here.
## `tip_cell.gmacs`, beside this, makes each into the `r32g32f` texture
## [method SaTipImage.upload] makes from the CPU's texels, the same to the bit,
## so no loop over a texel runs on the CPU and a grey pipe sends an eighth of
## what its tips hold.
##
## **The kernel is told the CPU's own numbers rather than doing the
## arithmetic**, because the card's is not the CPU's. A coverage is `byte / 255`
## rounded to a float, from [method coverage_table]. A colour texel's lightness
## is the luminance `SaTipImage` sums in doubles, and its three products are
## [method share_table]'s 64-bit fixed-point numbers, which each is exactly, so
## the kernel makes the sums and both roundings in integers. Not every card Sara
## runs on has doubles.
##
## **One instance is one compute list.** [method expand] settles a cell's
## dispatch and [method send] sends every one settled since, so a frame's share
## of a load, or the whole of it at a press, is one list rather than one a cell.
class_name SaTipCells
extends RefCounted

## The kernel and its two tables, made at the first cell and kept, since they
## are the same for every cell of every pipe.
static var _compute: SaCompute = null
static var _coverage: SaCompute.Buffer = null
static var _shares: SaCompute.Buffer = null
## The size and depth the block was last packed for. The cells of one pipe
## share both nearly always, so the block is packed again only when one of them
## changes rather than by name at every cell, which is a large share of a cell's
## cost.
static var _packed: Vector3i = Vector3i.ZERO

## The dispatches [method expand] settled, and the cells' bytes on the card,
## held until [method send] sends them.
var _recorded: Array[SaCompute.Recorded] = []
var _held: Array[SaCompute.Buffer] = []


## The tip texture of *size* to be made from *texels*, *depth* bytes a texel as
## the cell's GBR holds them, or null with no device to make it on. Made once
## [method send] has sent it.
func expand(size: Vector2i, depth: int, texels: PackedByteArray) -> SaTexture:
    var texture := SaTexture.new(size, RenderingDevice.DATA_FORMAT_R32G32_SFLOAT)
    if texture.rd == null or not texture.rid.is_valid():
        return null
    if _compute == null:
        _compute = SaCompute.new("tip_cell")
        _coverage = SaCompute.Buffer.new(coverage_table())
        _shares = SaCompute.Buffer.new(share_table())
        _compute.set_storage("coverage", _coverage.rid)
        _compute.set_storage("luminance", _shares.rid)
    var cell := SaCompute.Buffer.new(texels)
    _held.append(cell)
    _compute.set_image("tip", texture.rid)
    _compute.set_storage("cell", cell.rid)
    if _packed != Vector3i(size.x, size.y, depth):
        _packed = Vector3i(size.x, size.y, depth)
        _compute.set_params({"width": size.x, "height": size.y, "depth": depth})
    # The kernel names its own format, so the storage format is the one it was
    # built at and nothing reloads.
    var format := _compute.pipelines.storage_format
    var groups := Vector2i(SaCompute.groups_for(size.x), SaCompute.groups_for(size.y))
    var one := _compute.record("expand_tip_cell", format, groups.x, groups.y, 1, false)
    if one != null:
        _recorded.append(one)
    return texture


## Sends every cell [method expand] settled in one compute list. The device
## keeps the cells' bytes for the frame the list runs in once they are let go.
func send() -> void:
    SaCompute.submit(_recorded, "tip_cell")
    _recorded.clear()
    _held.clear()


## `byte / 255` for every byte, rounded to a float as `SaTipImage.gbr_at`
## rounds it.
static func coverage_table() -> PackedByteArray:
    var table := PackedFloat32Array()
    for value in 256:
        table.append(float(value) / 255.0)
    return table.to_byte_array()


## Red's, green's and blue's share of the luminance for every byte, the product
## `SaTipImage._gbr_luminance` makes, as two words of the double times two to
## the 64, low first.
##
## Every share is a whole number of two to the minus 64 and under one, since
## the smallest, one 255th of blue's weight, is over two to the minus 12, and a
## double's last bit is 52 places under its first.
static func share_table() -> PackedByteArray:
    var weights := SaTipImage.LUMINANCE_WEIGHTS
    var table := PackedByteArray()
    table.resize(3 * 256 * 8)
    for channel in 3:
        for value in 256:
            var share := float(value) / 255.0 * weights[channel]
            if share == 0.0:
                continue
            var bits := PackedFloat64Array([share]).to_byte_array().decode_s64(0)
            var at := (channel * 256 + value) * 8
            # The double is its 53-bit mantissa times two to its exponent less
            # 52, so times two to the 64 it is the mantissa shifted up by the
            # exponent and 12, which is 0 to 11 for a share under one.
            var mantissa := (bits & ((1 << 52) - 1)) | (1 << 52)
            var up := ((bits >> 52) & 0x7FF) - 1023 + 12
            table.encode_u32(at, (mantissa & ((1 << (32 - up)) - 1)) << up)
            table.encode_u32(at + 4, mantissa >> (32 - up))
    return table
