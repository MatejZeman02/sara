## Turns a brush tip file into a coverage mask, a lightness channel and the
## `r32g32f` texture both are uploaded into.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The greyscale mask rule is the one port left here, `libs/brush/kis_brush.cpp`
## of Krita 5.2.13. **Its copyright lines are in
## [`PROVENANCE.md`](PROVENANCE.md)**, beside it in the door, verbatim and
## named against this file. The row it belongs to is the characteristic
## size's, which lives in `sa_dab_geometry.gd` and is Sara's own.
##
## **The two readers below are written from the two file formats**. A PNG is a
## chunked container whose ancillary chunks Godot's `Image` discards, and a GBR is
## a big-endian header followed by its bytes: both are documented formats, and
## what each reader does is read one.
##
## **A tip has no size of its own**. A reader that gave a predefined tip a size,
## `max(width, height)` times a scale, would put a 32 by 32 GBR and a 512 by 512
## PNG at different widths from one Size row. Sara's Size row is the diameter and
## the dab kernel samples this mask at the dab's own inverse transform, so nothing
## here reads the tip's pixel dimensions as a size.
##
## Loading is CPU work done once, outside any stroke, so it breaks hard rule 1: it is not
## a readback of the canvas, it is a file becoming a texture before anything
## paints.
##
## **The mask is coverage, 0 to 1, and one texture serves every size.** The dab
## kernel samples it at the dab's inverse transform, so nothing here knows how
## large the brush is and no mipmap pyramid is built.
##
## **Two formats, and a named refusal for the rest.** `.png` and `.gbr` load.
## A `.gih` is a pipe, read by the pipe reader through Load Tip, and an `.abr`
## is a collection Load Tip opens in a chooser, so each is refused by name here
## rather than returning an empty mask. A third format is a branch in `load_from`.
class_name SaTipImage
extends RefCounted

const SaBrushTipScript = preload("res://core/api/tip/sa_brush_tip.gd")

## The spacing a tip gets when its file does not say: a version 1 GBR, whose
## header has no spacing field at all, and a PNG with no `brush_spacing` key.
##
## **Neither format states a default, so this is a choice and not a reading.** A
## quarter of the tip's size is what the tools that write these files put in the
## field when they write one, and it is the number every tip Sara has loaded so
## far was spaced at, so it stays put: changing it would move every stroke made
## with a tip whose file is silent. Zero would be the wrong kind of default, being
## a brush that stamps once per pixel of every stroke.
const SPACING_WHEN_UNSTATED: float = 0.25

## The channel spread above which a picture counts as carrying colour rather
## than as a grey mask.
##
## **A pixel read, not a header field**, because neither format states it: a
## `.png` and a `.gbr` are containers for both a grey tip and a colour one, and
## the only thing that knows which was drawn is the pixels. Four parts in a
## thousand is a little over one step of an eight-bit channel, so a picture
## written in grey and one written in colour with a rounding error between its
## channels are the two sides of it.
const COLOUR_EPSILON: float = 0.004

## What a texel's lightness is when its picture carries no colour, which is
## what "mid grey is neutral" means for the kernel's shift.
##
## The kernel reads the shift as `(lightness - NEUTRAL) * strength`, so this
## value is the one that makes a mask leave a dab's colour alone whatever the
## strength row says.
const NEUTRAL_LIGHTNESS: float = 0.5

## The luminance weights of Rec. 709, which is what "the image's luminance"
## means below and the same triple `core/sa_color_space.gd` converts with.
const LUMINANCE_WEIGHTS := Vector3(0.2126, 0.7152, 0.0722)

## The largest spacing a GBR's field is believed at. It stores a percentage of the
## tip's size in four big-endian bytes, and states no ceiling, so a reader has to
## pick the number above which it is looking at a misread field rather than at a
## spacing: a thousand is ten times the tip, which is already a row of separate
## stamps rather than a stroke.
##
## Refused rather than clamped, because a clamp paints something plausible and
## hides the fact that the offset was wrong.
const MAX_GBR_SPACING: int = 1000

## The two header lengths the format has. Every version carries `header_size`,
## `version`, `width`, `height` and `bytes`, which is twenty. Version 2 added
## `magic_number` and `spacing` after them, which is twenty-eight, and the name
## starts wherever the header ends, so reading a version 1 file at the version 2
## offset takes eight bytes of the name for a magic word and a spacing.
const GBR_V1_HEADER_BYTES: int = 20
const GBR_V2_HEADER_BYTES: int = 28

