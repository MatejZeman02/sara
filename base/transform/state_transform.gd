## The transform tool: the box, its eight handles, and translate, scale and
## rotate.
##
## Selecting the tool puts a box around what would be transformed, which is the
## selection's bounds when there is a selection and the box round the paint of
## the layers acted on when there is not, the layers picked in the Layers
## docker or the active layer alone. Dragging the body of the box moves the
## pixels under it, a corner or an edge handle scales, a drag just outside a
## corner rotates about the box's centre, Enter commits as one undo step and
## Escape puts everything back.
##
## **With no selection the handles drive the layer's live transform**: the
## box is the layer's paint through the map it is drawn by, a drag rewrites
## that map as it goes and lifts nothing, Enter is one step and Escape draws
## the map the session opened on. A selection and Freehand lift and resample
## at Enter, since a live transform moves the whole layer and a mesh is not a
## 3 by 3 map, and the corner says so.
##
## It draws nothing. Before a lift `preview_shape` returns the crop's
## `{"rect", "handles"}`, which `ui/canvas/selection_overlay.gd` already drew,
## and a lift `{"quad", "handles"}`, since a turned picture is no rectangle. The
## crop's `dim` is left off on purpose: dimming what is outside says "everything
## out here is going away", which is true of a crop and false of a transform.
##
## **The pixels are `sa_transform.gd`'s**, beside this file with the one tool
## that asks for it, and nothing about the lift, the preview or the history is
## decided here. This file is the gesture: which document pixel the pointer is
## on, whether the press was inside the box, and what Enter and Escape mean at
## each moment.
##
## The shear and the options rows are here too, and the handle arithmetic is
## `SaTransformHandles` beside this. The points a perspective corner, an edge
## over a placed map and a warp's control point move are `SaTransformPoints`
## in `warps`, which the press and the drag here hand those gestures to.
extends ToolState

## By path rather than by `class_name`, the way the wand reaches its own engine
## beside it, so the tool builds the pass without waiting on the class cache.
const SaTransformScript = preload("res://modules/sara-base-modules/base/transform/sa_transform.gd")
## Select > Transform Selection's pass, which moves the outline and lifts nothing.
const SaTransformShapeScript = preload("res://modules/sara-base-modules/base/transform/selection/sa_transform_shape.gd")
## A group's pass, every layer inside it moved as one.
const SaTransformGroupScript = preload("res://modules/sara-base-modules/base/transform/group/sa_transform_group.gd")

## Escape with no lift. Stays true until the tool is left, which is where
## `reset` runs.
var _dropped: bool = false

## Held from the first lift to the commit, because the lift cuts a hole and the
## hole would otherwise move the box out from under the drag: `target_box`
## measures the layer's paint, and after a lift that is the paint minus the
## piece in the air.
var _held_box: Rect2i = Rect2i()
var _pass: SaTransformScript = null

## The box round the paint the tool would move, measured again only when the
## layers, their chunks or the history have moved.
var _measure: SaTransformGroupScript.Measure = SaTransformGroupScript.Measure.new()

## The box may stand where a hand cannot take it when the tool opens, and the
## frame's tick answers it once. A gesture's release never asks, because the
## painter put the box there with the view where they wanted it.
var _reach_pending: bool = true
## How near a handle a press has to land, in screen pixels, how far outside a
## corner still counts as reaching for the rotation, and the side of the square
## a handle and a warp's point are drawn as. Screen rather than document pixels
## because a grab is a gesture of the hand, which is the reach `state_crop.gd`
## uses for the same reason, and a handle drawn by the document's pixels was four
## screen pixels over a photograph seen whole.
const HANDLE_REACH: float = 10.0
const ROTATE_REACH: float = 28.0
const HANDLE_SIDE: float = 9.0

enum Gesture { NONE, MOVE, SCALE, ROTATE, SHEAR, CORNER, PAIR, WARP, EDGE, EDGE_PAIR, CAGE }

## What a handle drag means, said out loud on the canvas instead of left to a
## modifier a painter has to know.
##
## **Normal** is the plain reading of a handle: an edge or a corner scales,
## Shift keeps the picture's proportions and Ctrl on an edge shears. **Shear** makes every handle lean the box over
## with no modifier held and none scale: a corner leans the edge it sits on
## along the drag's longer axis, so the box stays a parallelogram of its area.
## **Perspective** places the four corners and the pixels follow the homography
## through them, which a `Transform2D` cannot hold. A corner drag moves the other
## end of the edge it runs along the mirror way, and a side handle the opposite
## side the other way along it. Shift moves the one corner or the one side.
##
## **Freehand** is a grid of three by three
## control points over the box, each dragged on its own, the pixels following
## by a bilinear patch per cell through `SaTransform`'s mesh. The eight
## handles give way to the nine points, drawn as they are, and a press between
## them inside the box takes nothing, since a move is one cell away.
##
## **Mirrored** is Perspective with a partner for every handle. A corner drag
## moves the grabbed corner and moves the diagonally opposite one by the same
## displacement turned through the quad's centre, so that diagonal keeps its
## midpoint, and a side handle moves its edge and the opposite edge the same
## way. The picture follows the homography through the four, as Perspective's
## does, so a quad the mode has placed commits exactly as Perspective would.
##
## **Cage** is a polygon clicked round the subject, closed on its first point,
## whose points are then dragged, the picture inside following by Green
## coordinates through `SaTransformCage` and what is outside staying.
enum Mode { NORMAL, PERSPECTIVE, SHEAR, FREEHAND, MIRRORED, CAGE }

