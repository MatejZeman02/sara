## The crop tool: drag a rectangle, nudge its handles, and Enter or the Crop
## button in the Tool Options docker crops to it as one history step. Escape
## drops the rectangle.
##
## With no rectangle drawn the box stands on the canvas's edges, as
## Photoshop's does the moment the tool is picked: the painter trims by
## pulling a side in. A press on one of its handles pulls it, a click that does not travel leaves it there, and a drag
## anywhere else draws a fresh box as before. Escape and a finished crop put it
## back on the canvas as it then is. A box still on the whole canvas crops
## nothing at Enter and writes no step. A ratio lock in force fits the canvas
## box inside the canvas, centred.
##
## What is cropped is the tool's Crop option, with the canvas first and the
## active layer alone as one of three:
##
## - **Canvas**, the default, crops the document to the box, every layer, mask
##   and field, through the `crop` role's `SaCrop.crop_to`, and keeps the paint
##   outside in the layers' chunks unseen, for a later Canvas Size to show.
## - **Canvas and Delete Outside** is the same crop with everything outside the
##   box deleted from every layer.
## - **Layer** crops the active layer alone: the layer shows its
##   paint only inside the box as the drag goes, a live crop kept with its live
##   transform, written into an ordinary layer's chunks at Enter, and Escape
##   puts it back. An ordinary layer that carries a relief has no live crop to
##   show, so the box's dim is the preview and Enter writes the crop into every
##   field of its chunks, reached as the live transform's `IN_CHUNKS`.
##
## The crop itself is `SaLiveTransform`'s in the skeleton, reached through the
## `live_transform` role, because a module sees the door only and a role is how
## the door hands a tool a skeleton engine. This holds the rectangle, the
## gestures that shape it and the session, and draws nothing: `preview_shape`
## is what the selection overlay already reads from the marquee, with a flag
## asking for handles. A tool handed no roles, as in a suite that builds a
## machine bare, draws its box and crops nothing.
##
## Enter and Escape arrive through `handle_input` the way the polygon lasso's
## do, because the canvas forwards key events to whichever tool is active.
##
## The rectangle is not held inside the canvas, on either kind of drag. A
## layer's crop is in its own pixels, and the paint a layer holds past the
## canvas edge is kept by a crop that reaches it, for a later move to bring
## into view.
extends ToolState

## How near a handle a press has to land to grab it, in screen pixels, so the
## grab stays the same size to the hand at every zoom.
const HANDLE_REACH := 10.0

## How far a press may travel, in screen pixels, and still be a click, the
## tool machine's own Shift click distance. A module sees the door only, so the
## number is written here rather than read off the machine's helper.
const CLICK_REACH := 3.0

## What a press started: nothing, a fresh rectangle, a move of the whole one,
## or a pull on one handle.
enum Gesture { NONE, DRAW, MOVE, RESIZE }

## What the rectangle's shape is locked to. FREE is the default and is the
## drag the tool has always had. DOCUMENT is the canvas's own shape, which has
## no number here because it changes with the document, so it is resolved at
## drag time rather than stored.
enum Ratio { FREE, DOCUMENT, SQUARE, R3_2, R2_3, R4_3, R3_4, R16_9, R9_16 }

## Width over height for each named ratio. FREE and DOCUMENT are not in it:
## the first locks nothing and the second asks the document.
const RATIO_VALUES := {
    Ratio.SQUARE: 1.0,
    Ratio.R3_2: 3.0 / 2.0,
    Ratio.R2_3: 2.0 / 3.0,
    Ratio.R4_3: 4.0 / 3.0,
    Ratio.R3_4: 3.0 / 4.0,
    Ratio.R16_9: 16.0 / 9.0,
    Ratio.R9_16: 9.0 / 16.0,
}

## What a crop takes: the active layer, the document keeping what falls
## outside, or the document deleting it. The order is the option's.
enum Mode { LAYER, CANVAS, CANVAS_DELETE }

## The role the skeleton's live transform is registered under.
const ROLE := &"live_transform"
## The role of the document's crop, `SaCrop`.
const CANVAS_ROLE := &"crop"

## The locked shape, written through the `crop_ratio` option on the tool.
var ratio: int = Ratio.FREE
## What a crop takes, written through the `crop_mode` option on the tool.
## Canvas on a fresh settings folder, the crop Krita and Photoshop make.
var mode: int = Mode.CANVAS

