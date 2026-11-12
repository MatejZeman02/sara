## The window a double click on an attached filter's row opens.
##
## A double click on an attached filter opens its values to edit. A single click already shows
## the record's widgets in the tool options docker, which is [SaFilterPanel] and
## is what keeps the canvas visible under them. This is the row's other door:
## the same widgets in a window of their own, opened on the values the record
## holds, where a change previews live and one Apply lands as one step.
##
## The panel's shape with a dialog's two answers. The panel writes every settled
## widget change onto the record as an Edit Filter step, a drag folding into
## one. Here the same write is the preview and makes no step, Cancel puts back
## the values the window opened with, and Apply commits the pair, the opened
## values and the held ones, as one Edit Filter step through
## `SaFilterOps.set_parameters`, the door the panel writes through too.
##
## The preview row a dialog declares is hidden, for the panel's reason: the
## canvas is the preview of a filter that is attached.
##
## **The panel and this window cannot both be up on one filter.** The registry
## holds one instance per filter and a build gives it the rows of the last
## build, so two live sets of widgets would write each other's values. The row's
## own door takes the panel's pick back before it opens this.
##
## The one-shot Filter dialog builds on the same instance, so this window gives
## way to it when it opens, and opened while the dialog is up on its filter it
## builds no page: it shows a line saying where the filter is open, and builds
## its page from the record once the dialog has closed.
@tool
class_name SaFilterEditWindow
extends SaDialogWindow

## The node name, which is how a capture and the tests find the window.
const NODE_NAME := "FilterEdit"

## The widgets of a dialog this window has no use for, by the name `SaDialog`
## knows each by.
const LEFT_OUT: Array[String] = ["preview", "thumbnail", "canvas_preview"]

## The record being edited and the document it hangs in.
var record: SaAttachedFilter = null
var _document: SaDocument = null

## The filter's page, which is the panel's and the one-shot dialog's page too,
## and the filter that built it. Null when no installed module answers the
## record's key, and then nothing is editable and nothing is drawn but a line
## saying so.
var dialog: SaDialog = null
var filter: SaFilter = null

## How many times a settled widget change has been written onto the record.
var writes: int = 0

## The record's values when the window opened, which is what Cancel restores and
## what Apply's undo side holds.
var _opened_with: Dictionary = {}

## The layer the record came in on when the window was opened straight after
## adding it, and where the history stood just after that add. Cancel takes
## the add back while it is still the latest step.
var _fresh: SaLayer = null
var _fresh_at: int = -1

## The Affect all check, pinned over Apply when the record is an adjustment
## layer's own: a tick turns `SaLayer.affects_all` on that
## layer as one step of its own at once, the way a row's padlock does, and
## Cancel leaves it. Null for any other record.
var affect_all: CheckBox = null

var _registry: SaFilterRegistry = null
## The scrolled page and its pinned Apply row.
var _frame: SaFilterDialogFrame = null

## The one-shot Filter dialog this window waits behind, null while its page is
## built or no record is open.
var _waits_on: SaFilterDialogWindow = null


func _init() -> void:
    _init_dialog(NODE_NAME, tr("Filter"), SaFilterDialogFrame.OPENING_SIZE, SaFilterDialogFrame.FLOOR)
    # A Window is visible the moment it joins the tree, and this one is
    # installed at boot: without this it would sit blank over the top left of
    # the canvas from the first frame.
    visible = false
    # The × and Escape put the opening values back as Cancel does.
    close_requested.connect(cancel)
    # Enter in a slider's field takes the number and writes it onto the record
    # as every other change does, and Apply waits for its own press, for the
    # reason `SaFilterDialogWindow._init` gives.
    number_field_answers = false

    _frame = SaFilterDialogFrame.new()
    content.add_child(_frame)
    scrolling_body = _frame.scroll


## Puts one of these under *host* and points it at the filter registry.
##
## The shape [method SaFilterDialogWindow.install] has, and called from the same
## line of `Main`'s boot.
static func install(host: Node) -> void:
    if host == null:
        return
    var found := host.get_node_or_null(NodePath(NODE_NAME)) as SaFilterEditWindow
    if found == null:
        found = SaFilterEditWindow.new()
        host.add_child(found)
    var registries := host.get("registries") as SaRegistries
    if registries != null:
        found.watch(registries.filters)