## `GIMP` as a big-endian word, which is what a version 2 header carries in the
## field a version 1 header does not have, where the name has already started.
const GBR_MAGIC: int = 0x47494D50

## How many rays the silhouette is sampled along. Sixty-four is a point every
## 5.6 degrees, which at a 200 pixel ring leaves chords under 20 pixels, and
## the ring's own segment count is derived from a 6 pixel chord: an outline is
## a shape a painter recognises rather than a circle they measure.
const OUTLINE_SAMPLES: int = 64

## The coverage a texel needs for the silhouette to count it as inside the tip.
## Half, the same place `dab.gmacs` puts the edge of a mask.
const OUTLINE_COVERAGE: float = 0.5

## Outlines already built, by the path they were loaded from, so a painter
## switching between two tips pays for each of them once a session.
static var _outlines: Dictionary[String, PackedVector2Array] = {}

## Outlines already turned and narrowed, keyed by the whole transform, because
## the tool machine asks once a frame whether the shape has moved.
static var _transformed: Dictionary[String, PackedVector2Array] = {}


## One loaded tip, or one refusal. `error` empty means the rest is real.
##
## A class rather than a Dictionary so a caller cannot misspell a key and get
## null, which is the failure this loader is least able to report.
class Tip:
    extends RefCounted

    ## Coverage per texel, row major, `size.x * size.y` long. 1.0 is full.
    var mask: PackedFloat32Array = PackedFloat32Array()
    var size: Vector2i = Vector2i.ZERO
    ## This tip's own lightness per texel, row major and the same length as
    ## [member mask], which is the texture's second channel.
    ##
    ## **Always full, and mid grey where there is nothing to say.** A picture
    ## that carries no colour is a mask and its lightness is
    ## [constant NEUTRAL_LIGHTNESS], so the kernel's shift is exactly nought and
    ## a greyscale tip paints the texels it always did. Leaving this empty for a
    ## mask and branching on it in the kernel would be a second way to say what
    ## the value already says.
    var lightness: PackedFloat32Array = PackedFloat32Array()
    ## Whether this picture actually carries colour, which is what decides
    ## whether [member mask] is its alpha or the greyscale rule.
    ##
    ## Read by the loader off the pixels rather than off the file extension,
    ## because both formats hold both: a `.png` may be a grey mask or a colour
    ## map and so may a `.gbr`.
    var colourful: bool = false
    ## As a fraction of the tip's size, which is how the file states it.
    var spacing: float = SPACING_WHEN_UNSTATED
    ## The tip's own name when the file carries one, else the file's base name.
    var tip_name: String = ""
    ## Why this is not a tip. Empty on success, and the only thing worth reading
    ## when it is not.
    var error: String = ""

    ## How many bytes of the buffer this tip's own file occupied, header and
    ## pixels together, and zero for anything but a GBR that loaded.
    ##
    ## Here rather than answered beside the tip because a `.gih` is one GBR
    ## after another with nothing between them, so the only way to find the
    ## second tip is to be told where the first one stopped, and GDScript has no
    ## out parameter to be told it through.
    var bytes_read: int = 0

    func ok() -> bool:
        return error.is_empty() and size.x > 0 and size.y > 0

    ## The coverage at a texel, for a test or a probe. Zero outside the tip
    ## rather than an index error, because a caller asking off the edge is
    ## asking about a place the tip does not cover.
    func at(x: int, y: int) -> float:
        if x < 0 or y < 0 or x >= size.x or y >= size.y:
            return 0.0
        return mask[y * size.x + x]

    ## The lightness at a texel, for a test or a probe, and mid grey outside the
    ## tip for the reason [method at] answers nothing there.
    func lightness_at(x: int, y: int) -> float:
        if x < 0 or y < 0 or x >= size.x or y >= size.y or lightness.is_empty():
            return NEUTRAL_LIGHTNESS
        return lightness[y * size.x + x]

    ## The silhouette, built once and kept, because the ring is drawn every
    ## frame the pointer moves and a tip changes only when a painter loads one.
    var _outline: PackedVector2Array = PackedVector2Array()

    ## This tip's shape as a closed polyline, in units of its own half-size, so
    ## the point furthest from the centre sits at 1.0.
    ##
    ## **A radial silhouette rather than a contour.** For each of *samples*
    ## angles it walks out from the centre and keeps the furthest texel whose
    ## coverage reaches [constant OUTLINE_COVERAGE]. That is exact for anything
    ## convex, which is what a brush tip almost always is, it costs one pass
    ## over a ray per angle, and it fails in one describable way: a tip with a
    ## bay in its edge is drawn across the bay, and one with a hole in the
    ## middle is drawn as if the hole were filled. Marching squares would
    ## follow both and is the thing to reach for if a painter ever asks.
    ##
    ## Empty when the tip is not one, or when nothing on it reaches the
    ## coverage, which is a mask of nothing and has no shape to draw.
    func outline(samples: int = OUTLINE_SAMPLES) -> PackedVector2Array:
        if not _outline.is_empty():
            return _outline
        if not ok() or samples < 3:
            return PackedVector2Array()
        var centre := Vector2(size) * 0.5
        var reach := maxf(centre.x, centre.y)
        # A quarter of a texel a step, and the texel rounded rather than
        # truncated: at half a step and a truncation the ray missed the last
        # texel often enough that a round tip came back varying by 8 percent,
        # which reads as a wobbly circle rather than as a circle.
        var steps := int(ceilf(reach)) * 4
        var points := PackedVector2Array()
        var furthest := 0.0
        for i in samples:
            var angle := TAU * float(i) / float(samples)
            var ray := Vector2(cos(angle), sin(angle))
            var found := 0.0
            for step in range(steps, 0, -1):
                var distance := reach * float(step) / float(steps)
                var texel := centre + ray * distance
                if at(roundi(texel.x), roundi(texel.y)) >= OUTLINE_COVERAGE:
                    found = distance
                    break
            points.append(ray * found)
            furthest = maxf(furthest, found)
        if furthest <= 0.0:
            return PackedVector2Array()
        for i in points.size():
            points[i] = points[i] / furthest
        _outline = points
        return _outline


