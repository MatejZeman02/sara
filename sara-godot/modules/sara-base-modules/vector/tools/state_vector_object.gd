## The Object tool: picks the objects of a vector layer, moves them by a drag
## and resizes one by the eight handles of its box.
##
## A press on an object picks it and drags the picked set, Shift on the press
## adds it to the set or takes it out, and a press on nothing drops the pick.
## With one object picked, a press on one of its handles pulls that side or
## corner, and Shift held keeps a corner's pull to the box's proportions.
## Delete or Backspace takes the picked objects off the layer.
##
## **The drag redraws as it goes and is one step when let go.** Each frame the
## pointer moved, the picked objects are given their new boxes and the door
## redraws only the bounds each left and reached (hard rule 2). The history
## records the objects' JSON from before the press and after the release, so
## an undo puts the whole drag back at once.
extends ToolState

const VectorObject := preload("res://modules/sara-base-modules/vector/sa_vector_object.gd")
const VectorSettings := preload("res://modules/sara-base-modules/vector/tools/sa_vector_settings.gd")
const VectorHandles := preload("res://modules/sara-base-modules/vector/tools/sa_vector_handles.gd")

## The steps a drag and a deletion record.
const MOVE_TITLE := "Move Objects"
const RESIZE_TITLE := "Resize Object"
const DELETE_TITLE := "Delete Objects"

## The shared settings, handed in by the machine from the descriptor.
var settings: VectorSettings = null
## The tool itself, the value of the objects list's row.
var objects_listing: ToolState:
    get:
        return self

## The layer a drag is under way on, null at rest.
var _layer: SaLayer = null
## The recipe's JSON when the press went down, the step's undo side.
var _before: Dictionary = {}
var _press_at: Vector2 = Vector2.ZERO
## The handle a resize pulls, or -1 for a move.
var _handle: int = -1
## Each picked object's box when the press went down, by id.
var _start: Dictionary[String, Rect2] = {}
## The pointer's offset from the press the boxes were last given, and the one
## they are owed.
var _given: Vector2 = Vector2.ZERO
var _owed: Vector2 = Vector2.ZERO
var _square: bool = false
## When the next live redraw may run, in microseconds of the engine's clock.
var _next_follow: int = 0


func reset() -> void:
    if _layer != null:
        _land()


func handle_input(event: InputEvent) -> void:
    var doc := document()
    if doc == null or settings == null:
        return
    var button := event as InputEventMouseButton
    if button != null and button.button_index == MOUSE_BUTTON_LEFT:
        _square = button.shift_pressed
        if button.pressed:
            _press(doc, get_document_mouse_position(), button.shift_pressed)
        elif _layer != null:
            _owed = get_document_mouse_position() - _press_at
            _land()
        return
    var key := event as InputEventKey
    if key != null and key.pressed and (key.keycode == KEY_DELETE or key.keycode == KEY_BACKSPACE):
        _delete(doc)
        return
    var motion := event as InputEventMouseMotion
    if motion != null and _layer != null:
        _square = motion.shift_pressed
        _owed = get_document_mouse_position() - _press_at


func keeps_key(keycode: Key) -> bool:
    return keycode == KEY_DELETE or keycode == KEY_BACKSPACE


## Gives the picked objects the boxes the pointer owes them, once a frame
## however many motions the frame brought, and no sooner than twice the last
## redraw's own time after it, so a large ellipse's resize redraws a few
## times a second and the canvas and the handles still move every frame.
func tick(_delta: float) -> void:
    if _layer == null or _owed == _given or Time.get_ticks_usec() < _next_follow:
        return
    var started := Time.get_ticks_usec()
    _follow()
    var now := Time.get_ticks_usec()
    _next_follow = now + (now - started) * 2