## The mode the handles are read in. Written by the Tool Options row and by a
## capture step, and read on every press.
var mode: int = Mode.NORMAL

## The four corners a perspective drag placed and the warp's nine control
## points, with their copies frozen at the press. A fresh one is the box with
## nothing placed on it, which is what `reset` and `_rest` put back.
var _points: SaTransformPoints = SaTransformPoints.new()
## Cage mode's polygon and the weights it closed with, fresh where `_points` is.
var _cage: SaTransformCage = SaTransformCage.new()

## A motion has moved the box since the Tool Options docker was last told. The
## GPU dispatch itself is deferred inside `SaTransform`, which keeps its own
## map current on every call so `pending_quad()` and the rest never go stale,
## and `_pass.tick()` below is what actually pays for it. This flag is the
## docker sync alone, so a tablet's few hundred events a second cost one
## `_sync_ui_from_settings` a frame rather than one each, and a frame's motions
## are one gesture as far as the docker is concerned.
var _preview_pending: bool = false
var _rows_read_at: Array = []  ## `SaTransformLive.under` when the rows were last told.

var _dragging: bool = false
var _gesture: int = Gesture.NONE
var _anchor: Vector2 = Vector2.ZERO
## The whole gesture, as one map from the box's own frame to the canvas.
## Every gesture composes onto this rather than keeping a number of its own,
## which is what let the shear be a case rather than a fourth field.
var matrix: Transform2D = Transform2D.IDENTITY
var _matrix_at_press: Transform2D = Transform2D.IDENTITY

## The handle the press grabbed, as -1, 0 or 1 per axis, and where the pointer
## was in the box's own frame when the press landed. A scale and a shear both
## hold the far side still, which is what makes a handle drag read as pulling
## the box rather than as moving it.
var _grabbed: Vector2i = Vector2i.ZERO
var _press_in_box: Vector2 = Vector2.ZERO

## The rotate arrow, the hover's and the held turn's, built on the first ask and
## handed back after, since the machine asks every frame and tells by the object.
var _turn_pictures: Array[SaCursorPicture] = []


## Called on the outgoing tool, so leaving the transform and coming back is what
## brings a dropped box back. A lift in the air when the tool is left is put
## back rather than committed: a painter who reaches for another tool has not
## said yes to the move, and there is no way to ask them.
func reset() -> void:
    _dropped = false
    if is_moving():
        _pass.cancel()
    _held_box = Rect2i()
    # Another tool may paint before this one is back, and a held tool's stroke
    # need not move the history, so the box is measured again on return.
    _measure.forget()
    _reach_pending = true
    _dragging = false
    _gesture = Gesture.NONE
    matrix = Transform2D.IDENTITY
    _points = SaTransformPoints.new()
    _cage = SaTransformCage.new()
    _preview_pending = false


## The box on screen: where the picture currently is, or an empty rectangle once
## Escape has dropped it. Public and named like the crop's `pending_rect` so a
## test and a capture step can read it without a screenshot.
func pending_box() -> Rect2i:
    if _dropped:
        return Rect2i()
    if is_moving():
        return _pass.landed_bounds()
    if _resting() == null:
        return target_box()
    var quad := pending_quad()
    var area := Rect2(quad[0], Vector2.ZERO) if not quad.is_empty() else Rect2()
    for corner in quad:
        area = area.expand(corner)
    var low := Vector2i(area.position.floor())
    return Rect2i(low, Vector2i(area.end.ceil()) - low)


## The four corners of the box as it stands, which a rotated box needs and a
## rectangle cannot say. Empty when there is no box. With no session open they
## are the box's own through the active layer's live transform, so a layer the
## tool opens on shows its handles where its transform put them.
func pending_quad() -> PackedVector2Array:
    if _dropped:
        return PackedVector2Array()
    if is_moving():
        return _pass.landed_quad()
    var box := target_box()
    if box.size.x <= 0 or box.size.y <= 0:
        return PackedVector2Array()
    var quad := SaHomography.corners_of(box)
    var live := _resting()
    if live != null:
        for i in quad.size():
            quad[i] = live.map_point(quad[i])
    return quad


## The live transform the active layer is drawn through, which the box stands
## on with nothing selected and one layer acted on, and null otherwise. A
## picked set's box is a plain rectangle round what its layers show.
func _resting() -> SaLiveTransform:
    var doc: SaDocument = document()
    if doc == null or (doc.selection != null and doc.selection.active) or not _picked().is_empty():
        return null
    return SaLiveTransform.of(doc.active_layer)


## The layers the painter picked in the Layers docker, the set the Layer
## menu's commands act on, when there are several, and empty when the tool
## acts on the active layer alone.
func _picked() -> Array[SaLayer]:
    var doc: SaDocument = document()
    var chosen: Array[SaLayer] = []
    if doc != null and doc.picked != null:
        chosen = doc.picked.acted_on(doc)
    return chosen if chosen.size() > 1 else ([] as Array[SaLayer])


## The map a gesture starts from and the rows read: the session's while one is
## open, and otherwise the affine part of the active layer's live transform.
func _map() -> Transform2D:
    if is_moving():
        return matrix
    var live := _resting()
    if live == null:
        return Transform2D.IDENTITY
    return SaTransformLive.resting(live.matrix, target_box())[0]


