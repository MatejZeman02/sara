## The magic wand: a click selects the contiguous region of colour
## around it, within a tolerance, from the merged picture or the active
## layer alone, in the mode the bar says. With Contiguous off it selects every
## texel of that colour, joined to the click or not.
##
## The flood itself is `sa_wand.gd` beside this file, one chunk at a time on
## the GPU, and so is the match of every texel the bucket fill's Contiguous off
## uses. This holds the options and hands the click over. Shift on the press
## adds, Alt subtracts and both intersect, as with the marquee and the lasso.
extends ToolState

## By path rather than by `class_name`, because the engine sits beside this
## file and a module's own files are reached the way its tests reach them,
## without waiting on the class cache.
const SaWandScript = preload("res://modules/sara-base-modules/base/wand/sa_wand.gd")
const SelectionChord = preload("res://modules/sara-base-modules/base/tools/selection_chord.gd")

## How far a colour may sit from the seed's, per channel, and still join.
## The `wand_tolerance` option.
var tolerance: float = 0.1
## Whether a click selects only the region joined to it, or every texel within
## the tolerance wherever it is, which is what the Select menu's Colour Range does.
## The `wand_contiguous` option, on by default as the fill's is.
var contiguous: bool = true
## Whether the flood reads every layer as shown or the active one alone.
## The `sample_merged` option, shared with the eyedropper.
var sample_merged: bool = true
## The `selection_mode` option, shared with the marquee and the lasso.
var mode: int = SaSelection.Mode.REPLACE
## How soft the edge of a selection this tool makes anew is, as a fraction of
## the canvas's smaller dimension. The `feather` option, a Tool Options docker
## row, and beside the Select menu's Feather, which sets the same live amount
## on a selection that already exists.
##
## It becomes the selection's feather amount when a shape replaces the
## selection. A shape added, subtracted or intersected goes into the hard mask
## and leaves the amount as it is, so the selection is feathered once from its
## hard mask and never once more for each shape (`SaSelection.feather`).
##
## A view of `SaSettings.selection_feather` rather than a value of its own, so
## the three selection tools show one Feather, the fraction means the same
## softness after a document is upgraded to 4K, and the painter's choice
## outlives the session.
var feather: float:
    set(value):
        SaInHand.Settings.write(&"selection_feather", value)
    get:
        return SaInHand.Settings.read(&"selection_feather")

var _wand: SaWandScript = SaWandScript.new()
## The pointer's marks for the chord.
var _chord: SelectionChord = SelectionChord.new()


## A click is over as it lands, so the row and the pointer show what Shift and
## Alt down now would give the next one, the mode the marquee shows between
## its drags.
func held_options() -> Dictionary:
    return SelectionChord.options_for(SelectionChord.held_mode(mode))


## The crosshair with the chord's mark in the cross's slot, as the marquee's.
func cursor_picture() -> SaCursorPicture:
    return _chord.picture_for(SelectionChord.held_mode(mode))


func handle_input(event: InputEvent) -> void:
    var doc: SaDocument = document()
    var button := event as InputEventMouseButton
    if button == null or button.button_index != MOUSE_BUTTON_LEFT or not button.pressed:
        return
    if doc == null:
        return
    var at := get_document_mouse_position()
    var press_mode := SaSelection.mode_for_press(mode, button.shift_pressed, button.alt_pressed)
    flood(Vector2i(floori(at.x), floori(at.y)), press_mode)


## Floods from *seed*, in document pixels, or matches every texel when
## [member contiguous] is off. Public so a capture step and a test can click
## without a pointer. The selection and its Feather are one undo step, and a
## click that changed nothing records none.
func flood(start: Vector2i, press_mode: int = mode) -> int:
    var doc: SaDocument = document()
    if doc == null:
        return 0
    return doc.selection.change(SaSelection.WAND_TITLE, _flood.bind(start, press_mode))


func _flood(start: Vector2i, press_mode: int) -> int:
    var doc: SaDocument = document()
    var merged: SaTexture = null
    if sample_merged and surface != null and surface.easel != null:
        # A flood can reach past the window, so the picture there goes in first,
        # and a layer shown or hidden a moment before is in it, `SaEasel.catch_up`.
        surface.easel.catch_up()
        surface.easel.flush()
        merged = surface.easel.output
    var filled := 0
    var replaced := press_mode == SaSelection.Mode.REPLACE or not doc.selection.active
    if contiguous:
        filled = _wand.flood(doc, start, tolerance, press_mode, merged, doc.active_layer)
    else:
        filled = _wand.select_matching(doc, start, tolerance, press_mode, merged, doc.active_layer)
    _feather_edge(replaced)
    return filled


## Sets the selection's feather to the tool's when *replaced* says the shape
## replaced the selection. An add, a subtract or an intersect leaves the amount
## alone, and the selection lays it over its hard mask once the step ends, so a
## shape added with Shift never softens the selection a second time.
##
## The stored fraction becomes pixels here rather than when it was set, so the
## radius is always the one the document in front of the painter deserves.
func _feather_edge(replaced: bool) -> void:
    var doc: SaDocument = document()
    if doc == null or not replaced:
        return
    var radius := SaSelectionFilters.feather_radius(feather, doc.brush_side)
    doc.selection.feather.apply(doc.selection, radius, doc.canvas_size, doc.projection.wrapping)
