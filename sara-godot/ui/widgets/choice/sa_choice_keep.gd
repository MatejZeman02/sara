## The rows, headings and lines a `SaChoicePopup` keeps between one build of its
## list and the next, so a menu filled again before every open makes over the
## rows it already has rather than building each one afresh.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## **Why.** A row is a button, a chord label and a box, and building one and
## adding it to the column cost 0.3 to 0.5 ms on the painter's machine, so the
## Layer menu's sixty rows were 17 to 19.5 ms of the frame it opened in. Making a
## row over is setting a few properties on nodes that are already in the tree.
##
## **How a build runs.** The list's `clear` hands every child of the column here
## as spare and leaves it where it is. Each `add_row`, `add_section` and
## `add_gap` then asks for its spare, a row by its id, a heading by its words and
## a line by how many lines came before it, and the popup makes it over and
## places it at the next slot. What the build never asked for is freed by
## `settle`, which the popup calls before it measures, opens or searches, and
## once deferred after the clear for a list that is never opened. A row that is
## found by a search is never kept, because the next needle takes it away.
##
## Its own class rather than more of the popup, because the popup owns the rows
## a painter sees and this owns which nodes they are made of. A list that adds
## nodes of its own to a row, as the search window adds its columns, does not
## ask for one, and builds its rows afresh as before.
class_name SaChoiceKeep
extends RefCounted

var _column: VBoxContainer = null
## Each spare node under its key, `row:<id>`, `section:<words>` or `gap:<n>`.
var _spare: Dictionary = {}
## How many of the column's children this build has placed, which is the slot
## the next one goes to.
var _placed: int = 0
## How many lines this build has asked for, the `<n>` of the next one's key.
var _gaps: int = 0
## How many rows this build made afresh and how many it made over, read by the
## suites and by a frame trace that asks why a build was slow. Written here only.
var built: int = 0
var reused: int = 0


func _init(column: VBoxContainer = null) -> void:
    _column = column


## Every child of the column becomes spare for the build that follows, and a
## found row or heading goes at once. Spares a build before this one left are
## among the children, so two clears in a row lose nothing.
func stash() -> void:
    _spare.clear()
    _placed = 0
    _gaps = 0
    built = 0
    reused = 0
    var gaps := 0
    for child in _column.get_children():
        var key := ""
        if child.has_meta(SaChoiceSearch.FOUND):
            key = ""
        elif child is SaChoiceRow:
            key = "row:" + String((child as SaChoiceRow).id)
        elif child is HSeparator:
            key = "gap:%d" % gaps
            gaps += 1
        elif child is Label:
            key = "section:" + (child as Label).text
        if key.is_empty() or _spare.has(key):
            drop(child)
            continue
        _spare[key] = child


## The spare row of *id*, taken out of the spares, or null. The popup makes it
## over with `SaChoiceRow.refill` and places it, or drops it when it is of
## another shape.
func take_row(id: StringName) -> SaChoiceRow:
    return _take("row:" + String(id)) as SaChoiceRow


## Shows and places the spare heading reading *heading*, and says whether there
## was one, which the popup otherwise builds.
func reuse_section(heading: String) -> bool:
    return _reuse(_take("section:" + heading) as Control)


## Shows and places the spare line in the place of the one asked for, and says
## whether there was one.
func reuse_gap() -> bool:
    _gaps += 1
    return _reuse(_take("gap:%d" % (_gaps - 1)) as Control)


func _reuse(node: Control) -> bool:
    if node == null:
        return false
    node.visible = true
    place(node, false)
    return true


func _take(key: String) -> Node:
    var node: Node = _spare.get(key)
    _spare.erase(key)
    return node


## Puts *node* at the next slot of the column, adding it first when it is new.
## *fresh* says which of the two counts it goes in. A node already at its slot
## is not moved, so a menu that lists what it listed last time moves nothing.
func place(node: Control, fresh: bool) -> void:
    if node.get_parent() == null:
        _column.add_child(node)
    if node.get_index() != _placed:
        _column.move_child(node, _placed)
    _placed += 1
    if node is SaChoiceRow:
        if fresh:
            built += 1
        else:
            reused += 1


## Frees *node*, a spare the build could not use.
func drop(node: Node) -> void:
    if node.get_parent() == _column:
        _column.remove_child(node)
    node.queue_free()


## Frees every spare this build never asked for. Safe to run any number of
## times, and a list with no spares does nothing.
func settle() -> void:
    for node: Node in _spare.values():
        drop(node)
    _spare.clear()
