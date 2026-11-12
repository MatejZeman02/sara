## What an export writes to name the document's gamut, and the pixels it
## names.
##
## The gamut is what a picked colour means, so an
## export writes the picker's triple, the document's gamut through sRGB's curve,
## and names that gamut the way each format does. A PNG gets a `cICP` chunk, the
## four numbers a current reader takes, and an `iCCP` chunk carrying the matching
## profile for every reader before it. A JPEG gets the profile in APP2 and a TIFF
## in tag 34675. An EXR names nothing, so it is written in linear sRGB, which is
## what every reader takes an unlabelled one to be.
##
## Written unconverted and unlabelled, the default document, which stores
## Oklab, would export its L, a and b as red, green and blue, and a P3
## document's red would arrive anywhere else as sRGB's.
##
## The profiles are `assets/icc/`, written by `scripts/gen_icc_profiles.py` from
## the primaries `SaGamut` declares. A gamut Sara ships no profile for, ACES AP1
## or a custom set, is written unlabelled rather than under a wrong name, and so
## is a document that never declared a space.
##
## **The pixels are handled a chunk cell at a time**, rather than the whole
## output copied into a second float texture of the document's size and one
## dispatch run over all of it, which hard rule 2 forbids: rule 1's
## allowance names a readback, and it says nothing about a dispatch. The grid is
## `SaChunk.SIZE` document pixels, the one the compositor writes the output in,
## and [method cells_of] is the whole of it.
class_name SaExportGamut
extends RefCounted

const PNG_SIGNATURE: Array[int] = [137, 80, 78, 71, 13, 10, 26, 10]

## The only length an `IHDR` may have, which is what makes the offset below a
## constant rather than a thing read out of each file.
const PNG_IHDR_LENGTH: int = 13

## Where the pixels start in a PNG: the signature, then `IHDR`'s length, type,
## thirteen bytes and CRC. `cICP` and `iCCP` both have to come before any palette
## or pixel data, and straight after the header is before both.
const PNG_AFTER_IHDR: int = 8 + 4 + 4 + PNG_IHDR_LENGTH + 4

## The chunks that say what a PNG's colours are some other way, dropped when the
## gamut is named so nothing in the file contradicts `cICP` and `iCCP`.
const SUPERSEDED_PNG_CHUNKS: Array[String] = ["sRGB", "gAMA", "cHRM", "iCCP", "cICP"]

## ITU-T H.273's colour primaries codes, which is what a `cICP` chunk carries.
const CICP_PRIMARIES := {SaGamut.ID_SRGB: 1, SaGamut.ID_DISPLAY_P3: 12, SaGamut.ID_REC2020: 9}
## H.273's code for the sRGB curve, which every export here is written through.
const CICP_TRANSFER_SRGB: int = 13

## The profile file for each gamut Sara ships one for.
const PROFILE_FILES := {
    SaGamut.ID_SRGB: "srgb.icc",
    SaGamut.ID_DISPLAY_P3: "display_p3.icc",
    SaGamut.ID_REC2020: "rec2020.icc",
}
## By `res://`, which an exported build carries because `export_presets.cfg`
## includes `*.icc`.
const PROFILE_DIR := "res://assets/icc"

## The marker and the identifier ICC.1 Annex B puts in front of a profile in a
## JPEG.
const JPEG_APP0: int = 0xE0
const JPEG_APP2: int = 0xE2
const JPEG_ICC_IDENTIFIER := "ICC_PROFILE"

## How much of a PNG is read looking for `cICP`. It sits before the pixels, after
## the header and the profile, so the head of the file always holds it.
const PNG_HEAD_BYTES: int = 65536

## The four kernels the cell walk puts a scratch through, by the names the
## shader index knows them by. Named here so a cell and the conversion cannot
## be told to ask for two different ones.
const CONVERT_KERNEL: String = "convert_color_space"
const TONEMAP_KERNEL: String = "tonemap_rolloff"
const MAPPING_KERNEL: String = "map_into_gamut"
const ROUND_KERNEL: String = "round_to_bytes"

