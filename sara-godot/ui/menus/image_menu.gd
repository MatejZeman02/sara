## The Image menu: Image Size, Canvas Size and Crop to Selection, the flips
## and the turns of the whole picture, then the colour space and projection
## dialogs and the document's gamut and depth, with the DPI and the adjustments
## still to come.
##
## Every row above the gamut is a list of commands, and only the gamut and depth
## rows, which follow the document, are built here.
class_name SaImageMenu
extends SaMenu

const ID_COLOR_SPACE := 300
const ID_CROP_TO_SELECTION := 301
const ID_CANVAS_SIZE := 302
const ID_IMAGE_SIZE := 303
const ID_FLIP_HORIZONTAL := 304
const ID_FLIP_VERTICAL := 305
const ID_ROTATE_CLOCKWISE := 306
const ID_ROTATE_ANTICLOCKWISE := 307
const ID_ROTATE_180 := 308
const ID_PROJECTION := 309

## One row per gamut from here up, in the order of [constant GAMUT_PROFILES].
const ID_GAMUT_BASE := 310

## The gamuts a document is changed to from this menu, by the profile ids the
## Display page names a screen with, because a document and the screen it is
## painted on are meant to be able to agree.
const GAMUT_PROFILES: Array[String] = ["srgb", "display_p3", "rec2020"]

## One row per depth from here up, in the order of [constant DEPTHS].
const ID_DEPTH_BASE := 320

## The depths a document is converted to from this menu, half first.
const DEPTHS: Array[SaColorSpace.Depth] = [SaColorSpace.Depth.F16, SaColorSpace.Depth.F32]

## The tick beside the depth rows that turns the rounding at save on and off.
const ID_ROUNDING := 330
## The tick's hint. The sizes are measured on three
## paintings.
## three paintings.
const ROUNDING_HINT := (
    "Rounds full precision colour to 12 significant bits at every save, which no eye can see. "
    + "Off, every later save keeps every bit, and no bit an earlier save rounded comes back. "
    + "The colour then takes five to six times the space, 89 MB against 16 MB on three paintings, "
    + "57 MB against 9 MB as JPEG XL."
)

## The question going to half asks when no value is past its range. Every
## clause of it is a behaviour a suite in `core/image/precision/tests/` holds
## against the document.
const HALF_QUESTION := (
    "Convert this document to 16-bit float, half precision? Every colour keeps its value to the precision of a half float, "
    + "the file gets smaller by about half, and the old chunks are held for the undo. "
    + "A value smaller than about 0.00000006 becomes zero, which loses precision and not range."
)

## Added to [constant HALF_QUESTION] when the count found texels past the range,
## formatted with the count.
const HALF_RANGE := (
    " %d texels hold a value beyond 65504, the largest a half float holds. "
    + "They are kept at 65504, with their sign, and not turned to infinity."
)

## The question going to full precision asks, where nothing is lost.
const FULL_QUESTION := (
    "Convert this document to 32-bit float, full precision? Every colour keeps its value exactly, "
    + "the file gets about twice as large, and the old chunks are held for the undo."
)

## Added to either question when the step does not fit the undo history beside
## the steps it holds.
const HISTORY_FULL := " The undo history is full, so the oldest steps are dropped to make room, and this one can still be undone."

## The question a gamut row asks, formatted with the gamut the document leaves,
## the one it goes to and that one again. Every clause of it is a behaviour
## `core/export/tests/test_convert_keeps_the_canvas_and_clips_the_png.gd` holds against
## the pixels, so the sentence cannot promise what Convert does not do again.
const GAMUT_QUESTION := (
    "Convert this document from %s to %s? Every colour keeps its value, so the canvas looks the same. "
    + "A PNG or JPEG export clips the colours outside %s, and a TIFF or EXR export keeps them."
)


func _add_items() -> void:
    add_commands(
        [
            [ID_IMAGE_SIZE, &"image_size"],
            [ID_CANVAS_SIZE, &"image_canvas_size"],
            [ID_CROP_TO_SELECTION, &"image_crop_to_selection"],
            LINE,
            [ID_FLIP_HORIZONTAL, &"image_flip_horizontal"],
            [ID_FLIP_VERTICAL, &"image_flip_vertical"],
            [ID_ROTATE_CLOCKWISE, &"image_rotate_clockwise"],
            [ID_ROTATE_ANTICLOCKWISE, &"image_rotate_anticlockwise"],
            [ID_ROTATE_180, &"image_rotate_180"],
            LINE,
            [ID_COLOR_SPACE, &"image_color_space"],
            [ID_PROJECTION, &"image_projection"],
        ]
    )
    _add_gamut_items()
    _add_depth_items()


## The gamut a picked colour means, one row per gamut with the document's own
## drawn as the chosen one, so the menu says which it is as well as changing it.
## Rebuilt on every open with the rest of the menu, so it follows a File New and
## a conversion without a subscription.
func _add_gamut_items() -> void:
    add_heading(tr("Gamut"))
    var document := main_document()
    var current: SaGamut = document.color_space.gamut() if document != null and document.color_space != null else null
    for i in GAMUT_PROFILES.size():
        var gamut := SaSettingsProofs.space_for(GAMUT_PROFILES[i]).gamut()
        add_item(tr(gamut.display_name), ID_GAMUT_BASE + i)
        explain(ID_GAMUT_BASE + i, "Converts the document into this gamut, after a question saying which exports clip.")
        if current != null and current.matches(gamut):
            popup.set_current(key(ID_GAMUT_BASE + i))


