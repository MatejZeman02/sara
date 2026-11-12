## The rows of the layers docker: one per layer, top of the stack first.
##
## The home of the row drag and of the eye sweep, with which rows are picked kept by `picked`, an `SaLayerPick`: press a
## row, move past a few pixels, and the row nearest the pointer on release is where it goes. The list only reports the two
## indices and which edge of the target the drop landed on, `item_dropped(from, to, mode)`, and the docker turns those into
## a move on the document, so the list knows nothing about layers beyond the one each row carries.
class_name SaLayerList
extends ScrollContainer

signal item_selected(index: int)
## A row was dragged from one index and released over another.
signal item_dropped(from_index: int, to_index: int, mode: Drop)
## A layer was renamed from its row, after the name had landed on the layer.
signal item_renamed(index: int, new_name: String)

## A group's fold mark was pressed. The list does not decide what a collapse
## hides, because that is a question about the document's tree and the docker is
## what reads it.
signal group_toggled(index: int)
## A row's note mark was pressed, the brush aimed already as a plain press on the row aims it. The docker opens the note.
signal note_pressed(index: int)
## A ground row's picture was double clicked, and the docker opens its settings.
signal ground_opened(index: int)

## A filter row was picked, or null when a layer row took the pick back. The
## docker shows that record's panel, or clears it.
signal filter_selected(record: SaAttachedFilter)

## Pixels the pointer has to travel before a press becomes a drag rather than
## a click, so a click that wobbles does not reorder anything.
const DRAG_THRESHOLD: float = 6.0

## Where a drop would land while a row is being dragged. NONE is not dragging,
## and REFUSED is a row a dragged mask cannot go onto. It stays here rather than
## beside the drawing of it, because the docker and the drag tests both name it.
enum Drop { NONE, ABOVE, BELOW, INTO, REFUSED }

## The column the rows stand in, which keeps a sleeping row's place.
var vbox: SaLayerRowColumn

## Which rows' pictures a change of the document marks, and the stroke's row.
var marks := SaLayerPictureMarks.new()

## The canvas whose document the rows describe. Assigning it subscribes to that
## document, because a thumbnail has to notice a stroke and nothing else in the
## docker fires while one is being painted.
var target_canvas: SaCanvas = null:
    set(value):
        _unwatch_document()
        target_canvas = value
        _watch_document()

## The rows, top of the stack first, written by this list and by the fold's
## `SaLayerRowReuse` beside it, and read by the docker for the layer each row
## carries. A layer's row and a filter's are both `SaRowFrame`s.
var rows: Array[SaRowFrame] = []

## Which rows are picked: the set, the active row, the anchor and the picked
## filter record. The docker and the captures ask it directly, and the rows are
## handed it as they are built, so each answers for itself what it looks like
## and which rows a press on it acts through.
var picked: SaLayerPick

## The rename gesture. `layer_rename.gd` holds what a rename means, this file
## holds which row asked for one and what a confirmed name does next.
var _rename := SaLayerRename.new()

## Which rows a refresh drew and which wait to come into view, as
## [SaLayerRowRefresh] says.
var _refreshes := SaLayerRowRefresh.new()

## The layer the last plain press on a layer row landed on, which the double
## click that follows renames, kept as the layer since the first press can rebuild
## every row before the box lays them out.
var _pressed_layer: SaLayer = null
## Scrolls the list while a dragged row is held near its top or bottom edge.
var _edge := SaLayerListEdgeScroll.new(self, _aim_at)
## Keeps the rows far from the view asleep, so a show of the docker lays out
## the rows in view and no other, as [SaLayerRowSleep] says.
var sleep := SaLayerRowSleep.new(self)
## The drag of a mask, armed instead of a row's by a press on a mask picture.
var mask_drag := SaLayerMaskDrag.new()

## The row drag: which row a press armed, where the pointer started, whether
## the travel has passed the threshold, and which row wears the mark and what
## the mark says. The mark is kept so it can be taken off the row it was on
## without restyling the whole list.
##
## `dragging`, `drop_row` and `drop_mode` are read by the capture harness and
## the tests rather than a screenshot, and written here alone.
var _drag_from: int = -1
var _drag_origin: Vector2 = Vector2.ZERO
var dragging: bool = false
var drop_row: int = -1
var drop_mode: Drop = Drop.NONE

## The eye sweep: the row a press on an eye armed, where that press landed,
## whether travel has passed the threshold, and the one value every eye it
## crosses is set to. Its own state rather than a share of the row drag's,
## because the two can never both be live: the eye button consumes a press
## before the row's own `gui_input` ever sees it.
var _eye_armed: int = -1
var _eye_origin: Vector2 = Vector2.ZERO
var _eye_dragging: bool = false
var _eye_wanted: bool = false

## The layers the sweep has actually changed, and what each was before, so one
## `commit_pair` at release covers all of them and undo restores each to its
## own state rather than to one shared value.
var _eye_touched: Array[SaLayer] = []
var _eye_previous: Array[bool] = []
var _eye_last_idx: int = -1

