## The idle clock: says once that the painter has stopped, after the Idle After
## preference's seconds with no stroke, fill or layer change.
##
## **One clock for every idle job.** The stats docker's numbers read it first,
## the thumbnails and the minimap when the painter asks them to wait for a stop,
## and the autosave reads its seconds, so that none of them keeps a wait of its
## own and the painter sets one number. `SaSettings.idle_after_seconds`
## is that number, five by default. [signal stopped] is the one thing the clock
## says, and it says it once until the next edit.
##
## **What counts as an edit** is a change the document announces with
## `document_changed`, a step the history takes, an undo or a redo included, and
## a stroke open on the document, which keeps the clock at nothing for as long
## as it is down. A pan, a zoom, a rotation and a change of view mode are not
## edits. A zoom does announce `chunks_invalidated`, because it uncovers chunks
## the composite has not drawn, so that signal is not heard: it says what the
## view needs and not what the painter did.
##
## **It follows the main document and nobody wires it.** The clock is an
## autoload, and each frame it reads which document the main scene shows and
## watches that one, by name, because the main scene is `ui`'s and `core` never
## names it. A document that is replaced, File > New or an Open, starts the wait
## again from nothing.
##
## **Its time comes from outside.** [method tick] takes the seconds since the
## last call, as `SaAutosave.tick` does, so a suite drives a minute in a call and
## never waits. `_process` passes the frame's delta.
class_name SaIdleClock
extends Node

## Emitted once when the painter has stopped, and not again until the next edit.
signal stopped

## The seconds to wait. Mirrored from Preferences each frame while
## [member follow_settings] is on, which a suite turns off to dial its own.
var idle_seconds: float = 5.0
var follow_settings: bool = true

## Whether the clock watches the main scene's document by itself. A suite that
## attaches a document of its own turns it off.
var follow_main: bool = true

var document: SaDocument = null

## Seconds since the last edit, and whether [signal stopped] has been said for
## it.
var _quiet: float = 0.0
var said: bool = false
var _seen_position: int = -1


func _init() -> void:
    SaBootMarks.mark(&"idle_init")
    name = "SaIdleClock"


func _process(delta: float) -> void:
    if follow_settings:
        idle_seconds = SaSettings.idle_after_seconds
    if follow_main:
        _follow_main_document()
    tick(delta)


## Watches *doc*, and starts the wait again. Null watches nothing.
func attach(doc: SaDocument) -> void:
    if is_instance_valid(document) and document.document_changed.is_connected(note_edit):
        document.document_changed.disconnect(note_edit)
    document = doc
    if doc != null and not doc.document_changed.is_connected(note_edit):
        doc.document_changed.connect(note_edit)
    _seen_position = _history_position()
    note_edit()


## One frame of the clock, *delta* seconds on. Returns whether the painter was
## just told they have stopped.
func tick(delta: float) -> bool:
    if document == null:
        return false
    var position := _history_position()
    if position != _seen_position:
        _seen_position = position
        note_edit()
    if is_stroke_open():
        note_edit()
        return false
    if said:
        return false
    _quiet += delta
    if _quiet < idle_seconds:
        return false
    said = true
    var traced := SaFrameTrace.now()
    stopped.emit()
    SaFrameTrace.spent("idle stopped", traced)
    return true


## Something was edited just now: the wait starts again, and the clock may say
## so once more.
func note_edit() -> void:
    _quiet = 0.0
    said = false


## Whether a stroke is being painted: the stroke buffer holds chunks until the
## commit, and an erase paints straight into the layer through the transaction.
## The reading `SaAutosave` waits on.
func is_stroke_open() -> bool:
    if document == null:
        return false
    if document.stroke_layer != null and not document.stroke_layer.chunks.is_empty():
        return true
    return document.stroke_transaction != null and document.stroke_transaction.direct_paint


func _history_position() -> int:
    return document.history.position() if document != null and document.history != null else -1


## Attaches to the document the main scene's canvas shows, when it is not the
## one already watched.
func _follow_main_document() -> void:
    var tree := get_tree()
    var main_node: Node = tree.current_scene if tree != null else null
    if main_node == null or not ("main_canvas" in main_node):
        return
    # Core never names the canvas classes, so each step is an Object read by
    # name, and a typed Object is what lets `get()` be called without a warning.
    var surface: Object = main_node.get(&"main_canvas")
    if surface == null or not ("canvas" in surface):
        return
    var canvas: Object = surface.get(&"canvas")
    var doc: SaDocument = canvas.get(&"document") if canvas != null else null
    if doc != null and doc != document:
        attach(doc)
