## The Magnetic Lasso: a trace that clings to the edge the painter follows,
## laying anchors as it goes, closed into the document-wide selection.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Intelligent scissors, Mortensen and Barrett's method and the one behind
## Photoshop's tool of this name. A click starts the trace and the pointer
## then needs no button: the live path runs from the last anchor along the
## cheapest way over the picture's edges to the pointer, `SaMagneticTrace`.
## A click lays an anchor, and anchors are laid on their own where the path
## has stood still a while, at the Frequency option's spacing.
##
## **Editing.** Backspace takes the last anchor away, Escape abandons the
## trace, and a click on the first anchor, a double click or Enter closes it.
## Holding Alt draws straight to the pointer and, with the button down,
## freehand, and letting it go hands back to the magnetic path. Shift or Alt
## on the click that starts a trace adds or subtracts, both intersect, as on
## the other lassos, and Alt is read as the chord on that click alone.
##
## **The result** is the closed outline in the selection, graded at the edge
## unless Anti-aliasing is off and feathered by the Feather, one undo step.
extends ToolState

const SaMagneticTraceScript = preload("res://modules/sara-base-modules/base/magnetic/sa_magnetic_trace.gd")
const SelectionChord = preload("res://modules/sara-base-modules/base/tools/selection_chord.gd")

## The history's name for the step a closed trace is.
const TITLE: String = "Magnetic Lasso"
## How far a click may land from the first anchor and still close the trace,
## in screen pixels, the Polygonal Lasso's reach.
const CLOSE_DISTANCE: float = 8.0
## An outline enclosing less than this, in square document pixels, is no area.
const MIN_AREA: float = 1.0
## The Contrast option's full scale, the gradient in Oklab units a pixel that
## a Contrast of 100% asks of an edge.
const CONTRAST_SCALE: float = 0.1

## How far from the pointer the path looks for an edge, in screen pixels. The
## `magnetic_width` option.
var width: int = 10
## The edge strength below which the path takes no notice of an edge, 0 to 1
## of [constant CONTRAST_SCALE]. The `magnetic_contrast` option.
var contrast: float = 0.1
## How often anchors are laid on their own, 0 for never to 1 for the
## closest. The `magnetic_frequency` option.
var frequency: float = 0.57
## Whether the cost reads every layer as shown or the active one alone. The
## `sample_merged` option, shared with the wand and the eyedropper.
var sample_merged: bool = true
## The `selection_mode` option, shared with the marquee and the lassos.
var mode: int = SaSelection.Mode.REPLACE
## Whether the edge is graded by how much of each pixel the outline covers.
## The `lasso_anti_alias` option, one setting with the other lassos.
var anti_alias: bool = true
## How soft the edge of a selection this tool makes anew is, as a fraction of
## the canvas's smaller dimension, a view of `SaSettings.selection_feather` as
## on the other selection tools.
var feather: float:
    set(value):
        SaInHand.Settings.write(&"selection_feather", value)
    get:
        return SaInHand.Settings.read(&"selection_feather")

## The trace under way, or null.
var trace: SaMagneticTraceScript = null
var _press_mode: int = SaSelection.Mode.REPLACE
## The mode Shift or Alt gave the trace under way, or -1 for one that took
## neither.
var _press_chord: int = -1
## Whether the button is down, for a freehand drag under Alt.
var _held: bool = false
var _chord: SelectionChord = SelectionChord.new()


func reset() -> void:
    trace = null
    _held = false


func handle_input(event: InputEvent) -> void:
    if document() == null:
        return
    var key := event as InputEventKey
    if key != null:
        _key(key)
        return
    var button := event as InputEventMouseButton
    if button != null and button.button_index == MOUSE_BUTTON_LEFT:
        _button(button)
        return
    var motion := event as InputEventMouseMotion
    if motion != null and trace != null:
        _apply_options()
        var at := get_document_mouse_position()
        if motion.alt_pressed:
            trace.freehand(at, _held)
        else:
            if trace.drawing_freehand():
                trace.end_freehand()
            trace.move(at)


## Settles more of the search while the pointer rests, so a path the last
## move did not finish reaches the pointer a frame or two later.
func tick(_delta: float) -> void:
    if trace != null:
        trace.tick()


## Backspace, while a trace is under way, takes its last anchor away rather
## than clearing the layer.
func keeps_key(keycode: Key) -> bool:
    return trace != null and keycode == KEY_BACKSPACE