## Loads *path* by its extension. The one door.
##
## By extension rather than by sniffing the bytes, which is what
## `core/image/sa_image_import.gd` does too: a file that lies about its format is a
## corrupt file, and saying so is more use than guessing right.
static func load_from(path: String) -> Tip:
    var lower := path.to_lower()
    if lower.ends_with(".png") or lower.ends_with(".gbr"):
        var bytes := FileAccess.get_file_as_bytes(path)
        if bytes.is_empty():
            return _refuse(TranslationServer.translate("%s could not be read.") % path.get_file())
        return load_bytes(bytes, path.get_file())
    return load_bytes(PackedByteArray(), path.get_file())


## The from-bytes door beside the from-path one.
##
## A Krita preset carries its tip inside its own file, base64 in the XML, so
## the bytes of a PNG or a GBR arrive with a *file_name* and no file. The name
## is what decides the format, by extension exactly as [method load_from]
## decides it, and it is the name every refusal and every fallback tip name
## quotes, so a painter reading a message sees the tip's name from the preset
## rather than the preset's path. `load_from` is this door with a read in front
## of it, and the two readers below know nothing about files.
static func load_bytes(bytes: PackedByteArray, file_name: String) -> Tip:
    var lower := file_name.to_lower()
    if lower.ends_with(".png"):
        return _png_from_bytes(bytes, file_name)
    if lower.ends_with(".gbr"):
        return _gbr_from_bytes(bytes, file_name)
    if lower.ends_with(".gih"):
        return _refuse(
            (
                TranslationServer.translate("%s is a GIMP pipe. Load Tip reads it with the pipe reader, not as a single tip.")
                % file_name
            )
        )
    if lower.ends_with(".abr"):
        return _refuse(
            (
                TranslationServer.translate("%s is a brush collection. Load Tip opens it and loads the tip picked from it.")
                % file_name
            )
        )
    return _refuse(TranslationServer.translate("%s is not a brush tip Sara reads. Open a .png or a .gbr.") % file_name)


## Uploads a tip's mask to a two-channel texture, or null when the tip is not
## one.
##
## **One texture with coverage in red and lightness in green**, rather than a
## second sampler. A second texture is a seventh binding on a kernel whose
## uniform set already carries six things it may not read, and the two numbers
## describe one texel of one picture, so they belong in one texel. The kernel
## reads `.r` where it reads a mask, which is the whole of the compatibility
## this needed.
##
## `r32f` per channel rather than a half, and no sRGB transfer on either: the
## coverage is nobody's colour and the lightness is a ratio against mid grey
## rather than a value displayed anywhere, the same reason
## `core/api/selection/sa_selection.gd` stores its mask in a float. Sized to the tip, so a
## 32 by 32 GBR costs 8 KB whatever size it is stamped at.
static func upload(tip: Tip) -> SaTexture:
    if tip == null or not tip.ok():
        return null
    return upload_texels(tip.size, texels(tip))


