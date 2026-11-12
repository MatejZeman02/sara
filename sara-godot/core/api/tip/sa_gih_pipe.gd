## Reads GIMP's `.gih`, an animated pipe, as a list of tips and its parasite.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## **Written from the format, not ported.** A `.gih` is three things one after
## another: a UTF-8 name line, a parameter line, and then one whole `.gbr` per
## tip concatenated with nothing between them. That is the entire container, so
## this file is a line reader, a `key:value` reader and a loop over
## [method SaTipImage.gbr_at], which is the GBR reader, given an offset and a
## length so a second tip can start where the first one stopped.
##
## **This reads and binds nothing.** Nothing here chooses a tip, touches a dab
## or reaches a kernel: `SaBrushTipMask.advance` moves a pipe along a stroke,
## and it reads [member Pipe.selections] and [member Pipe.ranks] to do it.
## Keeping the two apart means the file format and the stroke behaviour are two
## records and two proofs, and it means a reader that is wrong about the format
## fails in a test rather than as a stroke that paints the wrong picture.
##
## **What the parameter line's fields mean**, which is the half of the format a
## reader has to know and the half that is documented nowhere in the file:
##
## - `ncells`, how many `.gbr` tips follow. It is written twice, once as the
##   bare first token of the line and once as this key, and this reader refuses
##   a file where the two disagree rather than believing one of them.
## - `dim`, how many dimensions the collection is indexed by, 1 to
##   [constant MAX_DIMENSIONS]. Almost every pipe in the wild is 1.
## - `rank0` to `rank3`, how many tips each dimension holds. They multiply to
##   `ncells`, which is the check that a rank was not misread.
## - `sel0` to `sel3`, **how a dab picks a tip along that dimension**, one of
##   [constant SELECTIONS]. This is the field the stroke acts on, and the one
##   GIMP's dialog calls "selection": `incremental` steps one per dab, `angular` picks by the
##   stroke's direction, `random` picks by a stream, `velocity` by speed,
##   `pressure`, `xtilt` and `ytilt` by the tablet, and `constant` never moves.
## - `placement`, which is **not** that. It says how the cells were laid out in
##   the GIMP image the pipe was cut from, `constant` for a regular grid and
##   `default` for whatever the layers gave, so it is a fact about the file's
##   own making and nothing a stroke reads.
## - `cellwidth`, `cellheight`, `cols`, `rows`, the same story: the source
##   image's grid, kept because a reader that drops fields cannot be checked
##   against the file it read.
## - `step`, the spacing as a percentage, the same number a version 2 GBR
##   carries. Each tip carries its own too, so this is the collection's word
##   over the tips' and `SaBrushTipMask` decides which wins.
##
## Every field lands in [member Pipe.parameters] as written, so a key this
## reader has no opinion about survives to be read later rather than being
## dropped on the way in.
class_name SaGihPipe
extends RefCounted

## The line separator the format uses. GIMP writes a bare newline, and a file
## that travelled through a Windows tool arrives with a carriage return in front
## of it, which [method _line] trims: a name of "Vine\r" is a name nobody typed.
const NEWLINE: int = 0x0A
const CARRIAGE_RETURN: int = 0x0D

## The most dimensions a pipe is indexed by, which is GIMP's own `PIPE_MAXDIM`
## and the reason there are four `rank` and four `sel` keys and no more.
const MAX_DIMENSIONS: int = 4

## The most tips a file is believed to hold. The count is read out of a text
## line, so a corrupt or mistyped file can ask for millions of tips and this is
## the number above which the reader stops rather than looping. A thousand and
## twenty-four is far past the largest pipe GIMP ships, which is a hundred.
##
## Refused rather than clamped, for the reason `sa_tip_image.gd` refuses an
## impossible spacing: a clamp reads something plausible and hides the misread.
const MAX_CELLS: int = 1024

## How a dab picks a tip along one dimension. GIMP's set, in GIMP's spelling,
## and the whole of it: a mode outside this list is a file this reader does not
## understand, and saying so is more use than quietly falling back to
## `constant`, which is a pipe that never advances for a reason nothing reports.
const SELECTIONS: Array = ["constant", "incremental", "angular", "velocity", "random", "pressure", "xtilt", "ytilt"]

## The selection a dimension gets when the file names none. `constant` is what
## GIMP assumes, and it is the mode that changes nothing.
const SELECTION_WHEN_UNSTATED: String = "constant"

## How the cells were laid out in the image the pipe was cut from. Not a mode a
## stroke reads, and kept because refusing a value the field may hold is the
## only way to notice that the parameter line was misread.
const PLACEMENTS: Array = ["constant", "default"]

## The placement a silent file gets, which is GIMP's own default.
const PLACEMENT_WHEN_UNSTATED: String = "constant"

