## The drawing assistants' section of a `.sad`: the rulers and every later
## guide a document keeps, written under a header key of their own rather than
## inside the per-module object.
##
## **Why a section of its own.** The guides are the document's, as the symmetry
## axes are, and a reader looking at a file for its rulers finds them under
## one key. In memory they ride in the document's `module_data` under
## `SaStrokeHold.GUIDES_KEY`, so `SaDocument` holds no field for them and a
## module reads and writes them through the door. A save lifts the key out of
## the `modules` object into `assistants`, and an open puts it back.
##
## **Additive to v4.** A file without the key opens as before with no guide, and
## an older Sara that meets the key never reads it. Nothing is written for a
## document with no guide, so its header is the one it always had.
class_name SaSadAssistants
extends RefCounted

## The header key the guides are written under.
const HEADER_KEY := "assistants"


## Moves the document's guides out of the `modules` object *header* already
## holds and into their own key. Nothing for a document with none.
static func write_header(header: Dictionary[String, Variant]) -> void:
    var modules: Variant = header.get("modules")
    if not (modules is Dictionary):
        return
    var written: Dictionary = modules
    var guides: Variant = written.get(SaStrokeHold.GUIDES_KEY)
    written.erase(SaStrokeHold.GUIDES_KEY)
    if written.is_empty():
        header.erase("modules")
    if not SaTyped.list(guides).is_empty():
        header[HEADER_KEY] = guides


## Puts the guides *header* holds back into *document*'s `module_data`, after
## the `modules` object was read into it. A file without the section leaves
## the document with none.
static func read_header(header: Dictionary[String, Variant], document: SaDocument) -> void:
    var guides: Variant = header.get(HEADER_KEY)
    if document == null or SaTyped.list(guides).is_empty():
        return
    document.module_data[SaStrokeHold.GUIDES_KEY] = guides