## Chunk cells the last export walked. Reset at the start of every
## [method encoded_image], [method linear_image] and [method byte_image], and
## bounded by the cell count of the picture they were handed.
##
## A public counter for the reason `SaMergedSnapshot.chunk_copies` is one: the
## bound is a claim about how narrowly this path works, and a count is what a
## test can hold it to rather than trusting that no copy was of the whole
## canvas.
static var cells_visited: int = 0

## Bytes of VRAM the largest texture the last cell walk allocated holds, which is
## the scratch it copies each cell into.
##
## Read off that texture's own `bytes` rather than computed here, so it is the
## real allocation and not this file's arithmetic. What it guards against is a
## second float texture the size of the whole document, so the test holds this
## to a cell's worth.
static var peak_scratch_bytes: int = 0

static var _crc_table := PackedInt64Array()


## The chunk grid the export path works in: every cell of a dense picture, one
## rectangle each, so no pass or copy here is ever the whole canvas (hard rule 2).
##
## The output texture is one picture at the document's pitch rather than a
## layer's sparse chunks, so the grid is the one the compositor writes it in and
## the cell is `SaChunk.SIZE` document pixels, exactly as `SaMergedSnapshot` reads
## it. A picture smaller than one cell is one cell the size of the picture.
static func cells_of(size: Vector2i) -> Array[Rect2i]:
    var cells: Array[Rect2i] = []
    var pitch := SaChunk.SIZE
    for gy in range(0, size.y, pitch):
        for gx in range(0, size.x, pitch):
            cells.append(Rect2i(Vector2i(gx, gy), Vector2i(pitch, pitch)).intersection(Rect2i(Vector2i.ZERO, size)))
    return cells


## The space an export writes *space*'s pixels in: its primaries and its white,
## RGB, through sRGB's curve. What `SaColorSpace.to_display` hands the picker,
## so a painted `1, 0, 0` leaves as `255, 0, 0` in a file named for its gamut.
static func export_space(space: SaColorSpace) -> SaColorSpace:
    var source := space if space != null else SaColorSpace.srgb()
    return SaColorSpace.create(SaColorSpace.ID_CUSTOM, source.primaries, source.white, SaTransferFunction.srgb(), source.depth)


## The gamut an export of *space* is named for, or null when it is named for
## none: no document, or one that never declared a space, which a label would
## claim it had.
static func gamut_named(space: SaColorSpace) -> SaGamut:
    if space == null or not space.is_specified:
        return null
    var gamut := space.gamut()
    return gamut if PROFILE_FILES.has(gamut.id) else null


## *texture*, holding *space*'s stored numbers, as a float image in
## [method export_space].
##
## Converted through the kernel Image > Convert uses, the way the recorder's
## frame is, and read back as it stands when the two already agree and no
## *tonemap* is asked for, which is every RGB document on the sRGB curve and a
## null *space*. The conversion runs over one chunk cell at a time and never
## over the picture, so the export path makes no copy of the whole output and
## dispatches over no rectangle bigger than a chunk (hard rule 2, d26).
##
## *tonemap* is knee, desaturation and blend white for the highlight rolloff,
## or empty to skip it and clip on narrowing.
## Passing it forces the cell walk even when the gamut is already the
## target's, because the rolloff still has to run on an sRGB document's own
## numbers.
##
## *gamut_mapping* is a key of `SaGamutMapping.MODES`. Oklab forces the cell
## walk the same way and runs the mapping kernel after the rolloff. The caller
## passes it only for a file that narrows, and `SaGamutMapping.for_export` is
## how it decides: this file is core and reads no preference.
##
## *relief* is the lit relief a flat export bakes, run first on
## every cell, or null to write the colour alone. Given one, the walk runs even
## where nothing else would, because the light has to reach the cells.
static func encoded_image(
    texture: SaTexture,
    space: SaColorSpace,
    tonemap: PackedFloat32Array = PackedFloat32Array(),
    gamut_mapping: String = SaGamutMapping.CLIP,
    relief: SaExportRelief = null
) -> Image:
    if texture == null:
        push_error("SaExportGamut.encoded_image: texture is null")
        return null
    cells_visited = 0
    peak_scratch_bytes = 0
    var target := export_space(space)
    var mapped := SaGamutMapping.export_maps(gamut_mapping, false)
    if relief == null and tonemap.is_empty() and not mapped and (space == null or space.matches(target)):
        return _float_image(texture)
    var convert_params := PackedFloat32Array()
    if space != null and not space.matches(target):
        convert_params = space.to_conversion_push_constant(target)
    return _through_cells(texture, convert_params, null, tonemap, mapped, relief)