var item_count: int:
    get:
        return rows.size()


func _init() -> void:
    horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO

    vbox = SaLayerRowColumn.new(sleep.held)
    vbox.add_theme_constant_override(&"separation", SaUI.px(2))
    add_child(vbox)
    vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    add_child(_edge)
    add_child(sleep)

    # The rest of a drag is taken on the list rather than on the row, and there
    # is nothing to take until a row has been pressed. See `_input`.
    set_process_input(false)
    # A picture out of sight stops asking each frame whether it is shown, and
    # a scroll, a resize or rows laid out again bring it back.
    get_v_scroll_bar().value_changed.connect(_wake_rows)
    resized.connect(_wake_rows)
    vbox.sort_children.connect(_wake_rows)

    _rename.committed.connect(_on_rename_committed)
    picked = SaLayerPick.new(_on_pick_style_moved, func(record: SaAttachedFilter) -> void: filter_selected.emit(record))
    _rename.cancelled.connect(_on_rename_cancelled)


## A stroke, an undo or anything else that moves pixels, which [member marks]
## says which pictures of the rows it leaves old.
func _on_document_pixels_changed(arg: Variant = null) -> void:
    marks.heard(arg, _shown_document(), rows)


## A scroll, a resize or the rows laid out again: the rows that came into view
## are drawn if a refresh owed them, and their pictures asked again.
func _wake_rows(_value: float = 0.0) -> void:
    sleep.follow()
    _refreshes.pay_in_view(self, _shown_document())
    SaLayerPictureMarks.wake_all(rows)


func _watch_document() -> void:
    var doc: SaDocument = target_canvas.document if target_canvas != null else null
    if doc == null:
        return
    if not doc.chunks_invalidated.is_connected(_on_document_pixels_changed):
        doc.chunks_invalidated.connect(_on_document_pixels_changed)
    if not doc.document_changed.is_connected(_on_document_pixels_changed):
        doc.document_changed.connect(_on_document_pixels_changed)
    # The pick moves the rims and nothing else, and a pick on the active row
    # sets no new active layer, so nothing would rebuild the rows for it.
    if not doc.mask_target_changed.is_connected(_on_mask_target_changed):
        doc.mask_target_changed.connect(_on_mask_target_changed)
    if not doc.layer_changed.is_connected(_on_document_pixels_changed):
        doc.layer_changed.connect(_on_document_pixels_changed)


func _unwatch_document() -> void:
    var doc: SaDocument = target_canvas.document if target_canvas != null and is_instance_valid(target_canvas) else null
    if doc == null or not is_instance_valid(doc):
        return
    if doc.chunks_invalidated.is_connected(_on_document_pixels_changed):
        doc.chunks_invalidated.disconnect(_on_document_pixels_changed)
    if doc.document_changed.is_connected(_on_document_pixels_changed):
        doc.document_changed.disconnect(_on_document_pixels_changed)
    if doc.mask_target_changed.is_connected(_on_mask_target_changed):
        doc.mask_target_changed.disconnect(_on_mask_target_changed)
    if doc.layer_changed.is_connected(_on_document_pixels_changed):
        doc.layer_changed.disconnect(_on_document_pixels_changed)


func _on_mask_target_changed(_mask: SaMask) -> void:
    refresh_all()


func clear() -> void:
    # An open field belongs to a row that is about to be freed, and its
    # `focus_exited` would otherwise arrive after the row it named had gone.
    _rename.cancel()
    var children := vbox.get_children()
    children.reverse()
    for child in children:
        SaLayerRowReuse.let_go(self, child)
    rows.clear()
    picked.reset()


## A row for *layer*. *depth* indents it one step per group it sits inside, and
## a group's row carries a folder mark before its name. A row with no layer is
## a label and nothing else, which is what the drag tests build.
func add_item(label: String, depth: int = 0, is_group: bool = false, layer: SaLayer = null) -> int:
    var idx := rows.size()
    var row := SaLayerRowView.new(label, depth, is_group, idx, layer, picked)

    # Connected here rather than in the row, so the handlers stay private to
    # the file that answers them, and read the index a fold may have renumbered.
    row.eye_btn.pressed.connect(func() -> void: _on_eye_pressed(row.row_index))
    # Armed on the down rather than the click, so a drag that leaves the button
    # before release, which cancels the button's own `pressed`, still answers. A
    # press that never becomes a drag is `_on_eye_pressed`'s.
    row.eye_btn.button_down.connect(func() -> void: _arm_eye(row.row_index, get_global_mouse_position()))
    for which: StringName in row.toggles:
        (row.toggles[which] as Button).pressed.connect(func() -> void: _on_toggle_pressed(row.row_index, which))
    row.gui_input.connect(func(ev: InputEvent) -> void: _on_row_gui_input(ev, row.row_index))
    if row.disclose != null:
        row.disclose.pressed.connect(func() -> void: group_toggled.emit(row.row_index))
    row.comment_btn.pressed.connect(func() -> void: SaLayerRowView.aim_brush(_shown_document(), layer, &""))
    row.comment_btn.pressed.connect(func() -> void: note_pressed.emit(row.row_index))

    return _adopt(row)