## The rectangle a transform acts on, or an empty one when there is nothing to
## act on: the box held since the lift while a move is in the air, and otherwise
## the selection's bounds while a selection is active and the box round the
## active layer's paint when there is none, both clipped to the canvas. It
## answers the same whether or not the box has been dropped, because dropping
## is about the box on screen rather than about what a transform would take.
##
## Asked afresh every time rather than held, so switching layer or changing the
## selection moves the box without anything having to tell this tool that
## either happened. The lift is what holds it still, and `painted_bounds` keeps
## its measure until the layer or the history moves.
func target_box() -> Rect2i:
    var doc: SaDocument = document()
    if _held_box.size.x > 0 and _held_box.size.y > 0:
        return _held_box
    if doc == null:
        return Rect2i()
    var canvas := Rect2i(Vector2i.ZERO, doc.canvas_size)
    if doc.selection != null and doc.selection.active:
        return doc.selection.bounds.intersection(canvas)
    var picked := _picked()
    if not picked.is_empty():
        return _measure.box_of(doc, SaTransformGroupScript.movable(doc, picked), false).intersection(canvas)
    return painted_bounds(doc.active_layer).intersection(canvas)


## The box round *layer*'s paint, in document pixels, tight by the reduce
## `SaTransformGroup.Measure` runs. Empty when the layer is null or holds no
## paint, which is a fresh layer nobody has painted on.
func painted_bounds(layer: SaLayer) -> Rect2i:
    var doc: SaDocument = document()
    if layer == null:
        return Rect2i()
    if layer.is_group:
        return _measure.box_of(doc, SaTransformGroupScript.members(doc, layer), false)
    return _measure.box_of(doc, [layer], true)


## Whether a move is in the air, so the Tool Options docker and a state dump can
## tell a box that is only drawn from one that has pixels lifted behind it or a
## layer's live transform under its handles.
func is_moving() -> bool:
    return _pass != null and (_pass.is_lifted() or _pass.is_held())


## The scale the handles have pulled the picture to.
func move_scale() -> Vector2:
    return _map().get_scale()


## The angle the picture has been turned through, in radians.
func move_angle() -> float:
    return _map().get_rotation()


## How far the shear has leaned the box over, in radians. Zero is a box whose
## sides are still at right angles.
func move_skew() -> float:
    return _map().get_skew()


## How far the picture's centre has moved from where it was lifted.
func move_offset() -> Vector2i:
    var centre := _centre_in_box()
    return Vector2i((_map() * centre - centre).round())


## The rows in the Tool Options docker, each a reading of the one matrix and
## each writing it back the same way a handle drag does.
##
## A `Transform2D` has exactly six degrees of freedom and these are the six, so
## the decomposition is exact rather than a best fit: a number typed here and a
## handle pulled to the same place end in the same document.
##
## **Lifting on the first write** is what makes them work before a drag. A row
## edited while nothing is in the air cuts the hole first, exactly as the first
## motion of a drag does, because there is no other moment for it to happen at.
@export var move_x: float = 0.0:
    get:
        return (_map() * _centre_in_box() - _centre_in_box()).x
    set(value):
        _write_rows(Vector2(value, move_y), move_scale(), move_angle(), move_skew())

@export var move_y: float = 0.0:
    get:
        return (_map() * _centre_in_box() - _centre_in_box()).y
    set(value):
        _write_rows(Vector2(move_x, value), move_scale(), move_angle(), move_skew())

## The size, as a fraction of what was lifted. Percent rather than pixels
## because the box is whatever was lifted and a width in pixels
## reads as a promise about the picture that the box cannot keep.
@export var scale_x: float = 1.0:
    get:
        return move_scale().x
    set(value):
        _write_rows(Vector2(move_x, move_y), Vector2(value, scale_y), move_angle(), move_skew())

@export var scale_y: float = 1.0:
    get:
        return move_scale().y
    set(value):
        _write_rows(Vector2(move_x, move_y), Vector2(scale_x, value), move_angle(), move_skew())

@export var angle_degrees: float = 0.0:
    get:
        return rad_to_deg(move_angle())
    set(value):
        _write_rows(Vector2(move_x, move_y), move_scale(), deg_to_rad(value), move_skew())

@export var shear_degrees: float = 0.0:
    get:
        return rad_to_deg(move_skew())
    set(value):
        _write_rows(Vector2(move_x, move_y), move_scale(), move_angle(), deg_to_rad(value))

## The mode, `Mode` above, held here rather than on the pass for the reason the
## filter is: a painter picks the mode before anything is in the air.
##
## Changing it mid-gesture drops the corners or the nine points the new mode
## has no handle for and keeps the affine part of the map, so the mode row
## moves the handles rather than the picture.
@export var transform_mode: int = Mode.NORMAL:
    set(value):
        var caged := mode == Mode.CAGE
        transform_mode = clampi(value, 0, Mode.size() - 1)
        mode = transform_mode
        # A layer's live transform holds no mesh, so Freehand ends a live
        # session as Enter would, and the warp after it lifts. A cage closes
        # on the picture as it lies, so entering Cage ends any session.
        if (_bends(mode) and _pass != null and _pass.is_held()) or (mode == Mode.CAGE and not caged and is_moving()):
            commit_move()
        # The corners, the mesh's nine points and the cage are readings no
        # other mode has a handle for, and the affine part stays.
        var dropped := _points.drop(_on_corners(transform_mode), transform_mode == Mode.FREEHAND)
        if caged and mode != Mode.CAGE:
            dropped = dropped or not _cage.points().is_empty()
            _cage = SaTransformCage.new()
        if dropped and _pass != null and is_moving():
            _pass.preview_matrix(matrix)
            EventBus.tool_options_moved.emit()

