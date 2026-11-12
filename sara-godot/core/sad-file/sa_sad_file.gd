## The `.sad` container: the format's constants, the writer, the reader's
## steps around `SaSadOpening`, and the preview
## thumbnail a recent-files grid reads. One layer's entry in the header, every
## key of it but its chunks, is `SaSadLayerEntry`'s, beside this file.
##
## The writer, the reader and the preview are one file rather than three
## around a fourth that holds the constants, because the keys one writes are
## the keys the other reads, and nothing here reaches for an instance.
##
## `SaExport.save_sad()` and `SaExport.load_sad()` stay the door callers type,
## because autosave, the recorder and the file menu call them by that name.
##
## Every function is static, and two of them are not called `save` and `load`
## on purpose: a declaration of `load` anywhere in the project shadows
## `@GlobalScope.load()` for everyone, and the error is reported at the
## innocent calls rather than at the declaration.
class_name SaSadFile
extends RefCounted

## Binary format constants
##
## The magic every file this build reads starts with. A file with any other
## magic is refused, an early build's among them.
const SAD_MAGIC_V4: String = "SAD2"
## The magic of the early container, named only so its refusal can say so.
const EARLY_MAGIC: String = "SAD1"
## The sibling a save is written to before it is renamed into place.
const SAD_TEMP_SUFFIX := ".saving"
## The newest version this build writes and reads, a file holding a drawn
## layer. What a save stamps is `stamp_for(document)`, 14 or above
## for a document holding any stored texture and older only for one that holds none.
const SAD_VERSION: int = SaSadDrawn.VERSION
## What a file in a codec is written as, one above a shared source.
const SAD_VERSION_CODED: int = SaSadSharedSource.VERSION + 1
## What a document holding any stored texture is written as: its blobs are byte
## planes of deltas, `SaSadBlob`'s, which a build that reads 13 would upload as
## the texture's own bytes and show as noise. So it refuses a 14 by name.
const SAD_VERSION_PLANES: int = 14
## What a document with a layer a simulation rule steps is written as, the
## record in its layer's entry with the seed beside the paint.
const SAD_VERSION_SIMULATION: int = 13
## What a document with a Screen layer is written as, so a file of an older
## version is known to have drawn Screen by the formula alone.
const SAD_VERSION_ABOVE_WHITE: int = 10
## What a document with a layer in Overlay, Soft Light, Hard Light, Colour
## Dodge, Exclusion or Hard Mix is written as, the rest of the separable
## display-referred modes, which kept drawing above white a version after
## Screen. A file at 10 drew Screen the new way and these by the formula alone.
const SAD_VERSION_SEPARABLE_ABOVE_WHITE: int = 11
## What a document with a layer in Hue, Saturation, Colour or Lightness is
## written as, the four that swap components in Oklab LCh, which work over the
## whole range a version after the separable modes. A file older than this drew
## them inside the window up to white, as "The component modes" in
## libs/composite_blend_ops.gmacs says.
const SAD_VERSION_OKLCH_ABOVE_WHITE: int = 12
## The display-referred modes that keep drawing above white, see "Above white"
## in libs/composite_blend_ops.gmacs, each with the version since which a file
## draws it so. A file older than its mode's version drew it by the formula
## alone, or for Hue, Saturation, Colour and Lightness inside the window up
## to white. Hard Mix is here by its id, a module's mode when it joined and the
## skeleton's now, because the id is the word a `.sad` file names it by,
## whichever code draws it, and the version is the file's to give.
const EXTENDED_ABOVE_WHITE: Dictionary[StringName, int] = {
    &"screen": SAD_VERSION_ABOVE_WHITE,
    &"overlay": SAD_VERSION_SEPARABLE_ABOVE_WHITE,
    &"soft_light": SAD_VERSION_SEPARABLE_ABOVE_WHITE,
    &"hard_light": SAD_VERSION_SEPARABLE_ABOVE_WHITE,
    &"color_dodge": SAD_VERSION_SEPARABLE_ABOVE_WHITE,
    &"exclusion": SAD_VERSION_SEPARABLE_ABOVE_WHITE,
    &"hard_mix": SAD_VERSION_SEPARABLE_ABOVE_WHITE,
    &"hue": SAD_VERSION_OKLCH_ABOVE_WHITE,
    &"saturation": SAD_VERSION_OKLCH_ABOVE_WHITE,
    &"color": SAD_VERSION_OKLCH_ABOVE_WHITE,
    &"lightness": SAD_VERSION_OKLCH_ABOVE_WHITE,
}
## What a document with a layer drawn through a live transform and no layer in
## an extended mode is written as, so the builds that read version 9 keep
## opening it.
const SAD_VERSION_LIVE_TRANSFORM: int = 9
## What a document with an effect layer and no live transform is written as,
## so the builds that read version 8 keep opening it.
const SAD_VERSION_EFFECT: int = 8
## What a document with an adjustment layer and no effect layer is written as,
## so the builds that read version 7 keep opening it.
const SAD_VERSION_ADJUSTMENT: int = 7
## What a document with a height and no adjustment layer is written as, so the
## builds that read version 6 keep opening it.
const SAD_VERSION_HEIGHT: int = 6
## What a document with a mask or an attached filter and no height is written
## as, so the builds that read version 5 keep opening it.
const SAD_VERSION_MASKED: int = 5
## What a document with no mask and no attached filter is still written as, so
## every build since v4 keeps opening it.
const SAD_VERSION_PLAIN: int = 4
## v4: the header, and every chunk blob independently, so one chunk can be
## decoded without touching the rest, which is what makes doing it off the
## main thread possible later.
const SAD_BLOB_COMPRESS: int = FileAccess.COMPRESSION_ZSTD