## A row for *record*, which hangs on *node*, null being the document's root,
## one step past the node's own *node_depth*. It carries no layer, so `layer_at`
## answers null for it, which is what stops every gesture written for a layer
## from acting on a filter.
func add_filter_item(record: SaAttachedFilter, node: SaLayer, title: String, node_depth: int = 0) -> int:
    var idx := rows.size()
    var row := SaFilterRowView.new(record, node, title, node_depth, idx, picked)
    row.eye_btn.pressed.connect(func() -> void: _on_filter_eye_pressed(row.row_index))
    row.gui_input.connect(func(ev: InputEvent) -> void: _on_filter_row_gui_input(ev, row.row_index))
    return _adopt(row)


## Takes a built row into the list and the pick, and answers its index.
func _adopt(row: SaRowFrame) -> int:
    var idx := rows.size()
    vbox.add_child(row)
    rows.append(row)
    picked.row_added(row is SaFilterRowView)
    _update_row_style(idx)
    SaUI.apply_ui_theme(row)
    _update_row_display(idx)
    return idx


## The filter row at *idx*, or null for a layer's row and outside the list.
func filter_at(idx: int) -> SaFilterRowView:
    return rows[idx] as SaFilterRowView if idx >= 0 and idx < rows.size() else null


## The record row *idx* draws, or null for a layer's row. What the docker reads,
## so it never has to name the row's class.
func record_at(idx: int) -> SaAttachedFilter:
    var row := filter_at(idx)
    return row.record if row != null else null


## Which way a group row's fold mark points. The docker keeps the set of closed
## groups, so the row is told rather than asked.
func set_item_collapsed(idx: int, collapsed: bool) -> void:
    if idx >= 0 and idx < rows.size():
        rows[idx].set_collapsed(collapsed)


## How many rows there are, for whoever holds only the list: the drag tests and
## the capture step. The docker counts layers instead, from the document.
func row_count() -> int:
    return rows.size()


## Settles every layer thumbnail under *root*, the dockers that are windows of
## their own included, because each is a node under it.
##
## The capture harness asks this before every shot. A thumbnail
## redraws at most every quarter second of wall clock and a scenario waits in
## drawn frames, so how much of the interval a `wait` covers depends on how
## fast the frames come, and without a settle two runs of one scenario could
## differ on the active layer's picture. Here on the list because the list is the package's
## door, and not behind a preference, so the painter keeps the interval.
## Answers whether one is still to be drawn, as [method SaLayerThumbnail.settle_all] says.
static func settle_thumbnails(root: Node) -> bool:
    return SaLayerThumbnail.settle_all(root)


## The layer row *idx* carries, or null outside the list, for a row built
## without one, and for one whose layer has been freed.
func layer_at(idx: int) -> SaLayer:
    if idx < 0 or idx >= rows.size() or not rows[idx].has_layer():
        return null
    return rows[idx].layer


# --- Selection -----------------------------------------------------------------


## The layers behind the picked rows, in the list's own order, top of the stack
## first. Empty when the rows carry no layers, which is what a test list is.
##
## **A row can outlive its layer, and `is` against a freed instance raises**.
## `has_layer` asks `is_instance_valid` for that reason and not for tidiness:
## `Left operand of 'is' is a previously freed instance` is a script error, not
## a false, so an `is` guard meant to skip a bad row would be the line that
## throws. Opening a document sets its active layer while the docker still
## shows the rows of the one before, whose layers are freed by then.
##
## The rows are not cleared first and do not need to be: `sync_layer_list`
## clears and rebuilds them in the same call, and the only thing that reads them
## first is this, which exists so a selection survives a rebuild. A set that
## survives a rebuild has to tolerate a rebuild that replaced the document, and
## that is this function's job rather than its caller's.
func selected_layers() -> Array[SaLayer]:
    var out: Array[SaLayer] = []
    for i in picked.selected_indices():
        if rows[i].has_layer():
            out.append(rows[i].layer)
    return out


## Puts the set back after the docker has rebuilt the rows, by layer rather
## than by index: a group operation renumbers every row under it, so the
## indices from before the rebuild name the wrong layers afterwards.
##
## A set without the active layer is a set the operation replaced, a duplicate
## or a group, and it collapses to the active row. Adding the new active layer
## to the old set instead makes Duplicate duplicate twice, the set growing by
## one on every rebuild.
func select_layers(layers: Array[SaLayer], active: SaLayer) -> void:
    var wanted: Array[int] = []
    var active_idx := -1
    # Read off the rows rather than through [method layer_at], whose checks
    # were a third of this on a stack of 790 rows.
    for i in rows.size():
        var row := rows[i]
        if row.record != null or not row.has_layer():
            continue
        var layer := row.layer
        if layers.has(layer):
            wanted.append(i)
        if layer == active:
            active_idx = i
    picked.restore(wanted, active_idx)


