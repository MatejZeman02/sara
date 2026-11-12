## Renaming a layer from its row: the field, what confirms it, what throws it
## away, and what a typed name is allowed to be.
##
## Out of `layer_list.gd`, which the rename would otherwise have made too long.
## The seam is the one the row view
## already draws: the row owns how the field looks, the list owns which row is
## being renamed and what a confirmed name does to the document, and this owns
## the gesture in between.
##
## It holds the layer as well as the row index, because the two can come apart:
## the docker rebuilds every row whenever the document's tree moves, and an
## index that survives such a rebuild names a different layer afterwards.
class_name SaLayerRename
extends RefCounted

## A confirmed rename. The layer travels with the index so the list can check
## that the row still carries it before touching anything.
signal committed(index: int, layer: SaLayer, wanted: String)

## A rename that wrote nothing: Escape, an empty field, or a row that went away
## underneath it.
signal cancelled(index: int)

var _edit: LineEdit = null
var _label: Label = null
var _layer: SaLayer = null
var _index: int = -1

## Set while the field is being taken down. Hiding it and dropping its focus
## raises `focus_exited` from inside the close, and without this that would be
## read as a second answer to a rename already answered.
var _closing: bool = false


## What a typed name becomes, in the row's field and in the docker's rename
## dialog alike: its edges trimmed, so a name that is only spaces reads as empty
## and cancels. Every other character stays, a full stop and a colon among them,
## because the layer keeps the typed name beside the one its node can hold
## (`SaLayer.take_name`).
static func sanitize_name(raw: String) -> String:
    return raw.strip_edges()


## Opens the name of the row at *index* for editing, in its *edit* field over its
## *label*, and returns whether it opened. A second call while one is open
## confirms the first, which is what clicking from one row to another does in
## every list that offers this.
##
## The field, the label and the layer rather than the row, because the row is
## the list's own and the list opens the field on no filter row.
func begin(edit: LineEdit, label: Label, layer: SaLayer, index: int) -> bool:
    if active():
        commit()
    if edit == null or not is_instance_valid(layer):
        return false

    _edit = edit
    _label = label
    _layer = layer
    _index = index
    _closing = false

    # The layer's own name rather than the row's label, because a group's label
    # carries the fold mark and renaming one must not write the mark into the
    # document.
    edit.text = str(layer.name)
    # The layer's note travels with the field. Sara renames a layer in the row
    # itself rather than in a dialog, so this is the layer's rename dialog, and
    # a painter typing a name is exactly the painter who wants to see what the
    # layer was noted as. The field shows it and never writes it: a note is set
    # through the door, and a rename that silently rewrote one would be the
    # losing-a-name failure this file already argues against.
    edit.tooltip_text = layer.comment
    edit.visible = true
    label.visible = false
    if not edit.text_submitted.is_connected(_on_submitted):
        edit.text_submitted.connect(_on_submitted)
        edit.focus_exited.connect(_on_focus_exited)
        edit.gui_input.connect(_on_gui_input)
    # Both focus calls are guarded, because a row built by a test is never added
    # to a tree and Godot raises on either of them there.
    if edit.is_inside_tree():
        edit.grab_focus()
    edit.select_all()
    edit.caret_column = edit.text.length()
    return true


## Whether a field is open, and on which row. -1 when none is.
func active() -> bool:
    return _edit != null and is_instance_valid(_edit)


func row() -> int:
    return _index if active() else -1


## The layer being renamed, for whoever wants to know without reading the row.
func renamed_layer() -> SaLayer:
    return _layer if active() and is_instance_valid(_layer) else null


## Confirms the field: Enter, and the focus leaving it. An empty name is not a
## name, so it cancels rather than writing one nothing can read on a row.
func commit() -> void:
    if not active():
        return
    var wanted := sanitize_name(_edit.text)
    var at := _index
    var which := _layer
    _close()
    if wanted.is_empty() or which == null or not is_instance_valid(which):
        cancelled.emit(at)
        return
    committed.emit(at, which, wanted)


## Throws the field away and leaves the name as it was. Escape, and a row that
## is being taken down under an open field.
func cancel() -> void:
    if not active():
        return
    var at := _index
    _close()
    cancelled.emit(at)


func _close() -> void:
    _closing = true
    if is_instance_valid(_edit):
        _edit.visible = false
        if _edit.is_inside_tree():
            _edit.release_focus()
    if is_instance_valid(_label):
        _label.visible = true
    _edit = null
    _label = null
    _layer = null
    _index = -1
    _closing = false


func _on_submitted(_text: String) -> void:
    commit()


## Escape is taken here rather than in unhandled input, because a `LineEdit` that
## does not consume it lets it reach whatever else in the window answers Escape,
## and the docker's own close is one of those.
func _on_gui_input(ev: InputEvent) -> void:
    var key := ev as InputEventKey
    if key == null or not key.pressed or key.keycode != KEY_ESCAPE:
        return
    var edit := _edit
    cancel()
    if is_instance_valid(edit):
        edit.accept_event()


## Clicking away confirms, rather than discarding what was typed. Losing a name
## silently is the worse of the two failures, and Escape is the door out that
## says so out loud.
func _on_focus_exited() -> void:
    if _closing:
        return
    commit()