## Bilinear or nearest, which is `SaResampleKernel.Filter`. Held here rather than
## on the pass, because the pass is built at the first lift and a painter
## chooses the filter before there is one.
@export var filter_mode: int = SaResampleKernel.Filter.BILINEAR:
    set(value):
        filter_mode = value
        if _pass != null:
            _pass.filter = value
            if _pass.is_lifted():
                _pass.preview_matrix(matrix)


## Builds the matrix the six numbers describe and hands it to the pass.
func _write_rows(offset: Vector2, scale: Vector2, angle: float, skew: float) -> void:
    if not is_moving() and not _lift(target_box()):
        return
    var centre := _centre_in_box()
    var basis := Transform2D(angle, scale, skew, Vector2.ZERO)
    _pass.preview_matrix(Transform2D(basis.x, basis.y, centre + offset - basis.basis_xform(centre)))
    matrix = _pass.matrix
    # The other five rows are readings of the matrix this one just rewrote, so a
    # write to one moves the five beside it. The docker's own write comes back
    # through here too, and its listener is muted, so this cannot loop.
    EventBus.tool_options_moved.emit()


## What `ui/canvas/selection_overlay.gd` draws, on the frame it asks. A rectangle until
## the picture is in the air, a quad once it can be turned.
##
## **The vocabulary is shapes and not tools**. `lines` is an array of polylines,
## `knots` an array of points and `cells` a row of boxes with a shape in each,
## and the overlay draws those three without knowing what drew them. `mesh` and
## `modes` said both at once, which is what put a `SaTransformMesh` call and the
## four mode constants in the skeleton.
##
## **`ants` is the map the selection outline is drawn through**. The box followed
## the drag and the outline did not, so a painter dragged a piece out of a box
## that stayed behind and could not see where the selection would land. It is the
## same `Transform2D` the lifted picture is previewed through, so the outline and
## the preview are the same gesture rather than two readings of it, and it covers
## rotation, scale and shear for nothing extra. Absent while nothing is in the
## air, which is what tells the overlay to draw the mask where it is stored.
func preview_shape() -> Dictionary:
    var quad := pending_quad()
    if quad.size() < 4:
        return {}
    # Freehand's nine points from the moment the mode is picked, the grid `_press` grabs.
    var grid := SaTransformPoints.shape_of(SaTransformMesh.grid_over(quad)) if mode == Mode.FREEHAND else {}
    # The strip's cells, and the side every handle and point is drawn at.
    var strip := {"cells": SaTransformModeStrip.cells(quad, transform_mode, 1.0 / _view_zoom()), "handle_side": HANDLE_SIDE}
    if mode == Mode.CAGE:
        return {"quad": quad, "handles": false}.merged(strip, true).merged(_cage.shape(), true)
    if not is_moving():
        # A layer drawn through a live transform stands as the quad it puts
        # its box at, which a rectangle cannot say once it is turned.
        var box := {"quad": quad} if _resting() != null else {"rect": Rect2(pending_box())}
        return box.merged({"handles": true}).merged(strip, true).merged(grid, true)
    # No `ants` under a perspective map: the outline is drawn through a
    # `Transform2D`, which cannot hold a homography, so the mask stays where it
    # is stored and the quad says where the picture went. A perspective outline
    # is a shader question of its own.
    if _pass != null and _pass.is_warped():
        # The mesh's grid and its nine points in place of the eight
        # handles, and no `ants` for the reason the perspective gives.
        return {"quad": quad, "handles": false}.merged(strip, true).merged(SaTransformPoints.shape_of(_pass.mesh()), true)
    if _pass != null and _pass.is_perspective():
        return {"quad": quad, "handles": true}.merged(strip, true)
    return {"quad": quad, "handles": true, "ants": matrix}.merged(strip, true).merged(grid, true)


## Enter commits and hands the machine back to the tool the painter came
## from, Escape puts a move back and otherwise drops the box, and a drag
## decides its gesture from where the press landed. Enter with nothing lifted
## commits nothing and stays, so a stray Enter does not throw the painter out
## of a tool they have only just picked.
func handle_input(event: InputEvent) -> void:
    var doc: SaDocument = document()
    if doc == null:
        return
    var key := event as InputEventKey
    if key != null and key.keycode == KEY_SHIFT and _dragging and not key.echo:
        # Shift pressed or let go with the hand still is a motion of its own,
        # so the box snaps to its ratio or frees its axes without a nudge.
        _drag(get_document_mouse_position(), key.pressed)
        return
    if key != null and key.pressed:
        if key.keycode == KEY_ENTER or key.keycode == KEY_KP_ENTER:
            if commit_move():
                request_hand_back()
        elif key.keycode == KEY_ESCAPE:
            if is_moving():
                cancel_move()
            elif not _cage.points().is_empty():
                _cage = SaTransformCage.new()
            else:
                _dropped = true
        return

    var button := event as InputEventMouseButton
    if button != null and button.button_index == MOUSE_BUTTON_LEFT:
        if button.pressed:
            _press(get_document_mouse_position(), button.shift_pressed, button.ctrl_pressed)
        else:
            _dragging = false
            _gesture = Gesture.NONE
        return

    var motion := event as InputEventMouseMotion
    if _dragging and motion != null:
        _drag(get_document_mouse_position(), motion.shift_pressed)