## The bytes [method upload] sends, coverage and lightness interleaved the way
## the texture holds them.
##
## **Apart from the upload because it is the half a thread can take.** It reads
## the tip and touches no device, and for a pipe of hundreds of cells it is a
## loop over every texel of every cell, which `SaTipCache` runs on a worker
## while the window goes on drawing.
##
## Read off locals rather than the tip's members, for the lock [method gbr_at]
## says it keeps out of its own loop.
static func texels(tip: Tip) -> PackedByteArray:
    var count := tip.size.x * tip.size.y
    var mask := tip.mask
    var lightness := tip.lightness
    var lit := lightness.size()
    var channels := PackedFloat32Array()
    channels.resize(count * 2)
    for i in count:
        channels[i * 2] = mask[i]
        channels[i * 2 + 1] = lightness[i] if i < lit else NEUTRAL_LIGHTNESS
    return channels.to_byte_array()


## The texture [method upload] makes, of *size*, from *bytes* that
## [method texels] built, or null with no device to make it on.
static func upload_texels(size: Vector2i, bytes: PackedByteArray) -> SaTexture:
    var texture := SaTexture.new(size, RenderingDevice.DATA_FORMAT_R32G32_SFLOAT)
    if texture.rd == null:
        return null
    texture.rd.texture_update(texture.rid, 0, bytes)
    return texture


static func _refuse(reason: String) -> Tip:
    var tip := Tip.new()
    tip.error = reason
    return tip


## A PNG through Godot's own decoder, with the greyscale rule over it.
##
## **A grey tip's rule is `(1 - red) * alpha`**, which is the port
## `kis_brush.cpp` still grants this file its lines for. A black texel is full
## coverage and a white one is none, which is how every brush tip anybody has
## ever drawn is drawn: dark where the brush marks. The red channel is the one
## read because a tip drawn in grey carries the same value in all three.
##
## An image that is all grey and fully opaque is a mask by that rule alone.
## An image that carries alpha is a mask by the same rule with the alpha
## multiplied in, so a soft-edged tip on transparency loads the way it looks.
##
## **A picture that carries colour is read the other way round**: its alpha is
## the coverage and its own colour is the lightness the dab kernel shifts by.
## That is what Krita's lightness map wants, and it is the reading
## `_gbr_from_bytes` gives a depth-four GBR, rather than a field on the chunk
## choosing the rule.
##
## The two rules disagree only for a picture that carries colour, so a grey tip
## loads the mask the grey rule alone gives, texel for texel.
static func _png_from_bytes(bytes: PackedByteArray, file_name: String) -> Tip:
    var image := Image.new()
    if bytes.is_empty() or image.load_png_from_buffer(bytes) != OK:
        return _refuse(TranslationServer.translate("%s could not be read as a PNG.") % file_name)
    if image.get_width() <= 0 or image.get_height() <= 0:
        return _refuse(TranslationServer.translate("%s decoded to nothing.") % file_name)

    var tip := Tip.new()
    tip.size = Vector2i(image.get_width(), image.get_height())
    tip.colourful = _has_colour(image)
    tip.mask.resize(tip.size.x * tip.size.y)
    tip.lightness.resize(tip.size.x * tip.size.y)
    for y in tip.size.y:
        for x in tip.size.x:
            var texel := image.get_pixel(x, y)
            var at := y * tip.size.x + x
            # The alpha is the mask either way for a picture with colour, and
            # the greyscale rule multiplies it in for one without.
            tip.mask[at] = clampf(texel.a if tip.colourful else (1.0 - texel.r) * texel.a, 0.0, 1.0)
            tip.lightness[at] = luminance_of(texel) if tip.colourful else NEUTRAL_LIGHTNESS

    var text := _png_text_keys(bytes)
    tip.spacing = SaTyped.float_at(text, "brush_spacing", SPACING_WHEN_UNSTATED)
    tip.tip_name = SaTyped.text_at(text, "brush_name", file_name.get_basename())
    return tip


