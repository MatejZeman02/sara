## The marquee: drag a rectangle or an ellipse into the
## document-wide selection.
##
## The rectangle is the Marquee tool and the ellipse the Ellipse Select tool,
## `state_ellipse_select.gd`, which is this state with `shape` fixed. The mode
## is an option on the descriptor, so the bar offers it and the right-click
## menu too. Shift on the press adds, Alt subtracts and both intersect whatever
## the bar says, the chord Photoshop and Krita share. While a key is down the
## Tool Options mode row and a mark on the pointer say which, and a key pressed
## or let go mid-drag leaves the shape's mode alone. A click without a drag in
## replace mode drops the selection, which is how a painter gets rid of one
## without reaching for the menu.
##
## **Shift pressed after the press holds the box square**, so Ellipse Select
## drags a circle and the Marquee a square, as Krita and Photoshop do. A press
## made with Shift took it for Add, so its drag squares only once Shift has
## been let go and pressed again.
##
## **A press inside the selection moves its outline** and leaves the pixels,
## as Photoshop and GIMP do, so moving an outline needs neither a fresh shape
## nor the Transform tool, which moves the pixels with it. It takes a press
## with neither Shift nor Alt in Replace mode inside the
## selection's shape, so a press in the corner of an ellipse's box or in the
## notch of a lasso's outline starts a new shape there. Deselect, or a press
## with Shift, starts a shape from inside an old one, which the Selection row's
## hint says.
extends ToolState

const SelectionChord = preload("res://modules/sara-base-modules/base/tools/selection_chord.gd")

## The two shapes a drag can make.
const RECTANGLE: int = 0
const ELLIPSE: int = 1

## The undo step a move of the outline records.
const MOVE_TITLE: String = "Move Selection"

## What a drag makes. Not an option: the tool a painter picks is the shape, so
## neither tool shows a row that would make the other.
var shape: int = RECTANGLE
## What the shape does to the selection: an `SaSelection.Mode`, the
## `selection_mode` option shared with the lasso.
var mode: int = SaSelection.Mode.REPLACE
## Whether an ellipse's edge is graded by how much of each pixel it covers. The
## `ellipse_anti_alias` option, on by default as the lasso's is, which only the
## Ellipse Select tool declares: a rectangle on whole pixels has no edge for a
## grade to soften, and a row that does nothing is worse than none.
var anti_alias: bool = true
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

var _dragging: bool = false
var _anchor: Vector2 = Vector2.ZERO
var _corner: Vector2 = Vector2.ZERO
var _press_mode: int = SaSelection.Mode.REPLACE
## The mode Shift or Alt gave the press under way, or -1 for one that took
## neither. Kept through the drag, so a key let go or pressed midway changes
## neither the shape's mode nor what the row and the pointer say.
var _press_chord: int = -1
## Whether the drag under way is held square, and whether Shift has been up
## since the press, which a press made with Shift needs before Shift squares.
var _square: bool = false
var _shift_was_up: bool = false

## Whether the press is moving the selection's outline rather than dragging a
## shape, where it went down in document pixels, and the whole pixels the
## pointer has taken the outline since.
var _moving: bool = false
var _move_from: Vector2 = Vector2.ZERO
var _move_by: Vector2i = Vector2i.ZERO

## The three kernels a move's carry runs, made at the first move and kept for
## this tool's life, as the transform keeps its own.
var _mask_kernels: SaTransformSelection.Kernels = SaTransformSelection.Kernels.new()

## The pointer's marks for the chord.
var _chord: SelectionChord = SelectionChord.new()


func reset() -> void:
    _dragging = false
    _moving = false
    _move_by = Vector2i.ZERO


func handle_input(event: InputEvent) -> void:
    var doc: SaDocument = document()
    if doc == null:
        return
    var button := event as InputEventMouseButton
    if button != null and button.button_index == MOUSE_BUTTON_LEFT:
        if button.pressed:
            _press(get_document_mouse_position(), button.shift_pressed, button.alt_pressed)
            return
        _hold_square(button.shift_pressed)
        if _moving:
            _moving = false
            _apply_move()
        elif _dragging:
            _dragging = false
            _apply()
        return
    var key := event as InputEventKey
    if key != null and key.keycode == KEY_SHIFT:
        _hold_square(key.pressed)
        return
    if not event is InputEventMouseMotion:
        return
    _hold_square((event as InputEventMouseMotion).shift_pressed)
    if _moving:
        _move_by = Vector2i((get_document_mouse_position() - _move_from).round())
    elif _dragging:
        _corner = get_document_mouse_position()


## Starts a move of the outline when [method moves_from] says the press is one,
## and a shape otherwise.
func _press(at: Vector2, shift: bool, alt: bool) -> void:
    if moves_from(at, shift, alt):
        _moving = true
        _move_from = at
        _move_by = Vector2i.ZERO
        return
    _dragging = true
    _anchor = at
    _corner = _anchor
    _press_mode = SaSelection.mode_for_press(mode, shift, alt)
    _press_chord = SelectionChord.pressed_mode(mode, shift, alt)
    _shift_was_up = not shift
    _square = false


## Squares the drag while Shift is down, once it has been up since the press.
func _hold_square(shift: bool) -> void:
    if not shift:
        _shift_was_up = true
    _square = shift and _shift_was_up