## The pick moved the look of these rows. A rebuild can have shortened the list
## since the indices were true, so each is checked against the rows there are.
func _on_pick_style_moved(indices: Array[int]) -> void:
    if _shown_document() != null:
        _shown_document().picked.pick(selected_layers())
    for i in indices:
        if i >= 0 and i < rows.size():
            _update_row_style(i)


## Draws every row again from the document, the rows in view at once and the
## rest when they come into view, as [SaLayerRowRefresh] says.
func refresh_all() -> void:
    _refreshes.all(self, _shown_document())


# --- The presses on a row --------------------------------------------------------


## One of the three right-hand toggles. Each writes the layer's own flag, so a
## group's eye and a child's lock never mean the same thing to the document.
func _on_toggle_pressed(idx: int, which: StringName) -> void:
    var layer := layer_at(idx)
    if layer == null:
        return
    var document := _shown_document()
    # The rest of the picked set follows the row that was pressed, the way the
    # eye does, so a mixed set lands on one state rather than swapping every row
    # for its opposite.
    var wanted: bool = not SaLayerFlagStep.read(layer, which)
    var reached: Array[SaLayer] = []
    for i in rows[idx].acted_on():
        var other := layer_at(i)
        if other != null:
            reached.append(other)
    if document != null:
        # One step for the whole set, which an undo takes back whole.
        SaLayerFlagStep.new(document).write(reached, which, wanted)
    else:
        # A list with no document, which only a suite builds, has no history
        # and no stack to clip in, so the locks are written alone.
        for other in reached:
            if which == &"paint":
                other.is_locked = wanted
            elif which == &"alpha":
                other.alpha_locked = wanted
    refresh_all()


## A confirmed rename, which `SaLayerOps.rename` writes as one Rename Layer
## step, so an undo gives the old name back. A list with no canvas, which only
## a suite builds, has no history and writes the name alone. The row is put
## right here rather than waiting for a rebuild, so no frame shows a stale
## label.
##
## Godot makes a node's name unique among its siblings, so a name another layer
## already holds comes back with a digit on it. The row reads the layer rather
## than the typed text, so what the painter is shown is what actually landed.
func _on_rename_committed(idx: int, layer: SaLayer, wanted: String) -> void:
    if not is_instance_valid(layer):
        return
    # The rebuild that a rebuild-triggering action would have run can have moved
    # the row out from under the index while the field was open.
    var still_there: bool = layer_at(idx) == layer
    var document := _shown_document()
    if document != null:
        SaLayerOps.new(document).rename(layer, wanted)
    elif layer.shown_name() != wanted:
        layer.take_name(wanted)
    if still_there:
        _update_row_display(idx)
        item_renamed.emit(idx, layer.shown_name())


func _on_rename_cancelled(idx: int) -> void:
    if idx >= 0 and idx < rows.size():
        _update_row_display(idx)


## The eye acts on every picked row when the one it belongs to is among them,
## and on its own row otherwise. What the eye means is the row's own state
## flipped, and the rest of the set follows it rather than each flipping its
## own, or a mixed set would only ever get more mixed.
func _on_eye_pressed(idx: int) -> void:
    var layer := layer_at(idx)
    if layer == null:
        return
    var document := _shown_document()
    var wanted := not layer.visible
    var changed: Array[SaLayer] = []
    var previous: Array[bool] = []
    for i in rows[idx].acted_on():
        var other := layer_at(i)
        if document != null and other != null and other.visible != wanted:
            changed.append(other)
            previous.append(other.visible)
            SaLayerEyeWrite.show_now(document, other, wanted)
        _update_row_display(i)
    # One step for the whole set, when the eye is in the history at all.
    if not changed.is_empty():
        SaLayerEyeWrite.commit(document, changed, previous, wanted)


## A filter row's eye: the record's enabled flag, as one history step. The rows
## redraw from the document's own announcement of it.
func _on_filter_eye_pressed(idx: int) -> void:
    var row := filter_at(idx)
    var document := _shown_document()
    if row == null or row.record == null or document == null:
        return
    SaFilterOps.new(document).set_enabled(row.record, not row.record.enabled)
    _update_row_display(idx)


## The press on a filter row: it picks the record and arms the same drag a
## layer's row arms. The layer set is left alone.
##
## A double click opens the record in the filter editor and goes no further. The
## first press of the pair has already picked the record and put its panel in
## the tool options docker, and the registry holds one instance per filter, so
## the pick is taken back before the window opens: two live sets of one filter's
## widgets would write each other's values.
func _on_filter_row_gui_input(ev: InputEvent, idx: int) -> void:
    var press := ev as InputEventMouseButton
    var row := filter_at(idx)
    if press == null or row == null or press.button_index != MOUSE_BUTTON_LEFT or not press.pressed:
        return
    # A press on a filter carries no layer to a double click that follows it.
    _pressed_layer = null
    if press.double_click:
        _open_filter_editor(row.record)
        return
    picked.pick_filter(row.record)
    SaFilterRowView.aim_brush_at_filter(_shown_document(), row.record, row.picture_at(press.position))
    _arm_drag(idx, press.global_position)