## The longest side of the preview thumbnail written into the header, in
## pixels, and the WebP quality it is encoded at. A recent-files grid wants a
## small picture to skim, not the whole canvas, and 0.9 is where text in the UI
## still reads.
const PREVIEW_LONG_SIDE: int = 256
const PREVIEW_QUALITY: float = 0.9

# ---------------------------------------------------------------------------
# The preview picture
# ---------------------------------------------------------------------------


## *shot* with its longest side at *long_side*, or *shot* itself when it is
## already smaller. Never enlarged: a small picture is not worth more pixels
## than it has. The writer shrinks the painter's preview through this and a
## note shrinks its window shot through the same lines.
static func shrink(shot: Image, long_side: int) -> Image:
    var size := shot.get_size()
    var longest := maxi(size.x, size.y)
    if longest <= long_side or longest <= 0:
        return shot
    var ratio := float(long_side) / float(longest)
    var smaller := Image.new()
    smaller.copy_from(shot)
    smaller.resize(maxi(1, roundi(size.x * ratio)), maxi(1, roundi(size.y * ratio)), Image.INTERPOLATE_LANCZOS)
    return smaller


## Writes *preview* into *header* and *blobs*, which must hold no blob yet.
##
## The document preview, additive to v4: a file without it still opens, and a
## reader without the key still opens a file that has one. Written only when a
## preview is given, which is the painter's save rather than the autosave or the
## capture step, where a readback buys a picture nobody looks at. Its bytes are
## the first blob of the region at offset 0, so a reader seeks once instead of
## walking the index. A save in the background calls this on its worker, before
## the first chunk's bytes, because the shrink and the encode are tens of
## milliseconds on a large picture.
static func preview_into(header: Dictionary[String, Variant], blobs: PackedByteArray, preview: Image) -> void:
    if preview == null:
        return
    var thumbnail := shrink(preview, PREVIEW_LONG_SIDE)
    var rgba8 := thumbnail
    if thumbnail.get_format() != Image.FORMAT_RGBA8:
        rgba8 = Image.new()
        rgba8.copy_from(thumbnail)
        rgba8.convert(Image.FORMAT_RGBA8)
    var webp := rgba8.save_webp_to_buffer(true, PREVIEW_QUALITY)
    header["preview"] = {
        "offset": blobs.size(),
        "size": webp.size(),
        "format": "webp",
        "width": thumbnail.get_width(),
        "height": thumbnail.get_height(),
    }
    blobs.append_array(webp)


## The preview stored in the v4 file at *path*, or null when there is none.
##
## A recent-files grid wants a thumbnail, and building a whole `SaDocument` to
## get one is the readback hard rule 1 exists to stop, ten times over at start.
## This seeks once, decodes the WebP the writer stored as the first blob, and
## touches no `RenderingDevice`.
##
## Quiet where a thumbnail is simply absent: a file that is not a `.sad`
## and a file saved with no preview all answer null without an error,
## because a missing picture is not a fault.
static func read_preview(path: String) -> Image:
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        return null
    var header := _header_from(file)
    if not header.has("preview"):
        file.close()
        return null
    var entry := SaTyped.strings(header["preview"])
    var offset := SaTyped.int_at(entry, "offset", 0)
    var size := SaTyped.int_at(entry, "size", 0)
    if size <= 0:
        file.close()
        return null
    var region := file.get_buffer(file.get_length() - file.get_position())
    file.close()
    if offset + size > region.size():
        return null
    var image := Image.new()
    if image.load_webp_from_buffer(region.slice(offset, offset + size)) != OK:
        return null
    return image


## The key a Reference picture's entry carries the bytes a file stored for it
## under, in memory only, `SaSadReferencePictures`'s and named here for the docker.
const REFERENCE_BYTES := SaSadReferencePictures.BYTES_KEY


## The bytes a file stored for the Reference picture *entry* is, or none.
static func reference_bytes(entry: Dictionary) -> PackedByteArray:
    var held: Variant = entry.get(REFERENCE_BYTES)
    return held if held is PackedByteArray else PackedByteArray()


## The picture *held* holds, the bytes a file stored for the Reference picture
## at *path*, with the colour space they name, or null. The docker's door to
## `SaSadReferencePictures.read_held`.
static func reference_picture(held: PackedByteArray, path: String) -> SaSadReferencePictures.Held:
    return SaSadReferencePictures.read_held(held, path)


## The header of the v4 `.sad` at *path*, read without its blobs, or an empty
## dictionary for a file that is not one. What a document will hold is known
## from it before the file is opened, which the check of the card's memory
## before an Open asks.
static func header_at(path: String) -> Dictionary[String, Variant]:
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        return {}
    var header := _header_from(file)
    file.close()
    return header


## The header of the open *file*, left at the first byte after it.
static func _header_from(file: FileAccess) -> Dictionary[String, Variant]:
    if file.get_buffer(4).get_string_from_ascii() != SAD_MAGIC_V4:
        return {}
    # version(4 LE) | header_compressed(4 LE) | header_raw(4 LE), then the header.
    file.get_32()
    var header_packed_size := file.get_32()
    var header_raw_size := file.get_32()
    var header_bytes := file.get_buffer(header_packed_size).decompress(header_raw_size, SAD_BLOB_COMPRESS)
    if header_bytes.is_empty():
        return {}
    var json := JSON.new()
    if json.parse(header_bytes.get_string_from_utf8()) != OK:
        return {}
    return SaTyped.strings(json.data)