## Whether a press at *point*, in document pixels, with *shift* and *alt* as
## given, moves the selection's outline rather than starting a shape.
##
## The shape that made the selection rather than its mask, so the answer needs
## nothing read back: [method SaSelection.shape_has_point] while the shape still
## describes the mask, and the bounds where it does not, a selection added to, subtracted
## from, inverted or made by the wand.
func moves_from(point: Vector2, shift: bool, alt: bool) -> bool:
    var doc: SaDocument = document()
    if shift or alt or mode != SaSelection.Mode.REPLACE or doc == null:
        return false
    var selection := doc.selection
    if not selection.active or not Rect2(selection.bounds).has_point(point):
        return false
    return selection.shape_has_point(point)


## The move shape while the outline is held and over a selection a press would
## move, and the descriptor's cross everywhere else. Shift and Alt are read off
## the keyboard, so pressing one over the selection gives the cross back before
## the pointer moves.
func cursor_shape() -> int:
    var doc: SaDocument = document()
    if _moving:
        return Control.CURSOR_MOVE
    if _dragging or doc == null:
        return -1
    var over := moves_from(get_document_mouse_position(), Input.is_key_pressed(KEY_SHIFT), Input.is_key_pressed(KEY_ALT))
    return Control.CURSOR_MOVE if over else -1


## The mode the row and the pointer show: the press's own through a drag, and
## what Shift and Alt down now would give a press otherwise. -1 for the
## painter's chosen mode, and for a move of the outline, which makes no shape.
func shown_chord() -> int:
    if _dragging:
        return _press_chord
    return -1 if _moving else SelectionChord.held_mode(mode)


func held_options() -> Dictionary:
    return SelectionChord.options_for(shown_chord())


## The crosshair with the chord's mark, standing in the cross's slot while a
## key is down or a press made with one is dragged.
func cursor_picture() -> SaCursorPicture:
    return _chord.picture_for(shown_chord())


## The box between the press and the pointer, in whole document pixels.
##
## Both corners round to the nearest pixel edge, so a drag of 640 pixels is a
## box of 640 wherever the press lands. Flooring one corner and ceiling the
## other gave 641 whenever the pointer sat a fraction into a pixel.
##
## Held square, the press rounds to its pixel first and the side is the longer
## of the pointer's two distances in whole pixels, laid towards the pointer, so
## the box is square to the pixel wherever the press and the pointer sit.
func drag_rect() -> Rect2i:
    if _square:
        var from := Vector2i(roundi(_anchor.x), roundi(_anchor.y))
        var reach := _corner - Vector2(from)
        var side := roundi(maxf(absf(reach.x), absf(reach.y)))
        var to := from + Vector2i(side if reach.x >= 0.0 else -side, side if reach.y >= 0.0 else -side)
        return Rect2i(from.min(to), Vector2i(side, side))
    var low := Vector2(minf(_anchor.x, _corner.x), minf(_anchor.y, _corner.y))
    var high := Vector2(maxf(_anchor.x, _corner.x), maxf(_anchor.y, _corner.y))
    var origin := Vector2i(roundi(low.x), roundi(low.y))
    return Rect2i(origin, Vector2i(roundi(high.x), roundi(high.y)) - origin)


## What the overlay draws while the drag is on: the box, and whether it is
## an ellipse. Empty when nothing is being dragged.
##
## A move hands the overlay the offset as `ants`, the map it already draws the
## mask's own ants through while the Transform tool holds a piece, so the
## outline that follows the pointer is the selection's real edge and not its
## box. The mask itself stays put until the release.
func preview_shape() -> Dictionary:
    if _moving:
        return {"ants": Transform2D(0.0, Vector2(_move_by))}
    if not _dragging:
        return {}
    return {"rect": Rect2(drag_rect()), "ellipse": shape == ELLIPSE}


## A press and a release inside one document pixel are a click, though the box
## between them can be a pixel wide when the two land either side of a
## half-pixel. Taking that box as a shape would select the one pixel, and the
## pen would then paint nothing anywhere else.
##
## The shape and its Feather are one undo step, named for the tool, and a
## click's drop is the Deselect step Krita records for the same click.
func _apply() -> void:
    var doc: SaDocument = document()
    var rect := drag_rect()
    var selection := doc.selection
    if rect.size.x <= 1 and rect.size.y <= 1:
        if _press_mode == SaSelection.Mode.REPLACE:
            selection.drop()
        return
    var title := SaSelection.ELLIPSE_TITLE if shape == ELLIPSE else SaSelection.RECT_TITLE
    selection.change(title, _land.bind(rect))


## Carries the mask by the whole pixels the pointer moved, as one step through
## the door every selection change takes. A release within the pixel it went
## down in is a click, and drops the selection as a click outside does, which
## is what a click of the marquee does in Photoshop too.
func _apply_move() -> void:
    var doc: SaDocument = document()
    var by := _move_by
    _move_by = Vector2i.ZERO
    var selection := doc.selection
    if by == Vector2i.ZERO:
        selection.drop()
        return
    var was: RefCounted = selection.standing_shape()
    selection.change(MOVE_TITLE, _carry.bind(selection, by, was))


## Carries the mask by *by* and the shape that made it, *was*, with it.
func _carry(selection: SaSelection, by: Vector2i, was: RefCounted) -> void:
    SaTransformSelection.translate(selection, by, _mask_kernels)
    selection.carry_shape(was, by)


## Writes the dragged shape into the selection and sets its feather, the work
## of the step [method _apply] records.
func _land(rect: Rect2i) -> void:
    var doc: SaDocument = document()
    var replaced := _press_mode == SaSelection.Mode.REPLACE or not doc.selection.active
    if shape == ELLIPSE:
        doc.selection.select_ellipse(rect, _press_mode, anti_alias)
    else:
        doc.selection.select_rect(rect, _press_mode)
    _feather_edge(replaced)


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