## What Krita writes for a placement it never had, a null string through C's
## printf. Twenty-one of the pipes in Krita's own default bundles say it, in
## either case, and each is a file that stated no placement, so it reads as
## [constant PLACEMENT_WHEN_UNSTATED] rather than as a value to refuse, which
## would leave every such pipe preset to be imported bare.
const PLACEMENT_NULL: String = "(null)"

## The keys whose value is a number, checked before any of them is read, so a
## `rank0:many` is a refusal naming the field rather than a rank of zero.
const NUMERIC_KEYS: Array = [
    "ncells", "dim", "cellwidth", "cellheight", "cols", "rows", "step", "rank0", "rank1", "rank2", "rank3"
]


## One pipe, or one refusal. `error` empty means the rest is real, which is the
## shape [SaTipImage.Tip] has and for the same reason: a caller that misspells a
## key on a Dictionary gets null and no report.
class Pipe:
    extends RefCounted

    ## The pipe's own name, off the first line, or the file's base name when
    ## that line is empty.
    var pipe_name: String = ""

    ## The tips, in file order, each a [SaTipImage.Tip] that loaded.
    var tips: Array = []

    ## How many tips the parameter line promised, which is [member tips] size on
    ## anything that loaded and is worth keeping apart from it in a refusal.
    var cell_count: int = 0

    ## Every `key:value` of the parameter line, as written, values as text.
    var parameters: Dictionary[String, String] = {}

    ## `dim`, and the length of both arrays below.
    var dimension: int = 1

    ## `rank0` upwards, one per dimension, multiplying to [member cell_count].
    var ranks: PackedInt32Array = PackedInt32Array()

    ## `sel0` upwards, one per dimension. **The field a stroke
    ## reads.**
    var selections: PackedStringArray = PackedStringArray()

    ## `placement`, the source image's grid rather than a stroke's mode.
    var placement: String = PLACEMENT_WHEN_UNSTATED

    ## Where each tip's GBR starts in the bytes it was read from, found by
    ## [method SaGihPipe.read_head] from the headers alone. Shorter than
    ## [member cell_count] when a header says something the walk cannot step
    ## past, and the tip there is the one whose read says why.
    var offsets: PackedInt64Array = PackedInt64Array()

    ## Why this is not a pipe. Empty on success.
    var error: String = ""

    func ok() -> bool:
        return error.is_empty() and not tips.is_empty()


## Loads *path* by its extension, the one door, the way `SaTipImage` has one.
static func load_from(path: String) -> Pipe:
    if not path.to_lower().ends_with(".gih"):
        return _refuse(TranslationServer.translate("%s is not a GIMP pipe. A pipe is a .gih.") % path.get_file())
    var bytes := FileAccess.get_file_as_bytes(path)
    if bytes.is_empty():
        return _refuse(TranslationServer.translate("%s could not be read.") % path.get_file())
    return read_bytes(bytes, path.get_file())


## The from-bytes door beside it, which is the one a Krita preset needs: a
## `.gih` arrives inside a `.kpp` as base64 and never touches a disk.
##
## *file_name* is what every refusal quotes, so a painter reads the tip's name
## out of the preset rather than the preset's path. It is [method read_head]
## and then [method read_cell] for every tip in file order, which is the first
## refusal in file order when there is one.
static func read_bytes(bytes: PackedByteArray, file_name: String) -> Pipe:
    var pipe := read_head(bytes, file_name)
    if not pipe.error.is_empty():
        return pipe
    for index in pipe.cell_count:
        var tip := read_cell(bytes, pipe, index, file_name)
        if not tip.ok():
            return _refuse(tip.error)
        pipe.tips.append(tip)
    return pipe