# ---------------------------------------------------------------------------
# .sad format: save
# ---------------------------------------------------------------------------


## Module data in the exact form a JSON round trip produces, so a file is stable
## from its first save rather than its second.
##
## The problem this solves is small and would otherwise be permanent. JSON has one
## number type, so `JSON.parse_string` returns 3.0 for a stored `3`. Writing a
## module's dictionary straight into the header therefore puts `3` on disk, and
## the next save of the same untouched data writes `3.0`. A document opened and
## saved on a build without the module would differ from the original, which is
## exactly the guarantee that has to hold.
##
## Passing the data through stringify and parse first reaches that fixed point
## before it is written, so every save from then on is byte for byte the same.
## Godot's `JSON.stringify` sorts keys, so ordering is already stable and only the
## numbers needed this.
##
## Anything a module stores that JSON cannot represent degrades here, at save
## time, where a test can see it, rather than silently on the next load.
static func canonical_module_data(raw: Dictionary) -> Dictionary[String, Variant]:
    if raw.is_empty():
        return {}
    var canonical: Variant = JSON.parse_string(JSON.stringify(raw))
    if canonical is Dictionary:
        return SaTyped.strings(canonical)
    push_error("SaExport: module data is not JSON-representable, so it was not written.")
    return {}


## What the disk says after a save of *target* failed, the sentences that
## follow the failure's own: where the written picture is kept, why, and the
## previous file. Every save's failure line ends so, the door's among them.
## *side* is where the save wrote its side file, beside *target* when empty.
## A side file kept elsewhere, as a content address's is, says nothing of the
## previous file, which the address alone holds.
static func why_not_saved(target: String, side := "") -> String:
    var kept := target + SAD_TEMP_SUFFIX if side.is_empty() else side
    var said := [""]
    if FileAccess.file_exists(kept):
        said.append(TranslationServer.translate("The picture was written in full and is kept at '%s'.") % kept)
    var folder := target if DirAccess.dir_exists_absolute(target) else kept if DirAccess.dir_exists_absolute(kept) else ""
    if not folder.is_empty():
        said.append(TranslationServer.translate("A folder stands at '%s'.") % folder)
    elif not FileAccess.file_exists(kept):
        said.append(TranslationServer.translate("Nothing could be written into the folder '%s'.") % kept.get_base_dir())
    var beside := kept == target + SAD_TEMP_SUFFIX
    if beside and FileAccess.file_exists(target):
        said.append(TranslationServer.translate("The previous file is untouched."))
    elif beside and FileAccess.file_exists(target + "1"):
        said.append(TranslationServer.translate("The previous file is at '%s1'.") % target)
    return " ".join(said)


## Saves *document* to a .sad file at *path*, in the v4 container.
##
## Layout:
##   magic(4) | version(4 LE) | header_compressed(4 LE) | header_raw(4 LE)
##   | Zstd JSON header | blob region
##
## Every field of every chunk is one Zstd blob in the region, addressed by the
## offset index in the header, in the texture's own texel format. Nothing is
## base64, nothing shares a compression stream, and no offset assumes 16 bytes
## per texel, a single-channel height field is a quarter of an albedo one.
## Writes the document to *path* without ever leaving a half-written file there.
##
## The bytes go to a sibling temporary file first, every write is checked, and
## only then is it renamed over the destination, so a save that runs out of disk
## or hits a read-only directory leaves the previous file as it was. A rename
## that fails keeps the side file, the whole picture, and puts back a previous
## file already moved aside, [method why_not_saved] saying where each is.
##
## The file being replaced is kept as `<name>.sad1`, the one before that becomes
## `.sad2`, up to *keep_versions* of them, and 0 keeps none, Blender's habit. A
## negative count reads the Preferences value.
## This is not the autosave: that is `SaAutosave`, and it writes elsewhere.
##
## It records nothing on the document. Whoever saved decides whether this file
## is now the document's own, through `SaDocument.mark_saved()`.
static func save_file(document: SaDocument, path: String, keep_versions: int = -1, preview: Image = null) -> Error:
    if document == null:
        push_error("SaExport.save_sad: document is null")
        return ERR_INVALID_PARAMETER
    # A file still opening is read whole first, or the save writes its holes.
    SaSadOpening.complete(document)
    var rd := GlobalShaderCompiler.get_rd()
    if rd == null:
        push_error("SaExport.save_sad: RenderingDevice unavailable")
        return ERR_CANT_ACQUIRE_RESOURCE
    var blobs := PackedByteArray()
    var walk := header_of.bind(document, blobs, rd, preview)
    var header: Dictionary[String, Variant] = SaLinkedFile.beside(document, path, walk, blobs)
    var versions := keep_versions if keep_versions >= 0 else SaSettings.sad_versions
    return SaSadSave.write_out(path, header, blobs, versions)


## Ends in this frame the walk in shares of a save from the key, so a save at
## once never runs while that walk holds the snapshot.
static func walk_out() -> void:
    SaSadSave.walk_out()


## Saves *doc* to *path* in the background, after any save already running, as
## `SaSadSave.start` does, with *rounds* for a save the painter asked for and an
## autosave, *by* naming the codec of a save asked for in one by name, and
## *waits* for a save whose walk waits for its hashes with no preview, the
## autosave's. The door for a module and for the ui, which name the facade only.
static func save_in_background(
    doc: SaDocument,
    path: String,
    kept := -1,
    image: Object = null,
    owns := true,
    then := Callable(),
    rounds := false,
    by := &"",
    waits := false,
) -> SaSadSave:
    return SaSadSave.start(doc, path, kept, image, owns, then, rounds, by, waits)


