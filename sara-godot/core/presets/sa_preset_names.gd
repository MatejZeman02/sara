## Which stored preset a typed name means, with case folded, and the one move
## that changes only the case of a preset's file.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## **Case is folded on every platform.** Windows and macOS keep a folder whose
## names ignore case, so "pencil" saved beside "Pencil" writes over
## `Pencil.tres` there, and a rename from one to the other writes the file and
## then deletes it. Linux would keep two files, and a library moved to another
## machine would then hold two presets where it held one. So two names that
## differ only in case are one preset everywhere, and Linux shows what the
## other two would do.
##
## Its own file because `SaPresetStore` stands at its line limit, and the
## store answers [method taken_as] with one call to this.
class_name SaPresetNames
extends RefCounted

## The file a case-only rename passes through, beside the preset's own, so the
## move never asks a folder that ignores case to rename a file onto itself.
const PASSING_SUFFIX: String = ".renaming"


## The stored name among *names* that *wanted* would land on, compared with
## case folded, or empty when no preset has it. *wanted* is sanitised as a save
## would sanitise it, so a typed name and a stored one are compared alike.
static func taken_as(names: PackedStringArray, wanted: String) -> String:
    var folded := SaPresetStore.sanitize_name(wanted).to_lower()
    if folded.is_empty():
        return ""
    for stored: String in names:
        if stored.to_lower() == folded:
            return stored
    return ""


## Whether *a* and *b* name one preset and differ only in case.
static func only_case(a: String, b: String) -> bool:
    var left := SaPresetStore.sanitize_name(a)
    var right := SaPresetStore.sanitize_name(b)
    return left != right and left.to_lower() == right.to_lower()


## Renames the preset *from* to *to* in *store*, two names that differ only in
## case, and answers the name it now has, or empty when nothing moved.
##
## **A move of the file, never a write and a delete.** A write under "pencil"
## on a folder that ignores case lands in `Pencil.tres`, and the delete of
## "Pencil" after it removes the preset just written. The file goes to a
## passing name first and from there to its new one, so each step renames a
## file onto a name nobody holds. A step that fails puts the file back.
##
## The thumbnail is dropped rather than moved, since it is disposable and is
## drawn again for the new name. The store is told something outside it
## touched the folder, so its listing and what it knew of the old name are read
## afresh.
static func move_case(store: SaPresetStore, from: String, to: String) -> String:
    if store == null or not only_case(from, to):
        return ""
    var old_name := store.taken_as(from)
    var new_name := SaPresetStore.sanitize_name(to)
    if old_name.is_empty():
        return ""
    var old_path := store.dir.path_join(old_name + SaPresetStore.EXTENSION)
    var new_path := store.dir.path_join(new_name + SaPresetStore.EXTENSION)
    var passing := old_path + PASSING_SUFFIX
    if DirAccess.rename_absolute(old_path, passing) != OK:
        return ""
    if DirAccess.rename_absolute(passing, new_path) != OK:
        DirAccess.rename_absolute(passing, old_path)
        store.forget_tags()
        return ""
    SaPresetThumbs.forget(store.dir, old_name)
    store.forget_tags()
    return new_name


## Whether *root* is a place a preset store may write: an absolute path or a
## `user://` one. An empty or relative root is the process's working folder,
## which under a test run is the project folder, so a store pointed there would
## write every stock preset, its bundle record and its tag marker into the
## source tree. Says so with `push_error` and answers false instead.
static func writable_root(root: String) -> bool:
    if root.is_absolute_path():
        return true
    push_error("SaPresetStore: refusing to write under '%s', which is empty or relative. Use an absolute folder." % root)
    return false
