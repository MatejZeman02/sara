## The Shape tool: a drag draws a rectangle or an ellipse on a vector layer,
## the kind on its Tool Options row, Krita's way.
##
## Shift held squares the box, so a drag of the ellipse draws a circle, and Alt
## held draws it from the press outwards, its centre where the press went down,
## as Krita and Inkscape do. The new object takes the painter's pair, its
## stroke the foreground and its fill the background, and is picked, so its
## handles show at once and the Object tool finds it picked.
##
## A press on a layer that is not a vector layer makes one above it in the same
## undo step (`sa_vector_place.gd`). A click that drags less than a pixel draws
## nothing and picks the object under it instead, or drops the pick.
extends ToolState

const VectorObject := preload("res://modules/sara-base-modules/vector/sa_vector_object.gd")
const VectorSettings := preload("res://modules/sara-base-modules/vector/tools/sa_vector_settings.gd")
const VectorHandles := preload("res://modules/sara-base-modules/vector/tools/sa_vector_handles.gd")
const VectorPlace := preload("res://modules/sara-base-modules/vector/sa_vector_place.gd")

## The shared settings, handed in by the machine from the descriptor.
var settings: VectorSettings = null
## The tool itself, the value of the objects list's row, which reads the
## document and the pick through it.
var objects_listing: ToolState:
    get:
        return self

var _dragging: bool = false
var _anchor: Vector2 = Vector2.ZERO
var _corner: Vector2 = Vector2.ZERO
var _square: bool = false
var _from_centre: bool = false


func reset() -> void:
    _dragging = false


func handle_input(event: InputEvent) -> void:
    if document() == null or settings == null:
        return
    var button := event as InputEventMouseButton
    if button != null and button.button_index == MOUSE_BUTTON_LEFT:
        _hold(button.shift_pressed, button.alt_pressed)
        if button.pressed:
            _dragging = true
            _anchor = get_document_mouse_position()
            _corner = _anchor
        elif _dragging:
            _dragging = false
            _corner = get_document_mouse_position()
            _apply()
        return
    var key := event as InputEventKey
    if key != null and key.keycode == KEY_ESCAPE and key.pressed and _dragging:
        _dragging = false
        return
    var motion := event as InputEventMouseMotion
    if motion != null and _dragging:
        _hold(motion.shift_pressed, motion.alt_pressed)
        _corner = get_document_mouse_position()


func keeps_key(keycode: Key) -> bool:
    return keycode == KEY_ESCAPE and _dragging


func _hold(shift: bool, alt: bool) -> void:
    _square = shift
    _from_centre = alt


## The box the drag has drawn so far, in document pixels.
func drag_box() -> Rect2:
    var reach := _corner - _anchor
    if _square:
        var side := maxf(absf(reach.x), absf(reach.y))
        reach = Vector2(side if reach.x >= 0.0 else -side, side if reach.y >= 0.0 else -side)
    if _from_centre:
        return Rect2(_anchor - reach.abs(), reach.abs() * 2.0)
    return Rect2(_anchor, reach).abs()


## The dragged box while a drag is on, and the picked objects' box with its
## handles at rest.
func preview_shape() -> Dictionary:
    if _dragging:
        return {"rect": drag_box(), "ellipse": settings.kind == VectorObject.Kind.ELLIPSE}
    var doc := document()
    if settings == null or doc == null:
        return {}
    return VectorHandles.preview(VectorHandles.picked_box(VectorSettings.recipe_of(doc.active_layer), settings.picked))


func cursor_shape() -> int:
    return Control.CURSOR_CROSS


func _apply() -> void:
    var doc := document()
    var box := drag_box()
    if box.size.x < 1.0 and box.size.y < 1.0:
        var recipe := VectorSettings.recipe_of(doc.active_layer)
        var under := recipe.hit(_anchor, VectorHandles.PICK_REACH / _zoom()) if recipe != null else null
        settings.picked = PackedStringArray([under.id] if under != null else [])
        return
    var object := VectorObject.new(settings.kind as VectorObject.Kind, box)
    object.radius = settings.corner_radius
    object.filled = settings.fill_on
    object.fill = SaInHand.Pair.background()
    object.stroke = SaInHand.Pair.foreground()
    object.stroke_width = settings.stroke_width if settings.stroke_on else 0.0
    var layer := VectorPlace.place(
        doc, settings.context.get_ref() as SaContext if settings.context != null else null, object, settings.new_layer_each
    )
    settings.picked = PackedStringArray([object.id] if layer != null else [])


func _zoom() -> float:
    var view := surface.view if surface != null else null
    return maxf(view.get_zoom() if view != null else 1.0, 0.01)
