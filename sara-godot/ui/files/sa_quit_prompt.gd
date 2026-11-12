## The question Quit asks when an open document has unsaved work. With more
## than one, one window naming every one of them, answered by Save All, Discard
## All or Cancel. With one, the question Close asks, word for word and button
## for button, so a painter with one painting open is asked what Sara has
## always asked.
##
## **Why one window.** Sara asked about the document in front and quit on the
## answer, so a second document's work would go without a word. A question per
## document would be a queue of windows to answer before the program ends, and
## Save All is the answer a painter leaving the machine means.
##
## **One question at a time.** A second Ctrl+Q, or the window's close button
## pressed while the question is up, asks `standing()` first and brings the
## window forward rather than putting up a second one. A second window would
## save one document twice, and its Discard All could throw away what the
## first window's Save All had not yet written.
##
## **Save All saves one at a time**, each through the flow's own Save, because
## an untitled document still has to ask where to put it and the answer to that
## window comes back a frame later. Each save calls back here for the next one,
## so the order is the order the documents are open in, and a Cancel in any of
## those windows stops the quit with every document still open and nothing
## lost. A save that fails says so in the problems line and stops the quit the
## same way.
##
## The flow holds this while the window is up, because a `RefCounted` nothing
## refers to is freed under its own dialog.
class_name SaQuitPrompt
extends RefCounted

## The three answers, in button order.
const SAVE_ALL := 0
const DISCARD_ALL := 1
const CANCEL := 2

## Who the window is built under, the files flow.
var _host: Node

## `func(then: Callable, doc: SaDocument)`, the flow's own Save. Taken as a
## callable rather than reaching back for the flow, so the question names one
## class of the folder and the two files do not name each other.
var _save_one: Callable

## What runs once every document is saved or discarded, which is the quit.
var _proceed: Callable

## The documents Save All has still to write, in the order they are open in.
var _left: Array[SaDocument] = []

## The words of the buttons for the trail, Save or Save All by how many
## documents were asked about.
var _words: PackedStringArray = []

## The window while it is up. Weak, because the window frees itself once
## answered and this must not keep a freed node alive or reach it.
var _window: WeakRef = null


func _init(host: Node, save_one: Callable, proceed: Callable) -> void:
    _host = host
    _save_one = save_one
    _proceed = proceed


## Puts the question up about *modified*, every open document with unsaved
## work. Enter is Save and Escape is Cancel, so it can be answered without a
## mouse.
func ask(modified: Array[SaDocument]) -> void:
    _left = modified.duplicate()
    var text := question(modified)
    var labels := PackedStringArray([tr("Save All"), tr("Discard All"), tr("Cancel")])
    _words = PackedStringArray(["Save All", "Discard All", "Cancel"])
    if _left.size() == 1:
        var what := tr("quitting")
        text = SaDocumentFiles.save_question(_left[0], what)
        labels = PackedStringArray([tr("Save"), tr("Discard"), tr("Cancel")])
        _words = PackedStringArray(["Save", "Discard", "Cancel"])
        SaTrail.stage("asked whether to save the changes to %s before %s" % [SaDocumentFiles.display_name(_left[0]), what])
    else:
        SaTrail.stage("asked whether to save the changes to %d documents before quitting" % _left.size())
    var dialog := SaMessage.confirm(_host, tr("Unsaved changes"), text, labels, _answered, CANCEL, SAVE_ALL)
    _window = weakref(dialog)


## Whether the window is still on screen and unanswered. Once it is answered
## it hides, so a quit asked after a Cancel asks again.
func standing() -> bool:
    if _window == null:
        return false
    var dialog := _window.get_ref() as SaMessage
    return dialog != null and dialog.visible and not dialog.is_queued_for_deletion()


## Brings the standing window to the front and gives it the keys, which is
## what a second quit does instead of asking again.
func bring_forward() -> void:
    var dialog := _window.get_ref() as SaMessage if _window != null else null
    if dialog == null:
        return
    SaTrail.stage("brought the standing quit question forward")
    dialog.grab_focus()


## What the window says: the one-document sentence in the plural, and the
## documents' names under it, one to a line, so the painter reads which
## paintings are at stake before answering for all of them.
static func question(modified: Array[SaDocument]) -> String:
    var names := PackedStringArray()
    for doc in modified:
        names.append(SaDocumentFiles.display_name(doc))
    return String(TranslationServer.translate("Save the changes to these documents before quitting?")) + "\n\n" + "\n".join(names)


func _answered(index: int) -> void:
    SaTrail.stage("answered %s" % _words[clampi(index, SAVE_ALL, CANCEL)])
    if index == SAVE_ALL:
        _save_the_next()
    elif index == DISCARD_ALL:
        SaSadFile.after_saves(_proceed, String(TranslationServer.translate("quitting")))


## Saves the first document still waiting and comes back here when it is
## written. With none left the quit waits for whatever is still being written
## and then runs.
func _save_the_next() -> void:
    if _left.is_empty():
        SaSadFile.after_saves(_proceed, String(TranslationServer.translate("quitting")))
        return
    var doc: SaDocument = _left.pop_front()
    _save_one.call(_save_the_next, doc)