## The space an EXR holds whatever *space* stores: Rec. 709's primaries, D65
## and no curve, at *space*'s own depth so a linear sRGB document already
## matches it.
##
## Linear sRGB because an EXR names no gamut and every reader opens an
## unlabelled one that way, Blender and Nuke as well as `SaImageImport.space_for`.
static func linear_space(space: SaColorSpace) -> SaColorSpace:
    var linear := SaColorSpace.linear_srgb()
    return linear.with_depth(space.depth) if space != null else linear


## *texture*, holding *space*'s stored numbers, as a float image in [method
## linear_space], which is what an EXR is written from.
##
## The sibling of [method encoded_image] for the file that keeps its range: the
## same cell walk and the same conversion kernel, and nothing after it. No
## rolloff, no gamut mapping and no rounding, so a negative or a value above one
## leaves as it was and a P3 red lands outside sRGB's cube rather than on its
## edge. A null *space* converts nothing and writes the stored numbers, which is
## the bit-exact path `core/composite/tests/test_no_clamp.gd` holds.
##
## *relief* is [method encoded_image]'s, lit first on the stored numbers. With
## neither a conversion nor a relief to run, the texture is read back as it
## stands and no cell is walked.
static func linear_image(texture: SaTexture, space: SaColorSpace, relief: SaExportRelief = null) -> Image:
    if texture == null:
        push_error("SaExportGamut.linear_image: texture is null")
        return null
    cells_visited = 0
    peak_scratch_bytes = 0
    var convert_params := PackedFloat32Array()
    var target := linear_space(space)
    if space != null and not space.matches(target):
        convert_params = space.to_conversion_push_constant(target)
    if relief == null and convert_params.is_empty():
        return _float_image(texture)
    return _through_cells(texture, convert_params, null, PackedFloat32Array(), false, relief)


## *texture* as eight bits a channel, each rounded to the nearest step, with
## the stored numbers left as they are.
##
## Godot's `Image.convert` to `FORMAT_RGBA8` truncates, so every float landed on
## the step below it: a stored `0.99999988` left an export as `254` and a mid
## grey of `0.5` as `127`. Half a step is added on the GPU first, which turns the
## truncation into rounding, and that runs cell by cell because this is on every
## PNG and JPEG export an sRGB document's included.
static func byte_image(texture: SaTexture) -> Image:
    if texture == null:
        push_error("SaExportGamut.byte_image: texture is null")
        return null
    cells_visited = 0
    peak_scratch_bytes = 0
    return narrowed(_through_cells(texture, PackedFloat32Array(), Rounding.new(false, Vector2i.ZERO)))


## The same eight bits, with *texture*'s stored numbers read as *space* and
## written as *target* on the way.
##
## An export names its target through [method export_space], so a painted
## `1, 0, 0` leaves as `255, 0, 0` in a file named for its gamut. The recorder
## names plain sRGB instead, because a recorded frame is what the view shader
## would have drawn rather than what a file format writes. A null *target*, or
## one the stored numbers are already in, converts nothing.
##
## *tonemap* is the same knee, desaturation and blend white [method
## encoded_image] takes, run on the same cell after the gamut conversion and
## before the rounding this method adds, so a highlight is rolled off in the
## document's own numbers rather than in the byte grid it narrows to.
## *gamut_mapping* is [method encoded_image]'s, run between the two, and so
## is *relief*, run first.
##
## *dither* moves each texel's rounding by up to half a step either way, from
## a fixed pattern keyed to where the texel is in the picture, which is
## *texture*'s own corner plus *origin*: a chunk an OpenRaster layer is cut
## from names where it sits. Off, the bytes are the plain rounding's, and
## `round_to_bytes.gmacs` says how.
static func encoded_byte_image(
    texture: SaTexture,
    space: SaColorSpace,
    target: SaColorSpace = null,
    tonemap: PackedFloat32Array = PackedFloat32Array(),
    gamut_mapping: String = SaGamutMapping.CLIP,
    relief: SaExportRelief = null,
    dither: bool = false,
    origin: Vector2i = Vector2i.ZERO
) -> Image:
    return narrowed(rounded_image(texture, space, target, tonemap, gamut_mapping, relief, dither, origin))