## The window under the current scene, or null. What the capture step and the
## tests reach it by.
static func find_in(tree: SceneTree) -> SaFilterEditWindow:
    if tree == null:
        return null
    for node in tree.root.find_children(NODE_NAME, "Window", true, false):
        var window := node as SaFilterEditWindow
        if window != null:
            return window
    return null


## Opens the window on *attached*, wherever it hangs, and answers whether it
## opened. What the row's double click calls, and the layer kind browser with
## the layer it has just added as *fresh*.
static func open_in(tree: SceneTree, in_document: SaDocument, attached: SaAttachedFilter, fresh: SaLayer = null) -> bool:
    var window := find_in(tree)
    if window == null:
        return false
    window.open(attached, in_document, fresh)
    return true


## Where the filters are asked for by key from now on.
func watch(registry: SaFilterRegistry) -> void:
    _registry = registry


## Builds the record's page and shows the window on the values it holds.
##
## `SaFilter.set_parameters` is called after `build` and before the controls
## exist, so the values the record keeps are what the controls are drawn from
## and opening the window announces no change.
##
## *fresh* is the layer the record was just added on, and Cancel answers the
## add as well, rather than leave an empty adjustment layer behind. The add is
## committed first and taken back, rather than held until Apply, because the
## window is not modal and an undo while it is up would meet a layer no step
## had put in.
func open(attached: SaAttachedFilter, in_document: SaDocument, fresh: SaLayer = null) -> void:
    _settle()
    _close(false)
    if attached == null or in_document == null:
        return
    record = attached
    _document = in_document
    _opened_with = record.parameters.duplicate(true)
    if fresh != null and in_document.history != null:
        _fresh = fresh
        _fresh_at = in_document.history.position()
    filter = _registry.get_filter(record.key) if _registry != null else null

    if filter == null:
        # The one heading the window draws itself, since no page is realized
        # over it. A found filter's heading is the drag bar's, and a label put
        # in the rows before `show_page` is freed by it.
        var sentence := Label.new()
        sentence.name = "Heading"
        sentence.text_overrun_behavior = SaTheme.TEXT_CUT
        sentence.text = tr("No installed module provides this filter.")
        sentence.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        _frame.rows.add_child(sentence)
        retitle(tr("Filter"))
        _show()
        return

    retitle(_named_where(filter.title()))
    var holder := SaFilterPanel.dialog_holding(filter)
    if holder != null:
        _wait_behind(holder)
    else:
        _draw_page()
    _show()


## Builds the record's page into the frame, drawn from the values the record
## keeps.
func _draw_page() -> void:
    dialog = SaDialog.for_filter(filter)
    filter.set_parameters(record.parameters)
    _frame.show_page(dialog)
    _pin_affect_all()
    for declared: SaPageRow in dialog.rows():
        if declared.line != null and LEFT_OUT.has(dialog.widget_name(declared.key)):
            declared.line.visible = false
    dialog.rerun.connect(write_back)
    dialog.applied.connect(accept)
    dialog.cancelled.connect(cancel)
    default_button = dialog.apply_button


## Shows a line in place of the page while *window*, the one-shot Filter
## dialog, holds the filter's instance, and waits for it to close. The record
## is untouched until then, so Cancel or the × has nothing to put back.
func _wait_behind(window: SaFilterDialogWindow) -> void:
    _waits_on = window
    window.visibility_changed.connect(_follow_holder)
    var sentence := Label.new()
    sentence.name = "WaitNote"
    sentence.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    var said := tr("%s is open in the Filter dialog. Its values come back here when that closes.")
    sentence.text = said % filter.translated_title()
    _frame.rows.add_child(sentence)


## Builds the page once the dialog is gone or holds another filter. Heard on
## the dialog's every show and hide, which is why its own state is asked
## rather than the signal, for the reason `SaFilterPanel._follow_lender` gives.
func _follow_holder() -> void:
    if _waits_on == null or SaFilterPanel.dialog_holding(filter) == _waits_on:
        return
    _stop_waiting()
    if filter == null or record == null:
        return
    _frame.clear()
    _draw_page()
    _fit_next_frame()


func _stop_waiting() -> void:
    if _waits_on != null and is_instance_valid(_waits_on):
        _waits_on.visibility_changed.disconnect(_follow_holder)
    _waits_on = null


