## What a module fills in to teach Sara a picture format: how a file of it is
## recognised, read and written, and what the Export dialog says about it.
##
## A format registers through [method SaContext.register_image_format] and
## lands on [member SaRegistries.image_formats], which File > Open, Import, a
## drop, the reference board, the welcome window's cards, the Export dialog,
## the simulation's frames and the door's `export` step all ask, none of them
## naming the format. The skeleton registers its four the same way a module
## does, from `core/loader/image_formats`.
##
## **Reading.** A flat format hands back one [Image] through [member reader]. A
## layered one, OpenRaster the first, opens a whole document through
## [member opener] and brings its layers into the open one through
## [member importer], which is why the two routes stay apart in File > Open. A
## format that recognises its own first bytes says so through [member claims],
## so a WebP called `.jpg` still reaches the WebP reader.
##
## **The colour.** [member linear] is the convention a file that names no gamut
## of its own is read by, linear sRGB for an EXR and a Radiance file and sRGB
## for the rest, and [member named_space] is the gamut a file names in its own
## bytes, a PNG's `cICP` chunk or an EXR's `chromaticities`. Below both is
## [member embedded_profile], the ICC profile a file carries.
##
## **Writing.** [member writer] takes the easel, the path and a [Write], the
## rows the dialog offers. The rest is what the dialog shows: the rows the
## format needs, its depths, the sentence about a value outside 0 to 1 with and
## without the rolloff, and for a layered format what the file loses.
##
## Nothing here is called per dab: a format is asked at an open, a drop, an
## export, or a dialog's row moving.
class_name SaImageFormat
extends RefCounted

## The rows of the Export dialog a format may ask for. The depth row is shown
## for a format with [member depths], and the rolloff for a depth that clips.
const ROW_QUALITY := &"quality"
const ROW_HALF := &"half"
const ROW_FLATTEN := &"flatten"
const ROW_DITHER := &"dither"
const ROW_RELIEF := &"relief"


## What the Export dialog hands a writer: every row's value, whether the format
## shows the row or not, since a writer reads only its own.
class Write:
    extends RefCounted

    ## The bits a channel the file is written at, one of [member depths] or the
    ## format's [member default_depth].
    var depth: int = 0
    ## A lossy format's quality, 0 to 1.
    var quality: float = 0.9
    ## Whether a float format writes halves.
    var half: bool = false
    ## Whether a value above 1 is rolled off rather than clipped.
    var rolloff: bool = false
    ## The gamut mapping, one of [SaGamutMapping]'s names.
    var mapping: String = SaGamutMapping.CLIP
    ## Whether the relief the view shows is lit into the picture.
    var relief: bool = false
    ## What a transparent area becomes in a file with no alpha.
    var flatten: Color = Color.WHITE
    ## Whether an eight-bit file is rounded through the dither.
    var dither: bool = false
    ## The display exposure ahead of the rolloff, in stops, the door's alone.
    var stops: float = 0.0


## The name the registry, a scenario and a dump know the format by, lower case.
var id: StringName = &""
## The name on screen, `PNG` or `OpenRaster`.
var label: String = ""
## The extensions a file of the format is named with, lower case and without
## the dot, which are what an open and a typed export name are read by.
var extensions: PackedStringArray = []

## `func(head: PackedByteArray) -> bool`, whether the first sixteen bytes of a
## file are this format's, or empty for a format known by its name alone.
var claims: Callable = Callable()
## `func(path: String) -> Image`, the picture, or null with the reason reported.
var reader: Callable = Callable()
## `func(path: String, document: SaDocument, depth: int) -> Error`, the file
## as the whole of *document*, at *depth* unless the file decides it.
var opener: Callable = Callable()
## `func(path: String, document: SaDocument) -> Array[SaLayer]`, the file's
## layers above the active one as one step, the layers that came in.
var importer: Callable = Callable()
## The open dialog's line for a layered format, `*.ora ; OpenRaster`. A flat
## format is listed under the one Image line the registry builds.
var open_filter: String = ""
## Whether a file of the format holds linear light, read as linear sRGB, rather
## than values through sRGB's curve.
var linear: bool = false
## `func(path: String) -> SaColorSpace`, the gamut the file names itself, null
## when it names none. Empty for a format that never names one.
var named_space: Callable = Callable()
## `func(path: String) -> PackedByteArray`, the ICC profile the file carries,
## empty when it carries none. Asked only when [member named_space] has no
## answer, and read by `SaIccProfile` into the gamut and curve the picture opens
## in, or the reason the Import Fit window gives for not using it.
var embedded_profile: Callable = Callable()