## The picture [method encoded_byte_image] answers before it is narrowed: a
## float image whose every texel already sits on an eight-bit step, read back
## on this thread, so the narrowing can run on another one. The arguments are
## [method encoded_byte_image]'s.
static func rounded_image(
    texture: SaTexture,
    space: SaColorSpace,
    target: SaColorSpace = null,
    tonemap: PackedFloat32Array = PackedFloat32Array(),
    gamut_mapping: String = SaGamutMapping.CLIP,
    relief: SaExportRelief = null,
    dither: bool = false,
    origin: Vector2i = Vector2i.ZERO
) -> Image:
    if texture == null:
        push_error("SaExportGamut.encoded_byte_image: texture is null")
        return null
    cells_visited = 0
    peak_scratch_bytes = 0
    var into := target if target != null else export_space(space)
    var params := PackedFloat32Array()
    if space != null and not space.matches(into):
        params = space.to_conversion_push_constant(into)
    var mapped := SaGamutMapping.export_maps(gamut_mapping, false)
    var rounding := Rounding.new(dither, origin)
    return _through_cells(texture, params, rounding, tonemap, mapped, relief)


## The cells of *texture*, each one copied into a scratch the size of a cell and
## put through the conversion *convert_params* names, the rolloff, the gamut
## mapping and then the rounding kernel, read back into one float image. A
## *relief* lights the cell before any of them, on the stored numbers.
##
## **Why not the picture at once.** A copy of the whole output is a second float
## texture the size of the document in VRAM, and one dispatch over it is a
## compute pass over the whole canvas, which hard rule 2 forbids: the readback is
## the half of the export rule 1 permits, and it permits nothing about a
## dispatch. Walked a cell at a time, the VRAM this path holds is one cell
## however large the document is, and every rectangle it copies or dispatches
## over is a cell's.
##
## **One scratch, reused.** The kernel writes the whole cell, so the next copy
## overwrites what the last one left and nothing has to be cleared. Allocating
## per cell instead would take and give back a texture for every cell, and
## `SaTexture` bumps its epoch on both, which drops every cached uniform set for
## no gain.
##
## The readbacks are one per cell rather than one of the picture, which is the
## price. An empty *convert_params* means the conversion is skipped, an empty
## *tonemap* means the rolloff is skipped, a false *mapping* means a colour
## outside the cube is left for the narrowing to clip, a null *rounding* means
## the float picture is wanted and nothing is rounded, and there is no way to
## skip the copy: the rounding has to write somewhere, and a canvas's own output is
## never written to.
static func _through_cells(
    texture: SaTexture,
    convert_params: PackedFloat32Array,
    rounding: Rounding,
    tonemap: PackedFloat32Array = PackedFloat32Array(),
    mapping: bool = false,
    relief: SaExportRelief = null
) -> Image:
    var rd := GlobalShaderCompiler.get_rd()
    if rd == null or not texture.rid.is_valid():
        push_error("SaExportGamut: no RenderingDevice or no texture to read")
        return null
    var cells := cells_of(texture.size)
    if cells.is_empty():
        return null
    cells_visited = cells.size()
    var image := Image.create_empty(texture.size.x, texture.size.y, false, Image.FORMAT_RGBAF)
    # A cell of the pitch, whatever the edge cells are: the last column and the
    # last row are the only ones short of it, and a scratch that holds the
    # largest one holds every one.
    var scratch := SaTexture.new(Vector2i(SaChunk.SIZE, SaChunk.SIZE), texture.format)
    peak_scratch_bytes = scratch.bytes
    var converter: SaCompute = SaCompute.new(CONVERT_KERNEL) if not convert_params.is_empty() else null
    var roller: SaCompute = SaCompute.new(TONEMAP_KERNEL) if not tonemap.is_empty() else null
    var mapper: SaCompute = SaCompute.new(MAPPING_KERNEL) if mapping else null
    var rounder: SaCompute = SaCompute.new(ROUND_KERNEL) if rounding != null else null
    for cell: Rect2i in cells:
        var origin := Vector3(cell.position.x, cell.position.y, 0)
        rd.texture_copy(texture.rid, scratch.rid, origin, Vector3.ZERO, Vector3(cell.size.x, cell.size.y, 1), 0, 0, 0, 0)
        # The light first, on the stored numbers, the way the view lights them
        # before its display transform.
        if relief != null:
            relief.light_cell(scratch, cell)
        _run_cell(converter, CONVERT_KERNEL, scratch, cell, convert_params)
        _run_cell(roller, TONEMAP_KERNEL, scratch, cell, tonemap)
        # After the rolloff, which has already brought in what it touched, and
        # before the rounding, whose half step would push a channel at the
        # cube's edge out of it.
        _run_cell(mapper, MAPPING_KERNEL, scratch, cell, PackedFloat32Array())
        if rounding != null:
            _run_cell(rounder, ROUND_KERNEL, scratch, cell, rounding.params(cell))
        var read := _float_image(scratch)
        if read == null:
            continue
        # The part of the scratch this cell filled, copied into place. The rest
        # is the previous cell's pixels and is blitted nowhere.
        image.blit_rect(read, Rect2i(Vector2i.ZERO, cell.size), cell.position)
    return image