## The name line and the parameter line of *bytes*, and where every tip starts,
## without reading any tip's texels. A pipe whose `error` says why, or one with
## no tips yet whose [member Pipe.offsets] [method read_cell] reads them at.
##
## **Apart from the tips because the tips are the cost and each is its own.**
## A tip's texels are a loop over every one of them, and a pipe of hundreds of
## large tips takes most of a second of one thread to read. The next tip
## starts where this one's header says it stops, so the walk is a few
## numbers a tip, and with the starts known `SaTipCache` reads each tip's header
## and sends its bytes to the card as they stand.
static func read_head(bytes: PackedByteArray, file_name: String) -> Pipe:
    if bytes.is_empty():
        return _refuse(
            TranslationServer.translate("%s is empty, and a pipe is a name, a parameter line and its tips.") % file_name
        )
    var first := bytes.find(NEWLINE)
    if first < 0:
        return _refuse(TranslationServer.translate("%s has no line break at all, so it carries no name line.") % file_name)
    var second := bytes.find(NEWLINE, first + 1)
    if second < 0:
        return _refuse(TranslationServer.translate("%s stops after its name line and carries no parameter line.") % file_name)

    var pipe := Pipe.new()
    pipe.pipe_name = _line(bytes, 0, first)
    if pipe.pipe_name.is_empty():
        pipe.pipe_name = file_name.get_basename()
    var reason := _read_parameters(pipe, _line(bytes, first + 1, second), file_name)
    if not reason.is_empty():
        return _refuse(reason)

    # Each tip is a whole GBR, header and all, so the next one starts exactly
    # where this one stops, which is its header's length and its texels'. A
    # header the walk cannot step past ends it there, and that tip's own read
    # refuses it in the words the GBR reader has for it.
    var at := second + 1
    for index in pipe.cell_count:
        pipe.offsets.append(at)
        if bytes.size() - at < SaTipImage.GBR_V1_HEADER_BYTES:
            break
        var header := _be_u32(bytes, at)
        var width := _be_u32(bytes, at + 8)
        var height := _be_u32(bytes, at + 12)
        var depth := _be_u32(bytes, at + 16)
        if header <= 0 or width <= 0 or height <= 0 or (depth != 1 and depth != 4):
            break
        at += header + width * height * depth
    return pipe


## Tip *index* of *pipe*, read from *bytes* at the start [method read_head]
## found, or a tip whose `error` is the pipe's refusal naming it.
##
## *with_texels* false reads the cell's header alone, its size, spacing and
## depth, and is what `SaTipCache` reads, since it sends the cell's own bytes to
## the card and has them made into the tip there.
static func read_cell(
    bytes: PackedByteArray, pipe: Pipe, index: int, file_name: String, with_texels: bool = true
) -> SaTipImage.Tip:
    var at: int = pipe.offsets[index] if index < pipe.offsets.size() else -1
    var tip: SaTipImage.Tip = SaTipImage.gbr_at(bytes, at, file_name, with_texels)
    if not tip.ok():
        tip.error = (
            TranslationServer.translate("%s stops in tip %s of %s: %s") % [file_name, index + 1, pipe.cell_count, tip.error]
        )
    return tip


## The parameter line into *pipe*, answering the reason it could not be read or
## an empty string.
##
## A reason rather than a bool because every one of these is a sentence a
## painter is shown, and building it where the field is read is the only way it
## can name the field.
static func _read_parameters(pipe: Pipe, line: String, file_name: String) -> String:
    var tokens := line.replace("\t", " ").split(" ", false)
    if tokens.is_empty():
        return TranslationServer.translate("%s has an empty parameter line, which starts with the number of tips.") % file_name
    if not tokens[0].is_valid_int():
        return (
            TranslationServer.translate('%s starts its parameter line with "%s" rather than the number of tips.')
            % [file_name, tokens[0]]
        )
    pipe.cell_count = int(tokens[0])
    if pipe.cell_count <= 0:
        return (
            TranslationServer.translate("%s says it holds %s tips, and a pipe needs at least one.") % [file_name, pipe.cell_count]
        )
    if pipe.cell_count > MAX_CELLS:
        return (
            TranslationServer.translate("%s says it holds %s tips, above the %s a pipe may say.")
            % [file_name, pipe.cell_count, MAX_CELLS]
        )

    for index in range(1, tokens.size()):
        var token := tokens[index]
        var colon := token.find(":")
        if colon <= 0 or colon >= token.length() - 1:
            return (
                TranslationServer.translate('%s carries "%s" on its parameter line, which is not a key:value pair.')
                % [file_name, token]
            )
        pipe.parameters[token.substr(0, colon)] = token.substr(colon + 1)

    for key: String in NUMERIC_KEYS:
        if pipe.parameters.has(key) and not String(pipe.parameters[key]).is_valid_int():
            return (
                TranslationServer.translate("%s says %s:%s, and %s is a whole number.")
                % [file_name, key, pipe.parameters[key], key]
            )
    if pipe.parameters.has("ncells") and int(pipe.parameters["ncells"]) != pipe.cell_count:
        return (
            TranslationServer.translate("%s counts %s tips at the start of its parameter line and ncells:%s after it.")
            % [file_name, pipe.cell_count, int(pipe.parameters["ncells"])]
        )

    pipe.dimension = SaTyped.int_at(pipe.parameters, "dim", 1)
    if pipe.dimension < 1 or pipe.dimension > MAX_DIMENSIONS:
        return (
            TranslationServer.translate("%s says dim:%s, and a pipe is indexed by 1 to %s dimensions.")
            % [file_name, pipe.dimension, MAX_DIMENSIONS]
        )
    return _read_dimensions(pipe, file_name)


