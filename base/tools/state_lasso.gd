## The Lasso tool: a freehand outline dragged closed into the document-wide
## selection. The Polygonal Lasso, `state_polygonal_lasso.gd`, is this state
## with [member polygon] fixed on.
##
## The Lasso collects the pointer's path while the button is down and closes
## it on release. The Polygonal Lasso takes a point per click and closes on a
## double-click, on a click back onto the first point, or on Enter, and
## Escape throws the points away. Either way the selection kernel tests the
## polygon by even-odd winding over its bounding box and nothing more, and
## grades the edge by coverage unless Anti-aliasing is off.
##
## Two tools rather than a shape row on the bar, as Photoshop and Krita have
## them: a row hidden on the bar left a
## painter who pressed the one Lasso with no polygon anywhere, as it had left
## the marquee's ellipse before that became a tool.
extends ToolState

const SelectionChord = preload("res://modules/sara-base-modules/base/tools/selection_chord.gd")

## How far a click may land from the first point and still close the
## polygon, in screen pixels.
const CLOSE_DISTANCE: float = 8.0
## Freehand points closer than this to the last one are not kept, so a slow
## hand does not hand the kernel a thousand edges of nothing.
const MIN_STEP: float = 1.5
## An outline enclosing less than this, in square document pixels, is no
## area: the kernel would find no pixel inside it.
const MIN_AREA: float = 1.0

## Whether a click lays a point rather than a press starting a drag. Set by
## the Polygonal Lasso's own constructor and by nothing else. No option row
## names it, so a stored `lasso_shape` that said Polygon reaches no tool.
var polygon: bool = false
## The `selection_mode` option, shared with the marquee.
var mode: int = SaSelection.Mode.REPLACE
## Whether the edge is graded by how much of each pixel the outline covers,
## so a fill inside it steps down smoothly across a slanted edge rather than in
## one pixel. The `lasso_anti_alias` option, on by default as Krita's is. Off,
## every pixel is wholly in or out, which a pixel-art cut wants.
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

var _points: PackedVector2Array = PackedVector2Array()
var _dragging: bool = false
var _press_mode: int = SaSelection.Mode.REPLACE
## The mode Shift or Alt gave the outline under way, or -1 for one that took
## neither, kept until it closes as the marquee keeps its own.
var _press_chord: int = -1
## The pointer's marks for the chord.
var _chord: SelectionChord = SelectionChord.new()


func reset() -> void:
    _points = PackedVector2Array()
    _dragging = false


func handle_input(event: InputEvent) -> void:
    var doc: SaDocument = document()
    if doc == null:
        return
    var key := event as InputEventKey
    if key != null and key.pressed and polygon and not _points.is_empty():
        if key.keycode == KEY_ENTER or key.keycode == KEY_KP_ENTER:
            _close()
        elif key.keycode == KEY_ESCAPE:
            reset()
        return
    var button := event as InputEventMouseButton
    if button != null and button.button_index == MOUSE_BUTTON_LEFT:
        if polygon:
            _polygon_press(button)
        elif button.pressed:
            _dragging = true
            _points = PackedVector2Array([get_document_mouse_position()])
            _press_mode = _mode_for(button)
            _press_chord = SelectionChord.pressed_mode(mode, button.shift_pressed, button.alt_pressed)
        elif _dragging:
            _dragging = false
            _close()
        return
    if _dragging and event is InputEventMouseMotion:
        var at := get_document_mouse_position()
        if _points.is_empty() or _points[_points.size() - 1].distance_to(at) >= MIN_STEP:
            _points.append(at)


func _polygon_press(button: InputEventMouseButton) -> void:
    if not button.pressed:
        return
    var at := get_document_mouse_position()
    if _points.is_empty():
        _press_mode = _mode_for(button)
        _press_chord = SelectionChord.pressed_mode(mode, button.shift_pressed, button.alt_pressed)
        _points.append(at)
        return
    if button.double_click or (_points.size() >= 3 and _points[0].distance_to(at) <= CLOSE_DISTANCE / _zoom()):
        _close()
        return
    _points.append(at)


func _zoom() -> float:
    var view: SaView = surface.view if surface != null else null
    return maxf(view.get_zoom() if view != null else 1.0, 0.01)


func _mode_for(button: InputEventMouseButton) -> int:
    return SaSelection.mode_for_press(mode, button.shift_pressed, button.alt_pressed)


## The mode the row and the pointer show: the outline's own while one is under
## way, and what Shift and Alt down now would give a press otherwise, -1 for
## the painter's chosen mode.
func shown_chord() -> int:
    return _press_chord if _dragging or not _points.is_empty() else SelectionChord.held_mode(mode)


func held_options() -> Dictionary:
    return SelectionChord.options_for(shown_chord())


## The crosshair with the chord's mark in the cross's slot, as the marquee's.
func cursor_picture() -> SaCursorPicture:
    return _chord.picture_for(shown_chord())


## The points so far, for the overlay, and whether the outline is a drag
## that will close on release or a polygon waiting for its next click.
func preview_shape() -> Dictionary:
    if _points.is_empty():
        return {}
    return {"points": _points.duplicate(), "closed": _dragging}


## Closes the outline into a selection, one undo step. A click in replace mode drops the
## selection without a word and as one undo step, as Krita's does, and any other outline that
## holds no area leaves the selection as it was and says so, because the
## kernel would otherwise clear a replace and mark it active around nothing.
func _close() -> void:
    var doc: SaDocument = document()
    var points := _points
    reset()
    if points.size() <= 1 and _press_mode == SaSelection.Mode.REPLACE:
        doc.selection.drop()
        return
    if points.size() < 3 or absf(_area(points)) < MIN_AREA:
        EventBus.corner_notice.emit(tr("The lasso closed around no area, so the selection did not change."))
        return
    doc.selection.change(SaSelection.FREEHAND_TITLE, _land.bind(points))


## Writes the closed outline into the selection and sets its feather, one undo step
## with the Feather because [method _close] runs it inside one change.
func _land(points: PackedVector2Array) -> void:
    var doc: SaDocument = document()
    var replaced := _press_mode == SaSelection.Mode.REPLACE or not doc.selection.active
    doc.selection.select_polygon(points, _press_mode, anti_alias)
    _feather_edge(replaced)


## The polygon's signed area in square document pixels, by the shoelace sum.
## It reads zero for a flick along a line, and also for the two equal lobes of
## a figure of eight, whose windings cancel although the kernel would fill both.
static func _area(points: PackedVector2Array) -> float:
    var twice := 0.0
    var last := points[points.size() - 1]
    for point in points:
        twice += last.x * point.y - point.x * last.y
        last = point
    return twice * 0.5


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