## Opens the filter editor on *record*, a filter row's or a filter layer's own,
## if its document is on screen. The drag the first press armed is dropped, the
## way `begin_rename` drops it: the pointer may move after the pair and a row
## dragged is a reorder nobody asked for.
func _open_filter_editor(record: SaAttachedFilter) -> void:
    var document := _shown_document()
    if record == null or document == null or not is_inside_tree():
        return
    _cancel_drag()
    picked.pick_filter(null)
    SaFilterEditWindow.open_in(get_tree(), document, record)


## Opens a row's name for editing, and answers whether it opened. *idx* below
## zero means the active row, which is what the F2 key asks for.
##
## The row has to carry a layer: a list built without one, which is what the
## drag tests are, has a label and nothing to write a name onto.
func begin_rename(idx: int = -1) -> bool:
    var at: int = idx if idx >= 0 else _active_row()
    if layer_at(at) == null:
        return false
    # A double click is a press, and a press starts a drag. Dropping the gesture
    # keeps a rename from reordering the stack when the pointer then moves.
    _cancel_drag()
    var row: SaRowFrame = rows[at]
    sleep.wake(row)
    return _rename.begin(row.edit, row.lbl, row.layer, at)


## The row that now carries the layer the first press of a double click landed
## on, or *idx*, the row the second press reached, when that layer has no row
## any more or no plain press came first.
func _pressed_row(idx: int) -> int:
    if _pressed_layer != null and is_instance_valid(_pressed_layer):
        for i in rows.size():
            if layer_at(i) == _pressed_layer:
                return i
    return idx


## Which row is being renamed, or -1. The tests and the state dump read this
## rather than hunting for a visible `LineEdit`.
func renaming_row() -> int:
    return _rename.row()


## F2 renames the active row, and only while the window holding this list has
## the keyboard: an unhandled key reaches the viewport it was pushed into, and
## a docker is a `Window`, so a docker that is not focused never sees this.
##
## The Layers docker's Rename command takes F2 wherever the focus is, and this
## is the list's own reading of the key. The router refuses to route a key
## while a `LineEdit` has the focus, so typing an F into a name box stays an F.
func _unhandled_key_input(ev: InputEvent) -> void:
    var key := ev as InputEventKey
    if key == null or not key.pressed or key.echo or key.keycode != KEY_F2:
        return
    if begin_rename() and is_inside_tree():
        get_viewport().set_input_as_handled()


## The press, and only the press. Everything after it is `_input`'s.
func _on_row_gui_input(ev: InputEvent, idx: int) -> void:
    var press := ev as InputEventMouseButton
    if press == null or press.button_index != MOUSE_BUTTON_LEFT or not press.pressed:
        return
    # A double click opens the name, or on a ground's or a filter layer's picture
    # its settings, and goes no further: a selection would come twice and an
    # armed drag could reorder the stack while a field is open. A pair delivered
    # in one frame lands a row low, as the first press rebuilt the rows.
    if press.double_click:
        var row := _pressed_row(idx)
        _pressed_layer = null
        var on_picture: bool = rows[idx].picture_at(press.position) == &"layer"
        if on_picture and layer_at(row).generator_params.has(SaGeneratedLayer.PARAM_TOOTH):
            ground_opened.emit(row)
        elif on_picture and SaBackdropLayer.own_filter(layer_at(row)) != null:
            _open_filter_editor(SaBackdropLayer.own_filter(layer_at(row)))
        else:
            begin_rename(row)
        return
    # Asked first, as the selection rebuilds the rows and frees the pressed one.
    var picture: StringName = rows[idx].picture_at(press.position)
    var pressed_layer := layer_at(idx)
    var document: SaDocument = target_canvas.document if target_canvas != null else null
    if rows[idx].switch_mask(press, document):
        return
    if SaLayerPick.select_opaque(document, pressed_layer, picture, press.ctrl_pressed, press.shift_pressed, press.alt_pressed):
        return
    _pressed_layer = pressed_layer
    SaUsageTally.layer_picked(SaUsageTally.ROW)
    # The row the pick decided is active, not the row under the pointer, and
    # the docker sets the document's active layer from whatever arrives here.
    item_selected.emit(picked.press(idx, press.ctrl_pressed, press.shift_pressed, true))
    if not press.ctrl_pressed and not press.shift_pressed:
        SaLayerRowView.aim_brush(target_canvas.document if target_canvas != null else null, pressed_layer, picture)
    mask_drag.arm(pressed_layer if picture == &"mask" else null)
    _arm_drag(idx, press.global_position)


