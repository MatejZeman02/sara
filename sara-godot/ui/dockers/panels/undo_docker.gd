## The Undo History docker: the steps the document can go back through, oldest
## at the top, with the one it is standing on marked.
##
## **The word History belongs to this** and not to the trail of brush presets,
## which is called Recent Presets, so a painter who opens History from the
## Dockers menu gets the undo stack and not a list of presets. The Info
## docker's section and the `history` block of every dump are the undo stack
## too, and this is the one a painter can open.
##
## **Oldest at the top**, which is the opposite of the preset trail beside it and
## is deliberate. A trail of visits has no order but recency, so its newest entry
## is its answer. A stack of steps is a timeline, and a timeline read downwards
## is what Krita and Photoshop both draw, so a painter who has used either
## already knows which way the arrow of time points here.
##
## **A row is clickable, and clicking it goes there.** The alternative, a list
## that only reports, was considered and is the smaller half of what a painter
## opening this expects: Ctrl+Z already reports by doing, and a window that only
## says what Ctrl+Z would do is a window nobody opens twice. Going there is
## `SaDocument.undo()` and `redo()` called until the stack is where the row is,
## which is the same door the Edit menu and the shortcut router use, so nothing
## here reaches into `UndoRedo` to move it.
##
## **A step with no name reads "Step N"**, N being its place in the stack. Every
## step Sara commits through `SaHistory.commit` carries a name, so this is for a
## step something else pushed, and a blank row a painter cannot tell from the
## blank row above it is worse than a numbered one.
##
## Nothing here is stored. The undo stack is the document's and dies with it, so
## a docker over it has no file beside `docker_layout.cfg` and nothing to
## migrate.
##
## **The footer says how many steps the budget has taken**, a number nothing
## else here shows. It is a line rather than a row,
## because it is not a step and cannot be clicked to, and it stands for as long
## as the count is above zero rather than arriving once per dropped step.
@tool
extends DockerWindow

class_name UndoDocker

## What the docker opens at. Narrow and tall, because a row is one name, and
## taller than the preset trail because a stack is longer than twenty visits.
const DEFAULT_SIZE := Vector2i(240, 340)

## The row standing for the document before anything was done to it, which is
## where clicking undoes everything. It is a real place in the stack rather than
## a label: `UndoRedo` counts actions and `-1` is "none of them done".
const BASE_STEP: int = -1

## What a step with no name of its own is called, numbered from one so it reads
## as a painter counts rather than as an array is indexed.
const UNNAMED := "Step %d"

var rows: VBoxContainer = null
var empty_label: Label = null

## The list's scroll, which a rebuild brings to the row the stack is standing on.
var scroll: ScrollContainer = null

## The row a rebuild asked to be brought into view, or null once it is.
var _row_to_show: Button = null

## The process frame of the last rebuild or show, which the scroll waits past. A
## row built this frame, or shown with its window this frame, has no place in its
## column until the containers sort at the end of the frame, which the engine's
## own documentation on `ensure_control_visible` says too, and a scroll asked of it then
## goes to the top of an unsorted list.
var _show_after: int = -1

## The line under the rows that says how many steps the memory budget has taken.
## Hidden until a step is actually dropped.
##
## A full undo stack throws no pop-up in the corner, one line per dropped step.
## This docker is where a painter looks when a row they remember
## is missing, so the count lives on its frame and stands there rather than
## arriving once per drop, and it names the setting because the setting is the
## painter's next move.
var dropped_label: Label = null

## The version the rows were built for, so a poll that finds nothing changed
## costs one integer comparison. `UndoRedo.get_version()` moves on every commit,
## undo and redo, which is exactly when a row has to move.
var _seen_version: int = -1
var _seen_count: int = -1

## The drop count the footer was built for, for the same reason. Kept apart from
## the pair above because a drop is what the footer says and not what the rows
## hold.
var _seen_dropped: int = -1

## The stack the rows were last built from, so a second document brought
## forward at the same version and count still rebuilds them.
var _seen_stack: WeakRef = null