## One kernel over one cell's own rectangle, or nothing when *compute* is null.
##
## The dispatch covers the cell exactly, one cell of a scratch allocated at the
## pitch, so `global_id` is a pixel of the cell and neither kernel reads outside
## it.
static func _run_cell(compute: SaCompute, kernel: String, scratch: SaTexture, cell: Rect2i, params: PackedFloat32Array) -> void:
    if compute == null:
        return
    compute.use_storage_format(scratch.format)
    compute.set_texture(0, scratch.rid)
    # The mapping kernel declares no params, so it is handed no block.
    if not params.is_empty():
        compute.set_push_constant_float_array(params)
    compute.dispatch_kernel(kernel, SaCompute.groups_for(cell.size.x), SaCompute.groups_for(cell.size.y), 1)


## *image* at eight bits a channel, or null when there is none. The one
## narrowing PNG and JPEG share, safe on a worker thread.
static func narrowed(image: Image) -> Image:
    if image == null:
        return null
    image.convert(Image.FORMAT_RGBA8)
    return image


## How a cell walk that narrows to bytes rounds: always to the nearest step,
## and with the dither when it was asked for, keyed to where the texture sits
## in the picture.
class Rounding:
    extends RefCounted

    ## One step in 255, the dither's whole span, half of it either way.
    const STEP: float = 1.0 / 255.0

    var dither: bool
    ## Where the texture's corner is in the picture, so a chunk an OpenRaster
    ## layer is cut from takes the pattern of its place.
    var origin: Vector2i

    func _init(dithered: bool, at: Vector2i) -> void:
        dither = dithered
        origin = at

    ## The kernel's four floats for *cell*: half a step, the dither's span or
    ## nought, and the cell's corner in the picture.
    func params(cell: Rect2i) -> PackedFloat32Array:
        var corner := origin + cell.position
        return PackedFloat32Array([0.5 * STEP, STEP if dither else 0.0, corner.x, corner.y])


## Knee, desaturation and blend white for [method encoded_image] and [method
## encoded_byte_image], padded to the four floats the packer demands, or empty
## when *enabled* is false, which is what turns the rolloff off.
static func tonemap_params(enabled: bool, knee: float, desaturation: float, blend_white: float) -> PackedFloat32Array:
    if not enabled:
        return PackedFloat32Array()
    return PackedFloat32Array([knee, desaturation, blend_white, 0.0])


## The float readback `SaExport` owns, reached through its autoload the way the
## recorder reaches it.
static func _float_image(texture: SaTexture) -> Image:
    @warning_ignore("static_called_on_instance")
    var image := SaExport.get_texture_image_float(texture)
    return image