## The rest of a row drag or an eye sweep: the travel and the release, once a
## press has begun one. Positions here are the docker window's own, the same
## ones `row_at` and the row rects are in.
##
## It cannot live on the row. The press
## itself selects the layer, the document announces a new active layer, the
## docker rebuilds every row, and the row holding Godot's mouse grab is freed
## under the pointer. Motion then goes to whatever row is hovered instead, and
## the release goes nowhere at all, so the drop never landed and no reorder ever
## happened. The list survives every rebuild, so the gesture lives on the list.
##
## The two never both act on one event: the eye button consumes the press that
## would have reached the row's own `gui_input`, so `_drag_from` stays -1
## whenever `_eye_armed` does not.
func _input(ev: InputEvent) -> void:
    _drag_input(ev)
    _eye_input(ev)


# --- The row drag ----------------------------------------------------------------


## Arms a drag from the press that selected a row. Nothing moves until the
## pointer has travelled `DRAG_THRESHOLD`.
func _arm_drag(idx: int, at: Vector2) -> void:
    _drag_from = idx
    _drag_origin = at
    dragging = false
    set_process_input(true)


func _drag_input(ev: InputEvent) -> void:
    if _drag_from < 0:
        return
    var motion := ev as InputEventMouseMotion
    if motion != null:
        # A release over another window never reaches this viewport, so a motion
        # with the button already up is what ends the drag it left behind. The
        # question goes to `Input` rather than to the event's own `button_mask`,
        # which an injected motion carries as zero: a capture would then cancel
        # its own drag on the first pixel of travel.
        if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
            _cancel_drag()
            return
        if not dragging and (motion.global_position - _drag_origin).length() >= DRAG_THRESHOLD:
            dragging = true
        if dragging:
            _edge.follow(motion.global_position)
        return
    var button := ev as InputEventMouseButton
    if button == null or button.button_index != MOUSE_BUTTON_LEFT or button.pressed:
        return
    var was_dragging := dragging
    _finish_drag(button.global_position, button.ctrl_pressed or button.alt_pressed)
    set_process_input(false)
    # Only a real drag eats its release. A plain click's release still belongs to
    # whatever is under it, a button on the row included.
    if was_dragging and is_inside_tree():
        get_viewport().set_input_as_handled()


## Drops the gesture without dropping the row, for a release this viewport never
## saw.
func _cancel_drag() -> void:
    drag_over(-1, Drop.NONE)
    _drag_from = -1
    dragging = false
    mask_drag.let_go()
    set_process_input(false)


## The records of *node*, null for the root, as the list draws them under its row.
static func listed_filters(records: Array[SaAttachedFilter], node: SaLayer = null) -> Array[SaAttachedFilter]:
    return SaFilterListing.listed(records, node)


## The row under *global_point*, or -1 between rows and outside the list. The
## docker asks this as well, for the right press that opens the row menu.
func row_at(global_point: Vector2) -> int:
    for i in rows.size():
        if rows[i].get_global_rect().has_point(global_point):
            return i
    return -1


## What a drop at *global_point* over row *idx* means, which is a question about
## one row's rectangle and so the row's to answer.
func drop_mode_at(idx: int, global_point: Vector2) -> Drop:
    if idx < 0 or idx >= rows.size():
        return Drop.NONE
    # A filter over a layer's row lands inside that node from the middle half of
    # the row, and the quarter at either end is between two layers, where no
    # filter may be.
    if filter_at(_drag_from) != null and filter_at(idx) == null:
        var rect := rows[idx].get_global_rect()
        var down := (global_point.y - rect.position.y) / maxf(rect.size.y, 1.0)
        var edge := SaRowFrame.GROUP_EDGE
        return Drop.INTO if down > edge and down < 1.0 - edge else Drop.NONE
    return rows[idx].drop_mode_at(global_point)


## Puts the mark where a release at *global_point* would land.
## The row under the pointer answers for itself, and a point on no row is
## measured against the nearest one, moved onto that row's nearer edge, so the
## question stays the row's own `drop_mode_at`.
func _aim_at(global_point: Vector2) -> void:
    var area := Rect2()
    if is_inside_tree():
        area = get_viewport().get_visible_rect()
    var rects: Array[Rect2] = []
    for row in rows:
        rects.append(row.get_global_rect())
    var idx := nearest_row(rects, _bottom_row(), area, global_point)
    if idx < 0:
        drag_over(-1, Drop.NONE)
        return
    var rect := rects[idx]
    var onto := Vector2(global_point.x, clampf(global_point.y, rect.position.y, rect.end.y - 1.0))
    drag_over(idx, drop_mode_at(idx, onto))


## The row a drop at *point* is measured against, given every row's rectangle,
## the row that stands for the bottom of the stack and *area*, the docker the
## rows are drawn in. Static and over rectangles, so a suite can ask it with no
## window.
##
## A reorder lands at the nearest valid place rather than demanding an exact
## drop point. A point on a row is that row. Anywhere else inside the docker,
## above the first row is the first, below the last is *bottom_row*, and
## between two rows is whichever edge is nearer. Outside the docker it is -1
## and the release cancels.
static func nearest_row(rects: Array[Rect2], bottom_row: int, area: Rect2, point: Vector2) -> int:
    for i in rects.size():
        if rects[i].has_point(point):
            return i
    if rects.is_empty() or not area.has_point(point):
        return -1
    if point.y < rects[0].position.y:
        return 0
    if point.y >= rects[rects.size() - 1].end.y:
        return bottom_row
    var best := -1
    var best_gap := INF
    for i in rects.size():
        var gap := maxf(rects[i].position.y - point.y, point.y - rects[i].end.y)
        if gap < best_gap:
            best_gap = gap
            best = i
    return best


