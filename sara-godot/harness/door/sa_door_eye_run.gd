## Which steps of a door batch are answered in the frame they ran, so that a
## run of shows and hides costs one composite rather than one each.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A request of about forty `{"layer": {"of": g,
## "visible": b}}` steps took 2 to 7 s, because the door gave every step its
## two settle frames and a drawn frame, and each of those frames folded and
## composited the picture the step before had left. A step that only shows or
## hides a layer prints its verdict before it returns and needs no frame to
## land, so one with another such step after it in the same batch is answered
## at once, and the next runs in the same frame. The last of the run settles as
## any step does, and its answer comes once the picture they made together is
## drawn. A request that names its own `settle` keeps it.
##
## **The last of a run waits for the picture, over frames.** The fold a show
## owes is paid over the frames after it, and the easel composites what that
## dirties as many chunks a frame as its budget pays for, both so that a
## painter's click never stops the window. A run of two or more is a client
## asking for a picture, so its last step answers once the canvas stands where
## the stack draws it, with the fold paid and nothing held, and not before. Bringing
## the canvas up to that picture in the frame it ran, the way an export's read
## does, held frames of 1.1 to 1.3 s for a switch of many groups, a
## `Sara stall:` line each. A lone show or hide, a click's
## twin, keeps the frames and is answered after them as any step is.

## **A run is one undo step**, "Layer Visibility" as a single eye's is, so one
## Ctrl+Z after a switch puts back every group it showed or hid,
## rather than one group of forty.
##
## The door stands at its line budget, which is why the rule is a file of its
## own rather than a few lines there.
class_name SaDoorEyeRun
extends RefCounted

## How many shows and hides of the run under way have run in this frame and
## gone on to the next, nought between runs.
var _ran := 0
## Whether a run is being gathered into one history step now.
var _gathering := false
## Whether the run that ended last waits for its picture, [method owes].
var _owed := false
## The dialogs named for the answers of a run, from one walk of the tree.
var _dialogs := SaDoorDialogs.EachFrame.new()


## Whether *request* begins a run of shows and hides, which [method as_one]
## then runs whole.
func begins(request: Dictionary, rest: Array) -> bool:
    return not _gathering and _ran == 0 and runs_on(request, rest)


## Calls *first*, the door running the first step of a run, which runs the rest
## of the run in the same call, and gathers every step they commit into one,
## and answers what *first* returned.
func as_one(first: Callable) -> Variant:
    var canvas := SaCanvasView.front_canvas()
    if canvas == null or canvas.document == null or canvas.document.history == null:
        return first.call()
    var returned: Array = [null]
    _gathering = true
    canvas.document.history.as_one("Layer Visibility", func() -> void: returned[0] = first.call())
    _gathering = false
    return returned[0]


## The frames *request* settles for, given the steps of its batch still to run
## in *rest*: none when it and the next are both a show or a hide, and
## *default* otherwise or when the request names its own.
func settle(request: Dictionary, rest: Array, default: int) -> int:
    if request.has("settle"):
        _ran = 0
        return maxi(int(request["settle"]), 0)
    if runs_on(request, rest):
        _ran += 1
        return 0
    return default


## Notes, once *request* ran, whether it ended a run of shows and hides, whose
## answer then waits for [method owes]. Nothing otherwise.
func after(request: Dictionary, rest: Array) -> void:
    if runs_on(request, rest):
        return
    _owed = _ran > 0 and is_eye(request)
    _ran = 0


## Whether the run that ended last still waits for the canvas in front to
## stand where its stack draws it where it shows: a fold the debt holds back,
## a region the easel's budget or an effect refresh held in the view, or a
## composite asked for and not made. A region held outside the view waits for
## a pan, as it does for the painter, and a reader flushes it. False once it stands, and from then on until the next run ends.
func owes() -> bool:
    if not _owed:
        return false
    var canvas := SaCanvasView.front_canvas()
    var easel := canvas.easel if canvas != null else null
    if easel == null or easel.document == null:
        _owed = false
        return false
    var fold := easel.document.fold
    _owed = (fold != null and fold.debt.is_owed()) or easel.backlog.reaches(easel.composed_area()) or easel.needs_composite
    return _owed


## Writes the dialogs standing into *answer*, from the walk this frame made
## when it is of a run of eyes or a ping, neither of which opens a dialog.
func name_dialogs(answer: Dictionary, root: Window) -> void:
    _dialogs.name_in(answer, root, _gathering or answer.has("ping"))


## Whether *request* and the first of *rest* are both a show or a hide with
## nothing else in them, so that the second runs in the frame the first did.
static func runs_on(request: Dictionary, rest: Array) -> bool:
    if rest.is_empty() or not (rest[0] is Dictionary):
        return false
    return is_eye(request) and is_eye(rest[0] as Dictionary) and not (rest[0] as Dictionary).has("settle")


## Whether *request* is a `layer` step that names a layer with `of` and sets
## its `visible` and does nothing else, which is the step a switch of groups is
## made of. An `id` beside it is the client's own, and a dump, which reads the
## state the frames after would settle, keeps the request out.
static func is_eye(request: Dictionary) -> bool:
    var keys := request.size() - (1 if request.has("id") else 0)
    if keys != 1 or not (request.get("layer") is Dictionary):
        return false
    var spec: Dictionary = request["layer"]
    return spec.size() == 2 and spec.has("of") and spec.has("visible")
