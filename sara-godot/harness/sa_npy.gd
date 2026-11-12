## The `.npy` format, version 1.0, as far as an array of shape `(h, w, 4)` in C
## order needs it, float32 or the small form's uint8: the magic, a header that
## is a Python dict literal padded so the body starts on a 64 byte boundary, and
## the body. NumPy's own `np.load` reads what this writes, and `np.save` writes
## what this reads.
##
## Its own file beside the step because it is a file format and not a step,
## and the step's folder is one a reader takes in whole.
extends RefCounted

const MAGIC := [0x93, 0x4E, 0x55, 0x4D, 0x50, 0x59]

## NumPy's names for the two element types a file here holds.
const FLOATS := "<f4"
const BYTES := "|u1"


## The magic, the version and the padded header for an array of *size* whose
## elements are *descr*.
static func header(size: Vector2i, descr: String = FLOATS) -> PackedByteArray:
    var text := "{'descr': '%s', 'fortran_order': False, 'shape': (%d, %d, 4), }" % [descr, size.y, size.x]
    # Ten bytes of preamble, the text and its newline make a multiple of 64.
    var padded := text + " ".repeat(63 - (10 + text.length()) % 64) + "\n"
    var out := PackedByteArray(MAGIC)
    out.append_array(PackedByteArray([1, 0, padded.length() & 0xFF, padded.length() >> 8]))
    out.append_array(padded.to_ascii_buffer())
    return out


## The file at *path* as an `RGBAF` image, or a String saying why it is not
## one: a missing file, another format, another dtype, another shape, or a
## body of the wrong length.
##
## The header is read first and the body in one read of its own, straight into
## the image's bytes. Reading the whole file and slicing the body off would copy
## it a second time, a cost every large write would pay.
static func read(path: String) -> Variant:
    if path.is_empty():
        return "a write names the .npy file it reads"
    if not FileAccess.file_exists(path):
        return "%s is not there" % path
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        return "%s could not be opened: %s" % [path, error_string(FileAccess.get_open_error())]
    var size := file.get_length()
    var bytes := file.get_buffer(mini(size, 12))
    if bytes.size() < 10 or bytes.slice(0, 6) != PackedByteArray(MAGIC):
        return "%s is not a .npy file" % path
    var major := bytes[6]
    var preamble := 10 if major == 1 else 12
    if bytes.size() < preamble:
        return "%s ends inside its header" % path
    var length := bytes.decode_u16(8) if major == 1 else bytes.decode_u32(8)
    var start := preamble + length
    if size < start:
        return "%s ends inside its header" % path
    file.seek(preamble)
    var text := file.get_buffer(length).get_string_from_ascii()
    var descr := RegEx.create_from_string("'descr':\\s*'([^']*)'").search(text)
    if descr == null or not descr.get_string(1) in ["<f4", "=f4", "|f4"]:
        return "%s holds %s, and a layer takes float32, '<f4'" % [path, descr.get_string(1) if descr != null else "no dtype"]
    if RegEx.create_from_string("'fortran_order':\\s*True").search(text) != null:
        return "%s is in Fortran order, and a layer takes C order" % path
    var shape := RegEx.create_from_string("'shape':\\s*\\(\\s*(\\d+)\\s*,\\s*(\\d+)\\s*,\\s*(\\d+)\\s*,?\\s*\\)").search(text)
    if shape == null or int(shape.get_string(3)) != 4:
        return "%s is not an array of shape (h, w, 4)" % path
    var height := int(shape.get_string(1))
    var width := int(shape.get_string(2))
    if size - start != width * height * 16:
        return "%s holds %d bytes of body where (%d, %d, 4) is %d" % [path, size - start, height, width, width * height * 16]
    if width == 0 or height == 0:
        return "%s is an empty array" % path
    return Image.create_from_data(width, height, false, Image.FORMAT_RGBAF, file.get_buffer(size - start))