## The frame's own work: `SaTransform.tick` is the GPU dispatch a motion asked
## for, and this tool's own `_preview_pending` is the Tool Options sync that
## rode along with it. Both wait for whatever the map is by the time the frame
## gets here, not for the motion that first changed it.
func tick(_delta: float) -> void:
    if _pass != null:
        _pass.tick()
    if _reach_pending:
        _reach_pending = false
        bring_handles_in()
    var under := SaTransformLive.under(document())
    if under != _rows_read_at and not is_moving() and not _dragging:
        _rows_read_at = under
        _preview_pending = true
    if not _preview_pending:
        return
    _preview_pending = false
    EventBus.tool_options_moved.emit()


## Writes the move into the layer as one history step. True when there was one.
func commit_move() -> bool:
    if not is_moving():
        return false
    var done: bool = _pass.commit()
    _rest()
    return done


## An undo or a redo commits the move first, so the move is the step it takes
## back. Left in the air, the undo takes back the stroke under the lift and the
## next Enter lands the moved picture over a history that no longer holds it.
## The tool stays, unlike Enter's hand back, because the painter asked for an
## undo and not for the move to be over.
func close_session() -> bool:
    return commit_move()


## A session its map has moved. One put down where it was writes no step, for
## the reason the pass's `commit` gives, so the pass's own reading is asked here.
func holds_session() -> bool:
    return is_moving() and _pass.has_moved()


## The Flip Horizontally button: the picture in the air mirrored across its
## box's own vertical middle, lifting it first when nothing is in the air yet.
func flip_horizontal() -> void:
    _flip(true)


## The Flip Vertically button, across the box's own horizontal middle.
func flip_vertical() -> void:
    _flip(false)


## The map times minus one on one axis of the box, about the box's centre.
##
## **On the box's side of the map**, the way a scale is, so a turned picture
## flips along its own axis and stays turned by the same angle, and the box on
## screen does not move: only what is in it is mirrored. A selection's pixels
## are what the lift took, so the button flips those, and the ants follow
## through `preview_shape`, which draws through this same matrix.
##
## A placed perspective quad or a warp's nine points are a map the matrix
## cannot hold, so `SaTransformPoints.flip` re-reads them in mirror order
## instead.
func _flip(horizontal: bool) -> void:
    if mode == Mode.CAGE:
        return
    if not is_moving() and not _lift(target_box()):
        return
    if _points.holds():
        _placed(_points.flip(horizontal, _held_box, _pass))
    else:
        var centre := _centre_in_box()
        var axes := Vector2(-1.0, 1.0) if horizontal else Vector2(1.0, -1.0)
        var mirror := Transform2D(Vector2(axes.x, 0.0), Vector2(0.0, axes.y), centre - centre * axes)
        matrix = matrix * mirror
        _pass.preview_matrix(matrix)
    EventBus.tool_options_moved.emit()


## Puts the pixels back where they were lifted from.
func cancel_move() -> void:
    if _pass != null:
        _pass.cancel()
    _rest()


func _rest() -> void:
    _held_box = Rect2i()
    matrix = Transform2D.IDENTITY
    _points = SaTransformPoints.new()
    _cage = SaTransformCage.new()
    _dragging = false
    _gesture = Gesture.NONE
    _preview_pending = false
    # A commit or a cancel puts the six back to zero, which is as much a move
    # the rows have to follow as the drag that got there.
    EventBus.tool_options_moved.emit()


## Pans the view by the least that puts every handle and the mode strip's
## cells inside the room between the dockers, once as the tool opens, so a box
## that opens under a docker can be taken.
##
## **Only as the tool opens, never as a gesture ends.** A reach on every
## release that left a handle outside the room would move the whole view by a
## thousand pixels the frame the hand let go of a picture dragged past the
## window's edge, and the tool would read as jumping the view when done. A painter who leaves a handle under a
## docker pans to it as they pan for anything else.
##
## **Panning, rather than clamping the box or moving the dockers.** A handle
## under a docker cannot be pressed, because the press lands on the docker.
## Clamping the gesture would refuse a place the painter asked for, and the
## picture may belong half under a docker. Moving a docker moves the painter's
## layout. The view is the one thing a painter moves all the time without
## meaning anything by it, and the least pan keeps the picture where the eye
## already was. `SaView.get_free_rect` is the room a fit and a centre use, the
## visible rectangle less the docker columns, so the handles land where the
## document would. An axis the handles cannot all fit across is left alone,
## because no pan along it takes every one in and any pan would push others
## out, and zooming out is the painter's call. A docker floating in the middle
## of the canvas is one the free rectangle leaves in, so the windows over the
## canvas are kept clear of as well, through `SaTransformHandles.clear_shift`.
##
## Public so a suite drives it the way the tick does.
func bring_handles_in() -> void:
    var view: SaView = surface.view if surface != null else null
    var quad := pending_quad()
    if view == null or quad.size() < 4:
        return
    var points := pending_mesh()
    if points.is_empty():
        for corner: Vector2i in SaTransformHandles.HANDLE_CORNERS:
            points.append(SaTransformHandles.point_on(quad, corner))
    # The strip above the box is pressed the way a handle is.
    for cell: Rect2 in SaTransformModeStrip.boxes(quad, 1.0 / _view_zoom()):
        points.append(cell.position)
        points.append(cell.end)
    var screen := PackedVector2Array()
    for point: Vector2 in points:
        screen.append(view.document_to_screen(point))
    var shift := SaTransformHandles.clear_shift(screen, view.get_free_rect(), SaTransformHandles.windows_over(), HANDLE_REACH)
    if shift != Vector2.ZERO:
        view.set_pan(view.get_pan() + shift)


