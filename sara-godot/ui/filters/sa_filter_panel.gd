## An attached filter's widgets as a panel, for the tool options docker rather
## than a dialog.
##
## An attached filter's parameters belong in the tool options docker rather
## than in a modal dialog, so the painter keeps painting under them. So this builds the record's filter with [SaDialog] exactly as
## [SaFilterDialogWindow] does and realizes it into itself, and differs in what
## a change does: there is nothing to apply and nothing to cancel. Every settled
## widget change is written back onto the record's parameters through
## `SaFilterOps.set_parameters`, which moves its revision, redraws the canvas
## and makes an Edit Filter step. The first write of a panel is a step of its
## own and every later one folds into it while it is still the latest, so a
## drag is one undo, as a layer's opacity slider is. The edit window's Apply
## makes the same step, so the two doors agree. An undo or a redo that moves
## the record's values moves the widgets with them.
##
## The two rows a dialog has and a panel has no use for are left out by hiding
## them: the Apply and Cancel pair, and the preview, because the canvas is the
## preview of a filter that is attached.
##
## The registry holds one instance per filter, so building a panel rebuilds
## that instance's widgets. One panel at a time is the docker's rule, and it is
## what makes that safe. The one-shot Filter dialog builds its own page on the
## same instance, so a panel on that filter gives way to it through
## [method give_way]: its rows hide behind a line saying where the filter is
## open, it writes nothing while the dialog is up, and it draws its rows again
## from the record once the dialog has gone. A panel built while the dialog is
## already up on its filter starts behind that line and builds no page, since
## a build would point the instance at its rows and the dialog's preview and
## Apply would read the record's values under sliders showing its own.
##
## `SaFilter.set_parameters` is called after `build` and before the controls
## exist, so the values the record keeps are what the controls are drawn from
## and opening a panel announces no change.
class_name SaFilterPanel
extends VBoxContainer

## The node name, which is how a capture and the docker find the panel.
const NODE_NAME := "FilterPanel"

## The widgets of a dialog that a panel leaves out, by the name `SaDialog`
## knows each by.
const LEFT_OUT: Array[String] = ["apply_cancel", "preview", "thumbnail", "canvas_preview"]

## The label column's width in logical pixels. A dialog's is 210, which pushed
## every control past the edge of a docker at its default width, and the tool
## options docker's own 104 wraps "Brightness", because a page's title is bold
## and at the full font size.
const LABEL_WIDTH: int = 124

## The record whose parameters the widgets write, and the filter that built
## them, null when no installed module answers to the record's key.
var record: SaAttachedFilter = null
var filter: SaFilter = null

## The page the filter declared, or null without a filter.
var dialog: SaDialog = null

## How many times a change has been written onto the record.
var writes: int = 0

var _document: SaDocument = null

## The values the widgets were last drawn from or last wrote, which is what
## tells a change made behind the panel's back from its own.
var _shown: Dictionary = {}

## The container the page is realized into, drawn again when the record's
## values move behind the panel's back.
var _rows: VBoxContainer = null

## The one-shot Filter dialog this panel gave the filter's instance to, null
## while the instance's page is the panel's own.
var _lent_to: SaFilterDialogWindow = null

## The line shown in place of the rows while they are lent.
var _lent_note: Label = null


func _init(attached: SaAttachedFilter, its_filter: SaFilter, document: SaDocument) -> void:
    name = NODE_NAME
    record = attached
    filter = its_filter
    _document = document
    size_flags_horizontal = Control.SIZE_EXPAND_FILL

    var heading := Label.new()
    heading.name = "Heading"
    heading.text_overrun_behavior = SaTheme.TEXT_CUT
    add_child(heading)

    if filter == null or record == null:
        heading.text = TranslationServer.translate("No installed module provides this filter.")
        heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        return

    heading.text = SaAttachedFilter.numbered_in(_document, record, filter.title())

    _rows = VBoxContainer.new()
    _rows.name = "Rows"
    _rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    add_child(_rows)
    var holder := dialog_holding(filter)
    if holder != null:
        _lend(holder)
    else:
        _draw_rows()
    if _document != null:
        _document.document_changed.connect(_follow_record)

    # Under the widgets, because it ends the record and they edit it.
    var flatten_button := Button.new()
    flatten_button.name = "FlattenButton"
    flatten_button.text = tr("Flatten", "flatten a filter")
    flatten_button.tooltip_text = tr("Writes this filter into the pixels it is attached over and takes it off, as one step.")
    flatten_button.pressed.connect(flatten)
    add_child(flatten_button)


