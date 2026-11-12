## What the filter dialog works on: the document and the layer its context is
## built for, and the listening that hears either change while it is open.
##
## The dialog is not exclusive, so the Layers docker and the document tabs take
## clicks while it stands, and the canvas preview is drawn on whatever layer is
## active, so a context that stayed on the layer it was built for would show the
## filter on one layer and write another. This holds the pair in one place and
## says when the painter moves off it, and the window decides what that means:
## it follows a switch of layer and closes, as Cancel does, on a switch of
## document, because a dialog's settings are the painter's for this picture and
## a document closed under it has nothing left to write into.
class_name SaFilterDialogTarget
extends RefCounted

## The active layer is now another than [member layer], one the painter picked
## in the same document. Not sent for a layer that went to none, which is
## [signal left] too, because there is nothing left to run the filter on.
signal switched

## The dialog's document is not the one it works on now: another tab is in
## front, the document is closing, or it holds no active layer.
signal left

## The document the dialog opened on. Read by the window, written here alone.
var document: SaDocument = null

## The layer the context is built for, the document's active layer when this
## was made.
var layer: SaLayer = null

## Answers the canvas the dialog works on now, the window's own lookup, so a
## window a suite points at one canvas hears no other document come forward.
var _canvas_now: Callable


func _init(on: SaDocument, canvas_now: Callable) -> void:
    document = on
    layer = on.active_layer
    _canvas_now = canvas_now
    document.active_layer_changed.connect(_on_active_layer_changed)
    EventBus.active_document_changed.connect(_on_front_changed)


## Refuses an open of *filter_key* on *on* in the corner, and answers whether
## it did. A document with no active layer is the one refusal: what a layer
## itself refuses is said in the dialog by the dimmed ways, so the painter can
## still look and attach, on an open and on a switch alike.
static func refuses(on: SaDocument, filter_key: StringName) -> bool:
    if on != null and on.active_layer != null:
        return false
    SaProblems.refuse("Filter", TranslationServer.translate("There is no active layer to run '%s' on.") % String(filter_key))
    return true


## A context over [member layer] for the filter *module_id* registered, with
## *step_name* as its history step.
##
## `previewing` is true for every context the dialog makes, because every run it
## makes is a preview: it calls `run` on open and after every widget change,
## and Apply is what writes.
func context(module_id: StringName, step_name: String) -> SaFilterContext:
    return SaFilterContext.new(document, layer, module_id, step_name, true)


## Stops hearing either change. Asked ahead of every write, because Layer's
## Apply makes a layer active and a heard switch would open the dialog again
## over the close, and on every close.
func release() -> void:
    if is_instance_valid(document) and document.active_layer_changed.is_connected(_on_active_layer_changed):
        document.active_layer_changed.disconnect(_on_active_layer_changed)
    if EventBus.active_document_changed.is_connected(_on_front_changed):
        EventBus.active_document_changed.disconnect(_on_front_changed)


func _on_active_layer_changed(now: SaLayer) -> void:
    if now == layer:
        return
    if now == null:
        left.emit()
    else:
        switched.emit()


func _on_front_changed(_surface: SaSurface) -> void:
    if document_of(_canvas_now.call()) != document:
        left.emit()


## The canvas a filter dialog works on: *pinned* where a suite set one, and
## otherwise the front document's while *window* is in the tree.
static func canvas_for(pinned: SaCanvas, window: Node) -> SaCanvas:
    if pinned != null:
        return pinned
    return SaCanvasView.front_canvas() if window.is_inside_tree() else null


## The document *canvas* shows, or null for no canvas.
static func document_of(canvas: SaCanvas) -> SaDocument:
    return canvas.document if canvas != null and is_instance_valid(canvas) else null


## The middle of the document *canvas* shows, on screen, in the space
## *window*'s `position` is measured in, or an infinite point when there is no
## canvas on screen to ask.
##
## The canvas is a control the view scales and pans, so its global transform
## carries the document's middle to the main window's pixels. An OS window's
## position is in screen pixels, so the main window's own place and scale are
## put back on for that one.
static func centre_on_screen(window: Window, canvas: SaCanvas) -> Vector2:
    if canvas == null or not canvas.is_inside_tree():
        return Vector2.INF
    var centre := canvas.get_global_transform() * (Vector2(canvas.canvas_size) / 2.0)
    if window.is_embedded():
        return centre
    var main := window.get_tree().root
    return Vector2(main.position) + main.get_final_transform() * centre