func _init() -> void:
    _init_docker(SaDockerIds.UNDO, "Undo History", DEFAULT_SIZE, Vector2i(150, 140))
    # Where a fresh profile finds it: beside Recent Presets, which the shipped
    # layout puts at (900, 680) and 300 wide, so the two lists of what has
    # happened stand together, and its whole frame inside a 1920 by 1080 window.
    # The default layout's section says the same place, and this is where a
    # first tick in the Window menu opens it under a layout with no section for
    # it. It was (2, 1000), the foot of the window, where a docker 340 tall
    # showed its title and nothing under it.
    position = Vector2i(1200, 680)

    var vbox := SaMake.column(_control_node, "VBoxContainer")
    vbox.set_anchors_preset(Control.PRESET_FULL_RECT)

    drag_handle = DockerUtils.make_drag_bar("Undo History")
    vbox.add_child(drag_handle)

    var margin := SaMake.margin(vbox, "MarginContainer", SaUI.BASE_MARGIN)
    margin.size_flags_vertical = Control.SIZE_EXPAND_FILL

    scroll = SaMake.scroll(margin, "Scroll")
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED

    rows = SaMake.column(scroll, "Rows", 2)
    rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL

    empty_label = SaMake.label(rows, "EmptyState", tr("Nothing to undo yet."))
    empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

    # The footer, under the scroll so it never scrolls away with the rows. Built
    # in `_init` with the rest of the frame, and hidden until a drop says
    # otherwise, so an untouched docker is the docker it always was.
    dropped_label = SaMake.label(vbox, "Dropped")
    dropped_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    dropped_label.visible = false
    SaTheme.bind_font(dropped_label, "text_muted")

    visibility_changed.connect(func() -> void: _show_after = Engine.get_process_frames())


func _ready() -> void:
    _setup_docker_ready()
    if not SaSettings.profile_changed.is_connected(apply_layout_settings):
        SaSettings.profile_changed.connect(apply_layout_settings)
    apply_layout_settings()
    refresh()


func apply_layout_settings() -> void:
    apply_docker_base_layout(SaDockerIds.UNDO)


## Polls the stack's own version rather than following a signal, for the reason
## the Info docker and the Graph docker poll: the document is replaced under a
## docker by File > New and by File > Open, and one integer comparison a frame
## is cheaper than following that with signals from a document that may not
## exist yet.
func _process(_delta: float) -> void:
    # A docker is a Window rather than a Control, so `visible` is the whole
    # question and there is no is_visible_in_tree to ask.
    if not visible or not is_inside_tree():
        return
    if Engine.get_process_frames() > _show_after:
        show_current_row()
    refresh()


## Rebuilds the rows when the stack has moved, and does nothing when it has not.
## Public because a capture and a test want the list without waiting for a frame.
func refresh() -> void:
    var undo_redo := _undo_redo()
    if undo_redo == null:
        if _seen_count != 0:
            _seen_count = 0
            _seen_version = -1
            _seen_dropped = -1
            _rebuild([], BASE_STEP)
            _show_dropped(0)
        return
    var dropped := _document().history.dropped_steps
    var version := undo_redo.get_version()
    var count := undo_redo.get_history_count()
    var same: bool = _seen_stack != null and undo_redo == _seen_stack.get_ref()
    if same and version == _seen_version and count == _seen_count and dropped == _seen_dropped:
        return
    _seen_stack = weakref(undo_redo)
    _seen_version = version
    _seen_count = count
    _seen_dropped = dropped
    _rebuild(step_names(), current_step())
    _show_dropped(dropped)


## What each step in the stack is called, oldest first. Public so a capture reads
## the words rather than counting buttons in a picture.
func step_names() -> Array[String]:
    var named: Array[String] = []
    var undo_redo := _undo_redo()
    if undo_redo == null:
        return named
    for index in undo_redo.get_history_count():
        var action_name := undo_redo.get_action_name(index)
        named.append(action_name if not action_name.is_empty() else UNNAMED % (index + 1))
    return named