## Whether any texel of *image* carries a colour, which is what decides which of
## the two coverage rules above a PNG is read by.
##
## **The spread across the three channels rather than a colour space**, because
## the question is whether all three carry one number or three: a greyscale
## image is exactly the case where they agree, and a picture that is nearly grey
## answers no, which is right, since a mask is what it would be used as.
static func _has_colour(image: Image) -> bool:
    for y in image.get_height():
        for x in image.get_width():
            var texel := image.get_pixel(x, y)
            var spread := maxf(maxf(absf(texel.r - texel.g), absf(texel.g - texel.b)), absf(texel.r - texel.b))
            if spread > COLOUR_EPSILON:
                return true
    return false


## A colour's luminance, in the Rec. 709 weights and on the values as stored.
##
## **On the stored values rather than on a linearised copy**, which is the
## neutral the row above states: a painter's mid grey is the code value a half,
## and the kernel's shift is read against mid grey, so the conversion that would
## make this physically right would move every tip's neutral off the number a
## painter reads. The shift itself is applied in Oklab, which is where the hue
## is held.
static func luminance_of(color: Color) -> float:
    var weights := LUMINANCE_WEIGHTS
    return clampf(color.r * weights.x + color.g * weights.y + color.b * weights.z, 0.0, 1.0)


## The `tEXt` chunks of a PNG, as key to value.
##
## By hand, because Godot's `Image` throws every ancillary chunk away and offers
## no way to ask for one. The two keys worth reading are `brush_spacing` and
## `brush_name`, which is what a tip exported from Krita carries, so such a tip
## loses its own spacing here otherwise, silently, and a painter would only find
## out by measuring a stroke.
##
## Only `tEXt`, which is the uncompressed Latin-1 flavour and the one those keys
## arrive in. `zTXt` is the same payload deflated and `iTXt` is UTF-8 with a
## language tag and a compression flag of its own, and reading either means a
## second decoder for a key no tip in the wild puts there.
static func _png_text_keys(bytes: PackedByteArray) -> Dictionary[String, String]:
    var out: Dictionary[String, String] = {}
    # 8 bytes of signature, then length, type, data, CRC per chunk.
    var at := 8
    while at + 8 <= bytes.size():
        var length := bytes.decode_u32(at)
        var kind := bytes.slice(at + 4, at + 8).get_string_from_ascii()
        # decode_u32 is little endian and every PNG length is big endian.
        length = (((length & 0xFF) << 24) | ((length & 0xFF00) << 8) | ((length >> 8) & 0xFF00) | ((length >> 24) & 0xFF))
        var data_at := at + 8
        if length < 0 or data_at + length > bytes.size():
            break
        if kind == "tEXt":
            var raw := bytes.slice(data_at, data_at + length)
            var split := raw.find(0)
            if split > 0:
                var key := raw.slice(0, split).get_string_from_ascii()
                out[key] = raw.slice(split + 1, raw.size()).get_string_from_ascii()
        if kind == "IEND":
            break
        at = data_at + length + 4
    return out


## A GIMP `.gbr`, whose header is big endian and whose shape changed at version 2.
##
## Read from the format: five 32-bit fields, two more from version 2 on, a
## terminated name, then `width * height * bytes` of data. Every guard below is a
## field checked against the size of the file it came out of, because a header is
## a set of numbers a corrupt file is free to lie about and each one is used as an
## offset or a length.
##
## **A depth-1 byte is the coverage, not its complement.** The mask this returns
## is coverage directly, 255 meaning a fully covered texel, which is what the
## format stores. Inverting it would be right only for a pipeline that keeps a
## mask as a white background and inverts again when it stamps, and reading a GBR
## that way makes a round tip a square with a hole in it.
static func _gbr_from_bytes(bytes: PackedByteArray, file_name: String) -> Tip:
    return gbr_at(bytes, 0, file_name)


