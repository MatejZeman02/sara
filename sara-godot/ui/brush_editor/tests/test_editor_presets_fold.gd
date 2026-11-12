## The Brush Presets fold at the top of the Brush Editor's page list: the
## chrome it builds, what a rebuild leaves alone, and the seam that keeps the
## picking out of the list and out of the window.
##
## **Mostly detached, for the reason the F5 suite gives.**
## Adding a `Window` to the tree in a headless run hangs, so the list is
## built alone wherever the claim allows it. The two window assertions build the
## window and never show it, which is what `test_brush_editor_window.gd` does.
##
## What is not here is the picture: whether the second preset's values reach the
## pages is the scenario's claim, because it needs a store with two presets in
## it, a bar to apply through and a painting behind the dialog.
extends "res://tests/test_framework.gd"

## The window builds a scratchpad with a viewport and a canvas in it, and the
## chooser renders thumbnails. The list on its own needs neither, but a suite
## runs under one flag.
const REQUIRES_GPU := true


func _list() -> SaBrushEditorPageList:
    return SaBrushEditorPageList.new()


## The request is for "an expandable menu", so the two things it has to be are a
## header a painter can press and a box that is not showing until they do.
func test_the_fold_is_built_shut_with_the_title_the_note_names() -> void:
    var list := _list()
    assert_not_null(list.presets_header, "The list carries a header")
    assert_not_null(list.presets_box, "and a box under it for the window to fill")
    assert_false(list.presets_open, "shut when it is built")
    assert_false(list.presets_box.visible, "so the box is not on screen")
    assert_eq(list.presets_header.text, SaBrushEditorPageList.PRESETS_TITLE, "and the header reads the note's own words")
    assert_eq(list.presets_header.icon, SaUI.get_icon(SaBrushEditorPageList.FOLDED_ARROW), "after the folded arrow, an icon")
    assert_eq(SaBrushEditorPageList.PRESETS_TITLE, "Brush Presets", "which are Brush Presets")
    list.free()


## A fold that took a fixed slice of a fixed column would leave the rows under it
## nowhere to go: at 200 with the rows as this list's own children, five of the
## brush's eleven pages would be off the bottom of the dialog with nothing to
## reach them by. The box is a column of its own left of the rows and takes the
## height, so it never grows into the rows because it is not above them.
func test_both_halves_of_the_column_scroll_rather_than_clip() -> void:
    var list := _list()
    assert_true(list.presets_box is ScrollContainer, "The library scrolls inside its own room")
    assert_eq(list.presets_box.get_parent(), list.presets_column, "in a column of its own")
    assert_true(list.presets_column.get_parent() == null, "which is not above the rows, it is the window's to place beside them")
    assert_eq(list.presets_box.size_flags_vertical, Control.SIZE_EXPAND_FILL, "and takes the column's height")
    assert_not_null(list.rows_box, "The rows have a box of their own")
    assert_true(list.rows_box.get_parent() is ScrollContainer, "inside a scroll")
    assert_eq(list.rows_box.get_parent().size_flags_vertical, Control.SIZE_EXPAND_FILL, "which takes what is left")
    list.free()


## The header is the affordance, so pressing it has to move the state and say so
## once, and restoring a remembered state has to move it and say nothing.
func test_folding_announces_and_restoring_does_not() -> void:
    var list := _list()
    var heard: Array[bool] = []
    list.presets_folded.connect(func(open: bool) -> void: heard.append(open))

    list.fold_presets(true)
    assert_true(list.presets_open, "Opening it opens it")
    assert_true(list.presets_box.visible, "and the box comes on screen")
    assert_eq(list.presets_header.icon, SaUI.get_icon(SaBrushEditorPageList.OPEN_ARROW), "arrow down")
    assert_eq(heard, [true] as Array[bool], "announced once")

    list.fold_presets(false)
    assert_false(list.presets_box.visible, "Shutting it takes the box away")
    assert_eq(heard, [true, false] as Array[bool], "and announces that too")

    # What `bind_tool` does with the profile's remembered state. A profile that
    # announced itself back would be a write per open of the editor.
    list.fold_presets(true, false)
    assert_true(list.presets_open, "A restored state still moves the fold")
    assert_eq(heard.size(), 2, "and tells nobody")
    list.free()