## Which of the eight handles *at* is on, or null, through `SaTransformHandles`.
func _handle_under(at: Vector2) -> Variant:
    return SaTransformHandles.under(pending_quad(), at, HANDLE_REACH / _view_zoom())


## Document pixels per screen pixel, so a reach written in screen pixels means
## the same thing at every zoom.
func _view_zoom() -> float:
    var view: SaView = surface.view if surface != null else null
    return maxf(view.get_zoom() if view != null else 1.0, 0.01)


## The rotate arrow where a press would turn the box and all through a turn
## being dragged, and nothing elsewhere, which leaves the descriptor's move
## shape. Godot has no rotate shape among its stock ones, so the arrow is a
## picture of the theme's standing in the move shape's slot.
func cursor_picture() -> SaCursorPicture:
    var turns := _dragging and _gesture == Gesture.ROTATE
    if not _dragging and mode != Mode.CAGE:
        var points := pending_mesh() if mode == Mode.FREEHAND else PackedVector2Array()
        var at := get_document_mouse_position()
        turns = SaTransformHandles.turns_at(pending_quad(), at, 1.0 / _view_zoom(), HANDLE_REACH, ROTATE_REACH, points)
    if turns and _turn_pictures.is_empty():
        for held: bool in [false, true]:
            _turn_pictures.append(SaCursorPicture.new(&"rotate", SaUI.get_icon("cursor_rotate"), Vector2(0.5, 0.5), held))
    return _turn_pictures[int(_dragging)] if turns else null


## What the mode of the strip's cell under the pointer does, none mid-drag.
func tooltip() -> String:
    return "" if _dragging else SaTransformModeStrip.tip(pending_quad(), 1.0 / _view_zoom(), get_document_mouse_position())


## *shift* and *ctrl* come off the event rather than out of `Input`, because a
## press carries the modifiers it was made with and a scenario's injected press
## has no key held down anywhere for `Input.is_key_pressed` to find.
func _press(at: Vector2, shift: bool, ctrl := false) -> void:
    var quad := pending_quad()
    if quad.size() < 4:
        return
    # The strip is drawn over the canvas by the overlay, which ignores the
    # mouse the way every overlay does, so the press that lands on it arrives
    # here and is answered before any gesture is chosen. One description of
    # where the strip is, asked twice of `SaTransformModeStrip` with the same
    # number, so the picture and the press cannot drift apart.
    var cell := SaTransformModeStrip.pick(quad, 1.0 / _view_zoom(), at)
    if cell >= 0:
        transform_mode = cell
        EventBus.tool_options_moved.emit()
        return
    _anchor = at
    _matrix_at_press = _map()
    _press_in_box = _matrix_at_press.affine_inverse() * at
    # A cage's press places, closes or grabs one of its points, and only a
    # grab is a drag.
    if mode == Mode.CAGE:
        _dragging = _cage.press(at, HANDLE_REACH / _view_zoom(), target_box()) == SaTransformCage.Press.GRABBED
        _gesture = Gesture.CAGE if _dragging else Gesture.NONE
        return
    # The four corners and the nine control points are frozen here whatever the
    # press turns out to mean, and under Freehand the nine are the handles.
    if _points.press(quad, at, HANDLE_REACH / _view_zoom(), mode == Mode.FREEHAND):
        _gesture = Gesture.WARP
        _dragging = true
        return
    var grabbed: Variant = _handle_under(at)
    if grabbed != null:
        _grabbed = grabbed
        # Ctrl on an edge handle leans the box over, Photoshop's skew chord.
        # Under Normal any other handle scales, and Shift held on a motion
        # keeps the box's ratio, which `_drag` reads.
        var edge_handle: bool = _grabbed.x == 0 or _grabbed.y == 0
        var corner_handle: bool = _grabbed.x != 0 and _grabbed.y != 0
        if _on_corners(mode) and corner_handle:
            # A corner moves a partner, the other end of the edge it is dragged
            # along or, under Mirrored, the corner across the centre. Under
            # Perspective Shift moves it alone.
            _gesture = Gesture.CORNER if shift and mode == Mode.PERSPECTIVE else Gesture.PAIR
        elif (_on_corners(mode) or mode == Mode.FREEHAND) and edge_handle:
            # A side handle moves the points the mode is made of rather than
            # scaling, which would throw away a corner or a control point a
            # hand had just placed. An edge is two corners, or three of the
            # nine. Shift under Perspective, and Freehand always, move the one
            # side alone.
            _gesture = Gesture.EDGE if mode == Mode.FREEHAND or (shift and mode == Mode.PERSPECTIVE) else Gesture.EDGE_PAIR
        elif mode == Mode.SHEAR:
            # The mode says what Shift says on an edge, and Shift goes on
            # saying it, so a painter who knows the modifier keeps it. A corner
            # here leans an edge too, the one `SaTransformHandles.lean` picks.
            _gesture = Gesture.SHEAR
        else:
            _gesture = Gesture.SHEAR if (edge_handle and ctrl) else Gesture.SCALE
        _dragging = true
        return

    # Under Freehand a press between the nine points moves nothing, so a
    # point missed is not the whole picture slid away.
    if Geometry2D.is_point_in_polygon(at, quad):
        _dragging = mode != Mode.FREEHAND
        _gesture = Gesture.MOVE if _dragging else Gesture.NONE
        return

    # Outside the box and within reach of a corner is the rotation, which is
    # where every other program puts it and costs no modifier.
    if SaTransformHandles.near_a_corner(quad, at, ROTATE_REACH / _view_zoom()):
        _gesture = Gesture.ROTATE
        _dragging = true


