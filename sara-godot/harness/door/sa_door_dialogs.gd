## The dialogs of Sara's own standing over the canvas, which every door answer
## names under `dialogs`.
##
## The "Recovered work" question can stand over the canvas from a client's
## first request, and without this nothing in an answer said so until a click on
## Later did nothing. The state dump has carried `open_dialogs` all along, but a `state`
## step answers with the dump's path and a model does not spend its context on
## the file. So the answer says it, and only while a dialog stands: an answer
## over a clear canvas has no key and costs nothing more.
##
## **The walk is over the tree, not over `get_embedded_subwindows()`**, which is
## the list `SaDialogWindow.capture_open` reads. With Embed subwindows off a
## dialog is a window of its own and in no viewport's list, so that walk misses
## it. A dialog of Sara's own is an `SaDialogWindow` or one of the engine's
## `AcceptDialog`s, the file picker's fallback among them. A docker, a
## dropdown's list and a menu are windows as well and are left out, because
## none of them asks anything.
class_name SaDoorDialogs
extends RefCounted

## The step that answers a message window the way Escape would. It reaches the
## window whether it is embedded or one of its own, where a click on the window
## can do nothing.
const ESCAPE_STEP := {"message": {"close": "escape"}}


## Writes `dialogs` into *answer* while a dialog stands under *root*, and leaves
## the answer alone otherwise.
static func name_in(answer: Dictionary, root: Window) -> void:
    var named := on_screen(root)
    if not named.is_empty():
        answer["dialogs"] = named


## The door's own naming, which walks the tree once a frame for a run of shows
## and hides, as `SaDoorEyeRun` says, however many answers the run makes. None
## of them opens or closes a dialog, so the walk the first made names what
## stands for the rest. Any other answer walks afresh, since a step answered in
## the frame of the last walk, a suite's above all, can have put one up.
## Forty answers of a season's switch walked the tree forty times, 88 ms of the
## frame they ran in.
class EachFrame:
    extends RefCounted

    var _frame := -1
    var _named: Array = []

    ## Writes `dialogs` into *answer* as [method SaDoorDialogs.name_in] does,
    ## from the walk this frame already made when *in_run* says the answer is
    ## one of a run of eyes.
    func name_in(answer: Dictionary, root: Window, in_run: bool) -> void:
        var now := Engine.get_process_frames()
        if now != _frame or not in_run:
            _frame = now
            _named = SaDoorDialogs.on_screen(root)
        if not _named.is_empty():
            answer["dialogs"] = _named.duplicate(true)


## The dialogs on screen under *root* in tree order, one entry each, and an empty
## list when there is none.
##
## The tree is walked once, and the message `close` reaches is asked for only
## when a dialog stands, since asking walks the tree a second time. Every answer
## pays for the walks, so two would cost a NumPy slider's write a share it can
## feel, where one is small beside it.
static func on_screen(root: Window) -> Array:
    var named: Array = []
    if root == null:
        return named
    var shown: Array[Window] = []
    # No pattern, which matches every name as "*" does without turning each
    # of the tree's few thousand names into a String to compare.
    for node: Node in root.find_children("", "Window", true, false):
        var window := node as Window
        if window.visible and (window is SaDialogWindow or window is AcceptDialog):
            shown.append(window)
    if shown.is_empty():
        return named
    # The message the `message` step's `close` reaches, which is not always the
    # one on top: the step takes the question it asked itself first, then the
    # problem dialog, then whichever message it finds.
    var closes := SaMessage.live_dialog(root.get_tree())
    for window: Window in shown:
        named.append(entry(window, window == closes))
    return named


## One dialog's entry: its title, and for a message window its button labels in
## the order the question gave them, which is the order of their nodes
## `Button0` and on. The message *closes* names also carries the step that
## answers it and the label of the button that answer is.
static func entry(window: Window, closes: bool) -> Dictionary:
    var named := {"title": window.title}
    var message := window as SaMessage
    if message == null:
        return named
    var labels: Array = []
    for button: Button in message.buttons:
        labels.append(button.text)
    named["buttons"] = labels
    # The cancel index rather than a label read off the row, because Escape
    # hides the window and every hide that is not a button answers it.
    var cancel := message.cancel_index
    if closes and cancel >= 0 and cancel < labels.size():
        named["step"] = ESCAPE_STEP.duplicate(true)
        named["presses"] = labels[cancel]
    return named
