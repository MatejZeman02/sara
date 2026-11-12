## The Undo History docker: a window on the undo stack, with the step it is standing on marked
## and every row a way back to it.
##
## The docker is a Window, so it is built detached under a plain Node and its
## `_ready` never runs, which is what `test_tool_options_docker.gd` does and why.
## What it cannot reach that way is the easel, so every case here hands it a
## document rather than letting it find one.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

## The docker's `_init` builds real controls, and a document needs a device.
const REQUIRES_GPU := true

const CANVAS := Vector2i(64, 64)

var _host: Node = null
var _docker: UndoDocker = null
var _easel: SaEasel = null


func before_each() -> void:
    _easel = SaEasel.create_default(CANVAS)
    _host = Node.new()
    _docker = UndoDocker.new()
    _host.add_child(_docker)


func after_each() -> void:
    _host.free()
    _host = null
    _docker = null
    _easel.free()
    _easel = null


## Three named steps on the stack, committed the way any tool commits one.
func _three_steps() -> void:
    for name: String in ["Paint", "New Layer", "Merge Down"]:
        var undo_redo := _easel.document.undo_redo
        undo_redo.create_action(name)
        undo_redo.add_do_method(func() -> void: pass)
        undo_redo.add_undo_method(func() -> void: pass)
        undo_redo.commit_action()


## What the docker reads off a stack, which is the whole model behind the rows.
## `current_step` is `UndoRedo`'s own index, so the opening state is -1 by
## construction rather than by a translation this file would have to keep right.
func test_the_docker_reads_the_stack_it_is_over() -> void:
    _three_steps()
    var undo_redo := _easel.document.undo_redo
    assert_eq(undo_redo.get_history_count(), 3, "Three actions are on the stack")
    assert_eq(undo_redo.get_current_action(), 2, "and it is standing on the last of them")
    assert_eq(undo_redo.get_action_name(0), "Paint", "each under the name it was committed with")

    _easel.document.undo()
    assert_eq(undo_redo.get_current_action(), 1, "One undo steps back one row")
    _easel.document.undo()
    _easel.document.undo()
    assert_eq(undo_redo.get_current_action(), UndoDocker.BASE_STEP, "and undoing everything reaches the opening state")


## A step committed with no name of its own is numbered rather than blank,
## because a blank row a painter cannot tell from the blank row above it is
## worse than a numbered one.
func test_a_step_with_no_name_is_numbered() -> void:
    var undo_redo := _easel.document.undo_redo
    undo_redo.create_action("")
    undo_redo.add_do_method(func() -> void: pass)
    undo_redo.add_undo_method(func() -> void: pass)
    undo_redo.commit_action()
    assert_eq(undo_redo.get_action_name(0), "", "The stack itself holds no name")
    assert_eq(UndoDocker.UNNAMED % 1, "Step 1", "and the docker calls it by its place, counted from one")


## The rows are the steps, oldest first, under a row for the state before any of
## them. The order is the opposite of the Recent Presets docker beside it and is
## deliberate: a stack is a timeline, and a timeline reads downwards.
func test_the_rows_are_the_steps_oldest_first_under_an_opening_row() -> void:
    _three_steps()
    _docker._rebuild(["Paint", "New Layer", "Merge Down"] as Array[String], 2)
    assert_eq(
        _docker.row_texts(),
        ["Opened", "Paint", "New Layer", "Merge Down"] as Array[String],
        "The opening state leads, then the steps in the order they happened"
    )
    assert_false(_docker.empty_label.visible, "and the empty state is out of the way")


## An empty stack says so rather than showing one lonely row a painter cannot
## use, and the opening row is still there because it is where they already are.
func test_an_empty_stack_says_there_is_nothing_to_undo() -> void:
    _docker._rebuild([] as Array[String], UndoDocker.BASE_STEP)
    assert_true(_docker.empty_label.visible, "The empty state is shown")
    assert_eq(_docker.row_texts(), ["Opened"] as Array[String], "with the opening row under it and no steps")


