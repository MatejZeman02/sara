## The file a document was opened from when that file is not a `.sad`: a JPEG,
## a PNG or an OpenRaster file. The title, the tab, the Info docker and the
## prompts read its name while the document has no `.sad` of its own, so two
## photographs open as two names and not as two Untitled tabs.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Kept beside the document rather than in [member SaDocument.file_path],
## because that member is where Save writes, and a picture's path there would
## have Ctrl+S write a `.sad` over the photograph. It is held on the document
## as metadata, so it lives and dies with it and no table outside has to be
## told when a tab closes. A document that is reset to a fresh one forgets it,
## and one saved to a `.sad` stops reading it, since its own file names it then.
class_name SaDocumentSource
extends RefCounted

## The metadata key the source path is held under.
const KEY := &"sa_document_source"


## Records that *doc* was just opened from the picture at *path*, and that what
## it holds is that picture exactly, so nothing would be lost by closing it.
## Clean here means clean for the questions that ask whether to discard: the
## document still has no file of its own, so Save asks where as before. The
## listeners of the name hear `path_changed`, since a clean document whose
## mark did not move would otherwise go on reading Untitled.
static func opened_from(doc: SaDocument, path: String) -> void:
    if doc == null:
        return
    doc.set_meta(KEY, path)
    doc.mark_saved("")
    doc.path_changed.emit(doc.file_path)


## The path *doc* was opened from, or empty for a document that was not opened
## from a picture or has been saved to a `.sad` since.
static func path_of(doc: SaDocument) -> String:
    if doc == null or not doc.file_path.is_empty():
        return ""
    return str(doc.get_meta(KEY, ""))


## The name a document goes by: its `.sad`'s file name once it has one, the
## picture's file name while it has not, and empty for one never saved nor
## opened from a file.
static func name_of(doc: SaDocument) -> String:
    if doc == null:
        return ""
    if not doc.file_path.is_empty():
        return doc.file_path.get_file()
    return path_of(doc).get_file()


## Forgets where *doc* came from, for a document rebuilt as a fresh one.
static func forget(doc: SaDocument) -> void:
    if doc != null and doc.has_meta(KEY):
        doc.remove_meta(KEY)