## How many bits a channel gets, one row per depth with the document's own drawn
## as the chosen one, built on every open as the gamut rows are.
func _add_depth_items() -> void:
    add_heading(tr("Depth"))
    var document := main_document()
    for i in DEPTHS.size():
        add_item(tr(SaColorSpace.depth_name(DEPTHS[i])), ID_DEPTH_BASE + i)
        explain(ID_DEPTH_BASE + i, "Converts every colour of the document to this depth, after a question saying what it keeps.")
        if document != null and document.color_space != null and document.color_space.depth == DEPTHS[i]:
            popup.set_current(key(ID_DEPTH_BASE + i))
    # Offered on a full precision document only, since a save rounds nothing
    # at half precision, and dimmed there rather than gone so it is found.
    var space := document.color_space if document != null else null
    var full := space != null and space.depth == SaColorSpace.Depth.F32
    add_check_item(tr("Round Colour at Save"), ID_ROUNDING, space == null or space.rounds_at_save, not full)
    explain(ID_ROUNDING, tr(ROUNDING_HINT))


## The gamut and depth rows and the rounding tick, which run no command: there
## is one per gamut and per depth and the list is the menu's own.
func _pressed(id: int) -> void:
    if id == ID_ROUNDING:
        var document := main_document()
        if document != null and document.color_space != null:
            SaSadSnapshot.choose_rounding(document, not document.color_space.rounds_at_save)
        return
    if id >= ID_DEPTH_BASE and id < ID_DEPTH_BASE + DEPTHS.size():
        # Deferred for the gamut's reason below.
        ask_depth.call_deferred(DEPTHS[id - ID_DEPTH_BASE])
        return
    if id >= ID_GAMUT_BASE and id < ID_GAMUT_BASE + GAMUT_PROFILES.size():
        # Deferred, because the question is a window that takes focus, and
        # popping one from inside a popup's own signal handler runs while the
        # popup is still mid-hide.
        ask_gamut.call_deferred(SaSettingsProofs.space_for(GAMUT_PROFILES[id - ID_GAMUT_BASE]).gamut())


## Asks before converting the document into *gamut*, and answers the question it
## put up, or null when there was nothing to ask.
##
## A conversion keeps every colour where it was, and the stored values are not
## clamped (hard rule 5). The canvas draws a document through linear sRGB into
## the display profile, so it shows the same picture after Convert as before,
## and the question promises no clip on screen. What does clip is an eight-bit export: PNG and JPEG are written in the document's
## gamut, so a colour outside the new one is clamped a channel at a time, while a
## TIFF keeps its floats sign and all and an EXR writes the stored numbers.
## [constant GAMUT_QUESTION] says that, because it is the part a painter cannot
## see coming. The document's own gamut and one the conversion refuses ask
## nothing: the first is no change and the second says why in the corner.
func ask_gamut(gamut: SaGamut) -> SaMessage:
    var document := main_document()
    if document == null or document.color_space == null or document.color_space.gamut().matches(gamut):
        return null
    var target := document.color_space.with_gamut(gamut)
    var blocked := SaColorConversion.new(document).blocked_reason(target)
    if not blocked.is_empty():
        SaMessage.notice(tr("The gamut cannot change: %s") % blocked)
        return null
    return SaMessage.confirm(
        host(),
        tr("Change Gamut"),
        tr(GAMUT_QUESTION) % [document.color_space.gamut().display_name, gamut.display_name, gamut.display_name],
        PackedStringArray([tr("Cancel"), tr("Convert")]),
        _on_gamut_answered.bind(document, target),
        0,
        1
    )


func _on_gamut_answered(index: int, document: SaDocument, target: SaColorSpace) -> void:
    if index == 1 and is_instance_valid(document):
        SaColorConversion.new(document).convert_to(target)


## Asks before converting the document to *depth*, and answers the question it
## put up, or null when there was nothing to ask: the document's own depth is
## no change. *of* is the main canvas's document unless a suite hands one.
##
## Going to half counts first, on the card, the texels with a finite value a
## half cannot hold, and the question says how many and that they are held at
## 65504 with Cancel as its first button. The count goes to the log as well, in
## a line a scenario reads. Going to float loses nothing and counts nothing.
func ask_depth(depth: SaColorSpace.Depth, of: SaDocument = null) -> SaMessage:
    var document := of if of != null else main_document()
    if document == null:
        return null
    var precision := SaPrecision.new(document)
    var blocked := precision.blocked_reason(depth)
    if not blocked.is_empty():
        if document.color_space == null or document.color_space.depth != depth:
            SaMessage.notice(tr("The depth cannot change: %s") % blocked)
        return null
    var text := tr(FULL_QUESTION)
    if depth == SaColorSpace.Depth.F16:
        var beyond := precision.count_beyond_half()
        print("Image > Depth: %d texels hold a value beyond 65504" % beyond)
        text = tr(HALF_QUESTION)
        if beyond > 0:
            text += tr(HALF_RANGE) % beyond
    if precision.drops_older_steps(depth):
        text += tr(HISTORY_FULL)
    return SaMessage.confirm(
        host(),
        tr("Change Depth"),
        text,
        PackedStringArray([tr("Cancel"), tr("Convert")]),
        _on_depth_answered.bind(document, depth),
        0,
        1
    )


func _on_depth_answered(index: int, document: SaDocument, depth: SaColorSpace.Depth) -> void:
    if index == 1 and is_instance_valid(document):
        SaPrecision.new(document).convert_to(depth)