var _rect: Rect2i = Rect2i()
## Whether the painter has shaped a box. While false the box is the canvas's,
## [method _canvas_box], asked afresh each time so a new canvas size or ratio
## lock moves it with no signal.
var _has_rect: bool = false
var _gesture: Gesture = Gesture.NONE
## Which handle is held, as -1, 0 or 1 per axis. Zero on an axis means that
## axis is not being pulled, so (0, 0) is the whole rectangle moving.
var _grabbed: Vector2i = Vector2i.ZERO
var _anchor: Vector2 = Vector2.ZERO
var _started_from: Rect2i = Rect2i()
## The layer the open session crops, null while none is open.
var _layer: SaLayer = null
## The live transform the layer had when the session opened, an
## `SaLiveTransform` or null for none, which Escape puts back and the step at
## Enter starts from.
var _before: RefCounted = null
var _open: bool = false
## Whether the open session writes its crop into the layer's chunks at the end
## rather than showing it live, for an ordinary layer that carries a relief.
var _in_place: bool = false


## Called when the machine switches away from this tool, or when the document
## is rebuilt. An open session is put back rather than written, the way the
## transform tool puts a lift back: a painter who reaches for another tool has
## not said yes to the crop.
func reset() -> void:
    _cancel()
    _drop_box()


func _drop_box() -> void:
    _gesture = Gesture.NONE
    _has_rect = false
    _rect = Rect2i()


## The rectangle the tool would crop to, the canvas's own box while the
## painter has shaped none, and empty with no document. Public so a test and a
## capture step can read it without a screenshot.
func pending_rect() -> Rect2i:
    return _rect if _has_rect else _canvas_box()


## The box the tool stands on while none is drawn: the whole canvas, or with a
## ratio locked the largest box of that ratio inside it, centred.
func _canvas_box() -> Rect2i:
    var doc: SaDocument = document()
    if doc == null:
        return Rect2i()
    var canvas := doc.canvas_size
    var locked := locked_ratio()
    if locked <= 0.0 or canvas.x <= 0 or canvas.y <= 0:
        return Rect2i(Vector2i.ZERO, canvas)
    var size := canvas
    if float(canvas.x) > float(canvas.y) * locked:
        size.x = clampi(roundi(float(canvas.y) * locked), 1, canvas.x)
    else:
        size.y = clampi(roundi(float(canvas.x) / locked), 1, canvas.y)
    @warning_ignore("integer_division")
    return Rect2i((canvas - size) / 2, size)


## Whether *rect* is the whole canvas, which a crop to it would not change.
func _is_whole_canvas(rect: Rect2i, doc: SaDocument) -> bool:
    return rect == Rect2i(Vector2i.ZERO, doc.canvas_size)


## Width over height the drag is locked to, 0.0 when nothing is locked. The
## document is asked every time rather than cached, because File > New replaces
## it under a tool that stays selected.
func locked_ratio() -> float:
    var doc: SaDocument = document()
    if ratio == Ratio.DOCUMENT:
        if doc == null or doc.canvas_size.y <= 0:
            return 0.0
        return float(doc.canvas_size.x) / float(doc.canvas_size.y)
    return float(RATIO_VALUES.get(ratio, 0.0))


## What the selection overlay draws: the rectangle, its eight handles, and the
## dim over everything outside it.
##
## The dim is asked for by name rather than read off the handles flag, so a
## later tool can have one without the other.
func preview_shape() -> Dictionary:
    var rect := pending_rect()
    if not rect.has_area():
        return {}
    return {"rect": Rect2(rect), "handles": true, "dim": true}


## Crops to the pending rectangle as one history step, the document or the
## active layer as [member mode] says, and drops the rectangle. The Enter key
## and the Crop row in the Tool Options docker both land here. False when there
## was no document, the box is the whole canvas, the layer refused a crop, or
## nothing changed.
func crop_now() -> bool:
    var doc: SaDocument = document()
    if doc == null:
        return false
    _rect = pending_rect()
    _has_rect = _rect.has_area()
    if not _has_rect or _is_whole_canvas(_rect, doc):
        _cancel()
        _drop_box()
        return false
    if mode != Mode.LAYER:
        var done_canvas := _crop_canvas(doc)
        _drop_box()
        return done_canvas
    var done := false
    if _write():
        done = close_session()
    else:
        _cancel()
    _drop_box()
    return done


