## The document's name as the Info docker's Name row shows it: the name alone
## once saved, a star after it while there are unsaved changes, and the word
## "autosaved" after the star once a recovery copy holds those changes.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The text is said once, by [method text_for] , and an instance keeps it up to
## date by listening rather than polling. It hears the document's public signals
## and the autosave's `saved`, so neither `SaAutosave` nor the window title is
## touched. The title builds its name and star in `Main._refresh_window_title`,
## and the suite beside this reads that the two agree for the same document.
##
## "Autosaved" stands only while the document is modified. A saved document
## needs no recovery copy, and the label says nothing then. Any change after the
## copy was written takes the word away until the next copy lands, because the
## copy does not hold everything the star stands for. The mark is decided by
## the signals alone, never by the autosave's timer or the path it wrote.
class_name SaDocumentLabel
extends RefCounted

## The text changed, with the text it now reads.
signal changed(text: String)

## The document whose name this reads.
var document: SaDocument = null

## The autosave's `saved` signal, which says a recovery copy is on disk, or an
## empty signal when there is no autosave to hear.
var copies: Signal = Signal()

## Whether a recovery copy was written after the document's last change.
var autosaved: bool = false

## What the row reads now, kept so a listener joining late reads it at once.
var text: String = ""


## Listens to *doc* and to *copy_written*, the autosave's `saved`. That is
## empty when there is no autosave, as in a suite or before main has started
## one. The signal rather than the autosave is handed in, because `SaAutosave`
## is an inner file of `core/sad-file` and its signal is all this reads.
func _init(doc: SaDocument, copy_written: Signal = Signal()) -> void:
    document = doc
    copies = copy_written
    if doc != null:
        doc.modified_changed.connect(_on_modified_changed)
        doc.document_changed.connect(_on_changed)
        doc.chunks_invalidated.connect(_on_chunks_invalidated)
        doc.path_changed.connect(_on_path_changed)
    if not copy_written.is_null():
        copy_written.connect(_on_autosaved)
    text = _read()


## The row's text for a document named *file_name*, empty for one never saved,
## *modified* when it has unsaved changes, and *copy_written* when a recovery
## copy was written after its last change. The mark needs both, so a saved
## document reads its name alone whatever the autosave did.
static func text_for(file_name: String, modified: bool, copy_written: bool) -> String:
    var shown: String = file_name if not file_name.is_empty() else String(TranslationServer.translate("Untitled"))
    if not modified:
        return shown
    if copy_written:
        return String(TranslationServer.translate("%s*, autosaved")) % shown
    return "%s*" % shown


## The name the window title shows for *doc*: the file's name, the picture's
## it was opened from while it has no `.sad`, or empty for a document never
## saved nor opened from a file.
static func file_name_of(doc: SaDocument) -> String:
    return SaDocumentSource.name_of(doc)


func _read() -> String:
    if document == null:
        return ""
    return text_for(file_name_of(document), document.modified, autosaved)


func _update() -> void:
    var now := _read()
    if now == text:
        return
    text = now
    changed.emit(text)


## Either way the copy does not stand for the change: a save makes it
## unneeded, and a first change after a save is not in it yet.
func _on_modified_changed(_modified: bool) -> void:
    autosaved = false
    _update()


func _on_changed() -> void:
    autosaved = false
    _update()


func _on_chunks_invalidated(_grid_positions: Array) -> void:
    _on_changed()


func _on_path_changed(_path: String) -> void:
    _update()


## A copy landed. It counts only while the document still has changes, as a
## copy written into a document saved meanwhile is deleted as it lands.
func _on_autosaved(_path: String) -> void:
    autosaved = document != null and document.modified
    _update()