## The `rank` and `sel` pair of every dimension, once `dim` is known to be one.
##
## Apart from the caller because the two together are one function with eleven
## branches, and because this half is the half a stroke reads.
static func _read_dimensions(pipe: Pipe, file_name: String) -> String:
    var product := 1
    for index in pipe.dimension:
        var rank_key := "rank%d" % index
        if not pipe.parameters.has(rank_key):
            return TranslationServer.translate("%s says dim:%s and carries no %s.") % [file_name, pipe.dimension, rank_key]
        var rank := int(pipe.parameters[rank_key])
        if rank <= 0:
            return (
                TranslationServer.translate("%s says %s:%s, and a dimension holds at least one tip.")
                % [file_name, rank_key, rank]
            )
        pipe.ranks.append(rank)
        product *= rank
        var selection := SaTyped.text_at(pipe.parameters, "sel%d" % index, SELECTION_WHEN_UNSTATED)
        if not SELECTIONS.has(selection):
            return (
                TranslationServer.translate("%s says sel%s:%s, and a pipe selects by %s.")
                % [file_name, index, selection, ", ".join(PackedStringArray(SELECTIONS))]
            )
        pipe.selections.append(selection)
    if product != pipe.cell_count and pipe.dimension == 1:
        # One dimension holds every tip, so its rank says nothing the count
        # does not, and the tips that follow are the file's own evidence. Krita
        # ships a pipe of three tips that says rank0:5, Texture_leaves_fuzzy's,
        # and paints it, so the rank takes the count. With two dimensions or
        # more the ranks say how the tips are laid out, and a wrong one is a
        # misread nothing can repair, so that stays refused.
        pipe.ranks[0] = pipe.cell_count
    elif product != pipe.cell_count:
        return (
            TranslationServer.translate("%s holds %s tips and its ranks multiply to %s.") % [file_name, pipe.cell_count, product]
        )

    pipe.placement = SaTyped.text_at(pipe.parameters, "placement", PLACEMENT_WHEN_UNSTATED)
    if pipe.placement.to_lower() == PLACEMENT_NULL:
        pipe.placement = PLACEMENT_WHEN_UNSTATED
    if not PLACEMENTS.has(pipe.placement):
        return (
            TranslationServer.translate("%s says placement:%s, and a GIH is laid out %s.")
            % [file_name, pipe.placement, " or ".join(PackedStringArray(PLACEMENTS))]
        )
    return ""


## The first `sel` mode a pipe's parameter line names that [constant SELECTIONS]
## does not cover, or empty when every named mode is one Sara reads.
##
## `read_bytes` refuses a pipe outright on such a mode, because a mode that
## silently did nothing would be a pipe that never advances for a reason nothing
## reports. A reader with only that refusal cannot say *which* mode it was, so
## the importer calls this to tag a preset with the mode it lost rather than
## with the whole tip.
static func unknown_selection(bytes: PackedByteArray) -> String:
    var first := bytes.find(NEWLINE)
    var second := bytes.find(NEWLINE, first + 1)
    if first < 0 or second < 0:
        return ""
    var tokens := _line(bytes, first + 1, second).replace("\t", " ").split(" ", false)
    if tokens.size() < 2:
        return ""
    var dimension := 1
    var selections: Dictionary[String, String] = {}
    for index in range(1, tokens.size()):
        var colon := tokens[index].find(":")
        if colon <= 0 or colon >= tokens[index].length() - 1:
            continue
        var key := tokens[index].substr(0, colon)
        var value := tokens[index].substr(colon + 1)
        if key == "dim" and value.is_valid_int():
            dimension = clampi(int(value), 1, MAX_DIMENSIONS)
        elif key.begins_with("sel") and key.trim_prefix("sel").is_valid_int():
            selections[key] = value
    for index in dimension:
        var selection := SaTyped.text_at(selections, "sel%d" % index, SELECTION_WHEN_UNSTATED)
        if not SELECTIONS.has(selection):
            return selection
    return ""


## The big-endian word at *at*, the way every GBR header field is written.
static func _be_u32(bytes: PackedByteArray, at: int) -> int:
    if at + 4 > bytes.size():
        return 0
    return (bytes[at] << 24) | (bytes[at + 1] << 16) | (bytes[at + 2] << 8) | bytes[at + 3]


## One line of *bytes*, without the carriage return a Windows tool leaves.
static func _line(bytes: PackedByteArray, from: int, to: int) -> String:
    var stop := to
    if stop > from and bytes[stop - 1] == CARRIAGE_RETURN:
        stop -= 1
    return bytes.slice(from, stop).get_string_from_utf8()


static func _refuse(reason: String) -> Pipe:
    var pipe := Pipe.new()
    pipe.error = reason
    return pipe