## Writes the open session as the history step it is, and ends it. The box
## stays, so a later drag of it opens a session of its own. Asked by every undo
## and redo first, through `ToolMachine.close_session`, so an undo under an
## open crop takes the crop back rather than a step before it.
func close_session() -> bool:
    var doc: SaDocument = document()
    if not _open:
        return false
    var done := false
    if _in_place:
        var bake := _bake()
        done = bake != null and _layer_kept() and bool(bake.call(&"crop_in_place", doc, _layer, _rect))
    else:
        var live := _live()
        done = live != null and _layer_kept() and bool(live.call(&"commit", doc, _layer, _before))
    _close()
    return done


## Whether the layer shows another crop than it had when the session opened,
## or, written in place, whether there is a box to write.
func holds_session() -> bool:
    if _in_place:
        return _open and _layer_kept() and _rect.has_area()
    var live := _live()
    return _open and live != null and _layer_kept() and bool(live.call(&"changed_from", _layer, _before))


func handle_input(event: InputEvent) -> void:
    var doc: SaDocument = document()
    if doc == null:
        return
    var key := event as InputEventKey
    if key != null and key.pressed:
        if key.keycode == KEY_ENTER or key.keycode == KEY_KP_ENTER:
            crop_now()
        elif key.keycode == KEY_ESCAPE:
            reset()
        return
    var button := event as InputEventMouseButton
    if button != null and button.button_index == MOUSE_BUTTON_LEFT:
        if button.pressed:
            _press(get_document_mouse_position())
        elif _gesture != Gesture.NONE:
            _release(get_document_mouse_position())
        return
    if _gesture != Gesture.NONE and event is InputEventMouseMotion:
        _drag(get_document_mouse_position())


## Ends the press at *at*. A fresh draw that never left the click's few pixels
## puts the box back on the canvas, as a click into Photoshop's crop does.
func _release(at: Vector2) -> void:
    var drew := _gesture == Gesture.DRAW
    _gesture = Gesture.NONE
    _has_rect = _rect.size.x > 0 and _rect.size.y > 0
    if drew and at.distance_to(_anchor) < CLICK_REACH / _zoom():
        _drop_box()


func _press(at: Vector2) -> void:
    if mode == Mode.LAYER:
        _open_session()
    _anchor = at
    # The canvas's box is a box like a drawn one to the handles, though not to
    # a press inside it, which draws afresh as a press on no box always has.
    var drawn := _has_rect
    _rect = pending_rect()
    _started_from = _rect
    if _rect.has_area():
        # Typed rather than inferred: the function answers null for a press
        # that is on no handle at all, and inferring from that is a warning
        # the project treats as an error.
        var grabbed: Variant = _handle_under(at)
        if grabbed != null and (drawn or grabbed != Vector2i.ZERO):
            _grabbed = grabbed
            _has_rect = true
            _gesture = Gesture.MOVE if _grabbed == Vector2i.ZERO else Gesture.RESIZE
            return
    _gesture = Gesture.DRAW
    _has_rect = true
    _rect = Rect2i(Vector2i(roundi(at.x), roundi(at.y)), Vector2i.ZERO)


func _drag(to: Vector2) -> void:
    var locked := locked_ratio()
    match _gesture:
        Gesture.DRAW:
            # The corner the press landed on stays put and the pointer drives
            # the other, so a locked draw is anchored where a free one is.
            _rect = _lock(_box(_anchor, to), locked, _drawn_corner(to))
        Gesture.MOVE:
            var moved := Vector2i(roundi(to.x - _anchor.x), roundi(to.y - _anchor.y))
            _rect = Rect2i(_started_from.position + moved, _started_from.size)
        Gesture.RESIZE:
            _rect = _lock(_pull(_started_from, _grabbed, to - _anchor), locked, _grabbed)
        _:
            return
    if _open:
        _write()


## The skeleton's live transform under [constant ROLE], or null for a tool the
## machine handed no roles.
func _live() -> Script:
    return _role(ROLE)


