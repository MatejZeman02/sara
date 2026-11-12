## Whether a document still matches the copy on disk, measured against its
## history rather than kept by hand.
##
## Raised by every mutation and cleared by a save or a load. Clearing it
## records where the history stands as the clean place, and an undo or redo
## sets it from there: clean exactly when the history is back on that step and
## nothing outside the history changed meanwhile.
##
## The document keeps its `modified` property and its `modified_changed`
## signal, which the window title, the prompts and the tabs read, and hands
## both sides to this class: *position* answers where the history stands, and
## *announce* is called with the new bit each time it turns. So the mark knows
## nothing of the document but those two calls.
class_name SaSavedMark
extends RefCounted

## Whether anything has changed since the last save or load. Written by
## [method mark] and [method step] alone.
var modified: bool = false
## How many times [member modified] was raised, so a save in the background
## knows whether anything changed after its snapshot.
var raises: int = 0

var _position: Callable
var _announce: Callable
## Where the history stood when the mark was last cleared.
var _clean_at: int = -1
## Whether the document changed at the clean place without a history step, a
## colour space change or a recovery copy, so no undo can make it clean.
var _changed_off_history: bool = false
## A raise at the clean place that has not yet been told apart from a step.
var _raise_pending: bool = false
## True while an undo or redo runs, whose own raises say nothing.
var _stepping: bool = false


func _init(position: Callable, announce: Callable) -> void:
    _position = position
    _announce = announce


## Raises the mark when *value* is true and clears it at the history's present
## place when false, and announces when the bit turns.
func mark(value: bool) -> void:
    if value:
        raises += 1
        _note_raise()
    else:
        _clean_at = _position.call()
        _changed_off_history = false
        _raise_pending = false
    if modified == value:
        return
    modified = value
    _announce.call(value)


## Moves the history one step with *move* and sets the mark from where it lands.
##
## The actions themselves raise the mark as they run, a layer put back in its
## place announces like any edit, so their raises are held off here and the
## mark is the comparison alone.
func step(move: Callable) -> void:
    _settle_raise()
    _stepping = true
    move.call()
    var moved: bool = _changed_off_history or _position.call() != _clean_at
    mark(moved)
    _stepping = false


## A raise while the history stands where the document was saved is either the
## first half of a step, whose commit follows in the same call, or a change the
## history never hears of. Which one is known only once the edit has finished,
## so it is settled at the end of the frame or at the next undo or redo,
## whichever comes first. Some edits raise before they commit and some after,
## so the order inside one edit cannot tell them apart.
func _note_raise() -> void:
    if _stepping or _raise_pending or _position.call() != _clean_at:
        return
    _raise_pending = true
    _settle_raise.call_deferred()


func _settle_raise() -> void:
    if not _raise_pending:
        return
    _raise_pending = false
    if _position.call() == _clean_at:
        _changed_off_history = true