## The profile naming *gamut*, or empty for a gamut Sara ships none for.
static func profile_for(gamut: SaGamut) -> PackedByteArray:
    if gamut == null or not PROFILE_FILES.has(gamut.id):
        return PackedByteArray()
    var file_name: String = PROFILE_FILES[gamut.id]
    return FileAccess.get_file_as_bytes(PROFILE_DIR.path_join(file_name))


## *png*, a whole file as the encoder wrote it, with *gamut* named in it, or
## *png* untouched when *gamut* is null or the bytes are not a PNG.
##
## Two encoders hand this their bytes, Godot's at eight bits and
## `SaPng16Writer` at sixteen, and the splice holds for both because both write
## the one shape PNG allows: the signature, then `IHDR` first at thirteen
## bytes. The sixteen-bit file was proved through this path rather than
## assumed, and the length is checked here as well as the type, so a
## header of any other size is left unlabelled rather than cut in half.
static func png_with_gamut(png: PackedByteArray, gamut: SaGamut) -> PackedByteArray:
    if gamut == null or not _header_is_plain(png):
        return png
    var named := PackedByteArray()
    named.append_array(_png_chunk("cICP", PackedByteArray([CICP_PRIMARIES[gamut.id], CICP_TRANSFER_SRGB, 0, 1])))
    # The profile's name, a zero, compression method zero and a zlib stream,
    # which is what `COMPRESSION_DEFLATE` writes: Godot's Deflate mode keeps
    # zlib's own header and checksum.
    var body := gamut.display_name.to_ascii_buffer()
    body.append(0)
    body.append(0)
    body.append_array(profile_for(gamut).compress(FileAccess.COMPRESSION_DEFLATE))
    named.append_array(_png_chunk("iCCP", body))
    var out := png.slice(0, PNG_AFTER_IHDR)
    out.append_array(named)
    # Godot's encoder writes an sRGB chunk into every PNG, and a reader finding
    # it beside iCCP may believe either one, so whatever the two new chunks
    # supersede goes and every other chunk is copied as it was.
    var at := PNG_AFTER_IHDR
    while at + 12 <= png.size():
        var end := at + 12 + _u32_be_at(png, at)
        if not SUPERSEDED_PNG_CHUNKS.has(png.slice(at + 4, at + 8).get_string_from_ascii()):
            out.append_array(png.slice(at, end))
        at = end
    return out


## *png* with *metadata* in one `iTXt` chunk an entry, straight after the
## header, or *png* untouched when *metadata* is null or the bytes are not a PNG
## with the plain header [method png_with_gamut] also asks for.
##
## `iTXt` rather than `tEXt`, because a painter's name is not always Latin-1
## and `iTXt` is the one text chunk that holds UTF-8. Uncompressed, with no
## language tag and no translated keyword, which is the shape every reader
## takes. The chunk may go anywhere between the header and the end, so the
## place the gamut chunks are spliced into serves, whichever splice runs first.
static func png_with_text(png: PackedByteArray, metadata: SaExportMetadata) -> PackedByteArray:
    if metadata == null or not _header_is_plain(png):
        return png
    var out := png.slice(0, PNG_AFTER_IHDR)
    for entry: PackedStringArray in metadata.png_entries():
        var body := entry[0].to_ascii_buffer()
        # The keyword's end, then the compression flag and method, both zero
        # for plain text, then the empty language tag and translated keyword.
        body.append_array(PackedByteArray([0, 0, 0, 0, 0]))
        body.append_array(entry[1].to_utf8_buffer())
        out.append_array(_png_chunk("iTXt", body))
    out.append_array(png.slice(PNG_AFTER_IHDR))
    return out


## Whether *png* starts with the signature and a thirteen-byte `IHDR`, the one
## shape both encoders write and the one a splice after the header can trust.
static func _header_is_plain(png: PackedByteArray) -> bool:
    if png.size() < PNG_AFTER_IHDR or png.slice(0, 8) != PackedByteArray(PNG_SIGNATURE):
        return false
    return png.slice(12, 16).get_string_from_ascii() == "IHDR" and _u32_be_at(png, 8) == PNG_IHDR_LENGTH