## Runs *then* once every background save has ended, every export target
## one started is whole and every export written over frames,
## `SaExportInTurns`, has ended, at once when none runs. *why* is what waits,
## and the progress line says so.
static func after_saves(then: Callable, why: String) -> void:
    SaSadSave.after_all(SaExportTargets.after_writes.bind(SaExport.InTurns.after_all.bind(then), why), why)


## Whether a background save is running or waiting, or its export targets or
## an export over frames are still being written.
static func saving() -> bool:
    return SaSadSave.is_running() or SaExportTargets.writing() or SaExport.InTurns.running()


## Drives every background save to its end without a frame, its export
## targets and every export over frames with it, for a suite and for a quit
## that cannot wait for one. False when one is still running after
## *longest_msec*.
static func finish_saves(longest_msec := 60000) -> bool:
    var saved := SaSadSave.finish_all(longest_msec) and SaExportTargets.finish_writes(longest_msec)
    return SaExport.InTurns.finish_all(longest_msec) and saved


## The header a save of *document* writes, with every blob it addresses
## appended to *blobs* in the order the header names them, the preview first.
##
## Read on the main thread, because it walks the layers and asks the device.
## While `SaSadSave` takes a snapshot, `SaSadBlob.write` copies each texture
## on the card instead of reading it back, and leaves its slot for the save's
## worker to fill, so the same walk serves the save that waits and the save
## that runs in the background. The head is [method header_head] and each
## layer's entry `SaSadWalk.entry_of`, which a save in the background walks a
## share of a turn.
static func header_of(
    document: SaDocument, blobs: PackedByteArray, rd: RenderingDevice, preview: Image = null
) -> Dictionary[String, Variant]:
    var header := header_head(document, blobs, rd, preview)
    var layers_written: Array = header["layers"]
    for child in document.get_children():
        if child is SaLayer:
            layers_written.append(SaSadWalk.entry_of(child as SaLayer, blobs, rd))
    return header


## Every key of [method header_of]'s header but the layers' entries, whose
## list it holds empty, with the blobs of the preview, the reference pictures
## and the root's filters appended to *blobs*.
static func header_head(
    document: SaDocument, blobs: PackedByteArray, rd: RenderingDevice, preview: Image = null
) -> Dictionary[String, Variant]:
    var version := stamp_for(document)
    var layers_written: Array = []
    var header: Dictionary[String, Variant] = {
        "format": "sad",
        "version": version,
        "width": document.canvas_size.x,
        "height": document.canvas_size.y,
        "layers": layers_written,
    }
    # The document colour descriptor. Additive to the v4 header, so no version
    # bump and no second reader: a build without this key still opens the file,
    # and this build opens one that has none.
    #
    # A document whose space was never specified writes no key at all rather than
    # inventing an sRGB declaration for it. Recording a guess as though the user
    # had chosen it is how a later conversion pass transforms pixels nobody
    # described.
    if document.color_space != null and document.color_space.is_specified:
        header["color_space"] = document.color_space.to_header()
    # What the pixels are a picture of, additive like the colour space and
    # written only when it says something other than flat, so a reader without
    # this line opens a panorama as the flat picture it also is.
    if not document.projection.is_default():
        header[SaProjection.HEADER_KEY] = document.projection.to_header()
    # The blend reference white, likewise additive. Written only when it is not
    # the default, so a plain document's header does not grow a key that says
    # nothing, and a reader without this line still gets the right answer for
    # every file Sara has written so far.
    if not is_equal_approx(document.blend_reference_white, 1.0):
        header["blend_reference_white"] = document.blend_reference_white
    # The document's resolution, additive like the two above but written on
    # every save: 72 is a choice a painter made in File > New, not the absence
    # of one, so the file records it. A reader without this line still opens
    # the file, and one reading a file without the key gets 72.
    header["dpi"] = document.dpi
    # The light the impasto is drawn and baked under, additive and written on
    # every save for the reason the resolution is: a reader without the key
    # falls back on its own Preferences, which differ from machine to machine,
    # so leaving it out would light the file differently on the next one.
    header[SaReliefLight.HEADER_KEY] = document.relief_light.to_header()
    # The side a brush's size is read against, additive and written only when
    # a crop kept one other than the shorter side, so a cropped document opens
    # again with the brush the size it was. A reader without the key reads the
    # shorter side, which is what every file before it meant.
    if not is_equal_approx(document.brush_side, minf(document.canvas_size.x, document.canvas_size.y)):
        header["brush_side"] = document.brush_side
    # The Double Resolution switch, additive and written only while it is on,
    # so a reader without the key opens the file with it off.
    if document.double_resolution.on:
        header[SaDoubleResolution.HEADER_KEY] = document.double_resolution.to_header()
    # The symmetry axes and their switches, additive like the keys above and
    # written only when they say something: a switch on, or the handles moved
    # off rest. A reader without this line opens the file with the axes at rest.
    var canvas := Vector2(document.canvas_size)
    if document.symmetry.is_active() or not document.symmetry.is_at_rest(canvas):
        header["symmetry"] = document.symmetry.to_header()
    # The infinite canvas's switch, written only when on.
    SaInfiniteCanvas.write_header(document, header)
    # Per-module document state, additive to v4 like the two keys above. Omitted
    # entirely when no module stored anything, so a plain document's header does
    # not grow an empty object.
    var document_modules := canonical_module_data(document.module_data)
    if not document_modules.is_empty():
        header["modules"] = document_modules
    SaSadAssistants.write_header(header)
    preview_into(header, blobs, preview)
    # The Reference docker's boards, additive like the keys above and omitted
    # when there are none: paths and rectangles, and the pictures' own file
    # bytes beside them while Preferences keeps them in the file.
    SaSadReferencePictures.write_header(document.reference_boards, header, blobs, SaSettings.sad_keeps_reference_pictures)
    # The layer the painter had selected, additive like the keys above, so the
    # file opens on it rather than on the bottom of the stack.
    SaSadActiveLayer.write_header(document, header)
    # The filters attached to the document's root, in the shape a layer's are
    # written in below, and absent when there are none.
    if not document.root_filters.is_empty():
        header["filters"] = write_filters(document.root_filters, blobs, rd)
    return header