## Which row is marked, and which are dimmed. The row the stack is standing on
## takes the accent fill, dimmed is a step that has been undone and is waiting
## to be redone, and a step already done and behind you needs no marking at all.
##
## The fill is the box a toggle that is on draws, in place of the row's own
## pressed look, which could not be told from the rows around it.
func test_the_row_the_stack_stands_on_takes_the_accent_and_the_undone_ones_are_dimmed() -> void:
    _docker._rebuild(["Paint", "New Layer", "Merge Down"] as Array[String], 1)
    var filled: Array[String] = []
    var dimmed: Array[String] = []
    var toggles := 0
    for child in _docker.rows.get_children():
        var button := child as Button
        if button == null:
            continue
        if button.toggle_mode:
            toggles += 1
        var box := button.get_theme_stylebox("normal") as StyleBoxFlat
        if button.has_theme_stylebox_override("normal") and box != null and box.bg_color == SaTheme.palette.toggle_on:
            filled.append(button.text)
        if button.modulate.a < 1.0:
            dimmed.append(button.text)
    assert_eq(filled, ["New Layer"] as Array[String], "One row is filled with the accent, the one the stack is standing on")
    assert_eq(toggles, 0, "and no row is a toggle any more, so none of them reads as pressed")
    assert_eq(dimmed, ["Merge Down"] as Array[String], "and only the step waiting to be redone is dimmed")


## The docker opens inside a 1920 by 1080 window, beside Recent
## Presets. It was placed at (2, 1000) and no shipped layout has a section for
## it, so a first tick opened a docker 340 tall 80 units from the foot of the
## window, its title alone on screen.
func test_a_fresh_profile_opens_the_docker_inside_the_window() -> void:
    var own := Rect2i(_docker.position, _docker.size)
    assert_eq(
        _docker.position, Vector2i(1200, 680), "It opens beside Recent Presets, which the shipped layout puts at (900, 680)"
    )
    assert_true(
        Rect2i(Vector2i(), Vector2i(1920, 1080)).encloses(own), "and its whole frame is inside 1920 by 1080: %s" % str(own)
    )


## After thirty steps the row the stack is standing on is in
## the scroll's view. The list grew downwards and stayed scrolled to Opened, so
## the current step was out of sight.
##
## A suite runs inside one frame and the docker is a window kept out of the
## tree, so its scroll is lent to a viewport that is in it and laid out by hand,
## outside in, the way `test_a_groups_name_keeps_its_ellipsis_when_the_list_scrolls.gd`
## lays out the Layers list.
func test_after_thirty_steps_the_current_row_is_in_view() -> void:
    var undo_redo := _easel.document.undo_redo
    for index in 30:
        undo_redo.create_action("Stroke %d" % (index + 1))
        undo_redo.add_do_method(func() -> void: pass)
        undo_redo.add_undo_method(func() -> void: pass)
        undo_redo.commit_action()
    var named: Array[String] = []
    for index in undo_redo.get_history_count():
        named.append(undo_redo.get_action_name(index))
    var at := undo_redo.get_current_action()
    assert_eq(at, 29, "The stack stands on its thirtieth step")

    var scroll := _docker.scroll
    scroll.get_parent().remove_child(scroll)
    var viewport := SubViewport.new()
    viewport.size = UndoDocker.DEFAULT_SIZE
    EventBus.add_child(viewport)
    viewport.add_child(scroll)
    scroll.size = Vector2(UndoDocker.DEFAULT_SIZE.x, UndoDocker.DEFAULT_SIZE.y - 60)

    _docker._rebuild(named, at)
    var current := _docker.rows.get_child(_docker.rows.get_child_count() - 1) as Button
    assert_eq(current.text, "Stroke 30", "The last row is the step the stack stands on")
    _sort(viewport)
    assert_true(
        _docker.rows.size.y > scroll.size.y, "and thirty rows are taller than the list, so the list has to scroll to show it"
    )
    assert_false(
        scroll.get_global_rect().encloses(current.get_global_rect()),
        "Laid out, the list starts at Opened with the step below the fold"
    )

    assert_true(_docker.show_current_row(), "The scroll is brought to the current row")
    _sort(viewport)
    assert_true(
        scroll.get_global_rect().encloses(current.get_global_rect()),
        (
            "and the row is inside the scroll's visible area: %s in %s"
            % [str(current.get_global_rect()), str(scroll.get_global_rect())]
        )
    )
    assert_false(_docker.show_current_row(), "A second call has nothing left to show")

    viewport.free()


## Sorts every container under *node*, outside in, so the rectangles below it
## are the ones the running app would draw. A test cannot await a frame.
##
## Each container is asked its minimum size first. A `ScrollContainer` works out
## its scroll range in that question, which in the docker the margin around it
## asks as it sorts, and a scroll lent to a bare viewport is asked by nobody, so
## its range stayed at nothing and the scroll to the row was clamped to the top.
func _sort(node: Node) -> void:
    for child: Node in node.get_children():
        if child is Container:
            (child as Container).get_combined_minimum_size()
            (child as Container).notification(Container.NOTIFICATION_SORT_CHILDREN)
        _sort(child)