## The last row whose layer sits in no group, which is the bottom of the stack.
## The last row itself can be a member of an open group or a filter, and a drop
## below either would land inside a group rather than at the end the painter
## dragged to. A group's row with its block under it is fine: a drop below a
## group's row clears the whole block. A list of rows with no layers, a
## suite's, answers its last row.
func _bottom_row() -> int:
    for i in range(rows.size() - 1, -1, -1):
        var layer := layer_at(i)
        if layer != null and filter_at(i) == null and SaLayerStack.parent_of(layer) == null:
            return i
    return rows.size() - 1


## Starts a drag on *idx* without a pointer, for a scenario that wants the mark
## drawn without driving a gesture. The mouse path is `_on_row_gui_input` and
## `_input`, which `layer-row-drag.json` presses.
func begin_drag(idx: int, mask: bool = false) -> void:
    if idx < 0 or idx >= rows.size():
        return
    mask_drag.arm(layer_at(idx) if mask else null)
    _drag_from = idx
    dragging = true
    drag_over(idx, Drop.NONE)


## Moves the mark to *idx*. Cheap enough to call on every motion: it restyles
## the row losing the mark and the row taking it, and nothing else.
func drag_over(idx: int, mode: Drop) -> void:
    mode = _allowed_drop(idx, mode)
    var wanted: int = idx if mode != Drop.NONE and (idx != _drag_from or mode == Drop.REFUSED) else -1
    if wanted == drop_row and mode == drop_mode:
        return
    var previous := drop_row
    drop_row = wanted
    drop_mode = mode if wanted >= 0 else Drop.NONE
    if previous >= 0 and previous < rows.size():
        _update_row_style(previous)
    if drop_row >= 0:
        _update_row_style(drop_row)


## What a drop on row *idx* may be, given which row is being dragged. A mask
## goes inside a row that takes it and is refused by any other. A layer never
## lands on a filter's row. A filter lands above or below a filter of its own node, or
## inside another node through the middle of that node's row, and nowhere else, because
## a filter is never a member of the layer order: the mark does not appear and the drop
## is refused.
func _allowed_drop(idx: int, mode: Drop) -> Drop:
    if mode == Drop.NONE or idx < 0 or idx >= rows.size():
        return mode
    if mask_drag.armed():
        return mask_drag.mode_over(layer_at(idx) if filter_at(idx) == null else null)
    var dragged := filter_at(_drag_from)
    var over := filter_at(idx)
    if dragged == null:
        return Drop.NONE if over != null else mode
    if over != null:
        return mode if over.node == dragged.node else Drop.NONE
    var target := layer_at(idx)
    return Drop.INTO if mode == Drop.INTO and target != null and target != dragged.node else Drop.NONE


## Ends the drag wherever the mark is, which is what the release does and what a
## scenario calls after `drag_over`. A dragged mask is copied with *copy*.
func drop(copy: bool = false) -> void:
    var from := _drag_from
    var to := drop_row
    var mode := drop_mode
    var was_dragging := dragging
    drag_over(-1, Drop.NONE)
    _drag_from = -1
    dragging = false
    var alone := picked.let_go() if not was_dragging else -1
    if alone >= 0:
        item_selected.emit(alone)
    if not was_dragging or from < 0 or to < 0 or mode == Drop.NONE or mask_drag.armed():
        mask_drag.drop(_shown_document(), layer_at(to) if was_dragging and to >= 0 and filter_at(to) == null else null, copy)
        return
    if filter_at(from) != null:
        _drop_filter(filter_at(from), to, mode)
        return
    item_dropped.emit(from, to, mode)


## A filter's row was released where `_allowed_drop` lets one land. Onto a
## filter of its own node it is a reorder, and onto another node's row it is a
## move to that node, on top of what the node already carries. Either is one
## history step, and the document's announcement of it rebuilds the rows. Done
## here rather than reported, the way the eye is, because the docker would need
## the row's own class to read the record off it.
func _drop_filter(dragged: SaFilterRowView, to: int, mode: Drop) -> void:
    var document := _shown_document()
    if document == null or dragged.record == null or not dragged.node_alive():
        return
    var ops := SaFilterOps.new(document)
    var over := filter_at(to)
    if over == null:
        ops.move_to(dragged.node, dragged.record, layer_at(to))
        return
    var list := ops.filters_of(dragged.node)
    ops.reorder(dragged.node, dragged.record, SaFilterListing.index_for(list, dragged.record, over.record, mode == Drop.ABOVE))


func _finish_drag(global_point: Vector2, copy: bool) -> void:
    var row := dragging and filter_at(_drag_from) == null and not mask_drag.armed()
    var tabs := row and SaDocumentTabs.drop_layer(self, layer_at(_drag_from), global_point)
    if dragging:
        _aim_at(Vector2.INF if tabs else global_point)
    drop(copy)