## The version a save of *document* is stamped with: 15 when two layers share
## a source, 13 when any layer carries a simulation, else 12, 11 or 10 when any
## layer is in a mode of `EXTENDED_ABOVE_WHITE`, the most any such mode gives,
## 9 when any layer is drawn through a live transform, 8 when any layer is an
## effect layer, 7 when any layer is an adjustment layer, 6 when any layer
## carries a height, 5 when any layer carries a mask or any node an attached
## filter, 4 for every other document.
##
## Not 5 for everything, because a reader refuses any version above its own
## outright, so an unconditional bump would stop an older build opening files
## that hold nothing it cannot read. Written this way a plain
## document keeps opening everywhere, and a masked one is refused by an older
## build with a sentence that names the version. An additive v4 key was the
## alternative and is rejected: an older build would open the file, carry a mask
## field it never composites, and show the wrong picture rather than none.
##
## The attached filter is in the question asked here, for the same reason: an
## older build that opened the file would show the picture without its
## filters and write it back without them.
##
## Height is in it for the mask's reason, and it takes a version of its own
## because the builds that read 5 are the ones that would misread it. Their
## schema loop loads the field and saves it back, so the texels survive, but
## they allocate it in every chunk, show the paint without its relief, and
## write a colour into it: a fill clears every field that is not the mask with
## the fill's colour, and a crop's white ground lands in it as a millimetre.
## A build that reads 5 refuses a 6 by name, and 0.12.1, which reads 4,
## refuses both.
##
## The adjustment layer takes 7 by the mask's own rule, since an older build
## would show the wrong picture. The recipe needs no key the older builds lack:
## the type id, the records, the mask, the mode and the opacity are all words
## version 5 has. The rejected alternative was to stamp it 5 for its records,
## as it would have been, and a build up to 0.16.3 then opens the file, keeps
## the type id it cannot resolve, draws nothing for a layer with no chunk, and
## shows the picture without the adjustment as if that were the painting. A
## build that reads 6 refuses a 7 by name instead.
##
## The effect layer takes 8 by the same rule. A build that reads 7 would keep
## the type id it cannot resolve and the records, read no chunk, since its cache
## is never written, and draw nothing where the effect shows.
##
## The live transform takes 9 by it too. A build that reads 8 would skip the
## key it does not know, open the layer where it was painted and show the
## wrong picture, then save it back without its map.
##
## A layer in a mode of `EXTENDED_ABOVE_WHITE` takes 10, for a picture that
## changed rather than for a word an older build lacks. Such a mode drew a
## value above white by its formula alone before the extension, so a build
## that reads 9 would show the older picture, and the version is also how this
## build knows a file was drawn that way: SaOlderReading names the layers whose
## picture changed when a file older than 10 is opened, and a file this build
## saved is never one. The rest of the separable display-referred modes take
## 11 by the same rule, and a version of their own because a file at 10 drew
## Screen the new way and them by the formula alone, so the stamp tells one
## from the other.
## Hue, Saturation, Colour and Lightness take 12 by the same rule, and a
## version of their own because a file at 11 drew the separable modes the new
## way and them inside the window, so the stamp tells one from the other.
##
## A simulation takes 13 for what an older build would lose rather than for the
## picture it would draw. A build that reads 12 would skip the key, show the
## layer's paint at its step, which is the right picture, and write the file
## back without the rule, the count and the seed, so Reset would have nothing to
## reach and the painter would not be told. It refuses a 13 by name instead.
static func version_for(document: SaDocument) -> int:
    if document == null:
        return SAD_VERSION_PLAIN
    var version := SAD_VERSION_PLAIN if document.root_filters.is_empty() else SAD_VERSION_MASKED
    for child in document.get_children():
        var layer := child as SaLayer
        if layer == null:
            continue
        if SaSimulation.record_of(layer) != null:
            version = maxi(version, SAD_VERSION_SIMULATION)
        if EXTENDED_ABOVE_WHITE.has(layer.blend_mode):
            version = maxi(version, EXTENDED_ABOVE_WHITE[layer.blend_mode])
        if SaSadDrawn.keeps_recipe(layer):
            version = maxi(version, SaSadDrawn.VERSION)
        if layer.live_transform != null:
            version = maxi(version, SaSadSharedSource.version_of(layer))
        elif layer.is_effect():
            version = maxi(version, SAD_VERSION_EFFECT)
        elif layer.is_adjustment():
            version = maxi(version, SAD_VERSION_ADJUSTMENT)
        elif layer.carries_height():
            version = maxi(version, SAD_VERSION_HEIGHT)
        elif layer.mask != null or SaFieldSpec.find(layer.schema, SaFieldSpec.MASK) != null or not layer.filters.is_empty():
            version = maxi(version, SAD_VERSION_MASKED)
    return version


