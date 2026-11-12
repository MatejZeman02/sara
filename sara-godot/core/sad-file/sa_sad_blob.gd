## One texture of a `.sad` as its blob, and back: a chunk's field, a mask's own
## chunk and a simulation's seed chunk all go through here.
##
## **From version 14 a blob may be planes.** `sad_blob.gmacs`, beside this,
## takes each channel's bit pattern from the texel to its left as an integer,
## which is exact, and splits the differences into byte planes, every texel's
## first byte, then every texel's second, and so on, before Zstd. A float's
## sign and exponent bytes repeat and its low mantissa bytes are close to
## noise, and as the texture holds them the two alternate, so Zstd found little
## to repeat. The forward kernel runs before the readback of a save and the
## inverse after the upload of a load, because a byte loop in GDScript over a
## hundred megabytes takes minutes.
##
## **The smaller form is kept.** Planes win on smooth paint and lose on
## much else, a half precision painting above all, where most chunks grew under
## them. So a save reads back both the planes and the texture's bytes as they
## lie, compresses each, and keeps whichever came out smaller. A guess on the
## card from a count beside the planes picked wrong too often to stand in for
## the two compressions. A mask is always stored plain, since plain wins on
## most mask chunks and saves nearly all the choice would.
##
## **A planes form that came out badly is not weighed against the plain form.**
## Rounding colour to 12 bits leaves the plain form of random colour near its
## full size, a run of short matches that Zstd codes slowly, while a planes form
## above [constant PLANES_PLAIN_LIMIT] of the chunk was never the smaller of the
## two on the reference paintings or on random colour, where it is around 0.6 of
## the chunk. So the planes form is compressed first and a planes form past that
## limit is stored without the plain form being compressed at all, which is
## where a rounded save of random colour spent its time. At or under the limit,
## and with no planes at all, the two are weighed as they always were.
##
## **The entry names the transform.** A blob stored as planes carries
## `"transform": "delta_planes"` beside its offset and sizes, and one without
## the key holds the texture's bytes as they lie, which is every blob of a file
## stamped 13 or under, every blob where plain came out smaller, and any
## texture the kernels cannot take: a format not in [constant LAYOUT], or a
## width that is not a multiple of four.
class_name SaSadBlob
extends RefCounted

## The key of a blob's entry that names its transform, and the one transform.
const TRANSFORM_KEY := "transform"
const DELTA_PLANES := "delta_planes"

## The share of a chunk's bytes a planes form may take and still be weighed
## against the plain form. A planes form past it is stored without the plain
## form being compressed, which the research measured at 0.3: no reference
## painting, and no chunk of random rounded colour, held such a planes form
## that the plain form was smaller.
const PLANES_PLAIN_LIMIT := 0.3

## The kernels' file.
const SHADER := "sad_blob"
## The lanes of the inverse kernel's workgroup, one workgroup a row.
## `sad_blob.gmacs` holds the same number.
const ROW_LANES := 256

## Channels, and bytes a channel, of every format the kernels take,
## `SaSadCodec.LAYOUT`, since a codec takes the same four.
const LAYOUT := SaSadCodec.LAYOUT

## The kernels, made at the first blob and kept.
static var _compute: SaCompute = null
## The planes a save reads back, kept between blobs of one size, since every
## chunk of a field is the same size and a buffer a chunk was a megabyte of
## zeroes made and thrown away each time.
static var _planes: SaCompute.Buffer = null
## The planes a load sends, kept the same way. An update of it waits on the
## dispatch that read it last, which the device orders, and making a buffer a
## chunk was most of what an open cost on top of the bytes as they lie.
static var _uploads: SaCompute.Buffer = null


