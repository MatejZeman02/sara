## The colour profile a picture carries, found in the file's own bytes, and the
## gamut an EXR names in its `chromaticities` attribute.
##
## Godot 4.7 reads a PNG's `iCCP`, a JPEG's profile, a WebP's `ICCP` and an
## EXR's `chromaticities` and throws them away, so a photograph from a camera
## set to Adobe RGB or from a phone that writes Display P3 opened as sRGB, its
## greens duller than every other program showed them. These read the bytes
## before Godot does, each only as far as the picture's data, and hand the
## profile to `SaIccProfile`, which reads the primaries, the white and the curve
## or says why it cannot.
##
## The formats are the skeleton's: PNG, JPEG and WebP through
## [member SaImageFormat.embedded_profile], EXR through its `named_space`. A
## TIFF's profile is its tag 34675, which the image formats module's reader
## already holds and hands over the same way.
class_name SaEmbeddedProfile
extends RefCounted

## How far a profile's primaries and white may stand from a preset's, in CIE
## xy, and still open on that preset: s15Fixed16 and a Bradford step there and
## back move them by about 0.0001, and the presets nearest each other are
## further apart than this by a hundred times.
const PRESET_BOUND := 0.001

## The eight bytes every PNG starts with.
const PNG_SIGNATURE: Array[int] = [137, 80, 78, 71, 13, 10, 26, 10]
## An `APP2` segment of a profile starts with this and a zero, then the part's
## number and how many parts there are, counting from one.
const JPEG_ICC := "ICC_PROFILE"
const JPEG_ICC_HEADER := 14
## The most of an EXR's head read for its attributes. A header past it is one
## of thousands of attributes, and its gamut is read as unnamed.
const EXR_HEAD_BYTES := 1 << 20


## The space *space* stands for as the preset it is within [constant PRESET_BOUND]
## of, with that preset's curve, or *space* itself. A Display P3 profile opens
## on Display P3, which the Import Fit window lists by name.
static func as_preset(space: SaColorSpace) -> SaColorSpace:
    if space == null:
        return null
    for preset: SaColorSpace in SaColorSpace.presets():
        if preset.coordinates != SaColorSpace.Coordinates.RGB or not preset.transfer.matches(space.transfer):
            continue
        var near := preset.white.distance_to(space.white) <= PRESET_BOUND
        for i in 3:
            near = near and preset.primaries[i].distance_to(space.primaries[i]) <= PRESET_BOUND
        if near:
            return preset
    return space


## The profile in a PNG's `iCCP` chunk at *path*, inflated, or empty. Read chunk
## by chunk up to the first `IDAT`, where the specification puts it.
static func png(path: String) -> PackedByteArray:
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null or file.get_buffer(8) != PackedByteArray(PNG_SIGNATURE):
        return PackedByteArray()
    while file.get_position() + 8 <= file.get_length():
        var head := file.get_buffer(8)
        var length := _big(head, 0, 4)
        var kind := head.slice(4, 8).get_string_from_ascii()
        if kind == "IDAT" or kind == "IEND":
            break
        if kind != "iCCP":
            file.seek(file.get_position() + length + 4)
            continue
        var body := file.get_buffer(length)
        # The profile's name, a zero, the compression method, then zlib.
        var zero := body.find(0)
        if zero < 0 or zero + 2 > body.size() or body[zero + 1] != 0:
            return PackedByteArray()
        return _inflate(body.slice(zero + 2))
    return PackedByteArray()