## *jpg* with *gamut*'s profile in one APP2 segment, after the JFIF header when
## the encoder wrote one, since a reader may want APP0 first. One segment holds
## the whole profile, which ICC.1 caps at 65519 bytes a segment and which Sara's
## are well under.
static func jpg_with_gamut(jpg: PackedByteArray, gamut: SaGamut) -> PackedByteArray:
    var profile := profile_for(gamut)
    if profile.is_empty() or jpg.size() < 6 or jpg[0] != 0xFF or jpg[1] != 0xD8:
        return jpg
    var at := 2
    # A segment's length counts its own two bytes and not its marker's, so APP0
    # ends its marker and that length after the start-of-image marker. One byte
    # pair short put the profile inside the JFIF header and no reader opened it.
    if jpg[2] == 0xFF and jpg[3] == JPEG_APP0:
        at = 2 + 2 + ((jpg[4] << 8) | jpg[5])
    var body := JPEG_ICC_IDENTIFIER.to_ascii_buffer()
    body.append(0)
    # This segment's number and how many there are, one of one.
    body.append(1)
    body.append(1)
    body.append_array(profile)
    var segment := PackedByteArray([0xFF, JPEG_APP2])
    _put_u16_be(segment, body.size() + 2)
    segment.append_array(body)
    var out := jpg.slice(0, at)
    out.append_array(segment)
    out.append_array(jpg.slice(at))
    return out


## The colour primaries code the `cICP` chunk of the PNG at *path* carries, or -1
## when it has none, names another curve, or is not a PNG. The half of this class
## an import reads, so a picture Sara wrote opens as the gamut it was written in.
static func png_primaries_at(path: String) -> int:
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        return -1
    var head := file.get_buffer(mini(file.get_length(), PNG_HEAD_BYTES))
    file.close()
    if head.size() < 8 or head.slice(0, 8) != PackedByteArray(PNG_SIGNATURE):
        return -1
    var at := 8
    while at + 8 <= head.size():
        var length := (head[at] << 24) | (head[at + 1] << 16) | (head[at + 2] << 8) | head[at + 3]
        var type := head.slice(at + 4, at + 8).get_string_from_ascii()
        if type == "IDAT" or type == "IEND":
            return -1
        if type == "cICP" and length == 4 and at + 12 <= head.size():
            var transfer_ok := head[at + 9] == CICP_TRANSFER_SRGB and head[at + 10] == 0
            return head[at + 8] if transfer_ok else -1
        at += 12 + length
    return -1


## The space a picture named with primaries *code* was written in, or null for a
## code this knows no gamut for.
static func space_for_primaries(code: int) -> SaColorSpace:
    for gamut_id: StringName in CICP_PRIMARIES:
        if CICP_PRIMARIES[gamut_id] == code:
            return SaColorSpace.srgb().with_gamut(SaGamut.from_id(gamut_id))
    return null


## The CRC a PNG chunk ends with, over its type and its data.
static func crc32(bytes: PackedByteArray) -> int:
    if _crc_table.is_empty():
        _crc_table.resize(256)
        for n in 256:
            var c := n
            for k in 8:
                c = (0xEDB88320 ^ (c >> 1)) if (c & 1) != 0 else (c >> 1)
            _crc_table[n] = c
    var crc := 0xFFFFFFFF
    for b in bytes:
        crc = _crc_table[(crc ^ b) & 0xFF] ^ (crc >> 8)
    return crc ^ 0xFFFFFFFF


static func _png_chunk(type: String, data: PackedByteArray) -> PackedByteArray:
    var typed := type.to_ascii_buffer()
    typed.append_array(data)
    var out := PackedByteArray()
    _put_u32_be(out, data.size())
    out.append_array(typed)
    _put_u32_be(out, crc32(typed))
    return out


static func _u32_be_at(bytes: PackedByteArray, at: int) -> int:
    return (bytes[at] << 24) | (bytes[at + 1] << 16) | (bytes[at + 2] << 8) | bytes[at + 3]


static func _put_u16_be(into: PackedByteArray, value: int) -> void:
    into.append((value >> 8) & 0xFF)
    into.append(value & 0xFF)


static func _put_u32_be(into: PackedByteArray, value: int) -> void:
    into.append((value >> 24) & 0xFF)
    into.append((value >> 16) & 0xFF)
    into.append((value >> 8) & 0xFF)
    into.append(value & 0xFF)