## Pins the Affect all check over Apply when the record is the own record of
## an adjustment layer, the one its row stands for, ticked as the layer is.
func _pin_affect_all() -> void:
    var holder := SaAttachedFilter.holder_in(_document, record) as SaLayer
    if holder == null or SaBackdropLayer.own_filter(holder) != record:
        return
    affect_all = SaMake.check_box(null, "AffectAll", tr("Affect all"), holder.affects_all)
    affect_all.tooltip_text = tr("Adjusts the whole picture from wherever the layer sits, and hides with its group.")
    affect_all.toggled.connect(_toggle_affect_all.bind(holder))
    _frame.pin_over_buttons(affect_all)


## The check's tick, *on*, written onto *layer* as one step. A step that
## changes nothing, a layer gone from the document, sets the box back.
func _toggle_affect_all(on: bool, layer: SaLayer) -> void:
    if not is_instance_valid(layer) or not SaBackdropLayer.affect_all(_document, layer, on):
        if affect_all != null:
            affect_all.set_pressed_no_signal(is_instance_valid(layer) and layer.affects_all)


## What the title and the heading read for the record being opened: the filter's
## *filter_title*, numbered the way its row is, and the node it hangs under, so
## "Gaussian Blur 2 on Swamp", or "Gaussian Blur on the whole picture" for a
## record on the document's root. A record that hangs nowhere reads the title
## alone. There is no preview strip to say it instead, for the reason `LEFT_OUT`
## gives.
func _named_where(filter_title: String) -> String:
    var numbered := SaAttachedFilter.numbered_in(_document, record, filter_title)
    var holder := SaAttachedFilter.holder_in(_document, record)
    if holder == _document:
        return tr("%s on the whole picture") % numbered
    if holder != null:
        return tr("%s on %s") % [numbered, holder.name]
    return numbered


## Shows the window at the size it was built with, centred when it has a tree
## to be centred in, so the fit on the next frame grows it to this record's page
## and to no page before it, for the reasons
## `SaFilterDialogWindow._reopen_at_opening_size` gives, the floor first.
##
## A window built offscreen, which is how a suite holds one, has neither a
## parent nor a screen, and `popup_centered` asks the tree for one exactly as
## `popup` does. The guard is here rather than in the suite for the reason
## `SaChoicePopup.open_under` carries one.
func _show() -> void:
    var was_open := visible
    logical_size = SaFilterDialogFrame.OPENING_SIZE
    logical_min_size = SaFilterDialogFrame.FLOOR
    if not is_inside_tree():
        visible = true
        return
    min_size = SaUI.window_size_for(self, logical_min_size)
    apply_window_scale()
    popup_centered()
    if was_open:
        _fit_next_frame()


## Writes what the widgets hold onto the record, when it differs from what the
## record already keeps. `SaDialog`'s deferred rerun calls this, so two widgets
## moved in one frame are one write, and the repaint that follows is the whole
## of the preview: the compositor reads the record on the next frame.
func write_back() -> void:
    if filter == null or record == null:
        return
    var values := filter.parameters()
    if values == record.parameters:
        return
    writes += 1
    _write(values)


## Apply: one history step over the values the window opened with, and the
## window closes. The live writes already left the record holding them, so the
## step repeats what is there and only its undo side changes anything, which is
## what `SaHistory.commit_pair` asks of a caller that has already applied.
func accept() -> void:
    if filter != null and record != null and _document != null:
        _commit_held(false)
    _close(true)


## The one Edit Filter step over the values the window opened with, which Apply
## always makes and the settle before another record only when they *changed*.
func _commit_held(only_changed: bool) -> void:
    var held := record.parameters
    if only_changed and held == _opened_with:
        return
    SaFilterOps.new(_document).set_parameters(record, held, UndoRedo.MERGE_DISABLE, _opened_with)


## What the window does with the record it holds when it is opened on another,
## which a double click on a second filter's row does while it is up, since it
## is not modal. It settles as Apply does: a live edit the painter made and
## saw on the canvas stays, as the one Edit Filter step Apply would have made,
## so Ctrl+Z takes it back. Cancel's way would throw away a change the painter
## never asked to lose, with no step to bring it back. A widget moved this
## frame has its write still deferred, so it is flushed first. A record that
## nothing moved makes no step, and a fresh layer's add stays, because it is
## already a step of its own.
func _settle() -> void:
    if dialog != null:
        dialog.flush_rerun()
    if filter != null and record != null and is_instance_valid(_document):
        _commit_held(true)