## The skeleton's writer of a crop into a relief layer's chunks,
## `SaTransformBake`, reached through the live transform's door.
func _bake() -> Script:
    var live := _live()
    return live.get(&"IN_CHUNKS") as Script if live != null else null


## The skeleton's engine under *role*, or null for a tool handed no roles.
func _role(role: StringName) -> Script:
    return roles.script_for(role) if roles != null else null


## Crops *doc* to the rectangle, keeping what falls outside for Canvas and
## deleting it for Canvas and Delete Outside, one history step over every
## layer. A tool handed no roles crops nothing.
func _crop_canvas(doc: SaDocument) -> bool:
    var engine := _role(CANVAS_ROLE)
    if engine == null or not _rect.has_area():
        return false
    var deleting := mode == Mode.CANVAS_DELETE
    return bool(engine.new(doc).call(&"crop_to", _rect, deleting, not deleting))


## Opens a session on the active layer, saying once why it cannot when the
## layer takes no crop. True when one is open.
func _open_session() -> bool:
    var doc: SaDocument = document()
    if _open:
        return true
    var live := _live()
    if live == null or doc == null or doc.active_layer == null:
        return false
    var bake := _bake()
    _in_place = bake != null and bool(bake.call(&"crops_in_place", doc, doc.active_layer))
    if not _in_place and bool(live.call(&"crop_refused", doc, doc.active_layer)):
        return false
    _layer = doc.active_layer
    _before = _layer.live_transform
    _open = true
    return true


## Shows the session's layer cropped to the rectangle, with no step yet, and
## answers whether the layer shows it. A rectangle with no area writes nothing,
## which is the press before the first move.
func _write() -> bool:
    var doc: SaDocument = document()
    if not _open_session() or not _rect.has_area() or not _layer_kept():
        return false
    if _in_place:
        return true
    return bool(_live().call(&"crop_to", doc, _layer, _rect))


## Whether the session's layer is still a layer of the document.
func _layer_kept() -> bool:
    var doc: SaDocument = document()
    return is_instance_valid(_layer) and doc != null and _layer.get_parent() == doc


## Puts back what the layer showed when the session opened, and ends it.
func _cancel() -> void:
    var doc: SaDocument = document()
    var live := _live()
    if _open and not _in_place and live != null and _layer_kept():
        live.call(&"show_live", doc, _layer, _before)
    _close()


func _close() -> void:
    _open = false
    _in_place = false
    _layer = null
    _before = null


## Which corner the pointer is pulling in a fresh draw, in the same -1, 0, 1
## per axis a handle uses, so the lock anchors the press rather than the
## rectangle's own corner.
func _drawn_corner(to: Vector2) -> Vector2i:
    return Vector2i(1 if to.x >= _anchor.x else -1, 1 if to.y >= _anchor.y else -1)


## *free* reshaped to *locked*, held at the edges *grabbed* is not pulling. A
## ratio of 0.0 is no lock at all, and then this is the rectangle the drag
## produced, untouched.
##
## Nothing is fitted to the canvas here. A crop is a rectangle of the layer's
## own pixels and clips nothing it is handed, so a locked rectangle hanging off
## the edge keeps both its shape and the size the hand gave it.
static func _lock(free: Rect2i, locked: float, grabbed: Vector2i) -> Rect2i:
    if locked <= 0.0:
        return free
    return _held(free, _ratio_size(free.size, locked), grabbed)


## The size nearest *free* with the wanted ratio. The longer axis wins, so the
## rectangle contains the free drag rather than being cut back inside it, which
## is what keeps the pointer on the edge it is pulling.
static func _ratio_size(free: Vector2i, locked: float) -> Vector2i:
    var wide := float(free.x) >= float(free.y) * locked
    if wide:
        return Vector2i(maxi(free.x, 1), maxi(roundi(float(maxi(free.x, 1)) / locked), 1))
    return Vector2i(maxi(roundi(float(maxi(free.y, 1)) * locked), 1), maxi(free.y, 1))