func _press(doc: SaDocument, at: Vector2, shift: bool) -> void:
    var layer := doc.active_layer
    var recipe := VectorSettings.recipe_of(layer)
    if recipe == null or layer.is_locked:
        settings.picked = PackedStringArray()
        return
    _handle = -1
    if settings.picked.size() == 1 and not shift:
        var picked := recipe.find(settings.picked[0])
        if picked != null:
            _handle = VectorHandles.under(picked.box, at, VectorHandles.REACH / _zoom())
    if _handle < 0:
        var under := recipe.hit(at, VectorHandles.PICK_REACH / _zoom())
        if under == null:
            if not shift:
                settings.picked = PackedStringArray()
            return
        var picks := settings.picked.duplicate()
        if shift and picks.has(under.id):
            picks.remove_at(picks.find(under.id))
            settings.picked = picks
            return
        if shift:
            picks.append(under.id)
        elif not picks.has(under.id):
            picks = PackedStringArray([under.id])
        settings.picked = picks
    _layer = layer
    _before = recipe.to_json()
    _press_at = at
    _given = Vector2.ZERO
    _owed = Vector2.ZERO
    _next_follow = 0
    _start.clear()
    for object_id in settings.picked:
        var object := recipe.find(object_id)
        if object != null:
            _start[object_id] = object.box


## Gives each picked object its box for the pointer's offset now.
func _follow() -> void:
    var recipe := VectorSettings.recipe_of(_layer)
    _given = _owed
    if recipe == null:
        return
    for object_id: String in _start:
        recipe.reshape(object_id, box_for(object_id))


## The box the object *object_id* is given for the drag so far. A move goes
## by whole document pixels, which keeps a panel's edges on the pixels they
## were drawn on and lets the kernel draw the same outline again.
func box_for(object_id: String) -> Rect2:
    var start: Rect2 = _start.get(object_id, Rect2())
    if _handle >= 0:
        return VectorHandles.pulled(start, _handle, _owed, _square)
    return Rect2(start.position + _owed.round(), start.size)


## Ends the drag: the boxes it owes, and one step from the press to here.
func _land() -> void:
    _follow()
    var layer := _layer
    _layer = null
    var recipe := VectorSettings.recipe_of(layer)
    if recipe == null:
        return
    var after := recipe.to_json()
    if after == _before:
        return
    var doc := layer.get_parent() as SaDocument
    if doc == null or doc.history == null:
        return
    var step := SaDrawnLayer.Step.new(layer, _before, after)
    var title := RESIZE_TITLE if _handle >= 0 else MOVE_TITLE
    doc.history.commit_pair(TranslationServer.translate(title), step.redo, step.undo, step.bytes())
    doc.modified = true


func _delete(doc: SaDocument) -> void:
    var layer := doc.active_layer
    if VectorSettings.recipe_of(layer) == null or layer.is_locked or settings.picked.is_empty():
        return
    var gone := settings.picked.duplicate()
    settings.picked = PackedStringArray()
    SaDrawnLayer.edit(
        layer,
        TranslationServer.translate(DELETE_TITLE),
        func(recipe: SaDrawnRecipe) -> void:
            for object_id in gone:
                recipe.call("remove", object_id)
    )


## The picked objects' box with its handles, through a drag the box the
## pointer has reached, which the redraw catches up with.
func preview_shape() -> Dictionary:
    var doc := document()
    if settings == null or doc == null:
        return {}
    if _layer != null and not _start.is_empty():
        var reached := Rect2()
        for object_id: String in _start:
            var box := box_for(object_id)
            reached = box if reached.size == Vector2.ZERO else reached.merge(box)
        return VectorHandles.preview(reached)
    return VectorHandles.preview(VectorHandles.picked_box(VectorSettings.recipe_of(doc.active_layer), settings.picked))


## The move shape while a drag is on.
func cursor_shape() -> int:
    if _layer != null:
        return Control.CURSOR_MOVE
    return -1


func _zoom() -> float:
    var view := surface.view if surface != null else null
    return maxf(view.get_zoom() if view != null else 1.0, 0.01)