# --- The eye sweep ----------------------------------------------------------


## Arms a visibility sweep from the press that lands on *idx*'s eye. Nothing
## moves until the pointer has travelled `DRAG_THRESHOLD`, the same as the row
## drag: a click that wobbles is still a click, and the plain click a shorter
## travel leaves alone is `_on_eye_pressed`'s own, which the multi-selected set
## follows and this gesture does not.
func _arm_eye(idx: int, at: Vector2) -> void:
    var layer := layer_at(idx)
    if layer == null:
        return
    _eye_armed = idx
    _eye_origin = at
    _eye_dragging = false
    _eye_wanted = not layer.visible
    _eye_touched.clear()
    _eye_previous.clear()
    _eye_last_idx = -1
    set_process_input(true)


func _eye_input(ev: InputEvent) -> void:
    if _eye_armed < 0:
        return
    var motion := ev as InputEventMouseMotion
    if motion != null:
        # Same reasoning as the row drag: a release over another window never
        # reaches this viewport, so a motion with the button already up is
        # what ends the sweep it left behind.
        if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
            _finish_eye()
            return
        if not _eye_dragging and (motion.global_position - _eye_origin).length() >= DRAG_THRESHOLD:
            _eye_dragging = true
            _apply_eye(_eye_armed)
        if _eye_dragging:
            var over := _eye_at(motion.global_position)
            if over >= 0:
                _apply_eye(over)
        return
    var button := ev as InputEventMouseButton
    if button == null or button.button_index != MOUSE_BUTTON_LEFT or button.pressed:
        return
    var was_dragging := _eye_dragging
    _finish_eye()
    # Only a real sweep eats its release, the same rule the row drag keeps: a
    # plain click's release still belongs to the button, which is what fires
    # `_on_eye_pressed` for a click that never crossed the threshold.
    if was_dragging and is_inside_tree():
        get_viewport().set_input_as_handled()


## The row whose eye sits under *global_point*, or -1. Its own walk rather than
## a check inside `row_at`, because a press on the eye is consumed by the
## button before the row's own `gui_input` ever sees it, so the sweep that
## follows has to hit-test the eye rects directly.
func _eye_at(global_point: Vector2) -> int:
    for i in rows.size():
        if rows[i].eye_btn.get_global_rect().has_point(global_point):
            return i
    return -1


## Sets *idx*'s layer to `_eye_wanted`, live, so the eye and the canvas answer
## while the pointer is still moving. Skipped when the layer already reads
## that way, or a sweep back over ground it already covered would record a
## layer as touched a second time for nothing the undo step needs to know.
func _apply_eye(idx: int) -> void:
    if idx < 0 or idx >= rows.size() or idx == _eye_last_idx:
        return
    _eye_last_idx = idx
    var layer := layer_at(idx)
    if layer == null or layer.visible == _eye_wanted:
        return
    var document := _shown_document()
    if document == null:
        return
    _eye_touched.append(layer)
    _eye_previous.append(layer.visible)
    SaLayerEyeWrite.show_now(document, layer, _eye_wanted)
    _update_row_display(idx)


## Ends the sweep and commits every layer it actually changed as one undo
## step when Preferences keeps the eye in the history, its do the value the whole sweep agreed on and its undo each layer's
## own state from before the press, not one shared value: two layers that
## started apart would otherwise land on the same wrong side of an undo.
func _finish_eye() -> void:
    _eye_armed = -1
    _eye_dragging = false
    set_process_input(false)
    if _eye_touched.is_empty():
        return
    var layers := _eye_touched.duplicate()
    var previous := _eye_previous.duplicate()
    var document := _shown_document()
    _eye_touched.clear()
    _eye_previous.clear()
    if document != null:
        SaLayerEyeWrite.commit(document, layers, previous, _eye_wanted)


# --- Drawing and reporting -------------------------------------------------------


func _update_row_style(idx: int) -> void:
    var mode: Drop = drop_mode if idx == drop_row else Drop.NONE
    rows[idx].style(mode)


## The row the pick is on, which is what a rename with no row named means.
func _active_row() -> int:
    for i in rows.size():
        if rows[i].on_the_pick():
            return i
    return -1


func _update_row_display(idx: int) -> void:
    rows[idx].refresh(_shown_document())


## The document the rows describe, or null without a canvas. One place asks the
## canvas, so the handlers below it do not each reach into it.
func _shown_document() -> SaDocument:
    return target_canvas.document if target_canvas != null else null


## What each row is and where its press targets are, for a capture that presses
## one with the mouse. The list answers because only it knows which rows are
## picked. Every row a refresh owed is drawn first, and every sleeping row
## woken, so the report reads what a whole refresh drew.
func row_report() -> Array:
    sleep.wake_all()
    _refreshes.pay_all(self, _shown_document())
    var out: Array = []
    for i in rows.size():
        out.append(rows[i].report())
    return out