## Where the stack is standing: the index of the last step that has been done,
## and [constant BASE_STEP] when none has. Public for the same reason.
func current_step() -> int:
    var undo_redo := _undo_redo()
    if undo_redo == null:
        return BASE_STEP
    # `get_current_action` answers the action that *would be undone*, which is
    # the one already done, and -1 when there is nothing to undo. That is
    # BASE_STEP by construction rather than by a translation.
    return undo_redo.get_current_action()


## The footer line, and the whole of what the docker says about a history the
## budget has shortened.
##
## The count stands rather than arriving once per dropped step, because a
## painter who has just lost their fourth step needs the number, not four
## lines. It names the setting
## because the setting is the painter's next move.
func _show_dropped(count: int) -> void:
    if dropped_label == null:
        return
    dropped_label.visible = count > 0
    if count <= 0:
        dropped_label.text = ""
        return
    dropped_label.text = (
        tr("One step was dropped. Preferences > Interface sets how deep it goes.")
        if count == 1
        else (
            tr_n(
                "%d step was dropped. Preferences > Interface sets how deep it goes.",
                "%d steps were dropped. Preferences > Interface sets how deep it goes.",
                count
            )
            % count
        )
    )


## What the footer says, and the empty string while it is not showing. Public for
## the same reason `row_texts` is: a capture and a suite read the words rather
## than grading a picture of them.
func dropped_line() -> String:
    if dropped_label == null or not dropped_label.visible:
        return ""
    return dropped_label.text


## Takes the document to the state after step *index*, [constant BASE_STEP]
## meaning before every step. Answers how many steps it moved, negative for
## undoing, so a caller can tell a refused jump from one that had nowhere to go.
func go_to_step(index: int) -> int:
    var canvas := _canvas()
    if canvas == null:
        return 0
    var moved := walk(canvas.document, canvas.tool_machine(), index)
    if moved != 0:
        refresh()
    return moved


## The walk [method go_to_step] does, over *document* with *machine* the tool
## machine on its canvas. Static so a suite walks a document of its own.
##
## Through `SaDocument.undo` and `redo` rather than through `UndoRedo` itself,
## which is the door the Edit menu and the shortcut router use: it is the one
## that marks the document modified, and a docker that moved the stack without
## it would leave a file Sara thinks is saved.
##
## **An open liquify or transform session is closed first**, which is what the
## chord and the Edit menu do. Otherwise a press on the row the stack stands on
## would do nothing while a push stands on the canvas, and a press on any row
## above it would step the history under the session and leave the session
## drawing from a picture no longer there.
static func walk(document: SaDocument, machine: ToolMachine, index: int) -> int:
    if document == null:
        return 0
    if machine != null:
        machine.close_session()
    var undo_redo := document.undo_redo
    var moved := 0
    # A bound rather than a while: a stack that refuses to move would otherwise
    # spin here, and `undo` answering false is the only signal that it did.
    for _step in maxi(undo_redo.get_history_count(), 1) + 1:
        # `get_current_action` is the step already done, -1 when none is,
        # which is BASE_STEP by construction.
        var at := undo_redo.get_current_action()
        if at == index:
            break
        if at > index:
            if not document.undo():
                break
            moved -= 1
        else:
            if not document.redo():
                break
            moved += 1
    return moved


## One button per step, oldest first, under a row for the state before any of
## them. Rebuilt whole for the reason the preset trail gives: a stack this size
## is nothing to build, and the alternative is bookkeeping that goes wrong the
## first time a step is dropped for the memory budget.
func _rebuild(named: Array[String], at: int) -> void:
    if rows == null:
        return
    for child in rows.get_children():
        if child != empty_label:
            # Removed as well as freed, the trap `history_docker.gd` records:
            # `queue_free` alone leaves the node a child until the next frame,
            # and a docker built outside the tree never gets one.
            rows.remove_child(child)
            child.queue_free()
    empty_label.visible = named.is_empty()
    _show_after = Engine.get_process_frames()
    _row_to_show = _add_row(tr("Opened"), BASE_STEP, at)
    for index in named.size():
        var button := _add_row(named[index], index, at)
        if index == at:
            _row_to_show = button