## What a save of *document* stamps: [method version_for], what its features
## ask, and 14 above that when it holds any stored texture, whose blob is
## planes. Kept apart because the features' stamps still say what each one
## needs, and a document with no texture at all is opened by the build before.
static func stamp_for(document: SaDocument) -> int:
    var version := version_for(document)
    if document == null:
        return version
    if _masks_hold_textures(document.root_filters):
        return maxi(version, SAD_VERSION_PLANES)
    for child in document.get_children():
        var layer := child as SaLayer
        if layer != null and _holds_textures(layer):
            return maxi(version, SAD_VERSION_PLANES)
    return version


## Whether the save writes a blob for *layer*: a stored chunk, a chunk of a
## mask of its own or of an attached filter's, or a simulation's seed. The
## stamp of a document with none of them stays what its features ask, so a
## build that reads only to 13 still opens it.
static func _holds_textures(layer: SaLayer) -> bool:
    var stored := SaSceneLayer.stored_chunks(layer) if layer.is_scene() else SaEffectLayer.stored_chunks(layer)
    if not stored.is_empty():
        return true
    if layer.mask != null and layer.mask.is_own() and not layer.mask.grid_positions().is_empty():
        return true
    if _masks_hold_textures(layer.filters):
        return true
    var simulation := SaSimulation.record_of(layer)
    return simulation != null and not simulation.seed_chunks.is_empty()


## Whether a mask of its own on any of *records* holds a chunk.
static func _masks_hold_textures(records: Array[SaAttachedFilter]) -> bool:
    for record in records:
        if record.mask != null and record.mask.is_own() and not record.mask.grid_positions().is_empty():
            return true
    return false


## *texture* stored in *blobs*, its slot answered, for a feature that keeps textures in a layer's entry, a linked file's override.
static func write_texture(texture: SaTexture, blobs: PackedByteArray, rd: RenderingDevice) -> Dictionary[String, Variant]:
    return SaSadBlob.write(texture, blobs, rd)


## Fills *texture* from the *slot* [method write_texture] wrote, and answers whether it read.
static func read_texture(slot: Dictionary[String, Variant], blobs: PackedByteArray, texture: SaTexture) -> bool:
    var raw := SaSadBlob.read(slot, blobs, texture)
    return not raw.is_empty() and SaSadBlob.upload(texture, raw, SaSadBlob.is_planes(slot))


## A mask as it goes to disk, and the one writer of it: a layer's here, a
## group's and an attached filter's, so the board has one mask on disk and
## not two.
##
## `{"enabled": bool}` for a mask that is a field of its layer, whose coverage
## travels with the layer's chunks, and `"rest"` when a position it holds
## nothing at reads other than one, which a chunk the layer allocates opens at.
## A mask holding chunks of its own adds `"chunks"`, one Zstd blob each
## appended to *blobs* and addressed the way a layer's field is. An older build reads such a mask as one outside its chunks,
## which is the format's rule for a key it does not know.
static func write_mask(mask: SaMask, blobs: PackedByteArray, rd: RenderingDevice) -> Dictionary[String, Variant]:
    var entry: Dictionary[String, Variant] = {"enabled": mask.enabled}
    if mask.rest != 1.0:
        entry["rest"] = mask.rest
    if not mask.is_own():
        return entry
    var written: Array = []
    for grid_pos: Vector2i in mask.grid_positions():
        var texture := mask.texture_for(grid_pos)
        if texture == null or not texture.rid.is_valid() or SaSadSnapshot.leaves_out(texture):
            continue
        var slot := SaSadBlob.write(texture, blobs, rd, true)
        if slot.is_empty():
            continue
        slot.merge({"x": grid_pos.x, "y": grid_pos.y})
        written.append(slot)
    entry["chunks"] = written
    return entry


## The mask *entry* describes, as one holding chunks of its own, read out of
## *blobs*. An absent `"enabled"` reads as true. A chunk whose blob is out of
## range or will not decompress is left out, and so reads as one.
##
## A layer's field form needs none of this, because its coverage came in with
## its chunks: the loader sets the flag on the mask the schema gave the layer.
static func read_mask(entry: Dictionary[String, Variant], blobs: PackedByteArray) -> SaMask:
    var mask := SaMask.own()
    mask.enabled = SaTyped.bool_at(entry, "enabled", true)
    mask.rest = SaTyped.float_at(entry, "rest", 1.0)
    var rd := GlobalShaderCompiler.get_rd()
    if rd == null:
        return mask
    for raw_slot: Variant in entry.get("chunks", []):
        var slot := SaTyped.strings(raw_slot)
        var raw := SaSadBlob.read(slot, blobs)
        if raw.is_empty():
            push_warning("SaExport.load_sad: a mask chunk is out of range or failed to decompress")
            continue
        var texture := mask.get_or_create(Vector2i(SaTyped.int_at(slot, "x", 0), SaTyped.int_at(slot, "y", 0)))
        if not SaSadBlob.upload(texture, raw, SaSadBlob.opening(texture, slot, raw)):
            push_warning("SaExport.load_sad: a mask chunk's planes do not fit its texture")
    return mask


## A node's attached filters as they go to disk, bottom first: `key`, `params`,
## `enabled`, and a `mask` entry by `write_mask` when the record has one, so a
## filter's mask and a group's are one shape on disk. The parameters go through
## the JSON fixed point a module's data goes through, so the second save of an
## untouched document writes the bytes the first did.
static func write_filters(records: Array[SaAttachedFilter], blobs: PackedByteArray, rd: RenderingDevice) -> Array:
    var written: Array = []
    for record in records:
        var entry: Dictionary[String, Variant] = {
            "key": String(record.key),
            "params": canonical_module_data(record.parameters),
            "enabled": record.enabled,
        }
        if record.mask != null:
            entry["mask"] = write_mask(record.mask, blobs, rd)
        written.append(entry)
    return written


