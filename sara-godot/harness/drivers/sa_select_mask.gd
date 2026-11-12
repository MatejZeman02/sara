## The coverage a `select` step's `mask` key names, read from a file the size
## of the canvas and joined to the selection in the step's mode.
##
## A painter who held a mask had to trace its outline and send the polygon, and
## the outline of a strip one pixel wide encloses no pixel centre, so every thin
## shape was lost. Sending the mask itself leaves nothing to trace.
##
## A file is a NumPy `.npy` of shape `(h, w)` or `(h, w, 1)`, in C or Fortran
## order, float32, float64 or uint8, or a picture Godot opens, whose first
## channel is read. A float is coverage from 0 to 1 as it stands, and a byte is
## coverage in 255ths, so a soft mask gives a soft selection. Its own file beside the canvas driver
## because it is a file format and a merge, and the driver is the step.
extends RefCounted

## The undo step a mask records, as the history lists it.
const TITLE := "Select from Mask"

## The element types a `.npy` mask may hold, by NumPy's names.
const FLOAT32 := ["<f4", "=f4", "|f4"]
const FLOAT64 := ["<f8", "=f8", "|f8"]
const BYTES := ["|u1", "<u1", "=u1"]

## The `.npy` format the door's pixels already cross in, for its magic.
const Npy := preload("res://harness/sa_npy.gd")


## The coverage *spec*'s `mask` names as an `FORMAT_RF` image of *size*, or a
## String saying why there is none. A relative name is read from *folder*, the
## run's folder, as `write_pixels` reads one, and a missing file says both.
static func read(spec: Dictionary, size: Vector2i, folder: String) -> Variant:
    var name := String(spec["mask"])
    if name.is_empty():
        return "a mask names the file it reads"
    var path := name if name.is_absolute_path() else folder.path_join(name)
    if not FileAccess.file_exists(path):
        return (
            "%s is not there, and the run's folder, which a relative name is read from, is %s"
            % [ProjectSettings.globalize_path(path), ProjectSettings.globalize_path(folder)]
        )
    var loaded: Variant = _npy(path) if path.get_extension().to_lower() == "npy" else _picture(path)
    if loaded is String:
        return loaded
    var image: Image = loaded
    if image.get_size() != size:
        return (
            "the mask %s is %d by %d and the canvas is %d by %d, so nothing was selected"
            % [ProjectSettings.globalize_path(path), image.get_width(), image.get_height(), size.x, size.y]
        )
    return image


## Joins *image*'s coverage to *selection* in *mode*: a fresh chunk for each grid
## position where the mask holds something, uploaded once, and none where it is
## 0 throughout, through the merge the wand and a colour range share. Records
## nothing, so the caller runs it inside `SaSelection.change`.
static func merge(selection: SaSelection, image: Image, mode: int) -> void:
    var edge := selection.make_chunk().pixel_size()
    var region := {}
    var blank := PackedByteArray()
    blank.resize(edge * edge * 4)
    for gy: int in ceili(float(image.get_height()) / edge):
        for gx: int in ceili(float(image.get_width()) / edge):
            var tile := Image.create_empty(edge, edge, false, Image.FORMAT_RF)
            tile.blit_rect(image, Rect2i(gx * edge, gy * edge, edge, edge), Vector2i.ZERO)
            var data := tile.get_data()
            if data == blank:
                continue
            var chunk := selection.make_chunk()
            var field := chunk.field(SaSelection.FIELD)
            field.rd.texture_update(field.rid, 0, data)
            region[Vector2i(gx, gy)] = chunk
    selection.merge_region(region, mode)


## A `.npy` of one channel as an `FORMAT_RF` image, or why it is not one.
static func _npy(path: String) -> Variant:
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        return "%s could not be opened: %s" % [path, error_string(FileAccess.get_open_error())]
    var size := file.get_length()
    var bytes := file.get_buffer(mini(size, 12))
    if bytes.size() < 10 or bytes.slice(0, 6) != PackedByteArray(Npy.MAGIC):
        return "%s is not a .npy file" % path
    var preamble := 10 if bytes[6] == 1 else 12
    if bytes.size() < preamble:
        return "%s ends inside its header" % path
    var length := bytes.decode_u16(8) if bytes[6] == 1 else bytes.decode_u32(8)
    file.seek(preamble)
    var text := file.get_buffer(length).get_string_from_ascii()
    var start := preamble + length
    var found := RegEx.create_from_string("'descr':\\s*'([^']*)'").search(text)
    var descr := found.get_string(1) if found != null else "no dtype"
    var width_of := 0
    if descr in FLOAT32:
        width_of = 4
    elif descr in FLOAT64:
        width_of = 8
    elif descr in BYTES:
        width_of = 1
    if width_of == 0:
        return "%s holds %s, and a mask takes float32, float64 or uint8" % [path, descr]
    var fortran := RegEx.create_from_string("'fortran_order':\\s*True").search(text) != null
    var shape := RegEx.create_from_string("'shape':\\s*\\(\\s*(\\d+)\\s*,\\s*(\\d+)\\s*(?:,\\s*1\\s*)?,?\\s*\\)").search(text)
    if shape == null:
        return "%s is not an array of shape (h, w) or (h, w, 1), one channel" % path
    var height := int(shape.get_string(1))
    var width := int(shape.get_string(2))
    if width == 0 or height == 0:
        return "%s is an empty array" % path
    if size - start != width * height * width_of:
        return "%s holds %d bytes of body where (%d, %d) is %d" % [path, size - start, height, width, width * height * width_of]
    file.seek(start)
    var body := file.get_buffer(size - start)
    if width_of == 8:
        # No packed array converts to another, so the doubles go through an
        # Array, which float32 is spared.
        body = PackedFloat32Array(Array(body.to_float64_array())).to_byte_array()
    # Fortran order is the array's columns one after another, the image of its
    # transpose, which NumPy saves for an array broadcast along a row.
    var across := height if fortran else width
    var down := width if fortran else height
    var image := Image.create_from_data(across, down, false, Image.FORMAT_R8 if width_of == 1 else Image.FORMAT_RF, body)
    image.convert(Image.FORMAT_RF)
    if fortran:
        image.rotate_90(CLOCKWISE)
        image.flip_x()
    return image


## A picture's first channel as an `FORMAT_RF` image, or why there is none.
static func _picture(path: String) -> Variant:
    var image := Image.load_from_file(path)
    if image == null or image.is_empty():
        return "%s is neither a .npy array nor a picture Sara can open" % path
    if image.is_compressed():
        image.decompress()
    image.convert(Image.FORMAT_RF)
    return image
