## What the window is called: the front document's name, its unsaved mark, and
## the gamut a colour picked in it means.
##
## **The connections follow the front document.** File > New and File > Open
## rebuild a document in place, so one connection to it would do for one
## document, and it fails for two: a second document is a second object, and a
## title still bound to the first would name the painting the painter has moved
## away from. The owner says when the front document changes, this moves its
## two connections to the new one and writes the title again, and a rebuild in
## place needs nothing, because the object rebuilt is the one being watched.
class_name SaWindowTitle
extends Node

## What main names the node, and what a dump or a suite asks the main scene
## for.
const NODE_NAME := "WindowTitle"

## The open documents, whose front one the title names.
var _documents: SaDocuments

## The document the two connections are on, so they can be taken off it again.
## Null before the first document is open, which is the first frames of a boot.
var _watched: SaDocument = null


func _init(documents: SaDocuments) -> void:
    name = NODE_NAME
    _documents = documents


func _ready() -> void:
    if not EventBus.active_document_changed.is_connected(_on_front_changed):
        EventBus.active_document_changed.connect(_on_front_changed)
    # The gamut the title names is the document's, and the word for a wider
    # display follows the Wider display row, which announces on the bus.
    if not EventBus.document_color_space_changed.is_connected(_on_space_changed):
        EventBus.document_color_space_changed.connect(_on_space_changed)
    if not EventBus.tonemap_changed.is_connected(refresh):
        EventBus.tonemap_changed.connect(refresh)
    follow()


func _exit_tree() -> void:
    if EventBus.active_document_changed.is_connected(_on_front_changed):
        EventBus.active_document_changed.disconnect(_on_front_changed)
    if EventBus.document_color_space_changed.is_connected(_on_space_changed):
        EventBus.document_color_space_changed.disconnect(_on_space_changed)
    if EventBus.tonemap_changed.is_connected(refresh):
        EventBus.tonemap_changed.disconnect(refresh)
    _let_the_old_one_go()


## Moves the two connections onto whichever document is in front now and
## writes the title. Public because the boot calls it once and a suite reads
## the title it leaves.
func follow() -> void:
    var front := _documents.front if _documents != null else null
    var document := front.get_document() if front != null else null
    if document != _watched:
        _let_the_old_one_go()
        _watched = document
        if document != null:
            document.path_changed.connect(refresh)
            document.modified_changed.connect(refresh)
    refresh()


## Writes the title. Takes and ignores what any of the three signals carries,
## so one handler serves them all.
func refresh(_value: Variant = null) -> void:
    if not is_inside_tree() or _watched == null or not is_instance_valid(_watched):
        return
    var mark := "*" if _watched.modified else ""
    # The gamut a picked colour means, which is the document's, so the red
    # `1, 0, 0` paints can be read off the window rather than looked up.
    var space := _watched.color_space if _watched.color_space != null else SaColorSpace.unspecified()
    var words := space.gamut().display_name
    # And how a wider display is filled when it is not the correct rendering, so a
    # colour judged under Native is never taken for one that exports.
    if SaSettings.display_fill != SaDisplayFill.CORRECT:
        words = tr("%s, %s") % [words, tr(SaDisplayFill.display_name(SaSettings.display_fill))]
    get_window().title = tr("%s%s (%s) - Sara") % [SaDocumentFiles.display_name(_watched), mark, words]


## Only the document the title names writes it again, so a document behind
## another tab changing its space, and the Info docker's scratchpad, leave the
## window called what it was.
func _on_space_changed(changed: SaDocument) -> void:
    if changed == _watched:
        refresh()


func _on_front_changed(_surface: SaSurface) -> void:
    follow()


func _let_the_old_one_go() -> void:
    if _watched == null or not is_instance_valid(_watched):
        _watched = null
        return
    if _watched.path_changed.is_connected(refresh):
        _watched.path_changed.disconnect(refresh)
    if _watched.modified_changed.is_connected(refresh):
        _watched.modified_changed.disconnect(refresh)
    _watched = null