## The records *raw* describes, in the file's order. Anything but an array is a
## node with no filters, which is every file written before the key existed. An
## entry with no key is left out with a warning, and a key no installed module
## registers is kept as it is, to be written back on the next save.
static func read_filters(raw: Variant, blobs: PackedByteArray) -> Array[SaAttachedFilter]:
    var records: Array[SaAttachedFilter] = []
    if not raw is Array:
        return records
    for item: Variant in raw:
        var entry := SaTyped.strings(item)
        var key := str(entry.get("key", ""))
        if key.is_empty():
            push_warning("SaExport.load_sad: an attached filter names no key")
            continue
        var record := SaAttachedFilter.new(StringName(key), SaTyped.strings(entry.get("params", {})))
        record.enabled = SaTyped.bool_at(entry, "enabled", true)
        var mask_entry: Variant = entry.get("mask", null)
        if mask_entry is Dictionary:
            record.mask = read_mask(SaTyped.strings(mask_entry), blobs)
        records.append(record)
    return records


# ---------------------------------------------------------------------------
# .sad format: load
# ---------------------------------------------------------------------------


## Loads a .sad file from *path* into *document*, replacing its current layers.
## What the document held is let go of before the file's blobs are read, and a
## load that fails leaves it a new empty document, by [SaSadLettingGo].
##
## `document_compositor` is only needed when loading into a fresh SaDocument that
## does not have one yet, loading rebuilds the layer caches, which composites.
## Loading into the live document leaves it null, since that one is already wired.
static func load_file(document: SaDocument, path: String, document_compositor: SaCompositor = null) -> Error:
    return SaSadLettingGo.failed(document, _read_file(document, path, document_compositor))


static func _read_file(document: SaDocument, path: String, document_compositor: SaCompositor) -> Error:
    if document == null:
        push_error("SaExport.load_sad: document is null")
        return ERR_INVALID_PARAMETER
    if document_compositor != null:
        document.compositor = document_compositor
    if document.compositor == null:
        push_error("SaExport.load_sad: document has no compositor; pass one as document_compositor")
        return ERR_INVALID_PARAMETER
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        var open_err := FileAccess.get_open_error()
        push_error("SaExport.load_sad: cannot open '%s' for reading (err %d)" % [path, open_err])
        return open_err
    # The magic says whether this is a file Sara reads at all.
    var magic := file.get_buffer(4).get_string_from_ascii()
    if magic == SAD_MAGIC_V4:
        return SaSadOpening.new(document, file, path).whole()
    file.close()
    if magic == EARLY_MAGIC:
        push_error("SaExport.load_sad: '%s' was written by an early build that Sara no longer reads" % path)
        return ERR_FILE_UNRECOGNIZED
    push_error("SaExport.load_sad: not a valid .sad file - bad magic '%s'" % magic)
    return ERR_FILE_UNRECOGNIZED


## Opens the `.sad` at *path* into *document* as [method load_file] does, over
## as many frames as a file's layers take, and calls *then* with the error
## once the document holds it: within this call for a file that reads in one
## step, and for any refusal. `SaSadOpening` says
## why the window keeps drawing and why the document is untouched until then.
## *landed*, when given, is called once the stack is in the document with its
## chunks still to come, and answers the document's part the view shows,
## [method SaSadOpening.over_frames].
static func open_over_frames(document: SaDocument, path: String, then: Callable, landed: Callable = Callable()) -> void:
    var file := FileAccess.open(path, FileAccess.READ) if document != null and document.compositor != null else null
    if file == null or file.get_buffer(4).get_string_from_ascii() != SAD_MAGIC_V4:
        if file != null:
            file.close()
        then.call(load_file(document, path))
        return
    SaSadOpening.new(document, file, path).over_frames(
        func(error: Error) -> void: then.call(SaSadLettingGo.failed(document, error)), landed
    )


## Whether an open over frames is under way or has just landed, the frames
## the layer pictures wait out, as [method SaSadOpening.busy] says.
static func opening() -> bool:
    return SaSadOpening.busy()


## Whether an open over frames landed in *document* and still fills its chunks
## in, [method SaSadOpening.still_filling].
static func filling(document: SaDocument) -> bool:
    return SaSadOpening.still_filling(document) != null


## Whether *document* is still opening with chunks of its file not yet in,
## which the effect layers wait out before they refresh.
static func chunks_to_come(document: SaDocument) -> bool:
    var running := SaSadOpening.still_filling(document)
    return running != null and running.percent_in() < 100


## The corner's line for a press of *gesture* on *document* still opening,
## empty when it is not, [method SaSadOpening.refusal].
static func opening_refusal(document: SaDocument, gesture: String) -> String:
    return SaSadOpening.refusal(document, gesture)


## Fills in every chunk *document* still waits for, in this call, as a save
## does first, [method SaSadOpening.complete].
static func finish_opening(document: SaDocument) -> void:
    SaSadOpening.complete(document)


## The version the file at *path* was stamped with, read before it is opened:
## the container's word after the magic and
## 0 for a file that is not a .sad, which `load_file` then refuses.
static func version_at(path: String) -> int:
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        return 0
    var magic := file.get_buffer(4).get_string_from_ascii()
    var version := 0
    if magic == SAD_MAGIC_V4:
        version = file.get_32()
    file.close()
    return version


## The line that names the layers of *document*, opened from a file stamped
## *version*, that draw differently now, or an empty one. SaOlderReading says
## how they are found.
static func changed_since(document: SaDocument, version: int) -> String:
    return SaOlderReading.notice(SaOlderReading.changed(document, version))


