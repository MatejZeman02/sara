## The narrow door a module holds a stroke's pointer to a guide through, and
## draws its guides over the canvas by: a drawing assistant's ruler first.
##
## **Where the hold enters.** At the pointer, never in an engine. The machine
## asks [method held_at] at a painting tool's press, with the press's own point,
## and the tool keeps the answer for the stroke, so every position
## `ToolState.get_document_mouse_position` hands that tool until the release is
## moved onto the guide. Every brush engine reads its positions there, the stamp,
## the noise brush, the filter brush and the eraser alike, so none of them knows
## a guide exists. Pressure, tilt and timing ride on the events and are not
## touched.
##
## **What a holder is.** A module hands in a [Holder] under its own id. The
## skeleton never names the module, and a holder answers for any document the
## press lands in, reading what it keeps in that document itself. A module that
## goes takes its holder with it in its `unregister`.
##
## **Why one door for the hold and the drawing.** What a guide holds a stroke
## to and what the painter sees of it are the same lines, and a holder that drew
## through one door and held through another could drift apart. The overlay asks
## [method draw] and [method signature] here and knows no guide's geometry.
class_name SaStrokeHold
extends RefCounted

## The key of a document's `module_data` its guides are kept under, a list of
## JSON entries, which a `.sad` writes as a section of its own,
## `SaSadAssistants`. One key for every holder's guides, so the file needs no
## word of any module's.
const GUIDES_KEY := "assistants"


## What a module hands in. Every method answers nothing, so a holder overrides
## only what it has.
class Holder:
    extends RefCounted

    ## The position a stroke pressed at *at*, in *document*'s pixels, is held
    ## to, as a `func(Vector2) -> Vector2`, or an empty Callable for a press no
    ## guide of this holder takes. Asked once a press.
    func hold(_document: SaDocument, _at: Vector2) -> Callable:
        return Callable()

    ## How far *at* lies from the guide [method hold] would choose, in document
    ## pixels, or INF when none would. Two holders are weighed by it.
    func reach(_document: SaDocument, _at: Vector2) -> float:
        return INF

    ## Draws this holder's guides of *document* on *overlay*, which draws in
    ## document pixels, *per_pixel* document pixels to one on screen.
    func draw(_document: SaDocument, _overlay: Control, _per_pixel: float) -> void:
        pass

    ## What the drawing is made of, compared once a frame, so the overlay
    ## redraws when it changes and only then.
    func signature(_document: SaDocument) -> Array:
        return []


## Module id to its holder, in the order they came.
static var _holders: Dictionary[StringName, Holder] = {}


## Hands in *holder* under *module_id*, in place of one it gave before.
static func put(module_id: StringName, holder: Holder) -> void:
    if holder == null:
        _holders.erase(module_id)
        return
    _holders[module_id] = holder


## Takes *module_id*'s holder away, for the module's `unregister`.
static func take_away(module_id: StringName) -> void:
    _holders.erase(module_id)


## The hold a stroke pressed at *at* in *document* keeps to, the holder with the
## nearest guide answering, or an empty Callable for a free stroke.
static func held_at(document: SaDocument, at: Vector2) -> Callable:
    if document == null:
        return Callable()
    var nearest: Holder = null
    var nearest_reach := INF
    for holder: Holder in _holders.values():
        var reached := holder.reach(document, at)
        if reached < nearest_reach:
            nearest_reach = reached
            nearest = holder
    return nearest.hold(document, at) if nearest != null else Callable()


## Draws every holder's guides of *document* on *overlay*.
static func draw(document: SaDocument, overlay: Control, per_pixel: float) -> void:
    if document == null:
        return
    for holder: Holder in _holders.values():
        holder.draw(document, overlay, per_pixel)


## What every holder's drawing of *document* is made of, one array.
static func signature(document: SaDocument) -> Array:
    var seen: Array = []
    if document == null:
        return seen
    for holder: Holder in _holders.values():
        seen.append(holder.signature(document))
    return seen