## The one thing a rebuild must not do. If `build` freed every child, the fold
## being a child, a second `bind_tool` would have emptied the box the
## window put the chooser in and left a header over nothing.
func test_a_rebuild_keeps_the_fold_and_replaces_only_the_rows() -> void:
    var list := _list()
    var marker := Control.new()
    marker.name = "PretendChooser"
    list.presets_box.add_child(marker)

    list.build([{"title": "Size", "dynamic": true, "switch": true, "on": true}, {"title": "General"}])
    assert_eq(list.page_count(), 2, "Two pages")
    list.build([{"title": "General"}])
    assert_eq(list.page_count(), 1, "and a rebuild leaves one")

    assert_not_null(list.presets_header, "The header survived the rebuild")
    assert_eq(list._rows[0]["row"].get_parent(), list.rows_box, "and the row went into the rows' own box")
    assert_true(list.presets_box.get_child_count() == 1, "and what the window put in the box is still in it")
    assert_eq(list.presets_box.get_child(0).name, "PretendChooser", "the same node rather than a fresh one")
    list.free()


## `{"brush_editor": {"presets": {"fold": true, "pick": "Inker"}}}`. The list
## folds and answers the name, and applying it is somebody else's job, which is
## the whole reason the step is split this way: a list of rows holds no store.
func test_the_capture_step_folds_here_and_answers_the_pick() -> void:
    var list := _list()
    assert_eq(list.capture_presets({"fold": true, "pick": "Inker"}), "Inker", "The pick comes back")
    assert_true(list.presets_open, "and the fold was applied here")

    assert_eq(list.capture_presets({"fold": false}), "", "A step naming no pick answers nothing")
    assert_false(list.presets_open, "and shuts it")
    assert_eq(list.capture_presets({}), "", "An empty step changes nothing and answers nothing")
    assert_false(list.presets_open, "the fold is where it was")
    list.free()


## The dump's half. A shot of a shut fold is a picture of nothing, so the report
## is what says the section exists, whether it is open and whether the window
## has put anything in it.
func test_the_report_says_open_filled_and_what_the_header_reads() -> void:
    var list := _list()
    var shut: Dictionary = list.presets_report()
    assert_false(bool(shut["open"]), "Shut")
    assert_false(bool(shut["filled"]), "and empty until a host fills it")
    assert_eq(String(shut["arrow"]), SaBrushEditorPageList.FOLDED_ARROW, "with the folded arrow on the header")

    var marker := Control.new()
    list.presets_box.add_child(marker)
    list.fold_presets(true)
    var open: Dictionary = list.presets_report()
    assert_true(bool(open["open"]), "Open")
    assert_true(bool(open["filled"]), "and filled")
    assert_eq(String(open["arrow"]), SaBrushEditorPageList.OPEN_ARROW, "with the open arrow")
    list.free()


## The profile key. Shut by default, because a painter who never works from
## presets should not lose the top of the page list to a grid.
func test_the_state_is_remembered_per_profile() -> void:
    var was: bool = SaSettings.brush_editor_presets_open
    SaSettings.brush_editor_presets_open = true
    assert_true(SaSettings.brush_editor_presets_open, "The profile holds it")
    SaSettings.load_settings()
    assert_true(SaSettings.brush_editor_presets_open, "and reading the profile back gives it")
    SaSettings.brush_editor_presets_open = was

    var fresh := SaSettingsValues.new()
    assert_false(fresh.brush_editor_presets_open, "A profile that never saw the key opens the fold shut")
    assert_true(SaSettingsKeys.KEYS.has("brush_editor_presets_open"), "and the key is declared, so it is written and read back")
    fresh.free()


## The window fills the box with the same control the Brush Presets docker
## hosts, rather than the list growing a chooser of its own.
func test_the_window_puts_the_dockers_own_chooser_in_the_fold() -> void:
    var window := SaBrushEditorWindow.new()
    assert_not_null(window.presets_chooser, "The window built a chooser")
    assert_eq(window.presets_chooser.get_parent(), window.page_list.presets_box, "and put it in the list's box")
    assert_true(window.presets_chooser is SaBrushPresetsChooser, "It is the docker's chooser class, not a second grid")
    window.free()


## The seam. A cell picked in the editor is announced rather than applied,
## because writing the settings resource the whole application is holding is the
## bar's job and the window must not know a bar exists.
func test_a_pick_is_announced_rather_than_applied() -> void:
    var window := SaBrushEditorWindow.new()
    var heard: Array[String] = []
    window.preset_chosen.connect(func(stored: String) -> void: heard.append(stored))
    window.presets_chooser.preset_chosen.emit("Inker")
    assert_eq(heard, ["Inker"] as Array[String], "The chooser's cell reaches the window's signal unchanged")
    window.free()