## The lift happens here rather than on the press, so a click inside the box
## that moves nothing costs nothing: a press that turned out not to be a drag
## would otherwise have cut a hole and put it straight back.
##
## **Every gesture is a composition onto the matrix the press froze**, rather
## than a number of its own. Move and rotate compose on the canvas side, because
## a painter drags in canvas pixels and turns what they see. Scale and shear
## compose on the box side, because both are named by which handle was grabbed
## and a handle is a place in the box, not on the screen. That split is why the
## shear needed no fourth field and no fourth branch anywhere below this
## function.
##
## *shift* is read on every motion, so Shift on a handle under Normal keeps
## the box's ratio from the motion it is pressed on to the one it is let go on.
func _drag(to: Vector2, shift: bool) -> void:
    if not is_moving():
        if to.distance_squared_to(_anchor) < 1.0:
            return
        if not _lift(target_box()):
            _dragging = false
            return

    var wanted := matrix
    match _gesture:
        Gesture.MOVE:
            wanted = Transform2D(0.0, (to - _anchor).round()) * _matrix_at_press
        Gesture.ROTATE:
            var centre := _matrix_at_press * _centre_in_box()
            var turn := (to - centre).angle() - (_anchor - centre).angle()
            wanted = Transform2D(0.0, centre) * Transform2D(turn, Vector2.ZERO) * Transform2D(0.0, -centre) * _matrix_at_press
        Gesture.SCALE:
            wanted = _matrix_at_press * SaTransformHandles.pull(target_box(), _grabbed, _matrix_at_press, to, shift)
        Gesture.SHEAR:
            wanted = _matrix_at_press * SaTransformHandles.lean(target_box(), _grabbed, _matrix_at_press, _press_in_box, to)
        Gesture.CORNER, Gesture.PAIR:
            _placed(_points.drag_corner(_grabbed, to, _gesture == Gesture.PAIR, mode == Mode.MIRRORED, _held_box, _pass))
            return
        Gesture.EDGE, Gesture.EDGE_PAIR:
            var paired := _gesture == Gesture.EDGE_PAIR
            var by := to - _anchor
            _placed(_points.drag_edge(_grabbed, by, paired, mode == Mode.FREEHAND, mode == Mode.MIRRORED, _held_box, _pass))
            return
        Gesture.WARP:
            _placed(_points.drag_point(to, _held_box, _pass))
            return
        Gesture.CAGE:
            _placed(_cage.drag(to, _held_box, _pass))
            return
        _:
            return

    if wanted.is_equal_approx(matrix):
        return
    # A map a hand has placed is carried through an affine gesture rather than
    # thrown away by it, which would flatten placed corners back to a box on
    # every motion. Only the mode row's setter and `reset` drop them now.
    if _points.holds():
        _placed(_points.carry(wanted * _matrix_at_press.affine_inverse(), _held_box, _pass))
        return
    # Read back, because the pass may hold the map short of what was asked,
    # a text layer's at its last move.
    _pass.preview_matrix(wanted)
    matrix = _pass.matrix
    # The docker sync waits for the frame's tick, as the GPU dispatch waits in
    # SaTransform's own, so a frame with several motions costs one of each.
    _preview_pending = true


## A placing the points took, read back as the matrix the pass now holds, with
## the docker sync left for the frame's tick. Nothing when they refused it, so
## the drag holds the last map that worked.
func _placed(done: bool) -> void:
    if not done:
        return
    matrix = _pass.matrix
    _preview_pending = true


## Whether *which* is a mode read as four corners through a homography, which
## Perspective and Mirrored both are and differ only in what a drag moves.
static func _on_corners(which: int) -> bool:
    return which == Mode.PERSPECTIVE or which == Mode.MIRRORED


## Whether *which* bends the picture through a mesh, which a layer's live
## transform cannot hold, so its session lifts.
static func _bends(which: int) -> bool:
    return which == Mode.FREEHAND or which == Mode.CAGE


## The mesh in the air, for a dump and a test, empty while none is.
func pending_mesh() -> PackedVector2Array:
    return _pass.mesh() if _pass != null and is_moving() and _pass.is_warped() else PackedVector2Array()


## The box's centre in its own frame.
func _centre_in_box() -> Vector2:
    var box := target_box()
    return Vector2(box.position) + Vector2(box.size) * 0.5