## Appends *texture*'s blob to *blobs* and answers its entry, `offset`, `size`,
## `raw_size` and, when planes came out smaller, `transform`, or an empty entry
## when the texture gave nothing back. The caller adds what places it. With
## *plain* the bytes are stored as they lie with no comparison, as a version 13
## build stored them. With *coded*, a chunk's colour or height field, a save
## that asked for a codec codes it there, `SaSadCodec`. A blob is copied from
## the file the save replaces when its key, which names the codec, matches, so
## a save in a codec copies only blobs coded in it, and a mask's Zstd blob.
static func write(
    texture: SaTexture, blobs: PackedByteArray, rd: RenderingDevice, plain := false, coded := false
) -> Dictionary[String, Variant]:
    var slot: Dictionary[String, Variant] = {}
    if texture == null or rd == null or not texture.rid.is_valid():
        return slot
    var codec := SaSadCodec.asked(texture, coded and not plain)
    # A texture as the last save wrote it is copied from that file.
    var key := SaSadSnapshot.key_of(texture, plain, codec)
    var old := SaSadSnapshot.old_slot(key)
    # A save in the background copies the texture on the card here and reads
    # it back over the next frames, so this walk asks the device for nothing.
    if SaSadSave.taking != null:
        var taken := SaSadSave.taking.take(texture, takes(texture) and not plain and codec.is_empty(), old)
        var copied := not old.is_empty()
        return SaSadSnapshot.noted(key, taken if copied else SaSadCodec.name_in(taken, codec), copied)
    var packed := SaSadSnapshot.read_now(old) if not old.is_empty() else PackedByteArray()
    if not packed.is_empty():
        copy_into(slot, old, packed, blobs)
        return SaSadSnapshot.noted(key, slot, true)
    var source := SaSadSnapshot.to_read(texture)
    var planes := _planes_of(source) if takes(source) and not plain and codec.is_empty() else PackedByteArray()
    var raw := rd.texture_get_data(source.rid, 0)
    if raw.is_empty():
        return slot
    var stream := SaSadCodec.encoded(raw, source) if not codec.is_empty() else PackedByteArray()
    if stream.is_empty():
        fill_smaller(slot, planes, raw, blobs)
    else:
        place(slot, stream, raw.size(), blobs)
        slot[SaSadCodec.KEY] = String(codec)
    return SaSadSnapshot.noted(key, slot, false)


## Compresses *raw* onto the end of *blobs* and writes where it went into
## *slot*. Touches no device and no shared state, so `SaSadSave`'s worker
## calls it off the main thread.
static func fill(slot: Dictionary[String, Variant], raw: PackedByteArray, blobs: PackedByteArray) -> void:
    place(slot, raw.compress(SaSadFile.SAD_BLOB_COMPRESS), raw.size(), blobs)


## Compresses *planes* and *raw*, one texture's two forms, and appends the
## smaller to *blobs*, naming the transform in *slot* only when the planes won.
## A tie, or no planes at all, stores the bytes as they lie. Compresses the
## planes form first and reaches for the plain form only when the planes form
## came out at or under [constant PLANES_PLAIN_LIMIT] of the chunk, the guard
## the class comment describes. Off the main thread as [method fill] is.
static func fill_smaller(
    slot: Dictionary[String, Variant], planes: PackedByteArray, raw: PackedByteArray, blobs: PackedByteArray
) -> void:
    if planes.size() != raw.size():
        fill(slot, raw, blobs)
        return
    var packed_planes := planes.compress(SaSadFile.SAD_BLOB_COMPRESS)
    if packed_planes.size() > PLANES_PLAIN_LIMIT * raw.size():
        slot[TRANSFORM_KEY] = DELTA_PLANES
        place(slot, packed_planes, raw.size(), blobs)
        return
    var packed := raw.compress(SaSadFile.SAD_BLOB_COMPRESS)
    if packed_planes.size() < packed.size():
        slot[TRANSFORM_KEY] = DELTA_PLANES
        packed = packed_planes
    place(slot, packed, raw.size(), blobs)


## Appends *packed*, the compressed blob *old* names in the file a save
## replaces, to *blobs* and writes where it went into *slot*, with the form,
## the codec and the size *old* gives, so a copied JPEG XL blob stays one. Off
## the main thread as [method fill] is.
static func copy_into(
    slot: Dictionary[String, Variant], old: Dictionary[String, Variant], packed: PackedByteArray, blobs: PackedByteArray
) -> void:
    if is_planes(old):
        slot[TRANSFORM_KEY] = DELTA_PLANES
    if old.has(SaSadCodec.KEY):
        slot[SaSadCodec.KEY] = old[SaSadCodec.KEY]
    place(slot, packed, SaTyped.int_at(old, "raw_size", 0), blobs)


## Appends *packed*, a blob already in its stored form, to *blobs* and writes
## where it went into *slot*, with *raw_size*, the texture's bytes.
static func place(slot: Dictionary[String, Variant], packed: PackedByteArray, raw_size: int, blobs: PackedByteArray) -> void:
    slot["offset"] = blobs.size()
    slot["size"] = packed.size()
    slot["raw_size"] = raw_size
    blobs.append_array(packed)