## What the window does when the one-shot Filter dialog opens on its filter,
## the registry's one instance, through [method SaFilterPanel.give_way]. Two
## live pages on one instance write each other's values, so this one settles
## and closes before the dialog builds. It settles as Apply does and as an open
## on another record does: a live edit the painter saw on the canvas stays as
## one Edit Filter step Ctrl+Z takes back, where Cancel's way would throw it
## away with no step to bring it back.
##
## A window already waiting behind the dialog holds no page and keeps waiting.
func give_way() -> void:
    if _waits_on != null:
        return
    _settle()
    _close(true)


## Cancel: the values the window opened with go back on the record, through the
## same write a widget change makes, and no step is made because the document
## ends where it started.
##
## On a fresh layer the add is undone too, through the document's history,
## when it is still the latest step, so the layer list is as it was and a redo
## brings back the layer as it was added. A step the painter took while the
## window was up keeps the layer, because undoing past it would take that.
func cancel() -> void:
    if filter != null and record != null and record.parameters != _opened_with:
        _write(_opened_with)
    if _fresh != null and is_instance_valid(_document) and _document.history.position() == _fresh_at:
        _document.undo()
    _close(true)


## What the window is, for the state dump. The page half is already in the dump:
## `SaPage.capture_state` finds any container a page was realized into.
func describe() -> Dictionary:
    var all_pressed: Variant = null
    if affect_all != null:
        all_pressed = affect_all.button_pressed
    return {
        "open": visible,
        "title": title,
        "filter": String(record.key) if record != null else "",
        "provided": filter != null,
        "parameters": record.parameters if record != null else {},
        "opened_with": _opened_with,
        "writes": writes,
        "fresh": String(_fresh.name) if _fresh != null and is_instance_valid(_fresh) else "",
        "affect_all": all_pressed,
        "waiting": _waits_on != null,
    }


## Names the window, in the OS title and in the drag bar both.
##
## `SaDialogWindow` writes the drag bar's label once, from the title it was
## constructed with, and this window serves every attached record and so every
## filter. So the label is written again rather than the window rebuilt, which
## is what `SaFilterDialogWindow` does for the same reason.
func retitle(text: String) -> void:
    title = text
    var label := drag_handle.find_child("TitleLabel", true, false) as Label if drag_handle != null else null
    if label != null:
        label.text = text


## Drives the filter edit window: `{"filter_edit": {"open": {"layer": "Sky",
## "index": 0}}}` opens the window on that node's record, `{"layer": ""}` naming
## the document's root, and `"index"` the record's place among that node's
## filters. `{"widget": "radius", "value": 6}` moves one of its rows the way a
## hand would, `"apply"`, `"cancel"` and `"flush"` press the two buttons and the
## frame boundary, and `"describe"` prints what the window says it is.
## `"press_apply"` and `"press_cancel"` raise the button's own `pressed`, as a
## hand's click does, the path that would free the button inside its signal.
## `{"retitle": "A very long name"}` writes the heading a filter of that name
## would, since no installed filter is named that long.
##
## A step of its own because this window is an embedded subwindow and an
## injected click does not route into one, which is the same reason
## `sa_preferences_driver.gd` and `SaFilterDialogWindow.capture` exist.
static func capture(tree: SceneTree, spec: Variant) -> String:
    var window := find_in(tree)
    if window == null:
        return "SaCapture: no filter editor installed"
    var options: Dictionary = spec if spec is Dictionary else {"do": String(spec)}
    if options.has("open"):
        var document := _document_of(tree)
        var attached := _record_in(document, options["open"] as Dictionary)
        if attached == null:
            return "SaCapture: no attached filter to open for %s" % JSON.stringify(options["open"])
        window.open(attached, document)
        return "SaCapture: filter editor opened on '%s', %s" % [attached.key, JSON.stringify(window.describe())]
    if String(options.get("do", "")) == "describe":
        return "SaCapture: filter editor is %s" % JSON.stringify(window.describe())
    if window.dialog == null:
        return "SaCapture: no filter editor open"
    if options.has("retitle"):
        window.retitle(String(options["retitle"]))
        return "SaCapture: filter editor headed '%s'" % window.title
    if options.has("widget"):
        return window._move_widgets([options])
    # A list, because a capture runs one step a frame and the rerun is deferred
    # to the end of one: two widgets in two steps are two frames and two writes,
    # and only two widgets in the same step are the case the coalescing is for.
    if options.has("widgets"):
        return window._move_widgets(options["widgets"] as Array)
    match String(options.get("do", "")):
        "apply":
            window.accept()
            return "SaCapture: filter editor applied"
        "cancel":
            window.cancel()
            return "SaCapture: filter editor cancelled"
        "press_apply", "press_cancel":
            var button := window.dialog.apply_button if options["do"] == "press_apply" else window.dialog.cancel_button
            var named := button.text
            button.pressed.emit()
            return "SaCapture: filter editor's %s pressed, %s" % [named, JSON.stringify(window.describe())]
        "flush":
            window.dialog.flush_rerun()
            return "SaCapture: rerun flushed, %s" % JSON.stringify(window.describe())
    return "SaCapture: no filter editor command %s" % JSON.stringify(spec)