## Uploads *raw*, the bytes of *slot*, into *texture* of a chunk stored at
## *stored*, or says why not of the field *where* names.
static func put_blob(
    texture: SaTexture, slot: Dictionary[String, Variant], raw: PackedByteArray, stored: float, where: String
) -> void:
    if raw.is_empty():
        push_warning("SaExport.load_sad: %s failed to decompress" % where)
        return
    # Only plain bytes can need widening, a chunk below 1.0 being plain.
    var planes := SaSadBlob.opening(texture, slot, raw)
    if not SaSadBlob.upload(texture, raw if planes else SaSadCoarseLayer.widened(raw, stored), planes):
        push_warning("SaExport.load_sad: %s does not fit its texture" % where)


# ---------------------------------------------------------------------------
# The steps the reader takes around `SaSadOpening`
# ---------------------------------------------------------------------------


## Drops the document's layers and resizes it, ready for a load to rebuild.
##
## Immediate .free() rather than queue_free, so new children can be added on the
## very next line without waiting a frame.
##
## The active layer and the mask target let go first. Freeing a layer fires the
## document's `child_exiting_tree` for it, and each `add_child` of the load fires
## `child_entered_tree`, and the layers docker answers both by reading the active
## layer. Left pointing at a layer this frees, it handed a freed object to a typed
## argument once per layer, a `SCRIPT ERROR` on every open. `_finish_load` sets
## the first loaded layer once the stack is whole.
##
## The selection is made afresh, as `reset_to_default` makes it. It belongs to the
## picture it was drawn over, and kept across an open it stood active over a
## picture it was never drawn on, a rectangle ready to mask the first stroke.
static func replace_layers(document: SaDocument, canvas_size: Vector2i) -> void:
    document.active_layer = null
    document.mask_target = null
    document.selection = SaSelection.new(Callable(document, &"get").bind(&"history"))
    for child in document.get_children():
        if child is SaLayer:
            child.free()
    # A file of any version replaces the root's filters with its own, and only
    # a version 5 one has any.
    document.root_filters.clear()
    # And is flat unless its header says otherwise, which only a v4 one can.
    document.projection = SaProjection.new()
    document.canvas_size = canvas_size
    # The cache layers are not serialised, so they have to be recreated here.
    _ensure_cache_layers(document)


## The projection kinds the running app registered, which a file's kind is read
## against. The reader is static and handed no registry, so it asks the main
## scene for its own, as `SaGeneratedLayer` does for a module's view shader.
## Null where no main scene holds any, a suite's, and a file's kind is then
## kept by its id and maps as flat.
static func running_kinds() -> SaProjection.Kinds:
    var tree := Engine.get_main_loop() as SceneTree
    var main_node: Node = tree.current_scene if tree != null else null
    if main_node == null or not ("registries" in main_node):
        return null
    var held: Variant = main_node.get("registries")
    var registries: SaRegistries = held if held is SaRegistries else null
    return registries.projections if registries != null else null


## Selects *active*, the layer the file was saved with active or else the first
## loaded one, and rebuilds the caches.
static func finish_load(document: SaDocument, active: SaLayer) -> Error:
    _join_groups(document)
    SaEffectLayer.join_inputs(document)
    SaSadSharedSource.join(document)
    if active != null:
        document.active_layer = active
    # Announced before the caches are rebuilt, because rebuilding them resolves
    # every layer and a derived field resolved by a hook that has not been
    # reattached yet is a blank field the compositor then reads.
    EventBus.document_loaded.emit(document)
    document.update_caches()
    document.composite_requested.emit()
    # Replacing the layers raised the flag on the way in. What is loaded is what
    # is on disk, so there is nothing unsaved. The path is the caller's to set.
    document.modified = false
    return OK


## Points every member at its group, by the name the header carried. A second
## pass, because a member may be written before the group it names. A name no
## layer has, or one that is not a group, leaves the member at the top level.
static func _join_groups(document: SaDocument) -> void:
    var by_name: Dictionary[String, SaLayer] = {}
    for child in document.get_children():
        if child is SaLayer:
            by_name[str(child.name)] = child
    for child in document.get_children():
        var layer := child as SaLayer
        if layer == null or not layer.has_meta("group_name"):
            continue
        var parent: SaLayer = by_name.get(str(layer.get_meta("group_name")), null)
        layer.remove_meta("group_name")
        layer.group = parent if parent != null and parent.is_group and parent != layer else null


## Makes sure the document's internal (non-serialised) cache layers exist.
static func _ensure_cache_layers(document: SaDocument) -> void:
    if document.stroke_layer == null:
        document.stroke_layer = SaLayer.new()
        document.stroke_layer.name = "StrokeBuffer"
    # The fold's caches were made for the document this one replaces, so they
    # go, and the next rebuild makes them at the loaded depth.
    if document.fold == null:
        document.fold = SaLayerFold.new()
    document.fold.release()

    # The caches carry no header entry, because they are rebuilt rather than
    # stored, so nothing in the file tells them what depth to allocate at. They
    # have to follow the document they were just loaded into.
    #
    # Set unconditionally rather than only on the branches above, because the
    # common case is a document that already has caches: opening an F16 file into
    # a session that was editing an F32 one would leave three layers at the old
    # depth, and every composite into them would be refused with "one dispatch
    # cannot serve both" while the load still reported success.
    var cache_schema := SaFieldSpec.schema_for_space(document.color_space)
    # Dropped before the schema changes, because it was allocated at whatever
    # the previous document was and is now the wrong depth.
    document.stroke_layer.release_chunks()
    document.stroke_layer.schema = cache_schema