func _key(key: InputEventKey) -> void:
    if trace == null:
        return
    if key.keycode == KEY_ALT and not key.pressed:
        if trace.drawing_freehand():
            trace.end_freehand()
        return
    if not key.pressed:
        return
    match key.keycode:
        KEY_ENTER, KEY_KP_ENTER:
            close()
        KEY_ESCAPE:
            reset()
        KEY_BACKSPACE:
            if not trace.back():
                reset()


func _button(button: InputEventMouseButton) -> void:
    _held = button.pressed
    if not button.pressed:
        return
    var at := get_document_mouse_position()
    _apply_options()
    if trace == null:
        _press_mode = SaSelection.mode_for_press(mode, button.shift_pressed, button.alt_pressed)
        _press_chord = SelectionChord.pressed_mode(mode, button.shift_pressed, button.alt_pressed)
        trace = SaMagneticTraceScript.new(at, _cell(), _picture)
        _apply_options()
        return
    if button.alt_pressed:
        trace.freehand(at, true)
        return
    if button.double_click:
        close()
        return
    if trace.anchors.size() >= 2 and trace.anchors[0].distance_to(at) <= CLOSE_DISTANCE / _zoom():
        close()
        return
    trace.move(at)
    trace.click()


## Closes the trace back to its first anchor into the selection, one undo
## step. An outline holding no area leaves the selection as it was and says
## so, as the lasso does.
func close() -> void:
    if trace == null:
        return
    var points := trace.closed()
    reset()
    if points.size() < 3 or absf(_area(points)) < MIN_AREA:
        EventBus.corner_notice.emit(tr("The lasso closed around no area, so the selection did not change."))
        return
    document().selection.change(TITLE, _land.bind(points))


## The anchors and the outline so far, for the overlay: the outline as an
## open line the live path ends, and each anchor a knot.
func preview_shape() -> Dictionary:
    if trace == null:
        return {}
    return {"points": trace.outline(), "closed": false, "knots": trace.anchors.duplicate(), "handle_side": 6.0}


## The mode the row and the pointer show: the trace's own while one is under
## way, and what Shift and Alt down now would give a click otherwise.
func shown_chord() -> int:
    return _press_chord if trace != null else SelectionChord.held_mode(mode)


func held_options() -> Dictionary:
    return SelectionChord.options_for(shown_chord())


func cursor_picture() -> SaCursorPicture:
    return _chord.picture_for(shown_chord())


## The options as the trace reads them, in its cells.
func _apply_options() -> void:
    if trace == null:
        return
    var cell := _cell()
    trace.width_cells = maxi(0, roundi(float(width) / (_zoom() * cell)))
    trace.contrast = clampf(contrast, 0.0, 1.0) * CONTRAST_SCALE
    trace.frequency = clampf(frequency, 0.0, 1.0)


## Document pixels a cell of the cost window spans: one at a zoom of one or
## more, and the power of two nearest a screen pixel's reach zoomed out, so
## the window covers what the screen shows at the screen's own detail.
func _cell() -> float:
    var zoom := _zoom()
    if zoom >= 1.0:
        return 1.0
    return pow(2.0, floorf(log(1.0 / zoom) / log(2.0)))


func _zoom() -> float:
    var view: SaView = surface.view if surface != null else null
    return maxf(view.get_zoom() if view != null else 1.0, 0.01)


## What the cost reads, `[space, merged, layer]`: the merged picture when
## Sample merged is on, the active layer's chunks when it is off.
func _picture() -> Array:
    var doc := document()
    if doc == null:
        return [null, null, null]
    if sample_merged and surface != null and surface.easel != null:
        surface.easel.catch_up()
        surface.easel.flush()
        return [doc.color_space, surface.easel.output, null]
    return [doc.color_space, null, doc.active_layer]


## Writes the outline into the selection and sets its feather, inside the one
## change [method close] opened.
func _land(points: PackedVector2Array) -> void:
    var doc := document()
    var replaced := _press_mode == SaSelection.Mode.REPLACE or not doc.selection.active
    doc.selection.select_polygon(points, _press_mode, anti_alias)
    if not replaced:
        return
    var radius := SaSelectionFilters.feather_radius(feather, doc.brush_side)
    doc.selection.feather.apply(doc.selection, radius, doc.canvas_size, doc.projection.wrapping)


## The polygon's signed area in square document pixels, by the shoelace sum.
static func _area(points: PackedVector2Array) -> float:
    var twice := 0.0
    var last := points[points.size() - 1]
    for point in points:
        twice += last.x * point.y - point.x * last.y
        last = point
    return twice * 0.5