## *free* resized to *size* about the edges *grabbed* is not pulling. A corner
## pull holds the opposite corner, and an edge pull holds that edge's opposite
## and grows the free axis about the centre, so an edge drag does not also
## slide the rectangle sideways.
static func _held(free: Rect2i, size: Vector2i, grabbed: Vector2i) -> Rect2i:
    var position := free.position
    if grabbed.x < 0:
        position.x = free.end.x - size.x
    elif grabbed.x == 0:
        # Whole pixels are the point, and half of an odd size lands the
        # rectangle a pixel left of centre rather than between two.
        @warning_ignore("integer_division")
        position.x = free.get_center().x - size.x / 2
    if grabbed.y < 0:
        position.y = free.end.y - size.y
    elif grabbed.y == 0:
        @warning_ignore("integer_division")
        position.y = free.get_center().y - size.y / 2
    return Rect2i(position, size)


## The rectangle *from* with the edges *grabbed* names moved by *by*.
##
## Normalised through `abs()`, so pulling an edge past its opposite flips the
## rectangle rather than leaving it inside out, which is what every other
## rectangle drag in the app does.
static func _pull(from: Rect2i, grabbed: Vector2i, by: Vector2) -> Rect2i:
    var low := from.position
    var high := from.end
    var moved := Vector2i(roundi(by.x), roundi(by.y))
    if grabbed.x < 0:
        low.x += moved.x
    elif grabbed.x > 0:
        high.x += moved.x
    if grabbed.y < 0:
        low.y += moved.y
    elif grabbed.y > 0:
        high.y += moved.y
    return Rect2i(Vector2i(mini(low.x, high.x), mini(low.y, high.y)), (high - low).abs())


## The whole-pixel box between two points, whichever way round they are.
##
## Both corners round to the nearest pixel edge. Flooring the low one and
## ceiling the high one made every drag whose pointer sat a fraction into a
## pixel one pixel larger than the hand moved, and a drag of 640 came out 641.
static func _box(one: Vector2, other: Vector2) -> Rect2i:
    var low := Vector2i(roundi(minf(one.x, other.x)), roundi(minf(one.y, other.y)))
    var high := Vector2i(roundi(maxf(one.x, other.x)), roundi(maxf(one.y, other.y)))
    return Rect2i(low, high - low)


## Which handle *at* is on, `Vector2i.ZERO` for the inside of the rectangle,
## and null for anywhere else, which starts a fresh rectangle instead.
func _handle_under(at: Vector2) -> Variant:
    var reach := HANDLE_REACH / _zoom()
    var centre := Rect2(_rect).get_center()
    var edges := {-1: Vector2(_rect.position), 0: centre, 1: Vector2(_rect.end)}
    for x: int in [-1, 0, 1]:
        for y: int in [-1, 0, 1]:
            if x == 0 and y == 0:
                continue
            var point := Vector2(edges[x].x, edges[y].y)
            if at.distance_to(point) <= reach:
                return Vector2i(x, y)
    # Written out rather than as a ternary, which cannot type a Vector2i and a
    # null as one thing.
    if Rect2(_rect).has_point(at):
        return Vector2i.ZERO
    return null


## The view's zoom, held off zero, which turns a reach in screen pixels into
## document pixels.
func _zoom() -> float:
    var view: SaView = surface.view if surface != null else null
    return maxf(view.get_zoom() if view != null else 1.0, 0.01)


## The pending rectangle, the ratio it is locked to, and the crop the active
## layer has in document pixels, empty when this is not the tool the machine is
## on.
##
## A dimmed box in a screenshot cannot be measured, and whether it is exactly 16:9
## is arithmetic. Answered here rather than read off this tool by name from
## `sara-godot/ui/`, because the state report asks each tool.
func capture_report(tool_name: StringName, active: bool) -> Dictionary:
    if not active:
        return {}
    return {
        "crop":
        {
            "tool": String(tool_name),
            "pending_rect": SaReportShapes.rect(Rect2(pending_rect())),
            "ratio": ratio,
            "mode": ["layer", "canvas", "canvas_delete"][mode],
            "locked_ratio": locked_ratio(),
            "session": _open,
            "layer_crop": SaReportShapes.rect(Rect2(_layer_crop())),
        }
    }


## The active layer's crop through its map, in document pixels, empty for none.
func _layer_crop() -> Rect2i:
    var doc: SaDocument = document()
    var live := _live()
    if live == null or doc == null or doc.active_layer == null:
        return Rect2i()
    var box: Rect2i = live.call(&"crop_box", doc.active_layer)
    return box