## One GBR starting at *at*, and how long it was, so the next one can be
## found.
##
## An offset rather than a slice because a `.gih` is a hundred GBRs in one
## buffer and slicing each of them out would copy the tail of the file once per
## tip. Every guard below is a field checked against the room left after *at*,
## for the reason the whole-file reader checks against the size of the file: a
## header is a set of numbers a corrupt file is free to lie about, and each one
## is used as an offset or a length.
##
## *with_texels* false reads the header alone and leaves [member Tip.mask] and
## [member Tip.lightness] empty, for a pipe's cell `SaTipCache` makes on the
## card from its own bytes, which start [member Tip.bytes_read] less the texels
## after *at*.
static func gbr_at(bytes: PackedByteArray, at: int, file_name: String, with_texels: bool = true) -> Tip:
    if at < 0 or bytes.size() - at < GBR_V1_HEADER_BYTES:
        return _refuse(TranslationServer.translate("%s is too short to be a GBR.") % file_name)

    var header_size := _be_u32(bytes, at)
    var version := _be_u32(bytes, at + 4)
    var width := _be_u32(bytes, at + 8)
    var height := _be_u32(bytes, at + 12)
    var depth := _be_u32(bytes, at + 16)

    if width <= 0 or height <= 0:
        return _refuse(
            TranslationServer.translate("%s says it is %s × %s px, which is not a valid tip size.") % [file_name, width, height]
        )
    if header_size <= 0 or at + header_size > bytes.size():
        return _refuse(
            (
                TranslationServer.translate("%s has a header of %s bytes in a file of %s.")
                % [file_name, header_size, bytes.size() - at]
            )
        )

    var spacing := SPACING_WHEN_UNSTATED
    if version > 1:
        if bytes.size() - at < GBR_V2_HEADER_BYTES:
            return _refuse(TranslationServer.translate("%s says version %s and stops before its spacing.") % [file_name, version])
        var raw_spacing := _be_u32(bytes, at + 24)
        if raw_spacing > MAX_GBR_SPACING:
            return _refuse(
                TranslationServer.translate("%s has a spacing of %s, above the 1000 a GBR may say.") % [file_name, raw_spacing]
            )
        spacing = float(raw_spacing) / 100.0

    var needed := header_size + width * height * depth
    if depth != 1 and depth != 4:
        return _refuse(
            (
                TranslationServer.translate("%s has %s channels. Sara reads greyscale tips, with 1, and colour tips, with 4.")
                % [file_name, depth]
            )
        )
    if at + needed > bytes.size():
        return _refuse(
            (
                TranslationServer.translate("%s wants %s bytes of tip after its header and the file holds %s.")
                % [file_name, needed, bytes.size() - at]
            )
        )

    var tip := Tip.new()
    tip.size = Vector2i(width, height)
    tip.spacing = spacing
    tip.tip_name = _gbr_name(bytes, at, header_size, version, file_name)
    tip.bytes_read = needed
    # A depth of 4 is RGBA rather than a grey mask, and its three colour bytes
    # are the second channel rather than a colour with nowhere to go.
    tip.colourful = depth == 4
    if not with_texels:
        return tip
    # Into locals and onto the tip once, because an object's member indexed
    # once a texel is the object looked up once a texel, which the debug build
    # Sara ships does under ObjectDB's one lock, so a pipe's cells read on every
    # worker at once would run slower than on one thread.
    var mask := PackedFloat32Array()
    var lightness := PackedFloat32Array()
    mask.resize(width * height)
    lightness.resize(width * height)
    var read_at := at + header_size
    if depth == 1:
        # Coverage per texel and no colour of its own, so its lightness is the
        # neutral one.
        lightness.fill(NEUTRAL_LIGHTNESS)
        for i in width * height:
            mask[i] = float(bytes[read_at + i]) / 255.0
    else:
        # RGBA, where the alpha is the coverage and the three colour bytes are
        # the luminance the kernel shifts the dab's colour by, which is the
        # reading `_png_from_bytes` gives a picture that carries colour.
        for i in width * height:
            mask[i] = float(bytes[read_at + 3]) / 255.0
            lightness[i] = _gbr_luminance(bytes, read_at)
            read_at += depth
    tip.mask = mask
    tip.lightness = lightness
    return tip


## One depth-four GBR texel's luminance, off the three colour bytes that sit
## before its alpha.
static func _gbr_luminance(bytes: PackedByteArray, at: int) -> float:
    var weights := LUMINANCE_WEIGHTS
    var red := float(bytes[at]) / 255.0
    var green := float(bytes[at + 1]) / 255.0
    var blue := float(bytes[at + 2]) / 255.0
    return clampf(red * weights.x + green * weights.y + blue * weights.z, 0.0, 1.0)