## Brings the row the stack is standing on into the scroll's view, and answers
## whether it did.
##
## A list that only grew downwards opened scrolled to Opened, its first row, so
## after thirty steps the step a painter was on sat below the fold and the
## sittings found it only by scrolling. Called from `_process` a frame after the
## rebuild or the show, once the list is laid out, and public so a suite that
## lays the list out by hand can ask for it inside one frame. Once per rebuild,
## so a painter who scrolls up to an older step is left there.
func show_current_row() -> bool:
    if _row_to_show == null or scroll == null:
        return false
    if not is_instance_valid(_row_to_show) or not _row_to_show.is_inside_tree():
        return false
    scroll.ensure_control_visible(_row_to_show)
    _row_to_show = null
    return true


## One row, and the button it is, so the rebuild can keep the current one.
func _add_row(text: String, index: int, at: int) -> Button:
    var button := SaMake.button(rows, "Step_%d" % (index + 1), text)
    button.clip_text = true
    button.alignment = HORIZONTAL_ALIGNMENT_LEFT
    button.custom_minimum_size = Vector2(0, SaUI.px(SaUI.BASE_BTN_H))
    # The accent fill for where the stack is standing, dimmed for a step that
    # has been undone and is waiting to be redone. Two states rather than three,
    # because "done and behind you" is the ordinary case and needs no marking.
    # The fill is the box a toggle that is on draws, in every state of the row,
    # so it reads as on under the pointer as well, rather than the row's own
    # pressed look, which against Sara's dark panels is a shade or two off the
    # rows around it and easy to miss.
    if index == at:
        for state: String in ["normal", "hover", "pressed", "focus"]:
            button.add_theme_stylebox_override(state, SaTheme.make_toggle_style("pressed"))
    button.modulate.a = 1.0 if index <= at else 0.45
    button.tooltip_text = (
        tr("Undo everything and start again from the opened file.")
        if index == BASE_STEP
        else tr("Go to the state just after %s.") % text
    )
    button.pressed.connect(_on_row_pressed.bind(index))
    return button


func _on_row_pressed(index: int) -> void:
    go_to_step(index)


func _document() -> SaDocument:
    var canvas := _canvas()
    return canvas.document if canvas != null else null


func _undo_redo() -> UndoRedo:
    var document := _document()
    return document.undo_redo if document != null else null


## The canvas this docker is over, the front document's, found the way the base
## module's histogram finds it rather than injected by `Main`'s boot, so the
## history shown changes as soon as another document comes forward. Its tool
## machine is the one a row press asks to close a session.
func _canvas() -> SaCanvas:
    return SaCanvasView.front_canvas() if is_inside_tree() else null


## What the docker is showing, for the capture harness: the rows in the order
## they are drawn, which one is marked, and how many steps the stack holds.
##
## Static and taking the root, the shape `ReferenceDocker.capture_state` uses, so
## `harness/report/sa_state_report.gd` needs one line rather than a lookup of its own. A
## picture of this docker is a column of words, and which row is down is a
## pressed state a screenshot argues about.
static func capture_state(root: Window) -> Dictionary:
    var docker := root.find_child(SaDockerIds.UNDO, true, false) as UndoDocker
    if docker == null:
        return {"present": false}
    var named := docker.step_names()
    return {
        "present": true,
        "showing": docker.visible,
        "steps": named,
        "at": docker.current_step(),
        "count": named.size(),
        # What the buttons actually read, so the dump grades the rows rather
        # than the model behind them: the empty-state label is skipped and a
        # step with no name of its own arrives here as "Step N".
        "rows": docker.row_texts(),
        # The footer's words, and the empty string while it is hidden, so a
        # dump grades the count a painter reads without a picture and without
        # reading it off the history itself.
        "dropped": docker.dropped_line(),
    }


## The words on the rows, in the order they are drawn, the opening row first.
func row_texts() -> Array[String]:
    var texts: Array[String] = []
    if rows == null:
        return texts
    for child in rows.get_children():
        var button := child as Button
        if button != null:
            texts.append(button.text)
    return texts
