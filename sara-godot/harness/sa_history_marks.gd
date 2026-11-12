## The `mark` and `rewind` steps: a batch of steps undone by the name it
## was marked with.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## `undo` takes a count, so a script redoing a whole object of hundreds of
## strokes would have to count its own steps, or delete a layer and send
## everything again. A mark names the history's place, and a
## rewind undoes back to it and says how many steps that took.
##
## **A mark is the history's serial, not its index.** `SaHistory.position`
## answers a serial per step, which eviction does not shift and an undo
## followed by a new step does not repeat, so a mark the history has dropped,
## or one undone past and replaced, is found missing rather than rewound to the
## wrong place. Serials are shared by every history, so a mark made on another
## document is never found in this one either.
##
## **The painter's work is not undone unasked.** The mark keeps the count of
## the painter's changes the door had heard, `SaCaptureRun.painter_changes`,
## and a rewind refuses while that count has moved since, unless the step says
## `"force": true`. The count is the door's (`SaDoorGlance.Changes`), so a run
## with no door never moves it and a scenario's rewind is never refused for it.
## It counts every change the painter announced, so a hand that only toggled a
## layer's eye after the mark is refused as well, which errs on the side of the
## painter's work.
##
## Reached by path from the step table, not by class name, so no editor rescan
## stands between a fresh checkout and a step.
extends RefCounted

const CaptureRun := preload("res://harness/sa_capture_run.gd")

## The run, read for the document and for the painter's count.
var _run: CaptureRun = null

## Each mark by name, as `[serial, painter changes]` when it was made.
var _marks: Dictionary = {}


func _init(run: CaptureRun) -> void:
    _run = run


## Marks the history's place: under a name a `rewind` takes the document back
## to, `{"mark": "window"}`.
##
## **Arguments.**
## - `mark` string, the name. Marking a name again moves it to where the
##   history stands now.
func mark(name: String) -> void:
    var document := _run.main_document()
    if document == null or document.history == null:
        print("SaCapture: refused mark %s, there is no document whose history to mark" % name)
        return
    _marks[name] = [document.history.position(), _run.painter_changes]
    print("SaCapture: mark %s at step %d of the history" % [name, document.undo_redo.get_current_action() + 1])


## Rewinds to a mark: undoes every step since `mark` took that name and says
## how many, `{"rewind": "window"}`.
##
## **Arguments.**
## - `rewind` string, a name a `mark` step took.
## - `force` boolean, false by default: rewinds even when the painter changed
##   the document by hand since the mark, undoing their steps with the door's.
##
## Refused, with nothing undone, for a name never marked, a mark the history
## no longer holds, dropped by its budget or undone past and replaced, and a
## mark the painter has changed the document since, unless forced.
func rewind(name: String, force: bool) -> void:
    if not _marks.has(name):
        print("SaCapture: refused rewind %s, no mark has that name, the marks are %s" % [name, _marks.keys()])
        return
    var document := _run.main_document()
    if document == null or document.history == null:
        print("SaCapture: refused rewind %s, there is no document whose history to rewind" % name)
        return
    var kept: Array = _marks[name]
    var back := steps_back(document.history, document.undo_redo, int(kept[0]))
    if back < 0:
        print("SaCapture: refused rewind %s, the history no longer holds the mark, dropped by its budget or undone past" % name)
        return
    var by_hand := _run.painter_changes - int(kept[1])
    if by_hand != 0 and not force:
        var why := "the painter changed the document %d time(s) since the mark, and a rewind would undo their work too"
        print('SaCapture: refused rewind %s, %s, send "force": true to rewind anyway' % [name, why % by_hand])
        return
    var undone := 0
    while undone < back and document.undo_redo.undo():
        undone += 1
    # Back at the mark, so what the painter did before this is either undone
    # or older than where the history now stands.
    _marks[name] = [kept[0], _run.painter_changes]
    print("SaCapture: rewind %s, %d step(s) undone" % [name, undone])


## How many undos take *history* back to the step whose serial is *serial*, or
## -1 when no undo reaches it: dropped, never this document's, or ahead of
## where the history stands.
static func steps_back(history: SaHistory, undo_redo: UndoRedo, serial: int) -> int:
    var current := undo_redo.get_current_action()
    if history.position() == serial:
        return 0
    var kept := mini(current, history.step_serials.size() - 1)
    for i in range(kept, -1, -1):
        if history.step_serials[i] == serial:
            return current - i
    return current + 1 if history.base_serial == serial else -1