## Moves every widget in *moves*, in this frame, and says how many writes the
## window has made. Nothing is flushed here, for the reason
## `SaFilterDialogWindow._move_widgets` gives: the rerun is the dialog's own
## deferred call and lands when this frame's work is done.
func _move_widgets(moves: Array) -> String:
    var said: Array = []
    for move: Variant in moves:
        var one: Dictionary = move as Dictionary
        var named := String(one.get("widget", ""))
        var row := dialog.row(StringName(named))
        if row == null:
            return "SaCapture: the editor has no widget '%s'" % named
        said.append(_drive(row, one))
    return (
        "SaCapture: moved %s, writes so far %d, rerun pending %s"
        % [", ".join(PackedStringArray(said)), writes, dialog.rerun_pending]
    )


## Moves one widget and answers what to say about it.
##
## A `CUSTOM` row is handed the step's own words through `capture_option_edit`
## on its control, so a widget the skeleton knows nothing about is driven by the
## one method its author wrote rather than by a branch here. Every other kind
## moves through the signal its control raises, for the reason `SaPageRow.drive`
## gives: half of Godot's controls do not raise one for a script's assignment,
## and a `Range` raises its a frame later or not at all.
static func _drive(row: SaPageRow, one: Dictionary) -> String:
    var named := String(one.get("widget", ""))
    if row.kind == SaPageRow.Kind.CUSTOM:
        var custom := row.control
        if custom != null and is_instance_valid(custom) and custom.has_method("capture_option_edit"):
            var handed := one.duplicate()
            handed.erase("widget")
            return String(custom.call("capture_option_edit", handed))
    var value: Variant = one.get("value", null)
    var slider := row.control as FactorSlider
    if slider != null:
        slider.value = float(value)
        slider.value_changed.emit(slider.value)
    else:
        row.drive(value)
    return "%s -> %s" % [named, row.value]


## The record the capture's `open` names, on the node of that name or on the
## document's root without one.
static func _record_in(document: SaDocument, spec: Dictionary) -> SaAttachedFilter:
    if document == null:
        return null
    var wanted := String(spec.get("layer", ""))
    var list: Array[SaAttachedFilter] = document.root_filters
    if not wanted.is_empty():
        var node := document.get_node_or_null(NodePath(wanted)) as SaLayer
        if node == null:
            return null
        list = node.filters
    var index := int(spec.get("index", 0))
    return list[index] if index >= 0 and index < list.size() else null


## The front document, which is what a scenario's `open` is read against.
static func _document_of(tree: SceneTree) -> SaDocument:
    var canvas := SaCanvasView.front_canvas() if tree != null else null
    return canvas.document if canvas != null else null


## *values* onto the record with no step, through the write an Edit Filter
## step makes, which redraws the record's node and folds again only the caches
## that baked it.
func _write(values: Dictionary) -> void:
    if _document == null or not is_instance_valid(_document):
        record.replace_parameters(values)
        return
    SaFilterOps.new(_document).write(record, values)


## Empties the rows and forgets the record. `SaFilterDialogFrame.clear` frees
## them at once outside the tree, for the reason `SaFilterBrowser.refresh`
## gives, and queues them in it, where the close runs inside the pressed
## button's own signal.
func _close(hide_window: bool) -> void:
    _stop_waiting()
    if dialog != null:
        dialog.rerun.disconnect(write_back)
        dialog.applied.disconnect(accept)
        dialog.cancelled.disconnect(cancel)
    dialog = null
    filter = null
    record = null
    _document = null
    _opened_with = {}
    _fresh = null
    _fresh_at = -1
    writes = 0
    default_button = null
    affect_all = null
    _frame.clear()
    if hide_window:
        hide()