## The bytes *slot* addresses in *blobs*, out of Zstd, or none when the slot
## points outside them or they will not decompress. Planes stay planes until
## [method upload]. A blob whose slot names a codec is decoded by it to fill
## *texture*, `SaSadCodec.decode`.
static func read(slot: Dictionary[String, Variant], blobs: PackedByteArray, texture: SaTexture = null) -> PackedByteArray:
    var offset := SaTyped.int_at(slot, "offset", 0)
    var size := SaTyped.int_at(slot, "size", 0)
    if size <= 0 or offset < 0 or offset + size > blobs.size():
        return PackedByteArray()
    if slot.has(SaSadCodec.KEY):
        return SaSadCodec.decode(slot, blobs.slice(offset, offset + size), texture)
    return blobs.slice(offset, offset + size).decompress(SaTyped.int_at(slot, "raw_size", 0), SaSadFile.SAD_BLOB_COMPRESS)


## Whether *slot*'s blob is planes. A transform this build does not know is
## not, and its bytes then fail [method upload]'s size check or show as noise,
## which is why a file that holds one is stamped above what an older build reads.
static func is_planes(slot: Dictionary[String, Variant]) -> bool:
    return SaTyped.text_at(slot, TRANSFORM_KEY, "") == DELTA_PLANES


## Puts *bytes*, as [method read] gave them, into *texture*: as they lie, or
## through the inverse kernel when *planes*. False when planes do not fit the
## texture, which is then left as it was.
static func upload(texture: SaTexture, bytes: PackedByteArray, planes: bool) -> bool:
    var rd := texture.rd
    if rd == null or not texture.rid.is_valid() or bytes.is_empty():
        return false
    if not planes:
        rd.texture_update(texture.rid, 0, bytes)
        return true
    if not takes(texture) or bytes.size() != _bytes_of(texture):
        return false
    if _uploads == null or _uploads.size != bytes.size():
        _uploads = SaCompute.Buffer.new(bytes)
    else:
        _uploads.update(bytes)
    _kernels().run(
        "sad_blob_texels", {"field": texture, "planes": _uploads}, _params(texture), Rect2i(0, 0, ROW_LANES, texture.size.y)
    )
    return true


## Whether *slot*'s blob is planes, as [method is_planes] answers, noting for
## `SaSadSnapshot.opened` that *raw*, its bytes out of Zstd, fill *texture*
## exactly as an open is about to upload them. The loader asks it at each
## chunk it fills.
static func opening(texture: SaTexture, slot: Dictionary[String, Variant], raw: PackedByteArray) -> bool:
    var planes := is_planes(slot)
    if texture != null and LAYOUT.has(texture.format) and raw.size() == _bytes_of(texture) and (not planes or takes(texture)):
        SaSadSnapshot.opening(texture, slot, planes)
    return planes


## Whether the kernels take *texture*.
static func takes(texture: SaTexture) -> bool:
    return LAYOUT.has(texture.format) and texture.size.x % 4 == 0 and texture.size.x > 0 and texture.size.y > 0


## *texture* as planes, read back, or none with no device.
static func _planes_of(texture: SaTexture) -> PackedByteArray:
    var bytes := plane_bytes(texture)
    if _planes == null or _planes.size != bytes:
        _planes = planes_buffer(bytes)
    if not _planes.rid.is_valid():
        return PackedByteArray()
    planes_into(texture, _planes)
    return _planes.read()


## A buffer of *bytes* for [method planes_into] to fill.
static func planes_buffer(bytes: int) -> SaCompute.Buffer:
    var zeroes := PackedByteArray()
    zeroes.resize(bytes)
    return SaCompute.Buffer.new(zeroes)


## Sends the forward kernel, *texture* into *planes* as byte planes of deltas,
## without reading anything back. *planes* holds [method plane_bytes] bytes.
static func planes_into(texture: SaTexture, planes: SaCompute.Buffer) -> void:
    var region := Rect2i(0, 0, floori(texture.size.x / 4.0), texture.size.y)
    _kernels().run("sad_blob_planes", {"field": texture, "planes": planes}, _params(texture), region)


## The bytes *texture*'s planes take, which are the bytes it holds, for a
## format of [constant LAYOUT].
static func plane_bytes(texture: SaTexture) -> int:
    return _bytes_of(texture)


static func _bytes_of(texture: SaTexture) -> int:
    var layout: Vector2i = LAYOUT[texture.format]
    return texture.size.x * texture.size.y * layout.x * layout.y


static func _params(texture: SaTexture) -> Dictionary:
    var layout: Vector2i = LAYOUT[texture.format]
    return {"width": texture.size.x, "height": texture.size.y, "channels": layout.x, "channel_bytes": layout.y}


static func _kernels() -> SaCompute:
    if _compute == null:
        _compute = SaCompute.new(SHADER)
    return _compute