## `func(easel: SaEasel, path: String, options: SaImageFormat.Write) -> Error`.
var writer: Callable = Callable()
## The writer over frames, `func(easel: SaEasel, path: String, options:
## Write, then: Callable) -> void`, which calls *then* with the error once the
## file is whole. Empty for a format that writes in the frame it is asked,
## which [method write_picture_in_turns] then calls [member writer] for.
var writer_in_turns: Callable = Callable()
## What a typed name with no extension of this format gets, `.png`.
var suffix: String = ""
## The save dialog's line, `*.png ; PNG Image`.
var save_filter: String = ""
## The depth row's entries, `{"id": bits, "label": words}` each, in order, and
## empty for a format with no depth row.
var depths: Array = []
## The bits the file is written at before the painter touches the row, and the
## bits of a format with no row, 0 when its depth is a switch of its own.
var default_depth: int = 0
## The Export dialog's own rows the format shows, of the `ROW_` names.
var rows: Array[StringName] = []
## Whether the file keeps the layers rather than flattening the picture.
var keeps_layers: bool = false
## Whether the writer names the author, the date and Sara in the file.
var names_author: bool = false
## What the file does to a value outside 0 to 1 at its default depth, and the
## same with the rolloff on, empty for a format that never clips.
var note: String = ""
var note_rolled: String = ""
## The same two sentences for a depth they are not true of, by bits.
var depth_notes: Dictionary = {}
var depth_notes_rolled: Dictionary = {}
## The Result's first line, `Format: %s, %s` with the label and the depth.
var result_line: String = "Format: %s, %s"
## `func(document: SaDocument) -> PackedStringArray`, what a layered file
## loses of *document*, a sentence each. Empty for a flat format.
var losses: Callable = Callable()
## What a layered file says about the relief it leaves out.
var relief_loss: String = ""


func _init(format_id: StringName = &"", format_label: String = "") -> void:
    id = format_id
    label = format_label


## Whether a file of the format opens as one picture.
func reads() -> bool:
    return reader.is_valid()


## Whether a file of the format opens as a document with its layers.
func opens_layers() -> bool:
    return opener.is_valid()


## Whether Export writes the format.
func writes() -> bool:
    return writer.is_valid()


## Writes *easel* to *path* under *options*, which is how every export of a
## registered format is made: the Export dialog, a save's export targets, the
## simulation's frames and the door's `export` step all come here.
##
## The one call rather than [member writer] straight, because an export reads
## the picture back off the card and encodes it on the thread that asked, which
## holds the frame, and a place on the trail is what makes a stall in it say
## export rather than name whatever stood before.
func write_picture(easel: SaEasel, path: String, options: Write) -> Error:
    var ticket := SaTrail.enter("the export of %s" % path.get_file())
    var written: Error = writer.call(easel, path, options)
    SaTrail.give_back(ticket)
    return written


## Writes *easel* to *path* under *options* as [method write_picture] does, over
## frames where the format has [member writer_in_turns], and calls *then* with
## the error once the file is whole. A format with none is written now and
## *then* called before this returns. File > Export and the door's `export`
## step come here, so the painter goes on painting while a PNG is written.
func write_picture_in_turns(easel: SaEasel, path: String, options: Write, then: Callable) -> void:
    if not writer_in_turns.is_valid():
        then.call(write_picture(easel, path, options))
        return
    writer_in_turns.call(easel, path, options, then)


## Whether *path* ends in one of the format's extensions, case ignored.
func names(path: String) -> bool:
    return extensions.has(path.get_extension().to_lower())


## The sentence about a value outside 0 to 1 at *bits*, rolled off or not. A
## depth with a sentence of its own takes it, and the rolled sentence falls back
## to the plain one for a format the rolloff changes nothing in.
func note_at(bits: int, rolled: bool) -> String:
    if not rolled:
        var said: String = depth_notes.get(bits, note)
        return said
    var plain := note_rolled if not note_rolled.is_empty() else note
    var rolled_note: String = depth_notes_rolled.get(bits, plain)
    return rolled_note


## Whether the file clips a value outside 0 to 1 at *bits*, which is what the
## rolloff offers an alternative to: a depth with a rolled sentence, or a
## format with one.
func clips(bits: int) -> bool:
    return depth_notes_rolled.has(bits) or not note_rolled.is_empty()


## The ids of the depth row's entries.
func depth_ids() -> Array[int]:
    var ids: Array[int] = []
    for entry: Dictionary in depths:
        var depth_id: int = entry["id"]
        ids.append(depth_id)
    return ids