## The profile in a JPEG's `APP2` segments at *path*, its parts put together in
## their numbered order, or empty when a part is missing. Read segment by
## segment up to the scan.
static func jpeg(path: String) -> PackedByteArray:
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        return PackedByteArray()
    var start := file.get_buffer(2)
    if start.size() < 2 or start[0] != 0xFF or start[1] != 0xD8:
        return PackedByteArray()
    var parts: Dictionary[int, PackedByteArray] = {}
    var expected := 0
    while file.get_position() + 4 <= file.get_length():
        var marker := file.get_buffer(2)
        if marker[0] != 0xFF:
            break
        if marker[1] == 0xFF:
            # A fill byte before the marker.
            file.seek(file.get_position() - 1)
            continue
        if marker[1] == 0xDA or marker[1] == 0xD9:
            break
        var length := _big(file.get_buffer(2), 0, 2)
        if length < 2:
            break
        var body := file.get_buffer(length - 2)
        if marker[1] == 0xE2 and body.size() > JPEG_ICC_HEADER and body.slice(0, 11).get_string_from_ascii() == JPEG_ICC:
            parts[body[12]] = body.slice(JPEG_ICC_HEADER)
            expected = body[13]
    var profile := PackedByteArray()
    for part in range(1, expected + 1):
        if not parts.has(part):
            return PackedByteArray()
        profile.append_array(parts[part])
    return profile


## The profile in a WebP's `ICCP` chunk at *path*, or empty. Its chunks follow
## the twelve bytes of the RIFF header, each padded to an even length.
static func webp(path: String) -> PackedByteArray:
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        return PackedByteArray()
    var head := file.get_buffer(12)
    if (
        head.size() < 12
        or head.slice(0, 4).get_string_from_ascii() != "RIFF"
        or head.slice(8, 12).get_string_from_ascii() != "WEBP"
    ):
        return PackedByteArray()
    while file.get_position() + 8 <= file.get_length():
        var chunk := file.get_buffer(8)
        var kind := chunk.slice(0, 4).get_string_from_ascii()
        var length := chunk.decode_u32(4)
        if kind == "ICCP":
            return file.get_buffer(length)
        if kind == "VP8 " or kind == "VP8L":
            break
        file.seek(file.get_position() + length + (length & 1))
    return PackedByteArray()


## The linear light in the gamut an EXR's `chromaticities` attribute names, as
## the preset it is where it is one, or null when the file names none. An EXR
## holds linear light whatever its gamut, so the curve is linear.
static func exr_space(path: String) -> SaColorSpace:
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        return null
    var head := file.get_buffer(mini(file.get_length(), EXR_HEAD_BYTES))
    var numbers := exr_chromaticities(head)
    if numbers.size() != 8:
        return null
    var primaries := PackedVector2Array(
        [Vector2(numbers[0], numbers[1]), Vector2(numbers[2], numbers[3]), Vector2(numbers[4], numbers[5])]
    )
    var white := Vector2(numbers[6], numbers[7])
    return as_preset(SaColorSpace.create(SaColorSpace.ID_CUSTOM, primaries, white, SaTransferFunction.linear()))


## The eight floats of the `chromaticities` attribute in an EXR's first bytes
## *head*, red, green, blue and white as x and y, or empty. The header is
## attributes of a name, a type, a little-endian size and the value, and ends
## at an empty name.
static func exr_chromaticities(head: PackedByteArray) -> PackedFloat32Array:
    if head.size() < 8 or head.slice(0, 4) != PackedByteArray([0x76, 0x2F, 0x31, 0x01]):
        return PackedFloat32Array()
    var at := 8
    while at < head.size() and head[at] != 0:
        var name_end := head.find(0, at)
        if name_end < 0:
            break
        var type_end := head.find(0, name_end + 1)
        if type_end < 0 or type_end + 5 > head.size():
            break
        var attribute := head.slice(at, name_end).get_string_from_ascii()
        var size := head.decode_s32(type_end + 1)
        var value := type_end + 5
        if size < 0 or value + size > head.size():
            break
        if attribute == "chromaticities" and size == 32:
            var numbers := PackedFloat32Array()
            for i in 8:
                numbers.append(head.decode_float(value + i * 4))
            return numbers
        at = value + size
    return PackedFloat32Array()


## A zlib stream inflated, whatever size it grows to, or empty when it is not
## one. Godot's deflate mode is zlib's own format, header and checksum.
static func _inflate(stream: PackedByteArray) -> PackedByteArray:
    if stream.is_empty():
        return PackedByteArray()
    return stream.decompress_dynamic(-1, FileAccess.COMPRESSION_DEFLATE)


static func _big(bytes: PackedByteArray, at: int, size: int) -> int:
    var value := 0
    for i in size:
        value = (value << 8) | bytes[at + i]
    return value