## Opens a session over *box*, which it holds: a live one on the active layer's
## transform with nothing selected, outside Freehand, on a smart layer, one that
## carries a live transform already and can take another, and otherwise the
## lift that resamples at Enter. An ordinary layer takes the lift, so Enter
## writes the moved paint into its chunks as one step and leaves no transform
## pending and no Apply Transform to press. The corner
## says so only for a selection and Freehand, which resample on a smart layer
## too. The engine is the `transform` role's when the machine handed this tool
## the registries, and the file beside this one when nothing did.
func _lift(box: Rect2i) -> bool:
    var doc: SaDocument = document()
    if not _picked().is_empty():
        return _lift_set(doc, _picked(), box)
    var layer := doc.active_layer
    var group := layer != null and layer.is_group
    if group and _bends(mode):
        EventBus.corner_notice.emit(tr(SaTransformGroupScript.BENDS_LINE))
        return false
    if _pass == null or _pass is SaTransformShapeScript or (_pass is SaTransformGroupScript) != group:
        var engine: Script = roles.script_for(&"transform") if roles != null else SaTransformScript
        _pass = SaTransformGroupScript.new(doc) if group else engine.new(doc)
    _pass.filter = filter_mode
    var selected := doc.selection != null and doc.selection.active
    var live := SaLiveTransform.of(layer) != null and SaLiveTransform.refusal(doc, layer, Basis.IDENTITY).is_empty()
    var smart := group or live
    if not selected and not _bends(mode) and smart:
        if not _pass.hold(layer, box):
            return false
        matrix = _pass.matrix
        # A perspective's four corners, placed, so a move or a turn carries
        # the map rather than flattening it.
        if _pass.is_perspective():
            _points = SaTransformPoints.new(_pass.landed_quad())
    elif _pass.lift(layer, box):
        var line := _lift_line(selected)
        if not line.is_empty():
            EventBus.corner_notice.emit(line)
    else:
        return false
    _held_box = box
    return true


## Opens one session over *box* on every layer *picked*: the group's pass,
## live while nothing is selected outside Freehand and Cage, and otherwise
## landed at Enter layer by layer. A picked group under a mesh is refused as
## a group alone is.
func _lift_set(doc: SaDocument, picked: Array[SaLayer], box: Rect2i) -> bool:
    if _bends(mode) and picked.any(func(layer: SaLayer) -> bool: return layer.is_group):
        EventBus.corner_notice.emit(tr(SaTransformGroupScript.BENDS_LINE))
        return false
    if not _pass is SaTransformGroupScript:
        _pass = SaTransformGroupScript.new(doc)
    _pass.filter = filter_mode
    var selected := doc.selection != null and doc.selection.active
    if not _pass.open_set(picked, box, selected or _bends(mode)):
        return false
    matrix = _pass.matrix
    var line := _lift_line(selected)
    if not line.is_empty():
        EventBus.corner_notice.emit(line)
    _held_box = box
    return true


## Select > Transform Selection: the selection's outline moved alone until Enter
## or Escape, a move in the air committed first. False with nothing selected.
func transform_selection() -> bool:
    commit_move()
    var doc: SaDocument = document()
    var shape := SaTransformShapeScript.new(doc)
    shape.filter = filter_mode
    if doc == null or not shape.lift(doc.active_layer, target_box()):
        return false
    _pass = shape
    _held_box = shape.bounds
    _dropped = false
    EventBus.corner_notice.emit(tr(shape.OPEN_LINE))
    return true


## What the corner says of a lift that a smart layer's live transform could not
## have held: a selection's pixels or a mesh. Empty for a whole ordinary layer,
## whose lift is the default and needs no word.
func _lift_line(selected: bool) -> String:
    if selected:
        return tr("The selection's pixels are resampled into the layer at Enter, since a layer's live transform moves all of it.")
    if mode == Mode.FREEHAND:
        return tr("Freehand is applied when you press Enter and cannot be edited afterwards.")
    if mode == Mode.CAGE:
        return tr("The cage is applied when you press Enter and cannot be edited afterwards.")
    return ""


## The box the transform would act on, empty when this is not the tool the
## machine is on.
##
## A screenshot shows a white rectangle without saying whether it came from the
## selection or from the layer's paint, and an empty box and a dropped one look
## the same in a picture. Answered here rather than read off this tool by name
## from `sara-godot/ui/`, because the state report asks each tool.
func capture_report(tool_name: StringName, active: bool) -> Dictionary:
    if not active:
        return {}
    var moved := move_offset()
    var pulled := move_scale()
    return {
        "transform":
        {
            "tool": String(tool_name),
            # Which of the four modes is picked, because the strip on the
            # canvas and the row in the docker write the same property and a
            # screenshot of a box says neither. Without it a scenario can show
            # that a press landed on the strip and not what it did.
            "mode": transform_mode,
            "pending_box": SaReportShapes.rect(Rect2(pending_box())),
            "target_box": SaReportShapes.rect(Rect2(target_box())),
            # Whether pixels are in the air and how far they have come. A
            # screenshot of a moved picture and of a picture painted there in the
            # first place are the same picture.
            "moving": is_moving(),
            # Whether the move is the layer's live transform rather than
            # lifted pixels, which a shot of either cannot tell apart.
            "live": _pass != null and _pass.is_held(),
            # The outline moving alone, which a shot cannot tell from a lift.
            "selection_only": _pass is SaTransformShapeScript and is_moving(),
            "offset": {"x": float(moved.x), "y": float(moved.y)},
            # A screenshot of a turned box cannot say by how much, and a scale of
            # 0.999 and one of 1.0 are the same picture.
            "scale": {"x": pulled.x, "y": pulled.y},
            "degrees": rad_to_deg(move_angle()),
            # The shear, in degrees off square. Zero is a box whose sides are
            # still at right angles, which no other field can say.
            "skew_degrees": rad_to_deg(move_skew()),
            "quad": SaReportShapes.points(pending_quad()),
            # The nine control points the overlay draws, a warp's or the grid a
            # Freehand box rests under, which a shot of a bent picture cannot say.
            "mesh": SaReportShapes.points(preview_shape().get("knots", PackedVector2Array()) as PackedVector2Array),
            # The cage's points and whether it has closed, which the knots
            # above cannot say of an outline still being clicked.
            "cage": SaReportShapes.points(_cage.points()),
            "cage_closed": _cage.closed,
        }
    }