## Writes what the widgets hold onto the record, when it differs from what the
## record already keeps, as an Edit Filter step. `SaDialog`'s deferred rerun
## calls this, so two widgets moved in one frame are one write, and a suite
## calls `dialog.flush_rerun()` in place of the frame boundary.
##
## The first write opens a step and the later ones fold into it. A fold needs
## the latest step to be an Edit Filter, so a stroke or an undo in between
## starts a new one, and a panel opened on another record starts its own.
func write_back() -> void:
    if filter == null or record == null or _document == null or not is_instance_valid(_document):
        return
    # The instance's store answers the dialog's controls now, not these rows.
    if _lent_to != null:
        return
    var values := filter.parameters()
    if values == record.parameters:
        return
    var merge := UndoRedo.MERGE_ENDS if writes > 0 else UndoRedo.MERGE_DISABLE
    # Before the write, because the write redraws and the redraw is what
    # `_follow_record` listens to.
    _shown = values.duplicate(true)
    if SaFilterOps.new(_document).set_parameters(record, values, merge):
        writes += 1


## Builds the filter's page into the rows, drawn from the values the record
## keeps. `realize` empties the rows first, so a second call replaces the
## first page.
func _draw_rows() -> void:
    if dialog != null:
        dialog.rerun.disconnect(write_back)
    dialog = SaDialog.for_filter(filter)
    filter.set_parameters(record.parameters)
    _shown = record.parameters.duplicate(true)
    dialog.realize(_rows)
    for declared: SaPageRow in dialog.rows():
        if declared.line == null:
            continue
        if LEFT_OUT.has(dialog.widget_name(declared.key)):
            declared.line.visible = false
        elif declared.line.get_child_count() > 0:
            (declared.line.get_child(0) as Control).custom_minimum_size.x = SaUI.px(LABEL_WIDTH)
    dialog.rerun.connect(write_back)


## Draws the widgets again from the record when something other than this
## panel moved its values, an undo or a redo of an Edit Filter step above all,
## so the sliders read what the canvas shows. A change still waiting for its
## rerun is the hand's and is left to land.
##
## Compared with what the widgets were last given and not with
## `filter.parameters()`, because the registry's one instance is what the
## compositor evaluates every record through, and the redraw that follows an
## undo has already handed it the record's values by the time this runs.
## Drawn again rather than `dialog.refresh()`, because a module's own row, the
## adjust filters' slider among them, holds no value the page can push, so the
## first run of the scenario put the record back at 21 under a slider at -53.
func _follow_record() -> void:
    if filter == null or record == null or dialog == null or dialog.rerun_pending or _lent_to != null:
        return
    if has_node("Heading"):
        (get_node("Heading") as Label).text = SaAttachedFilter.numbered_in(_document, record, filter.title())
    if record.parameters == _shown:
        return
    _draw_rows()


## What the one-shot Filter *window* calls before it builds its page on
## *its_filter*, the registry's one instance of it. Every panel on that filter
## lends it its rows, and the edit window, when it is up on that filter, is
## settled as Apply settles it and closes, since its page is one widget set too
## and two live sets write each other's values.
##
## Settled and not cancelled, for the reason `SaFilterEditWindow.give_way`
## gives. The panel stays, because it is where the painter keeps the record's
## widgets for as long as its row is picked, and closing it would change the
## docker under a dialog opened on another layer.
static func give_way(window: SaFilterDialogWindow, its_filter: SaFilter) -> void:
    if window == null or its_filter == null or not window.is_inside_tree():
        return
    var tree := window.get_tree()
    for node in tree.root.find_children(NODE_NAME, "", true, false):
        var panel := node as SaFilterPanel
        if panel != null and panel.filter == its_filter:
            panel._lend(window)
    var editor := SaFilterEditWindow.find_in(tree)
    if editor != null and editor.filter == its_filter:
        editor.give_way()