## The name a GBR carries between its header fields and its pixels. Latin-1 in
## version 1 and UTF-8 from version 2, both terminated, which is why the length
## is one short of the gap.
static func _gbr_name(bytes: PackedByteArray, at: int, header_size: int, version: int, file_name: String) -> String:
    var starts := at + (GBR_V1_HEADER_BYTES if version == 1 else GBR_V2_HEADER_BYTES)
    var length := header_size - (starts - at) - 1
    if length <= 0 or starts + length > bytes.size():
        return file_name.get_basename()
    var raw := bytes.slice(starts, starts + length)
    var text := raw.get_string_from_utf8() if version > 1 else raw.get_string_from_ascii()
    return text if not text.is_empty() else file_name.get_basename()


static func _be_u32(bytes: PackedByteArray, at: int) -> int:
    if at + 4 > bytes.size():
        return 0
    return (bytes[at] << 24) | (bytes[at + 1] << 16) | (bytes[at + 2] << 8) | bytes[at + 3]


## The cursor outline for the image at *path*, turned by *radians*, narrowed to
## *ratio* on its minor axis, and in units of the ring's radius.
##
## Empty for a path that is not a tip, which is what a procedural tip and a
## failed load both give, and is what leaves the ring a circle.
##
## The transform is applied here rather than by the caller because the caller is
## a module's cursor line and this is the file that knows what the points mean.
##
## **Narrow first, then turn**, which is the order the dab kernel builds its own
## transform in and the reason the ring agrees with the mark it promises. The
## ratio is a squash along the tip's own minor axis, so it has to be applied while
## that axis is still the tip's: turn first and the squash happens along the
## screen instead, and a flattened tip at forty-five degrees comes out flattened
## the wrong way.
static func cursor_outline(path: String, radians: float, ratio: float, flip: bool) -> PackedVector2Array:
    # Memoised on the whole transform, not only on the path, because the tool
    # machine asks once a frame whether the shape has changed and rebuilding
    # sixty-four rotated points to answer "no" is work nobody asked for.
    var key := "%s|%.5f|%.5f|%s" % [path, radians, ratio, flip]
    if _transformed.has(key):
        return _transformed[key]
    var shape := outline_for(path)
    if shape.is_empty():
        _transformed[key] = shape
        return shape
    var narrowed := clampf(ratio, 0.0, 1.0)
    # One mirrored axis turns a right-handed frame left-handed, so the angle
    # measured in it runs the other way, which is the seam `state_brush.gd`
    # describes where it builds the dab's own box.
    var turn := -radians if flip else radians
    var out := PackedVector2Array()
    out.resize(shape.size())
    for i in shape.size():
        out[i] = Vector2(shape[i].x, shape[i].y * narrowed).rotated(turn)
    _transformed[key] = out
    return out


## The cursor outline for whatever tip *settings* is holding.
##
## Static, and the descriptor binds it to the settings resource rather than
## wrapping it in a lambda: a closure written in `stamp-brush/module.gd` would
## capture that module, the descriptor would hold the closure and the module
## would hold the descriptor, and a `RefCounted` cycle is 704 leaked objects at
## exit with `run_tests.sh` red for a reason nothing in the diff looks like.
##
## Read through `in` and by method name because the settings resource and the
## tip on it belong to the brush engine, and this is a loader: what it needs is
## a path and three numbers.
static func outline_of(settings: Resource) -> PackedVector2Array:
    if settings == null or not "tip" in settings:
        return PackedVector2Array()
    var held: Variant = settings.get("tip")
    if not held is SaBrushTipScript:
        return PackedVector2Array()
    var tip: SaBrushTipScript = held
    if not tip.uses_image():
        return PackedVector2Array()
    return cursor_outline(tip.image_path, tip.angle, tip.ratio, tip.mirror_flips_handedness())


## The silhouette of the tip at *path*, cached by path.
##
## Loading a PNG to draw a cursor would be absurd once a frame, so the outline
## outlives the `Tip` it was taken from: the mask is thousands of floats and
## the outline is [constant OUTLINE_SAMPLES] points.
static func outline_for(path: String) -> PackedVector2Array:
    if path.is_empty():
        return PackedVector2Array()
    if _outlines.has(path):
        return _outlines[path]
    var tip := load_from(path)
    var shape := tip.outline() if tip.ok() else PackedVector2Array()
    _outlines[path] = shape
    return shape


## Forgets every cached outline, for a test that loads the same path twice with
## different bytes behind it.
static func forget_outlines() -> void:
    _outlines.clear()
    _transformed.clear()