## The one-shot Filter dialog when it is up on *its_filter*, or null. What a
## panel or the edit window asks before it builds a page on the instance, since
## either can be built under the dialog, which is not exclusive. The main
## loop's tree rather than the node's, because the docker builds a panel
## before it adds it.
static func dialog_holding(its_filter: SaFilter) -> SaFilterDialogWindow:
    var window := SaFilterDialogWindow.find_in(Engine.get_main_loop() as SceneTree)
    if its_filter == null or window == null or not window.visible or window.filter != its_filter:
        return null
    return window


## Hands the filter's instance to *window*: a change still waiting for its
## rerun lands first, since it was made on the panel's own page, then the rows
## hide behind a line and the panel waits for the window to close.
func _lend(window: SaFilterDialogWindow) -> void:
    if _lent_to == window or _rows == null:
        return
    if dialog != null:
        dialog.flush_rerun()
    _lent_to = window
    window.visibility_changed.connect(_follow_lender)
    _rows.visible = false
    _lent_note = Label.new()
    _lent_note.name = "LentNote"
    _lent_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    var sentence := tr("%s is open in the Filter dialog. Its values come back here when that closes.")
    _lent_note.text = sentence % filter.translated_title()
    add_child(_lent_note)
    move_child(_lent_note, _rows.get_index() + 1)


## Takes the instance back once the window is gone or holds another filter, and
## draws the rows from the record, which the dialog never wrote, so the next
## move of a row starts from what the record keeps.
##
## Heard on the window's every show and hide, the popup that opens it among
## them, which is why the window's own state is asked rather than the signal.
func _follow_lender() -> void:
    if _lent_to == null:
        return
    if is_instance_valid(_lent_to) and _lent_to.visible and _lent_to.filter == filter:
        return
    if is_instance_valid(_lent_to):
        _lent_to.visibility_changed.disconnect(_follow_lender)
    _lent_to = null
    if _lent_note != null:
        remove_child(_lent_note)
        _lent_note.queue_free()
        _lent_note = null
    _rows.visible = true
    if record != null and filter != null:
        _draw_rows()


## Writes the record into the pixels under it and takes it off, as one history
## step. A record on a layer goes at once, because what it writes is that
## layer's pixels and one undo brings them back. A record on a group or on the
## root writes into every layer under it, so the painter is told so in one
## sentence first, and a cancel says what was not done.
func flatten() -> void:
    if record == null or _document == null or not is_instance_valid(_document):
        return
    var ops := SaFilterOps.new(_document)
    var node := ops.node_of(record)
    if node == null and not ops.filters_of(null).has(record):
        return
    if node != null and not node.is_group:
        ops.flatten(node, record)
        return
    var sentence := ops.flatten_sentence(node, record)
    var host: Node = get_tree().current_scene if is_inside_tree() and get_tree().current_scene != null else self
    SaMessage.confirm(
        host,
        tr("Flatten Filter"),
        sentence,
        PackedStringArray([tr("Cancel"), tr("Flatten", "flatten a filter")]),
        _on_flatten_answered.bind(node, sentence),
        0,
        1
    )


## The answer to the question above: 1 is Flatten, and everything else,
## Escape included, is Cancel.
func _on_flatten_answered(index: int, node: SaLayer, sentence: String) -> void:
    if index != 1:
        SaProblems.refuse("Flatten Filter", tr("Cancelled. Nothing was changed. %s") % sentence)
        return
    if _document != null and is_instance_valid(_document):
        SaFilterOps.new(_document).flatten(node, record)


## What the panel is, for the state dump. The widgets themselves are already
## there, because `SaPage.capture_state` finds any container a page was
## realized into.
func describe() -> Dictionary:
    return {
        "filter": String(record.key) if record != null else "",
        "title": (get_node("Heading") as Label).text,
        "provided": filter != null,
        "parameters": record.parameters if record != null else {},
        "revision": record.revision if record != null else 0,
        "writes": writes,
        "lent": _lent_to != null,
    }
